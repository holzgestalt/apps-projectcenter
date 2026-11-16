#import "PCXcodeProject.h"

static NSString * const PCXcodeProjectMarker = @"XCODE_PROJECT_PATH";

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
    [entry setObject:([settings isKindOfClass:[NSDictionary class]] ? settings : [NSDictionary dictionary]) forKey:@"Settings"];
    if (base) [entry setObject:base forKey:@"Base"];
    [result addObject:entry];
  }
  return result;
}

static NSDictionary *Phase(NSDictionary *objects, NSString *identifier)
{
  static NSDictionary *names = nil;
  NSDictionary *phase = [objects objectForKey:identifier];
  NSString *isa = [phase objectForKey:@"isa"];
  NSMutableArray *files = [NSMutableArray array];
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
  }
  if (![name isKindOfClass:[NSString class]] || ![name length])
    name = [names objectForKey:isa] ? [names objectForKey:isa] : isa;
  [entry setObject:name forKey:@"Name"];
  [entry setObject:([names objectForKey:isa] ? [names objectForKey:isa] : (isa ? isa : @"")) forKey:@"Kind"];
  [entry setObject:files forKey:@"Files"];
  if ([[phase objectForKey:@"shellScript"] isKindOfClass:[NSString class]])
    [entry setObject:[phase objectForKey:@"shellScript"] forKey:@"Script"];
  return entry;
}

@implementation PCXcodeProject
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
    for (NSString *key in @[@"TargetName", @"BuildScript", @"Executable"])
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
    if ([targets count] != 1)
      [NSException raise:@"XcodeImport" format:@"Expected one application target (found %lu). Select an application target with TargetName in GNUstep/ProjectCenter.plist.", (unsigned long)[targets count]];
    NSDictionary *target = [targets objectAtIndex:0];
    if (![[target objectForKey:@"name"] isKindOfClass:[NSString class]] || ![[target objectForKey:@"name"] length])
      [NSException raise:@"XcodeImport" format:@"The application target has no name."];
    NSMutableDictionary *paths = [NSMutableDictionary dictionary];
    NSDictionary *mainGroup = ReadGroup([project objectForKey:@"mainGroup"], root, root, objects, paths, [NSMutableSet set]);
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                   path, PCXcodeProjectMarker, @"Application", @"PROJECT_TYPE", [target objectForKey:@"name"], @"PROJECT_NAME", nil];
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
      NSDictionary *description = Phase(objects, phase);
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
@end
