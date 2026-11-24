/*
 PCDeployment.h

 Deployment of an Xcode project: the platforms that Archive builds
 shippable applications for, and the scripts that build and package them.

 This file is part of GNUstep ProjectCenter.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation; either version 2 of the License, or
 (at your option) any later version.
 */

#import <Foundation/Foundation.h>

/* The Deployment of an Xcode project lives in the build settings of its
 * targets, where Xcode leaves it alone (see +[PCXcodeProject
 * platformOfTarget:]):
 * - A Mac target has one platform, macOS, whose only setting is the
 *   target's ARCHS (Architectures); the rest comes from the Xcode project.
 * - A Linux target (SDKROOT = linux) lists its distributions in
 *   GNUSTEP_DISTRIBUTIONS (Debian, RPM, Linux: words of Kind) and keeps each
 *   one's settings as GNUSTEP_<KIND>_<SETTING> (KIND being DEBIAN, RPM or
 *   TARBALL, SETTING the key in capitals: GNUSTEP_DEBIAN_PACKAGE_NAME).
 *   ARCHS (Architectures) holds the architectures of all its distributions.
 * Settings are written into every configuration of the target, and only
 * when changed: one that is not there takes its default
 * (+defaultValueForKey:ofDeployment:project:). A deployment is a dictionary
 * of strings: Kind, Target (its name), Architectures, the settings, and for
 * Archive, Name and Architecture (one of them, in the kind's own words).
 * Foundation only, so the tests can use it.
 *
 * A GNUstep platform (all but macOS) is built in one of three ways (Build):
 * - Native: with this computer's GNUstep, for this computer's system and
 *   architecture.
 * - Toolchain: cross compiled with another GNUstep installation, made for
 *   the target system (Toolchain is the folder of its GNUstep.sh); the
 *   package is made here.
 * - Container: in a Docker or Podman container of the target system
 *   (Image, prepared by the Setup command), which builds and packages, for
 *   any architecture the container tool can run. The default image is
 *   ProjectCenter's own (GNUstep-image.Dockerfile, built by archive.sh when
 *   it is missing), with GNUstep built with clang and libobjc2. The project
 *   folder is mounted at its own path.
 * Without a build script, GNUstep platforms build with ProjectCenter's
 * compiler (pc-xcode-build.py), as Build does; else with make.
 * macOS is built with xcodebuild archive. */
@interface PCDeployment : NSObject

/* The kinds of platform, in menu order: [{Kind, Title, Summary, Platform}],
 * Platform being macOS, Linux or Windows. */
+ (NSArray *)kinds;
+ (NSDictionary *)kindNamed:(NSString *)kind;

/* The settings of a kind, in the order the editor shows them:
 * {Section} starts a section; a field is {Key, Title, Type, Help} with Type
 * Text, Choice (and Choices [[Title, Value]]) or Check (YES or NO). */
+ (NSArray *)fieldsForKind:(NSString *)kind;
/* The keys of the fields that the deployment's Build doesn't use. */
+ (NSSet *)unusedKeysOfDeployment:(NSDictionary *)deployment;

/* The kinds of a platform (macOS, Linux or Windows), in menu order. */
+ (NSArray *)kindsForPlatform:(NSString *)platform;
/* The build setting a setting of a kind is kept in; nil for those that are
 * not kept (Kind, Name, Enabled, Architecture). */
+ (NSString *)buildSettingForKey:(NSString *)key ofKind:(NSString *)kind;
/* The distributions (kinds) of a Linux target, in its order. */
+ (NSArray *)distributionsOfTarget:(NSDictionary *)target;
/* The deployments of a target, an entry of +[PCXcodeProject
 * overviewOfProjectAtPath:error:]: macOS for a Mac target, one for each
 * distribution of a Linux target. */
+ (NSArray *)deploymentsOfTarget:(NSDictionary *)target;
/* What Archive makes for the project at path (the .xcodeproj): macOS for
 * every Mac application target (with its own scheme where it has one), and
 * every distribution of each Linux target once for each architecture, with
 * Name and Architecture. */
+ (NSArray *)deploymentsOfProjectAtPath:(NSString *)path;
/* The deployments for the targets that the toolbar scheme archives. */
+ (NSArray *)deploymentsForProject:(NSDictionary *)project scheme:(NSDictionary *)scheme;

