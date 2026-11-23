#import <Foundation/Foundation.h>
#import "PCXcodeProject.h"
#import "PCDeployment.h"
#import "PCGormArchive.h"
#import "PCGormXIBWriter.h"
#import "PCInterfaceDocument.h"

static void Check(BOOL condition, NSString *message)
{
  if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}

/* Every .gorm of ProjectCenter: read and written back unchanged, edited and
 * read again, and shown as a well-formed XIB. */
static void TestGormArchives(void)
{
  NSString              *repository = [[[NSString stringWithUTF8String:__FILE__]
                                        stringByDeletingLastPathComponent]
                                       stringByDeletingLastPathComponent];
  NSDirectoryEnumerator *files = [[NSFileManager defaultManager] enumeratorAtPath:repository];
  NSString              *file;
  NSUInteger            count = 0;

  while ((file = [files nextObject]))
  {
    NSString      *path, *error = nil;
    NSData        *data;
    PCGormArchive *archive;
    NSXMLDocument *xib;

    if (![file hasSuffix:@".gorm/objects.gorm"] || [file hasPrefix:@"build"])
    {
      continue;
    }
    path = [repository stringByAppendingPathComponent:file];
    data = [NSData dataWithContentsOfFile:path];
    archive = [PCGormArchive archiveWithData:data error:&error];
    Check(archive != nil, [NSString stringWithFormat:@"%@ reads: %@", file, error]);
    Check([[archive data] isEqualToData:data], [NSString stringWithFormat:@"%@ is written back unchanged", file]);
    xib = [PCGormXIBWriter documentForArchive:archive toolsVersion:nil warnings:NULL];
    Check([[NSXMLDocument alloc] initWithData:[xib XMLData] options:0 error:NULL] != nil,
          [NSString stringWithFormat:@"%@ gives well-formed XIB", file]);
    for (PCGormObject *object in [archive allObjects])
    {
      if ([object isKindOfClassNamed:@"NSWindow"] || [object isKindOfClassNamed:@"NSPanel"])
      {
        NSString *query = [NSString stringWithFormat:@"//window[@id='%@']",
                           [PCGormXIBWriter identifierForObject:object]];
        Check([[xib nodesForXPath:query error:NULL] count] == 1,
              [NSString stringWithFormat:@"%@: window %@ in the XIB", file, object]);
      }
    }
    count++;
  }
  Check(count >= 30, @"the .gorm files of ProjectCenter are found");

  {
    NSString      *info = [repository stringByAppendingPathComponent:@"English.lproj/Info.gorm/objects.gorm"];
    NSString      *error = nil;
    PCGormArchive *archive = [PCGormArchive archiveWithContentsOfFile:info error:&error];
    PCGormObject  *panel = nil, *field = nil;
    PCGormArchive *edited;
    NSData        *data;

    for (PCGormObject *object in [archive allObjects])
    {
      if ([object isKindOfClassNamed:@"NSPanel"]) panel = object;
      if (field == nil && [object isKindOfClassNamed:@"NSTextField"]) field = object;
    }
    Check([[panel stringForField:@"title"] isEqual:@"Info"], @"Info panel title");
    [panel setString:@"Über" forField:@"title"];
    [[field objectForField:@"cell"] setString:@"Edited" forField:@"contents"];
    [field setRect:NSMakeRect(1, 2, 300, 40) forField:@"frame"];
    data = [archive data];
    edited = [PCGormArchive archiveWithData:data error:&error];
    Check(edited != nil, [NSString stringWithFormat:@"edited archive reads: %@", error]);
    Check([[[edited objectWithIdentifier:[panel identifier]] stringForField:@"title"] isEqual:@"Über"],
          @"edited title (not Latin-1 safe for every character) is kept");
    Check([[[[edited objectWithIdentifier:[field identifier]] objectForField:@"cell"]
            stringForField:@"contents"] isEqual:@"Edited"], @"edited cell contents are kept");
    Check(NSEqualRects([[edited objectWithIdentifier:[field identifier]] rectForField:@"frame"],
                       NSMakeRect(1, 2, 300, 40)), @"edited frame is kept");
    Check([[edited data] isEqualToData:data], @"an edited archive is written back unchanged");
  }
}

/* The XIB editor's model: edits change only what they are about. */
static void TestInterfaceDocument(void)
{
  NSString *xib =
  @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
  @"<document type=\"com.apple.InterfaceBuilder3.Cocoa.XIB\" version=\"3.0\" toolsVersion=\"1\" targetRuntime=\"MacOSX.Cocoa\" useAutolayout=\"YES\">\n"
  @"<objects>\n"
  @"<customObject id=\"-2\" userLabel=\"File's Owner\" customClass=\"Controller\">\n"
  @"<connections><outlet property=\"label\" destination=\"lab-el-001\" id=\"out-le-t01\"/></connections>\n"
  @"</customObject>\n"
  @"<window title=\"Main\" id=\"win-do-w01\">\n"
  @"<view key=\"contentView\" id=\"con-te-nt1\">\n"
  @"<rect key=\"frame\" x=\"0.0\" y=\"0.0\" width=\"400\" height=\"300\"/>\n"
  @"<autoresizingMask key=\"autoresizingMask\"/>\n"
  @"<subviews>\n"
  @"<textField id=\"lab-el-001\">\n"
  @"<rect key=\"frame\" x=\"20\" y=\"260\" width=\"100\" height=\"16\"/>\n"
  @"<textFieldCell key=\"cell\" title=\"Name\" id=\"cel-l0-001\"><font key=\"font\" metaFont=\"system\"/></textFieldCell>\n"
  @"</textField>\n"
  @"</subviews>\n"
  @"<constraints>\n"
  @"<constraint firstItem=\"lab-el-001\" firstAttribute=\"leading\" secondItem=\"con-te-nt1\" secondAttribute=\"leading\" constant=\"20\" id=\"con-st-001\"/>\n"
  @"<constraint firstItem=\"lab-el-001\" firstAttribute=\"width\" constant=\"100\" priority=\"750\" id=\"con-st-002\"/>\n"
  @"</constraints>\n"
  @"</view>\n"
  @"</window>\n"
  @"</objects>\n"
  @"</document>\n";
  NSString            *error = nil;
  PCInterfaceDocument *doc = [PCInterfaceDocument documentWithData:[xib dataUsingEncoding:NSUTF8StringEncoding]
                                                             error:&error];
  NSXMLElement        *owner, *window, *label, *button;
  NSArray             *rows;
  BOOL                found = NO;

  Check(doc != nil, [NSString stringWithFormat:@"XIB model reads: %@", error]);
  Check([PCInterfaceDocument documentWithData:[@"<plist/>" dataUsingEncoding:NSUTF8StringEncoding] error:NULL] == nil,
        @"XIB model refuses other XML");
  owner = [doc objectWithIdentifier:@"-2"];
  window = [doc objectWithIdentifier:@"win-do-w01"];
  label = [doc objectWithIdentifier:@"lab-el-001"];
  Check([[doc nameOfObject:label] isEqual:@"Name"], @"object name from its cell title");
  Check([doc objectOfElement:(NSXMLElement *)[[[label elementsForName:@"rect"] objectAtIndex:0] self]] == label,
        @"object of an element");

  rows = [doc attributesOfObject:label];
  for (NSDictionary *row in rows)
  {
    if ([[row objectForKey:@"Label"] isEqual:@"frame.width"]) found = [[row objectForKey:@"Value"] isEqual:@"100"];
  }
  Check(found, @"attribute rows include frame.width");
  [doc setValue:@"YES" ofAttribute:@"hidden" ofElement:label];
  Check([[[label attributeForName:@"hidden"] stringValue] isEqual:@"YES"], @"attribute set");
  [doc setValue:@"" ofAttribute:@"hidden" ofElement:label];
  Check([label attributeForName:@"hidden"] == nil, @"empty value removes the attribute");
  {
    /* The inspector finds keyed children, and makes the ones a change needs. */
    NSXMLElement *cell = [doc childOfElement:label withKey:@"cell" creatingNamed:nil];
    NSXMLElement *font = [doc childOfElement:cell withKey:@"font" creatingNamed:@"font"];
    NSXMLElement *color;

    Check([[cell name] isEqual:@"textFieldCell"] && [[[font attributeForName:@"metaFont"] stringValue]
                                                     isEqual:@"system"], @"keyed children found");
    Check([doc childOfElement:cell withKey:@"textColor" creatingNamed:nil] == nil, @"missing child not made");
    color = [doc childOfElement:cell withKey:@"textColor" creatingNamed:@"color"];
    Check([[color name] isEqual:@"color"] && [color parent] == cell
          && [[[color attributeForName:@"key"] stringValue] isEqual:@"textColor"]
          && [doc childOfElement:cell withKey:@"textColor" creatingNamed:@"color"] == color,
          @"missing child made once");
    [color detach];
  }

  Check([[doc connectionsOfObject:label] count] == 1, @"incoming outlet listed");
  Check([[doc constraintsOfObject:label] count] == 2, @"constraints of the label");
  Check([[doc descriptionOfConstraint:[[doc constraintsOfObject:label] objectAtIndex:0]]
         isEqual:@"Name.leading = leading + 20"], @"constraint description");
  Check([[doc descriptionOfConstraint:[[doc constraintsOfObject:label] objectAtIndex:1]]
         isEqual:@"Name.width = 100 @750"], @"constant constraint description");
  {
    NSXMLElement *width = [[doc constraintsOfObject:label] objectAtIndex:1];
    NSData       *before = [doc data];

    Check([[doc itemsOfConstraint:[[doc constraintsOfObject:label] objectAtIndex:0]] count] == 2
          && [[doc itemsOfConstraint:width] isEqual:@[label]], @"views of constraints");
    Check([doc canRemoveObject:width], @"constraints can be removed");
    [doc removeObject:width];
    Check([[doc constraintsOfObject:label] count] == 1 && [doc objectWithIdentifier:@"lab-el-001"] != nil,
          @"removing a constraint keeps its view");
    doc = [PCInterfaceDocument documentWithData:before error:NULL];
    label = [doc objectWithIdentifier:@"lab-el-001"];
    window = [doc objectWithIdentifier:@"win-do-w01"];
    owner = [doc objectWithIdentifier:@"-2"];
  }

  button = [doc insertLibraryItem:@"Push Button" forObject:window];
  Check(button != nil && [[[button parent] name] isEqual:@"subviews"]
        && [[[button parent] parent] isEqual:[doc objectWithIdentifier:@"con-te-nt1"]],
        @"button added to the window's content view");
  Check([doc insertLibraryItem:@"Menu Item" forObject:window] == nil, @"no menu item in a window");
  Check([doc addAction:@"save" fromObject:button toObject:owner] != nil, @"action added");
  Check([[[[[doc connectionsOfObject:button] objectAtIndex:0] attributeForName:@"selector"] stringValue]
         isEqual:@"save:"], @"action selector gets its colon");
  Check([doc addOutlet:@"saveButton" fromObject:owner toObject:button] != nil, @"outlet added");
  Check([[doc connectionsOfObject:owner] count] == 3, @"owner has its outlets and the action to it");

  Check(![doc canRemoveObject:owner] && ![doc canRemoveObject:[doc objectWithIdentifier:@"con-te-nt1"]],
        @"placeholders and content views stay");
  [doc removeObject:label];
  Check([doc objectWithIdentifier:@"lab-el-001"] == nil && [doc objectWithIdentifier:@"cel-l0-001"] == nil,
        @"label and its cell removed");
  Check([[doc connectionsOfObject:owner] count] == 2, @"outlet to the label removed");
  Check([[[[doc XMLDocument] rootElement] XMLString] rangeOfString:@"con-st-00"].location == NSNotFound,
        @"constraints of the label removed");
  Check([PCInterfaceDocument documentWithData:[doc data] error:NULL] != nil, @"edited XIB reads again");
  {
    NSMutableSet *ids = [NSMutableSet set];
    NSUInteger   i;

    for (i = 0; i < 200; i++)
    {
      [ids addObject:[doc uniqueIdentifier]];
    }
    Check([ids count] > 190 && [[ids anyObject] length] == 10, @"identifiers in Xcode's form");
  }
}

