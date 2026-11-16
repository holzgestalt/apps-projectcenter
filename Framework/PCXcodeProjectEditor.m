/*
 PCXcodeProjectEditor.m

 Read-only project editor for Xcode projects.

 This file is part of GNUstep ProjectCenter.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation; either version 2 of the License, or
 (at your option) any later version.
 */

#import "PCXcodeProjectEditor.h"
#import "PCXcodeProject.h"
#import "PCNavigators.h"

#import <ProjectCenter/PCProject.h>

// ============================================================================
// ==== Project and targets list
// ============================================================================

@interface PCTargetList : PCNavigator
{
  @public
  PCXcodeProjectEditor *editor;    // not retained
  NSDictionary         *overview;  // not retained
}
@end

@implementation PCTargetList

- (void)reloadItems
{
  PCNavigatorItem *projectGroup;
  PCNavigatorItem *targetGroup;
  NSInteger index = 1;

  [roots removeAllObjects];
  projectGroup = [PCNavigatorItem itemWithTitle:@"PROJECT" icon:nil info:nil];
  [projectGroup->children addObject:[PCNavigatorItem itemWithTitle:[overview objectForKey:@"Name"]
                                                              icon:[NSImage imageNamed:@"FileProject"]
                                                              info:[NSDictionary dictionaryWithObject:[NSNumber numberWithInteger:0] forKey:@"Index"]]];
  [roots addObject:projectGroup];
  targetGroup = [PCNavigatorItem itemWithTitle:@"TARGETS" icon:nil info:nil];
  for (NSDictionary *target in [overview objectForKey:@"Targets"])
  {
    BOOL application = [[target objectForKey:@"ProductType"] hasPrefix:@"com.apple.product-type.application"];
    [targetGroup->children addObject:[PCNavigatorItem itemWithTitle:[target objectForKey:@"Name"]
                                                               icon:[NSImage imageNamed:application ? @"NSApplicationIcon" : @"GSBuildTemplate"]
                                                               info:[NSDictionary dictionaryWithObject:[NSNumber numberWithInteger:index++] forKey:@"Index"]]];
  }
  [roots addObject:targetGroup];
  [self _reloadOutlineExpandingAll];
}

- (void)selectIndex:(NSInteger)index
{
  for (NSInteger row = 0; row < [outline numberOfRows]; row++)
  {
    PCNavigatorItem *item = [outline itemAtRow:row];
    if ([[item->info objectForKey:@"Index"] integerValue] == index && item->info)
    {
      updatingSelection = YES;
      [outline selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
      updatingSelection = NO;
      return;
    }
  }
}

- (void)selectionDidChange:(PCNavigatorItem *)item
{
  NSNumber *index = [item->info objectForKey:@"Index"];
  if (index)
  {
    [editor selectEntryAtIndex:[index integerValue]];
  }
}

/* Group headers are labels, not selectable entries. */
- (BOOL)outlineView:(NSOutlineView *)v shouldSelectItem:(id)item
{
  return ((PCNavigatorItem *)item)->info != nil;
}

@end

// ============================================================================
// ==== Project editor
// ============================================================================

static NSString *DisplayValue(id value)
{
  if ([value isKindOfClass:[NSArray class]])
    return [value componentsJoinedByString:@" "];
  return value ? [value description] : @"";
}

static NSString *ProductTypeName(NSString *type, NSString *kind)
{
  NSDictionary *names = [NSDictionary dictionaryWithObjectsAndKeys:
                         @"Application", @"com.apple.product-type.application",
                         @"Unit Test Bundle", @"com.apple.product-type.bundle.unit-test",
                         @"UI Test Bundle", @"com.apple.product-type.bundle.ui-testing",
                         @"Bundle", @"com.apple.product-type.bundle",
                         @"Framework", @"com.apple.product-type.framework",
                         @"Command-line Tool", @"com.apple.product-type.tool",
                         @"Static Library", @"com.apple.product-type.library.static",
                         @"Dynamic Library", @"com.apple.product-type.library.dynamic",
                         @"App Extension", @"com.apple.product-type.app-extension", nil];

  if ([names objectForKey:type]) return [names objectForKey:type];
  if (type) return type;
  if ([kind isEqual:@"Aggregate"]) return @"Aggregate";
  if ([kind isEqual:@"External"]) return @"External Build Tool";
  return kind ? kind : @"";
}

@implementation PCXcodeProjectEditor

static NSTableView *Table(NSArray *titles, CGFloat firstWidth, id owner, NSView *container)
{
  NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:[container bounds]] autorelease];
  NSTableView *table = [[[NSTableView alloc] initWithFrame:[[scroll contentView] bounds]] autorelease];
  NSUInteger i;

  [scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [scroll setHasVerticalScroller:YES];
  [scroll setHasHorizontalScroller:YES];
  [scroll setAutohidesScrollers:YES];
  [scroll setBorderType:NSNoBorder];
  for (i = 0; i < [titles count]; i++)
  {
    NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:
                              [NSString stringWithFormat:@"%lu", (unsigned long)i]] autorelease];
    [[column headerCell] setStringValue:[titles objectAtIndex:i]];
    [column setWidth:i == 0 ? firstWidth : 260];
    [column setEditable:NO];
    [table addTableColumn:column];
  }
  [table setColumnAutoresizingStyle:NSTableViewNoColumnAutoresizing];
  [table setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [table setDataSource:owner];
  [table setDelegate:owner];
  [scroll setDocumentView:table];
  [container addSubview:scroll];
  return table;
}

