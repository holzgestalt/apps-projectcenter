#import <Foundation/Foundation.h>
#import "PCXcodeProject.h"

static void Check(BOOL condition, NSString *message)
{
  if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}

static void Write(NSString *root, NSString *path, NSString *contents)
{
  NSString *file = [root stringByAppendingPathComponent:path];
  [[NSFileManager defaultManager] createDirectoryAtPath:[file stringByDeletingLastPathComponent]
                         withIntermediateDirectories:YES attributes:nil error:NULL];
  Check([contents writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:NULL], path);
}

int main(int argc, char **argv)
{
  @autoreleasepool
    {
      NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
      NSString *bundle = [root stringByAppendingPathComponent:@"Sample.xcodeproj"];
      NSString *fixture = @"// !$*UTF8*$!\n{objectVersion=77; rootObject=PROJ; objects={"
        "PROJ={isa=PBXProject;mainGroup=ROOT;targets=(TARGET,AGG);};"
        "TARGET={isa=PBXNativeTarget;name=Sample;productType=\"com.apple.product-type.application\";};"
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
      NSLog(@"Xcode project adapter tests passed");
    }
  return 0;
}
