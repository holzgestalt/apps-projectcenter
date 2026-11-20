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
#import "PCDeploymentEditor.h"

#import <ProjectCenter/PCProject.h>

/* The document of the General pane's scroll view, which holds the form at
 * its top. */
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

- (id)initWithProject:(PCProject *)aProject
{
  if ((self = [super init]))
  {
    NSView *list;

    project = aProject;
    if ([NSBundle loadNibNamed:@"ProjectEditor" owner:self] == NO || view == nil)
    {
      NSLog(@"PCXcodeProjectEditor: error loading ProjectEditor");
      [self release];
      return nil;
    }

    targetList = [[PCTargetList alloc] initWithProject:aProject];
    targetList->editor = self;
    list = [targetList view];
    [list setFrame:[targetListArea bounds]];
    [list setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [targetListArea addSubview:list];

    [sections setSelectedSegment:0];
    [tabs selectTabViewItemAtIndex:0];
    [deploymentEditor setProject:aProject];

    /* The fields of the forms, by the name of their row in -generalRows. */
    projectControls = [[NSDictionary alloc] initWithObjectsAndKeys:
                       projectNameField, @"Project",
                       projectLocationField, @"Location",
                       projectFormatField, @"Project Format",
                       developmentRegionPopUp, @"Development Region",
                       localizationsField, @"Localizations",
                       projectConfigurationsField, @"Configurations",
                       targetsField, @"Targets", nil];
    targetControls = [[NSDictionary alloc] initWithObjectsAndKeys:
                      targetNameField, @"Target",
                      typeField, @"Type",
                      productNameField, @"Product Name",
                      displayNameField, @"Display Name",
                      bundleIdentifierField, @"Bundle Identifier",
                      versionField, @"Version",
                      buildField, @"Build",
                      minimumMacOSPopUp, @"Minimum macOS",
                      mainInterfacePopUp, @"Main Interface",
                      infoPlistField, @"Info.plist",
                      appIconPopUp, @"App Icon",
                      targetConfigurationsField, @"Configurations",
                      dependenciesField, @"Dependencies",
                      buildToolField, @"Build Tool",
                      buildScriptField, @"Build Script",
                      executableField, @"Executable",
                      themePopUp, @"Theme", nil];
    targetFormHeight = NSHeight([targetForm frame]);

    formContainer = [[PCFormView alloc] initWithFrame:NSMakeRect(0, 0, [generalScroll contentSize].width, 100)];
    [formContainer setAutoresizingMask:NSViewWidthSizable];
    [generalScroll setDocumentView:formContainer];
    /* The form is as wide as the scroll view. */
    [[generalScroll contentView] setPostsFrameChangedNotifications:YES];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_sizeGeneralForm)
                                                 name:NSViewFrameDidChangeNotification
                                               object:[generalScroll contentView]];
    /* The split view resizes its panes in proportion until it is in a
     * window; then the target list gets its width once. */
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_placeDivider:)
                                                 name:NSViewFrameDidChangeNotification
                                               object:splitView];
  }
  return self;
}

- (void)_placeDivider:(NSNotification *)notification
{
  if ([splitView window] == nil || NSWidth([splitView frame]) < 400) return;
  [splitView setPosition:200 ofDividerAtIndex:0];
  [[NSNotificationCenter defaultCenter] removeObserver:self
                                                  name:NSViewFrameDidChangeNotification
                                                object:splitView];
}