/* Every XIB of ProjectCenter is written back as it was read, also after an
 * object and a connection are added and removed again. */
/* The constraint names Xcode's document outline showed for this XIB. */
static void TestConstraintNames(void)
{
  NSString *xib =
  @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
  @"<document type=\"com.apple.InterfaceBuilder3.Cocoa.XIB\" version=\"3.0\" toolsVersion=\"23504\""
  @" targetRuntime=\"MacOSX.Cocoa\" useAutolayout=\"YES\">\n"
  @"<objects>\n"
  @"<window title=\"Form\" id=\"win\">\n"
  @"<view key=\"contentView\" id=\"v\">\n"
  @"<rect key=\"frame\" x=\"0.0\" y=\"0.0\" width=\"320\" height=\"120\"/>\n"
  @"<subviews>\n"
  @"<textField id=\"n\"><rect key=\"frame\" x=\"18\" y=\"84\" width=\"104\" height=\"16\"/>\n"
  @"<constraints>\n"
  @"<constraint firstAttribute=\"width\" constant=\"100\" priority=\"750\" id=\"c1\"/>\n"
  @"<constraint firstAttribute=\"height\" relation=\"lessThanOrEqual\" constant=\"40\" id=\"c2\"/>\n"
  @"</constraints>\n"
  @"<textFieldCell key=\"cell\" title=\"Name\" id=\"nc\"/>\n"
  @"</textField>\n"
  @"<popUpButton id=\"pop\" userLabel=\"GormNSPopUpButton\"><rect key=\"frame\" x=\"110\" y=\"270\" width=\"110\" height=\"24\"/>\n"
  @"<popUpButtonCell key=\"cell\" type=\"push\" title=\"Item 1\" id=\"popc\"/>\n"
  @"</popUpButton>\n"
  @"<button id=\"ok\"><rect key=\"frame\" x=\"130\" y=\"76\" width=\"96\" height=\"32\"/>\n"
  @"<buttonCell key=\"cell\" type=\"push\" title=\"OK\" id=\"okc\"/>\n"
  @"</button>\n"
  @"<customView id=\"box\" userLabel=\"Box\"><rect key=\"frame\" x=\"20\" y=\"20\" width=\"160\" height=\"40\"/></customView>\n"
  @"</subviews>\n"
  @"<constraints>\n"
  @"<constraint firstItem=\"n\" firstAttribute=\"leading\" secondItem=\"v\" secondAttribute=\"leading\" constant=\"20\" id=\"c3\"/>\n"
  @"<constraint firstItem=\"ok\" firstAttribute=\"leading\" secondItem=\"n\" secondAttribute=\"trailing\" constant=\"8\" id=\"c4\"/>\n"
  @"<constraint firstItem=\"ok\" firstAttribute=\"centerY\" secondItem=\"n\" secondAttribute=\"centerY\" id=\"c5\"/>\n"
  @"<constraint firstItem=\"box\" firstAttribute=\"width\" secondItem=\"v\" secondAttribute=\"width\" multiplier=\"0.5\" id=\"c6\"/>\n"
  @"<constraint firstAttribute=\"bottom\" secondItem=\"box\" secondAttribute=\"bottom\" constant=\"20\" id=\"c7\"/>\n"
  @"<constraint firstItem=\"ok\" firstAttribute=\"width\" relation=\"greaterThanOrEqual\" secondItem=\"n\""
  @" secondAttribute=\"width\" priority=\"250\" constant=\"-10\" id=\"c8\"/>\n"
  @"<constraint firstItem=\"box\" firstAttribute=\"leading\" secondItem=\"v\" secondAttribute=\"leadingMargin\" id=\"c9\"/>\n"
  @"<constraint firstItem=\"box\" firstAttribute=\"top\" secondItem=\"pop\" secondAttribute=\"bottom\" constant=\"8\" symbolic=\"YES\" id=\"c10\"/>\n"
  @"<constraint firstAttribute=\"trailing\" secondItem=\"box\" secondAttribute=\"trailing\" constant=\"-2\" id=\"c11\"/>\n"
  @"</constraints>\n"
  @"</view>\n"
  @"</window>\n"
  @"</objects>\n"
  @"</document>\n";
  PCInterfaceDocument *doc = [PCInterfaceDocument documentWithData:[xib dataUsingEncoding:NSUTF8StringEncoding]
                                                             error:NULL];
  NSDictionary        *expected = [NSDictionary dictionaryWithObjectsAndKeys:
                                   @"width = 100 @750", @"c1",
                                   @"height ≤ 40", @"c2",
                                   @"Name.leading = leading + 20", @"c3",
                                   @"OK.leading = Name.trailing + 8", @"c4",
                                   @"OK.centerY = Name.centerY", @"c5",
                                   @"Box.width = 0.5 × width", @"c6",
                                   @"bottom = Box.bottom + 20", @"c7",
                                   @"OK.width ≥ Name.width - 10 @250", @"c8",
                                   @"Box.leading = leadingMargin", @"c9",
                                   @"Box.top = GormNSPopUpButton.bottom", @"c10",
                                   @"trailing = Box.trailing - 2", @"c11",
                                   nil];
  NSMutableDictionary *constraints = [NSMutableDictionary dictionary];

  Check(doc != nil, @"constraint XIB reads");
  for (NSXMLElement *object in [doc objects])
  {
    for (NSXMLElement *constraint in [doc constraintsOfObject:object])
    {
      [constraints setObject:constraint forKey:[[constraint attributeForName:@"id"] stringValue]];
    }
  }
  for (NSString *identifier in expected)
  {
    NSString *name = [doc descriptionOfConstraint:[constraints objectForKey:identifier]];

    Check([name isEqual:[expected objectForKey:identifier]],
          [NSString stringWithFormat:@"constraint %@ named as in Xcode: %@", identifier, name]);
  }
  Check([[doc nameOfObject:[doc objectWithIdentifier:@"v"]] isEqual:@"View"]
        && [[doc nameOfObject:[doc objectWithIdentifier:@"box"]] isEqual:@"Box"]
        && [[doc nameOfObject:[doc objectWithIdentifier:@"pop"]] isEqual:@"GormNSPopUpButton"],
        @"object names as in Xcode, the label before the title");

  /* The inspector's view of constraints. */
  {
    NSXMLElement *c1 = [constraints objectForKey:@"c1"], *c4 = [constraints objectForKey:@"c4"];
    NSXMLElement *c5 = [constraints objectForKey:@"c5"], *c10 = [constraints objectForKey:@"c10"];
    NSXMLElement *c11 = [constraints objectForKey:@"c11"];
    NSXMLElement *view = [doc objectWithIdentifier:@"v"], *box = [doc objectWithIdentifier:@"box"];
    NSXMLElement *name = [doc objectWithIdentifier:@"n"];

    Check([[doc kindOfConstraint:c11] isEqual:@"Horizontal Space Constraint"]
          && [[doc kindOfConstraint:c10] isEqual:@"Vertical Space Constraint"]
          && [[doc kindOfConstraint:c1] isEqual:@"Width Constraint"]
          && [[doc kindOfConstraint:c5] isEqual:@"Center Y Alignment Constraint"]
          && [[doc kindOfConstraint:[constraints objectForKey:@"c8"]] isEqual:@"Equal Widths Constraint"],
          @"constraint kinds");
    Check([doc ownerOfConstraint:c11] == view && [doc firstItemOfConstraint:c11] == view
          && [doc ownerOfConstraint:c1] == name, @"constraint owners");
    Check([[doc candidateItemsForConstraint:c11] count] == 5
          && [[doc candidateItemsForConstraint:c11] objectAtIndex:0] == view, @"constraint candidates");
    Check([[PCInterfaceDocument titleOfConstraintAttribute:@"centerX"] isEqual:@"Center X"]
          && [[PCInterfaceDocument titleOfConstraintAttribute:@"leadingMargin"] isEqual:@"Leading Margin"],
          @"attribute titles");

    [doc setFirstItem:box attribute:@"trailing" ofConstraint:c11];
    [doc setSecondItem:view attribute:@"trailing" ofConstraint:c11];
    Check([[doc descriptionOfConstraint:c11] isEqual:@"Box.trailing = trailing - 2"], @"constraint items swapped");
    [doc setFirstItem:view attribute:@"trailing" ofConstraint:c11];
    Check([c11 attributeForName:@"firstItem"] == nil, @"the owner as first item is left out");
    [doc setSecondItem:nil attribute:nil ofConstraint:c4];
    Check([c4 attributeForName:@"secondItem"] == nil && [c4 attributeForName:@"secondAttribute"] == nil,
          @"constraint without second item");
    [doc setNumber:@"12" ofAttribute:@"constant" ofConstraint:c10];
    Check([c10 attributeForName:@"symbolic"] == nil
          && [[doc descriptionOfConstraint:c10] isEqual:@"Box.top = GormNSPopUpButton.bottom + 12"],
          @"a constant replaces the standard spacing");
    [doc setValue:@"greaterThanOrEqual" ofAttribute:@"relation" ofElement:c11];
    [doc setNumber:@"250" ofAttribute:@"priority" ofConstraint:c11];
    Check([[[c11 XMLString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
           hasPrefix:@"<constraint firstAttribute=\"trailing\" relation=\"greaterThanOrEqual\""
           @" secondItem=\"v\" secondAttribute=\"trailing\" priority=\"250\" constant=\"-2\" id=\"c11\""],
          [NSString stringWithFormat:@"constraint attributes in Xcode's order: %@", [c11 XMLString]]);
    [doc setNumber:@"1000" ofAttribute:@"priority" ofConstraint:c1];
    [doc setNumber:@"0" ofAttribute:@"constant" ofConstraint:c10];
    Check([c1 attributeForName:@"priority"] == nil && [c10 attributeForName:@"constant"] == nil,
          @"default numbers are left out");
  }
}

static void TestInterfaceDocumentRoundTrip(void)
{
  NSString              *repository = [[[NSString stringWithUTF8String:__FILE__]
                                        stringByDeletingLastPathComponent]
                                       stringByDeletingLastPathComponent];
  NSDirectoryEnumerator *files = [[NSFileManager defaultManager] enumeratorAtPath:repository];
  NSString              *file;
  NSUInteger            count = 0;

  while ((file = [files nextObject]))
  {
    NSData              *data;
    PCInterfaceDocument *doc;
    NSXMLElement        *window = nil, *button, *owner;

    if (![file hasSuffix:@".xib"] || [file hasPrefix:@"build"])
    {
      continue;
    }
    data = [NSData dataWithContentsOfFile:[repository stringByAppendingPathComponent:file]];
    doc = [PCInterfaceDocument documentWithData:data error:NULL];
    Check(doc != nil, [NSString stringWithFormat:@"%@ reads as a XIB", file]);
    Check([[doc data] isEqualToData:data], [NSString stringWithFormat:@"%@ is written back unchanged", file]);
    for (NSXMLElement *object in [doc objects])
    {
      if ([[object name] isEqual:@"window"]) { window = object; break; }
    }
    owner = [doc objectWithIdentifier:@"-2"];
    if (window && owner)
    {
      NSXMLElement *action;

      button = [doc insertLibraryItem:@"Push Button" forObject:window];
      action = [doc addAction:@"test" fromObject:button toObject:owner];
      Check(button != nil && action != nil, [NSString stringWithFormat:@"%@: button and action added", file]);
      Check([PCInterfaceDocument documentWithData:[doc data] error:NULL] != nil,
            [NSString stringWithFormat:@"%@: edited XIB reads", file]);
      [doc removeObject:button];
      Check([[doc data] isEqualToData:data],
            [NSString stringWithFormat:@"%@ is as before after adding and removing a button", file]);
    }
    count++;
  }
  Check(count >= 30, @"the .xib files of ProjectCenter are found");
}

static void Write(NSString *root, NSString *path, NSString *contents)
{
  NSString *file = [root stringByAppendingPathComponent:path];
  [[NSFileManager defaultManager] createDirectoryAtPath:[file stringByDeletingLastPathComponent]
                            withIntermediateDirectories:YES attributes:nil error:NULL];
  Check([contents writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:NULL], path);
}

/* The GNUstep settings beside an Xcode project, which the General pane
 * edits, and the themes it offers. */
static void TestGNUstepSettings(void)
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString      *root = [NSTemporaryDirectory() stringByAppendingPathComponent:
                         [[NSProcessInfo processInfo] globallyUniqueString]];
  NSString      *bundle = [root stringByAppendingPathComponent:@"Sample.xcodeproj"];
  NSString      *file = [root stringByAppendingPathComponent:@"GNUstep/ProjectCenter.plist"];
  NSString      *error = nil;
  NSDictionary  *dict;
  NSArray       *themes;

  Write(root, @"Sample.xcodeproj/project.pbxproj", @"{objectVersion=77; rootObject=PROJ; objects={"
        "PROJ={isa=PBXProject;mainGroup=ROOT;targets=(APP);};"
        "APP={isa=PBXNativeTarget;name=Sample;productType=\"com.apple.product-type.application\";};"
        "ROOT={isa=PBXGroup;children=();sourceTree=\"<group>\";};};}");
  Check([[PCXcodeProject GNUstepSettingsOfProjectAtPath:bundle] count] == 0, @"no settings file");
  Check([PCXcodeProject setGNUstepSetting:@"GTK4 \"Native\"" forKey:@"Theme" ofProjectAtPath:bundle error:&error],
        error);
  Check([PCXcodeProject setGNUstepSetting:@"scripts/build.sh" forKey:@"BuildScript"
                          ofProjectAtPath:[bundle stringByAppendingPathComponent:@"project.pbxproj"] error:&error],
        error);
  Check([[NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:NULL]
         isEqual:@"{\n    BuildScript = \"scripts/build.sh\";\n    Theme = \"GTK4 \\\"Native\\\"\";\n}\n"],
        @"settings written as an OpenStep property list, sorted and quoted");
  dict = [PCXcodeProject projectAtPath:bundle error:&error];
  Check([[dict objectForKey:@"XCODE_Theme"] isEqual:@"GTK4 \"Native\""]
        && [[dict objectForKey:@"XCODE_BuildScript"] isEqual:[root stringByAppendingPathComponent:@"scripts/build.sh"]],
        @"the project reads the theme, and the build script's path is resolved");
  Check([[PCXcodeProject launchArgumentsForProject:dict] isEqual:(@[@"-GSTheme", @"GTK4 \"Native\""])],
        @"Run passes the theme");
  NSDictionary *baseEnvironment = @{@"PATH": @"/example/tools", @"GNUSTEP_APPLICATION_THEME": @"ParentTheme"};
  NSDictionary *buildEnvironment = [PCXcodeProject buildEnvironmentForProject:dict baseEnvironment:baseEnvironment];
  Check([[buildEnvironment objectForKey:@"GNUSTEP_APPLICATION_THEME"] isEqual:@"GTK4 \"Native\""]
        && [[buildEnvironment objectForKey:@"PATH"] isEqual:@"/example/tools"]
        && [[baseEnvironment objectForKey:@"GNUSTEP_APPLICATION_THEME"] isEqual:@"ParentTheme"],
        @"Build passes the selected provider to scripts/make without mutating its base environment");
  Check([[PCXcodeProject buildEnvironmentForProject:@{} baseEnvironment:baseEnvironment]
         objectForKey:@"GNUSTEP_APPLICATION_THEME"] == nil, @"Default clears an inherited theme override");
  Check([PCXcodeProject setGNUstepSetting:@"" forKey:@"Theme" ofProjectAtPath:bundle error:&error]
        && [[PCXcodeProject GNUstepSettingsOfProjectAtPath:bundle] objectForKey:@"Theme"] == nil
        && [[PCXcodeProject launchArgumentsForProject:[PCXcodeProject projectAtPath:bundle error:NULL]] count] == 0,
        @"Default removes the theme");
  Check([PCXcodeProject setGNUstepSetting:nil forKey:@"BuildScript" ofProjectAtPath:bundle error:&error]
        && ![fm fileExistsAtPath:[file stringByDeletingLastPathComponent]],
        @"the file, and the empty GNUstep folder, go with the last setting");
  Write(root, @"GNUstep/ProjectCenter.plist", @"{ broken");
  Check(![PCXcodeProject setGNUstepSetting:@"X" forKey:@"Theme" ofProjectAtPath:bundle error:&error]
        && [error length]
        && [[NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:NULL] isEqual:@"{ broken"],
        @"an unreadable file is not overwritten");

  Write(root, @"Local/Themes/GTK4Native.theme/Resources/Info-gnustep.plist", @"{}");
  Write(root, @"User/Themes/Neos.theme/Resources/Info-gnustep.plist", @"{}");
  Write(root, @"User/Themes/GTK4Native.theme/Resources/Info-gnustep.plist", @"{}");
  Write(root, @"User/Themes/notes.txt", @"not a theme");
  themes = [PCXcodeProject themesInLibraries:@[[root stringByAppendingPathComponent:@"User"],
                                                [root stringByAppendingPathComponent:@"Local"],
                                                [root stringByAppendingPathComponent:@"Missing"]]];
  Check([themes isEqual:(@[@"GTK4Native", @"Neos"])],
        [NSString stringWithFormat:@"themes of every Library folder, once each: %@", themes]);
  [fm removeItemAtPath:root error:NULL];
}

/* "My Mac (GNUstep)": finding GNUstep and the environment of GNUstep.sh. */
static void TestGNUstepOnMac(void)
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString      *root = [NSTemporaryDirectory() stringByAppendingPathComponent:
                         [[NSProcessInfo processInfo] globallyUniqueString]];
  NSString      *makefiles = [root stringByAppendingPathComponent:@"GNUstep/Makefiles"];
  NSString      *tools = [root stringByAppendingPathComponent:@"Tools"];
  NSString      *missing = [root stringByAppendingPathComponent:@"Missing"];
  NSDictionary  *environment;

  Write(root, @"GNUstep/Makefiles/GNUstep.sh",
        [NSString stringWithFormat:@"GNUSTEP_MAKEFILES='%@'\nexport GNUSTEP_MAKEFILES\n"
         @"PC_TEST_LINES='first\nsecond'\nexport PC_TEST_LINES\necho noise\n", makefiles]);
  Write(root, @"Tools/gnustep-config", [NSString stringWithFormat:
        @"#!/bin/sh\n[ \"$1\" = --variable=GNUSTEP_MAKEFILES ] && echo '%@'\n", makefiles]);
  [fm setAttributes:@{NSFilePosixPermissions: @0755}
       ofItemAtPath:[tools stringByAppendingPathComponent:@"gnustep-config"] error:NULL];

  Check([[PCXcodeProject GNUstepMakefilesWithEnvironment:@{@"GNUSTEP_MAKEFILES": makefiles}
                                             toolFolders:@[] makefileFolders:@[]] isEqual:makefiles],
        @"GNUSTEP_MAKEFILES of the environment");
  Check([[PCXcodeProject GNUstepMakefilesWithEnvironment:@{@"PATH": [NSString stringWithFormat:@"%@:%@", missing, tools]}
                                             toolFolders:@[] makefileFolders:@[]] isEqual:makefiles],
        @"gnustep-config on the PATH");
  Check([[PCXcodeProject GNUstepMakefilesWithEnvironment:@{@"GNUSTEP_MAKEFILES": missing}
                                             toolFolders:@[missing, tools] makefileFolders:@[]] isEqual:makefiles],
        @"gnustep-config in the usual tool folders, past a wrong GNUSTEP_MAKEFILES");
  Check([[PCXcodeProject GNUstepMakefilesWithEnvironment:@{} toolFolders:@[]
                                         makefileFolders:@[missing, makefiles]] isEqual:makefiles],
        @"a usual makefile folder");
  Check([PCXcodeProject GNUstepMakefilesWithEnvironment:@{} toolFolders:@[missing]
                                         makefileFolders:@[missing]] == nil, @"no GNUstep");

  environment = [PCXcodeProject GNUstepEnvironmentForMakefiles:makefiles];
  Check([[environment objectForKey:@"GNUSTEP_MAKEFILES"] isEqual:makefiles]
        && [[environment objectForKey:@"PC_TEST_LINES"] isEqual:@"first\nsecond"]
        && [environment objectForKey:@"HOME"] != nil,
        [NSString stringWithFormat:@"the environment GNUstep.sh sets up: %@", environment]);
  Check([PCXcodeProject GNUstepEnvironmentForMakefiles:missing] == nil, @"no environment without GNUstep.sh");

  /* The GNUstep chosen in the preferences: a prefix of any layout, the
   * folder of GNUstep.sh or GNUstep.sh itself. */
  {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString       *fhs = [root stringByAppendingPathComponent:@"fhs"];
    NSString       *fhsMakefiles = [[fhs stringByAppendingPathComponent:@"share/GNUstep/Makefiles"]
                                    stringByStandardizingPath];
    NSString       *layout = [root stringByAppendingPathComponent:@"gnustep"];
    NSString       *layoutMakefiles = [[layout stringByAppendingPathComponent:@"System/Library/Makefiles"]
                                       stringByStandardizingPath];

    Write(root, @"fhs/share/GNUstep/Makefiles/GNUstep.sh", @"true\n");
    Write(root, @"gnustep/System/Library/Makefiles/GNUstep.sh", @"true\n");
    Check([[PCXcodeProject GNUstepMakefilesInFolder:fhs] isEqual:fhsMakefiles]
          && [[PCXcodeProject GNUstepMakefilesInFolder:layout] isEqual:layoutMakefiles],
          @"the Makefiles folder of an fhs or gnustep prefix");
    Check([[PCXcodeProject GNUstepMakefilesInFolder:fhsMakefiles] isEqual:fhsMakefiles]
          && [[PCXcodeProject GNUstepMakefilesInFolder:[fhsMakefiles stringByAppendingPathComponent:@"GNUstep.sh"]]
              isEqual:fhsMakefiles]
          && [[PCXcodeProject GNUstepMakefilesInFolder:[NSString stringWithFormat:@"  %@/ ", fhs]]
              isEqual:fhsMakefiles],
          @"the folder of GNUstep.sh, GNUstep.sh itself, and spaces around");
    Check([PCXcodeProject GNUstepMakefilesInFolder:missing] == nil
          && [PCXcodeProject GNUstepMakefilesInFolder:@""] == nil
          && [PCXcodeProject GNUstepMakefilesInFolder:nil] == nil, @"no GNUstep.sh in a folder");

    [defaults setObject:layout forKey:PCGNUstepDefault];
    Check([[PCXcodeProject chosenGNUstep] isEqual:layout]
          && [[PCXcodeProject GNUstepMakefiles] isEqual:layoutMakefiles], @"the chosen GNUstep is used");
    [defaults setObject:missing forKey:PCGNUstepDefault];
    Check([PCXcodeProject GNUstepMakefiles] == nil && [PCXcodeProject GNUstepEnvironment] == nil,
          @"a chosen folder without GNUstep.sh is no GNUstep, not another one");
    [defaults setObject:@" " forKey:PCGNUstepDefault];
    Check([PCXcodeProject chosenGNUstep] == nil
          && ([PCXcodeProject GNUstepMakefiles] == [PCXcodeProject foundGNUstepMakefiles]),
          @"an empty choice finds GNUstep");
    [defaults removeObjectForKey:PCGNUstepDefault];
  }
#ifndef GNUSTEP
  Check(![PCXcodeProject buildsWithGNUstepForProject:@{@"PROJECT_NAME": @"Plain"}],
        @"a ProjectCenter project on macOS has no destination");
#endif
  [fm removeItemAtPath:root error:NULL];
}

