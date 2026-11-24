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
#import "PCXcodeProject.h"

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
  /* Make Toolchain... is enabled while the builder is free. */
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(_builderChanged:)
                                               name:PCProjectBuilderDidChangeNotification
                                             object:nil];
  /* No project nor target yet: only the note. */
  [self _fillAddButton];
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
  [target release];
  [super dealloc];
}

- (void)setProject:(PCProject *)aProject
{
  project = aProject;
}

- (void)setOwner:(id)anOwner
{
  owner = anOwner;
}

- (NSString *)_projectPath
{
  return [[project projectDict] objectForKey:@"XCODE_PROJECT_PATH"];
}

- (NSDictionary *)target { return target; }
- (NSArray *)deployments { return deployments; }
- (NSDictionary *)controls { return controls; }
- (NSButton *)makeToolchainButton { return makeToolchainButton; }

- (void)_builderChanged:(NSNotification *)notification
{
  if ([[notification object] respondsToSelector:@selector(project)] && [[notification object] project] == project)
  {
    /* A toolchain just made becomes the default. */
    [self _updateForm];
  }
}

- (void)makeToolchain:(id)sender
{
  NSInteger index = [self selectedIndex];

  if (index < 0 || index >= (NSInteger)[deployments count]) return;
  [[project projectBuilder] performMakeToolchainForDeployment:[deployments objectAtIndex:index]];
  if ([[project projectBuilder] isMakingToolchain])
  {
    [[project projectWindow] showProjectBuild:self];
  }
}

- (BOOL)_isLinuxTarget
{
  return target && [[PCXcodeProject platformOfTarget:target] isEqual:@"Linux"];
}

- (void)setTarget:(NSDictionary *)aTarget
{
  BOOL same = [[aTarget objectForKey:@"Identifier"] isEqual:[target objectForKey:@"Identifier"]];

  ASSIGN(target, aTarget);
  [self reload];
  if (!same) [self selectIndex:[deployments count] ? 0 : -1];
}

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

/* The add menu: the distributions a Linux target doesn't have yet. */
- (void)_fillAddButton
{
  NSArray *present = [deployments valueForKey:@"Kind"];

  [addButton removeAllItems];
  [addButton addItemWithTitle:@"+"];
  for (NSString *kind in [PCDeployment kindsForPlatform:@"Linux"])
  {
    NSDictionary *entry = [PCDeployment kindNamed:kind];

    if ([present containsObject:kind]) continue;
    [addButton addItemWithTitle:[NSString stringWithFormat:@"%@ (%@)", [entry objectForKey:@"Title"],
                                 [entry objectForKey:@"Summary"]]];
    [[addButton lastItem] setRepresentedObject:kind];
  }
  [addButton setHidden:![self _isLinuxTarget]];
  [removeButton setHidden:![self _isLinuxTarget]];
  [addButton setEnabled:([addButton numberOfItems] > 1)];
}

- (void)reload
{
  NSInteger selected = [self selectedIndex];
  NSString  *selectedKind = selected >= 0 && selected < (NSInteger)[deployments count]
    ? [[deployments objectAtIndex:selected] objectForKey:@"Kind"] : nil;
  NSInteger index;

  [deployments removeAllObjects];
  for (NSDictionary *deployment in [PCDeployment deploymentsOfTarget:target])
  {
    [deployments addObject:[NSMutableDictionary dictionaryWithDictionary:deployment]];
  }
  [platformsTable reloadData];
  [self _fillAddButton];
  /* The same distribution stays selected; its form only takes the new
   * values, so a field being edited keeps its place. */
  index = selectedKind ? (NSInteger)[[deployments valueForKey:@"Kind"] indexOfObject:selectedKind] : NSNotFound;
  if (index != NSNotFound && index == selected)
  {
    [self _updateForm];
    return;
  }
  if (index == NSNotFound) index = MIN(MAX(selected, 0), (NSInteger)[deployments count] - 1);
  [self selectIndex:index];
}

/* After an edit: the project editor reads the project again, and gives the
 * target back with its new settings. Later, as an edit may come from a
 * control the form makes again. */
- (void)_projectChanged
{
  [NSObject cancelPreviousPerformRequestsWithTarget:owner selector:@selector(reload) object:nil];
  if ([owner respondsToSelector:@selector(reload)])
  {
    [owner performSelector:@selector(reload) withObject:nil afterDelay:0];
  }
}

- (BOOL)_succeeded:(BOOL)done error:(NSString *)error
{
  if (!done)
  {
    NSRunAlertPanel(@"Deployment", @"%@", @"OK", nil, nil, error ? error : @"The project could not be changed.");
  }
  [self _projectChanged];
  return done;
}

// --- Distributions

- (void)addPlatformOfKind:(NSString *)kind
{
  NSString *error = nil;
  BOOL     done = [PCDeployment addDistribution:kind toTarget:target projectAtPath:[self _projectPath] error:&error];

  if (done)
  {
    /* Shown at once; the project editor's reload confirms it. */
    [deployments addObject:[NSMutableDictionary dictionaryWithObjectsAndKeys:kind, @"Kind", @"YES", @"Enabled", nil]];
    [platformsTable reloadData];
    [self selectIndex:[deployments count] - 1];
  }
  [self _succeeded:done error:error];
}

