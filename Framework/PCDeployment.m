/*
 PCDeployment.m

 Deployment of an Xcode project: the platforms that Archive builds
 shippable applications for, and the scripts that build and package them.

 This file is part of GNUstep ProjectCenter.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation; either version 2 of the License, or
 (at your option) any later version.
 */

#import "PCDeployment.h"
#import "PCXcodeProject.h"

#include <sys/utsname.h>

static NSString * const PCDeploymentKey = @"Deployment";

// --- Kinds and their settings

static NSDictionary *Kind(NSString *kind, NSString *title, NSString *summary, NSString *platform)
{
  return [NSDictionary dictionaryWithObjectsAndKeys:kind, @"Kind", title, @"Title",
          summary, @"Summary", platform, @"Platform", nil];
}

static NSDictionary *Section(NSString *title)
{
  return [NSDictionary dictionaryWithObject:title forKey:@"Section"];
}

static NSDictionary *Text(NSString *key, NSString *title, NSString *help)
{
  return [NSDictionary dictionaryWithObjectsAndKeys:key, @"Key", title, @"Title", @"Text", @"Type",
          help, @"Help", nil];
}

static NSDictionary *Check(NSString *key, NSString *title, NSString *help)
{
  return [NSDictionary dictionaryWithObjectsAndKeys:key, @"Key", title, @"Title", @"Check", @"Type",
          help, @"Help", nil];
}

static NSDictionary *Choice(NSString *key, NSString *title, NSArray *choices, NSString *help)
{
  return [NSDictionary dictionaryWithObjectsAndKeys:key, @"Key", title, @"Title", @"Choice", @"Type",
          choices, @"Choices", help, @"Help", nil];
}

/* [[Title, Value]] for values that are their own titles. */
static NSArray *Plain(NSArray *values)
{
  NSMutableArray *choices = [NSMutableArray array];

  for (NSString *value in values)
  {
    [choices addObject:[NSArray arrayWithObjects:value, value, nil]];
  }
  return choices;
}

static NSArray *Architectures(NSString *kind)
{
  if ([kind isEqual:@"Debian"]) return @[@"amd64", @"arm64", @"armhf", @"i386", @"riscv64"];
  if ([kind isEqual:@"Windows"]) return @[@"x86_64", @"i686"];
  return @[@"x86_64", @"aarch64"];
}

/* The name of a machine (as uname says it) in a kind's packages. */
static NSString *ArchitectureOfMachine(NSString *kind, NSString *machine)
{
  BOOL arm64 = [machine isEqual:@"arm64"] || [machine isEqual:@"aarch64"];
  BOOL x86 = [machine isEqual:@"i386"] || [machine isEqual:@"i686"];

  if ([kind isEqual:@"Debian"])
  {
    if ([machine isEqual:@"x86_64"]) return @"amd64";
    if (arm64) return @"arm64";
    if ([machine hasPrefix:@"armv7"]) return @"armhf";
    if (x86) return @"i386";
    return machine;
  }
  if (arm64) return @"aarch64";
  if (x86) return @"i686";
  return machine;
}

/* docker run --platform for an architecture of any kind. */
static NSString *ContainerPlatform(NSString *architecture)
{
  NSDictionary *platforms = @{@"amd64": @"linux/amd64", @"x86_64": @"linux/amd64",
                              @"arm64": @"linux/arm64", @"aarch64": @"linux/arm64",
                              @"armhf": @"linux/arm/v7", @"i386": @"linux/386", @"i686": @"linux/386",
                              @"riscv64": @"linux/riscv64"};

  return [platforms objectForKey:architecture];
}

static BOOL IsGNUstepKind(NSString *kind)
{
  return [kind isEqual:@"Debian"] || [kind isEqual:@"RPM"] || [kind isEqual:@"Linux"]
  || [kind isEqual:@"Windows"];
}

// --- Shell scripts

/* A word for /bin/sh: single quoted. */
static NSString *SQ(NSString *string)
{
  return [NSString stringWithFormat:@"'%@'", [(string ? string : @"")
                                              stringByReplacingOccurrencesOfString:@"'"
                                              withString:@"'\\''"]];
}