/* The exit status of a shell command. */
static int Shell(NSString *command)
{
  NSTask *task = [[[NSTask alloc] init] autorelease];

  [task setLaunchPath:@"/bin/sh"];
  [task setArguments:@[@"-c", command]];
  [task setStandardOutput:[NSFileHandle fileHandleWithNullDevice]];
  [task launch];
  [task waitUntilExit];
  return [task terminationStatus];
}

/* Deployment: the platforms in GNUstep/ProjectCenter.plist, their defaults,
 * and the Archive scripts, run with a stand-in toolchain. */
static void TestDeployment(void)
{
  NSFileManager       *fm = [NSFileManager defaultManager];
  NSString            *root = [[NSTemporaryDirectory() stringByAppendingPathComponent:
                                [[NSProcessInfo processInfo] globallyUniqueString]] stringByResolvingSymlinksInPath];
  NSString            *bundle, *error = nil, *text, *script, *folder;
  NSDictionary        *projectDict, *scripts, *debian, *container, *overview, *macTarget, *linuxTarget;
  NSMutableDictionary *tarball, *windows, *compiled, *boxed;
  NSArray             *list;
  NSString            *repository = [[[NSString stringWithUTF8String:__FILE__]
                                      stringByDeletingLastPathComponent]
                                     stringByDeletingLastPathComponent];
  NSString            *standIn;

  /* ProjectCenter's compiler and image, which the tool has no bundle for. */
  setenv("PROJECTCENTER_RESOURCES",
         [[repository stringByAppendingPathComponent:@"Framework/Resources"] fileSystemRepresentation], 1);
  [fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:NULL];
  root = [root stringByResolvingSymlinksInPath];
  bundle = [root stringByAppendingPathComponent:@"Sample.xcodeproj"];
  Write(root, @"Sample.xcodeproj/project.pbxproj", @"{objectVersion=77; rootObject=PROJ; objects={"
        "PROJ={isa=PBXProject;mainGroup=ROOT;targets=(APP, LNX);buildConfigurationList=PL;};"
        "PL={isa=XCConfigurationList;buildConfigurations=(PR);};"
        "PR={isa=XCBuildConfiguration;name=Release;buildSettings={MARKETING_VERSION=\"2.1\";};};"
        "APP={isa=PBXNativeTarget;name=Sample;productName=Sample;buildConfigurationList=TL;"
        "productType=\"com.apple.product-type.application\";};"
        "TL={isa=XCConfigurationList;buildConfigurations=(TR);};"
        "TR={isa=XCBuildConfiguration;name=Release;buildSettings={\n\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME) App\";\n\t\t\t};};"
        "LNX={isa=PBXNativeTarget;name=\"Sample Linux\";productName=Sample;buildConfigurationList=LL;"
        "productType=\"com.apple.product-type.application\";};"
        "LL={isa=XCConfigurationList;buildConfigurations=(LD, LR);};"
        "LD={isa=XCBuildConfiguration;name=Debug;buildSettings={\n\t\t\t\tPRODUCT_NAME = Sample;\n\t\t\t\tSDKROOT = linux;\n\t\t\t};};"
        "LR={isa=XCBuildConfiguration;name=Release;buildSettings={\n\t\t\t\tPRODUCT_NAME = Sample;\n\t\t\t\tSDKROOT = linux;\n\t\t\t};};"
        "ROOT={isa=PBXGroup;children=();sourceTree=\"<group>\";};};}");
  /* A build script that makes the bundle where GNUSTEP_BUILD_DIR says. */
  Write(root, @"build.sh", @"for argument; do case \"$argument\" in GNUSTEP_BUILD_DIR=*) dir=${argument#*=};; esac; done\n"
        "mkdir -p \"$dir/Sample.app\" && echo binary > \"$dir/Sample.app/Sample\" && echo exe > \"$dir/Sample.app/Sample.exe\"\n");
  Write(root, @"Toolchain/GNUstep.sh", @"PC_TOOLCHAIN=yes\n");
  Write(root, @"GNUstep/ProjectCenter.plist", @"{BuildScript=build.sh;}");
  projectDict = [PCXcodeProject projectAtPath:bundle error:&error];
  Check(projectDict != nil, error);

  /* Targets: SDKROOT = linux makes the Linux target. */
  overview = [PCXcodeProject overviewOfProjectAtPath:bundle error:&error];
  macTarget = [[overview objectForKey:@"Targets"] objectAtIndex:0];
  linuxTarget = [PCXcodeProject linuxTargetOfOverview:overview];
  Check([[PCXcodeProject platformOfTarget:macTarget] isEqual:@"macOS"]
        && [[linuxTarget objectForKey:@"Name"] isEqual:@"Sample Linux"], @"a Mac and a Linux target");
  list = [PCDeployment deploymentsOfProjectAtPath:bundle];
  Check([list count] == 1 && [[[list objectAtIndex:0] objectForKey:@"Kind"] isEqual:@"macOS"]
        && [[[list objectAtIndex:0] objectForKey:@"Name"] isEqual:@"macOS"],
        [NSString stringWithFormat:@"a Mac application target archives for macOS, no distribution yet: %@", list]);

  Check([[[PCDeployment productOfProject:projectDict] objectForKey:@"Version"] isEqual:@"2.1"]
        && [[[PCDeployment productOfProject:projectDict] objectForKey:@"Product"] isEqual:@"Sample App"],
        [NSString stringWithFormat:@"the product's name and version: %@", [PCDeployment productOfProject:projectDict]]);
  Check([[[[PCDeployment fieldsForKind:@"Debian"] objectAtIndex:1] objectForKey:@"Key"] isEqual:@"Kind"]
        && [[[[PCDeployment fieldsForKind:@"Debian"] objectAtIndex:2] objectForKey:@"Key"] isEqual:@"Architectures"]
        && [[[PCDeployment fieldsForKind:@"macOS"] valueForKey:@"Key"] containsObject:@"Architectures"]
        && [[[PCDeployment fieldsForKind:@"macOS"] filteredArrayUsingPredicate:
             [NSPredicate predicateWithFormat:@"Key != nil"]] count] == 1,
        @"a distribution's form starts with it and the architectures; macOS has only those");
  Check([[PCDeployment buildSettingForKey:@"PackageName" ofKind:@"Debian"] isEqual:@"GNUSTEP_DEBIAN_PACKAGE_NAME"]
        && [[PCDeployment buildSettingForKey:@"AutomaticDependencies" ofKind:@"RPM"]
            isEqual:@"GNUSTEP_RPM_AUTOMATIC_DEPENDENCIES"]
        && [[PCDeployment buildSettingForKey:@"FileName" ofKind:@"Linux"] isEqual:@"GNUSTEP_TARBALL_FILE_NAME"]
        && [[PCDeployment buildSettingForKey:@"Architectures" ofKind:@"macOS"] isEqual:@"ARCHS"]
        && [PCDeployment buildSettingForKey:@"Name" ofKind:@"Debian"] == nil
        && [PCDeployment buildSettingForKey:@"Target" ofKind:@"RPM"] == nil
        && [PCDeployment buildSettingForKey:@"Maintainer" ofKind:@"RPM"] == nil,
        @"the build setting of each setting");
  {
    NSDictionary *own = @{@"Kind": @"Debian", @"Architectures": @"x86_64", @"Configuration": @"Beta",
                          @"Maintainer": @"Me", @"Build": @"Container"};
    NSDictionary *rpm = [PCDeployment deployment:own changedToKind:@"RPM"];

    Check([[rpm objectForKey:@"Configuration"] isEqual:@"Beta"] && [[rpm objectForKey:@"Build"] isEqual:@"Container"]
          && [[rpm objectForKey:@"Architectures"] isEqual:@"x86_64"] && [rpm objectForKey:@"Maintainer"] == nil,
          [NSString stringWithFormat:@"Debian made RPM keeps the shared settings: %@", rpm]);
    Check([PCDeployment deployment:own changedToKind:@"Nothing"] == nil
          && [PCDeployment deployment:own changedToKind:@"Debian"] == own, @"an unknown or unchanged kind");
  }

  /* Distributions, written as build settings of the Linux target. */
  Check([PCDeployment addDistribution:@"Debian" toTarget:linuxTarget projectAtPath:bundle error:&error]
        && [PCDeployment addDistribution:@"RPM" toTarget:linuxTarget projectAtPath:bundle error:&error], error);
  Check(![PCDeployment addDistribution:@"macOS" toTarget:linuxTarget projectAtPath:bundle error:&error],
        @"only Linux distributions in a Linux target");
  linuxTarget = [PCXcodeProject linuxTargetOfOverview:[PCXcodeProject overviewOfProjectAtPath:bundle error:NULL]];
  debian = [[PCDeployment deploymentsOfTarget:linuxTarget] objectAtIndex:0];
  Check([PCDeployment setValue:@"Me <me@example.com>" forKey:@"Maintainer" ofDeployment:debian target:linuxTarget
                 projectAtPath:bundle error:&error]
        && [PCDeployment setValue:@"x86_64 aarch64" forKey:@"Architectures" ofDeployment:debian target:linuxTarget
                    projectAtPath:bundle error:&error]
        && [PCDeployment setValue:@"Beta" forKey:@"Configuration"
                     ofDeployment:[[PCDeployment deploymentsOfTarget:linuxTarget] objectAtIndex:1]
                           target:linuxTarget projectAtPath:bundle error:&error], error);
  text = [NSString stringWithContentsOfFile:[bundle stringByAppendingPathComponent:@"project.pbxproj"]
                                   encoding:NSUTF8StringEncoding error:NULL];
  Check([[text componentsSeparatedByString:@"GNUSTEP_DEBIAN_MAINTAINER = \"Me <me@example.com>\";"] count] == 3
        && [[text componentsSeparatedByString:@"GNUSTEP_DISTRIBUTIONS = \"Debian RPM\";"] count] == 3
        && [[text componentsSeparatedByString:@"ARCHS = \"x86_64 aarch64\";"] count] == 3,
        [NSString stringWithFormat:@"written into both configurations of the Linux target: %@", text]);
  linuxTarget = [PCXcodeProject linuxTargetOfOverview:[PCXcodeProject overviewOfProjectAtPath:bundle error:NULL]];
  list = [PCDeployment deploymentsOfTarget:linuxTarget];
  Check([[list valueForKey:@"Kind"] isEqual:(@[@"Debian", @"RPM"])]
        && [[[list objectAtIndex:0] objectForKey:@"Maintainer"] isEqual:@"Me <me@example.com>"]
        && [[[list objectAtIndex:1] objectForKey:@"Configuration"] isEqual:@"Beta"]
        && [[[list objectAtIndex:1] objectForKey:@"Architectures"] isEqual:@"x86_64 aarch64"],
        [NSString stringWithFormat:@"read back from the target: %@", list]);
  list = [PCDeployment deploymentsOfProjectAtPath:bundle];
  Check([[list valueForKey:@"Name"] isEqual:(@[@"macOS", @"Debian / Ubuntu (amd64)", @"Debian / Ubuntu (arm64)",
                                              @"Fedora / openSUSE (x86_64)", @"Fedora / openSUSE (aarch64)"])]
        && [[[list objectAtIndex:2] objectForKey:@"Architecture"] isEqual:@"arm64"],
        [NSString stringWithFormat:@"Archive: each distribution once per architecture, in its words: %@",
         [list valueForKey:@"Name"]]);

  /* Changing and removing a distribution takes its settings along. */
  Check(![PCDeployment changeDistribution:[[PCDeployment deploymentsOfTarget:linuxTarget] objectAtIndex:1]
                                   toKind:@"Debian" ofTarget:linuxTarget projectAtPath:bundle error:&error],
        @"a distribution the target has already is refused");
  Check([PCDeployment changeDistribution:[[PCDeployment deploymentsOfTarget:linuxTarget] objectAtIndex:1]
                                  toKind:@"Linux" ofTarget:linuxTarget projectAtPath:bundle error:&error], error);
  linuxTarget = [PCXcodeProject linuxTargetOfOverview:[PCXcodeProject overviewOfProjectAtPath:bundle error:NULL]];
  Check([[PCDeployment distributionsOfTarget:linuxTarget] isEqual:(@[@"Debian", @"Linux"])]
        && [[PCXcodeProject buildSetting:@"GNUSTEP_TARBALL_CONFIGURATION" ofTarget:linuxTarget] isEqual:@"Beta"]
        && [PCXcodeProject buildSetting:@"GNUSTEP_RPM_CONFIGURATION" ofTarget:linuxTarget] == nil
        && [PCXcodeProject buildSetting:@"GNUSTEP_TARBALL_TARGET" ofTarget:linuxTarget] == nil,
        @"RPM made a tarball, in its place, with its settings");
  Check([PCDeployment removeDistribution:@"Debian" fromTarget:linuxTarget projectAtPath:bundle error:&error], error);
  linuxTarget = [PCXcodeProject linuxTargetOfOverview:[PCXcodeProject overviewOfProjectAtPath:bundle error:NULL]];
  Check([[PCDeployment distributionsOfTarget:linuxTarget] isEqual:(@[@"Linux"])]
        && [PCXcodeProject buildSetting:@"GNUSTEP_DEBIAN_MAINTAINER" ofTarget:linuxTarget] == nil,
        @"a removed distribution leaves no settings");

  /* The Mac target: only its ARCHS. */
  Check([PCDeployment setValue:@"arm64" forKey:@"Architectures"
                  ofDeployment:[[PCDeployment deploymentsOfTarget:macTarget] objectAtIndex:0]
                        target:macTarget projectAtPath:bundle error:&error], error);
  macTarget = [[[PCXcodeProject overviewOfProjectAtPath:bundle error:NULL] objectForKey:@"Targets"] objectAtIndex:0];
  Check([[[[PCDeployment deploymentsOfTarget:macTarget] objectAtIndex:0] objectForKey:@"Architectures"] isEqual:@"arm64"]
        && [PCXcodeProject buildSetting:@"GNUSTEP_DISTRIBUTIONS" ofTarget:macTarget] == nil,
        @"the Mac target's architectures are its ARCHS");

  /* The GNUstep settings move from ProjectCenter.plist to the Linux target. */
  Check([[[PCXcodeProject GNUstepSettingsOfProjectAtPath:bundle] objectForKey:@"BuildScript"] isEqual:@"build.sh"],
        @"a setting from before is still read from ProjectCenter.plist");
  Check([PCXcodeProject setGNUstepSetting:@"GTK4Native" forKey:@"Theme" ofProjectAtPath:bundle error:&error]
        && [PCXcodeProject setGNUstepSetting:@"build.sh" forKey:@"BuildScript" ofProjectAtPath:bundle error:&error],
        error);
  linuxTarget = [PCXcodeProject linuxTargetOfOverview:[PCXcodeProject overviewOfProjectAtPath:bundle error:NULL]];
  Check([[PCXcodeProject buildSetting:@"GNUSTEP_THEME" ofTarget:linuxTarget] isEqual:@"GTK4Native"]
        && [[PCXcodeProject buildSetting:@"GNUSTEP_BUILD_SCRIPT" ofTarget:linuxTarget] isEqual:@"build.sh"]
        && ![fm fileExistsAtPath:[root stringByAppendingPathComponent:@"GNUstep/ProjectCenter.plist"]],
        @"set again, they are build settings of the Linux target, and the plist file is gone");
  projectDict = [PCXcodeProject projectAtPath:bundle error:&error];
  Check([[projectDict objectForKey:@"XCODE_BuildScript"] isEqual:[root stringByAppendingPathComponent:@"build.sh"]]
        && [[projectDict objectForKey:@"XCODE_Theme"] isEqual:@"GTK4Native"],
        @"the project reads them from the Linux target");

  debian = @{@"Kind": @"Debian", @"Name": @"Debian / Ubuntu (amd64)", @"Architecture": @"amd64"};
  Check([[PCDeployment valueForKey:@"PackageName" ofDeployment:debian project:projectDict] isEqual:@"sample-app"]
        && [[PCDeployment valueForKey:@"Version" ofDeployment:debian project:projectDict] isEqual:@"2.1"],
        @"package name and version from the project");
  Check([[PCDeployment fileNameOfDeployment:@{@"Kind": @"Debian", @"Architecture": @"arm64"} project:projectDict]
         isEqual:@"sample-app_2.1_arm64.deb"], @"Debian file name");
  Check([[PCDeployment fileNameOfDeployment:@{@"Kind": @"RPM", @"Architecture": @"aarch64", @"Version": @"2.1-beta"}
                                    project:projectDict] isEqual:@"sample-app-2.1_beta-1.aarch64.rpm"],
        @"RPM file name");
  Check([[PCDeployment unusedKeysOfDeployment:@{@"Kind": @"Debian", @"Build": @"Container"}] containsObject:@"Toolchain"]
        && ![[PCDeployment unusedKeysOfDeployment:@{@"Kind": @"Debian", @"Build": @"Container"}] containsObject:@"Image"],
        @"the settings a way to build uses");
#ifdef __APPLE__
  Check([[[PCDeployment problemsWithDeployment:@{@"Kind": @"Debian", @"Build": @"Native"} project:projectDict]
          componentsJoinedByString:@" "] rangeOfString:@"need a Linux computer"].location != NSNotFound,
        @"no native Linux build on a Mac");
#endif
  Check([[[PCDeployment problemsWithDeployment:@{@"Kind": @"Linux", @"Build": @"Toolchain"} project:projectDict]
          componentsJoinedByString:@" "] rangeOfString:@"Set Toolchain"].location != NSNotFound,
        @"a toolchain needs its folder");
  container = @{@"Kind": @"RPM", @"Name": @"Fedora \"arm\"", @"Build": @"Container",
                @"Architecture": @"aarch64", @"Setup": @"dnf install -y it's"};

  /* The scripts: well formed, the container run with its platform. */
  folder = [root stringByAppendingPathComponent:@"build/Archives/Test"];
  scripts = [PCDeployment archiveScriptsForProject:projectDict
                                       deployments:@[debian, container,
                                                     @{@"Kind": @"macOS", @"Format": @"dmg", @"SigningIdentity": @"Me"},
                                                     @{@"Kind": @"Windows", @"Build": @"Toolchain"}]
                                            folder:folder makeTool:@"/usr/bin/make"];
  Check([scripts count] == 5, [NSString stringWithFormat:@"a script for each platform: %@", [scripts allKeys]]);
  for (NSString *name in scripts)
  {
    NSString *path = [root stringByAppendingPathComponent:name];

    [[scripts objectForKey:name] writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    Check(Shell([NSString stringWithFormat:@"/bin/sh -n '%@'", path]) == 0,
          [NSString stringWithFormat:@"%@ is a well-formed script:\n%@", name, [scripts objectForKey:name]]);
  }
  script = [scripts objectForKey:@"archive.sh"];
  Check([script rangeOfString:@"run --rm --platform 'linux/arm64'"].location != NSNotFound
        && [script rangeOfString:@"container_image 'projectcenter-gnustep:fedora-arm64' 'linux/arm64'"].location != NSNotFound
        && [script rangeOfString:@"-v \"$ROOT:$ROOT\" -w \"$ROOT\" 'projectcenter-gnustep:fedora-arm64'"].location
        != NSNotFound
        && [script rangeOfString:@"dnf install -y it'\\''s && exec /bin/sh"].location != NSNotFound,
        [NSString stringWithFormat:@"the container build, in ProjectCenter's image, at the project's own path: %@",
         script]);
  Check([[PCDeployment valueForKey:@"Setup" ofDeployment:@{@"Kind": @"Debian"} project:projectDict] isEqual:@""]
        && [[PCDeployment valueForKey:@"Setup" ofDeployment:@{@"Kind": @"Debian", @"Image": @"debian:stable"}
                                  project:projectDict] hasPrefix:@"apt-get"],
        @"ProjectCenter's image needs no setup; another one installs GNUstep");
  Check([[scripts objectForKey:@"2-Fedora-arm.sh"] rangeOfString:@"/opt/projectcenter/packages/*.rpm"].location
        != NSNotFound, @"the RPM gets GNUstep's package from the image next to it");
  Check([[scripts objectForKey:@"3-macOS.sh"] rangeOfString:@"hdiutil create"].location != NSNotFound
        && [[scripts objectForKey:@"3-macOS.sh"] rangeOfString:@"--sign \"$IDENTITY\""].location != NSNotFound,
        @"the macOS disk image, signed");
  for (NSString *name in scripts)
  {
    if ([name hasPrefix:@"1-"])
    {
      Check([[scripts objectForKey:name] rangeOfString:@"dpkg-deb"].location != NSNotFound
            && [[scripts objectForKey:name] rangeOfString:@"/bin/bash \"$ROOT\"/'build.sh' all"].location != NSNotFound,
            @"the Debian package, built with the project's script");
    }
  }

  /* Archive, with the stand-in toolchain: a tar.gz and a Windows zip. */
  tarball = [NSMutableDictionary dictionaryWithDictionary:@{@"Kind": @"Linux", @"Name": @"Linux (x86_64)"}];
  [tarball setObject:@"Toolchain" forKey:@"Build"];
  [tarball setObject:[root stringByAppendingPathComponent:@"Toolchain"] forKey:@"Toolchain"];
  windows = [NSMutableDictionary dictionaryWithDictionary:tarball];
  [windows setObject:@"Windows" forKey:@"Kind"];
  [windows setObject:@"x86_64" forKey:@"Architecture"];
  [windows setObject:@"Windows" forKey:@"Name"];
  Check([[PCDeployment problemsWithDeployment:tarball project:projectDict] count] == 0,
        [NSString stringWithFormat:@"ready to archive: %@", [PCDeployment problemsWithDeployment:tarball project:projectDict]]);
  script = [PCDeployment writeArchiveScriptsForProject:projectDict deployments:@[tarball, windows]
                                                folder:folder makeTool:@"/usr/bin/make" error:&error];
  Check(script != nil, error);
  Check(Shell([NSString stringWithFormat:@"/bin/sh '%@'", script]) == 0, @"Archive runs");
  Check(Shell([NSString stringWithFormat:@"tar -tzf '%@/%@' | grep -q '^Sample.app/Sample$'", folder,
               [PCDeployment fileNameOfDeployment:tarball project:projectDict]]) == 0,
        @"the tar.gz holds the application");
  Check(Shell([NSString stringWithFormat:@"unzip -l '%@/SampleApp-2.1-windows-x86_64.zip' | grep -q 'Sample/Sample.app/Sample.exe'",
               folder]) == 0, @"the Windows zip holds the application in its folder");
  [windows setObject:[root stringByAppendingPathComponent:@"Missing"] forKey:@"Toolchain"];
  script = [PCDeployment writeArchiveScriptsForProject:projectDict deployments:@[windows]
                                                folder:folder makeTool:@"/usr/bin/make" error:&error];
  Check(Shell([NSString stringWithFormat:@"/bin/sh '%@'", script]) != 0, @"a failed platform fails Archive");

  /* Without a build script: ProjectCenter's compiler, as Build uses it. */
  compiled = [NSMutableDictionary dictionaryWithDictionary:projectDict];
  [compiled removeObjectForKey:@"XCODE_BuildScript"];
  scripts = [PCDeployment archiveScriptsForProject:compiled
                                       deployments:@[@{@"Kind": @"Debian", @"Name": @"Debian (arm64)",
                                                       @"Architecture": @"arm64", @"Target": @"Sample Linux",
                                                       @"Build": @"Container"}]
                                            folder:folder makeTool:@"/usr/bin/make"];
  Check([[scripts objectForKey:@"1-Debian-arm64.sh"] rangeOfString:
         @"python3 \"$ROOT/build/Deployment/pc-xcode-build.py\" --project \"$ROOT\"/'Sample.xcodeproj' "
         @"--configuration 'Release' --target 'Sample Linux' --theme 'GTK4Native' --build-dir \"$BUILD/obj\""]
        .location != NSNotFound,
        [NSString stringWithFormat:@"the Linux target, built by ProjectCenter's compiler: %@",
         [scripts objectForKey:@"1-Debian-arm64.sh"]]);

  /* A container build, with a stand-in docker that runs the command here
   * (the project is mounted at its own path) and records what it builds. */
  standIn = [root stringByAppendingPathComponent:@"bin"];
  Write(root, @"bin/docker", @"#!/bin/sh\n"
        "log=\"$STANDIN_LOG\"\n"
        "case \"$1\" in\n"
        "  info) exit 0 ;;\n"
        "  image)\n"
        "    for argument; do image=\"$argument\"; done\n"
        "    [ -f \"$log.images\" ] && grep -qx \"$image\" \"$log.images\" && echo 2 ;;\n"
        "  build)\n"
        "    for argument; do context=\"$argument\"; done\n"
        "    echo \"$*\" >> \"$log\"\n"
        "    [ -f \"$context/Dockerfile\" ] && [ -f \"$context/gnustep-image.sh\" ] && [ -f \"$context/sources/.keep\" ] || exit 1\n"
        "    [ -f \"$context/sources/libobjc2/README\" ] && [ ! -e \"$context/sources/libobjc2/.git\" ] || exit 1\n"
        "    while [ $# -gt 0 ]; do [ \"$1\" = -t ] && echo \"$2\" >> \"$log.images\"; shift; done ;;\n"
        "  run)\n"
        "    echo \"$*\" >> \"$log\"\n"
        "    shift\n"
        "    while [ $# -gt 0 ]; do\n"
        "      case \"$1\" in --rm) shift ;; -w) cd \"$2\" || exit 1; shift 2 ;; --platform|-e|-v) shift 2 ;; *) break ;; esac\n"
        "    done\n"
        "    shift\n"
        "    exec \"$@\" ;;\n"
        "  *) exit 1 ;;\n"
        "esac\n");
  Shell([NSString stringWithFormat:@"chmod 755 '%@/docker'", standIn]);
  Write(root, @"Sources/libobjc2/README", @"libobjc2\n");
  Write(root, @"Sources/libobjc2/.git/HEAD", @"ref\n");
  boxed = [NSMutableDictionary dictionaryWithDictionary:@{@"Kind": @"Linux", @"Name": @"Linux (aarch64)",
                                                          @"Architecture": @"aarch64", @"Build": @"Container"}];
  script = [PCDeployment writeArchiveScriptsForProject:projectDict deployments:@[boxed]
                                                folder:folder makeTool:@"/usr/bin/make" error:&error];
  Check(script != nil
        && [fm fileExistsAtPath:[root stringByAppendingPathComponent:@"build/Deployment/GNUstep-image.Dockerfile"]]
        && [fm fileExistsAtPath:[root stringByAppendingPathComponent:@"build/Deployment/pc-xcode-build.py"]],
        @"the image's files and the compiler are next to the scripts");
  text = [NSString stringWithFormat:@"PATH='%@':\"$PATH\" STANDIN_LOG='%@/docker.log' GNUSTEP_SOURCES='%@/Sources' "
          @"GNUSTEP_MAKEFILES='%@/Toolchain' /bin/sh '%@'", standIn, root, root, root, script];
  Check(Shell(text) == 0, @"Archive runs in the stand-in container");
  Check(Shell([NSString stringWithFormat:@"tar -tzf '%@/%@' | grep -q '^Sample.app/Sample$'", folder,
               [PCDeployment fileNameOfDeployment:boxed project:projectDict]]) == 0,
        @"the container made the tar.gz");
  Check(Shell([NSString stringWithFormat:@"grep -q \"^build --platform linux/arm64 --build-arg BASE=debian:trixie "
               @"-t projectcenter-gnustep:debian-arm64 \" '%@/docker.log' && grep -q \"^run --rm --platform linux/arm64 \" "
               @"'%@/docker.log'", root, root]) == 0,
        [NSString stringWithFormat:@"the image is built once for its platform, then run: %@",
         [NSString stringWithContentsOfFile:[root stringByAppendingPathComponent:@"docker.log"]
                                   encoding:NSUTF8StringEncoding error:NULL]]);
  Check(Shell(text) == 0
        && Shell([NSString stringWithFormat:@"[ $(grep -c '^build ' '%@/docker.log') = 1 ]", root]) == 0,
        @"an image that is there is not built again");
  Check(Shell([NSString stringWithFormat:@"PATH='%@':\"$PATH\" STANDIN_LOG='%@/docker.log' "
               @"GNUSTEP_MAKEFILES='%@/Missing' /bin/sh '%@' 2>&1 | grep -q 'error: GNUstep.sh not found'",
               standIn, root, root, script]) == 0,
        @"errors in the container reach the build log");
  [fm removeItemAtPath:root error:NULL];
}

/* The General pane's edits: one entry of project.pbxproj or the Info.plist
 * at a time, the rest of the file unchanged. */
static void TestProjectEditing(void)
{
  NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:
                    [[NSProcessInfo processInfo] globallyUniqueString]];
  NSString *bundle = [root stringByAppendingPathComponent:@"Sample.xcodeproj"];
  NSString *file = [bundle stringByAppendingPathComponent:@"project.pbxproj"];
  NSString *info = [root stringByAppendingPathComponent:@"Info.plist"];
  NSString *error = nil;
  NSString *head = @"// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tobjectVersion = 77;\n\tobjects = {\n\n"
    "/* Begin PBXProject section */\n"
    "\t\tPROJ /* Project object */ = {\n\t\t\tisa = PBXProject;\n"
    "\t\t\tbuildConfigurationList = PLIST /* Build configuration list */;\n"
    "\t\t\tdevelopmentRegion = en;\n\t\t\tknownRegions = (\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t);\n"
    "\t\t\tmainGroup = ROOT;\n\t\t\ttargets = (\n\t\t\t\tAPP /* Sample */,\n\t\t\t);\n\t\t};\n"
    "/* End PBXProject section */\n\n";
  NSString *rest = @"\t\tAPP /* Sample */ = {\n\t\t\tisa = PBXNativeTarget;\n\t\t\tbuildConfigurationList = TLIST;\n"
    "\t\t\tname = Sample;\n\t\t\tproductType = \"com.apple.product-type.application\";\n\t\t};\n"
    "\t\tTLIST = {\n\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n"
    "\t\t\t\tDEBUG /* Debug */,\n\t\t\t\tRELEASE /* Release */,\n\t\t\t);\n\t\t};\n"
    "\t\tPLIST = {\n\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n\t\t\t);\n\t\t};\n"
    "\t\tROOT = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t);\n\t\t\tsourceTree = \"<group>\";\n\t\t};\n"
    "\t};\n\trootObject = PROJ /* Project object */;\n}\n";
  NSString *debug = @"\t\tDEBUG /* Debug */ = {\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {\n"
    "\t\t\t\tINFOPLIST_FILE = \"Info-macOS.plist\";\n\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 12.0;\n"
    "\t\t\t\t\"OTHER_LDFLAGS[arch=*]\" = (\n\t\t\t\t\t\"-lm\",\n\t\t\t\t);\n"
    "\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";\n\t\t\t};\n\t\t\tname = Debug;\n\t\t};\n";
  NSString *release = @"\t\tRELEASE /* Release */ = {\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {\n"
    "\t\t\t};\n\t\t\tname = Release;\n\t\t};\n";
  NSString *text, *expected;
  NSDictionary *overview;

  Write(root, @"Sample.xcodeproj/project.pbxproj", [NSString stringWithFormat:@"%@%@%@%@", head, debug, release, rest]);
  overview = [PCXcodeProject overviewOfProjectAtPath:bundle error:&error];
  Check([[overview objectForKey:@"Identifier"] isEqual:@"PROJ"]
        && [[[[[overview objectForKey:@"Targets"] objectAtIndex:0] objectForKey:@"Configurations"]
              valueForKey:@"Identifier"] isEqual:(@[@"DEBUG", @"RELEASE"])],
        @"the overview has the identifiers to edit");

  Check([PCXcodeProject setBuildSetting:@"MACOSX_DEPLOYMENT_TARGET" to:@"13.0"
                       inConfigurations:@[@"DEBUG", @"RELEASE"] ofProjectAtPath:bundle error:&error], error);
  Check([PCXcodeProject setBuildSetting:@"PRODUCT_BUNDLE_IDENTIFIER" to:@"org.example.my-app"
                       inConfigurations:@[@"DEBUG"] ofProjectAtPath:bundle error:&error], error);
  Check([PCXcodeProject setBuildSetting:@"INFOPLIST_FILE" to:nil
                       inConfigurations:@[@"DEBUG", @"RELEASE"] ofProjectAtPath:bundle error:&error], error);
  Check([PCXcodeProject setAttribute:@"developmentRegion" to:@"de" ofObject:@"PROJ"
                     ofProjectAtPath:bundle error:&error], error);
  text = [NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:NULL];
  expected = [NSString stringWithFormat:@"%@%@%@%@",
              [head stringByReplacingOccurrencesOfString:@"developmentRegion = en;" withString:@"developmentRegion = de;"],
              @"\t\tDEBUG /* Debug */ = {\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {\n"
              "\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 13.0;\n"
              "\t\t\t\t\"OTHER_LDFLAGS[arch=*]\" = (\n\t\t\t\t\t\"-lm\",\n\t\t\t\t);\n"
              "\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = \"org.example.my-app\";\n"
              "\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";\n\t\t\t};\n\t\t\tname = Debug;\n\t\t};\n",
              @"\t\tRELEASE /* Release */ = {\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {\n"
              "\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 13.0;\n\t\t\t};\n\t\t\tname = Release;\n\t\t};\n", rest];
  Check([text isEqual:expected], [NSString stringWithFormat:@"build settings and attributes edited in place, "
                                  @"in Xcode's order and quoting:\n%@", text]);
  Check(![PCXcodeProject setBuildSetting:@"X" to:@"1" inConfigurations:@[@"MISSING"]
                         ofProjectAtPath:bundle error:&error] && [error length]
        && [[NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:NULL] isEqual:expected],
        @"an unknown configuration leaves the file unchanged");

  Write(root, @"Info.plist", @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<plist version=\"1.0\">\n<dict>\n"
        "\t<key>CFBundleShortVersionString</key>\n\t<string>1.0</string>\n"
        "\t<key>CFBundleVersion</key>\n\t<string>$(CURRENT_PROJECT_VERSION)</string>\n</dict>\n</plist>\n");
  Check([PCXcodeProject setInfoValue:@"2.0 <beta>" forKey:@"CFBundleShortVersionString" inFile:info error:&error]
        && [PCXcodeProject setInfoValue:@"Sample & Co" forKey:@"CFBundleDisplayName" inFile:info error:&error]
        && [PCXcodeProject setInfoValue:nil forKey:@"CFBundleVersion" inFile:info error:&error], error);
  text = [NSString stringWithContentsOfFile:info encoding:NSUTF8StringEncoding error:NULL];
  Check([text isEqual:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<plist version=\"1.0\">\n<dict>\n"
         "\t<key>CFBundleShortVersionString</key>\n\t<string>2.0 &lt;beta&gt;</string>\n"
         "\t<key>CFBundleDisplayName</key>\n\t<string>Sample &amp; Co</string>\n</dict>\n</plist>\n"],
        [NSString stringWithFormat:@"Info.plist edited in place:\n%@", text]);
  [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
}

