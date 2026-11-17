/*
 PCNavigators.m

 Breakpoint and debug navigators for the project window's sidebar.

 This file is part of GNUstep ProjectCenter.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation; either version 2 of the License, or
 (at your option) any later version.
 */

#import "PCNavigators.h"

#import <ProjectCenter/PCProject.h>
#import <ProjectCenter/PCProjectEditor.h>
#import <ProjectCenter/PCProjectLauncher.h>
#import <ProjectCenter/PCProjectBuilder.h>
#import <ProjectCenter/PCProjectWindow.h>
#import <Protocols/CodeEditor.h>

/* GNUstep's programmatic tables retain cell-based mode by default. Register
 * view prototypes explicitly, just as its XIB loader does. */
#ifdef GNUSTEP
@interface NSTableView (PCNavigatorSupport)
- (void)_registerPrototypeViews:(NSArray *)views;
@end
#endif

@implementation PCNavigatorItem
+ (PCNavigatorItem *)itemWithTitle:(NSString *)aTitle icon:(NSImage *)anIcon info:(NSDictionary *)anInfo
{
  PCNavigatorItem *item = [[[self alloc] init] autorelease];
  item->title = [aTitle copy];
  item->icon = [anIcon retain];
  item->info = [anInfo retain];
  item->children = [NSMutableArray new];
  return item;
}
- (NSString *)title { return title; }
- (NSImage *)icon { return icon; }
- (NSDictionary *)info { return info; }
- (NSMutableArray *)children { return children; }
- (void)dealloc
{
  [title release]; [icon release]; [toolTip release];
  [info release]; [children release];
  [super dealloc];
}
@end

