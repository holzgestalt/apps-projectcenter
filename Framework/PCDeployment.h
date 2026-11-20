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

/* The platforms are kept as Deployment in GNUstep/ProjectCenter.plist, an
 * array of dictionaries of strings: Kind (macOS, Debian, RPM, Linux or
 * Windows), Name, Enabled (YES or NO) and the settings of the kind (see
 * +fieldsForKind:). A setting that is not there takes its default
 * (+defaultValueForKey:ofDeployment:project:), so a platform holds only
 * what was changed. Foundation only, so the tests can use it.
 *
 * A GNUstep platform (all but macOS) is built in one of three ways (Build):
 * - Native: with this computer's GNUstep, for this computer's system and
 *   architecture.
 * - Toolchain: cross compiled with another GNUstep installation, made for
 *   the target system (Toolchain is the folder of its GNUstep.sh); the
 *   package is made here.
 * - Container: in a Docker or Podman container of the target system
 *   (Image, prepared by the Setup command), which builds and packages, for
 *   any architecture the container tool can run.
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

/* The deployments of the project at path (the .xcodeproj), and saving them.
 * An empty list removes the Deployment setting. */
+ (NSArray *)deploymentsOfProjectAtPath:(NSString *)path;
+ (BOOL)setDeployments:(NSArray *)deployments
       ofProjectAtPath:(NSString *)path
                 error:(NSString **)error;

/* A new platform of a kind, enabled, with a name not yet used. */
+ (NSDictionary *)deploymentOfKind:(NSString *)kind
                          existing:(NSArray *)deployments
                        forProject:(NSDictionary *)projectDict;
/* The deployment as another kind: it keeps Enabled and the settings the new
 * kind has too, and its architecture where the new kind builds for it; a
 * name made from the old kind is made again, a name of the user's own kept.
 * deployments are all of them, this one included. */
+ (NSDictionary *)deployment:(NSDictionary *)deployment
               changedToKind:(NSString *)kind
                    existing:(NSArray *)deployments
                  forProject:(NSDictionary *)projectDict;

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
/* A command line tool on the PATH or in the usual places of Homebrew,
 * MacPorts and Docker, or nil. */
+ (NSString *)pathOfTool:(NSString *)name;

@end
