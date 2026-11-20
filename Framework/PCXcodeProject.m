#import "PCXcodeProject.h"

#ifdef __APPLE__
#include <sys/sysctl.h>
#endif

static NSData *RunTool(NSString *tool, NSArray *arguments);

static NSString * const PCXcodeProjectMarker = @"XCODE_PROJECT_PATH";

static BOOL SupportsGNUstep(NSDictionary *target, NSDictionary *objects)
{
  NSDictionary *list = [objects objectForKey:[target objectForKey:@"buildConfigurationList"]];
  for (NSString *config in [list objectForKey:@"buildConfigurations"])
  {
    NSDictionary *settings = [[objects objectForKey:config] objectForKey:@"buildSettings"];
    NSString *sdk = [[settings objectForKey:@"SDKROOT"] lowercaseString];
    if ([sdk isEqual:@"linux"] || [sdk isEqual:@"gnustep"]) return YES;
    id platforms = [settings objectForKey:@"SUPPORTED_PLATFORMS"];
    if ([platforms isKindOfClass:[NSString class]]) platforms = [platforms componentsSeparatedByString:@" "];
    if ([platforms containsObject:@"gnustep"]) return YES;
  }
  return NO;
}

static NSMutableDictionary *Group(NSString *name)
{
  return [NSMutableDictionary dictionaryWithObjectsAndKeys:
          (name ? name : @""), @"Name", [NSMutableArray array], @"Children", nil];
}

static NSDictionary *Leaf(NSString *name, NSString *path, NSString *root)
{
  NSString *prefix = [root stringByAppendingString:@"/"];
  /* SDK and build-product references are not editable project sources. */
  if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return nil;
  if ([path hasPrefix:prefix]) path = [path substringFromIndex:[prefix length]];
  return [NSDictionary dictionaryWithObjectsAndKeys:name, @"Name", path, @"File", nil];
}

static NSComparisonResult CompareNodes(id a, id b, void *context)
{
  return [[a objectForKey:@"Name"] localizedCaseInsensitiveCompare:[b objectForKey:@"Name"]];
}

static void SortGroup(NSMutableDictionary *group)
{
  NSMutableArray *children = [group objectForKey:@"Children"];
  [children sortUsingFunction:CompareNodes context:NULL];
  for (NSMutableDictionary *child in children)
    if ([child objectForKey:@"Children"]) SortGroup(child);
}

/* Returns the navigator node for a reference: a group {Name, Children} or a
 * file {Name, File}, or nil when nothing below it exists locally. The flat
 * identifier-to-path map still feeds ProjectCenter's file categories. */
static NSDictionary *ReadGroup(NSString *identifier, NSString *parent, NSString *root,
                               NSDictionary *objects, NSMutableDictionary *paths,
                               NSMutableSet *visited)
{
  if (![identifier isKindOfClass:[NSString class]] || [visited containsObject:identifier]) return nil;
  [visited addObject:identifier];
  NSDictionary *object = [objects objectForKey:identifier];
  if (![object isKindOfClass:[NSDictionary class]]) return nil;
  NSString *tree = [object objectForKey:@"sourceTree"];
  NSString *component = [object objectForKey:@"path"];
  if (tree && ![@[@"<group>", @"SOURCE_ROOT", @"<absolute>"] containsObject:tree]) return nil;
  if (component && ![component isKindOfClass:[NSString class]]) return nil;
  if (component && ([component rangeOfString:@"$("].location != NSNotFound ||
                    [component rangeOfString:@"${"].location != NSNotFound)) return nil;
  NSString *base = [tree isEqual:@"SOURCE_ROOT"] ? root : parent;
  NSString *path = component ? ([component isAbsolutePath] ? component : [base stringByAppendingPathComponent:component]) : base;
  path = [path stringByStandardizingPath];
  NSString *name = [object objectForKey:@"name"];
  if (![name isKindOfClass:[NSString class]] || ![name length]) name = [component lastPathComponent];
  /* Xcode 16+ can store folders rather than an explicit reference per file. */
  if ([[object objectForKey:@"isa"] isEqual:@"PBXFileSystemSynchronizedRootGroup"])
  {
    NSMutableDictionary *group = Group(name);
    NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtPath:path];
    NSString *entry;
    while ((entry = [enumerator nextObject]))
    {
      NSString *fullPath = [path stringByAppendingPathComponent:entry];
      NSString *type = [[enumerator fileAttributes] objectForKey:NSFileType];
      NSString *extension = [[entry pathExtension] lowercaseString];
      BOOL package = [@[@"xcassets", @"xib", @"nib", @"gorm", @"storyboard", @"bundle", @"framework", @"xcodeproj"] containsObject:extension];
      if ([[entry lastPathComponent] hasPrefix:@"."] || [type isEqual:NSFileTypeSymbolicLink])
      { [enumerator skipDescendents]; continue; }
      if (package) [enumerator skipDescendents];
      if ([type isEqual:NSFileTypeDirectory] && !package) continue;
      [paths setObject:fullPath forKey:[identifier stringByAppendingPathComponent:entry]];
      NSArray *parts = [entry pathComponents];
      NSMutableDictionary *container = group;
      for (NSUInteger i = 0; i + 1 < [parts count]; i++)
      {
        NSMutableDictionary *folder = nil;
        for (NSMutableDictionary *child in [container objectForKey:@"Children"])
          if ([child objectForKey:@"Children"] && [[child objectForKey:@"Name"] isEqual:[parts objectAtIndex:i]])
          { folder = child; break; }
        if (!folder)
        {
          folder = Group([parts objectAtIndex:i]);
          [[container objectForKey:@"Children"] addObject:folder];
        }
        container = folder;
      }
      NSDictionary *leaf = Leaf([parts lastObject], fullPath, root);
      if (leaf) [[container objectForKey:@"Children"] addObject:leaf];
    }
    SortGroup(group);
    return [[group objectForKey:@"Children"] count] ? group : nil;
  }
  if ([[object objectForKey:@"isa"] isEqual:@"PBXFileReference"])
  {
    [paths setObject:path forKey:identifier];
    return Leaf((name ? name : [path lastPathComponent]), path, root);
  }
  NSMutableDictionary *group = Group(name);
  id children = [object objectForKey:@"children"];
  if ([children isKindOfClass:[NSArray class]])
    for (NSString *child in children)
    {
      NSDictionary *node = ReadGroup(child, path, root, objects, paths, visited);
      if (node) [[group objectForKey:@"Children"] addObject:node];
    }
  return [[group objectForKey:@"Children"] count] ? group : nil;
}

static NSString *ObjectName(NSDictionary *objects, NSString *identifier)
{
  NSDictionary *object = [objects objectForKey:identifier];
  NSString *name;

  if (![object isKindOfClass:[NSDictionary class]]) return nil;
  name = [object objectForKey:@"name"];
  if (![name isKindOfClass:[NSString class]] || ![name length])
    name = [[object objectForKey:@"path"] lastPathComponent];
  if (![name isKindOfClass:[NSString class]] || ![name length])
    name = [object objectForKey:@"productName"];
  return [name isKindOfClass:[NSString class]] ? name : nil;
}

static NSArray *Configurations(NSDictionary *objects, NSString *listIdentifier)
{
  NSMutableArray *result = [NSMutableArray array];
  NSDictionary *list = [objects objectForKey:listIdentifier];

  for (NSString *identifier in [list objectForKey:@"buildConfigurations"])
  {
    NSDictionary *configuration = [objects objectForKey:identifier];
    NSDictionary *settings = [configuration objectForKey:@"buildSettings"];
    NSString *base = ObjectName(objects, [configuration objectForKey:@"baseConfigurationReference"]);
    NSMutableDictionary *entry = [NSMutableDictionary dictionary];

    if (![configuration isKindOfClass:[NSDictionary class]]) continue;
    [entry setObject:([configuration objectForKey:@"name"] ? [configuration objectForKey:@"name"] : @"") forKey:@"Name"];
    [entry setObject:identifier forKey:@"Identifier"];
    [entry setObject:([settings isKindOfClass:[NSDictionary class]] ? settings : [NSDictionary dictionary]) forKey:@"Settings"];
    if (base) [entry setObject:base forKey:@"Base"];
    [result addObject:entry];
  }
  return result;
}

static NSDictionary *Phase(NSDictionary *objects, NSString *identifier, NSDictionary *paths)
{
  static NSDictionary *names = nil;
  NSDictionary *phase = [objects objectForKey:identifier];
  NSString *isa = [phase objectForKey:@"isa"];
  NSMutableArray *files = [NSMutableArray array];
  NSMutableArray *filePaths = [NSMutableArray array];
  NSMutableDictionary *entry = [NSMutableDictionary dictionary];
  NSString *name = [phase objectForKey:@"name"];

  if (names == nil)
    names = [[NSDictionary alloc] initWithObjectsAndKeys:
             @"Compile Sources", @"PBXSourcesBuildPhase",
             @"Link Binary With Libraries", @"PBXFrameworksBuildPhase",
             @"Copy Bundle Resources", @"PBXResourcesBuildPhase",
             @"Headers", @"PBXHeadersBuildPhase",
             @"Copy Files", @"PBXCopyFilesBuildPhase",
             @"Run Script", @"PBXShellScriptBuildPhase", nil];
  if (![phase isKindOfClass:[NSDictionary class]]) return nil;
  for (NSString *buildFile in [phase objectForKey:@"files"])
  {
    NSDictionary *file = [objects objectForKey:buildFile];
    NSString *fileName = ObjectName(objects, [file objectForKey:@"fileRef"]);
    if (!fileName) fileName = ObjectName(objects, [file objectForKey:@"productRef"]);
    if (fileName) [files addObject:fileName];
    if ([paths objectForKey:[file objectForKey:@"fileRef"]])
      [filePaths addObject:[paths objectForKey:[file objectForKey:@"fileRef"]]];
  }
  if (![name isKindOfClass:[NSString class]] || ![name length])
    name = [names objectForKey:isa] ? [names objectForKey:isa] : isa;
  [entry setObject:name forKey:@"Name"];
  [entry setObject:([names objectForKey:isa] ? [names objectForKey:isa] : (isa ? isa : @"")) forKey:@"Kind"];
  [entry setObject:files forKey:@"Files"];
  [entry setObject:filePaths forKey:@"Paths"];
  if ([[phase objectForKey:@"shellScript"] isKindOfClass:[NSString class]])
    [entry setObject:[phase objectForKey:@"shellScript"] forKey:@"Script"];
  return entry;
}

@implementation PCXcodeProject
/* The platform of a target as project.pbxproj has it (see
 * +platformOfTarget:). */
