#import <Foundation/Foundation.h>
#import "PCXcodeProject.h"
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
    TestGormArchives();
    TestInterfaceDocument();
    TestConstraintNames();
    TestInterfaceDocumentRoundTrip();
    NSLog(@"Xcode project adapter tests passed");
  }
  return 0;
}