/* Edit → Convert → To XIB...: the interfaces of a project, without the
 * copies in build products, and their XIBs as gorm2xib writes them. */
static void TestConvertToXIB(void)
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString      *repository = [[[NSString stringWithUTF8String:__FILE__]
                                stringByDeletingLastPathComponent]
                               stringByDeletingLastPathComponent];
  NSString      *gorm = [repository stringByAppendingPathComponent:@"Framework/English.lproj/NewFile.gorm"];
  NSString      *root = [NSTemporaryDirectory() stringByAppendingPathComponent:
                         [[NSProcessInfo processInfo] globallyUniqueString]];
  NSArray       *places = @[@"English.lproj/Main.gorm", @"Sub/Panel.gorm", @"build/Copy.gorm",
                            @"obj/Copy.gorm", @".hidden/Copy.gorm", @"App.app/Contents/Resources/Copy.gorm",
                            @"Editor.editor/Resources/Copy.gorm"];
  NSArray       *found;
  NSArray       *warnings = nil;
  NSString      *error = nil;
  NSString      *xib;

  for (NSString *place in places)
  {
    NSString *target = [root stringByAppendingPathComponent:place];
    [fm createDirectoryAtPath:[target stringByDeletingLastPathComponent]
  withIntermediateDirectories:YES attributes:nil error:NULL];
    Check([fm copyItemAtPath:gorm toPath:target error:NULL], place);
  }
  Write(root, @"App.app/Contents/Info.plist", @"{}");
  Write(root, @"Editor.editor/Resources/Info-gnustep.plist", @"{}");
  [fm createDirectoryAtPath:[root stringByAppendingPathComponent:@"Empty.gorm"]
withIntermediateDirectories:YES attributes:nil error:NULL];

  found = [PCGormXIBWriter gormInterfacesInDirectory:root];
  Check([found isEqual:(@[[root stringByAppendingPathComponent:@"English.lproj/Main.gorm"],
                          [root stringByAppendingPathComponent:@"Sub/Panel.gorm"]])],
        [NSString stringWithFormat:@"interfaces without build products, bundles and hidden folders: %@", found]);
  xib = [PCGormXIBWriter XIBPathForGorm:[found objectAtIndex:1]];
  Check([xib isEqual:[root stringByAppendingPathComponent:@"Sub/Panel.xib"]], @"XIB next to its .gorm");
  Check([PCGormXIBWriter writeXIBForGormAtPath:[found objectAtIndex:1] toPath:xib
                                  toolsVersion:[PCGormXIBWriter interfaceBuilderVersion]
                                      warnings:&warnings error:&error], error);
  Check([warnings count] == 2, @"theme images that the XIB leaves out");
  if ([PCGormXIBWriter interfaceBuilderVersion])
  {
    Check([[NSData dataWithContentsOfFile:xib] isEqualToData:
           [NSData dataWithContentsOfFile:[repository stringByAppendingPathComponent:
                                           @"Framework/English.lproj/NewFile.xib"]]],
          @"converted as gorm2xib converted ProjectCenter's interfaces");
  }
  Check(![PCGormXIBWriter writeXIBForGormAtPath:[root stringByAppendingPathComponent:@"Empty.gorm"]
                                         toPath:xib toolsVersion:nil warnings:NULL error:&error]
        && [error length], @"a .gorm without objects.gorm is not converted");
  [fm removeItemAtPath:root error:NULL];
}