static NSString *PlatformOfRawTarget(NSDictionary *target, NSDictionary *objects)
{
  if (SupportsGNUstep(target, objects)) return @"Linux";
  for (NSString *identifier in [[objects objectForKey:[target objectForKey:@"buildConfigurationList"]]
                                objectForKey:@"buildConfigurations"])
  {
    id sdk = [[[objects objectForKey:identifier] objectForKey:@"buildSettings"] objectForKey:@"SDKROOT"];

    if (![sdk isKindOfClass:[NSString class]]) continue;
    if ([[sdk lowercaseString] isEqual:@"linux"]) return @"Linux";
    if ([[sdk lowercaseString] isEqual:@"windows"]) return @"Windows";
  }
  return @"macOS";
}

+ (NSDictionary *)projectAtPath:(NSString *)path error:(NSString **)error
{
  if (error) *error = nil;
  @try
  {
    path = [path stringByExpandingTildeInPath];
    if (![path isAbsolutePath]) path = [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:path];
    path = [path stringByStandardizingPath];
    if ([[path lastPathComponent] isEqual:@"project.pbxproj"])
      path = [path stringByDeletingLastPathComponent];
    NSString *root = [path stringByDeletingLastPathComponent];
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:[path stringByAppendingPathComponent:@"project.pbxproj"]];
    NSDictionary *objects = [plist objectForKey:@"objects"];
    NSDictionary *project = [objects objectForKey:[plist objectForKey:@"rootObject"]];
    if (![objects isKindOfClass:[NSDictionary class]] || ![[project objectForKey:@"isa"] isEqual:@"PBXProject"])
      [NSException raise:@"XcodeImport" format:@"Not a readable Xcode project: %@", path];
    NSString *settingsPath = [root stringByAppendingPathComponent:@"GNUstep/ProjectCenter.plist"];
    NSDictionary *settings = [NSDictionary dictionary];
    if ([[NSFileManager defaultManager] fileExistsAtPath:settingsPath])
    {
      settings = [NSDictionary dictionaryWithContentsOfFile:settingsPath];
      if (!settings) [NSException raise:@"XcodeImport" format:@"Invalid %@", settingsPath];
    }
    for (NSString *key in @[@"TargetName", @"BuildScript", @"Executable", @"Theme"])
      if ([settings objectForKey:key] && ![[settings objectForKey:key] isKindOfClass:[NSString class]])
        [NSException raise:@"XcodeImport" format:@"%@ must be a string in %@", key, settingsPath];
    NSMutableArray *targets = [NSMutableArray array];
    for (NSString *identifier in [project objectForKey:@"targets"])
    {
      NSDictionary *target = [objects objectForKey:identifier];
      if ([[target objectForKey:@"isa"] isEqual:@"PBXNativeTarget"] &&
          [[target objectForKey:@"productType"] isEqual:@"com.apple.product-type.application"] &&
          (![settings objectForKey:@"TargetName"] || [[target objectForKey:@"name"] isEqual:[settings objectForKey:@"TargetName"]]))
        [targets addObject:target];
    }
    if ([targets count] > 1)
    {
      /* An application with a Mac and a Linux target: the one for this
       * computer. */
#ifdef GNUSTEP
      NSString *platform = @"Linux";
#else
      NSString *platform = @"macOS";
#endif
      NSMutableArray *own = [NSMutableArray array];
      for (NSDictionary *target in targets)
        if ([PlatformOfRawTarget(target, objects) isEqual:platform]) [own addObject:target];
      if ([own count] == 1) targets = own;
    }
    if ([targets count] != 1)
      [NSException raise:@"XcodeImport" format:@"Expected one application target (found %lu). Select an application target with TargetName in GNUstep/ProjectCenter.plist.", (unsigned long)[targets count]];
    /* BuildScript, Executable and Theme may be build settings of the Linux
     * target by now. */
    settings = [self GNUstepSettingsOfProjectAtPath:path];
    NSDictionary *target = [targets objectAtIndex:0];
    if (![[target objectForKey:@"name"] isKindOfClass:[NSString class]] || ![[target objectForKey:@"name"] length])
      [NSException raise:@"XcodeImport" format:@"The application target has no name."];
    NSMutableDictionary *paths = [NSMutableDictionary dictionary];
    NSDictionary *mainGroup = ReadGroup([project objectForKey:@"mainGroup"], root, root, objects, paths, [NSMutableSet set]);
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                   path, PCXcodeProjectMarker, @"Application", @"PROJECT_TYPE",
                                   (SupportsGNUstep(target, objects) ? [target objectForKey:@"productName"] ?: [target objectForKey:@"name"] : [target objectForKey:@"name"]), @"PROJECT_NAME", nil];
    /* The navigator shows Xcode's own group hierarchy. */
    NSArray *groups = [mainGroup objectForKey:@"Children"];
    [result setObject:(groups ? groups : [NSArray array]) forKey:@"XCODE_GROUPS"];
    for (NSString *key in @[@"CLASS_FILES", @"HEADER_FILES", @"OTHER_SOURCES", @"INTERFACES", @"IMAGES", @"OTHER_RESOURCES", @"SUPPORTING_FILES"])
      [result setObject:[NSMutableArray array] forKey:key];
    NSString *prefix = [root stringByAppendingString:@"/"];
    for (NSString *identifier in [[paths allKeys] sortedArrayUsingSelector:@selector(compare:)])
    {
      NSString *file = [paths objectForKey:identifier];
      /* SDK and build-product references are not editable project sources. */
      if (![[NSFileManager defaultManager] fileExistsAtPath:file]) continue;
      if ([file hasPrefix:prefix]) file = [file substringFromIndex:[prefix length]];
      NSString *extension = [[file pathExtension] lowercaseString];
      NSString *key = @"OTHER_RESOURCES";
      if ([@[@"m", @"mm"] containsObject:extension]) key = @"CLASS_FILES";
      else if ([@[@"h", @"hpp"] containsObject:extension]) key = @"HEADER_FILES";
      else if ([@[@"c", @"cc", @"cpp", @"swift"] containsObject:extension]) key = @"OTHER_SOURCES";
      else if ([@[@"xib", @"nib", @"gorm", @"storyboard"] containsObject:extension]) key = @"INTERFACES";
      else if ([@[@"png", @"tiff", @"jpg", @"pdf", @"xcassets"] containsObject:extension]) key = @"IMAGES";
      if (![[result objectForKey:key] containsObject:file]) [[result objectForKey:key] addObject:file];
    }
    [[result objectForKey:@"SUPPORTING_FILES"] addObject:[[path lastPathComponent] stringByAppendingPathComponent:@"project.pbxproj"]];
    for (NSString *file in @[@"GNUmakefile", @"GNUstep/ProjectCenter.plist"])
      if ([[NSFileManager defaultManager] fileExistsAtPath:[root stringByAppendingPathComponent:file]])
        [[result objectForKey:@"SUPPORTING_FILES"] addObject:file];
    for (NSString *key in @[@"BuildScript", @"Executable"])
    {
      NSString *value = [settings objectForKey:key];
      if ([value length])
        [result setObject:([value isAbsolutePath] ? value : [[root stringByAppendingPathComponent:value] stringByStandardizingPath])
                   forKey:[@"XCODE_" stringByAppendingString:key]];
    }
    if ([[settings objectForKey:@"Theme"] length])
      [result setObject:[settings objectForKey:@"Theme"] forKey:@"XCODE_Theme"];
    return result;
  }
  @catch (NSException *exception)
  {
    if (error) *error = [exception reason];
    return nil;
  }
}

+ (NSDictionary *)overviewOfProjectAtPath:(NSString *)path error:(NSString **)error
{
  NSDictionary *plist, *objects, *project;
  NSMutableArray *targets = [NSMutableArray array];
  NSMutableDictionary *overview = [NSMutableDictionary dictionary];
  NSMutableDictionary *paths = [NSMutableDictionary dictionary];

  if (error) *error = nil;
  path = [[path stringByExpandingTildeInPath] stringByStandardizingPath];
  if ([[path lastPathComponent] isEqual:@"project.pbxproj"])
    path = [path stringByDeletingLastPathComponent];
  plist = [NSDictionary dictionaryWithContentsOfFile:[path stringByAppendingPathComponent:@"project.pbxproj"]];
  objects = [plist objectForKey:@"objects"];
  project = [objects objectForKey:[plist objectForKey:@"rootObject"]];
  if (![objects isKindOfClass:[NSDictionary class]] || ![[project objectForKey:@"isa"] isEqual:@"PBXProject"])
  {
    if (error) *error = [NSString stringWithFormat:@"Not a readable Xcode project: %@", path];
    return nil;
  }
  [overview setObject:[[path lastPathComponent] stringByDeletingPathExtension] forKey:@"Name"];
  [overview setObject:[plist objectForKey:@"rootObject"] forKey:@"Identifier"];
  ReadGroup([project objectForKey:@"mainGroup"], [path stringByDeletingLastPathComponent],
            [path stringByDeletingLastPathComponent], objects, paths, [NSMutableSet set]);
  if ([plist objectForKey:@"objectVersion"])
    [overview setObject:[plist objectForKey:@"objectVersion"] forKey:@"Format"];
  if ([project objectForKey:@"developmentRegion"])
    [overview setObject:[project objectForKey:@"developmentRegion"] forKey:@"DevelopmentRegion"];
  if ([[project objectForKey:@"knownRegions"] isKindOfClass:[NSArray class]])
    [overview setObject:[project objectForKey:@"knownRegions"] forKey:@"KnownRegions"];
  [overview setObject:Configurations(objects, [project objectForKey:@"buildConfigurationList"]) forKey:@"Configurations"];

  for (NSString *identifier in [project objectForKey:@"targets"])
  {
    NSDictionary *target = [objects objectForKey:identifier];
    NSMutableDictionary *entry = [NSMutableDictionary dictionary];
    NSMutableArray *phases = [NSMutableArray array];
    NSMutableArray *dependencies = [NSMutableArray array];
    NSString *isa = [target objectForKey:@"isa"];

    if (![target isKindOfClass:[NSDictionary class]]) continue;
    [entry setObject:(ObjectName(objects, identifier) ? ObjectName(objects, identifier) : identifier) forKey:@"Name"];
    [entry setObject:identifier forKey:@"Identifier"];
    [entry setObject:([isa isEqual:@"PBXNativeTarget"] ? @"Native"
                      : [isa isEqual:@"PBXAggregateTarget"] ? @"Aggregate"
                      : [isa isEqual:@"PBXLegacyTarget"] ? @"External" : (isa ? isa : @""))
              forKey:@"Kind"];
    if ([target objectForKey:@"productType"])
      [entry setObject:[target objectForKey:@"productType"] forKey:@"ProductType"];
    if ([target objectForKey:@"productName"])
      [entry setObject:[target objectForKey:@"productName"] forKey:@"ProductName"];
    [entry setObject:Configurations(objects, [target objectForKey:@"buildConfigurationList"]) forKey:@"Configurations"];
    for (NSString *phase in [target objectForKey:@"buildPhases"])
    {
      NSDictionary *description = Phase(objects, phase, paths);
      if (description) [phases addObject:description];
    }
    [entry setObject:phases forKey:@"Phases"];
    for (NSString *dependency in [target objectForKey:@"dependencies"])
    {
      NSString *name = ObjectName(objects, [[objects objectForKey:dependency] objectForKey:@"target"]);
      if (!name) name = [[objects objectForKey:dependency] objectForKey:@"name"];
      if ([name isKindOfClass:[NSString class]]) [dependencies addObject:name];
    }
    [entry setObject:dependencies forKey:@"Dependencies"];
    if ([target objectForKey:@"buildToolPath"])
      [entry setObject:[NSString stringWithFormat:@"%@ %@", [target objectForKey:@"buildToolPath"],
                        [target objectForKey:@"buildArgumentsString"] ? [target objectForKey:@"buildArgumentsString"] : @""]
                forKey:@"BuildTool"];
    [targets addObject:entry];
  }
  [overview setObject:targets forKey:@"Targets"];
  return overview;
}
// --- GNUstep settings and themes