static NSTableCellView *NavigatorCell(void)
{
  NSTableCellView *cell = [[[NSTableCellView alloc] initWithFrame:NSMakeRect(0,0,230,24)] autorelease];
  NSImageView *image = [[[NSImageView alloc] initWithFrame:NSMakeRect(2,4,16,16)] autorelease];
  NSTextField *label = [[[NSTextField alloc] initWithFrame:NSMakeRect(24,0,204,24)] autorelease];

  [cell setIdentifier:@"NavigatorItem"];
  [label setEditable:NO]; [label setSelectable:NO];
  [label setBezeled:NO]; [label setBordered:NO]; [label setDrawsBackground:NO];
  [label setFont:[NSFont systemFontOfSize:12]];
  [[label cell] setLineBreakMode:NSLineBreakByTruncatingTail];
  [label setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [cell addSubview:image]; [cell addSubview:label];
  [cell setImageView:image]; [cell setTextField:label];
  [label bind:NSValueBinding toObject:cell withKeyPath:@"objectValue.title" options:nil];
  [image bind:NSValueBinding toObject:cell withKeyPath:@"objectValue.icon" options:nil];
  return cell;
}

static NSImage *SmallIcon(NSString *name)
{
  return [NSImage imageNamed:name];
}

// ============================================================================
// ==== PCNavigator
// ============================================================================

@implementation PCNavigator

- (id)initWithProject:(PCProject *)aProject
{
  if ((self = [super init]))
  {
    NSTableColumn *column;

    project = aProject;
    roots = [NSMutableArray new];
    view = [[NSView alloc] initWithFrame:NSMakeRect(0,0,240,400)];
    [view setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    scrollView = [[NSScrollView alloc] initWithFrame:[view bounds]];
    [scrollView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [scrollView setBorderType:NSNoBorder];
    [scrollView setHasVerticalScroller:YES];
    [scrollView setHasHorizontalScroller:NO];
    [scrollView setAutohidesScrollers:YES];
    outline = [[NSOutlineView alloc] initWithFrame:[[scrollView contentView] bounds]];
    column = [[NSTableColumn alloc] initWithIdentifier:@"Navigator"];
    [column setWidth:230];
    [column setMinWidth:80];
    [outline addTableColumn:column];
    [outline setOutlineTableColumn:column];
    [column release];
    [outline setHeaderView:nil];
    [outline setGridStyleMask:NSTableViewGridNone];
#ifdef GNUSTEP
    [outline _registerPrototypeViews:[NSArray arrayWithObject:NavigatorCell()]];
#endif
    [outline setRowHeight:24];
    [outline setIndentationPerLevel:14];
    [outline setAllowsEmptySelection:YES];
    [outline setColumnAutoresizingStyle:NSTableViewFirstColumnOnlyAutoresizingStyle];
    [outline setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [outline setDataSource:(id)self];
    [outline setDelegate:(id)self];
    [scrollView setDocumentView:outline];
    [view addSubview:scrollView];
  }
  return self;
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [outline setDelegate:nil];
  [outline setDataSource:nil];
  [outline release];
  [scrollView release];
  [view release];
  [roots release];
  [super dealloc];
}

- (NSView *)view { return view; }
- (NSOutlineView *)outlineView { return outline; }
- (NSArray *)rootItems { return roots; }
- (void)reloadItems { }
- (void)selectionDidChange:(PCNavigatorItem *)item { }

- (void)_reloadOutlineExpandingAll
{
  updatingSelection = YES;
  [outline reloadData];
  for (PCNavigatorItem *item in roots)
  {
    if ([item->children count])
    {
      [outline expandItem:item];
    }
  }
  updatingSelection = NO;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{
  NSInteger row = [outline selectedRow];

  if (updatingSelection)
  {
    return;
  }
  [self selectionDidChange:row >= 0 ? [outline itemAtRow:row] : nil];
}

- (NSInteger)outlineView:(NSOutlineView *)v numberOfChildrenOfItem:(id)item
{
  return item ? [((PCNavigatorItem *)item)->children count] : [roots count];
}

- (id)outlineView:(NSOutlineView *)v child:(NSInteger)index ofItem:(id)item
{
  return [(item ? ((PCNavigatorItem *)item)->children : roots) objectAtIndex:index];
}

- (BOOL)outlineView:(NSOutlineView *)v isItemExpandable:(id)item
{
  return [((PCNavigatorItem *)item)->children count] > 0;
}

- (id)outlineView:(NSOutlineView *)v objectValueForTableColumn:(NSTableColumn *)column byItem:(id)item
{
#ifdef GNUSTEP
  return ((PCNavigatorItem *)item)->title;
#else
  /* Cocoa sets the cell view's objectValue from this; its bindings need
   * the item. */
  return item;
#endif
}

- (NSView *)outlineView:(NSOutlineView *)v viewForTableColumn:(NSTableColumn *)column item:(id)item
{
  NSTableCellView *cell = NavigatorCell();
  [cell setObjectValue:item];
  [cell setToolTip:((PCNavigatorItem *)item)->toolTip];
  return cell;
}

@end

// ============================================================================
// ==== Breakpoints
// ============================================================================

@implementation PCBreakpointNavigator

- (id)initWithProject:(PCProject *)aProject
{
  if ((self = [super initWithProject:aProject]))
  {
    NSRect bounds = [view bounds];
    NSView *bar = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, NSWidth(bounds), 28)] autorelease];

    [scrollView setFrame:NSMakeRect(0, 28, NSWidth(bounds), NSHeight(bounds) - 28)];
    [bar setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];

    /* Like Xcode's navigator footer: add (with a choice) and remove. */
    addButton = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(4, 2, 44, 24) pullsDown:YES] autorelease];
    [addButton addItemWithTitle:@"+"];
    [addButton addItemWithTitle:@"Add Exception Breakpoint"];
    [addButton addItemWithTitle:@"Add Symbolic Breakpoint…"];
    [[addButton itemAtIndex:1] setTarget:self];
    [[addButton itemAtIndex:1] setAction:@selector(addExceptionBreakpoint:)];
    [[addButton itemAtIndex:2] setTarget:self];
    [[addButton itemAtIndex:2] setAction:@selector(addSymbolicBreakpoint:)];
    [addButton setToolTip:@"Add a breakpoint"];
    [addButton setAutoresizingMask:NSViewMaxXMargin | NSViewMaxYMargin];
    [bar addSubview:addButton];

    removeButton = [[[NSButton alloc] initWithFrame:NSMakeRect(52, 2, 30, 24)] autorelease];
    [removeButton setTitle:@"−"];
    [removeButton setToolTip:@"Delete the selected breakpoint"];
    [removeButton setTarget:self];
    [removeButton setAction:@selector(removeSelectedBreakpoint:)];
    [removeButton setEnabled:NO];
    [removeButton setAutoresizingMask:NSViewMaxXMargin | NSViewMaxYMargin];
    [bar addSubview:removeButton];
    [view addSubview:bar];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(breakpointsDidChange:)
                                                 name:PCProjectBreakpointNotification object:nil];
    [self reloadItems];
  }
  return self;
}

