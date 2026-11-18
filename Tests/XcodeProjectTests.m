#import <Foundation/Foundation.h>
#import "PCXcodeProject.h"
#import "PCGormArchive.h"
#import "PCGormXIBWriter.h"

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

static void Write(NSString *root, NSString *path, NSString *contents)
{
  NSString *file = [root stringByAppendingPathComponent:path];
  [[NSFileManager defaultManager] createDirectoryAtPath:[file stringByDeletingLastPathComponent]
                            withIntermediateDirectories:YES attributes:nil error:NULL];
  Check([contents writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:NULL], path);
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
    TestGormArchives();
    NSLog(@"Xcode project adapter tests passed");
  }
  return 0;
}