static NSString *SettingsPath(NSString *path)
{
  path = [[path stringByExpandingTildeInPath] stringByStandardizingPath];
  if ([[path lastPathComponent] isEqual:@"project.pbxproj"])
  {
    path = [path stringByDeletingLastPathComponent];
  }
  return [[path stringByDeletingLastPathComponent]
          stringByAppendingPathComponent:@"GNUstep/ProjectCenter.plist"];
}

/* An OpenStep property list of strings, as the file is written by hand. */
static NSString *Quoted(NSString *string)
{
  NSMutableString *quoted = [NSMutableString stringWithString:string];

  [quoted replaceOccurrencesOfString:@"\\" withString:@"\\\\" options:0
                               range:NSMakeRange(0, [quoted length])];
  [quoted replaceOccurrencesOfString:@"\"" withString:@"\\\"" options:0
                               range:NSMakeRange(0, [quoted length])];
  [quoted replaceOccurrencesOfString:@"\n" withString:@"\\n" options:0
                               range:NSMakeRange(0, [quoted length])];
  return [NSString stringWithFormat:@"\"%@\"", quoted];
}

// --- Editing the Xcode project

/* project.pbxproj is edited as text, one entry at a time, so that the rest
 * of the file stays as Xcode wrote it. */

static NSUInteger SkipQuoted(NSString *text, NSUInteger i, NSUInteger end)
{
  for (i++; i < end; i++)
  {
    unichar c = [text characterAtIndex:i];

    if (c == '\\') i++;
    else if (c == '"') return i + 1;
  }
  return end;
}

/* Skips white space and comments. */
static NSUInteger SkipSpace(NSString *text, NSUInteger i, NSUInteger end)
{
  while (i < end)
  {
    unichar c = [text characterAtIndex:i];
    unichar next = i + 1 < end ? [text characterAtIndex:i + 1] : 0;

    if (c == ' ' || c == '\t' || c == '\n' || c == '\r')
    {
      i++;
    }
    else if (c == '/' && (next == '*' || next == '/'))
    {
      NSRange close = [text rangeOfString:(next == '*' ? @"*/" : @"\n") options:0
                                    range:NSMakeRange(i + 2, end - i - 2)];

      i = close.location == NSNotFound ? end : NSMaxRange(close);
    }
    else
    {
      break;
    }
  }
  return i;
}

/* The end of the value (or key) that starts at i. */
static NSUInteger ValueEnd(NSString *text, NSUInteger i, NSUInteger end)
{
  NSInteger depth = 0;

  while (i < end)
  {
    unichar c = [text characterAtIndex:i];

    if (c == '"')
    {
      i = SkipQuoted(text, i, end);
    }
    else if (c == '{' || c == '(')
    {
      depth++;
      i++;
    }
    else if (c == '}' || c == ')')
    {
      if (depth == 0) return i;
      depth--;
      i++;
    }
    else if (c == '/' && i + 1 < end && ([text characterAtIndex:i + 1] == '*'
                                         || [text characterAtIndex:i + 1] == '/'))
    {
      if (depth == 0) return i;
      i = SkipSpace(text, i, end);
    }
    else if (depth == 0 && (c == ';' || c == '=' || c == ',' || c == ' ' || c == '\t'
                            || c == '\n'))
    {
      return i;
    }
    else
    {
      i++;
    }
  }
  return end;
}

/* The entries `key = value;` of the dictionary whose contents run from start
 * to end: [{Key, Line (the whole line), Value}], as NSValue ranges. */
static NSArray *Entries(NSString *text, NSUInteger start, NSUInteger end)
{
  NSMutableArray *entries = [NSMutableArray array];
  NSUInteger     i = SkipSpace(text, start, end);

  while (i < end && [text characterAtIndex:i] != '}')
  {
    NSUInteger keyEnd = ValueEnd(text, i, end);
    NSString   *key = [text substringWithRange:NSMakeRange(i, keyEnd - i)];
    NSUInteger valueStart, valueEnd, lineStart, lineEnd;

    if ([key hasPrefix:@"\""])
    {
      @try { key = [key propertyList]; } @catch (NSException *exception) { key = nil; }
    }
    valueStart = SkipSpace(text, keyEnd, end);
    if (valueStart >= end || [text characterAtIndex:valueStart] != '=') break;
    valueStart = SkipSpace(text, valueStart + 1, end);
    valueEnd = ValueEnd(text, valueStart, end);
    lineEnd = SkipSpace(text, valueEnd, end);
    if (lineEnd >= end || [text characterAtIndex:lineEnd] != ';') break;
    lineEnd++;
    lineStart = [text rangeOfString:@"\n" options:NSBackwardsSearch
                              range:NSMakeRange(0, i)].location;
    lineStart = lineStart == NSNotFound ? 0 : lineStart + 1;
    if (lineEnd < end && [text characterAtIndex:lineEnd] == '\n') lineEnd++;
    [entries addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                        (key ? key : @""), @"Key",
                        [NSValue valueWithRange:NSMakeRange(lineStart, lineEnd - lineStart)], @"Line",
                        [NSValue valueWithRange:NSMakeRange(i, keyEnd - i)], @"KeyRange",
                        [NSValue valueWithRange:NSMakeRange(valueStart, valueEnd - valueStart)], @"Value",
                        nil]];
    i = SkipSpace(text, lineEnd, end);
  }
  return entries;
}

static NSDictionary *Entry(NSArray *entries, NSString *key)
{
  for (NSDictionary *entry in entries)
  {
    if ([[entry objectForKey:@"Key"] isEqual:key]) return entry;
  }
  return nil;
}

/* The contents of the dictionary value of an entry, inside its braces. */
static NSRange DictionaryContents(NSString *text, NSDictionary *entry)
{
  NSRange value = [[entry objectForKey:@"Value"] rangeValue];

  if (value.length < 2 || [text characterAtIndex:value.location] != '{')
  {
    return NSMakeRange(NSNotFound, 0);
  }
  return NSMakeRange(value.location + 1, value.length - 2);
}

/* The contents of an object in the objects dictionary. */
static NSRange ObjectContents(NSString *text, NSString *identifier)
{
  NSUInteger   start = SkipSpace(text, 0, [text length]);
  NSUInteger   end;
  NSDictionary *objects;

  if (start >= [text length] || [text characterAtIndex:start] != '{')
  {
    return NSMakeRange(NSNotFound, 0);
  }
  end = ValueEnd(text, start, [text length]);
  objects = Entry(Entries(text, start + 1, end), @"objects");
  if (objects == nil) return NSMakeRange(NSNotFound, 0);
  start = DictionaryContents(text, objects).location;
  if (start == NSNotFound) return NSMakeRange(NSNotFound, 0);
  return DictionaryContents(text, Entry(Entries(text, start, NSMaxRange(DictionaryContents(text, objects))),
                                        identifier));
}

/* A value as Xcode writes it: bare when it can be, else quoted. */
static NSString *PBXValue(NSString *value)
{
  static NSCharacterSet *bare = nil;

  if (bare == nil)
  {
    bare = [[[NSCharacterSet characterSetWithCharactersInString:
              @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_$/:."]
             invertedSet] retain];
  }
  if ([value length] && [value rangeOfCharacterFromSet:bare].location == NSNotFound
      && [value rangeOfString:@"//"].location == NSNotFound)
  {
    return value;
  }
  return Quoted(value);
}

/* Sets (or, with nil, removes) the entry `key` of the dictionary whose
 * contents are `contents`. New entries go in Xcode's order, sorted by key. */
static void SetEntry(NSMutableString *text, NSRange contents, NSString *key, NSString *value)
{
  NSArray      *entries = Entries(text, contents.location, NSMaxRange(contents));
  NSDictionary *entry = Entry(entries, key);
  NSString     *indent;
  NSUInteger   at;

  if (entry)
  {
    if (value)
      [text replaceCharactersInRange:[[entry objectForKey:@"Value"] rangeValue] withString:PBXValue(value)];
    else
      [text deleteCharactersInRange:[[entry objectForKey:@"Line"] rangeValue]];
    return;
  }
  if (value == nil) return;
  if ([entries count])
  {
    NSRange line = [[[entries objectAtIndex:0] objectForKey:@"Line"] rangeValue];

    indent = [text substringWithRange:NSMakeRange(line.location,
              [[[entries objectAtIndex:0] objectForKey:@"KeyRange"] rangeValue].location - line.location)];
    at = NSMaxRange([[[entries lastObject] objectForKey:@"Line"] rangeValue]);
    for (entry in entries)
    {
      if ([[entry objectForKey:@"Key"] compare:key] == NSOrderedDescending)
      {
        at = [[entry objectForKey:@"Line"] rangeValue].location;
        break;
      }
    }
  }
  else
  {
    /* An empty dictionary: one level deeper than its closing brace. */
    at = [text rangeOfString:@"\n" options:NSBackwardsSearch
                       range:NSMakeRange(0, NSMaxRange(contents))].location;
    if (at == NSNotFound || at < contents.location)
    {
      [text replaceCharactersInRange:contents withString:[NSString stringWithFormat:@" %@ = %@; ",
                                                          PBXValue(key), PBXValue(value)]];
      return;
    }
    at++;
    indent = [[text substringWithRange:NSMakeRange(at, NSMaxRange(contents) - at)]
              stringByAppendingString:@"\t"];
  }
  [text insertString:[NSString stringWithFormat:@"%@%@ = %@;\n", indent, PBXValue(key), PBXValue(value)]
             atIndex:at];
}

static NSString *PBXProjectFile(NSString *path)
{
  path = [[path stringByExpandingTildeInPath] stringByStandardizingPath];
  if ([[path lastPathComponent] isEqual:@"project.pbxproj"]) return path;
  return [path stringByAppendingPathComponent:@"project.pbxproj"];
}

/* Applies `edit` to the text of project.pbxproj and writes it, when the
 * result is still a property list. */
static BOOL EditProject(NSString *path, NSString **error, BOOL (^edit)(NSMutableString *))
{
  NSString        *file = PBXProjectFile(path);
  NSMutableString *text = [NSMutableString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding
                                                              error:NULL];
  NSString        *original = [[text copy] autorelease];
  id              plist = nil;

  if (error) *error = nil;
  if (text == nil)
  {
    if (error) *error = [NSString stringWithFormat:@"Cannot read %@.", file];
    return NO;
  }
  if (!edit(text))
  {
    if (error) *error = [NSString stringWithFormat:@"%@ does not have the expected entries.", file];
    return NO;
  }
  if ([text isEqual:original]) return YES;
  @try
  {
    plist = [text propertyList];
  }
  @catch (NSException *exception)
  {
    plist = nil;
  }
  if (![plist isKindOfClass:[NSDictionary class]])
  {
    if (error) *error = [NSString stringWithFormat:@"Editing %@ failed; it was left unchanged.", file];
    return NO;
  }
  if (![text writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:NULL])
  {
    if (error) *error = [NSString stringWithFormat:@"Cannot write %@.", file];
    return NO;
  }
  return YES;
}

/* An Info.plist value as XML. */
static NSString *XMLEscaped(NSString *string)
{
  NSMutableString *escaped = [NSMutableString stringWithString:string];

  [escaped replaceOccurrencesOfString:@"&" withString:@"&amp;" options:0
                                range:NSMakeRange(0, [escaped length])];
  [escaped replaceOccurrencesOfString:@"<" withString:@"&lt;" options:0
                                range:NSMakeRange(0, [escaped length])];
  [escaped replaceOccurrencesOfString:@">" withString:@"&gt;" options:0
                                range:NSMakeRange(0, [escaped length])];
  return escaped;
}

static id PropertyListOfString(NSString *text)
{
  NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];

  return data ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable
                                                           format:NULL error:NULL] : nil;
}

