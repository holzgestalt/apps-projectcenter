/*
 PCDeploymentEditor.m

 The Deployment tab of the Xcode project editor: the platforms that
 Archive builds shippable applications for, and the settings of each.

 This file is part of GNUstep ProjectCenter.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation; either version 2 of the License, or
 (at your option) any later version.
 */

#import "PCDeploymentEditor.h"
#import "PCDeployment.h"

#import <ProjectCenter/PCDefines.h>
#import <ProjectCenter/PCProject.h>
#import <ProjectCenter/PCProjectBuilder.h>
#import <ProjectCenter/PCProjectWindow.h>

/* The form's document view, filled from the top. */
@interface PCDeploymentForm : NSView
@end

@implementation PCDeploymentForm
- (BOOL)isFlipped
{
  return YES;
}
@end

static const CGFloat LabelWidth = 150;
static const CGFloat Margin = 20;

@implementation PCDeploymentEditor

- (void)awakeFromNib
{
  [addButton removeAllItems];
  [addButton addItemWithTitle:@"+"];
  for (NSDictionary *kind in [PCDeployment kinds])
  {
    [addButton addItemWithTitle:[NSString stringWithFormat:@"%@ (%@)", [kind objectForKey:@"Title"],
                                 [kind objectForKey:@"Summary"]]];
    [[addButton lastItem] setRepresentedObject:[kind objectForKey:@"Kind"]];
  }
  form = [[PCDeploymentForm alloc] initWithFrame:NSMakeRect(0, 0, [formScroll contentSize].width, 100)];
  [form setAutoresizingMask:NSViewWidthSizable];
  [formScroll setDocumentView:form];
  [[formScroll contentView] setPostsFrameChangedNotifications:YES];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(_sizeForm)
                                               name:NSViewFrameDidChangeNotification
                                             object:[formScroll contentView]];
  controls = [[NSMutableDictionary alloc] init];
  deployments = [[NSMutableArray alloc] init];
  [platformsTable setTarget:self];
  [self _showSelection];
}

- (void)dealloc
{
  [NSObject cancelPreviousPerformRequestsWithTarget:self];
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [platformsTable setDataSource:nil];
  [platformsTable setDelegate:nil];
  for (id control in [controls allValues])
  {
    if ([control isKindOfClass:[NSTextField class]]) [control setDelegate:nil];
  }
  [controls release];
  [deployments release];
  [fields release];
  [form release];
  [super dealloc];
}

- (void)setProject:(PCProject *)aProject
{
  project = aProject;
}

- (NSString *)_projectPath
{
  return [[project projectDict] objectForKey:@"XCODE_PROJECT_PATH"];
}

- (NSArray *)deployments { return deployments; }
- (NSDictionary *)controls { return controls; }

- (NSInteger)selectedIndex
{
  return [platformsTable selectedRow];
}

