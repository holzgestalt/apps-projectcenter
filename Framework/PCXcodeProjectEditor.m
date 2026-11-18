/*
 PCXcodeProjectEditor.m

 Project editor for Xcode projects: the Xcode project is shown read-only;
 the GNUstep settings (GNUstep/ProjectCenter.plist) can be edited.

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

/* The General pane's form, laid out from the top. */
@interface PCFormView : NSView
@end

@implementation PCFormView
- (BOOL)isFlipped
{
  return YES;
}
@end

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
    generalScroll = [[[NSScrollView alloc] initWithFrame:[[[tabs tabViewItemAtIndex:0] view] bounds]]
                     autorelease];
    [generalScroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [generalScroll setHasVerticalScroller:YES];
    [generalScroll setAutohidesScrollers:YES];
    [generalScroll setBorderType:NSNoBorder];
    [generalScroll setDrawsBackground:NO];
    [[[tabs tabViewItemAtIndex:0] view] addSubview:generalScroll];
    settingsTable = Table([NSArray arrayWithObject:@"Setting"], 300, self,
                          [[tabs tabViewItemAtIndex:1] view]);
    phasesTable = Table([NSArray arrayWithObjects:@"Phase", @"Contents", nil], 240, self,
                        [[tabs tabViewItemAtIndex:2] view]);
  }
  return self;
}

