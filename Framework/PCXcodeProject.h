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

/* GNUstep settings: GNUstep/ProjectCenter.plist beside the .xcodeproj,
 * ProjectCenter's own file (the Xcode project stays unchanged). Keys are
 * TargetName, BuildScript, Executable and Theme, all strings as written
 * (paths not resolved). +projectAtPath:error: puts them in the project
 * dictionary as XCODE_<Key>, with paths resolved. */
+ (NSDictionary *)GNUstepSettingsOfProjectAtPath:(NSString *)path;
/* Sets one of them; an empty or nil value removes it. Creates the file
 * when needed and removes it when no setting is left. */
+ (BOOL)setGNUstepSetting:(NSString *)value
                   forKey:(NSString *)key
         ofProjectAtPath:(NSString *)path
                    error:(NSString **)error;

/* GNUstep themes, found as GSTheme finds them: <Name>.theme bundles in the
 * Themes folder of each Library directory. Sorted names without the
 * extension; GNUstep's built-in theme is not a bundle and not listed. */
+ (NSArray *)installedThemes;
+ (NSArray *)themesInLibraries:(NSArray *)libraries;
/* Arguments for running the application with the project's Theme on
 * GNUstep (-GSTheme Name), or an empty array. */
+ (NSArray *)launchArgumentsForProject:(NSDictionary *)projectDict;

/* Schemes, configurations and run destinations, as Xcode's toolbar offers
 * them. A scheme picks the targets to build and, for each action, the build
 * configuration; the run destination picks the architectures. */

/* The schemes of an .xcodeproj, in Xcode's order: the shared ones
 * (xcshareddata), the user's own (xcuserdata), then one for each target
 * that no scheme builds, as Xcode creates them. Each is {Name, Shared,
 * Implicit, Targets, RunTarget, Configurations}; Targets are the names of
 * the targets it builds for running, RunTarget the target that Run starts
 * (absent when it starts none), and Configurations maps the actions Run,
 * Test, Profile, Analyze and Archive to a build configuration. */
+ (NSArray *)schemesOfProjectAtPath:(NSString *)path;
/* The project's build configuration names ("Debug", "Release"). */
+ (NSArray *)configurationsOfProjectAtPath:(NSString *)path;
/* The run destinations of this computer: [{Name, Destination,
 * Architecture, BuildOnly}]: "My Mac", "My Mac (Rosetta)" on Apple silicon
 * with Rosetta installed, and "Any Mac". Destination is the value of
 * xcodebuild's -destination; BuildOnly is YES for "Any Mac", which builds
 * every architecture but cannot be run. */
+ (NSArray *)runDestinations;

/* The scheme, configuration and destination chosen for a project read by
 * +projectAtPath:error:, as {Scheme, Configuration, Destination} with the
 * scheme and destination dictionaries from the methods above. A project
 * that has no choice saved gets the scheme of its application target, the
 * configuration of that scheme's Run action and the first destination. */
+ (NSDictionary *)buildSelectionForProject:(NSDictionary *)projectDict;
/* Saves the choice for this user (in the defaults; the Xcode project stays
 * unchanged). Any of the names may be nil to keep the current one. A
 * configuration is kept for each scheme, as Xcode keeps it in the scheme;
 * choosing a scheme's own Run configuration removes the override. */
+ (void)selectScheme:(NSString *)scheme
       configuration:(NSString *)configuration
         destination:(NSString *)destination
          forProject:(NSDictionary *)projectDict;

/* Building with Xcode's own tools, where they are installed (macOS). */

/* Path of xcodebuild, or nil without the Xcode tools. */
+ (NSString *)xcodebuildPath;
/* Arguments for xcodebuild to run `action` ("build" or "clean") for the
 * selection of +buildSelectionForProject:. A scheme that xcodebuild knows
 * is built with -scheme, so the products go to Xcode's DerivedData as when
 * building in Xcode; one it doesn't know with -target. */
+ (NSArray *)xcodebuildArgumentsForProject:(NSDictionary *)projectDict
                                    action:(NSString *)action;
/* Same, for a given selection (as returned by +buildSelectionForProject:)
 * and the schemes that xcodebuild knows, without running it. */
+ (NSArray *)xcodebuildArgumentsForProject:(NSDictionary *)projectDict
                                    action:(NSString *)action
                                 selection:(NSDictionary *)selection
                              knownSchemes:(NSArray *)knownSchemes;
/* Whether the selection can be run: its scheme has a run target and its
 * destination is not build-only. */
+ (BOOL)canRunProject:(NSDictionary *)projectDict;
/* The architecture to start the product with when it is not this
 * computer's own (x86_64 for "My Mac (Rosetta)"), or nil. */
+ (NSString *)launchArchitectureForProject:(NSDictionary *)projectDict;
/* The executable that xcodebuild builds for the run target of the selected
 * scheme, configuration and destination, or nil. Asks xcodebuild for the
 * build settings once per selection. */
+ (NSString *)builtExecutableForProject:(NSDictionary *)projectDict;
@end