static NSString *SchemeXML(NSString *target, NSString *run, NSString *archive, BOOL runnable)
{
  NSString *reference = [NSString stringWithFormat:@"<BuildableReference BuildableIdentifier=\"primary\" "
                         "BlueprintName=\"%@\" ReferencedContainer=\"container:Sample.xcodeproj\"/>", target];

  return [NSString stringWithFormat:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<Scheme version=\"1.7\">"
          "<BuildAction><BuildActionEntries><BuildActionEntry buildForRunning=\"YES\" buildForTesting=\"YES\">%@"
          "</BuildActionEntry></BuildActionEntries></BuildAction>"
          "<TestAction buildConfiguration=\"Debug\"/><LaunchAction buildConfiguration=\"%@\">%@</LaunchAction>"
          "<ProfileAction buildConfiguration=\"Release\"/><AnalyzeAction buildConfiguration=\"Debug\"/>"
          "<ArchiveAction buildConfiguration=\"%@\"/></Scheme>",
          reference, run,
          (runnable ? [NSString stringWithFormat:@"<BuildableProductRunnable>%@</BuildableProductRunnable>", reference] : @""),
          archive];
}

/* Schemes as Xcode lists them, and the scheme, configuration and destination
 * that the toolbar chooses for xcodebuild. */