- (void)breakpointsDidChange:(NSNotification *)notification
{
  [self reloadItems];
}

static NSString *SourceLine(NSString *file, NSUInteger line)
{
  NSString *text = [NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:NULL];
  NSArray *lines = [text componentsSeparatedByString:@"\n"];

  if (line == 0 || line > [lines count])
  {
    return @"";
  }
  return [[lines objectAtIndex:line - 1] stringByTrimmingCharactersInSet:
          [NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (void)reloadItems
{
  NSMutableDictionary *files = [NSMutableDictionary dictionary];
  NSImage *marker = SmallIcon(@"GSNavigatorBreakpointsTemplate");

  [roots removeAllObjects];
  for (NSDictionary *bp in [project symbolicBreakpoints])
  {
    NSString *symbol = [bp objectForKey:@"Symbol"];
    BOOL exception = [[bp objectForKey:@"Kind"] isEqual:PCBreakpointKindException];
    PCNavigatorItem *item = [PCNavigatorItem itemWithTitle:
                             (exception ? @"Objective-C Exception" : symbol) icon:marker info:bp];
    item->toolTip = [[NSString alloc] initWithFormat:@"Breaks in %@", symbol];
    [roots addObject:item];
  }
  for (NSDictionary *bp in [project breakpoints])
  {
    NSString *file = [project absolutePathForBreakpointFile:[bp objectForKey:@"File"]];
    if ([file isKindOfClass:[NSString class]] && [bp objectForKey:@"Line"])
    {
      NSMutableArray *list = [files objectForKey:file];
      if (!list)
      {
        list = [NSMutableArray array];
        [files setObject:list forKey:file];
      }
      [list addObject:bp];
    }
  }
  for (NSString *file in [[files allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)])
  {
    NSImage *fileIcon = [[NSWorkspace sharedWorkspace] iconForFile:file];
    PCNavigatorItem *group = [PCNavigatorItem itemWithTitle:[file lastPathComponent] icon:fileIcon
                                                       info:[NSDictionary dictionaryWithObject:file forKey:@"File"]];
    NSArray *lines = [[files objectForKey:file] sortedArrayUsingComparator:^(id a, id b) {
      return [[a objectForKey:@"Line"] compare:[b objectForKey:@"Line"]];
    }];

    group->toolTip = [file copy];
    for (NSDictionary *bp in lines)
    {
      NSUInteger line = [[bp objectForKey:@"Line"] unsignedIntegerValue];
      NSString *text = SourceLine(file, line);
      NSString *title = [text length]
      ? [NSString stringWithFormat:@"Line %lu  %@", (unsigned long)line, text]
      : [NSString stringWithFormat:@"Line %lu", (unsigned long)line];
      PCNavigatorItem *item = [PCNavigatorItem itemWithTitle:title icon:marker
                                                        info:[NSDictionary dictionaryWithObjectsAndKeys:file, @"File",
                                                              [bp objectForKey:@"Line"], @"Line", nil]];
      [group->children addObject:item];
    }
    [roots addObject:group];
  }
  [self _reloadOutlineExpandingAll];
  [removeButton setEnabled:NO];
}

- (void)selectionDidChange:(PCNavigatorItem *)item
{
  NSString *file = [item->info objectForKey:@"File"];
  NSNumber *line = [item->info objectForKey:@"Line"];

  [removeButton setEnabled:(line != nil || [item->info objectForKey:@"Symbol"] != nil)];
  if (file && line)
  {
    id<CodeEditor> editor = [[project projectEditor] openEditorForFilePath:file windowed:NO];
    [editor scrollToLineNumber:[line unsignedIntegerValue]];
  }
}

- (void)addExceptionBreakpoint:(id)sender
{
  [project setSymbolicBreakpoint:@"objc_exception_throw"
                            kind:PCBreakpointKindException enabled:YES];
}

- (void)addSymbolicBreakpointForSymbol:(NSString *)symbol
{
  [project setSymbolicBreakpoint:symbol kind:PCBreakpointKindSymbol enabled:YES];
}

- (void)addSymbolicBreakpoint:(id)sender
{
  NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 380, 120)
                                              styleMask:NSTitledWindowMask backing:NSBackingStoreBuffered defer:NO];
  NSTextField *label = [[[NSTextField alloc] initWithFrame:NSMakeRect(16, 80, 348, 20)] autorelease];
  NSTextField *field = [[[NSTextField alloc] initWithFrame:NSMakeRect(16, 50, 348, 24)] autorelease];
  NSButton *ok = [[[NSButton alloc] initWithFrame:NSMakeRect(274, 12, 90, 28)] autorelease];
  NSButton *cancel = [[[NSButton alloc] initWithFrame:NSMakeRect(178, 12, 90, 28)] autorelease];

  [panel setTitle:@"Symbolic Breakpoint"];
  [label setStringValue:@"Symbol, e.g. -[NSView setFrame:] or NSLog:"];
  [label setEditable:NO]; [label setSelectable:NO];
  [label setBezeled:NO]; [label setBordered:NO]; [label setDrawsBackground:NO];
  [ok setTitle:@"Add"]; [ok setKeyEquivalent:@"\r"];
  [ok setTarget:NSApp]; [ok setAction:@selector(stopModal)];
  [cancel setTitle:@"Cancel"]; [cancel setKeyEquivalent:@"\e"];
  [cancel setTarget:NSApp]; [cancel setAction:@selector(abortModal)];
  [[panel contentView] addSubview:label];
  [[panel contentView] addSubview:field];
  [[panel contentView] addSubview:ok];
  [[panel contentView] addSubview:cancel];
  [panel setInitialFirstResponder:field];
  [panel center];
  if ([NSApp runModalForWindow:panel] == NSRunStoppedResponse)
  {
    [self addSymbolicBreakpointForSymbol:[field stringValue]];
  }
  [panel orderOut:nil];
  [panel release];
}

- (void)removeSelectedBreakpoint:(id)sender
{
  NSInteger row = [outline selectedRow];
  PCNavigatorItem *item = row >= 0 ? [outline itemAtRow:row] : nil;
  NSDictionary *bp = item ? item->info : nil;

  if ([bp objectForKey:@"Symbol"])
  {
    [project setSymbolicBreakpoint:[bp objectForKey:@"Symbol"]
                              kind:[bp objectForKey:@"Kind"] enabled:NO];
  }
  else if ([bp objectForKey:@"Line"])
  {
    NSString *file = [bp objectForKey:@"File"];
    NSNumber *line = [bp objectForKey:@"Line"];

    [project setBreakpointForFile:file line:[line unsignedIntegerValue] enabled:NO];
    [[NSNotificationCenter defaultCenter]
     postNotificationName:PCProjectBreakpointNotification
     object:[NSDictionary dictionaryWithObjectsAndKeys:
             file, @"File", line, @"Line",
             [NSNumber numberWithBool:NO], @"Enabled", nil]];
  }
}

@end

// ============================================================================
// ==== Debug (call stack)
// ============================================================================

@implementation PCDebugNavigator

- (id)initWithProject:(PCProject *)aProject
{
  if ((self = [super initWithProject:aProject]))
  {
    state = [PCDebuggerStateExited copy];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(debuggerStateDidChange:)
                                                 name:PCDebuggerStateDidChangeNotification object:nil];
    [self reloadItems];
  }
  return self;
}