- (id)initWithProject:(PCProject *)aProject
{
  if ((self = [super init]))
  {
    NSRect frame = NSMakeRect(0, 0, 800, 500);
    NSView *list;
    NSArray *titles = [NSArray arrayWithObjects:@"General", @"Build Settings", @"Build Phases", nil];
    NSUInteger i;

    project = aProject;
    view = [[NSView alloc] initWithFrame:frame];
    [view setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    targetList = [[PCTargetList alloc] initWithProject:aProject];
    targetList->editor = self;
    list = [targetList view];
    [list setFrame:NSMakeRect(0, 0, 200, NSHeight(frame))];
    [list setAutoresizingMask:NSViewHeightSizable | NSViewMaxXMargin];
    [view addSubview:list];

    /* Like Xcode: a segmented control selects the pane. */
    sections = [[[NSSegmentedControl alloc] initWithFrame:
                 NSMakeRect(208 + (NSWidth(frame) - 208 - 330) / 2, NSHeight(frame) - 32, 330, 24)] autorelease];
    [sections setSegmentCount:[titles count]];
    for (i = 0; i < [titles count]; i++)
    {
      [sections setLabel:[titles objectAtIndex:i] forSegment:i];
      [sections setWidth:110 forSegment:i];
    }
    [[sections cell] setTrackingMode:NSSegmentSwitchTrackingSelectOne];
    [sections setSelectedSegment:0];
    [sections setTarget:self];
    [sections setAction:@selector(sectionChanged:)];
    [sections setAutoresizingMask:NSViewMinXMargin | NSViewMaxXMargin | NSViewMinYMargin];
    [view addSubview:sections];

    tabs = [[[NSTabView alloc] initWithFrame:NSMakeRect(208, 0, NSWidth(frame) - 208, NSHeight(frame) - 40)] autorelease];
    [tabs setTabViewType:NSNoTabsNoBorder];
    [tabs setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    for (i = 0; i < [titles count]; i++)
    {
      NSTabViewItem *item = [[[NSTabViewItem alloc] initWithIdentifier:[titles objectAtIndex:i]] autorelease];
      NSView *content = [[[NSView alloc] initWithFrame:[tabs contentRect]] autorelease];
      [content setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
      [item setLabel:[titles objectAtIndex:i]];
      [item setView:content];
      [tabs addTabViewItem:item];
    }
    [view addSubview:tabs];
    generalTable = Table([NSArray arrayWithObjects:@"Property", @"Value", nil], 180, self,
                         [[tabs tabViewItemAtIndex:0] view]);
    settingsTable = Table([NSArray arrayWithObject:@"Setting"], 300, self,
                          [[tabs tabViewItemAtIndex:1] view]);
    phasesTable = Table([NSArray arrayWithObjects:@"Phase", @"Contents", nil], 240, self,
                        [[tabs tabViewItemAtIndex:2] view]);
  }
  return self;
}

- (void)dealloc
{
  [generalTable setDataSource:nil]; [generalTable setDelegate:nil];
  [settingsTable setDataSource:nil]; [settingsTable setDelegate:nil];
  [phasesTable setDataSource:nil]; [phasesTable setDelegate:nil];
  [targetList release];
  [view release];
  [overview release];
  [selection release];
  [generalRows release];
  [settingRows release];
  [phaseRows release];
  [configurationNames release];
  [super dealloc];
}

- (void)sectionChanged:(id)sender
{
  [tabs selectTabViewItemAtIndex:[sections selectedSegment]];
}

- (void)selectSectionAtIndex:(NSInteger)index
{
  [sections setSelectedSegment:index];
  [tabs selectTabViewItemAtIndex:index];
}

- (NSView *)view { return view; }
- (NSDictionary *)overview { return overview; }
- (NSDictionary *)selection { return selection; }
- (NSTabView *)tabView { return tabs; }
- (NSArray *)generalRows { return generalRows; }
- (NSArray *)settingRows { return settingRows; }
- (NSArray *)phaseRows { return phaseRows; }
- (NSArray *)configurationNames { return configurationNames; }
- (NSOutlineView *)targetOutlineView { return [targetList outlineView]; }

- (void)reload
{
  NSString *path = [[project projectDict] objectForKey:@"XCODE_PROJECT_PATH"];
  NSDictionary *fresh = path ? [PCXcodeProject overviewOfProjectAtPath:path error:NULL] : nil;
  NSString *selectedName = [selection objectForKey:@"Name"];
  NSInteger index = 0, i = 1;

  ASSIGN(overview, fresh);
  targetList->overview = overview;
  [targetList reloadItems];

  /* Keep the selection; initially the target ProjectCenter builds. */
  if (selectedName == nil || selection == nil)
  {
    selectedName = [[project projectDict] objectForKey:@"PROJECT_NAME"];
    index = -1;
  }
  for (NSDictionary *target in [overview objectForKey:@"Targets"])
  {
    if ([[target objectForKey:@"Name"] isEqual:selectedName])
    {
      index = i;
    }
    i++;
  }
  [self selectEntryAtIndex:index < 0 ? 0 : index];
}

- (NSDictionary *)_mergedSettings:(NSString *)configuration
{
  NSMutableDictionary *settings = [NSMutableDictionary dictionary];

  /* Target settings override the project's, as in Xcode. */
  for (NSDictionary *c in [overview objectForKey:@"Configurations"])
    if ([[c objectForKey:@"Name"] isEqual:configuration])
      [settings addEntriesFromDictionary:[c objectForKey:@"Settings"]];
  if (selection != overview)
    for (NSDictionary *c in [selection objectForKey:@"Configurations"])
      if ([[c objectForKey:@"Name"] isEqual:configuration])
        [settings addEntriesFromDictionary:[c objectForKey:@"Settings"]];
  return settings;
}

- (NSString *)_configurationSummary:(NSArray *)configurations
{
  NSMutableArray *parts = [NSMutableArray array];
  for (NSDictionary *c in configurations)
  {
    [parts addObject:[c objectForKey:@"Base"]
     ? [NSString stringWithFormat:@"%@ (based on %@)", [c objectForKey:@"Name"], [c objectForKey:@"Base"]]
     : [c objectForKey:@"Name"]];
  }
  return [parts componentsJoinedByString:@", "];
}

- (void)_buildGeneralRows
{
  NSMutableArray *rows = [NSMutableArray array];
  void (^add)(NSString *, id) = ^(NSString *name, id value) {
    NSString *text = DisplayValue(value);
    if ([text length]) [rows addObject:[NSArray arrayWithObjects:name, text, nil]];
  };

  if (selection == overview)
  {
    add(@"Project", [overview objectForKey:@"Name"]);
    add(@"Project Format", [overview objectForKey:@"Format"]
        ? [NSString stringWithFormat:@"objectVersion %@", [overview objectForKey:@"Format"]] : nil);
    add(@"Development Region", [overview objectForKey:@"DevelopmentRegion"]);
    add(@"Localizations", [[overview objectForKey:@"KnownRegions"] componentsJoinedByString:@", "]);
    add(@"Configurations", [self _configurationSummary:[overview objectForKey:@"Configurations"]]);
    add(@"Targets", [[[overview objectForKey:@"Targets"] valueForKey:@"Name"] componentsJoinedByString:@", "]);
    add(@"Location", [[project projectDict] objectForKey:@"XCODE_PROJECT_PATH"]);
  }
  else
  {
    NSString *first = [[[selection objectForKey:@"Configurations"] firstObject] objectForKey:@"Name"];
    NSDictionary *settings = [self _mergedSettings:first];
    NSString *productName = DisplayValue([settings objectForKey:@"PRODUCT_NAME"]);
    NSString *version = DisplayValue([settings objectForKey:@"MARKETING_VERSION"]);
    NSString *build = DisplayValue([settings objectForKey:@"CURRENT_PROJECT_VERSION"]);

    productName = [productName stringByReplacingOccurrencesOfString:@"$(TARGET_NAME)"
                                                         withString:[selection objectForKey:@"Name"]];
    add(@"Target", [selection objectForKey:@"Name"]);
    add(@"Type", ProductTypeName([selection objectForKey:@"ProductType"], [selection objectForKey:@"Kind"]));
    add(@"Product Name", [productName length] ? productName : [selection objectForKey:@"ProductName"]);
    add(@"Bundle Identifier", [settings objectForKey:@"PRODUCT_BUNDLE_IDENTIFIER"]);
    add(@"Deployment Target", [settings objectForKey:@"MACOSX_DEPLOYMENT_TARGET"]
        ? [NSString stringWithFormat:@"macOS %@", DisplayValue([settings objectForKey:@"MACOSX_DEPLOYMENT_TARGET"])] : nil);
    add(@"Version", [version length] && [build length]
        ? [NSString stringWithFormat:@"%@ (%@)", version, build] : ([version length] ? version : build));
    add(@"Info.plist", [settings objectForKey:@"INFOPLIST_FILE"]);
    add(@"Configurations", [self _configurationSummary:[selection objectForKey:@"Configurations"]]);
    add(@"Dependencies", [[selection objectForKey:@"Dependencies"] componentsJoinedByString:@", "]);
    add(@"Build Tool", [selection objectForKey:@"BuildTool"]);
    if ([[selection objectForKey:@"Name"] isEqual:[[project projectDict] objectForKey:@"PROJECT_NAME"]])
    {
      /* The target ProjectCenter builds and runs on GNUstep. */
      add(@"GNUstep Build Script", [[project projectDict] objectForKey:@"XCODE_BuildScript"]);
      add(@"GNUstep Executable", [[project projectDict] objectForKey:@"XCODE_Executable"]);
    }
  }
  ASSIGN(generalRows, rows);
}

- (void)_buildSettingRows
{
  NSArray *configurations = [selection objectForKey:@"Configurations"];
  NSMutableArray *names = [NSMutableArray array];
  NSMutableArray *merged = [NSMutableArray array];
  NSMutableSet *keys = [NSMutableSet set];
  NSMutableArray *rows = [NSMutableArray array];
  NSArray *columns;
  NSUInteger i;

  if ([configurations count] == 0)
    configurations = [overview objectForKey:@"Configurations"];
  for (NSDictionary *c in configurations)
  {
    NSDictionary *settings = [self _mergedSettings:[c objectForKey:@"Name"]];
    [names addObject:[c objectForKey:@"Name"]];
    [merged addObject:settings];
    [keys addObjectsFromArray:[settings allKeys]];
  }
  for (NSString *key in [[keys allObjects] sortedArrayUsingSelector:@selector(compare:)])
  {
    NSMutableArray *row = [NSMutableArray arrayWithObject:key];
    for (NSDictionary *settings in merged)
      [row addObject:DisplayValue([settings objectForKey:key])];
    [rows addObject:row];
  }
  ASSIGN(settingRows, rows);
  ASSIGN(configurationNames, names);

  /* One value column per configuration. */
  columns = [[[settingsTable tableColumns] copy] autorelease];
  for (i = 1; i < [columns count]; i++)
    [settingsTable removeTableColumn:[columns objectAtIndex:i]];
  for (i = 0; i < [names count]; i++)
  {
    NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:
                              [NSString stringWithFormat:@"%lu", (unsigned long)i + 1]] autorelease];
    [[column headerCell] setStringValue:[names objectAtIndex:i]];
    [column setWidth:240];
    [column setEditable:NO];
    [settingsTable addTableColumn:column];
  }
}

- (void)_buildPhaseRows
{
  NSMutableArray *rows = [NSMutableArray array];

  for (NSDictionary *phase in [selection objectForKey:@"Phases"])
  {
    NSArray *files = [phase objectForKey:@"Files"];
    NSString *script = [phase objectForKey:@"Script"];
    NSString *count = script ? @"" : [NSString stringWithFormat:@"%lu item%@",
                                      (unsigned long)[files count], [files count] == 1 ? @"" : @"s"];

    [rows addObject:[NSArray arrayWithObjects:[phase objectForKey:@"Name"], count, nil]];
    for (NSString *file in files)
      [rows addObject:[NSArray arrayWithObjects:@"", file, nil]];
    for (NSString *line in [script componentsSeparatedByString:@"\n"])
      if ([line length])
        [rows addObject:[NSArray arrayWithObjects:@"", line, nil]];
  }
  if ([rows count] == 0 && selection != overview)
    [rows addObject:[NSArray arrayWithObjects:@"No build phases", @"", nil]];
  ASSIGN(phaseRows, rows);
}

- (void)selectEntryAtIndex:(NSInteger)index
{
  NSArray *targets = [overview objectForKey:@"Targets"];
  NSDictionary *entry = index <= 0 || index > (NSInteger)[targets count]
  ? overview : [targets objectAtIndex:index - 1];

  ASSIGN(selection, entry);
  [targetList selectIndex:entry == overview ? 0 : index];
  [self _buildGeneralRows];
  [self _buildSettingRows];
  [self _buildPhaseRows];
  /* The project has no build phases of its own. */
  [generalTable reloadData];
  [settingsTable reloadData];
  [phasesTable reloadData];
}

- (NSArray *)_rowsForTable:(NSTableView *)table
{
  if (table == generalTable) return generalRows;
  if (table == settingsTable) return settingRows;
  return phaseRows;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)table
{
  return [[self _rowsForTable:table] count];
}

- (id)tableView:(NSTableView *)table objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
  NSArray *values = [[self _rowsForTable:table] objectAtIndex:row];
  NSUInteger index = [[column identifier] integerValue];
  return index < [values count] ? [values objectAtIndex:index] : @"";
}

- (BOOL)tableView:(NSTableView *)table shouldEditTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
  return NO;
}

@end