- (void)selectIndex:(NSInteger)index
{
  if (index >= 0 && index < (NSInteger)[deployments count])
  {
    [platformsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
  }
  else
  {
    [platformsTable deselectAll:self];
  }
  [self _showSelection];
}

- (void)reload
{
  NSInteger selected = [self selectedIndex];

  [deployments removeAllObjects];
  for (NSDictionary *deployment in [PCDeployment deploymentsOfProjectAtPath:[self _projectPath]])
  {
    [deployments addObject:[NSMutableDictionary dictionaryWithDictionary:deployment]];
  }
  [platformsTable reloadData];
  if (selected < 0 && [deployments count]) selected = 0;
  [self selectIndex:MIN(selected, (NSInteger)[deployments count] - 1)];
}

- (BOOL)_save
{
  NSString *error = nil;

  if ([self _projectPath] == nil) return NO;
  if (![PCDeployment setDeployments:deployments ofProjectAtPath:[self _projectPath] error:&error])
  {
    NSRunAlertPanel(@"Deployment", @"%@", @"OK", nil, nil, error);
    return NO;
  }
  return YES;
}

// --- Platforms

- (void)addPlatformOfKind:(NSString *)kind
{
  NSDictionary *deployment = [PCDeployment deploymentOfKind:kind existing:deployments
                                                 forProject:[project projectDict]];

  if (deployment == nil) return;
  [deployments addObject:[NSMutableDictionary dictionaryWithDictionary:deployment]];
  [self _save];
  [platformsTable reloadData];
  [self selectIndex:[deployments count] - 1];
}

- (void)removePlatformAtIndex:(NSUInteger)index
{
  if (index >= [deployments count]) return;
  [deployments removeObjectAtIndex:index];
  [self _save];
  [platformsTable reloadData];
  [self selectIndex:MIN((NSInteger)index, (NSInteger)[deployments count] - 1)];
}

- (void)addPlatform:(id)sender
{
  NSString *kind = [[sender selectedItem] representedObject];

  if (kind) [self addPlatformOfKind:kind];
}

- (void)removePlatform:(id)sender
{
  if ([self selectedIndex] >= 0) [self removePlatformAtIndex:[self selectedIndex]];
}

- (void)archive:(id)sender
{
  PCProjectBuilder *builder = [project projectBuilder];

  [[project projectWindow] showProjectBuild:self];
  [builder performStartArchive];
}

- (BOOL)setValue:(NSString *)value forSetting:(NSString *)key ofDeploymentAtIndex:(NSUInteger)index
{
  NSMutableDictionary *deployment = index < [deployments count] ? [deployments objectAtIndex:index] : nil;
  NSString            *old;

  if (deployment == nil) return NO;
  if ([key isEqual:@"Kind"])
  {
    NSDictionary *changed = [PCDeployment deployment:deployment changedToKind:value
                                            existing:deployments forProject:[project projectDict]];

    if (changed == nil) return NO;
    if (changed == deployment) return YES;
    [deployments replaceObjectAtIndex:index withObject:[NSMutableDictionary dictionaryWithDictionary:changed]];
    if (![self _save]) return NO;
    [platformsTable reloadData];
    /* The fields depend on the kind. The form is made again after the
     * popup that changed it has finished, as that removes the popup. */
    if ((NSInteger)index == [self selectedIndex])
    {
      [self performSelector:@selector(_showSelection) withObject:nil afterDelay:0];
    }
    return YES;
  }
  value = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  old = [deployment objectForKey:key];
  if ([(old ? old : @"") isEqual:(value ? value : @"")]) return YES;
  /* A value that is the default is left out, so it follows the project. */
  if ([value length] && ![value isEqual:[PCDeployment defaultValueForKey:key ofDeployment:deployment
                                                                 project:[project projectDict]]])
  {
    [deployment setObject:value forKey:key];
  }
  else if ([key isEqual:@"Enabled"] || [key isEqual:@"Kind"] || [key isEqual:@"Name"])
  {
    /* Always written, so the file says what it is. */
    if ([value length]) [deployment setObject:value forKey:key];
  }
  else
  {
    [deployment removeObjectForKey:key];
  }
  if (![self _save]) return NO;
  [platformsTable reloadData];
  if ((NSInteger)index == [self selectedIndex]) [self _updateForm];
  return YES;
}

// --- Table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)table
{
  return [deployments count];
}

- (id)tableView:(NSTableView *)table objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
  NSDictionary *deployment = [deployments objectAtIndex:row];

  if ([[column identifier] isEqual:@"Enabled"])
  {
    return [NSNumber numberWithBool:[[PCDeployment valueForKey:@"Enabled" ofDeployment:deployment
                                                       project:[project projectDict]] boolValue]];
  }
  return [PCDeployment valueForKey:@"Name" ofDeployment:deployment project:[project projectDict]];
}

- (void)tableView:(NSTableView *)table
   setObjectValue:(id)value
   forTableColumn:(NSTableColumn *)column
              row:(NSInteger)row
{
  if ([[column identifier] isEqual:@"Enabled"])
  {
    [self setValue:[value boolValue] ? @"YES" : @"NO" forSetting:@"Enabled" ofDeploymentAtIndex:row];
  }
}

- (BOOL)tableView:(NSTableView *)table shouldEditTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
  return [[column identifier] isEqual:@"Enabled"];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
  [self _showSelection];
}

// --- The form

- (NSTextField *)_labelWithTitle:(NSString *)title frame:(NSRect)frame
{
  NSTextField *label = [[[NSTextField alloc] initWithFrame:frame] autorelease];

  [label setStringValue:title];
  [label setEditable:NO];
  [label setSelectable:NO];
  [label setBezeled:NO];
  [label setBordered:NO];
  [label setDrawsBackground:NO];
  return label;
}