- (void)dealloc
{
  [frames release];
  [reason release];
  [state release];
  [super dealloc];
}

- (NSArray *)frames { return frames; }

- (NSInteger)selectedFrameIndex
{
  NSInteger row = [outline selectedRow];
  PCNavigatorItem *item = row >= 0 ? [outline itemAtRow:row] : nil;
  NSNumber *index = [item->info objectForKey:@"Index"];
  return index ? [index integerValue] : -1;
}

- (void)debuggerStateDidChange:(NSNotification *)notification
{
  NSDictionary *info = [notification userInfo];

  /* Only this project's session. */
  if ([notification object] != [[project projectLauncher] debugger])
  {
    return;
  }
  debugger = [notification object];
  ASSIGN(state, [info objectForKey:@"State"]);
  ASSIGN(frames, [info objectForKey:@"Frames"]);
  ASSIGN(reason, [info objectForKey:@"Reason"]);
  [self reloadItems];
  if ([state isEqual:PCDebuggerStateStopped])
  {
    NSUInteger selected = [[info objectForKey:@"SelectedFrame"] unsignedIntegerValue];
    PCNavigatorItem *thread = [roots count] ? [roots objectAtIndex:0] : nil;

    if (thread && selected < [thread->children count])
    {
      NSInteger row = [outline rowForItem:[thread->children objectAtIndex:selected]];
      updatingSelection = YES;
      [outline selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
      [outline scrollRowToVisible:row];
      updatingSelection = NO;
    }
  }
}

- (void)reloadItems
{
  NSImage *threadIcon = SmallIcon(@"GSNavigatorDebugTemplate");

  [roots removeAllObjects];
  if ([state isEqual:PCDebuggerStateStopped])
  {
    PCNavigatorItem *thread = [PCNavigatorItem itemWithTitle:
                               [NSString stringWithFormat:@"Thread 1 — %@", reason ? reason : @"Paused"]
                                                        icon:threadIcon info:nil];
    NSUInteger index = 0;

    for (NSDictionary *frame in frames)
    {
      NSString *file = [frame objectForKey:@"File"];
      NSImage *icon = file ? [[NSWorkspace sharedWorkspace] iconForFile:file]
      : [NSImage imageNamed:@"common_Unknown"];
      PCNavigatorItem *item = [PCNavigatorItem itemWithTitle:
                               [NSString stringWithFormat:@"%@ %@", [frame objectForKey:@"Level"],
                                [frame objectForKey:@"Function"]]
                                                        icon:icon info:[NSDictionary dictionaryWithObject:
                                                                        [NSNumber numberWithUnsignedInteger:index++] forKey:@"Index"]];
      if (file)
      {
        item->toolTip = [[NSString alloc] initWithFormat:@"%@:%@",
                         file, [frame objectForKey:@"Line"]];
      }
      [thread->children addObject:item];
    }
    [roots addObject:thread];
  }
  else
  {
    [roots addObject:[PCNavigatorItem itemWithTitle:
                      ([state isEqual:PCDebuggerStateRunning] ? @"Running" : @"No debug session")
                                               icon:threadIcon info:nil]];
  }
  [self _reloadOutlineExpandingAll];
}

- (void)selectionDidChange:(PCNavigatorItem *)item
{
  NSNumber *index = [item->info objectForKey:@"Index"];

  if (index && debugger)
  {
    [debugger selectFrameAtIndex:[index unsignedIntegerValue]];
  }
}

@end

// ============================================================================
// ==== Issues
// ============================================================================

@implementation PCIssueNavigator

- (id)initWithProject:(PCProject *)aProject
{
  if ((self = [super initWithProject:aProject]))
  {
    NSRect bounds = [view bounds];
    NSView *bar = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, NSWidth(bounds), 28)] autorelease];

    [scrollView setFrame:NSMakeRect(0, 28, NSWidth(bounds), NSHeight(bounds) - 28)];
    [bar setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];

    /* The full build output, in the bottom area. */
    logButton = [[[NSButton alloc] initWithFrame:NSMakeRect(4, 2, 90, 24)] autorelease];
    [logButton setTitle:@"Build Log"];
    [logButton setBezelStyle:NSRoundedBezelStyle];
    [[logButton cell] setControlSize:NSControlSizeSmall];
    [logButton setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
    [logButton setToolTip:@"Show the output of the last build"];
    [logButton setTarget:self];
    [logButton setAction:@selector(showBuildLog:)];
    [logButton setAutoresizingMask:NSViewMaxXMargin | NSViewMaxYMargin];
    [bar addSubview:logButton];
    [view addSubview:bar];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(builderDidChange:)
                                                 name:PCProjectBuilderDidChangeNotification
                                               object:nil];
    [self reloadItems];
  }
  return self;
}

