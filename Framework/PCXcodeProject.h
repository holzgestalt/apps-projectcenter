#import <Foundation/Foundation.h>

/* Read-only project metadata adapter. Source files remain editable. */
@interface PCXcodeProject : NSObject
+ (NSDictionary *)projectAtPath:(NSString *)path error:(NSString **)error;
/* A read-only description of the project for the project editor:
 * {Name, Format, DevelopmentRegion, KnownRegions, Configurations, Targets}.
 * Configurations are [{Name, Base, Settings}]; each target is {Name, Kind,
 * ProductType, ProductName, Configurations, Phases, Dependencies}, a phase
 * {Name, Kind, Files, Script}. */
+ (NSDictionary *)overviewOfProjectAtPath:(NSString *)path error:(NSString **)error;

/* Building with Xcode's own tools, where they are installed (macOS). */

/* Path of xcodebuild, or nil without the Xcode tools. */
+ (NSString *)xcodebuildPath;
/* Arguments for xcodebuild to run `action` ("build" or "clean") on the
 * application target of a project read by +projectAtPath:error:. The scheme
 * of the same name is used when there is one, so the products go to Xcode's
 * DerivedData as when building in Xcode. */
+ (NSArray *)xcodebuildArgumentsForProject:(NSDictionary *)projectDict
                                    action:(NSString *)action;
/* The executable that xcodebuild builds for the application target, or nil.
 * Asks xcodebuild for the build settings once per project. */
+ (NSString *)builtExecutableForProject:(NSDictionary *)projectDict;
@end