- (void)_showSelection
{
  NSInteger    index = [self selectedIndex];
  NSDictionary *deployment = index >= 0 && index < (NSInteger)[deployments count]
  ? [deployments objectAtIndex:index] : nil;
  CGFloat      width = [formScroll contentSize].width;
  CGFloat      y = 12;
  BOOL         first = YES;

  for (id control in [controls allValues])
  {
    if ([control isKindOfClass:[NSTextField class]]) [control setDelegate:nil];
  }
  [controls removeAllObjects];
  while ([[form subviews] count])
  {
    [[[form subviews] lastObject] removeFromSuperview];
  }
  ASSIGN(fields, deployment ? [PCDeployment fieldsForKind:[deployment objectForKey:@"Kind"]] : nil);
  [removeButton setEnabled:(deployment != nil)];

  if (deployment == nil)
  {
    NSTextField *note = [self _labelWithTitle:([deployments count]
                                               ? @"Select a platform to see its settings."
                                               : @"Add a platform with + for each system Archive builds "
                                                 @"the application for.")
                                        frame:NSMakeRect(Margin, y, width - 2 * Margin, 34)];

    [note setAutoresizingMask:NSViewWidthSizable];
    [form addSubview:note];
    y += 40;
  }
  for (NSDictionary *field in fields)
  {
    NSString *section = [field objectForKey:@"Section"];
    NSString *type = [field objectForKey:@"Type"];
    NSString *key = [field objectForKey:@"Key"];
    NSRect   controlFrame = NSMakeRect(Margin + LabelWidth + 8, y, width - LabelWidth - 2 * Margin - 8, 22);
    id       control;

    if (section)
    {
      NSTextField *title;
      NSBox       *separator;

      y += first ? 0 : 10;
      first = NO;
      title = [self _labelWithTitle:section frame:NSMakeRect(Margin, y, width - 2 * Margin, 17)];
      [title setFont:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]];
      [title setAutoresizingMask:NSViewWidthSizable];
      [form addSubview:title];
      separator = [[[NSBox alloc] initWithFrame:NSMakeRect(Margin, y + 20, width - 2 * Margin, 1)] autorelease];
      [separator setBoxType:NSBoxSeparator];
      [separator setAutoresizingMask:NSViewWidthSizable];
      [form addSubview:separator];
      y += 30;
      continue;
    }
    if ([type isEqual:@"Choice"])
    {
      control = [[[NSPopUpButton alloc] initWithFrame:NSInsetRect(controlFrame, -2, -2) pullsDown:NO] autorelease];
      for (NSArray *choice in [field objectForKey:@"Choices"])
      {
        [control addItemWithTitle:[choice objectAtIndex:0]];
        [[control lastItem] setRepresentedObject:[choice objectAtIndex:1]];
      }
      [control setAction:@selector(_choiceChanged:)];
    }
    else if ([type isEqual:@"Check"])
    {
      control = [[[NSButton alloc] initWithFrame:controlFrame] autorelease];
      [control setButtonType:NSSwitchButton];
      [control setTitle:@""];
      [control setAction:@selector(_checkChanged:)];
    }
    else
    {
      control = [[[NSTextField alloc] initWithFrame:controlFrame] autorelease];
      [(NSTextField *)control setDelegate:(id)self];
      [control setAction:@selector(_textChanged:)];
    }
    [control setTarget:self];
    [control setAutoresizingMask:NSViewWidthSizable];
    [control setToolTip:[field objectForKey:@"Help"]];
    [form addSubview:control];
    [controls setObject:control forKey:key];

    control = [self _labelWithTitle:[field objectForKey:@"Title"]
                              frame:NSMakeRect(Margin, y + 3, LabelWidth, 17)];
    [control setAlignment:NSRightTextAlignment];
    [control setToolTip:[field objectForKey:@"Help"]];
    [form addSubview:control];
    y += 30;
  }
  [form setFrameSize:NSMakeSize(width, MAX(y + 12, [formScroll contentSize].height))];
  [[formScroll contentView] scrollToPoint:NSZeroPoint];
  [formScroll reflectScrolledClipView:[formScroll contentView]];
  [self _updateForm];
}