static void TestBuildSelection(void)
{
  NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
  NSString *bundle = [root stringByAppendingPathComponent:@"Sample.xcodeproj"];
  NSString *user = [NSString stringWithFormat:@"Sample.xcodeproj/xcuserdata/%@.xcuserdatad/xcschemes", NSUserName()];
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  id savedDefault = [[defaults objectForKey:@"PCXcodeBuildSelections"] retain];

  Write(root, @"Sample.xcodeproj/project.pbxproj", @"// !$*UTF8*$!\n{objectVersion=77; rootObject=PROJ; objects={"
        "PROJ={isa=PBXProject;mainGroup=ROOT;targets=(APP,LIB,TOOL,HIDDEN);buildConfigurationList=PLIST;};"
        "PLIST={isa=XCConfigurationList;buildConfigurations=(PDEBUG,PRELEASE);defaultConfigurationName=Release;};"
        "PDEBUG={isa=XCBuildConfiguration;name=Debug;buildSettings={};};"
        "PRELEASE={isa=XCBuildConfiguration;name=Release;buildSettings={};};"
        "APP={isa=PBXNativeTarget;name=App;productType=\"com.apple.product-type.application\";};"
        "LIB={isa=PBXNativeTarget;name=Lib;productType=\"com.apple.product-type.framework\";};"
        "TOOL={isa=PBXNativeTarget;name=Tool;productType=\"com.apple.product-type.tool\";};"
        "HIDDEN={isa=PBXAggregateTarget;name=Hidden;};"
        "ROOT={isa=PBXGroup;children=();sourceTree=\"<group>\";};};}");
  Write(root, @"Sample.xcodeproj/xcshareddata/xcschemes/App.xcscheme", SchemeXML(@"App", @"Debug", @"Release", YES));
  Write(root, [user stringByAppendingPathComponent:@"Lib Release.xcscheme"], SchemeXML(@"Lib", @"Release", @"Release", NO));
  Write(root, [user stringByAppendingPathComponent:@"xcschememanagement.plist"],
        @"{SchemeUserState={\"Lib Release.xcscheme\"={orderHint=0;};\"App.xcscheme_^#shared#^_\"={orderHint=1;};"
        "\"Hidden.xcscheme_^#shared#^_\"={isShown=0;};};}");

  NSArray *schemes = [PCXcodeProject schemesOfProjectAtPath:bundle];
  Check([[schemes valueForKey:@"Name"] isEqual:(@[@"Lib Release", @"App", @"Tool"])],
        [NSString stringWithFormat:@"schemes in the user's order, one made for each target without one, hidden ones left out: %@",
         [schemes valueForKey:@"Name"]]);
  NSDictionary *app = [schemes objectAtIndex:1];
  NSDictionary *lib = [schemes objectAtIndex:0];
  NSDictionary *tool = [schemes objectAtIndex:2];
  Check([[app objectForKey:@"Targets"] isEqual:@[@"App"]] && [[app objectForKey:@"RunTarget"] isEqual:@"App"]
        && [[app objectForKey:@"Shared"] boolValue] && ![[app objectForKey:@"Implicit"] boolValue], @"shared scheme");
  Check([[[app objectForKey:@"Configurations"] objectForKey:@"Run"] isEqual:@"Debug"]
        && [[[app objectForKey:@"Configurations"] objectForKey:@"Archive"] isEqual:@"Release"], @"configuration for each action");
  Check(![[lib objectForKey:@"Shared"] boolValue] && [lib objectForKey:@"RunTarget"] == nil
        && [[[lib objectForKey:@"Configurations"] objectForKey:@"Run"] isEqual:@"Release"], @"user scheme without a runnable");
  Check([[tool objectForKey:@"Implicit"] boolValue] && [[tool objectForKey:@"RunTarget"] isEqual:@"Tool"]
        && [[[tool objectForKey:@"Configurations"] objectForKey:@"Run"] isEqual:@"Debug"]
        && [[[tool objectForKey:@"Configurations"] objectForKey:@"Archive"] isEqual:@"Release"], @"implicit scheme for a tool");
  Check([[PCXcodeProject configurationsOfProjectAtPath:bundle] isEqual:(@[@"Debug", @"Release"])], @"project configurations");
  NSArray *destinations = [PCXcodeProject runDestinations];
  Check([[[destinations objectAtIndex:0] objectForKey:@"Name"] isEqual:@"My Mac"]
        && [[[destinations lastObject] objectForKey:@"BuildOnly"] boolValue]
        && [[[destinations lastObject] objectForKey:@"Destination"] isEqual:@"generic/platform=macOS"], @"run destinations");

  NSError *error = nil;
  NSString *problem = nil;
  NSDictionary *dict = [PCXcodeProject projectAtPath:bundle error:&problem];
  Check(dict != nil, problem);
  [defaults removeObjectForKey:@"PCXcodeBuildSelections"];
  NSDictionary *selection = [PCXcodeProject buildSelectionForProject:dict];
  Check([[[selection objectForKey:@"Scheme"] objectForKey:@"Name"] isEqual:@"App"]
        && [[selection objectForKey:@"Configuration"] isEqual:@"Debug"]
        && [[[selection objectForKey:@"Destination"] objectForKey:@"Name"] isEqual:@"My Mac"],
        @"default selection: the application's scheme, its Run configuration, My Mac");
  NSArray *arguments = [PCXcodeProject xcodebuildArgumentsForProject:dict action:@"build"
                                                           selection:selection knownSchemes:@[@"App"]];
  NSArray *expected = @[@"-project", bundle, @"-scheme", @"App", @"-configuration", @"Debug", @"-destination",
                        [[destinations objectAtIndex:0] objectForKey:@"Destination"], @"-quiet", @"build"];
  Check([arguments isEqual:expected], [NSString stringWithFormat:@"xcodebuild arguments for a scheme: %@", arguments]);

  [PCXcodeProject selectScheme:@"Tool" configuration:nil destination:nil forProject:dict];
  [PCXcodeProject selectScheme:nil configuration:@"Release" destination:nil forProject:dict];
  selection = [PCXcodeProject buildSelectionForProject:dict];
  Check([[[selection objectForKey:@"Scheme"] objectForKey:@"Name"] isEqual:@"Tool"]
        && [[selection objectForKey:@"Configuration"] isEqual:@"Release"], @"scheme and configuration chosen");
  arguments = [PCXcodeProject xcodebuildArgumentsForProject:dict action:@"clean"
                                                  selection:selection knownSchemes:@[@"App"]];
  Check([[arguments subarrayWithRange:NSMakeRange(2, 4)] isEqual:(@[@"-target", @"Tool", @"-configuration", @"Release"])]
        && [[arguments lastObject] isEqual:@"clean"], @"a scheme xcodebuild doesn't know builds its target");
  [PCXcodeProject selectScheme:@"App" configuration:nil destination:nil forProject:dict];
  Check([[[PCXcodeProject buildSelectionForProject:dict] objectForKey:@"Configuration"] isEqual:@"Debug"],
        @"each scheme keeps its own configuration");
  [PCXcodeProject selectScheme:@"Tool" configuration:@"Debug" destination:nil forProject:dict];
  Check([[[defaults objectForKey:@"PCXcodeBuildSelections"] objectForKey:bundle] objectForKey:@"Configurations"] != nil
        && [[[[defaults objectForKey:@"PCXcodeBuildSelections"] objectForKey:bundle] objectForKey:@"Configurations"] count] == 0,
        @"choosing the scheme's own configuration removes the override");
  Check([PCXcodeProject canRunProject:dict], @"a tool scheme runs on My Mac");

  [PCXcodeProject selectScheme:nil configuration:nil destination:@"Any Mac (arm64, x86_64)" forProject:dict];
  selection = [PCXcodeProject buildSelectionForProject:dict];
  Check(![PCXcodeProject canRunProject:dict], @"Any Mac only builds");
  arguments = [PCXcodeProject xcodebuildArgumentsForProject:dict action:@"build"
                                                  selection:selection knownSchemes:@[@"Tool"]];
  Check([arguments containsObject:@"generic/platform=macOS"], @"Any Mac destination for a scheme");
  arguments = [PCXcodeProject xcodebuildArgumentsForProject:dict action:@"build"
                                                  selection:selection knownSchemes:@[]];
  Check([arguments containsObject:@"ONLY_ACTIVE_ARCH=NO"] && ![arguments containsObject:@"-destination"],
        @"Any Mac without a scheme builds every architecture");
  [PCXcodeProject selectScheme:@"Lib Release" configuration:nil destination:@"My Mac" forProject:dict];
  Check(![PCXcodeProject canRunProject:dict], @"a scheme without a run target doesn't run");
  Check([[[PCXcodeProject buildSelectionForProject:dict] objectForKey:@"Configuration"] isEqual:@"Release"],
        @"the scheme's own Run configuration");

  /* A scheme removed in Xcode falls back to the application's. */
  [[NSFileManager defaultManager] removeItemAtPath:[root stringByAppendingPathComponent:user] error:&error];
  Check([[[[PCXcodeProject buildSelectionForProject:dict] objectForKey:@"Scheme"] objectForKey:@"Name"] isEqual:@"App"],
        @"a removed scheme falls back to the application's");

  if (savedDefault) [defaults setObject:savedDefault forKey:@"PCXcodeBuildSelections"];
  else [defaults removeObjectForKey:@"PCXcodeBuildSelections"];
  [savedDefault release];
  [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
}

int main(int argc, char **argv)
{
  @autoreleasepool
  {
    if (argc == 2 && strcmp(argv[1], "--theme-settings") == 0)
    {
      TestGNUstepSettings();
      NSLog(@"Project theme settings/build environment tests passed");
      return 0;
    }
    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
    NSString *bundle = [root stringByAppendingPathComponent:@"Sample.xcodeproj"];
    NSString *fixture = @"// !$*UTF8*$!\n{objectVersion=77; rootObject=PROJ; objects={"
    "PROJ={isa=PBXProject;mainGroup=ROOT;targets=(TARGET,AGG);developmentRegion=en;knownRegions=(en,Base);buildConfigurationList=PLIST;};"
    "PLIST={isa=XCConfigurationList;buildConfigurations=(PDEBUG);};"
    "PDEBUG={isa=XCBuildConfiguration;name=Debug;buildSettings={MACOSX_DEPLOYMENT_TARGET=11;};};"
    "TARGET={isa=PBXNativeTarget;name=Sample;productName=Sample;productType=\"com.apple.product-type.application\";"
    "buildConfigurationList=TLIST;buildPhases=(SOURCES,SCRIPT);dependencies=(DEP);};"
    "TLIST={isa=XCConfigurationList;buildConfigurations=(TDEBUG,TRELEASE);};"
    "TDEBUG={isa=XCBuildConfiguration;name=Debug;buildSettings={PRODUCT_BUNDLE_IDENTIFIER=org.example.Sample;GCC_PREPROCESSOR_DEFINITIONS=(\"DEBUG=1\",\"$(inherited)\");};};"
    "TRELEASE={isa=XCBuildConfiguration;name=Release;baseConfigurationReference=XCCONFIG;buildSettings={PRODUCT_BUNDLE_IDENTIFIER=org.example.Sample;};};"
    "XCCONFIG={isa=PBXFileReference;path=release.xcconfig;sourceTree=\"<group>\";};"
    "SOURCES={isa=PBXSourcesBuildPhase;files=(BMAIN);};"
    "BMAIN={isa=PBXBuildFile;fileRef=MAIN;};"
    "SCRIPT={isa=PBXShellScriptBuildPhase;name=\"Make Version\";shellScript=\"echo hi\";files=();};"
    "DEP={isa=PBXTargetDependency;target=AGG;};"
    "AGG={isa=PBXAggregateTarget;name=Scripts;};"
    "ROOT={isa=PBXGroup;children=(SRC,SYNC,SDK,VARIANT,ROOT);sourceTree=\"<group>\";};"
    "SRC={isa=PBXGroup;path=Sources;sourceTree=\"<group>\";children=(MAIN,HEADER,ABS);};"
    "MAIN={isa=PBXFileReference;path=\"Café file.m\";sourceTree=\"<group>\";};"
    "HEADER={isa=PBXFileReference;path=Include/Header.h;sourceTree=SOURCE_ROOT;};"
    "ABS={isa=PBXFileReference;path=\"/not/a/real/file.m\";sourceTree=\"<absolute>\";};"
    "SYNC={isa=PBXFileSystemSynchronizedRootGroup;path=Modern;sourceTree=\"<group>\";};"
    "SDK={isa=PBXFileReference;path=AppKit.framework;sourceTree=SDKROOT;};"
    "VARIANT={isa=PBXVariantGroup;name=MainMenu.xib;children=(EN);sourceTree=\"<group>\";};"
    "EN={isa=PBXFileReference;path=Base.lproj/MainMenu.xib;sourceTree=\"<group>\";};"
    "};}";
    Write(root, @"Sample.xcodeproj/project.pbxproj", fixture);
    Write(root, @"Sources/Café file.m", @"// source");
    Write(root, @"Include/Header.h", @"// header");
    Write(root, @"Modern/Nested/New.m", @"// synchronized folder");
    Write(root, @"Modern/Images.xcassets/Icon.imageset/image.png", @"image");
    Write(root, @"Modern/.ignored/Hidden.m", @"hidden");
    Write(root, @"Base.lproj/MainMenu.xib", @"<xml/>");
    Write(root, @"GNUmakefile", @"# preserve this\n");
    NSString *error = nil;
    NSDictionary *dict = [PCXcodeProject projectAtPath:bundle error:&error];
    Check(dict != nil, error);
    Check([[dict objectForKey:@"CLASS_FILES"] containsObject:@"Sources/Café file.m"], @"Unicode and spaces in group-relative source");
    Check([[dict objectForKey:@"HEADER_FILES"] containsObject:@"Include/Header.h"], @"SOURCE_ROOT reference");
    Check([[dict objectForKey:@"CLASS_FILES"] containsObject:@"Modern/Nested/New.m"], @"Xcode synchronized folder");
    Check([[dict objectForKey:@"CLASS_FILES"] count] == 2, @"cycles and hidden files excluded");
    Check([[dict objectForKey:@"IMAGES"] containsObject:@"Modern/Images.xcassets"], @"asset catalog stays a package");
    Check([[dict objectForKey:@"INTERFACES"] containsObject:@"Base.lproj/MainMenu.xib"], @"localized variant group");
    Check([[dict objectForKey:@"SUPPORTING_FILES"] containsObject:@"GNUmakefile"], @"existing build file");
    NSArray *groups = [dict objectForKey:@"XCODE_GROUPS"];
    Check([[groups valueForKey:@"Name"] isEqual:(@[@"Sources", @"Modern", @"MainMenu.xib"])], @"group tree keeps Xcode order and drops SDK references");
    NSArray *sources = [[groups objectAtIndex:0] objectForKey:@"Children"];
    Check([[sources valueForKey:@"File"] isEqual:(@[@"Sources/Café file.m", @"Include/Header.h"])], @"group files keep project-relative paths; missing files dropped");
    NSArray *modern = [[groups objectAtIndex:1] objectForKey:@"Children"];
    Check([[modern valueForKey:@"Name"] isEqual:(@[@"Images.xcassets", @"Nested"])], @"synchronized folder is a sorted tree without hidden entries");
    Check([[[[modern objectAtIndex:1] objectForKey:@"Children"] valueForKey:@"File"] isEqual:@[@"Modern/Nested/New.m"]], @"synchronized subfolder file");
    Check([[[[groups objectAtIndex:2] objectForKey:@"Children"] valueForKey:@"File"] isEqual:@[@"Base.lproj/MainMenu.xib"]], @"variant group localization");
    Check([PCXcodeProject projectAtPath:[bundle stringByAppendingPathComponent:@"project.pbxproj"] error:&error] != nil, @"pbxproj entry point");
    NSDictionary *overview = [PCXcodeProject overviewOfProjectAtPath:bundle error:&error];
    Check([[overview objectForKey:@"Name"] isEqual:@"Sample"] && [[overview objectForKey:@"DevelopmentRegion"] isEqual:@"en"], @"overview project name and region");
    Check([[[[overview objectForKey:@"Configurations"] objectAtIndex:0] objectForKey:@"Settings"] objectForKey:@"MACOSX_DEPLOYMENT_TARGET"] != nil, @"overview project build settings");
    NSArray *overviewTargets = [overview objectForKey:@"Targets"];
    Check([[overviewTargets valueForKey:@"Name"] isEqual:(@[@"Sample", @"Scripts"])] && [[[overviewTargets objectAtIndex:1] objectForKey:@"Kind"] isEqual:@"Aggregate"], @"overview lists all targets");
    NSDictionary *sampleTarget = [overviewTargets objectAtIndex:0];
    Check([[[sampleTarget objectForKey:@"Configurations"] valueForKey:@"Name"] isEqual:(@[@"Debug", @"Release"])]
          && [[[[sampleTarget objectForKey:@"Configurations"] objectAtIndex:1] objectForKey:@"Base"] isEqual:@"release.xcconfig"], @"overview target configurations and base xcconfig");
    Check([[[[[sampleTarget objectForKey:@"Configurations"] objectAtIndex:0] objectForKey:@"Settings"] objectForKey:@"GCC_PREPROCESSOR_DEFINITIONS"] count] == 2, @"list-valued build setting");
    NSArray *samplePhases = [sampleTarget objectForKey:@"Phases"];
    Check([[samplePhases valueForKey:@"Name"] isEqual:(@[@"Compile Sources", @"Make Version"])]
          && [[[samplePhases objectAtIndex:0] objectForKey:@"Files"] isEqual:@[@"Café file.m"]]
          && [[[samplePhases objectAtIndex:1] objectForKey:@"Script"] isEqual:@"echo hi"], @"overview build phases");
    Check([[sampleTarget objectForKey:@"Dependencies"] isEqual:@[@"Scripts"]], @"overview target dependencies");
    Write(root, @"GNUstep/ProjectCenter.plist", @"{TargetName=Sample;BuildScript=build.sh;Executable=output/Sample.app/Sample;}");
    dict = [PCXcodeProject projectAtPath:bundle error:&error];
    Check([[dict objectForKey:@"XCODE_BuildScript"] isEqual:[root stringByAppendingPathComponent:@"build.sh"]], @"build script path resolution");
    Check([[dict objectForKey:@"XCODE_Executable"] isEqual:[root stringByAppendingPathComponent:@"output/Sample.app/Sample"]], @"debug executable path resolution");
    Write(root, @"GNUstep/ProjectCenter.plist", @"{TargetName=Missing;}");
    Check([PCXcodeProject projectAtPath:bundle error:&error] == nil && [error length], @"missing target error");
    Write(root, @"GNUstep/ProjectCenter.plist", @"{BuildScript=(bad);}");
    Check([PCXcodeProject projectAtPath:bundle error:&error] == nil && [error length], @"malformed settings error");
    Write(root, @"Sample.xcodeproj/project.pbxproj", @"{objects=();rootObject=Missing;}");
    Check([PCXcodeProject projectAtPath:bundle error:&error] == nil && [error length], @"malformed project error");
    [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
    if (argc > 1)
    {
      dict = [PCXcodeProject projectAtPath:[NSString stringWithUTF8String:argv[1]] error:&error];
      Check(dict != nil, error);
      Check([[dict objectForKey:@"CLASS_FILES"] count] > 40, @"EditGlyphData source files");
      Check([[dict objectForKey:@"CLASS_FILES"] containsObject:@"EditGlyphData/GSWindowController.m"], @"EditGlyphData main controller");
      NSLog(@"EditGlyphData: %lu source files, %lu headers, %lu interfaces", (unsigned long)[[dict objectForKey:@"CLASS_FILES"] count], (unsigned long)[[dict objectForKey:@"HEADER_FILES"] count], (unsigned long)[[dict objectForKey:@"INTERFACES"] count]);
    }
    TestBuildSelection();
    TestConvertToXIB();
    TestGNUstepSettings();
    TestDeployment();
    TestProjectEditing();
    TestGNUstepOnMac();
    TestGormArchives();
    TestInterfaceDocument();
    TestConstraintNames();
    TestInterfaceDocumentRoundTrip();
    NSLog(@"Xcode project adapter tests passed");
  }
  return 0;
}