/* Edits, written into the target's build settings at once. An empty or nil
 * value removes the setting. */
+ (BOOL)setValue:(NSString *)value
          forKey:(NSString *)key
    ofDeployment:(NSDictionary *)deployment
          target:(NSDictionary *)target
   projectAtPath:(NSString *)path
           error:(NSString **)error;
+ (BOOL)addDistribution:(NSString *)kind
               toTarget:(NSDictionary *)target
          projectAtPath:(NSString *)path
                  error:(NSString **)error;
/* Removes the distribution and its settings. */
+ (BOOL)removeDistribution:(NSString *)kind
                fromTarget:(NSDictionary *)target
             projectAtPath:(NSString *)path
                     error:(NSString **)error;
/* The deployment as another kind: it keeps the settings the new kind has
 * too. */
+ (NSDictionary *)deployment:(NSDictionary *)deployment changedToKind:(NSString *)kind;
/* Changes a distribution of a target into another, in its place; refused if
 * the target has that one already. */
+ (BOOL)changeDistribution:(NSDictionary *)deployment
                    toKind:(NSString *)kind
                  ofTarget:(NSDictionary *)target
             projectAtPath:(NSString *)path
                     error:(NSString **)error;

/* The product of the project read by +[PCXcodeProject projectAtPath:error:]:
 * {Target, Product, DisplayName, Version, Identifier}, from its Release
 * build settings and Info.plist. */
+ (NSDictionary *)productOfProject:(NSDictionary *)projectDict;
/* The value a setting has when the deployment doesn't set it. */
+ (NSString *)defaultValueForKey:(NSString *)key
                    ofDeployment:(NSDictionary *)deployment
                         project:(NSDictionary *)projectDict;
/* The setting, or its default. */
+ (NSString *)valueForKey:(NSString *)key
             ofDeployment:(NSDictionary *)deployment
                  project:(NSDictionary *)projectDict;
/* The file Archive makes for the deployment (RPM packages are named by
 * rpmbuild, so this is the expected name). */
+ (NSString *)fileNameOfDeployment:(NSDictionary *)deployment
                           project:(NSDictionary *)projectDict;

/* What keeps this computer from archiving the deployment: sentences such as
 * "dpkg-deb is not installed (brew install dpkg).", empty when it can. */
+ (NSArray *)problemsWithDeployment:(NSDictionary *)deployment
                            project:(NSDictionary *)projectDict;

/* The scripts that archive the deployments into folder: {File name: text},
 * archive.sh running the others, one for each deployment. They are kept in
 * build/Deployment of the project folder, which the container mounts, and
 * folder must be inside the project folder too. makeTool is GNUstep's make
 * for native and toolchain builds. */
+ (NSDictionary *)archiveScriptsForProject:(NSDictionary *)projectDict
                               deployments:(NSArray *)deployments
                                    folder:(NSString *)folder
                                  makeTool:(NSString *)makeTool;
/* Writes them and returns the path of archive.sh, or nil. */
+ (NSString *)writeArchiveScriptsForProject:(NSDictionary *)projectDict
                                deployments:(NSArray *)deployments
                                     folder:(NSString *)folder
                                   makeTool:(NSString *)makeTool
                                      error:(NSString **)error;
/* A new folder for an archive: build/Archives/<Product> <date and time>. */
+ (NSString *)archiveFolderForProject:(NSDictionary *)projectDict;

/* This computer: macOS, Linux or Windows, and its architecture as uname
 * says it (arm64, x86_64, aarch64...). */
+ (NSString *)hostPlatform;
+ (NSString *)hostMachine;
/* A file of ProjectCenter's resources (pc-xcode-build.py,
 * GNUstep-image.Dockerfile, gnustep-image.sh), else of the folder in the
 * environment variable PROJECTCENTER_RESOURCES (for the tests), or nil. */
+ (NSString *)pathOfResource:(NSString *)file;
/* A command line tool on the PATH or in the usual places of Homebrew,
 * MacPorts and Docker, or nil. */
+ (NSString *)pathOfTool:(NSString *)name;

@end