+ (BOOL)setBuildSetting:(NSString *)key
                     to:(NSString *)value
       inConfigurations:(NSArray *)identifiers
        ofProjectAtPath:(NSString *)path
                  error:(NSString **)error
{
  return EditProject(path, error, ^BOOL (NSMutableString *text) {
    for (NSString *identifier in identifiers)
    {
      NSRange      object = ObjectContents(text, identifier);
      NSDictionary *settings;

      if (object.location == NSNotFound) return NO;
      settings = Entry(Entries(text, object.location, NSMaxRange(object)), @"buildSettings");
      if (settings == nil || DictionaryContents(text, settings).location == NSNotFound) return NO;
      SetEntry(text, DictionaryContents(text, settings), key, value);
    }
    return YES;
  });
}

+ (BOOL)setAttribute:(NSString *)key
                  to:(NSString *)value
            ofObject:(NSString *)identifier
     ofProjectAtPath:(NSString *)path
               error:(NSString **)error
{
  return EditProject(path, error, ^BOOL (NSMutableString *text) {
    NSRange object = ObjectContents(text, identifier);

    if (object.location == NSNotFound) return NO;
    SetEntry(text, object, key, value);
    return YES;
  });
}

+ (BOOL)setInfoValue:(NSString *)value
              forKey:(NSString *)key
              inFile:(NSString *)file
               error:(NSString **)error
{
  NSString            *text = [NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding
                                                           error:NULL];
  NSDictionary        *original = text ? PropertyListOfString(text) : nil;
  NSMutableDictionary *expected;
  NSMutableString     *edited = nil;
  NSData              *data;

  if (error) *error = nil;
  if (![original isKindOfClass:[NSDictionary class]])
  {
    if (error) *error = [NSString stringWithFormat:@"%@ is not a readable property list.", file];
    return NO;
  }
  expected = [NSMutableDictionary dictionaryWithDictionary:original];
  if (value) [expected setObject:value forKey:key];
  else [expected removeObjectForKey:key];
  if ([expected isEqual:original]) return YES;

  if ([text rangeOfString:@"<plist"].location != NSNotFound)
  {
    /* Edit the XML in place, so the rest stays as written. */
    NSString            *pattern = [NSString stringWithFormat:
                                    @"^([ \\t]*)<key>%@</key>\\s*<string>([^<]*)</string>[ \\t]*\\n?",
                                    [NSRegularExpression escapedPatternForString:XMLEscaped(key)]];
    NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:pattern
                                       options:NSRegularExpressionAnchorsMatchLines error:NULL];
    NSArray             *matches = [expression matchesInString:text options:0
                                                         range:NSMakeRange(0, [text length])];

    edited = [NSMutableString stringWithString:text];
    if ([matches count] == 1)
    {
      NSTextCheckingResult *match = [matches objectAtIndex:0];

      if (value) [edited replaceCharactersInRange:[match rangeAtIndex:2] withString:XMLEscaped(value)];
      else [edited deleteCharactersInRange:[match range]];
    }
    else if ([matches count] == 0 && value)
    {
      NSRange              close = [edited rangeOfString:@"</dict>" options:NSBackwardsSearch];
      NSTextCheckingResult *first = [[NSRegularExpression regularExpressionWithPattern:@"^([ \\t]*)<key>"
                                      options:NSRegularExpressionAnchorsMatchLines error:NULL]
                                     firstMatchInString:edited options:0
                                                  range:NSMakeRange(0, [edited length])];
      NSString             *indent = first ? [edited substringWithRange:[first rangeAtIndex:1]] : @"\t";
      NSUInteger           at;

      if (close.location != NSNotFound)
      {
        at = [edited rangeOfString:@"\n" options:NSBackwardsSearch
                             range:NSMakeRange(0, close.location)].location;
        at = at == NSNotFound ? close.location : at + 1;
        [edited insertString:[NSString stringWithFormat:@"%@<key>%@</key>\n%@<string>%@</string>\n",
                              indent, XMLEscaped(key), indent, XMLEscaped(value)]
                     atIndex:at];
      }
    }
    if (![PropertyListOfString(edited) isEqual:expected]) edited = nil;
  }
  data = edited ? [edited dataUsingEncoding:NSUTF8StringEncoding]
    : [NSPropertyListSerialization dataWithPropertyList:expected format:NSPropertyListXMLFormat_v1_0
                                                options:0 error:NULL];
  if (data == nil || ![data writeToFile:file atomically:YES])
  {
    if (error) *error = [NSString stringWithFormat:@"Cannot write %@.", file];
    return NO;
  }
  return YES;
}

// --- GNUstep settings

+ (NSDictionary *)_sidecarSettingsOfProjectAtPath:(NSString *)path
{
  NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:SettingsPath(path)];

  return [settings isKindOfClass:[NSDictionary class]] ? settings : [NSDictionary dictionary];
}

/* The settings kept as build settings of the Linux target. */
static NSDictionary *TargetGNUstepKeys(void)
{
  return @{@"Theme": @"GNUSTEP_THEME", @"BuildScript": @"GNUSTEP_BUILD_SCRIPT",
           @"Executable": @"GNUSTEP_EXECUTABLE"};
}

+ (NSString *)platformOfTarget:(NSDictionary *)target
{
  for (NSDictionary *configuration in [target objectForKey:@"Configurations"])
  {
    NSString *sdk = [[[configuration objectForKey:@"Settings"] objectForKey:@"SDKROOT"] lowercaseString];

    if (![sdk isKindOfClass:[NSString class]]) continue;
    id platforms = [[configuration objectForKey:@"Settings"] objectForKey:@"SUPPORTED_PLATFORMS"];
    if ([platforms isKindOfClass:[NSString class]]) platforms = [platforms componentsSeparatedByString:@" "];
    if ([sdk isEqual:@"linux"] || [sdk isEqual:@"gnustep"] || [platforms containsObject:@"gnustep"]) return @"Linux";
    if ([sdk isEqual:@"windows"]) return @"Windows";
  }
  return @"macOS";
}

+ (NSDictionary *)linuxTargetOfOverview:(NSDictionary *)overview
{
  for (NSDictionary *target in [overview objectForKey:@"Targets"])
  {
    if ([[self platformOfTarget:target] isEqual:@"Linux"]) return target;
  }
  return nil;
}

+ (NSString *)buildSetting:(NSString *)key ofTarget:(NSDictionary *)target
{
  NSArray *configurations = [target objectForKey:@"Configurations"];
  id      value = nil;

  /* Release first: the configuration Archive builds. */
  for (NSDictionary *configuration in configurations)
  {
    if ([[configuration objectForKey:@"Name"] isEqual:@"Release"])
    {
      value = [[configuration objectForKey:@"Settings"] objectForKey:key];
    }
  }
  for (NSDictionary *configuration in configurations)
  {
    if (value == nil) value = [[configuration objectForKey:@"Settings"] objectForKey:key];
  }
  if ([value isKindOfClass:[NSArray class]]) value = [value componentsJoinedByString:@" "];
  return [value isKindOfClass:[NSString class]] ? value : nil;
}

+ (BOOL)setBuildSetting:(NSString *)key
                     to:(NSString *)value
               ofTarget:(NSDictionary *)target
        ofProjectAtPath:(NSString *)path
                  error:(NSString **)error
{
  NSArray *identifiers = [[target objectForKey:@"Configurations"] valueForKey:@"Identifier"];

  if ([identifiers count] == 0)
  {
    if (error) *error = [NSString stringWithFormat:@"The target %@ has no build configurations.",
                         [target objectForKey:@"Name"]];
    return NO;
  }
  return [self setBuildSetting:key to:([value length] ? value : nil) inConfigurations:identifiers
               ofProjectAtPath:path error:error];
}

+ (NSDictionary *)GNUstepSettingsOfProjectAtPath:(NSString *)path
{
  NSMutableDictionary *settings = [NSMutableDictionary dictionaryWithDictionary:
                                   [self _sidecarSettingsOfProjectAtPath:path]];
  NSDictionary        *keys = TargetGNUstepKeys();
  NSDictionary        *target = [self linuxTargetOfOverview:[self overviewOfProjectAtPath:path error:NULL]];

  /* A value of the Linux target wins over one GNUstep/ProjectCenter.plist
   * still has from before. */
  for (NSString *key in keys)
  {
    NSString *value = [self buildSetting:[keys objectForKey:key] ofTarget:target];

    if ([value length]) [settings setObject:value forKey:key];
  }
  return settings;
}

/* A value as an OpenStep property list, indented as the file's top level
 * entries are: strings quoted, arrays and dictionaries one entry a line,
 * dictionaries sorted. */