- (void)dealloc
{
  [settingsTable setDataSource:nil]; [settingsTable setDelegate:nil];
  [phasesTable setDataSource:nil]; [phasesTable setDelegate:nil];
  [frameworksTable setDataSource:nil]; [frameworksTable setDelegate:nil];
  for (NSTextField *field in [[projectControls allValues] arrayByAddingObjectsFromArray:[targetControls allValues]])
  {
    if ([field isKindOfClass:[NSTextField class]]) [field setDelegate:nil];
  }
  [NSObject cancelPreviousPerformRequestsWithTarget:self];
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [targetList release];
  /* The nib's top-level objects. */
  [view release];
  [deploymentEditor release];
  [projectForm release];
  [targetForm release];
  [formContainer release];
  [projectControls release];
  [targetControls release];
  [frameworkRows release];
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
- (NSArray *)frameworkRows { return frameworkRows; }
- (NSArray *)configurationNames { return configurationNames; }
- (NSOutlineView *)targetOutlineView { return [targetList outlineView]; }
- (PCDeploymentEditor *)deploymentEditor { return deploymentEditor; }

- (void)reload
{
  NSString *path = [[project projectDict] objectForKey:@"XCODE_PROJECT_PATH"];
  NSDictionary *fresh = path ? [PCXcodeProject overviewOfProjectAtPath:path error:NULL] : nil;
  NSString *selectedName = [selection objectForKey:@"Name"];
  NSInteger index = 0, i = 1;

  ASSIGN(overview, fresh);
  targetList->overview = overview;
  [targetList reloadItems];
  [deploymentEditor reload];

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

/* The themes, Default passing none: the user's own GSTheme default applies. */
- (void)_fillThemePopUp:(NSPopUpButton *)popUp selected:(NSString *)theme
{
  NSArray    *installed = [PCXcodeProject installedThemes];
  NSMenuItem *item;

  /* An unset choice uses the application's own build default. */
  [popUp addItemWithTitle:@"Application Default"];
  [[popUp menu] addItem:[NSMenuItem separatorItem]];
  for (NSString *name in installed)
  {
    [popUp addItemWithTitle:name];
    [[popUp lastItem] setRepresentedObject:name];
  }
  if ([theme length] && ![installed containsObject:theme])
  {
    [popUp addItemWithTitle:[NSString stringWithFormat:@"%@ (not installed)", theme]];
    [[popUp lastItem] setRepresentedObject:theme];
  }
  for (item in [popUp itemArray])
  {
    if ([theme length] ? [[item representedObject] isEqual:theme] : [[item title] isEqual:@"Application Default"])
    {
      [popUp selectItem:item];
    }
  }
}

/* [Title, Value] choices; a current value that is not among them is added,
 * so it is shown as it is. */
- (void)_fillPopUp:(NSPopUpButton *)popUp choices:(NSArray *)list selected:(NSString *)current
{
  NSMenuItem *selected = nil;
  NSMenuItem *item;

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
}

/* The row of -generalRows that a field of the forms shows, or NSNotFound. */
- (NSUInteger)_generalRowNamed:(NSString *)name
{
  NSUInteger index;

  for (index = 0; name && index < [generalRows count]; index++)
  {
    NSArray *row = [generalRows objectAtIndex:index];

    if ([row count] > 1 && [[row objectAtIndex:0] isEqual:name]) return index;
  }
  return NSNotFound;
}

- (NSUInteger)_generalRowOfControl:(id)control
{
  NSDictionary *controls = selection == overview ? projectControls : targetControls;

  return [self _generalRowNamed:[[controls allKeysForObject:control] lastObject]];
}

/* The form shown, at the top of the scroll view and as wide as it; the
 * target form without its GNUstep section when that is hidden. */
- (void)_sizeGeneralForm
{
  NSView  *form = [[formContainer subviews] lastObject];
  CGFloat width = [generalScroll contentSize].width;
  CGFloat height = NSHeight([form frame]);

  if (form == nil) return;
  if (form == targetForm)
  {
    height = targetFormHeight - ([gnustepSection isHidden] ? NSHeight([gnustepSection frame]) : 0);
  }
  [formContainer setFrameSize:NSMakeSize(width, MAX(height, [generalScroll contentSize].height))];
  [form setFrame:NSMakeRect(0, 0, width, height)];
}

/* Fills the fields of the form from -generalRows. A field whose row has an
 * edit can be changed; the others show their value, or nothing. */
- (void)_showGeneralForm
{
  BOOL         projectShown = (selection == overview);
  NSView       *form = projectShown ? projectForm : targetForm;
  NSDictionary *controls = projectShown ? projectControls : targetControls;
  NSPoint      scrolled = [[generalScroll contentView] bounds].origin;
  NSString     *projectPath = [[project projectDict] objectForKey:@"XCODE_PROJECT_PATH"];

  for (NSString *name in controls)
  {
    id           control = [controls objectForKey:name];
    NSUInteger   index = [self _generalRowNamed:name];
    NSArray      *row = index == NSNotFound ? nil : [generalRows objectAtIndex:index];
    NSString     *text = row ? [row objectAtIndex:1] : @"";
    NSDictionary *how = [row count] > 2 ? [row objectAtIndex:2] : nil;

    if ([control isKindOfClass:[NSPopUpButton class]])
    {
      [control removeAllItems];
      if ([[how objectForKey:@"Control"] isEqual:@"Theme"])
      {
        [self _fillThemePopUp:control
                     selected:[[PCXcodeProject GNUstepSettingsOfProjectAtPath:projectPath] objectForKey:@"Theme"]];
      }
      else if ([how objectForKey:@"Choices"])
      {
        [self _fillPopUp:control choices:[how objectForKey:@"Choices"] selected:text];
      }
      else
      {
        [control addItemWithTitle:([text length] ? text : @"None")];
      }
      [control setEnabled:(how != nil)];
    }
    else
    {
      /* A field being edited keeps what is typed. */
      if ([control currentEditor] == nil) [control setStringValue:text];
      [control setEditable:(how != nil)];
      [control setBezeled:(how != nil)];
      [control setDrawsBackground:(how != nil)];
      [[control cell] setPlaceholderString:[how objectForKey:@"Placeholder"]];
    }
    [control setToolTip:([[how objectForKey:@"Control"] isEqual:@"Theme"]
                         ? @"The theme used when building and running with GNUstep. Rebuild after "
                           @"changing it. Application Default uses the application's own default."
                         : [how objectForKey:@"ToolTip"] ? [how objectForKey:@"ToolTip"]
                         : how ? [self _whereSaved:how] : ([text length] ? text : nil))];
  }

  if (!projectShown)
  {
    NSMutableArray *frameworks = [NSMutableArray array];
    BOOL           gnustep = [self _generalRowNamed:@"Build Script"] != NSNotFound;

    /* The rows without a name are the Frameworks and Libraries. */
    for (NSArray *row in generalRows)
    {
      if ([row count] > 1 && [[row objectAtIndex:0] isEqual:@""])
      {
        [frameworks addObject:[row subarrayWithRange:NSMakeRange(1, 1)]];
      }
    }
    ASSIGN(frameworkRows, frameworks);
    [frameworksTable reloadData];
    /* The GNUstep section, last in the form, only for the target
     * ProjectCenter builds. */
    [gnustepSection setHidden:!gnustep];
  }

  if ([form superview] != formContainer)
  {
    [projectForm removeFromSuperview];
    [targetForm removeFromSuperview];
    [formContainer addSubview:form];
  }
  [self _sizeGeneralForm];
  /* Filled again after an edit: keep the place. */
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
  NSUInteger index = [self _generalRowOfControl:sender];

  if (index != NSNotFound) [self setGeneralValue:[sender stringValue] atRow:index];
}

- (void)controlTextDidEndEditing:(NSNotification *)notification
{
  [self generalFieldChanged:[notification object]];
}

- (void)generalChoiceChanged:(id)sender
{
  NSUInteger index = [self _generalRowOfControl:sender];

  if (index != NSNotFound) [self setGeneralValue:[[sender selectedItem] representedObject] atRow:index];
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
  [self _showGeneralForm];
  [settingsTable reloadData];
  [phasesTable reloadData];
}

- (NSArray *)_rowsForTable:(NSTableView *)table
{
  if (table == settingsTable) return settingRows;
  if (table == frameworksTable) return frameworkRows;
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