- (void)dealloc
{
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

/* $(NAME) and ${NAME} from the build settings, as Xcode expands them in
 * Info.plist values. */
static NSString *Expanded(id value, NSDictionary *settings)
{
  NSMutableString *text = [NSMutableString stringWithString:DisplayValue(value)];
  NSUInteger      pass;

  for (pass = 0; pass < 4; pass++)
  {
    BOOL changed = NO;

    for (NSString *name in settings)
    {
      for (NSString *form in @[@"$(%@)", @"${%@}"])
      {
        NSString *macro = [NSString stringWithFormat:form, name];

        if ([text rangeOfString:macro].location != NSNotFound)
        {
          [text replaceOccurrencesOfString:macro withString:DisplayValue([settings objectForKey:name])
                                   options:0 range:NSMakeRange(0, [text length])];
          changed = YES;
        }
      }
    }
    if (!changed) break;
  }
  return text;
}

/* "$(NAME)" or "${NAME}" alone: the build setting an Info.plist value comes
 * from, as Xcode's General pane edits it. */
static NSString *MacroName(id value)
{
  NSString *name;

  if (![value isKindOfClass:[NSString class]] || [value length] < 4) return nil;
  if (!(([value hasPrefix:@"$("] && [value hasSuffix:@")"])
        || ([value hasPrefix:@"${"] && [value hasSuffix:@"}"])))
  {
    return nil;
  }
  name = [value substringWithRange:NSMakeRange(2, [value length] - 3)];
  if ([name rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_"] invertedSet]].location
      != NSNotFound)
  {
    return nil;
  }
  return name;
}

/* A popup item: [Title, Value], NSNull for no value. */
static NSArray *Choice(NSString *title, id value)
{
  return [NSArray arrayWithObjects:title, (value ? value : [NSNull null]), nil];
}

/* Names of the files with one of the extensions, without it, once each. */
static NSArray *NamesWithExtensions(NSArray *files, NSArray *extensions)
{
  NSMutableArray *names = [NSMutableArray array];

  for (NSString *file in files)
  {
    NSString *name = [[file lastPathComponent] stringByDeletingPathExtension];

    if ([extensions containsObject:[[file pathExtension] lowercaseString]]
        && ![names containsObject:name])
    {
      [names addObject:name];
    }
  }
  return [names sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

- (void)_buildGeneralRows
{
  NSMutableArray      *rows = [NSMutableArray array];
  NSString            *projectPath = [[project projectDict] objectForKey:@"XCODE_PROJECT_PATH"];
  __block NSUInteger  sectionStart = 0;
  void (^section)(NSString *) = ^(NSString *title) {
    /* A section without rows is left out. */
    if ([rows count] == sectionStart + 1) [rows removeLastObject];
    [rows addObject:[NSArray arrayWithObject:title]];
    sectionStart = [rows count] - 1;
  };
  void (^add)(NSString *, id) = ^(NSString *name, id value) {
    NSString *text = DisplayValue(value);
    if ([text length]) [rows addObject:[NSArray arrayWithObjects:name, text, nil]];
  };
  /* An editable row: [Name, Value, Edit], Edit saying what it changes. An
   * editable row is shown when empty, so it can be set. */
  void (^edit)(NSString *, id, NSDictionary *) = ^(NSString *name, id value, NSDictionary *how) {
    if (how == nil) add(name, value);
    else [rows addObject:[NSArray arrayWithObjects:name, DisplayValue(value), how, nil]];
  };
  NSDictionary *(^choices)(NSDictionary *, NSArray *) = ^NSDictionary *(NSDictionary *how, NSArray *list) {
    NSMutableDictionary *result;

    if (how == nil) return nil;
    result = [NSMutableDictionary dictionaryWithDictionary:how];
    [result setObject:list forKey:@"Choices"];
    return result;
  };

  if (selection == overview)
  {
    NSMutableArray *regions = [NSMutableArray array];

    section(@"Project Document");
    add(@"Project", [overview objectForKey:@"Name"]);
    add(@"Location", projectPath);
    add(@"Project Format", [overview objectForKey:@"Format"]
        ? [NSString stringWithFormat:@"objectVersion %@", [overview objectForKey:@"Format"]] : nil);
    section(@"Localizations");
    for (NSString *region in [overview objectForKey:@"KnownRegions"])
    {
      if (![region isEqual:@"Base"]) [regions addObject:Choice(region, region)];
    }
    edit(@"Development Region", [overview objectForKey:@"DevelopmentRegion"],
         ([overview objectForKey:@"Identifier"] && [regions count]
          ? [NSDictionary dictionaryWithObjectsAndKeys:@"Attribute", @"Kind", @"developmentRegion", @"Key",
             [overview objectForKey:@"Identifier"], @"Object", regions, @"Choices", nil] : nil));
    add(@"Localizations", [[overview objectForKey:@"KnownRegions"] componentsJoinedByString:@", "]);
    section(@"Build");
    add(@"Configurations", [self _configurationSummary:[overview objectForKey:@"Configurations"]]);
    add(@"Targets", [[[overview objectForKey:@"Targets"] valueForKey:@"Name"] componentsJoinedByString:@", "]);
  }
  else
  {
    NSString            *first = [[[selection objectForKey:@"Configurations"] firstObject] objectForKey:@"Name"];
    NSMutableDictionary *settings = [NSMutableDictionary dictionaryWithDictionary:[self _mergedSettings:first]];
    NSString            *name = [selection objectForKey:@"Name"];
    NSString            *infoFile = DisplayValue([settings objectForKey:@"INFOPLIST_FILE"]);
    NSArray             *configurations = [[selection objectForKey:@"Configurations"] valueForKey:@"Identifier"];
    NSMutableArray      *resources = [NSMutableArray array];
    NSMutableArray      *resourcePaths = [NSMutableArray array];
    NSMutableArray      *iconSets = [NSMutableArray array];
    NSMutableArray      *list;
    NSString            *infoPath = nil;
    NSDictionary        *info = nil;
    NSString            *productName;
    NSString            *mainKey;
    BOOL                generated = [DisplayValue([settings objectForKey:@"GENERATE_INFOPLIST_FILE"]) isEqual:@"YES"];
    BOOL                built = [name isEqual:[[project projectDict] objectForKey:@"PROJECT_NAME"]];

    if (![settings objectForKey:@"TARGET_NAME"]) [settings setObject:name forKey:@"TARGET_NAME"];
    productName = Expanded([settings objectForKey:@"PRODUCT_NAME"] ? [settings objectForKey:@"PRODUCT_NAME"]
                           : [selection objectForKey:@"ProductName"], settings);
    [settings setObject:productName forKey:@"PRODUCT_NAME"];
    if (![settings objectForKey:@"EXECUTABLE_NAME"]) [settings setObject:productName forKey:@"EXECUTABLE_NAME"];
    if ([infoFile length])
    {
      infoPath = [[[projectPath stringByDeletingLastPathComponent]
                   stringByAppendingPathComponent:Expanded(infoFile, settings)] stringByStandardizingPath];
      info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
      if (![info isKindOfClass:[NSDictionary class]])
      {
        info = nil;
        infoPath = nil;
      }
    }
    for (NSDictionary *phase in [selection objectForKey:@"Phases"])
    {
      if ([[phase objectForKey:@"Kind"] isEqual:@"Copy Bundle Resources"])
      {
        [resources addObjectsFromArray:[phase objectForKey:@"Files"]];
        [resourcePaths addObjectsFromArray:[phase objectForKey:@"Paths"]];
      }
    }
    for (NSString *catalog in resourcePaths)
    {
      NSDirectoryEnumerator *enumerator;
      NSString              *entry;

      if (![[[catalog pathExtension] lowercaseString] isEqual:@"xcassets"]) continue;
      enumerator = [[NSFileManager defaultManager] enumeratorAtPath:catalog];
      while ((entry = [enumerator nextObject]))
      {
        if ([[entry pathExtension] isEqual:@"appiconset"])
        {
          [iconSets addObject:[[entry lastPathComponent] stringByDeletingPathExtension]];
          [enumerator skipDescendents];
        }
      }
    }

    /* Edits go where Xcode puts them: a build setting in every configuration
     * of the target, or a key of its Info.plist. */
    NSDictionary *(^setting)(NSString *) = ^NSDictionary *(NSString *key) {
      if ([configurations count] == 0 || projectPath == nil) return nil;
      return [NSDictionary dictionaryWithObjectsAndKeys:@"Setting", @"Kind", key, @"Key",
              configurations, @"Configurations", nil];
    };
    NSDictionary *(^infoEdit)(NSString *) = ^NSDictionary *(NSString *key) {
      if (infoPath == nil) return nil;
      return [NSDictionary dictionaryWithObjectsAndKeys:@"Info", @"Kind", key, @"Key", infoPath, @"File", nil];
    };
    /* An Info.plist key: its own value, the build setting it names
     * ("$(MARKETING_VERSION)"), or the setting Xcode generates it from. */
    NSDictionary *(^infoKey)(NSString *, NSString *) = ^NSDictionary *(NSString *key, NSString *fallback) {
      id       raw = [info objectForKey:key];
      NSString *generatedKey = [@"INFOPLIST_KEY_" stringByAppendingString:key];

      if (raw)
      {
        if (MacroName(raw)) return setting(MacroName(raw));
        return [raw isKindOfClass:[NSString class]] ? infoEdit(key) : nil;
      }
      if ([settings objectForKey:generatedKey]) return setting(generatedKey);
      if (fallback) return setting(fallback);
      if (info) return infoEdit(key);
      return generated ? setting(generatedKey) : nil;
    };
    id (^value)(NSString *, NSString *) = ^id(NSString *infoKey, NSString *setting) {
      /* The Info.plist's value, else what Xcode generates it from. */
      id found = [info objectForKey:infoKey];
      if (found == nil) found = [settings objectForKey:[@"INFOPLIST_KEY_" stringByAppendingString:infoKey]];
      if (found == nil && setting) found = [settings objectForKey:setting];
      return found ? Expanded(found, settings) : nil;
    };

    section(@"Target");
    add(@"Target", name);
    /* Fixed when the target is made, as in Xcode. */
    add(@"Type", ProductTypeName([selection objectForKey:@"ProductType"], [selection objectForKey:@"Kind"]));
    edit(@"Product Name", productName, setting(@"PRODUCT_NAME"));

    /* Xcode's General pane, without what only the App Store and Xcode use
     * (App Category, Supported Destinations, Development Assets). */
    section(@"Identity");
    edit(@"Display Name", value(@"CFBundleDisplayName", nil), infoKey(@"CFBundleDisplayName", nil));
    edit(@"Bundle Identifier", value(@"CFBundleIdentifier", @"PRODUCT_BUNDLE_IDENTIFIER"),
         infoKey(@"CFBundleIdentifier", @"PRODUCT_BUNDLE_IDENTIFIER"));
    edit(@"Version", value(@"CFBundleShortVersionString", @"MARKETING_VERSION"),
         infoKey(@"CFBundleShortVersionString", @"MARKETING_VERSION"));
    edit(@"Build", value(@"CFBundleVersion", @"CURRENT_PROJECT_VERSION"),
         infoKey(@"CFBundleVersion", @"CURRENT_PROJECT_VERSION"));

    section(@"Deployment");
    list = [NSMutableArray array];
    if ([settings objectForKey:@"MACOSX_DEPLOYMENT_TARGET"] == nil)
    {
      [list addObject:Choice(@"SDK Default", nil)];
    }
    for (NSString *version in @[@"10.13", @"10.14", @"10.15", @"11.0", @"12.0", @"13.0", @"14.0",
                                @"15.0", @"26.0"])
    {
      [list addObject:Choice(version, version)];
    }
    edit(@"Minimum macOS", [settings objectForKey:@"MACOSX_DEPLOYMENT_TARGET"],
         choices(setting(@"MACOSX_DEPLOYMENT_TARGET"), list));
    mainKey = value(@"NSMainStoryboardFile", nil) ? @"NSMainStoryboardFile" : @"NSMainNibFile";
    list = [NSMutableArray arrayWithObject:Choice(@"None", nil)];
    for (NSString *interface in NamesWithExtensions(resources, ([mainKey isEqual:@"NSMainNibFile"]
                                                                ? @[@"xib", @"nib"] : @[@"storyboard"])))
    {
      [list addObject:Choice(interface, interface)];
    }
    edit(@"Main Interface", value(mainKey, nil), choices(infoKey(mainKey, nil), list));
    edit(@"Info.plist", infoFile, setting(@"INFOPLIST_FILE"));

    section(@"App Icon");
    list = [NSMutableArray arrayWithObject:Choice(@"None", nil)];
    if ([iconSets count] || [settings objectForKey:@"ASSETCATALOG_COMPILER_APPICON_NAME"])
    {
      /* An app icon set of the asset catalogs. */
      for (NSString *icon in [iconSets sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)])
      {
        [list addObject:Choice(icon, icon)];
      }
      edit(@"App Icon", [settings objectForKey:@"ASSETCATALOG_COMPILER_APPICON_NAME"],
           choices(setting(@"ASSETCATALOG_COMPILER_APPICON_NAME"), list));
    }
    else
    {
      /* An .icns file of the resources. */
      for (NSString *icon in NamesWithExtensions(resources, @[@"icns"]))
      {
        [list addObject:Choice(icon, icon)];
      }
      edit(@"App Icon", value(@"CFBundleIconFile", nil), choices(infoKey(@"CFBundleIconFile", nil), list));
    }

    section(@"Frameworks and Libraries");
    for (NSDictionary *phase in [selection objectForKey:@"Phases"])
      if ([[phase objectForKey:@"Kind"] isEqual:@"Link Binary With Libraries"])
        for (NSString *file in [phase objectForKey:@"Files"])
          add(@"", file);

    section(@"Build");
    add(@"Configurations", [self _configurationSummary:[selection objectForKey:@"Configurations"]]);
    add(@"Dependencies", [[selection objectForKey:@"Dependencies"] componentsJoinedByString:@", "]);
    add(@"Build Tool", [selection objectForKey:@"BuildTool"]);

    if (built)
    {
      /* The target ProjectCenter builds and runs on GNUstep; its settings
       * are ProjectCenter's own. */
      NSDictionary *gnustep = [PCXcodeProject GNUstepSettingsOfProjectAtPath:projectPath];
      NSString     *theme = [gnustep objectForKey:@"Theme"];
      NSString     *pathTip = @"A path, relative to the folder of the .xcodeproj or absolute. "
                              @"Saved in GNUstep/ProjectCenter.plist.";

      section(@"GNUstep");
      edit(@"Build Script", [gnustep objectForKey:@"BuildScript"],
           [NSDictionary dictionaryWithObjectsAndKeys:@"GNUstep", @"Kind", @"BuildScript", @"Key",
            @"GNUmakefile in the project folder", @"Placeholder", pathTip, @"ToolTip", nil]);
      edit(@"Executable", [gnustep objectForKey:@"Executable"],
           [NSDictionary dictionaryWithObjectsAndKeys:@"GNUstep", @"Kind", @"Executable", @"Key",
            @"found in the GNUstep build folders", @"Placeholder", pathTip, @"ToolTip", nil]);
      edit(@"Theme", ([theme length] ? theme : @"Default"),
           [NSDictionary dictionaryWithObjectsAndKeys:@"GNUstep", @"Kind", @"Theme", @"Key",
            @"Theme", @"Control", nil]);
    }
  }
  if ([rows count] == sectionStart + 1) [rows removeLastObject];
  ASSIGN(generalRows, rows);
}

// --- The General form

static NSTextField *FormField(NSRect frame, NSString *text, BOOL editable)
{
  NSTextField *field = [[[NSTextField alloc] initWithFrame:frame] autorelease];

  [field setStringValue:text];
  [field setEditable:editable];
  [field setSelectable:YES];
  [field setBezeled:editable];
  [field setDrawsBackground:editable];
  [[field cell] setScrollable:YES];
  [[field cell] setLineBreakMode:NSLineBreakByTruncatingMiddle];
  return field;
}

- (NSPopUpButton *)_themePopUp:(NSRect)frame selected:(NSString *)theme
{
  NSPopUpButton *popUp = [[[NSPopUpButton alloc] initWithFrame:frame pullsDown:NO] autorelease];
  NSArray       *installed = [PCXcodeProject installedThemes];
  NSMenuItem    *item;

  /* Default passes no theme: the user's own GSTheme default applies. */
  [popUp addItemWithTitle:@"Default"];
  [[popUp menu] addItem:[NSMenuItem separatorItem]];
  [popUp addItemWithTitle:@"GNUstep"];
  [[popUp lastItem] setRepresentedObject:@"GNUstep"];
  for (NSString *name in installed)
  {
    if ([name isEqual:@"GNUstep"]) continue;
    [popUp addItemWithTitle:name];
    [[popUp lastItem] setRepresentedObject:name];
  }
  if ([theme length] && ![theme isEqual:@"GNUstep"] && ![installed containsObject:theme])
  {
    [popUp addItemWithTitle:[NSString stringWithFormat:@"%@ (not installed)", theme]];
    [[popUp lastItem] setRepresentedObject:theme];
  }
  for (item in [popUp itemArray])
  {
    if ([theme length] ? [[item representedObject] isEqual:theme] : [[item title] isEqual:@"Default"])
    {
      [popUp selectItem:item];
    }
  }
  [popUp setToolTip:@"The theme Run starts the application with on GNUstep (-GSTheme), "
                    @"also with the destination My Mac (GNUstep) on macOS. "
                    @"Default leaves the user's own theme."];
  return popUp;
}

/* A popup of [Title, Value] choices; a current value that is not among them
 * is added, so it is shown as it is. */
- (NSPopUpButton *)_popUp:(NSRect)frame choices:(NSArray *)list selected:(NSString *)current
{
  NSPopUpButton *popUp = [[[NSPopUpButton alloc] initWithFrame:frame pullsDown:NO] autorelease];
  NSMenuItem    *selected = nil;
  NSMenuItem    *item;

  if (![current length]) current = nil;
  for (NSArray *choice in list)
  {
    id value = [choice objectAtIndex:1];

    item = [[popUp menu] addItemWithTitle:[choice objectAtIndex:0] action:NULL keyEquivalent:@""];
    [item setRepresentedObject:(value == [NSNull null] ? nil : value)];
    if (current ? [value isEqual:current] : value == [NSNull null]) selected = item;
  }
  if (selected == nil && current)
  {
    selected = [[popUp menu] addItemWithTitle:current action:NULL keyEquivalent:@""];
    [selected setRepresentedObject:current];
  }
  if (selected) [popUp selectItem:selected];
  return popUp;
}

- (void)_layoutGeneralForm
{
  CGFloat    width = MAX(400, [generalScroll contentSize].width);
  CGFloat    labelWidth = 180;
  CGFloat    x = labelWidth + 32;
  CGFloat    y = 16;
  NSPoint    scrolled = [[generalScroll contentView] bounds].origin;
  PCFormView *form = [[[PCFormView alloc] initWithFrame:NSMakeRect(0, 0, width, 100)] autorelease];
  NSFont     *bold = [NSFont boldSystemFontOfSize:0];
  NSUInteger index;

  [form setAutoresizingMask:NSViewWidthSizable];
  for (index = 0; index < [generalRows count]; index++)
  {
    NSArray *row = [generalRows objectAtIndex:index];

    if ([row count] == 1)
    {
      /* A section: its title over a line, as in Xcode. */
      NSTextField *title = FormField(NSMakeRect(20, y + 8, width - 40, 18), [row objectAtIndex:0], NO);
      NSBox       *line = [[[NSBox alloc] initWithFrame:NSMakeRect(20, y + 30, width - 40, 1)] autorelease];

      [title setFont:bold];
      [title setSelectable:NO];
      [title setAutoresizingMask:NSViewWidthSizable];
      [line setBoxType:NSBoxSeparator];
      [line setAutoresizingMask:NSViewWidthSizable];
      [form addSubview:title];
      [form addSubview:line];
      y += 40;
      continue;
    }

    NSString     *text = [row objectAtIndex:1];
    NSDictionary *how = [row count] > 2 ? [row objectAtIndex:2] : nil;
    NSTextField  *name = FormField(NSMakeRect(20, y + 3, labelWidth, 18), [row objectAtIndex:0], NO);
    NSView       *control;

    [name setAlignment:NSRightTextAlignment];
    [name setSelectable:NO];
    [form addSubview:name];
    if ([[how objectForKey:@"Control"] isEqual:@"Theme"] || [how objectForKey:@"Choices"])
    {
      NSRect        frame = NSMakeRect(x, y, MIN(260, width - x - 20), 24);
      NSPopUpButton *popUp = ([how objectForKey:@"Choices"]
                              ? [self _popUp:frame choices:[how objectForKey:@"Choices"] selected:text]
                              : [self _themePopUp:frame selected:
                                 [[PCXcodeProject GNUstepSettingsOfProjectAtPath:
                                   [[project projectDict] objectForKey:@"XCODE_PROJECT_PATH"]]
                                  objectForKey:@"Theme"]]);

      [popUp setTag:index];
      [popUp setTarget:self];
      [popUp setAction:@selector(generalChoiceChanged:)];
      control = popUp;
    }
    else if (how)
    {
      NSTextField *field = FormField(NSMakeRect(x, y + 1, width - x - 20, 22), text, YES);

      if ([how objectForKey:@"Placeholder"])
      {
        [[field cell] setPlaceholderString:[how objectForKey:@"Placeholder"]];
      }
      [field setTag:index];
      [field setTarget:self];
      [field setAction:@selector(generalFieldChanged:)];
      [field setDelegate:(id)self];
      [field setAutoresizingMask:NSViewWidthSizable];
      control = field;
    }
    else
    {
      control = FormField(NSMakeRect(x, y + 3, width - x - 20, 18), text, NO);
      [control setAutoresizingMask:NSViewWidthSizable];
    }
    [control setToolTip:([how objectForKey:@"ToolTip"] ? [how objectForKey:@"ToolTip"]
                         : how ? [self _whereSaved:how] : text)];
    [form addSubview:control];
    y += 28;
  }
  [form setFrameSize:NSMakeSize(width, MAX(y + 16, [generalScroll contentSize].height))];
  [generalScroll setDocumentView:form];
  /* Rebuilt after an edit: keep the place. */
  [[generalScroll contentView] scrollToPoint:scrolled];
  [generalScroll reflectScrolledClipView:[generalScroll contentView]];
}

/* Where an edit is saved, for its tooltip. */
- (NSString *)_whereSaved:(NSDictionary *)how
{
  NSString *kind = [how objectForKey:@"Kind"];

  if ([kind isEqual:@"Setting"])
  {
    return [NSString stringWithFormat:@"The build setting %@, for every configuration of the target.",
            [how objectForKey:@"Key"]];
  }
  if ([kind isEqual:@"Info"])
  {
    return [NSString stringWithFormat:@"%@ in %@.", [how objectForKey:@"Key"],
            [[how objectForKey:@"File"] lastPathComponent]];
  }
  if ([kind isEqual:@"Attribute"])
  {
    return [NSString stringWithFormat:@"%@ of the project.", [how objectForKey:@"Key"]];
  }
  return @"Saved in GNUstep/ProjectCenter.plist.";
}

- (BOOL)setGNUstepSetting:(NSString *)value forKey:(NSString *)key
{
  NSString            *path = [[project projectDict] objectForKey:@"XCODE_PROJECT_PATH"];
  NSString            *error = nil;
  NSDictionary        *fresh;
  NSMutableDictionary *projectDict = (NSMutableDictionary *)[project projectDict];

  if (path == nil)
  {
    return NO;
  }
  value = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([DisplayValue([[PCXcodeProject GNUstepSettingsOfProjectAtPath:path] objectForKey:key])
       isEqual:(value ? value : @"")])
  {
    return YES;
  }
  if (![PCXcodeProject setGNUstepSetting:value forKey:key ofProjectAtPath:path error:&error])
  {
    NSRunAlertPanel(@"GNUstep Settings", @"%@", @"OK", nil, nil, error);
    return NO;
  }
  /* Build and Run read the settings from the project dictionary. */
  fresh = [PCXcodeProject projectAtPath:path error:&error];
  for (NSString *name in @[@"BuildScript", @"Executable", @"Theme"])
  {
    NSString *projectKey = [@"XCODE_" stringByAppendingString:name];
    id       setting = [fresh objectForKey:projectKey];

    if (setting) [projectDict setObject:setting forKey:projectKey];
    else [projectDict removeObjectForKey:projectKey];
  }
  if (fresh == nil)
  {
    NSRunAlertPanel(@"GNUstep Settings", @"%@", @"OK", nil, nil, error);
  }
  return YES;
}

- (BOOL)setGeneralValue:(NSString *)value atRow:(NSUInteger)index
{
  NSString     *path = [[project projectDict] objectForKey:@"XCODE_PROJECT_PATH"];
  NSArray      *row = index < [generalRows count] ? [generalRows objectAtIndex:index] : nil;
  NSDictionary *how = [row count] > 2 ? [row objectAtIndex:2] : nil;
  NSString     *kind = [how objectForKey:@"Kind"];
  NSString     *key = [how objectForKey:@"Key"];
  NSString     *error = nil;
  BOOL         done = NO;

  if (how == nil || path == nil)
  {
    return NO;
  }
  value = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if (![value length]) value = nil;
  if ([kind isEqual:@"GNUstep"])
  {
    done = [self setGNUstepSetting:value forKey:key];
  }
  else if ([DisplayValue(value) isEqual:[row objectAtIndex:1]])
  {
    /* Unchanged: a value shown expanded keeps its $(SETTING). */
    return YES;
  }
  else if ([kind isEqual:@"Setting"])
  {
    done = [PCXcodeProject setBuildSetting:key to:value inConfigurations:[how objectForKey:@"Configurations"]
                           ofProjectAtPath:path error:&error];
  }
  else if ([kind isEqual:@"Info"])
  {
    done = [PCXcodeProject setInfoValue:value forKey:key inFile:[how objectForKey:@"File"] error:&error];
  }
  else if ([kind isEqual:@"Attribute"])
  {
    done = [PCXcodeProject setAttribute:key to:value ofObject:[how objectForKey:@"Object"]
                        ofProjectAtPath:path error:&error];
  }
  if (!done && error)
  {
    NSRunAlertPanel(@"Project Settings", @"%@", @"OK", nil, nil, error);
  }
  /* Show what the files say now, once the field has finished editing. */
  [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reload) object:nil];
  [self performSelector:@selector(reload) withObject:nil afterDelay:0];
  return done;
}

- (void)generalFieldChanged:(id)sender
{
  [self setGeneralValue:[sender stringValue] atRow:[sender tag]];
}

- (void)controlTextDidEndEditing:(NSNotification *)notification
{
  [self generalFieldChanged:[notification object]];
}

- (void)generalChoiceChanged:(id)sender
{
  [self setGeneralValue:[[sender selectedItem] representedObject] atRow:[sender tag]];
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
  [self _layoutGeneralForm];
  [settingsTable reloadData];
  [phasesTable reloadData];
}

- (NSArray *)_rowsForTable:(NSTableView *)table
{
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