static NSString *PropertyListText(id value, NSString *indent)
{
  NSMutableString *text;
  NSString        *inner = [indent stringByAppendingString:@"    "];
  NSUInteger      i = 0;

  if ([value isKindOfClass:[NSArray class]])
  {
    if ([value count] == 0) return @"()";
    text = [NSMutableString stringWithString:@"(\n"];
    for (id item in value)
    {
      [text appendFormat:@"%@%@%@\n", inner, PropertyListText(item, inner), ++i < [value count] ? @"," : @""];
    }
    [text appendFormat:@"%@)", indent];
    return text;
  }
  if ([value isKindOfClass:[NSDictionary class]])
  {
    if ([value count] == 0) return @"{}";
    text = [NSMutableString stringWithString:@"{\n"];
    for (NSString *key in [[value allKeys] sortedArrayUsingSelector:@selector(compare:)])
    {
      [text appendFormat:@"%@%@ = %@;\n", inner, key, PropertyListText([value objectForKey:key], inner)];
    }
    [text appendFormat:@"%@}", indent];
    return text;
  }
  return Quoted([value description]);
}

+ (BOOL)setGNUstepSetting:(NSString *)value
                   forKey:(NSString *)key
         ofProjectAtPath:(NSString *)path
                    error:(NSString **)error
{
  NSString     *setting = [TargetGNUstepKeys() objectForKey:key];
  NSDictionary *target = setting ? [self linuxTargetOfOverview:[self overviewOfProjectAtPath:path error:NULL]] : nil;

  if (target)
  {
    /* Into the Linux target; then out of ProjectCenter.plist, if it was
     * there. */
    if (![self setBuildSetting:setting to:value ofTarget:target ofProjectAtPath:path error:error]) return NO;
    if ([[self _sidecarSettingsOfProjectAtPath:path] objectForKey:key] == nil) return YES;
    return [self setGNUstepValue:nil forKey:key ofProjectAtPath:path error:error];
  }
  return [self setGNUstepValue:value forKey:key ofProjectAtPath:path error:error];
}

+ (BOOL)setGNUstepValue:(id)value
                 forKey:(NSString *)key
        ofProjectAtPath:(NSString *)path
                  error:(NSString **)error
{
  NSFileManager       *fm = [NSFileManager defaultManager];
  NSString            *file = SettingsPath(path);
  NSMutableDictionary *settings = [NSMutableDictionary dictionaryWithDictionary:
                                   [self _sidecarSettingsOfProjectAtPath:path]];
  NSMutableString     *text = [NSMutableString stringWithString:@"{\n"];

  if (error) *error = nil;
  if ([fm fileExistsAtPath:file] && [NSDictionary dictionaryWithContentsOfFile:file] == nil)
  {
    if (error) *error = [NSString stringWithFormat:@"%@ is not a valid property list.", file];
    return NO;
  }
  if ([value isKindOfClass:[NSString class]] ? [value length] > 0 : [value count] > 0)
  {
    [settings setObject:value forKey:key];
  }
  else
  {
    [settings removeObjectForKey:key];
  }
  if ([settings count] == 0)
  {
    if ([fm fileExistsAtPath:file] && ![fm removeItemAtPath:file error:NULL])
    {
      if (error) *error = [NSString stringWithFormat:@"Cannot remove %@.", file];
      return NO;
    }
    /* The GNUstep folder too, when nothing else is in it. */
    if ([[fm contentsOfDirectoryAtPath:[file stringByDeletingLastPathComponent] error:NULL] count] == 0)
    {
      [fm removeItemAtPath:[file stringByDeletingLastPathComponent] error:NULL];
    }
    return YES;
  }
  for (NSString *name in [[settings allKeys] sortedArrayUsingSelector:@selector(compare:)])
  {
    [text appendFormat:@"    %@ = %@;\n", name, PropertyListText([settings objectForKey:name], @"    ")];
  }
  [text appendString:@"}\n"];
  [fm createDirectoryAtPath:[file stringByDeletingLastPathComponent]
withIntermediateDirectories:YES attributes:nil error:NULL];
  if (![text writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:NULL])
  {
    if (error) *error = [NSString stringWithFormat:@"Cannot write %@.", file];
    return NO;
  }
  return YES;
}

+ (NSArray *)themesInLibraries:(NSArray *)libraries
{
  NSMutableSet *themes = [NSMutableSet set];

  for (NSString *library in libraries)
  {
    NSString *folder = [library stringByAppendingPathComponent:@"Themes"];

    for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:folder error:NULL])
    {
      BOOL isDirectory = NO;

      if ([[name pathExtension] isEqual:@"theme"]
          && [[NSFileManager defaultManager] fileExistsAtPath:[folder stringByAppendingPathComponent:name]
                                                  isDirectory:&isDirectory]
          && isDirectory)
      {
        [themes addObject:[name stringByDeletingPathExtension]];
      }
    }
  }
  return [[themes allObjects] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

+ (NSArray *)installedThemes
{
  NSMutableSet *names = [NSMutableSet set];
  NSMutableArray *folders = [NSMutableArray array];
  NSDictionary *environment = [[NSProcessInfo processInfo] environment];

  /* Installed application providers register the same pkg-config profiles
   * that GNUstep Make uses when linking the selected appearance. */
  for (NSString *key in @[@"PKG_CONFIG_PATH", @"PKG_CONFIG_LIBDIR"])
    if ([[environment objectForKey:key] length])
      [folders addObjectsFromArray:[[environment objectForKey:key] componentsSeparatedByString:@":"]];
  for (NSString *variable in @[@"GNUSTEP_SYSTEM_LIBRARIES", @"GNUSTEP_LOCAL_LIBRARIES", @"GNUSTEP_USER_LIBRARIES"])
  {
    NSData *data = RunTool(@"/usr/bin/env", @[@"gnustep-config", [@"--variable=" stringByAppendingString:variable]]);
    NSString *path = data ? [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease] : nil;
    path = [path stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([path length]) [folders addObject:[path stringByAppendingPathComponent:@"pkgconfig"]];
  }
  NSData *data = RunTool(@"/usr/bin/env", @[@"pkg-config", @"--variable=pc_path", @"pkg-config"]);
  NSString *path = data ? [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease] : nil;
  if ([path length]) [folders addObjectsFromArray:[[path stringByTrimmingCharactersInSet:
    [NSCharacterSet whitespaceAndNewlineCharacterSet]] componentsSeparatedByString:@":"]];
  for (NSString *folder in folders)
    for (NSString *file in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:folder error:NULL])
      if ([file hasPrefix:@"gnustep-theme-"] && [file hasSuffix:@".pc"])
      {
        NSString *name = [[file stringByDeletingPathExtension] substringFromIndex:[@"gnustep-theme-" length]];
        if ([name length]) [names addObject:name];
      }
  return [[names allObjects] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

+ (NSArray *)launchArgumentsForProject:(NSDictionary *)projectDict
{
  NSString *theme = [projectDict objectForKey:@"XCODE_Theme"];

  return [theme length] ? [NSArray arrayWithObjects:@"-GSTheme", theme, nil] : [NSArray array];
}

// --- Schemes, configurations and run destinations

static NSString * const PCXcodeSelectionsDefault = @"PCXcodeBuildSelections";

static NSString *ProjectBundlePath(NSString *path)
{
  path = [[path stringByExpandingTildeInPath] stringByStandardizingPath];
  if ([[path lastPathComponent] isEqual:@"project.pbxproj"])
  {
    path = [path stringByDeletingLastPathComponent];
  }
  return path;
}

static NSDictionary *ProjectObjects(NSString *path, NSDictionary **project)
{
  NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:
                         [path stringByAppendingPathComponent:@"project.pbxproj"]];
  NSDictionary *objects = [plist objectForKey:@"objects"];
  NSDictionary *root = [objects objectForKey:[plist objectForKey:@"rootObject"]];

  if (![objects isKindOfClass:[NSDictionary class]]
      || ![[root objectForKey:@"isa"] isEqual:@"PBXProject"])
  {
    return nil;
  }
  if (project)
  {
    *project = root;
  }
  return objects;
}

static NSString *UserDataPath(NSString *path)
{
  return [path stringByAppendingPathComponent:
          [NSString stringWithFormat:@"xcuserdata/%@.xcuserdatad", NSUserName()]];
}

/* Changes when the project, its scheme folders or the user's scheme order
 * change, so cached schemes are read again. */
static NSString *ProjectSignature(NSString *path)
{
  NSFileManager   *fm = [NSFileManager defaultManager];
  NSMutableString *signature = [NSMutableString stringWithString:path];
  NSArray         *files = @[@"project.pbxproj", @"xcshareddata/xcschemes",
                             @"xcshareddata/xcschemes/xcschememanagement.plist"];

  files = [files arrayByAddingObjectsFromArray:
           @[[UserDataPath(@"") stringByAppendingPathComponent:@"xcschemes"],
             [UserDataPath(@"") stringByAppendingPathComponent:@"xcschemes/xcschememanagement.plist"]]];
  for (NSString *file in files)
  {
    NSString *full = [path stringByAppendingPathComponent:file];
    NSArray  *names = [[full pathExtension] length] ? nil : [fm contentsOfDirectoryAtPath:full error:NULL];

    [signature appendFormat:@"|%@", [[fm attributesOfItemAtPath:full error:NULL] fileModificationDate]];
    /* A scheme edited in place leaves its folder's date unchanged. */
    for (NSString *name in names)
    {
      [signature appendFormat:@",%@", [[fm attributesOfItemAtPath:[full stringByAppendingPathComponent:name]
                                                            error:NULL] fileModificationDate]];
    }
  }
  return signature;
}

static NSString *Attribute(NSXMLElement *element, NSString *name)
{
  NSString *value = [[element attributeForName:name] stringValue];

  return [value length] ? value : nil;
}

static NSArray *Elements(NSXMLNode *node, NSString *query)
{
  NSArray *nodes = [node nodesForXPath:query error:NULL];

  return nodes ? nodes : [NSArray array];
}

/* {Name, Shared, Targets, RunTarget, Configurations} from an .xcscheme. */
static NSMutableDictionary *ReadScheme(NSString *file, BOOL shared)
{
  NSData              *data = [NSData dataWithContentsOfFile:file];
  NSXMLDocument       *document;
  NSXMLElement        *root;
  NSMutableArray      *targets = [NSMutableArray array];
  NSMutableArray      *allTargets = [NSMutableArray array];
  NSMutableDictionary *configurations = [NSMutableDictionary dictionary];
  NSMutableDictionary *scheme;
  NSDictionary        *actions;
  NSString            *runTarget;

  if (data == nil)
  {
    return nil;
  }
  document = [[[NSXMLDocument alloc] initWithData:data options:0 error:NULL] autorelease];
  root = [document rootElement];
  if (![[root name] isEqual:@"Scheme"])
  {
    return nil;
  }
  for (NSXMLElement *entry in Elements(root, @"BuildAction/BuildActionEntries/BuildActionEntry"))
  {
    NSString *name = Attribute([Elements(entry, @"BuildableReference") lastObject],
                               @"BlueprintName");

    if (name == nil)
    {
      continue;
    }
    [allTargets addObject:name];
    if ([Attribute(entry, @"buildForRunning") isEqual:@"YES"])
    {
      [targets addObject:name];
    }
  }
  actions = [NSDictionary dictionaryWithObjectsAndKeys:
             @"Run", @"LaunchAction", @"Test", @"TestAction",
             @"Profile", @"ProfileAction", @"Analyze", @"AnalyzeAction",
             @"Archive", @"ArchiveAction", nil];
  for (NSString *action in actions)
  {
    NSString *configuration = Attribute([Elements(root, action) lastObject],
                                        @"buildConfiguration");

    if (configuration)
    {
      [configurations setObject:configuration forKey:[actions objectForKey:action]];
    }
  }
  runTarget = Attribute([Elements(root, @"LaunchAction/BuildableProductRunnable/BuildableReference")
                         lastObject], @"BlueprintName");
  scheme = [NSMutableDictionary dictionaryWithObjectsAndKeys:
            [[file lastPathComponent] stringByDeletingPathExtension], @"Name",
            [NSNumber numberWithBool:shared], @"Shared",
            [NSNumber numberWithBool:NO], @"Implicit",
            ([targets count] ? targets : allTargets), @"Targets",
            configurations, @"Configurations", nil];
  if (runTarget)
  {
    [scheme setObject:runTarget forKey:@"RunTarget"];
  }
  return scheme;
}

static NSArray *SchemeFiles(NSString *directory)
{
  NSMutableArray *files = [NSMutableArray array];
  NSArray        *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:NULL];

  for (NSString *name in [names sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)])
  {
    if ([[name pathExtension] isEqual:@"xcscheme"])
    {
      [files addObject:[directory stringByAppendingPathComponent:name]];
    }
  }
  return files;
}