static NSString *Trimmed(id value)
{
  if (![value isKindOfClass:[NSString class]]) return @"";
  return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

/* A path inside the project folder as "$ROOT/...", so a script works in the
 * container, which mounts the folder elsewhere; others as they are. */
static NSString *RootPath(NSString *path, NSString *root)
{
  NSString *prefix = [root stringByAppendingString:@"/"];

  if ([path isEqual:root]) return @"\"$ROOT\"";
  if ([path hasPrefix:prefix]) return [@"\"$ROOT\"/" stringByAppendingString:SQ([path substringFromIndex:[prefix length]])];
  return SQ(path);
}

@implementation PCDeployment

+ (NSArray *)kinds
{
  return @[Kind(@"macOS", @"macOS", @"Application, as a zip archive or disk image", @"macOS"),
           Kind(@"Debian", @"Debian / Ubuntu", @".deb package", @"Linux"),
           Kind(@"RPM", @"Fedora / openSUSE", @".rpm package", @"Linux"),
           Kind(@"Linux", @"Linux", @".tar.gz archive of the application", @"Linux"),
           Kind(@"Windows", @"Windows", @".zip archive of the application", @"Windows")];
}

+ (NSDictionary *)kindNamed:(NSString *)kind
{
  for (NSDictionary *entry in [self kinds])
  {
    if ([[entry objectForKey:@"Kind"] isEqual:kind]) return entry;
  }
  return nil;
}

+ (NSArray *)fieldsForKind:(NSString *)kind
{
  NSMutableArray *fields = [NSMutableArray array];
  NSString       *installHelp = @"Where the package installs the application bundle.";

  NSMutableArray *kinds = [NSMutableArray array];

  for (NSDictionary *entry in [self kinds])
  {
    [kinds addObject:[NSArray arrayWithObjects:[entry objectForKey:@"Title"], [entry objectForKey:@"Kind"], nil]];
  }
  [fields addObject:Section(@"Platform")];
  [fields addObject:Choice(@"Kind", @"Platform", kinds,
                           @"The system Archive builds for, and the kind of file it makes. Settings that the "
                           @"new platform has too are kept.")];
  [fields addObject:Text(@"Name", @"Name", @"The platform's name in the list and in the Archive log.")];
  if ([kind isEqual:@"macOS"])
  {
    [fields addObject:Section(@"Build")];
    [fields addObject:Text(@"Scheme", @"Scheme", @"The scheme xcodebuild archives.")];
    [fields addObject:Text(@"Configuration", @"Configuration",
                           @"The build configuration; by default the scheme's Archive configuration.")];
    [fields addObject:Choice(@"Architecture", @"Architectures",
                             @[@[@"Project Setting", @""], @[@"Universal (arm64, x86_64)", @"universal"],
                               @[@"Apple silicon (arm64)", @"arm64"], @[@"Intel (x86_64)", @"x86_64"]],
                             @"ARCHS for the archive; Project Setting keeps the project's own.")];
    [fields addObject:Section(@"Signing")];
    [fields addObject:Text(@"SigningIdentity", @"Signing Identity",
                           @"A codesign identity, such as \"Developer ID Application: Name (TEAM)\". "
                           @"Empty signs as the project's settings say.")];
    [fields addObject:Text(@"NotaryProfile", @"Notary Profile",
                           @"A keychain profile of notarytool (xcrun notarytool store-credentials). "
                           @"Empty doesn't notarize.")];
    [fields addObject:Section(@"Package")];
    [fields addObject:Choice(@"Format", @"Format", @[@[@"Zip Archive", @"zip"], @[@"Disk Image", @"dmg"]],
                             @"A zip archive of the application, or a disk image with a link to Applications.")];
    [fields addObject:Text(@"FileName", @"File Name", @"The name of the file Archive makes.")];
    return fields;
  }

  [fields addObject:Section(@"Build")];
  [fields addObject:Choice(@"Build", @"Build",
                           @[@[@"Native", @"Native"], @[@"Cross Toolchain", @"Toolchain"],
                             @[@"Container", @"Container"]],
                           @"Native builds with this computer's GNUstep; Cross Toolchain with a GNUstep "
                           @"made for the target; Container in a Docker or Podman container.")];
  [fields addObject:Choice(@"Architecture", @"Architecture", Plain(Architectures(kind)),
                           @"The architecture the application is built and packaged for.")];
  [fields addObject:Text(@"Configuration", @"Configuration",
                         @"Debug builds with debug=yes, any other configuration with debug=no.")];
  [fields addObject:Text(@"Toolchain", @"Toolchain",
                         @"For Cross Toolchain: the folder of GNUstep.sh of a GNUstep installation "
                         @"made for the target, such as a sysroot's Makefiles folder.")];
  if (![kind isEqual:@"Windows"])
  {
    [fields addObject:Text(@"Image", @"Container Image",
                           @"For Container: the image to build in, with GNUstep, or a system the Setup "
                           @"command installs it on.")];
    [fields addObject:Text(@"Setup", @"Container Setup",
                           @"For Container: a shell command run in the container before the build. "
                           @"Empty for an image that has everything.")];
  }
  [fields addObject:Text(@"MakeArguments", @"Make Arguments",
                         @"More arguments for make or the build script, such as \"strip=yes\".")];

  if ([kind isEqual:@"Debian"] || [kind isEqual:@"RPM"])
  {
    BOOL deb = [kind isEqual:@"Debian"];

    [fields addObject:Section(@"Package")];
    [fields addObject:Text(@"PackageName", @"Package Name", @"The name of the package, in lowercase.")];
    [fields addObject:Text(@"Version", @"Version", @"The package version; by default the project's.")];
    if (!deb)
    {
      [fields addObject:Text(@"Release", @"Release", @"The release of this version of the package.")];
      [fields addObject:Text(@"License", @"License", @"The license, such as GPL-2.0-or-later.")];
    }
    else
    {
      [fields addObject:Text(@"Maintainer", @"Maintainer", @"Name and email address, \"Name <address>\".")];
      [fields addObject:Text(@"Section", @"Section", @"The archive section of the package.")];
    }
    [fields addObject:Text(@"Summary", @"Summary", @"One line that describes the application.")];
    [fields addObject:Text(@"Homepage", @"Homepage", @"The application's web site.")];
    [fields addObject:Text(@"Depends", deb ? @"Depends" : @"Requires",
                           @"More packages the application needs, separated by commas.")];
    [fields addObject:Check(@"AutomaticDependencies", @"Find Dependencies",
                            deb ? @"Adds the packages of the libraries the application links, and of "
                            @"GNUstep's back end, where dpkg knows them (Native and Container)."
                            : @"Lets rpmbuild add the libraries the application links.")];
    [fields addObject:Section(@"Installation")];
    [fields addObject:Text(@"InstallFolder", @"Install Folder", installHelp)];
    [fields addObject:Check(@"Launcher", @"Command", @"Installs a command in /usr/bin that starts the application.")];
    [fields addObject:Text(@"Categories", @"Menu Categories",
                           @"Categories of the desktop entry, separated by semicolons; empty makes no entry.")];
    [fields addObject:Text(@"Icon", @"Icon", @"A PNG or SVG file of the project for the desktop entry.")];
  }
  else
  {
    [fields addObject:Section(@"Package")];
    [fields addObject:Text(@"Version", @"Version", @"The version in the file name; by default the project's.")];
    if ([kind isEqual:@"Windows"])
    {
      [fields addObject:Check(@"IncludeLibraries", @"Include DLLs",
                              @"Copies the DLLs the application needs from GNUstep's folders next to it.")];
      [fields addObject:Text(@"LibraryFolders", @"Library Folders",
                             @"More folders to find DLLs in, separated by colons.")];
    }
  }
  [fields addObject:Text(@"FileName", @"File Name", @"The name of the file Archive makes.")];
  return fields;
}

+ (NSSet *)unusedKeysOfDeployment:(NSDictionary *)deployment
{
  NSString     *kind = [deployment objectForKey:@"Kind"];
  NSString     *build = [self valueForKey:@"Build" ofDeployment:deployment project:nil];
  NSMutableSet *keys = [NSMutableSet set];

  if (!IsGNUstepKind(kind)) return keys;
  if (![build isEqual:@"Toolchain"]) [keys addObject:@"Toolchain"];
  if (![build isEqual:@"Container"])
  {
    [keys addObject:@"Image"];
    [keys addObject:@"Setup"];
  }
  return keys;
}

// --- Saving

+ (NSArray *)deploymentsOfProjectAtPath:(NSString *)path
{
  id             list = [[PCXcodeProject GNUstepSettingsOfProjectAtPath:path] objectForKey:PCDeploymentKey];
  NSMutableArray *deployments = [NSMutableArray array];

  if (![list isKindOfClass:[NSArray class]]) return deployments;
  for (id entry in list)
  {
    if ([entry isKindOfClass:[NSDictionary class]] && [self kindNamed:[entry objectForKey:@"Kind"]])
    {
      [deployments addObject:entry];
    }
  }
  return deployments;
}

+ (BOOL)setDeployments:(NSArray *)deployments
       ofProjectAtPath:(NSString *)path
                 error:(NSString **)error
{
  NSMutableArray *list = [NSMutableArray array];

  /* Only what is set: empty settings take their defaults. */
  for (NSDictionary *deployment in deployments)
  {
    NSMutableDictionary *entry = [NSMutableDictionary dictionary];

    for (NSString *key in deployment)
    {
      NSString *value = Trimmed([deployment objectForKey:key]);

      if ([value length]) [entry setObject:value forKey:key];
    }
    [list addObject:entry];
  }
  return [PCXcodeProject setGNUstepValue:list forKey:PCDeploymentKey ofProjectAtPath:path error:error];
}

+ (NSDictionary *)deploymentOfKind:(NSString *)kind
                          existing:(NSArray *)deployments
                        forProject:(NSDictionary *)projectDict
{
  NSString            *title = [[self kindNamed:kind] objectForKey:@"Title"];
  NSMutableDictionary *deployment = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                     kind, @"Kind", @"YES", @"Enabled", nil];
  NSArray             *names = [deployments valueForKey:@"Name"];
  NSString            *name = title;
  NSUInteger          number = 2;

  if (title == nil) return nil;
  /* Another one of a kind is usually another architecture. */
  if (IsGNUstepKind(kind))
  {
    NSString *architecture = [self defaultValueForKey:@"Architecture" ofDeployment:deployment project:projectDict];

    for (NSDictionary *other in deployments)
    {
      if ([[other objectForKey:@"Kind"] isEqual:kind])
      {
        for (NSString *candidate in Architectures(kind))
        {
          BOOL used = NO;

          for (NSDictionary *existing in deployments)
          {
            used = used || ([[existing objectForKey:@"Kind"] isEqual:kind]
                            && [[self valueForKey:@"Architecture" ofDeployment:existing project:projectDict]
                                isEqual:candidate]);
          }
          if (!used)
          {
            architecture = candidate;
            break;
          }
        }
        [deployment setObject:architecture forKey:@"Architecture"];
        break;
      }
    }
    name = [NSString stringWithFormat:@"%@ (%@)", title, architecture];
  }
  while ([names containsObject:name])
  {
    name = [NSString stringWithFormat:@"%@ %lu", title, (unsigned long)number++];
  }
  [deployment setObject:name forKey:@"Name"];
  return deployment;
}

