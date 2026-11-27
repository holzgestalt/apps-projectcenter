#import <Foundation/Foundation.h>

/* The user default that chooses GNUstep (see +chosenGNUstep), set in the
 * Misc preferences. */
#define PCGNUstepDefault @"GNUstepInstallation"

/* Read-only project metadata adapter. Source files remain editable. */
@interface PCXcodeProject : NSObject
+ (NSDictionary *)projectAtPath:(NSString *)path error:(NSString **)error;
/* A read-only description of the project for the project editor:
 * {Name, Identifier, Format, DevelopmentRegion, KnownRegions, Configurations, Targets}.
 * Configurations are [{Name, Identifier, Base, Settings}]; each target is {Name, Identifier, Kind,
 * ProductType, ProductName, Configurations, Phases, Dependencies}, a phase
 * {Name, Kind, Files, Paths, Script}, Paths being the files found locally. */
+ (NSDictionary *)overviewOfProjectAtPath:(NSString *)path error:(NSString **)error;

/* Editing the project, for the General pane. project.pbxproj is changed as
 * text, one entry at a time, so the rest of the file stays as Xcode wrote it;
 * it is only written when the result still reads as a property list. A nil
 * value removes the entry. The identifiers are the Identifier values of
 * +overviewOfProjectAtPath:error:. */

/* A build setting in each of the given build configurations. */
+ (BOOL)setBuildSetting:(NSString *)key
                     to:(NSString *)value
       inConfigurations:(NSArray *)identifiers
        ofProjectAtPath:(NSString *)path
                  error:(NSString **)error;
/* An attribute of an object, such as the project's developmentRegion. */
+ (BOOL)setAttribute:(NSString *)key
                  to:(NSString *)value
            ofObject:(NSString *)identifier
     ofProjectAtPath:(NSString *)path
               error:(NSString **)error;
/* A string in an Info.plist. An XML file is edited in place; other formats
 * are written again as XML. */
+ (BOOL)setInfoValue:(NSString *)value
              forKey:(NSString *)key
              inFile:(NSString *)file
               error:(NSString **)error;

/* Targets by platform: a target whose SDKROOT is linux (or windows) builds
 * for that system with GNUstep; any other target is a Mac target. The
 * target is an entry of +overviewOfProjectAtPath:error:. */
+ (NSString *)platformOfTarget:(NSDictionary *)target;
/* The first Linux target of an overview, or nil. */
+ (NSDictionary *)linuxTargetOfOverview:(NSDictionary *)overview;
/* A build setting of a target: its Release configuration's, else the first
 * configuration that has it; a list is joined with spaces. nil if none has
 * it. Only the target's own settings, not the project's. */
+ (NSString *)buildSetting:(NSString *)key ofTarget:(NSDictionary *)target;
/* Sets (empty or nil: removes) a build setting in every configuration of
 * a target. */
+ (BOOL)setBuildSetting:(NSString *)key
                     to:(NSString *)value
               ofTarget:(NSDictionary *)target
        ofProjectAtPath:(NSString *)path
                  error:(NSString **)error;

/* GNUstep settings, keys TargetName, BuildScript, Executable and Theme, all
 * strings as written (paths not resolved). BuildScript, Executable and Theme
 * are build settings of the Linux target (GNUSTEP_BUILD_SCRIPT,
 * GNUSTEP_EXECUTABLE, GNUSTEP_THEME); without a Linux target, and for
 * values from before, they are in GNUstep/ProjectCenter.plist beside the
 * .xcodeproj, ProjectCenter's own file. The Linux target's value wins.
 * +projectAtPath:error: puts them in the project dictionary as
 * XCODE_<Key>, with paths resolved. */
+ (NSDictionary *)GNUstepSettingsOfProjectAtPath:(NSString *)path;
/* Sets one of them; an empty or nil value removes it. With a Linux target,
 * BuildScript, Executable and Theme go into it and out of the plist file;
 * the plist file is created when needed and removed when no setting is
 * left. */
+ (BOOL)setGNUstepSetting:(NSString *)value
                   forKey:(NSString *)key
         ofProjectAtPath:(NSString *)path
                    error:(NSString **)error;