- (void)builderDidChange:(NSNotification *)notification
{
  PCProjectBuilder *sender = [notification object];

  /* Subprojects build with the root project's builder. */
  if ([sender project] != project)
  {
    return;
  }
  builder = sender;
  [self reloadItems];
}

- (NSString *)_summary
{
  NSMutableArray *counts = [NSMutableArray array];
  int errors = [builder errorsCount];
  int warnings = [builder warningsCount];

  if (errors > 0)
  {
    [counts addObject:errors == 1 ? @"1 error"
                                  : [NSString stringWithFormat:@"%d errors", errors]];
  }
  if (warnings > 0)
  {
    [counts addObject:warnings == 1 ? @"1 warning"
                                    : [NSString stringWithFormat:@"%d warnings", warnings]];
  }
  if ([counts count] == 0)
  {
    return [builder buildResult];
  }
  return [NSString stringWithFormat:@"%@ — %@", [builder buildResult],
          [counts componentsJoinedByString:@", "]];
}

- (void)reloadItems
{
  NSMutableDictionary *byFile = [NSMutableDictionary dictionary];
  PCNavigatorItem     *summary;

  [roots removeAllObjects];
  if (builder != nil && ([builder isBuilding] || [builder isCleaning]))
  {
    summary = [PCNavigatorItem itemWithTitle:[builder isCleaning] ? @"Cleaning…" : @"Building…"
                                        icon:SmallIcon(@"GSNavigatorIssuesTemplate")
                                        info:nil];
  }
  else if ([builder buildResult] != nil)
  {
    summary = [PCNavigatorItem itemWithTitle:[self _summary]
                                        icon:SmallIcon([builder buildSucceeded]
                                                       ? @"GSIssueSucceeded" : @"GSIssueError")
                                        info:nil];
  }
  else
  {
    summary = [PCNavigatorItem itemWithTitle:@"No build results"
                                        icon:SmallIcon(@"GSNavigatorIssuesTemplate")
                                        info:nil];
  }
  [roots addObject:summary];

  /* One group per file, in the order the compiler reported them. */
  for (NSDictionary *issue in [builder issues])
  {
    NSString        *file = [issue objectForKey:@"File"];
    NSString        *type = [issue objectForKey:@"Type"];
    NSNumber        *line = [issue objectForKey:@"Line"];
    PCNavigatorItem *group = [byFile objectForKey:file];
    PCNavigatorItem *item;
    NSString        *icon = @"GSIssueNote";

    if (group == nil)
    {
      group = [PCNavigatorItem itemWithTitle:[file lastPathComponent]
                                        icon:[[NSWorkspace sharedWorkspace] iconForFile:file]
                                        info:[NSDictionary dictionaryWithObject:file forKey:@"File"]];
      group->toolTip = [file copy];
      [byFile setObject:group forKey:file];
      [roots addObject:group];
    }
    if ([type isEqualToString:@"error"])
    {
      icon = @"GSIssueError";
    }
    else if ([type isEqualToString:@"warning"])
    {
      icon = @"GSIssueWarning";
    }
    item = [PCNavigatorItem itemWithTitle:[issue objectForKey:@"Message"]
                                     icon:SmallIcon(icon)
                                     info:issue];
    item->toolTip = [[NSString alloc] initWithFormat:@"%@:%@: %@: %@",
                     [file lastPathComponent], line, type,
                     [issue objectForKey:@"Message"]];
    [group->children addObject:item];
  }
  [self _reloadOutlineExpandingAll];
}

- (void)selectionDidChange:(PCNavigatorItem *)item
{
  if ([item->info objectForKey:@"File"] != nil)
  {
    [builder showIssue:item->info];
  }
}

- (void)showBuildLog:(id)sender
{
  [[project projectWindow] showProjectBuild:self];
}

@end