/* The values, defaults and status of the selected platform, in the controls
 * that are there; a field being edited keeps what is typed. */
- (void)_updateForm
{
  NSInteger    index = [self selectedIndex];
  NSDictionary *deployment = index >= 0 && index < (NSInteger)[deployments count]
  ? [deployments objectAtIndex:index] : nil;
  NSDictionary *projectDict = [project projectDict];
  NSSet        *unused = [PCDeployment unusedKeysOfDeployment:deployment];
  NSArray      *problems;
  NSUInteger   enabled = 0;

  for (NSString *key in controls)
  {
    id       control = [controls objectForKey:key];
    NSString *value = [PCDeployment valueForKey:key ofDeployment:deployment project:projectDict];

    if ([control isKindOfClass:[NSPopUpButton class]])
    {
      NSInteger item = [control indexOfItemWithRepresentedObject:value];

      [control selectItemAtIndex:item >= 0 ? item : 0];
    }
    else if ([control isKindOfClass:[NSTextField class]])
    {
      if ([control currentEditor] == nil)
      {
        [control setStringValue:[[deployment objectForKey:key] isKindOfClass:[NSString class]]
         ? [deployment objectForKey:key] : @""];
      }
      [[control cell] setPlaceholderString:[PCDeployment defaultValueForKey:key ofDeployment:deployment
                                                                   project:projectDict]];
    }
    else
    {
      [control setState:[value boolValue] ? NSOnState : NSOffState];
    }
    [control setEnabled:![unused containsObject:key]];
  }

  for (NSDictionary *other in deployments)
  {
    if ([[PCDeployment valueForKey:@"Enabled" ofDeployment:other project:projectDict] boolValue]) enabled++;
  }
  [archiveButton setEnabled:(enabled > 0)];
  if (deployment == nil)
  {
    [statusField setStringValue:enabled ? [NSString stringWithFormat:@"Archive builds %lu platform%@.",
                                           (unsigned long)enabled, enabled == 1 ? @"" : @"s"] : @""];
    [statusField setToolTip:nil];
    return;
  }
  problems = [PCDeployment problemsWithDeployment:deployment project:projectDict];
  if ([problems count] == 0)
  {
    [statusField setStringValue:[NSString stringWithFormat:@"Ready: Archive makes %@.",
                                 [PCDeployment fileNameOfDeployment:deployment project:projectDict]]];
    [statusField setTextColor:[NSColor disabledControlTextColor]];
    [statusField setToolTip:nil];
  }
  else
  {
    [statusField setStringValue:[problems objectAtIndex:0]];
    [statusField setTextColor:[NSColor redColor]];
    [statusField setToolTip:[problems componentsJoinedByString:@"\n"]];
  }
}

- (void)_sizeForm
{
  CGFloat width = [formScroll contentSize].width;

  [form setFrameSize:NSMakeSize(width, MAX(NSHeight([form frame]), [formScroll contentSize].height))];
}

- (NSString *)_keyOfControl:(id)control
{
  for (NSString *key in controls)
  {
    if ([controls objectForKey:key] == control) return key;
  }
  return nil;
}

- (void)_textChanged:(id)sender
{
  NSString *key = [self _keyOfControl:sender];

  if (key && [self selectedIndex] >= 0)
  {
    [self setValue:[sender stringValue] forSetting:key ofDeploymentAtIndex:[self selectedIndex]];
  }
}

- (void)controlTextDidEndEditing:(NSNotification *)notification
{
  [self _textChanged:[notification object]];
}

- (void)_choiceChanged:(id)sender
{
  NSString *key = [self _keyOfControl:sender];

  if (key && [self selectedIndex] >= 0)
  {
    [self setValue:[[sender selectedItem] representedObject] forSetting:key
ofDeploymentAtIndex:[self selectedIndex]];
  }
}

- (void)_checkChanged:(id)sender
{
  NSString *key = [self _keyOfControl:sender];

  if (key && [self selectedIndex] >= 0)
  {
    [self setValue:[sender state] == NSOnState ? @"YES" : @"NO" forSetting:key
ofDeploymentAtIndex:[self selectedIndex]];
  }
}

@end