static NSInteger CompareSchemes(id a, id b, void *context)
{
  NSComparisonResult result = [[a objectForKey:@"_Hint"] compare:[b objectForKey:@"_Hint"]];

  return result != NSOrderedSame ? result : [[a objectForKey:@"_Index"] compare:[b objectForKey:@"_Index"]];
}

static NSArray *ConfigurationNames(NSDictionary *objects, NSDictionary *project)
{
  return [Configurations(objects, [project objectForKey:@"buildConfigurationList"])
          valueForKey:@"Name"];
}

static NSArray *ReadSchemes(NSString *path)
{
  NSDictionary   *project = nil;
  NSDictionary   *objects = ProjectObjects(path, &project);
  NSMutableArray *schemes = [NSMutableArray array];
  NSMutableSet   *built = [NSMutableSet set];
  NSString       *user = UserDataPath(path);
  NSDictionary   *state;
  NSArray        *names = ConfigurationNames(objects, project);
  NSString       *runConfiguration;
  NSString       *releaseConfiguration;
  NSUInteger     index = 0;

  if (objects == nil)
  {
    return [NSArray array];
  }
  for (NSString *file in SchemeFiles([path stringByAppendingPathComponent:@"xcshareddata/xcschemes"]))
  {
    NSMutableDictionary *scheme = ReadScheme(file, YES);
    if (scheme) [schemes addObject:scheme];
  }
  for (NSString *file in SchemeFiles([user stringByAppendingPathComponent:@"xcschemes"]))
  {
    NSMutableDictionary *scheme = ReadScheme(file, NO);
    if (scheme) [schemes addObject:scheme];
  }
  for (NSDictionary *scheme in schemes)
  {
    [built addObjectsFromArray:[scheme objectForKey:@"Targets"]];
  }

  /* Xcode creates a scheme for each target that none builds, with the
   * configurations of a new scheme. */
  runConfiguration = [names containsObject:@"Debug"] ? @"Debug" : [names firstObject];
  releaseConfiguration = [[objects objectForKey:[project objectForKey:@"buildConfigurationList"]]
                          objectForKey:@"defaultConfigurationName"];
  if (![names containsObject:releaseConfiguration])
  {
    releaseConfiguration = [names containsObject:@"Release"] ? @"Release" : [names lastObject];
  }
  for (NSString *identifier in [project objectForKey:@"targets"])
  {
    NSDictionary        *target = [objects objectForKey:identifier];
    NSString            *name = [target objectForKey:@"name"];
    NSString            *type = [target objectForKey:@"productType"];
    NSMutableDictionary *scheme;

    if (![name isKindOfClass:[NSString class]] || [built containsObject:name])
    {
      continue;
    }
    scheme = [NSMutableDictionary dictionaryWithObjectsAndKeys:
              name, @"Name", [NSNumber numberWithBool:YES], @"Shared",
              [NSNumber numberWithBool:YES], @"Implicit", @[name], @"Targets",
              [NSMutableDictionary dictionary], @"Configurations", nil];
    if (runConfiguration)
    {
      for (NSString *action in @[@"Run", @"Test", @"Analyze"])
        [[scheme objectForKey:@"Configurations"] setObject:runConfiguration forKey:action];
    }
    if (releaseConfiguration)
    {
      for (NSString *action in @[@"Profile", @"Archive"])
        [[scheme objectForKey:@"Configurations"] setObject:releaseConfiguration forKey:action];
    }
    if ([type isEqual:@"com.apple.product-type.application"]
        || [type isEqual:@"com.apple.product-type.tool"])
    {
      [scheme setObject:name forKey:@"RunTarget"];
    }
    [schemes addObject:scheme];
  }

  /* A native GNUstep target can coexist with the original Apple targets. */
  for (NSMutableDictionary *scheme in schemes)
    for (NSString *identifier in [project objectForKey:@"targets"])
    {
      NSDictionary *target = [objects objectForKey:identifier];
      if (![[target objectForKey:@"name"] isEqual:[scheme objectForKey:@"RunTarget"]]) continue;
      if (SupportsGNUstep(target, objects)) [scheme setObject:@YES forKey:@"SupportsGNUstep"];
    }

  /* The order and visibility the user chose in Manage Schemes. */
  state = [[NSDictionary dictionaryWithContentsOfFile:
            [user stringByAppendingPathComponent:@"xcschemes/xcschememanagement.plist"]]
           objectForKey:@"SchemeUserState"];
  for (NSMutableDictionary *scheme in [[schemes copy] autorelease])
  {
    NSString     *file = [[scheme objectForKey:@"Name"] stringByAppendingPathExtension:@"xcscheme"];
    NSDictionary *entry = [state objectForKey:[file stringByAppendingString:@"_^#shared#^_"]];
    id           hint;

    if (entry == nil)
    {
      entry = [state objectForKey:file];
    }
    if ([entry objectForKey:@"isShown"] && ![[entry objectForKey:@"isShown"] boolValue])
    {
      [schemes removeObject:scheme];
      continue;
    }
    hint = [entry objectForKey:@"orderHint"];
    [scheme setObject:[NSNumber numberWithInteger:([hint respondsToSelector:@selector(integerValue)]
                                                   ? [hint integerValue] : NSIntegerMax)]
               forKey:@"_Hint"];
    [scheme setObject:[NSNumber numberWithUnsignedInteger:index++] forKey:@"_Index"];
  }
  [schemes sortUsingFunction:CompareSchemes context:NULL];
  [schemes makeObjectsPerformSelector:@selector(removeObjectForKey:) withObject:@"_Hint"];
  [schemes makeObjectsPerformSelector:@selector(removeObjectForKey:) withObject:@"_Index"];
  return schemes;
}

/* The architecture of this computer, also when running under Rosetta. */
static NSString *NativeArchitecture(void)
{
#ifdef __APPLE__
  int    arm64 = 0;
  size_t size = sizeof(arm64);

  if (sysctlbyname("hw.optional.arm64", &arm64, &size, NULL, 0) == 0 && arm64)
  {
    return @"arm64";
  }
  return @"x86_64";
#elif defined(__aarch64__)
  return @"arm64";
#else
  return @"x86_64";
#endif
}

+ (NSArray *)schemesOfProjectAtPath:(NSString *)path
{
  static NSMutableDictionary *cache = nil;
  NSString *signature;
  NSArray  *schemes;

  path = ProjectBundlePath(path);
  signature = ProjectSignature(path);
  if (cache == nil)
  {
    cache = [NSMutableDictionary new];
  }
  schemes = [[cache objectForKey:path] objectForKey:@"Schemes"];
  if (schemes == nil || ![[[cache objectForKey:path] objectForKey:@"Signature"] isEqual:signature])
  {
    schemes = ReadSchemes(path);
    [cache setObject:@{@"Schemes": schemes, @"Signature": signature} forKey:path];
  }
  return schemes;
}

+ (NSArray *)configurationsOfProjectAtPath:(NSString *)path
{
  NSDictionary *project = nil;
  NSDictionary *objects = ProjectObjects(ProjectBundlePath(path), &project);
  NSArray      *names = objects ? ConfigurationNames(objects, project) : nil;

  return names ? names : [NSArray array];
}

+ (NSArray *)runDestinations
{
  NSString       *native = NativeArchitecture();
  NSMutableArray *destinations = [NSMutableArray array];
  NSNumber       *no = [NSNumber numberWithBool:NO];

  [destinations addObject:@{@"Name": @"My Mac", @"Architecture": native, @"BuildOnly": no,
                            @"Destination": [@"platform=macOS,arch=" stringByAppendingString:native]}];
  /* Intel code runs on Apple silicon only where Rosetta is installed. */
  if ([native isEqual:@"arm64"]
      && [[NSFileManager defaultManager] fileExistsAtPath:@"/Library/Apple/usr/libexec/oah/libRosettaRuntime"])
  {
    [destinations addObject:@{@"Name": @"My Mac (Rosetta)", @"Architecture": @"x86_64",
                              @"BuildOnly": no, @"Destination": @"platform=macOS,arch=x86_64"}];
  }
  /* GNUstep's make and libraries, where GNUstep is installed. */
  if ([self GNUstepMakefiles])
  {
    [destinations addObject:@{@"Name": @"My Mac (GNUstep)", @"Architecture": native,
                              @"BuildOnly": no, @"GNUstep": [NSNumber numberWithBool:YES]}];
  }
  [destinations addObject:@{@"Name": @"Any Mac (arm64, x86_64)",
                            @"BuildOnly": [NSNumber numberWithBool:YES],
                            @"Destination": @"generic/platform=macOS"}];
  return destinations;
}

static NSDictionary *Named(NSArray *entries, NSString *name)
{
  for (NSDictionary *entry in entries)
  {
    if ([[entry objectForKey:@"Name"] isEqual:name])
    {
      return entry;
    }
  }
  return nil;
}