- (void)removePlatformAtIndex:(NSUInteger)index
{
  NSString *error = nil;
  BOOL     done;

  if (index >= [deployments count]) return;
  done = [PCDeployment removeDistribution:[[deployments objectAtIndex:index] objectForKey:@"Kind"]
                               fromTarget:target projectAtPath:[self _projectPath] error:&error];
  if (done)
  {
    [deployments removeObjectAtIndex:index];
    [platformsTable reloadData];
    [self selectIndex:MIN((NSInteger)index, (NSInteger)[deployments count] - 1)];
  }
  [self _succeeded:done error:error];
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

- (BOOL)setValue:(NSString *)value forSetting:(NSString *)key ofDeploymentAtIndex:(NSUInteger)index
{
  NSMutableDictionary *deployment = index < [deployments count] ? [deployments objectAtIndex:index] : nil;
  NSString            *old;
  NSString            *error = nil;
  BOOL                done;

  if (deployment == nil || target == nil) return NO;
  if ([key isEqual:@"Kind"])
  {
    if ([value isEqual:[deployment objectForKey:@"Kind"]]) return YES;
    done = [PCDeployment changeDistribution:deployment toKind:value ofTarget:target
                              projectAtPath:[self _projectPath] error:&error];
    /* The reload finds another distribution in its place, and makes the
     * form again for its fields. */
    return [self _succeeded:done error:error];
  }
  value = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  old = [deployment objectForKey:key];
  if ([(old ? old : @"") isEqual:(value ? value : @"")]) return YES;
  /* A value that is the default is left out, so it follows the project. */
  if ([value length] && [value isEqual:[PCDeployment defaultValueForKey:key ofDeployment:deployment
                                                                project:[project projectDict]]])
  {
    value = nil;
  }
  done = [PCDeployment setValue:value forKey:key ofDeployment:deployment target:target
                  projectAtPath:[self _projectPath] error:&error];
  if (done)
  {
    if ([value length]) [deployment setObject:value forKey:key];
    else [deployment removeObjectForKey:key];
    /* Architectures belong to the target: every distribution has them. */
    if ([key isEqual:@"Architectures"])
    {
      for (NSMutableDictionary *other in deployments)
      {
        [other setObject:(value ? value : @"") forKey:key];
      }
    }
    [platformsTable reloadData];
    if ((NSInteger)index == [self selectedIndex]) [self _updateForm];
  }
  return [self _succeeded:done error:error];
}

// --- Table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)table
{
  return [deployments count];
}

- (id)tableView:(NSTableView *)table objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
  return [PCDeployment valueForKey:@"Name" ofDeployment:[deployments objectAtIndex:row]
                           project:[project projectDict]];
}

- (BOOL)tableView:(NSTableView *)table shouldEditTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
  return NO;
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
  makeToolchainButton = nil;
  while ([[form subviews] count])
  {
    [[[form subviews] lastObject] removeFromSuperview];
  }
  ASSIGN(fields, deployment ? [PCDeployment fieldsForKind:[deployment objectForKey:@"Kind"]] : nil);
  [removeButton setEnabled:(deployment != nil)];

  if (deployment == nil)
  {
    NSString    *text = (target == nil
                         ? @"Select a target to see its deployment. A Mac target has the architectures "
                           @"it is built for; a Linux target (SDKROOT = linux) the distributions it is "
                           @"packaged for."
                         : [self _isLinuxTarget]
                         ? ([deployments count] ? @"Select a distribution to see its settings."
                            : @"Add a distribution with + for each system Archive packages the application for.")
                         : @"This target is not built for macOS or Linux.");
    NSTextField *note = [self _labelWithTitle:text
                                        frame:NSMakeRect(Margin, y, width - 2 * Margin, 51)];

    [note setAutoresizingMask:NSViewWidthSizable];
    [form addSubview:note];
    y += 57;
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
      if ([key isEqual:@"Toolchain"])
      {
        /* Make Toolchain... right of the field. */
        NSRect buttonFrame = controlFrame;

        buttonFrame.size.width = 140;
        controlFrame.size.width -= NSWidth(buttonFrame) + 8;
        buttonFrame.origin.x = NSMaxX(controlFrame) + 8;
        makeToolchainButton = [[[NSButton alloc] initWithFrame:NSInsetRect(buttonFrame, 0, -3)] autorelease];
        [makeToolchainButton setButtonType:NSMomentaryPushInButton];
        [makeToolchainButton setBezelStyle:NSRoundedBezelStyle];
        [makeToolchainButton setTitle:@"Make Toolchain…"];
        [makeToolchainButton setTarget:self];
        [makeToolchainButton setAction:@selector(makeToolchain:)];
        [makeToolchainButton setAutoresizingMask:NSViewMinXMargin];
        [makeToolchainButton setToolTip:@"Makes a GNUstep cross toolchain for this platform in "
                             @"~/gnustep-toolchains (make-toolchain.sh): Debian's packages and GNUstep "
                             @"built for them, without Docker."];
        [form addSubview:makeToolchainButton];
      }
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
  if (makeToolchainButton)
  {
    PCProjectBuilder *builder = [project projectBuilder];

    /* Also while Build is Container: a platform whose Build is the default
     * builds with the toolchain once it is made. */
    [makeToolchainButton setEnabled:deployment != nil
     && [PCDeployment makeToolchainArgumentsForDeployment:deployment project:projectDict] != nil
     && ![builder isBuilding] && ![builder isCleaning]];
  }

	if (deployment == nil) {
		[statusField setStringValue:@""];
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