/* Sets any property list value (a string, or arrays and dictionaries of
 * them) in GNUstep/ProjectCenter.plist; an empty or nil value removes it. */
+ (BOOL)setGNUstepValue:(id)value
                 forKey:(NSString *)key
        ofProjectAtPath:(NSString *)path
                  error:(NSString **)error;

/* Installed application appearance providers, registered through the same
 * pkg-config profiles used by GNUstep Make. Sorted names. */
+ (NSArray *)installedThemes;
/* -installedThemes is looked up once and then remembered until this is
 * called, so a theme installed meanwhile is listed. */
+ (void)forgetInstalledThemes;
/* Legacy bundle discovery, retained for older project metadata/tools. */
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
 * Architecture, BuildOnly, GNUstep}]: "My Mac", "My Mac (Rosetta)" on Apple
 * silicon with Rosetta installed, "My Mac (GNUstep)" where GNUstep is
 * installed, and "Any Mac". Destination is the value of
 * xcodebuild's -destination; BuildOnly is YES for "Any Mac", which builds
 * every architecture but cannot be run. */
+ (NSArray *)runDestinations;

/* GNUstep on macOS: the "My Mac (GNUstep)" run destination, offered where
 * GNUstep is installed, builds with GNUstep's make in the environment of
 * GNUstep.sh, and Run starts the GNUstep build. */

/* The folder of GNUstep.sh: GNUSTEP_MAKEFILES, else what gnustep-config
 * says (found on the PATH or in the tool folders), else the first of the
 * makefile folders that has it; nil without GNUstep. */
+ (NSString *)GNUstepMakefilesWithEnvironment:(NSDictionary *)environment
                                  toolFolders:(NSArray *)toolFolders
                              makefileFolders:(NSArray *)makefileFolders;
/* The folder of GNUstep.sh in path: path itself, the folder of a GNUstep.sh
 * file, or the Makefiles folder of an installation prefix (fhs, gnustep or
 * the Homebrew and MacPorts layouts); nil if there is none. */
+ (NSString *)GNUstepMakefilesInFolder:(NSString *)path;
/* The GNUstep chosen in the preferences (the user default GNUstep: an
 * installation prefix or the folder of GNUstep.sh), or nil to find one. */
+ (NSString *)chosenGNUstep;
/* GNUstep as this process finds it, with GNUstep's usual places, Homebrew
 * and MacPorts. Looked up once. */
+ (NSString *)foundGNUstepMakefiles;
/* The GNUstep that Build, Run and Archive use: the chosen one (nil if it has
 * no GNUstep.sh), else the one found. */
+ (NSString *)GNUstepMakefiles;
/* The environment after sourcing GNUstep.sh, or nil. */
+ (NSDictionary *)GNUstepEnvironmentForMakefiles:(NSString *)makefiles;
+ (NSDictionary *)GNUstepEnvironment;
/* Build environment including the project's application-linked Theme. An
 * unset Theme removes an inherited override so the application's default wins. */
+ (NSDictionary *)buildEnvironmentForProject:(NSDictionary *)projectDict;
+ (NSDictionary *)buildEnvironmentForProject:(NSDictionary *)projectDict
                            baseEnvironment:(NSDictionary *)environment;
/* Whether Build and Run go through GNUstep: always on GNUstep, and on macOS
 * when "My Mac (GNUstep)" is chosen. */
+ (BOOL)buildsWithGNUstepForProject:(NSDictionary *)projectDict;

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

/* Path of Xcode's xcodebuild, or nil without Xcode. It is found also when
 * xcode-select points at the Command Line Tools. */
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
/* The executable for the selected run target and configuration. GNUstep
 * queries the built-in PBX compiler; native macOS queries xcodebuild. */
/* Built-in GNUstep PBX compiler, packaged in ProjectCenter's framework.
 * No application makefile, script or sidecar is required. */
+ (NSString *)GNUstepBuildTool;
+ (NSArray *)GNUstepBuildArgumentsForProject:(NSDictionary *)projectDict action:(NSString *)action;
+ (NSString *)builtExecutableForProject:(NSDictionary *)projectDict;
@end