/* Whether name is one +deploymentOfKind:... makes from a kind's title. */
static BOOL IsMadeName(NSString *name, NSString *title)
{
  NSString *rest;

  if (title == nil || ![name hasPrefix:title]) return NO;
  rest = [name substringFromIndex:[title length]];
  if ([rest length] == 0) return YES;
  if ([rest hasPrefix:@" ("] && [rest hasSuffix:@")"]) return YES;
  return [rest hasPrefix:@" "] && [rest length] > 1
    && [[rest substringFromIndex:1] rangeOfCharacterFromSet:
        [[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location == NSNotFound;
}

+ (NSDictionary *)deployment:(NSDictionary *)deployment
               changedToKind:(NSString *)kind
                    existing:(NSArray *)deployments
                  forProject:(NSDictionary *)projectDict
{
  NSString            *oldKind = [deployment objectForKey:@"Kind"];
  NSMutableArray      *others = [NSMutableArray arrayWithArray:deployments];
  NSMutableDictionary *changed;
  NSMutableSet        *keys = [NSMutableSet set];
  NSString            *oldTitle = [[self kindNamed:oldKind] objectForKey:@"Title"];
  NSString            *name = [deployment objectForKey:@"Name"];
  NSString            *architecture = [deployment objectForKey:@"Architecture"];

  if ([self kindNamed:kind] == nil) return nil;
  if ([kind isEqual:oldKind]) return deployment;
  [others removeObjectIdenticalTo:deployment];
  changed = [NSMutableDictionary dictionaryWithDictionary:[self deploymentOfKind:kind existing:others
                                                                      forProject:projectDict]];
  for (NSDictionary *field in [self fieldsForKind:kind])
  {
    if ([field objectForKey:@"Key"]) [keys addObject:[field objectForKey:@"Key"]];
  }
  /* The settings the new kind has too; an architecture only if the new kind
   * builds for it. */
  for (NSString *key in deployment)
  {
    if ([key isEqual:@"Kind"] || [key isEqual:@"Name"] || [key isEqual:@"Architecture"]) continue;
    if ([keys containsObject:key] || [key isEqual:@"Enabled"]) [changed setObject:[deployment objectForKey:key] forKey:key];
  }
  if (architecture && IsGNUstepKind(kind) && [Architectures(kind) containsObject:architecture])
  {
    [changed setObject:architecture forKey:@"Architecture"];
    if (![[changed objectForKey:@"Name"] hasSuffix:[NSString stringWithFormat:@"(%@)", architecture]])
    {
      [changed setObject:[NSString stringWithFormat:@"%@ (%@)", [[self kindNamed:kind] objectForKey:@"Title"],
                          architecture] forKey:@"Name"];
    }
  }
  /* A name of the user's own is kept; one made from the old kind ("Title",
   * "Title (arm64)" or "Title 2") is made again for the new one. */
  if (name && !IsMadeName(name, oldTitle))
  {
    [changed setObject:name forKey:@"Name"];
  }
  return changed;
}

// --- Defaults

/* $(NAME), ${NAME} and $(NAME:modifier) from build settings. */
static NSString *Expanded(NSString *value, NSDictionary *settings)
{
  NSMutableString *text = [NSMutableString stringWithString:Trimmed(value)];
  NSUInteger      pass;

  for (pass = 0; pass < 4; pass++)
  {
    BOOL changed = NO;

    for (NSString *open in @[@"$(", @"${"])
    {
      NSString *close = [open isEqual:@"$("] ? @")" : @"}";
      NSRange  start;

      while ((start = [text rangeOfString:open]).location != NSNotFound)
      {
        NSRange  end = [text rangeOfString:close options:0
                                     range:NSMakeRange(NSMaxRange(start), [text length] - NSMaxRange(start))];
        NSString *name;
        id       replacement;

        if (end.location == NSNotFound) break;
        name = [text substringWithRange:NSMakeRange(NSMaxRange(start), end.location - NSMaxRange(start))];
        name = [[name componentsSeparatedByString:@":"] objectAtIndex:0];
        replacement = [settings objectForKey:name];
        [text replaceCharactersInRange:NSMakeRange(start.location, NSMaxRange(end) - start.location)
                            withString:[replacement isKindOfClass:[NSString class]] ? replacement : @""];
        changed = YES;
      }
    }
    if (!changed) break;
  }
  return text;
}

+ (NSDictionary *)productOfProject:(NSDictionary *)projectDict
{
  NSString            *path = [projectDict objectForKey:@"XCODE_PROJECT_PATH"];
  NSString            *targetName = [projectDict objectForKey:@"PROJECT_NAME"];
  NSDictionary        *overview = path ? [PCXcodeProject overviewOfProjectAtPath:path error:NULL] : nil;
  NSMutableDictionary *settings = [NSMutableDictionary dictionary];
  NSDictionary        *target = nil;
  NSDictionary        *info = nil;
  NSString            *product, *version, *display, *identifier, *infoFile;

  for (NSDictionary *candidate in [overview objectForKey:@"Targets"])
  {
    if ([[candidate objectForKey:@"Name"] isEqual:targetName]) target = candidate;
  }
  /* Release, as Archive builds it; else the last configuration. */
  for (NSArray *configurations in @[[overview objectForKey:@"Configurations"] ?: @[],
                                    [target objectForKey:@"Configurations"] ?: @[]])
  {
    NSDictionary *chosen = [configurations lastObject];

    for (NSDictionary *configuration in configurations)
    {
      if ([[configuration objectForKey:@"Name"] isEqual:@"Release"]) chosen = configuration;
    }
    [settings addEntriesFromDictionary:[chosen objectForKey:@"Settings"]];
  }
  if (targetName == nil) targetName = @"Application";
  [settings setObject:targetName forKey:@"TARGET_NAME"];
  product = Expanded([settings objectForKey:@"PRODUCT_NAME"], settings);
  if (![product length]) product = [target objectForKey:@"ProductName"];
  if (![product length]) product = targetName;
  [settings setObject:product forKey:@"PRODUCT_NAME"];
  infoFile = Expanded([settings objectForKey:@"INFOPLIST_FILE"], settings);
  if ([infoFile length] && path)
  {
    info = [NSDictionary dictionaryWithContentsOfFile:
            [[path stringByDeletingLastPathComponent] stringByAppendingPathComponent:infoFile]];
    if (![info isKindOfClass:[NSDictionary class]]) info = nil;
  }
  version = Expanded([info objectForKey:@"CFBundleShortVersionString"], settings);
  if (![version length]) version = Expanded([settings objectForKey:@"MARKETING_VERSION"], settings);
  if (![version length]) version = @"1.0";
  display = Expanded([info objectForKey:@"CFBundleDisplayName"], settings);
  if (![display length]) display = Expanded([settings objectForKey:@"INFOPLIST_KEY_CFBundleDisplayName"], settings);
  if (![display length]) display = product;
  identifier = Expanded([info objectForKey:@"CFBundleIdentifier"], settings);
  if (![identifier length]) identifier = Expanded([settings objectForKey:@"PRODUCT_BUNDLE_IDENTIFIER"], settings);
  return [NSDictionary dictionaryWithObjectsAndKeys:targetName, @"Target", product, @"Product",
          display, @"DisplayName", version, @"Version", identifier ?: @"", @"Identifier", nil];
}

/* A package name: lowercase letters, digits, "+", "-" and ".". */
static NSString *PackageName(NSString *name)
{
  NSMutableString *package = [NSMutableString string];
  NSCharacterSet  *allowed = [NSCharacterSet characterSetWithCharactersInString:
                              @"abcdefghijklmnopqrstuvwxyz0123456789+-."];
  NSUInteger      i;

  name = [name lowercaseString];
  for (i = 0; i < [name length]; i++)
  {
    unichar c = [name characterAtIndex:i];

    if ([allowed characterIsMember:c]) [package appendFormat:@"%C", c];
    else if ([package length] && ![package hasSuffix:@"-"]) [package appendString:@"-"];
  }
  while ([package hasSuffix:@"-"]) [package deleteCharactersInRange:NSMakeRange([package length] - 1, 1)];
  return [package length] > 1 ? package : @"application";
}

+ (NSString *)defaultValueForKey:(NSString *)key
                    ofDeployment:(NSDictionary *)deployment
                         project:(NSDictionary *)projectDict
{
  NSString *kind = [deployment objectForKey:@"Kind"];
  NSString *platform = [[self kindNamed:kind] objectForKey:@"Platform"];

  if ([key isEqual:@"Name"]) return [[self kindNamed:kind] objectForKey:@"Title"];
  if ([key isEqual:@"Enabled"] || [key isEqual:@"AutomaticDependencies"] || [key isEqual:@"Launcher"]
      || [key isEqual:@"IncludeLibraries"])
  {
    return @"YES";
  }
  if ([key isEqual:@"Build"])
  {
    if (!IsGNUstepKind(kind)) return @"";
    if ([[self hostPlatform] isEqual:platform]) return @"Native";
    return [kind isEqual:@"Windows"] ? @"Toolchain" : @"Container";
  }
  if ([key isEqual:@"Architecture"])
  {
    NSString *native;

    if (!IsGNUstepKind(kind)) return @"";
    native = ArchitectureOfMachine(kind, [self hostMachine]);
    return [Architectures(kind) containsObject:native] ? native : [Architectures(kind) objectAtIndex:0];
  }
  if ([key isEqual:@"Configuration"])
  {
    NSString *configuration = nil;

    if ([kind isEqual:@"macOS"] && projectDict)
    {
      NSString *scheme = [self valueForKey:@"Scheme" ofDeployment:deployment project:projectDict];

      for (NSDictionary *entry in [PCXcodeProject schemesOfProjectAtPath:
                                   [projectDict objectForKey:@"XCODE_PROJECT_PATH"]])
      {
        if ([[entry objectForKey:@"Name"] isEqual:scheme])
        {
          configuration = [[entry objectForKey:@"Configurations"] objectForKey:@"Archive"];
        }
      }
    }
    return [configuration length] ? configuration : @"Release";
  }
  if ([key isEqual:@"Scheme"])
  {
    NSString *scheme = projectDict ? [[[PCXcodeProject buildSelectionForProject:projectDict]
                                       objectForKey:@"Scheme"] objectForKey:@"Name"] : nil;

    return scheme ? scheme : [[self productOfProject:projectDict] objectForKey:@"Target"];
  }
  if ([key isEqual:@"Format"]) return @"zip";
  if ([key isEqual:@"Image"])
  {
    return [kind isEqual:@"RPM"] ? @"fedora:latest" : @"debian:stable";
  }
  if ([key isEqual:@"Setup"])
  {
    if ([kind isEqual:@"RPM"])
    {
      return @"dnf install -y -q make gcc-objc gnustep-make gnustep-base-devel gnustep-gui-devel "
      @"gnustep-back rpm-build";
    }
    return @"apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "
    @"gnustep-devel >/dev/null";
  }
  if ([key isEqual:@"Version"]) return [[self productOfProject:projectDict] objectForKey:@"Version"];
  if ([key isEqual:@"PackageName"])
  {
    return PackageName([[self productOfProject:projectDict] objectForKey:@"Product"]);
  }
  if ([key isEqual:@"Summary"]) return [[self productOfProject:projectDict] objectForKey:@"DisplayName"];
  if ([key isEqual:@"Maintainer"])
  {
    NSString *name = NSFullUserName();

    return [name length] ? name : NSUserName();
  }
  if ([key isEqual:@"Section"]) return @"gnustep";
  if ([key isEqual:@"Release"]) return @"1";
  if ([key isEqual:@"License"]) return @"Proprietary";
  if ([key isEqual:@"InstallFolder"]) return @"/usr/lib/GNUstep/Applications";
  if ([key isEqual:@"Categories"]) return @"GNUstep;Utility;";
  if ([key isEqual:@"FileName"]) return [self _defaultFileNameOfDeployment:deployment project:projectDict];
  return @"";
}

+ (NSString *)valueForKey:(NSString *)key
             ofDeployment:(NSDictionary *)deployment
                  project:(NSDictionary *)projectDict
{
  NSString *value = Trimmed([deployment objectForKey:key]);

  return [value length] ? value : [self defaultValueForKey:key ofDeployment:deployment project:projectDict];
}

+ (NSString *)_defaultFileNameOfDeployment:(NSDictionary *)deployment
                                   project:(NSDictionary *)projectDict
{
  NSString *kind = [deployment objectForKey:@"Kind"];
  NSString *product = [[[self productOfProject:projectDict] objectForKey:@"Product"]
                       stringByReplacingOccurrencesOfString:@" " withString:@""];
  NSString *version = [self valueForKey:@"Version" ofDeployment:deployment project:projectDict];
  NSString *architecture = [self valueForKey:@"Architecture" ofDeployment:deployment project:projectDict];

  if ([kind isEqual:@"macOS"])
  {
    return [NSString stringWithFormat:@"%@-%@.%@", product, version,
            [self valueForKey:@"Format" ofDeployment:deployment project:projectDict]];
  }
  if ([kind isEqual:@"Debian"])
  {
    return [NSString stringWithFormat:@"%@_%@_%@.deb",
            [self valueForKey:@"PackageName" ofDeployment:deployment project:projectDict], version, architecture];
  }
  if ([kind isEqual:@"RPM"])
  {
    return [NSString stringWithFormat:@"%@-%@-%@.%@.rpm",
            [self valueForKey:@"PackageName" ofDeployment:deployment project:projectDict],
            [version stringByReplacingOccurrencesOfString:@"-" withString:@"_"],
            [self valueForKey:@"Release" ofDeployment:deployment project:projectDict], architecture];
  }
  return [NSString stringWithFormat:@"%@-%@-%@-%@.%@", product, version,
          [kind isEqual:@"Windows"] ? @"windows" : @"linux", architecture,
          [kind isEqual:@"Windows"] ? @"zip" : @"tar.gz"];
}

+ (NSString *)fileNameOfDeployment:(NSDictionary *)deployment
                           project:(NSDictionary *)projectDict
{
  return [[self valueForKey:@"FileName" ofDeployment:deployment project:projectDict] lastPathComponent];
}

// --- This computer

+ (NSString *)hostPlatform
{
#if defined(__APPLE__)
  return @"macOS";
#elif defined(_WIN32) || defined(__MINGW32__)
  return @"Windows";
#else
  return @"Linux";
#endif
}

+ (NSString *)hostMachine
{
  struct utsname name;

  if (uname(&name) != 0) return @"";
  return [NSString stringWithUTF8String:name.machine];
}

+ (NSArray *)_toolFolders
{
  NSMutableArray *folders = [NSMutableArray arrayWithArray:
                             [[[[NSProcessInfo processInfo] environment] objectForKey:@"PATH"]
                              componentsSeparatedByString:@":"]];

  /* A GUI application has a short PATH. */
  [folders addObjectsFromArray:@[@"/usr/local/bin", @"/opt/homebrew/bin", @"/opt/local/bin",
                                 @"/usr/bin", @"/bin", @"/usr/sbin",
                                 @"/Applications/Docker.app/Contents/Resources/bin"]];
  return folders;
}

+ (NSString *)pathOfTool:(NSString *)name
{
  for (NSString *folder in [self _toolFolders])
  {
    NSString *path = [folder stringByAppendingPathComponent:name];

    if ([folder length] && [[NSFileManager defaultManager] isExecutableFileAtPath:path]) return path;
  }
  return nil;
}

+ (NSString *)_containerTool
{
  NSString *tool = [self pathOfTool:@"docker"];

  return tool ? tool : [self pathOfTool:@"podman"];
}

/* The folder of GNUstep.sh for native builds: the GNUstep chosen in the
 * preferences, else the one found (GNUSTEP_MAKEFILES first), or nil. */
+ (NSString *)_nativeMakefiles
{
  return [PCXcodeProject GNUstepMakefiles];
}

+ (NSArray *)problemsWithDeployment:(NSDictionary *)deployment
                            project:(NSDictionary *)projectDict
{
  NSMutableArray *problems = [NSMutableArray array];
  NSString       *kind = [deployment objectForKey:@"Kind"];
  NSString       *platform = [[self kindNamed:kind] objectForKey:@"Platform"];
  NSString       *build = [self valueForKey:@"Build" ofDeployment:deployment project:projectDict];
  NSString       *architecture = [self valueForKey:@"Architecture" ofDeployment:deployment project:projectDict];
  NSString       *root = [[projectDict objectForKey:@"XCODE_PROJECT_PATH"] stringByDeletingLastPathComponent];
  BOOL           packagesHere = YES;
  NSString       *brew = [[self hostPlatform] isEqual:@"macOS"] ? @"brew install " : nil;

  if (platform == nil)
  {
    return [NSArray arrayWithObject:[NSString stringWithFormat:@"%@ is not a known platform.", kind]];
  }
  if ([kind isEqual:@"macOS"])
  {
    if (![[self hostPlatform] isEqual:@"macOS"] || [PCXcodeProject xcodebuildPath] == nil)
    {
      [problems addObject:@"macOS applications are archived on a Mac with Xcode."];
    }
    return problems;
  }
  if (root == nil || (![projectDict objectForKey:@"XCODE_BuildScript"]
                      && ![[NSFileManager defaultManager] fileExistsAtPath:
                           [root stringByAppendingPathComponent:@"GNUmakefile"]]))
  {
    [problems addObject:@"The project has no GNUmakefile or GNUstep build script."];
  }
  if ([build isEqual:@"Native"])
  {
    NSString *native = ArchitectureOfMachine(kind, [self hostMachine]);

    if (![[self hostPlatform] isEqual:platform])
    {
      [problems addObject:[NSString stringWithFormat:@"Native builds for %@ need a %@ computer; "
                           @"choose Container or Cross Toolchain.", platform, platform]];
    }
    else if (![native isEqual:architecture])
    {
      [problems addObject:[NSString stringWithFormat:@"This computer builds %@ natively, not %@; "
                           @"choose Container or Cross Toolchain.", native, architecture]];
    }
    if ([PCXcodeProject chosenGNUstep] && [self _nativeMakefiles] == nil)
    {
      [problems addObject:[NSString stringWithFormat:@"There is no GNUstep.sh in %@, the GNUstep chosen "
                           @"in Preferences → Misc.", [PCXcodeProject chosenGNUstep]]];
    }
    else if ([self _nativeMakefiles] == nil && [self pathOfTool:@"gnustep-config"] == nil)
    {
      [problems addObject:@"GNUstep is not installed on this computer, or choose it in Preferences → Misc."];
    }
  }
  else if ([build isEqual:@"Toolchain"])
  {
    NSString *toolchain = [[self valueForKey:@"Toolchain" ofDeployment:deployment project:projectDict]
                           stringByExpandingTildeInPath];

    if (![toolchain length])
    {
      [problems addObject:@"Set Toolchain to the folder of GNUstep.sh of a GNUstep made for the target."];
    }
    else if (![[NSFileManager defaultManager] fileExistsAtPath:[toolchain stringByAppendingPathComponent:@"GNUstep.sh"]])
    {
      [problems addObject:[NSString stringWithFormat:@"There is no GNUstep.sh in %@.", toolchain]];
    }
  }
  else if ([build isEqual:@"Container"])
  {
    packagesHere = NO;
    if ([kind isEqual:@"Windows"])
    {
      [problems addObject:@"Windows applications are built natively or with a cross toolchain."];
    }
    else if ([self _containerTool] == nil)
    {
      [problems addObject:@"Container builds need Docker or Podman, which is not installed."];
    }
    if (![[self valueForKey:@"Image" ofDeployment:deployment project:projectDict] length])
    {
      [problems addObject:@"Set the Container Image."];
    }
    if (ContainerPlatform(architecture) == nil)
    {
      [problems addObject:[NSString stringWithFormat:@"Containers don't run %@.", architecture]];
    }
  }
  else
  {
    [problems addObject:[NSString stringWithFormat:@"%@ is not a way to build.", build]];
  }

  /* The package is made where the build runs. */
  if (packagesHere)
  {
    if ([kind isEqual:@"Debian"] && [self pathOfTool:@"dpkg-deb"] == nil)
    {
      [problems addObject:[NSString stringWithFormat:@"dpkg-deb is not installed%@.",
                           brew ? @" (brew install dpkg)" : @""]];
    }
    if ([kind isEqual:@"RPM"] && [self pathOfTool:@"rpmbuild"] == nil)
    {
      [problems addObject:[NSString stringWithFormat:@"rpmbuild is not installed%@.",
                           brew ? @" (brew install rpm)" : @""]];
    }
    if ([kind isEqual:@"Windows"] && ![self pathOfTool:@"zip"] && ![self pathOfTool:@"ditto"]
        && ![self pathOfTool:@"bsdtar"])
    {
      [problems addObject:@"zip is not installed."];
    }
  }
  return problems;
}

// --- Scripts

+ (NSString *)archiveFolderForProject:(NSDictionary *)projectDict
{
  NSString        *root = [[projectDict objectForKey:@"XCODE_PROJECT_PATH"] stringByDeletingLastPathComponent];
  NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
  NSString        *name;

  [formatter setLocale:[[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"] autorelease]];
  [formatter setDateFormat:@"yyyy-MM-dd HH.mm.ss"];
  name = [NSString stringWithFormat:@"%@ %@", [[self productOfProject:projectDict] objectForKey:@"Product"],
          [formatter stringFromDate:[NSDate date]]];
  return [[root stringByAppendingPathComponent:@"build/Archives"] stringByAppendingPathComponent:name];
}

/* The start of each deployment's script: ROOT and OUT from the arguments,
 * the files made in a container given to the user who archives. */
static void AppendPrologue(NSMutableString *s, NSString *name, NSString *identifier)
{
  [s appendFormat:@"#!/bin/sh\n# %@: written by ProjectCenter for Archive.\n", name];
  [s appendString:@"ROOT=\"$1\"\nOUT=\"$2\"\ncd \"$ROOT\" || exit 1\n"];
  [s appendFormat:@"BUILD=\"$ROOT/build/Deployment/%@\"\n", identifier];
  [s appendString:@"finish() {\n"
   @"  if [ -n \"$HOST_UID\" ] && [ \"$(id -u)\" = 0 ]; then\n"
   @"    chown -R \"$HOST_UID:$HOST_GID\" \"$BUILD\" \"$OUT\" 2>/dev/null\n"
   @"  fi\n"
   @"}\n"
   @"trap finish EXIT\n"];
}

/* The commands that build a GNUstep application and set APP, APPNAME and
 * EXE to the bundle, its name and its executable's name. */
static void AppendGNUstepBuild(NSMutableString *s, NSDictionary *deployment, NSDictionary *projectDict,
                               NSString *makeTool, NSString *nativeMakefiles)
{
  NSString *root = [[projectDict objectForKey:@"XCODE_PROJECT_PATH"] stringByDeletingLastPathComponent];
  NSString *build = [PCDeployment valueForKey:@"Build" ofDeployment:deployment project:projectDict];
  NSString *script = [projectDict objectForKey:@"XCODE_BuildScript"];
  NSString *executable = [projectDict objectForKey:@"XCODE_Executable"];
  NSString *target = [[PCDeployment productOfProject:projectDict] objectForKey:@"Target"];
  NSString *configuration = [PCDeployment valueForKey:@"Configuration" ofDeployment:deployment project:projectDict];
  NSString *arguments = Trimmed([deployment objectForKey:@"MakeArguments"]);
  NSString *makefiles = nil;
  NSString *candidates = @"";

  if ([build isEqual:@"Toolchain"])
  {
    makefiles = [[PCDeployment valueForKey:@"Toolchain" ofDeployment:deployment project:projectDict]
                 stringByExpandingTildeInPath];
  }
  else if ([build isEqual:@"Native"])
  {
    makefiles = nativeMakefiles;
  }
  /* GNUstep's environment: the toolchain's, else the one in place or
   * gnustep-config's. */
  if (makefiles)
  {
    [s appendFormat:@"GNUSTEP_MAKEFILES=%@\n", SQ(makefiles)];
  }
  else
  {
    [s appendString:@"if [ -z \"$GNUSTEP_MAKEFILES\" ]; then\n"
     @"  GNUSTEP_MAKEFILES=$(gnustep-config --variable=GNUSTEP_MAKEFILES 2>/dev/null)\n"
     @"fi\n"];
  }
  [s appendString:@"if [ ! -f \"$GNUSTEP_MAKEFILES/GNUstep.sh\" ]; then\n"
   @"  echo \"error: GNUstep.sh not found (GNUSTEP_MAKEFILES=$GNUSTEP_MAKEFILES)\" >&2\n"
   @"  exit 1\n"
   @"fi\n"
   @". \"$GNUSTEP_MAKEFILES/GNUstep.sh\"\n"
   @"set -e\n"
   @"rm -rf \"$BUILD\"\n"
   @"mkdir -p \"$BUILD\" \"$OUT\"\n"];
  [s appendFormat:@"echo \"Building %@ (%@)...\"\n", target, configuration];
  if (script)
  {
    [s appendFormat:@"/bin/bash %@ all", RootPath(script, root)];
  }
  else
  {
    [s appendFormat:@"%@", [build isEqual:@"Container"] || ![makeTool length] ? @"make" : SQ(makeTool)];
  }
  [s appendFormat:@" %@ messages=yes GNUSTEP_BUILD_DIR=\"$BUILD/obj\"%@%@\n",
   [[configuration lowercaseString] hasPrefix:@"debug"] ? @"debug=yes" : @"debug=no",
   [arguments length] ? @" " : @"", arguments];

  /* The bundle: in the build folder, else where Run finds it. */
  candidates = [NSString stringWithFormat:@"\"$BUILD/obj/\"%@", SQ([target stringByAppendingPathExtension:@"app"])];
  if ([[[executable stringByDeletingLastPathComponent] pathExtension] isEqual:@"app"])
  {
    candidates = [candidates stringByAppendingFormat:@" %@",
                  RootPath([executable stringByDeletingLastPathComponent], root)];
  }
  candidates = [candidates stringByAppendingFormat:@" \"$ROOT/\"%@", SQ([target stringByAppendingPathExtension:@"app"])];
  [s appendFormat:@"APP=''\n"
   @"for candidate in %@; do\n"
   @"  if [ -d \"$candidate\" ]; then APP=\"$candidate\"; break; fi\n"
   @"done\n"
   @"if [ -z \"$APP\" ]; then\n"
   @"  APP=$(find \"$BUILD/obj\" -maxdepth 2 -type d -name '*.app' | head -n 1)\n"
   @"fi\n"
   @"if [ -z \"$APP\" ]; then\n"
   @"  echo \"error: the build made no application bundle\" >&2\n"
   @"  exit 1\n"
   @"fi\n"
   @"APPNAME=$(basename \"$APP\")\n"
   @"EXE=\"${APPNAME%%.app}\"\n"
   @"echo \"Built $APP\"\n", candidates];
}

/* The files of a Linux package in $STAGE: the bundle in the install
 * folder, the command and the desktop entry. */
static void AppendLinuxStage(NSMutableString *s, NSDictionary *deployment, NSDictionary *projectDict)
{
  NSString *install = [PCDeployment valueForKey:@"InstallFolder" ofDeployment:deployment project:projectDict];
  NSString *categories = [PCDeployment valueForKey:@"Categories" ofDeployment:deployment project:projectDict];
  NSString *icon = Trimmed([deployment objectForKey:@"Icon"]);
  NSString *display = [[PCDeployment productOfProject:projectDict] objectForKey:@"DisplayName"];
  BOOL     launcher = [[PCDeployment valueForKey:@"Launcher" ofDeployment:deployment project:projectDict] boolValue];

  if (![install hasPrefix:@"/"]) install = [@"/" stringByAppendingString:install];
  [s appendFormat:@"DEST=%@\n", SQ(install)];
  [s appendString:@"STAGE=\"$BUILD/package\"\n"
   @"mkdir -p \"$STAGE$DEST\"\n"
   @"cp -R \"$APP\" \"$STAGE$DEST/\"\n"];
  if (launcher)
  {
    [s appendString:@"mkdir -p \"$STAGE/usr/bin\"\n"
     @"printf '#!/bin/sh\\nexec \"%s\" \"$@\"\\n' \"$DEST/$APPNAME/$EXE\" > \"$STAGE/usr/bin/$PKG\"\n"
     @"chmod 755 \"$STAGE/usr/bin/$PKG\"\n"
     @"COMMAND=\"$PKG\"\n"];
  }
  else
  {
    [s appendString:@"COMMAND=\"$DEST/$APPNAME/$EXE\"\n"];
  }
  if ([categories length])
  {
    if (![categories hasSuffix:@";"]) categories = [categories stringByAppendingString:@";"];
    [s appendString:@"mkdir -p \"$STAGE/usr/share/applications\"\n"];
    [s appendFormat:@"{\n"
     @"  echo '[Desktop Entry]'\n"
     @"  echo 'Type=Application'\n"
     @"  echo %@\n"
     @"  echo \"Exec=$COMMAND %%F\"\n"
     @"  echo %@\n"
     @"  echo 'Terminal=false'\n",
     SQ([@"Name=" stringByAppendingString:display]), SQ([@"Categories=" stringByAppendingString:categories])];
    if ([icon length]) [s appendString:@"  echo \"Icon=$PKG\"\n"];
    [s appendString:@"} > \"$STAGE/usr/share/applications/$PKG.desktop\"\n"];
  }
  if ([icon length])
  {
    NSString *root = [[projectDict objectForKey:@"XCODE_PROJECT_PATH"] stringByDeletingLastPathComponent];
    NSString *path = [icon isAbsolutePath] ? icon : [root stringByAppendingPathComponent:icon];

    [s appendFormat:@"mkdir -p \"$STAGE/usr/share/pixmaps\"\n"
     @"cp %@ \"$STAGE/usr/share/pixmaps/$PKG.%@\"\n", RootPath(path, root), [icon pathExtension]];
  }
}

static NSString *DebianScript(NSDictionary *deployment, NSDictionary *projectDict)
{
  NSMutableString *s = [NSMutableString string];
  NSString        *(^value)(NSString *) = ^NSString *(NSString *key) {
    return [PCDeployment valueForKey:key ofDeployment:deployment project:projectDict];
  };
  NSString        *homepage = value(@"Homepage");

  [s appendFormat:@"PKG=%@\nVERSION=%@\nARCH=%@\n", SQ(value(@"PackageName")), SQ(value(@"Version")),
   SQ(value(@"Architecture"))];
  AppendLinuxStage(s, deployment, projectDict);
  [s appendFormat:@"DEPENDS=%@\n", SQ(value(@"Depends"))];
  if ([value(@"AutomaticDependencies") boolValue])
  {
    /* The packages of the linked libraries and of GNUstep's back end. */
    [s appendString:@"if command -v dpkg-query >/dev/null 2>&1 && command -v ldd >/dev/null 2>&1; then\n"
     @"  FOUND=$( {\n"
     @"    for binary in \"$APP/$EXE\" $(find \"$APP\" -type f -name '*.so*'); do\n"
     @"      ldd \"$binary\" 2>/dev/null | awk '/=>/ { print $3 }'\n"
     @"    done | sort -u | while read -r library; do\n"
     @"      [ -n \"$library\" ] || continue\n"
     @"      dpkg -S \"$library\" 2>/dev/null || dpkg -S \"$(readlink -f \"$library\")\" 2>/dev/null\n"
     @"    done\n"
     @"    dpkg -S '*/Bundles/libgnustep-back*' 2>/dev/null | head -n 1\n"
     @"  } | cut -d: -f1 | sort -u | paste -sd, - | sed 's/,/, /g')\n"
     @"  if [ -n \"$FOUND\" ]; then DEPENDS=\"${DEPENDS:+$DEPENDS, }$FOUND\"; fi\n"
     @"fi\n"];
  }
  [s appendString:@"mkdir -p \"$STAGE/DEBIAN\"\n"
   @"SIZE=$(du -sk \"$STAGE\" | cut -f1)\n"
   @"{\n"
   @"  echo \"Package: $PKG\"\n"
   @"  echo \"Version: $VERSION\"\n"
   @"  echo \"Architecture: $ARCH\"\n"];
  [s appendFormat:@"  echo %@\n", SQ([@"Maintainer: " stringByAppendingString:value(@"Maintainer")])];
  [s appendFormat:@"  echo %@\n", SQ([@"Section: " stringByAppendingString:value(@"Section")])];
  [s appendString:@"  echo 'Priority: optional'\n"
   @"  echo \"Installed-Size: $SIZE\"\n"
   @"  if [ -n \"$DEPENDS\" ]; then echo \"Depends: $DEPENDS\"; fi\n"];
  if ([homepage length]) [s appendFormat:@"  echo %@\n", SQ([@"Homepage: " stringByAppendingString:homepage])];
  [s appendFormat:@"  echo %@\n", SQ([@"Description: " stringByAppendingString:value(@"Summary")])];
  [s appendString:@"} > \"$STAGE/DEBIAN/control\"\n"];
  [s appendFormat:@"FILE=%@\n", SQ([PCDeployment fileNameOfDeployment:deployment project:projectDict])];
  [s appendString:@"echo \"Packaging $FILE...\"\n"
   @"if dpkg-deb --help 2>/dev/null | grep -q root-owner-group; then\n"
   @"  dpkg-deb --root-owner-group --build \"$STAGE\" \"$OUT/$FILE\"\n"
   @"else\n"
   @"  dpkg-deb --build \"$STAGE\" \"$OUT/$FILE\"\n"
   @"fi\n"];
  return s;
}

static NSString *RPMScript(NSDictionary *deployment, NSDictionary *projectDict)
{
  NSMutableString *s = [NSMutableString string];
  NSString        *(^value)(NSString *) = ^NSString *(NSString *key) {
    return [PCDeployment valueForKey:key ofDeployment:deployment project:projectDict];
  };
  NSString        *homepage = value(@"Homepage");
  NSString        *requires = value(@"Depends");
  BOOL            launcher = [value(@"Launcher") boolValue];

  [s appendFormat:@"PKG=%@\nVERSION=%@\nARCH=%@\n", SQ(value(@"PackageName")),
   SQ([value(@"Version") stringByReplacingOccurrencesOfString:@"-" withString:@"_"]), SQ(value(@"Architecture"))];
  AppendLinuxStage(s, deployment, projectDict);
  [s appendString:@"TOP=\"$BUILD/rpm\"\n"
   @"mkdir -p \"$TOP/SPECS\" \"$TOP/RPMS\" \"$TOP/BUILD\"\n"
   @"SPEC=\"$TOP/SPECS/$PKG.spec\"\n"
   @"{\n"
   @"  echo \"Name: $PKG\"\n"
   @"  echo \"Version: $VERSION\"\n"];
  [s appendFormat:@"  echo %@\n", SQ([@"Release: " stringByAppendingString:value(@"Release")])];
  [s appendFormat:@"  echo %@\n", SQ([@"Summary: " stringByAppendingString:value(@"Summary")])];
  [s appendFormat:@"  echo %@\n", SQ([@"License: " stringByAppendingString:value(@"License")])];
  if ([homepage length]) [s appendFormat:@"  echo %@\n", SQ([@"URL: " stringByAppendingString:homepage])];
  if ([requires length]) [s appendFormat:@"  echo %@\n", SQ([@"Requires: " stringByAppendingString:requires])];
  [s appendFormat:@"  echo 'AutoReqProv: %@'\n", [value(@"AutomaticDependencies") boolValue] ? @"yes" : @"no"];
  [s appendFormat:@"  echo; echo '%%description'; echo %@; echo\n", SQ(value(@"Summary"))];
  [s appendString:@"  echo '%install'\n"
   @"  echo 'mkdir -p %{buildroot}'\n"
   @"  echo \"cp -R '$STAGE'/. %{buildroot}/\"\n"
   @"  echo; echo '%files'\n"
   @"  echo \"\\\"$DEST/$APPNAME\\\"\"\n"];
  if (launcher) [s appendString:@"  echo \"/usr/bin/$PKG\"\n"];
  [s appendString:@"  if [ -f \"$STAGE/usr/share/applications/$PKG.desktop\" ]; then\n"
   @"    echo \"/usr/share/applications/$PKG.desktop\"\n"
   @"  fi\n"
   @"  if [ -d \"$STAGE/usr/share/pixmaps\" ]; then echo '/usr/share/pixmaps/*'; fi\n"
   @"} > \"$SPEC\"\n"];
  [s appendFormat:@"FILE=%@\n", SQ([PCDeployment fileNameOfDeployment:deployment project:projectDict])];
  /* No post-install processing: a cross build's binaries are not for this
   * computer's strip. */
  [s appendString:@"echo \"Packaging $FILE...\"\n"
   @"rpmbuild -bb --target \"$ARCH\" --define \"_topdir $TOP\" --define '__os_install_post %{nil}' "
   @"--define '_build_id_links none' \"$SPEC\"\n"
   @"MADE=$(find \"$TOP/RPMS\" -type f -name '*.rpm' | head -n 1)\n"
   @"if [ -z \"$MADE\" ]; then echo \"error: rpmbuild made no package\" >&2; exit 1; fi\n"
   @"cp \"$MADE\" \"$OUT/$FILE\"\n"];
  return s;
}

static NSString *TarScript(NSDictionary *deployment, NSDictionary *projectDict)
{
  return [NSString stringWithFormat:@"FILE=%@\n"
          @"echo \"Packaging $FILE...\"\n"
          @"tar -czf \"$OUT/$FILE\" -C \"$(dirname \"$APP\")\" \"$APPNAME\"\n",
          SQ([PCDeployment fileNameOfDeployment:deployment project:projectDict])];
}

static NSString *WindowsScript(NSDictionary *deployment, NSDictionary *projectDict)
{
  NSMutableString *s = [NSMutableString string];
  NSString        *folders = [PCDeployment valueForKey:@"LibraryFolders" ofDeployment:deployment project:projectDict];
  NSString        *architecture = [PCDeployment valueForKey:@"Architecture" ofDeployment:deployment project:projectDict];

  [s appendString:@"PACKAGE=\"$BUILD/package\"\n"
   @"mkdir -p \"$PACKAGE/$EXE\"\n"
   @"cp -R \"$APP\" \"$PACKAGE/$EXE/\"\n"
   @"DLLDIR=\"$PACKAGE/$EXE/$APPNAME\"\n"];
  if ([[PCDeployment valueForKey:@"IncludeLibraries" ofDeployment:deployment project:projectDict] boolValue])
  {
    /* The DLLs the executable needs, and theirs, from GNUstep's folders;
     * Windows' own are not found there and stay out. */
    [s appendFormat:@"OBJDUMP=''\n"
     @"for tool in %@-w64-mingw32-objdump objdump llvm-objdump; do\n"
     @"  if command -v \"$tool\" >/dev/null 2>&1; then OBJDUMP=\"$tool\"; break; fi\n"
     @"done\n"
     @"DIRS=\"$GNUSTEP_SYSTEM_TOOLS:$GNUSTEP_LOCAL_TOOLS:$GNUSTEP_SYSTEM_LIBRARIES:$GNUSTEP_LOCAL_LIBRARIES:\"%@\":$PATH\"\n",
     architecture, SQ(folders)];
    [s appendString:@"if [ -z \"$OBJDUMP\" ]; then\n"
     @"  echo \"warning: no objdump, so the DLLs are not included\"\n"
     @"else\n"
     @"  find \"$DLLDIR\" -maxdepth 1 -iname '*.exe' > \"$BUILD/todo\"\n"
     @"  while [ -s \"$BUILD/todo\" ]; do\n"
     @"    binary=$(head -n 1 \"$BUILD/todo\")\n"
     @"    sed '1d' \"$BUILD/todo\" > \"$BUILD/todo.next\"; mv \"$BUILD/todo.next\" \"$BUILD/todo\"\n"
     @"    for dll in $(\"$OBJDUMP\" -p \"$binary\" 2>/dev/null | sed -n 's/^[[:space:]]*DLL Name: //p' | tr -d '\\r'); do\n"
     @"      [ -f \"$DLLDIR/$dll\" ] && continue\n"
     @"      found=''\n"
     @"      OLDIFS=\"$IFS\"; IFS=:\n"
     @"      for dir in $DIRS; do\n"
     @"        if [ -n \"$dir\" ] && [ -f \"$dir/$dll\" ]; then found=\"$dir/$dll\"; break; fi\n"
     @"      done\n"
     @"      IFS=\"$OLDIFS\"\n"
     @"      [ -n \"$found\" ] || continue\n"
     @"      cp \"$found\" \"$DLLDIR/\"\n"
     @"      echo \"Included $dll\"\n"
     @"      echo \"$DLLDIR/$dll\" >> \"$BUILD/todo\"\n"
     @"    done\n"
     @"  done\n"
     @"fi\n"];
  }
  [s appendFormat:@"FILE=%@\n", SQ([PCDeployment fileNameOfDeployment:deployment project:projectDict])];
  [s appendString:@"echo \"Packaging $FILE...\"\n"
   @"cd \"$PACKAGE\"\n"
   @"if command -v zip >/dev/null 2>&1; then\n"
   @"  zip -qr \"$OUT/$FILE\" \"$EXE\"\n"
   @"elif command -v ditto >/dev/null 2>&1; then\n"
   @"  ditto -c -k --keepParent \"$EXE\" \"$OUT/$FILE\"\n"
   @"else\n"
   @"  bsdtar -a -cf \"$OUT/$FILE\" \"$EXE\"\n"
   @"fi\n"
   @"cd \"$ROOT\"\n"];
  return s;
}

static NSString *MacScript(NSDictionary *deployment, NSDictionary *projectDict)
{
  NSMutableString *s = [NSMutableString string];
  NSString        *(^value)(NSString *) = ^NSString *(NSString *key) {
    return [PCDeployment valueForKey:key ofDeployment:deployment project:projectDict];
  };
  NSString        *project = [projectDict objectForKey:@"XCODE_PROJECT_PATH"];
  NSString        *root = [project stringByDeletingLastPathComponent];
  NSString        *architecture = value(@"Architecture");
  NSString        *identity = value(@"SigningIdentity");
  NSString        *notary = value(@"NotaryProfile");
  NSString        *product = [[PCDeployment productOfProject:projectDict] objectForKey:@"Product"];
  BOOL            dmg = [value(@"Format") isEqual:@"dmg"];

  [s appendString:@"set -e\n"
   @"rm -rf \"$BUILD\"\n"
   @"mkdir -p \"$BUILD\" \"$OUT\"\n"];
  [s appendFormat:@"ARCHIVE=\"$BUILD/\"%@\n", SQ([product stringByAppendingPathExtension:@"xcarchive"])];
  [s appendFormat:@"echo \"Archiving the scheme %@ (%@)...\"\n", value(@"Scheme"), value(@"Configuration")];
  [s appendFormat:@"xcodebuild -project %@ -scheme %@ -configuration %@ -destination 'generic/platform=macOS' "
   @"-archivePath \"$ARCHIVE\"", RootPath(project, root), SQ(value(@"Scheme")), SQ(value(@"Configuration"))];
  if ([architecture isEqual:@"universal"]) [s appendString:@" ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO"];
  else if ([architecture length]) [s appendFormat:@" ARCHS=%@ ONLY_ACTIVE_ARCH=NO", SQ(architecture)];
  [s appendString:@" archive\n"
   @"APP=$(find \"$ARCHIVE/Products\" -type d -name '*.app' -prune | head -n 1)\n"
   @"if [ -z \"$APP\" ]; then echo \"error: the archive holds no application\" >&2; exit 1; fi\n"
   @"APPNAME=$(basename \"$APP\")\n"];
  if ([identity length])
  {
    [s appendFormat:@"IDENTITY=%@\n"
     @"echo \"Signing $APPNAME...\"\n"
     @"codesign --force --deep --options runtime --timestamp --sign \"$IDENTITY\" \"$APP\"\n", SQ(identity)];
  }
  [s appendFormat:@"FILE=%@\n", SQ([PCDeployment fileNameOfDeployment:deployment project:projectDict])];
  if ([notary length]) [s appendFormat:@"NOTARY=%@\n", SQ(notary)];
  if (dmg)
  {
    [s appendFormat:@"echo \"Making the disk image $FILE...\"\n"
     @"STAGE=\"$BUILD/dmg\"\n"
     @"mkdir -p \"$STAGE\"\n"
     @"cp -R \"$APP\" \"$STAGE/\"\n"
     @"ln -s /Applications \"$STAGE/Applications\"\n"
     @"hdiutil create -volname %@ -srcfolder \"$STAGE\" -ov -format UDZO \"$OUT/$FILE\"\n",
     SQ([[PCDeployment productOfProject:projectDict] objectForKey:@"DisplayName"])];
    if ([identity length]) [s appendString:@"codesign --force --timestamp --sign \"$IDENTITY\" \"$OUT/$FILE\"\n"];
    if ([notary length])
    {
      [s appendString:@"echo \"Notarizing $FILE...\"\n"
       @"xcrun notarytool submit \"$OUT/$FILE\" --keychain-profile \"$NOTARY\" --wait\n"
       @"xcrun stapler staple \"$OUT/$FILE\"\n"];
    }
  }
  else
  {
    [s appendString:@"echo \"Making the zip archive $FILE...\"\n"
     @"ditto -c -k --keepParent \"$APP\" \"$OUT/$FILE\"\n"];
    if ([notary length])
    {
      /* The ticket is stapled to the application, which is zipped again. */
      [s appendString:@"echo \"Notarizing $APPNAME...\"\n"
       @"xcrun notarytool submit \"$OUT/$FILE\" --keychain-profile \"$NOTARY\" --wait\n"
       @"xcrun stapler staple \"$APP\"\n"
       @"rm -f \"$OUT/$FILE\"\n"
       @"ditto -c -k --keepParent \"$APP\" \"$OUT/$FILE\"\n"];
    }
  }
  return s;
}

/* A file name for a deployment's script. */
static NSString *Identifier(NSDictionary *deployment, NSUInteger index)
{
  NSMutableString *name = [NSMutableString stringWithFormat:@"%lu-", (unsigned long)index + 1];
  NSString        *title = Trimmed([deployment objectForKey:@"Name"]);
  NSCharacterSet  *allowed = [NSCharacterSet alphanumericCharacterSet];
  NSUInteger      i;

  if (![title length]) title = [deployment objectForKey:@"Kind"];
  for (i = 0; i < [title length] && [name length] < 40; i++)
  {
    unichar c = [title characterAtIndex:i];

    if (c < 128 && [allowed characterIsMember:c]) [name appendFormat:@"%C", c];
    else if (![name hasSuffix:@"-"]) [name appendString:@"-"];
  }
  while ([name hasSuffix:@"-"]) [name deleteCharactersInRange:NSMakeRange([name length] - 1, 1)];
  return name;
}

+ (NSDictionary *)archiveScriptsForProject:(NSDictionary *)projectDict
                               deployments:(NSArray *)deployments
                                    folder:(NSString *)folder
                                  makeTool:(NSString *)makeTool
{
  NSString            *root = [[projectDict objectForKey:@"XCODE_PROJECT_PATH"] stringByDeletingLastPathComponent];
  NSString            *prefix = [root stringByAppendingString:@"/"];
  NSString            *relativeFolder = [folder hasPrefix:prefix] ? [folder substringFromIndex:[prefix length]] : nil;
  NSString            *nativeMakefiles = [self _nativeMakefiles];
  NSString            *containerTool = [self _containerTool];
  NSMutableDictionary *scripts = [NSMutableDictionary dictionary];
  NSMutableString     *main = [NSMutableString string];
  NSUInteger          index = 0;

  [main appendString:@"#!/bin/sh\n# Archive: written by ProjectCenter.\n"
   @"PATH=\"$PATH:/usr/local/bin:/opt/homebrew/bin:/opt/local/bin:"
   @"/Applications/Docker.app/Contents/Resources/bin\"\n"
   @"export PATH\n"];
  [main appendFormat:@"ROOT=%@\nOUT=%@\n", SQ(root), SQ(folder)];
  [main appendString:@"mkdir -p \"$OUT\"\n"
   @"FAILED=''\n"
   @"DONE=0\n"];

  for (NSDictionary *deployment in deployments)
  {
    NSString        *kind = [deployment objectForKey:@"Kind"];
    NSString        *name = [self valueForKey:@"Name" ofDeployment:deployment project:projectDict];
    NSString        *identifier = Identifier(deployment, index++);
    NSString        *file = [identifier stringByAppendingPathExtension:@"sh"];
    NSString        *build = [self valueForKey:@"Build" ofDeployment:deployment project:projectDict];
    NSMutableString *s = [NSMutableString string];
    NSString        *command;

    if ([self kindNamed:kind] == nil) continue;
    AppendPrologue(s, name, identifier);
    if ([kind isEqual:@"macOS"])
    {
      [s appendString:MacScript(deployment, projectDict)];
    }
    else
    {
      AppendGNUstepBuild(s, deployment, projectDict, makeTool, nativeMakefiles);
      if ([kind isEqual:@"Debian"]) [s appendString:DebianScript(deployment, projectDict)];
      else if ([kind isEqual:@"RPM"]) [s appendString:RPMScript(deployment, projectDict)];
      else if ([kind isEqual:@"Windows"]) [s appendString:WindowsScript(deployment, projectDict)];
      else [s appendString:TarScript(deployment, projectDict)];
    }
    [s appendString:@"echo \"Made $OUT/$FILE\"\n"];
    [scripts setObject:s forKey:file];

    if ([build isEqual:@"Container"] && IsGNUstepKind(kind))
    {
      NSString *setup = Trimmed([self valueForKey:@"Setup" ofDeployment:deployment project:projectDict]);
      NSString *inner = [NSString stringWithFormat:@"%@/bin/sh /src/build/Deployment/%@ /src %@",
                         [setup length] ? [setup stringByAppendingString:@" && "] : @"", file,
                         SQ(relativeFolder ? [@"/src/" stringByAppendingString:relativeFolder] : @"/src/build/Archives")];

      command = [NSString stringWithFormat:@"%@ run --rm --platform %@ -e HOST_UID=\"$(id -u)\" "
                 @"-e HOST_GID=\"$(id -g)\" -v \"$ROOT:/src\" -w /src %@ /bin/sh -c %@",
                 SQ(containerTool ? [containerTool lastPathComponent] : @"docker"),
                 SQ(ContainerPlatform([self valueForKey:@"Architecture" ofDeployment:deployment
                                                project:projectDict])),
                 SQ([self valueForKey:@"Image" ofDeployment:deployment project:projectDict]), SQ(inner)];
    }
    else
    {
      command = [NSString stringWithFormat:@"/bin/sh \"$ROOT/build/Deployment/\"%@ \"$ROOT\" \"$OUT\"", SQ(file)];
    }
    [main appendFormat:@"\necho %@\n", SQ([NSString stringWithFormat:@"=== %@ ===", name])];
    [main appendFormat:@"if %@; then\n"
     @"  DONE=$((DONE + 1))\n"
     @"else\n"
     @"  echo %@ >&2\n"
     @"  FAILED=\"$FAILED\"%@\n"
     @"fi\n", command, SQ([NSString stringWithFormat:@"error: %@ failed", name]),
     SQ([NSString stringWithFormat:@"\n  %@", name])];
  }
  [main appendString:@"\necho\n"
   @"echo \"Archived $DONE platform(s) to $OUT\"\n"
   @"if [ -n \"$FAILED\" ]; then\n"
   @"  printf 'Failed:%b\\n' \"$FAILED\"\n"
   @"  exit 1\n"
   @"fi\n"];
  [scripts setObject:main forKey:@"archive.sh"];
  return scripts;
}

+ (NSString *)writeArchiveScriptsForProject:(NSDictionary *)projectDict
                                deployments:(NSArray *)deployments
                                     folder:(NSString *)folder
                                   makeTool:(NSString *)makeTool
                                      error:(NSString **)error
{
  NSString      *root = [[projectDict objectForKey:@"XCODE_PROJECT_PATH"] stringByDeletingLastPathComponent];
  NSString      *directory = [root stringByAppendingPathComponent:@"build/Deployment"];
  NSDictionary  *scripts = [self archiveScriptsForProject:projectDict deployments:deployments
                                                   folder:folder makeTool:makeTool];
  NSFileManager *fm = [NSFileManager defaultManager];

  if (error) *error = nil;
  if (root == nil)
  {
    if (error) *error = @"Archive needs an Xcode project.";
    return nil;
  }
  if (![fm createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL])
  {
    if (error) *error = [NSString stringWithFormat:@"Cannot make %@.", directory];
    return nil;
  }
  for (NSString *name in scripts)
  {
    NSString *path = [directory stringByAppendingPathComponent:name];

    if (![[scripts objectForKey:name] writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL])
    {
      if (error) *error = [NSString stringWithFormat:@"Cannot write %@.", path];
      return nil;
    }
    [fm setAttributes:[NSDictionary dictionaryWithObject:[NSNumber numberWithShort:0755]
                                                  forKey:NSFilePosixPermissions]
         ofItemAtPath:path error:NULL];
  }
  return [directory stringByAppendingPathComponent:@"archive.sh"];
}

@end