static NSDictionary *SavedSelection(NSString *path)
{
  return [[[NSUserDefaults standardUserDefaults] dictionaryForKey:PCXcodeSelectionsDefault]
          objectForKey:path];
}

+ (NSDictionary *)buildSelectionForProject:(NSDictionary *)projectDict
{
  NSString     *path = [projectDict objectForKey:PCXcodeProjectMarker];
  NSString     *application = [projectDict objectForKey:@"PROJECT_NAME"];
  NSArray      *schemes;
  NSArray      *configurations;
  NSArray      *destinations = [self runDestinations];
  NSDictionary *saved;
  NSDictionary *scheme = nil;
  NSString     *configuration;
  NSDictionary *destination;

  if (path == nil)
  {
    return nil;
  }
  schemes = [self schemesOfProjectAtPath:path];
  configurations = [self configurationsOfProjectAtPath:path];
  saved = SavedSelection(path);
  scheme = Named(schemes, [saved objectForKey:@"Scheme"]);
#ifdef GNUSTEP
  if (scheme == nil)
    for (NSDictionary *candidate in schemes)
      if ([[candidate objectForKey:@"SupportsGNUstep"] boolValue]) { scheme = candidate; break; }
#endif

  if (scheme == nil)
  {
    scheme = Named(schemes, application);
  }
  if (scheme == nil)
  {
    for (NSDictionary *candidate in schemes)
    {
      if ([[candidate objectForKey:@"RunTarget"] isEqual:application])
      {
        scheme = candidate;
        break;
      }
    }
  }
  if (scheme == nil)
  {
    scheme = [schemes firstObject];
  }
  if (scheme == nil && application)
  {
    scheme = @{@"Name": application, @"Shared": @YES, @"Implicit": @YES,
               @"Targets": @[application], @"RunTarget": application,
               @"Configurations": @{}};
  }
  configuration = [[saved objectForKey:@"Configurations"] objectForKey:[scheme objectForKey:@"Name"]];
  if (![configurations containsObject:configuration])
  {
    configuration = [[scheme objectForKey:@"Configurations"] objectForKey:@"Run"];
  }
  if (configuration == nil)
  {
    configuration = [configurations containsObject:@"Debug"] || [configurations count] == 0
      ? @"Debug" : [configurations firstObject];
  }
  destination = Named(destinations, [saved objectForKey:@"Destination"]);
  if (destination == nil)
  {
    destination = [destinations firstObject];
  }
  return [NSDictionary dictionaryWithObjectsAndKeys:scheme, @"Scheme",
          configuration, @"Configuration", destination, @"Destination", nil];
}

+ (void)selectScheme:(NSString *)scheme
       configuration:(NSString *)configuration
         destination:(NSString *)destination
          forProject:(NSDictionary *)projectDict
{
  NSUserDefaults      *defaults = [NSUserDefaults standardUserDefaults];
  NSString            *path = [projectDict objectForKey:PCXcodeProjectMarker];
  NSMutableDictionary *all;
  NSMutableDictionary *saved;
  NSMutableDictionary *overrides;
  NSDictionary        *current;
  NSString            *schemeName;
  NSString            *own;

  if (path == nil)
  {
    return;
  }
  all = [NSMutableDictionary dictionaryWithDictionary:
         [defaults dictionaryForKey:PCXcodeSelectionsDefault]];
  saved = [NSMutableDictionary dictionaryWithDictionary:[all objectForKey:path]];
  overrides = [NSMutableDictionary dictionaryWithDictionary:[saved objectForKey:@"Configurations"]];
  if (scheme)
  {
    [saved setObject:scheme forKey:@"Scheme"];
  }
  if (destination)
  {
    [saved setObject:destination forKey:@"Destination"];
  }
  [all setObject:saved forKey:path];
  [defaults setObject:all forKey:PCXcodeSelectionsDefault];
  if (configuration)
  {
    current = [self buildSelectionForProject:projectDict];
    schemeName = [[current objectForKey:@"Scheme"] objectForKey:@"Name"];
    own = [[[current objectForKey:@"Scheme"] objectForKey:@"Configurations"] objectForKey:@"Run"];
    if ([configuration isEqual:own])
    {
      [overrides removeObjectForKey:schemeName];
    }
    else if (schemeName)
    {
      [overrides setObject:configuration forKey:schemeName];
    }
    [saved setObject:overrides forKey:@"Configurations"];
    [all setObject:saved forKey:path];
    [defaults setObject:all forKey:PCXcodeSelectionsDefault];
  }
}

// --- Building with xcodebuild

static NSData *RunTool(NSString *tool, NSArray *arguments)
{
  NSTask *task = [[NSTask alloc] init];
  NSPipe *output = [NSPipe pipe];
  NSData *data = nil;

  [task setLaunchPath:tool];
  [task setArguments:arguments];
  [task setStandardOutput:output];
  [task setStandardError:[NSFileHandle fileHandleWithNullDevice]];
  @try
  {
    [task launch];
    data = [[output fileHandleForReading] readDataToEndOfFile];
    [task waitUntilExit];
    if ([task terminationStatus] != 0)
    {
      data = nil;
    }
  }
  @catch (NSException *exception)
  {
    data = nil;
  }
  [task release];
  return data;
}

static id JSONFromTool(NSString *tool, NSArray *arguments)
{
  NSData *data = RunTool(tool, arguments);

  if (data == nil)
  {
    return nil;
  }
  return [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
}

+ (NSString *)xcodebuildPath
{
  NSString *path = @"/usr/bin/xcodebuild";

  return [[NSFileManager defaultManager] isExecutableFileAtPath:path] ? path : nil;
}

/* The schemes that xcodebuild can build, asked again when the project's
 * schemes change. */
+ (NSArray *)_xcodebuildSchemesOfProjectAtPath:(NSString *)path
{
  static NSMutableDictionary *cache = nil;
  NSString *signature = ProjectSignature(path);
  NSArray  *known;

  if (cache == nil)
  {
    cache = [NSMutableDictionary new];
  }
  known = [[cache objectForKey:path] objectForKey:@"Schemes"];
  if (known == nil || ![[[cache objectForKey:path] objectForKey:@"Signature"] isEqual:signature])
  {
    NSDictionary *list = JSONFromTool([self xcodebuildPath],
                                      @[@"-list", @"-json", @"-project", path]);

    known = [[list objectForKey:@"project"] objectForKey:@"schemes"];
    if (![known isKindOfClass:[NSArray class]])
    {
      known = [NSArray array];
    }
    [cache setObject:@{@"Schemes": known, @"Signature": signature} forKey:path];
  }
  return known;
}

/* -project, -scheme or -target, -configuration and the architectures. */
+ (NSArray *)_xcodebuildSelectionForProject:(NSDictionary *)projectDict
                                  selection:(NSDictionary *)selection
                               knownSchemes:(NSArray *)knownSchemes
{
  NSString       *path = [projectDict objectForKey:PCXcodeProjectMarker];
  NSDictionary   *scheme = [selection objectForKey:@"Scheme"];
  NSDictionary   *destination = [selection objectForKey:@"Destination"];
  NSString       *name = [scheme objectForKey:@"Name"];
  NSMutableArray *arguments;

  if (path == nil || name == nil)
  {
    return nil;
  }
  arguments = [NSMutableArray arrayWithObjects:@"-project", path, nil];
  if ([knownSchemes containsObject:name])
  {
    [arguments addObjectsFromArray:@[@"-scheme", name,
                                     @"-configuration", [selection objectForKey:@"Configuration"]]];
    if ([destination objectForKey:@"Destination"])
    {
      [arguments addObjectsFromArray:@[@"-destination", [destination objectForKey:@"Destination"]]];
    }
    return arguments;
  }

  /* Without a scheme there is no run destination: ask for its
   * architectures instead. */
  NSString *target = [scheme objectForKey:@"RunTarget"];
  if (target == nil)
  {
    target = [[scheme objectForKey:@"Targets"] firstObject];
  }
  if (target == nil)
  {
    target = name;
  }
  [arguments addObjectsFromArray:@[@"-target", target,
                                   @"-configuration", [selection objectForKey:@"Configuration"]]];
  if ([[destination objectForKey:@"BuildOnly"] boolValue])
  {
    [arguments addObject:@"ONLY_ACTIVE_ARCH=NO"];
  }
  else if ([destination objectForKey:@"Architecture"]
           && ![[destination objectForKey:@"Architecture"] isEqual:NativeArchitecture()])
  {
    [arguments addObjectsFromArray:@[@"-arch", [destination objectForKey:@"Architecture"]]];
  }
  return arguments;
}

+ (NSArray *)xcodebuildArgumentsForProject:(NSDictionary *)projectDict
                                    action:(NSString *)action
                                 selection:(NSDictionary *)selection
                              knownSchemes:(NSArray *)knownSchemes
{
  NSArray *arguments = [self _xcodebuildSelectionForProject:projectDict
                                                  selection:selection
                                               knownSchemes:knownSchemes];

  /* -quiet leaves the warnings, errors and the result. */
  return [arguments arrayByAddingObjectsFromArray:@[@"-quiet", action]];
}

+ (NSArray *)xcodebuildArgumentsForProject:(NSDictionary *)projectDict
                                    action:(NSString *)action
{
  NSString *path = [projectDict objectForKey:PCXcodeProjectMarker];

  if (path == nil || [self xcodebuildPath] == nil)
  {
    return nil;
  }
  return [self xcodebuildArgumentsForProject:projectDict
                                      action:action
                                   selection:[self buildSelectionForProject:projectDict]
                                knownSchemes:[self _xcodebuildSchemesOfProjectAtPath:path]];
}

+ (BOOL)canRunProject:(NSDictionary *)projectDict
{
  NSDictionary *selection = [self buildSelectionForProject:projectDict];

  return [[selection objectForKey:@"Scheme"] objectForKey:@"RunTarget"] != nil
    && ![[[selection objectForKey:@"Destination"] objectForKey:@"BuildOnly"] boolValue];
}

+ (NSString *)launchArchitectureForProject:(NSDictionary *)projectDict
{
  NSString *architecture = [[[self buildSelectionForProject:projectDict]
                             objectForKey:@"Destination"] objectForKey:@"Architecture"];

  return [architecture isEqual:NativeArchitecture()] ? nil : architecture;
}

+ (NSString *)GNUstepBuildTool
{
  return [[NSBundle bundleForClass:self] pathForResource:@"pc-xcode-build" ofType:@"py"];
}

+ (NSArray *)GNUstepBuildArgumentsForProject:(NSDictionary *)projectDict action:(NSString *)action
{
  NSString *path = [projectDict objectForKey:PCXcodeProjectMarker];
  NSString *tool = [self GNUstepBuildTool];
  if (!path || !tool || ![self buildsWithGNUstepForProject:projectDict]
      || [projectDict objectForKey:@"XCODE_BuildScript"]) return nil;
  NSDictionary *selection = [self buildSelectionForProject:projectDict];
  NSDictionary *scheme = [selection objectForKey:@"Scheme"];
  NSMutableArray *targets = [NSMutableArray array];
  NSString *runTarget = [scheme objectForKey:@"RunTarget"];
  if (runTarget) [targets addObject:runTarget];
  for (NSString *target in [scheme objectForKey:@"Targets"])
    if (![targets containsObject:target]) [targets addObject:target];
  NSMutableArray *arguments = [NSMutableArray arrayWithObjects:@"python3", tool,
    @"--project", path, @"--configuration", [selection objectForKey:@"Configuration"] ?: @"Debug", nil];
  for (NSString *target in targets) [arguments addObjectsFromArray:@[@"--target", target]];
  NSString *theme = [projectDict objectForKey:@"XCODE_Theme"];
  if (theme.length) [arguments addObjectsFromArray:@[@"--theme", theme]];
  if ([action isEqual:@"describe"]) [arguments addObject:@"--describe"];
  else [arguments addObjectsFromArray:@[@"--action", action]];
  return arguments;
}

+ (NSString *)builtExecutableForProject:(NSDictionary *)projectDict
{
  static NSMutableDictionary *executables = nil;
  NSString     *path = [projectDict objectForKey:PCXcodeProjectMarker];
  NSDictionary *selection;
  NSString     *target;
  NSArray      *arguments;
  NSString     *key;
  NSString     *executable;

  if (path && [self buildsWithGNUstepForProject:projectDict]
      && ![projectDict objectForKey:@"XCODE_BuildScript"])
  {
    if (![[[self buildSelectionForProject:projectDict] objectForKey:@"Scheme"] objectForKey:@"RunTarget"]) return nil;
    NSArray *arguments = [self GNUstepBuildArgumentsForProject:projectDict action:@"describe"];
    return arguments ? [JSONFromTool(@"/usr/bin/env", arguments) objectForKey:@"executable"] : nil;
  }
  if (path == nil || [self xcodebuildPath] == nil)
  {
    return nil;
  }
  selection = [self buildSelectionForProject:projectDict];
  target = [[selection objectForKey:@"Scheme"] objectForKey:@"RunTarget"];
  if (target == nil)
  {
    return nil;
  }
  arguments = [self _xcodebuildSelectionForProject:projectDict
                                         selection:selection
                                      knownSchemes:[self _xcodebuildSchemesOfProjectAtPath:path]];
  key = [[arguments componentsJoinedByString:@"\n"] stringByAppendingFormat:@"\n%@",
         ProjectSignature(path)];
  if (executables == nil)
  {
    executables = [NSMutableDictionary new];
  }
  executable = [executables objectForKey:key];
  if (executable != nil)
  {
    return executable;
  }
  for (NSDictionary *entry in JSONFromTool([self xcodebuildPath],
                                           [arguments arrayByAddingObjectsFromArray:
                                            @[@"-showBuildSettings", @"-json"]]))
  {
    NSDictionary *settings = [entry objectForKey:@"buildSettings"];
    NSString     *directory = [settings objectForKey:@"TARGET_BUILD_DIR"];
    NSString     *relative = [settings objectForKey:@"EXECUTABLE_PATH"];

    if ([[entry objectForKey:@"target"] isEqual:target] && directory && relative)
    {
      executable = [directory stringByAppendingPathComponent:relative];
      [executables setObject:executable forKey:key];
      break;
    }
  }
  return executable;
}

// --- GNUstep on macOS

static BOOL IsGNUstepMakefiles(NSString *path)
{
  return [path length] && [[NSFileManager defaultManager] fileExistsAtPath:
                           [path stringByAppendingPathComponent:@"GNUstep.sh"]];
}

+ (NSString *)GNUstepMakefilesWithEnvironment:(NSDictionary *)environment
                                  toolFolders:(NSArray *)toolFolders
                              makefileFolders:(NSArray *)makefileFolders
{
  NSMutableArray *folders = [NSMutableArray array];
  NSString       *path = [environment objectForKey:@"GNUSTEP_MAKEFILES"];

  if (IsGNUstepMakefiles(path)) return path;
  [folders addObjectsFromArray:[[environment objectForKey:@"PATH"] componentsSeparatedByString:@":"]];
  [folders addObjectsFromArray:toolFolders];
  for (NSString *folder in folders)
  {
    NSString *config = [folder stringByAppendingPathComponent:@"gnustep-config"];
    NSData   *output;

    if (![folder length] || ![[NSFileManager defaultManager] isExecutableFileAtPath:config]) continue;
    output = RunTool(config, @[@"--variable=GNUSTEP_MAKEFILES"]);
    path = output ? [[[[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding] autorelease]
                     stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] : nil;
    if (IsGNUstepMakefiles(path)) return path;
  }
  for (path in makefileFolders)
  {
    if (IsGNUstepMakefiles(path)) return path;
  }
  return nil;
}

+ (NSString *)GNUstepMakefilesInFolder:(NSString *)path
{
  NSArray *relative = @[@"", @"share/GNUstep/Makefiles", @"System/Library/Makefiles",
                        @"Library/Makefiles", @"lib/GNUstep/Makefiles", @"GNUstep/System/Library/Makefiles"];

  path = [[path stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
          stringByExpandingTildeInPath];
  if (![path length]) return nil;
  if ([[path lastPathComponent] isEqual:@"GNUstep.sh"]) path = [path stringByDeletingLastPathComponent];
  for (NSString *folder in relative)
  {
    NSString *makefiles = [folder length] ? [path stringByAppendingPathComponent:folder] : path;

    if (IsGNUstepMakefiles(makefiles)) return [makefiles stringByStandardizingPath];
  }
  return nil;
}

+ (NSString *)chosenGNUstep
{
  NSString *chosen = [[NSUserDefaults standardUserDefaults] stringForKey:PCGNUstepDefault];

  chosen = [chosen stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  return [chosen length] ? chosen : nil;
}

+ (NSString *)foundGNUstepMakefiles
{
  static id makefiles = nil;

  if (makefiles == nil)
  {
    /* A GUI application has a short PATH, so the usual places are tried too:
     * GNUstep's own layout, Homebrew and MacPorts. */
    makefiles = [self GNUstepMakefilesWithEnvironment:[[NSProcessInfo processInfo] environment]
                                          toolFolders:@[@"/usr/GNUstep/System/Tools",
                                                        @"/usr/GNUstep/Local/Tools", @"/usr/local/bin",
                                                        @"/opt/homebrew/bin", @"/opt/local/bin"]
                                      makefileFolders:@[@"/usr/GNUstep/System/Library/Makefiles",
                                                        @"/usr/local/share/GNUstep/Makefiles",
                                                        @"/opt/homebrew/share/GNUstep/Makefiles",
                                                        @"/opt/local/GNUstep/System/Library/Makefiles",
                                                        @"/opt/local/share/GNUstep/Makefiles"]];
    makefiles = makefiles ? [makefiles retain] : [[NSNull null] retain];
  }
  return makefiles == [NSNull null] ? nil : makefiles;
}

+ (NSString *)GNUstepMakefiles
{
  NSString *chosen = [self chosenGNUstep];

  /* A chosen installation that has no GNUstep.sh is no GNUstep, rather than
   * quietly another one. */
  return chosen ? [self GNUstepMakefilesInFolder:chosen] : [self foundGNUstepMakefiles];
}

+ (NSDictionary *)GNUstepEnvironmentForMakefiles:(NSString *)makefiles
{
  NSData              *output;
  NSString            *text;
  NSMutableDictionary *environment = [NSMutableDictionary dictionary];
  NSString            *last = nil;

  if (!IsGNUstepMakefiles(makefiles)) return nil;
  /* The environment GNUstep.sh sets up, as a shell that sources it has. */
  output = RunTool(@"/bin/sh", @[@"-c", @". \"$1/GNUstep.sh\" >/dev/null 2>&1; exec /usr/bin/env",
                                 @"sh", makefiles]);
  text = output ? [[[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding] autorelease] : nil;
  for (NSString *line in [text componentsSeparatedByString:@"\n"])
  {
    NSRange equals = [line rangeOfString:@"="];
    NSString *name = equals.location == NSNotFound ? nil : [line substringToIndex:equals.location];

    if ([name length] && [name rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:
          @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_"] invertedSet]].location
        == NSNotFound)
    {
      [environment setObject:[line substringFromIndex:equals.location + 1] forKey:name];
      last = name;
    }
    else if (last && [line length])
    {
      /* A value with a line break. */
      [environment setObject:[NSString stringWithFormat:@"%@\n%@", [environment objectForKey:last], line]
                      forKey:last];
    }
  }
  return [environment objectForKey:@"GNUSTEP_MAKEFILES"] ? environment : nil;
}

+ (NSDictionary *)GNUstepEnvironment
{
  static id       environment = nil;
  static NSString *environmentMakefiles = nil;
  NSString        *makefiles = [self GNUstepMakefiles];

  /* Made again when another GNUstep is chosen. */
  if (environment == nil || !(makefiles == environmentMakefiles || [makefiles isEqual:environmentMakefiles]))
  {
    [environment release];
    [environmentMakefiles release];
    environmentMakefiles = [makefiles copy];
    environment = [self GNUstepEnvironmentForMakefiles:makefiles];
    environment = environment ? [environment retain] : [[NSNull null] retain];
  }
  return environment == [NSNull null] ? nil : environment;
}

+ (NSDictionary *)buildEnvironmentForProject:(NSDictionary *)projectDict
                            baseEnvironment:(NSDictionary *)environment
{
  NSMutableDictionary *result = [NSMutableDictionary dictionaryWithDictionary:environment];
  NSString *theme = [projectDict objectForKey:@"XCODE_Theme"];

  if ([theme length]) [result setObject:theme forKey:@"GNUSTEP_APPLICATION_THEME"];
  else [result removeObjectForKey:@"GNUSTEP_APPLICATION_THEME"];
  return result;
}

+ (NSDictionary *)buildEnvironmentForProject:(NSDictionary *)projectDict
{
  NSDictionary *environment = [self GNUstepEnvironment];

  return [self buildEnvironmentForProject:projectDict
                          baseEnvironment:environment ?: [[NSProcessInfo processInfo] environment]];
}

+ (BOOL)buildsWithGNUstepForProject:(NSDictionary *)projectDict
{
#ifdef GNUSTEP
  return YES;
#else
  if ([projectDict objectForKey:PCXcodeProjectMarker] == nil) return NO;
  return [[[[self buildSelectionForProject:projectDict] objectForKey:@"Destination"]
           objectForKey:@"GNUstep"] boolValue];
#endif
}

@end
