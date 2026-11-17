/*
 GNUstep ProjectCenter - http://www.gnustep.org/experience/ProjectCenter.html

 Copyright (C) 2000-2026 Free Software Foundation

 Authors: Philippe C.D. Robert
 Serg Stoyan
 Riccardo Mottola

 This file is part of GNUstep.

 This application is free software; you can redistribute it and/or
 modify it under the terms of the GNU General Public
 License as published by the Free Software Foundation; either
 version 2 of the License, or (at your option) any later version.

 This application is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 Library General Public License for more details.

 You should have received a copy of the GNU General Public
 License along with this library; if not, write to the Free
 Software Foundation, Inc., 31 Milk Street #960789 Boston, MA 02196 USA.
 */

#import <ProjectCenter/PCDefines.h>
#import <ProjectCenter/PCFileManager.h>
#import <ProjectCenter/PCProjectManager.h>
#import <ProjectCenter/PCProject.h>
#import "../Headers/ProjectCenter/PCProjectBrowser.h"
#import <ProjectCenter/PCProjectEditor.h>
#import <ProjectCenter/PCProjectWindow.h>
#import <ProjectCenter/PCFileNameField.h>

#import <ProjectCenter/PCLogController.h>

#import "Modules/Preferences/Misc/PCMiscPrefs.h"
#import "PCFileTypeIcon.h"

NSString *PCBrowserDidSetPathNotification = @"PCBrowserDidSetPathNotification";

/* GNUstep's programmatic tables retain cell-based mode by default. Register
 * view prototypes explicitly, just as its XIB loader does. */
#ifdef GNUSTEP
@interface NSTableView (PCSourceViewSupport)
- (void)_registerPrototypeViews:(NSArray *)views;
@end
#endif

@interface PCSourceIconView : NSImageView
{
  NSString *symbolicIconName;
}
@end
@implementation PCSourceIconView
+ (void)initialize { if (self == [PCSourceIconView class]) [self exposeBinding:@"symbolicIconName"]; }
- (NSString *)symbolicIconName { return symbolicIconName; }
- (void)setSymbolicIconName:(NSString *)name { ASSIGNCOPY(symbolicIconName,name); }
- (NSString *)gtk4NativeIconName { return symbolicIconName; }
- (void)dealloc { [symbolicIconName release]; [super dealloc]; }
@end

@interface PCSourceOutlineView : NSOutlineView @end
@implementation PCSourceOutlineView
- (BOOL)gtk4NativeCompactRows { return YES; }
@end

/* Items have stable identities until the project file list changes. The
 * category paths remain compatible with editors, inspectors and breakpoints. */
@interface PCSourceItem : NSObject
{
  @public
  NSString *title;
  NSString *path;
  NSString *category;
  NSString *categoryPath;
  NSString *file;
  NSString *subprojectName;
  BOOL loadedSubproject;
  BOOL projectRoot;
  NSImage *icon;
  PCProject *owner;
  PCSourceItem *parent;
  NSMutableArray *children;
}
@end
@implementation PCSourceItem
- (id)init { if ((self = [super init])) children = [NSMutableArray new]; return self; }
- (NSString *)symbolicIconName
{
  if (projectRoot || subprojectName) return @"folder-documents-symbolic";
  if (!file && [[[title pathExtension] lowercaseString] isEqual:@"xib"]) return nil;
  if (!file) return @"folder-symbolic";
  if ([@[@"m",@"h",@"c",@"xib",@"plist"] containsObject:[[file pathExtension] lowercaseString]]) return nil;
  if ([@[@"png", @"jpg", @"jpeg", @"tiff", @"svg", @"pdf", @"xcassets"] containsObject:[[file pathExtension] lowercaseString]])
    return @"image-x-generic-symbolic";
  return @"text-x-generic-symbolic";
}
- (NSImage *)icon
{
  if (icon) return icon;
  NSImage *image = nil;
  if (projectRoot || subprojectName) image = [NSImage imageNamed:@"FileProject"];
  else if (!file && [[[title pathExtension] lowercaseString] isEqual:@"xib"])
    image = PCFileTypeIcon(@"xib");
  else if (file)
    image = PCFileTypeIcon([file pathExtension]) ?: [[NSWorkspace sharedWorkspace] iconForFile:
                                                     [owner pathForFile:file forKey:[owner keyForCategory:category]]];
  else image = [NSImage imageNamed:@"common_Folder"];
  icon = [image retain];
  return icon;
}
- (void)dealloc
{
  [title release]; [path release]; [category release];
  [categoryPath release]; [file release]; [subprojectName release]; [children release]; [icon release];
  [super dealloc];
}
@end

static NSTableCellView *SourceCell(void)
{
  NSTableCellView *cell = [[[NSTableCellView alloc] initWithFrame:NSMakeRect(0,0,230,20)] autorelease];
  [cell setIdentifier:@"SourceItem"];
  NSImageView *icon = [[[PCSourceIconView alloc] initWithFrame:NSMakeRect(2,2,16,16)] autorelease];
  [icon setImageAlignment:NSImageAlignCenter];
  [icon setImageScaling:NSImageScaleProportionallyUpOrDown];
  NSTextField *label = [[[NSTextField alloc] initWithFrame:NSMakeRect(22,0,206,20)] autorelease];
  [label setEditable:NO]; [label setSelectable:NO]; [label setBezeled:NO]; [label setBordered:NO]; [label setDrawsBackground:NO];
  [label setFont:[NSFont systemFontOfSize:12]];
  [[label cell] setLineBreakMode:NSLineBreakByTruncatingTail];
  [label setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [cell addSubview:icon]; [cell addSubview:label];
  [cell setImageView:icon]; [cell setTextField:label];
  [label bind:NSValueBinding toObject:cell withKeyPath:@"objectValue.title" options:nil];
  [icon bind:NSValueBinding toObject:cell withKeyPath:@"objectValue.icon" options:nil];
  [icon bind:@"symbolicIconName" toObject:cell withKeyPath:@"objectValue.symbolicIconName" options:nil];
  return cell;
}

@interface PCProjectBrowser (SourceOutline)
- (void)rebuildSourceTree;
- (void)addProject:(PCProject *)owner toItems:(NSMutableArray *)items parent:(PCSourceItem *)parent prefix:(NSString *)prefix ancestors:(NSSet *)ancestors;
- (void)outlineSelectionChanged:(NSNotification *)notification;
- (void)loadChildrenOfItem:(PCSourceItem *)item;
- (void)addXcodeNodes:(NSArray *)nodes toItem:(PCSourceItem *)parent owner:(PCProject *)owner
           categories:(NSDictionary *)categories prefix:(NSString *)prefix placed:(NSMutableSet *)placed;
@end

@implementation PCProjectBrowser

- (id)initWithProject:(PCProject *)aProject
{
  if ((self = [super init]))
  {
    project = aProject;
    sourceRoots = [NSMutableArray new];
    sourceItems = [NSMutableDictionary new];
    sourcePath = [@"/" copy];
    sourceScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,240,400)];
    [sourceScroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [sourceScroll setBorderType:NSNoBorder];
    [sourceScroll setHasVerticalScroller:YES];
    [sourceScroll setHasHorizontalScroller:NO];
    [sourceScroll setAutohidesScrollers:YES];
    outline = [[PCSourceOutlineView alloc] initWithFrame:[[sourceScroll contentView] bounds]];
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"Source"];
    [column setWidth:230];
    [column setMinWidth:80];
    [outline addTableColumn:column];
    [outline setOutlineTableColumn:column];
    [column release];
    [outline setHeaderView:nil];
    [outline setGridStyleMask:NSTableViewGridNone];
#ifdef GNUSTEP
    [outline _registerPrototypeViews:@[SourceCell()]];
#endif
    [outline setRowHeight:20];
    [outline setIndentationPerLevel:14];
    [outline setAllowsMultipleSelection:YES];
    [outline setAllowsEmptySelection:YES];
    [outline setColumnAutoresizingStyle:NSTableViewFirstColumnOnlyAutoresizingStyle];
    [outline setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [outline setDataSource:(id)self];
    [outline setDelegate:(id)self];
    [outline setTarget:self];
    [outline setDoubleAction:@selector(doubleClick:)];
    [sourceScroll setDocumentView:outline];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(projectDictDidChange:) name:PCProjectDictDidChangeNotification object:nil];
  }
  return self;
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [outline setDelegate:nil]; [outline setDataSource:nil];
  [sourceScroll release]; [outline release]; [sourceRoots release];
  [sourceItems release]; [sourcePath release];
  [super dealloc];
}

- (NSView *)view
{
  /* The owning project must have assigned this controller before loading
   * subprojects, which share their parent's browser/editor/window. */
  if (![sourceRoots count]) [self rebuildSourceTree];
  return sourceScroll;
}

- (PCSourceItem *)newItem:(NSString *)label path:(NSString *)path parent:(PCSourceItem *)parent
                    owner:(PCProject *)owner category:(NSString *)category categoryPath:(NSString *)categoryPath
{
  PCSourceItem *item = [[[PCSourceItem alloc] init] autorelease];
  item->title = [label copy]; item->path = [path copy]; item->parent = parent;
  item->owner = owner; item->category = [category copy]; item->categoryPath = [categoryPath copy];
  [sourceItems setObject:item forKey:path];
  return item;
}

- (void)addProject:(PCProject *)owner toItems:(NSMutableArray *)items parent:(PCSourceItem *)parent
            prefix:(NSString *)prefix ancestors:(NSSet *)ancestors
{
  if (!owner || [ancestors containsObject:[owner projectPath]]) return;
  /* An Xcode project keeps its own group hierarchy below one project row.
   * File rows keep their category paths, which editors and inspectors use. */
  NSArray *xcodeGroups = [[owner projectDict] objectForKey:@"XCODE_GROUPS"];
  NSMutableSet *placed = nil;
  if ([xcodeGroups isKindOfClass:[NSArray class]])
  {
    NSMutableDictionary *categories = [NSMutableDictionary dictionary];
    for (NSString *category in [owner rootCategories])
      for (NSString *file in [[owner projectDict] objectForKey:[owner keyForCategory:category]])
        if ([file isKindOfClass:[NSString class]] && ![categories objectForKey:file])
          [categories setObject:category forKey:file];
    NSString *rootPath = [prefix stringByAppendingPathComponent:[@"@" stringByAppendingString:[owner projectName]]];
    PCSourceItem *root = [self newItem:[owner projectName] path:rootPath parent:parent owner:owner category:nil categoryPath:nil];
    root->projectRoot = YES;
    [items addObject:root];
    placed = [NSMutableSet set];
    [self addXcodeNodes:xcodeGroups toItem:root owner:owner categories:categories prefix:prefix placed:placed];
    /* Files outside Xcode's groups (GNUstep build files, files opened from
     * elsewhere) follow in their ProjectCenter categories. */
    parent = root; items = root->children;
  }
  for (NSString *category in [owner rootCategories])
  {
    NSString *key = [owner keyForCategory:category];
    NSString *categoryPath = [prefix stringByAppendingPathComponent:category];
    if (placed)
    {
      BOOL remaining = NO;
      for (NSString *file in [[owner projectDict] objectForKey:key])
        if ([file isKindOfClass:[NSString class]] && [file length] && ![placed containsObject:file]) { remaining = YES; break; }
      if (!remaining) continue;
    }
    PCSourceItem *group = [self newItem:category path:categoryPath parent:parent owner:owner category:category categoryPath:categoryPath];
    [items addObject:group];
    NSArray *files = [[owner projectDict] objectForKey:key];
    for (NSString *file in [files sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)])
    {
      if (![file isKindOfClass:[NSString class]] || ![file length] || [placed containsObject:file]) continue;
      if ([key isEqual:PCSubprojects])
      {
        NSString *path = [categoryPath stringByAppendingPathComponent:file];
        PCSourceItem *node = [self newItem:file path:path parent:group owner:owner category:nil categoryPath:nil];
        node->subprojectName = [file copy];
        [group->children addObject:node];
        continue;
      }
      NSArray *components = [file isAbsolutePath] ? @[[file lastPathComponent]] : [file pathComponents];
      PCSourceItem *container = group;
      NSString *path = categoryPath;
      for (NSUInteger i = 0; i < [components count]; i++)
      {
        NSString *part = [components objectAtIndex:i];
        path = [path stringByAppendingPathComponent:part];
        /* Absolute references get a unique path but a readable leaf title. */
        if ([file isAbsolutePath]) path = [categoryPath stringByAppendingString:[@"/" stringByAppendingString:file]];
        PCSourceItem *node = [sourceItems objectForKey:path];
        if (!node)
        {
          node = [self newItem:part path:path parent:container owner:owner category:category categoryPath:categoryPath];
          [container->children addObject:node];
        }
        if (i + 1 == [components count] && !node->file) node->file = [file copy];
        container = node;
      }
    }
  }
}

- (void)addXcodeNodes:(NSArray *)nodes toItem:(PCSourceItem *)parent owner:(PCProject *)owner
           categories:(NSDictionary *)categories prefix:(NSString *)prefix placed:(NSMutableSet *)placed
{
  for (NSDictionary *node in nodes)
  {
    if (![node isKindOfClass:[NSDictionary class]]) continue;
    NSString *name = [node objectForKey:@"Name"];
    NSString *file = [node objectForKey:@"File"];
    if (![name isKindOfClass:[NSString class]]) continue;
    if (file)
    {
      NSString *category = [categories objectForKey:file];
      if (!category || [placed containsObject:file]) continue;
      NSString *categoryPath = [prefix stringByAppendingPathComponent:category];
      NSString *path = [file isAbsolutePath] ? [categoryPath stringByAppendingString:[@"/" stringByAppendingString:file]]
      : [categoryPath stringByAppendingPathComponent:file];
      PCSourceItem *item = [self newItem:name path:path parent:parent owner:owner category:category categoryPath:categoryPath];
      item->file = [file copy];
      [parent->children addObject:item];
      [placed addObject:file];
      continue;
    }
    /* Sibling groups may share a name; their navigator paths may not. */
    NSString *path = [parent->path stringByAppendingPathComponent:name];
    for (NSUInteger copy = 2; [sourceItems objectForKey:path]; copy++)
      path = [parent->path stringByAppendingPathComponent:[NSString stringWithFormat:@"%@ %lu", name, (unsigned long)copy]];
    PCSourceItem *group = [self newItem:name path:path parent:parent owner:owner category:nil categoryPath:nil];
    [self addXcodeNodes:[node objectForKey:@"Children"] toItem:group owner:owner categories:categories prefix:prefix placed:placed];
    if ([group->children count]) [parent->children addObject:group];
    else [sourceItems removeObjectForKey:path];
  }
}

- (void)loadChildrenOfItem:(PCSourceItem *)item
{
  if (!item || !item->subprojectName || item->loadedSubproject) return;
  item->loadedSubproject = YES;
  NSMutableSet *ancestors = [NSMutableSet set];
  for (PCSourceItem *parent = item->parent; parent; parent = parent->parent)
    [ancestors addObject:[parent->owner projectPath]];
  PCProject *child = [item->owner subprojectWithName:item->subprojectName];
  if (child)
  {
    item->owner = child;
    [self addProject:child toItems:item->children parent:item prefix:item->path ancestors:ancestors];
  }
}

- (void)rebuildSourceTree
{
  NSMutableArray *expanded = [NSMutableArray array];
  for (NSString *path in sourceItems)
    if ([outline isItemExpanded:[sourceItems objectForKey:path]]) [expanded addObject:path];
  NSString *selection = [[sourcePath copy] autorelease];
  updatingSelection = YES;
  [sourceRoots removeAllObjects]; [sourceItems removeAllObjects];
  [self addProject:project toItems:sourceRoots parent:nil prefix:@"/" ancestors:[NSSet set]];
  [outline reloadData];
  if (![expanded count])
  {
    for (PCSourceItem *item in sourceRoots)
      if ([item->category isEqual:@"Classes"] || [item->category isEqual:@"Headers"])
        [outline expandItem:item];
    else if (item->projectRoot)
    {
      /* Like a freshly opened Xcode project: the project and its
       * first group are open. */
      [outline expandItem:item];
      if ([item->children count] && !((PCSourceItem *)[item->children objectAtIndex:0])->file)
        [outline expandItem:[item->children objectAtIndex:0]];
    }
  }
  else
    for (NSString *path in [expanded sortedArrayUsingSelector:@selector(compare:)])
      if ([sourceItems objectForKey:path]) [outline expandItem:[sourceItems objectForKey:path]];
  updatingSelection = NO;
  if (![self setPath:selection]) [self setPath:@"/"];
}

- (PCSourceItem *)selectedItem
{
  if ([outline numberOfSelectedRows] != 1) return nil;
  return [outline itemAtRow:[outline selectedRow]];
}

- (PCSourceItem *)itemForCategoryPath:(NSString *)path
{
  if (![path length]) return nil;
  BOOL loaded;
  do
  {
    loaded = NO;
    for (PCSourceItem *candidate in [sourceItems allValues])
      if (candidate->subprojectName && !candidate->loadedSubproject &&
          [path hasPrefix:[candidate->path stringByAppendingString:@"/"]])
      { [self loadChildrenOfItem:candidate]; loaded = YES; }
  }
  while (loaded);
  PCSourceItem *item = [sourceItems objectForKey:path];
  if (item) return item;
  /* An editor may append a class/method symbol to its source-file path. */
  PCSourceItem *best = nil;
  for (NSString *candidate in sourceItems)
  {
    PCSourceItem *node = [sourceItems objectForKey:candidate];
    if (node->file && [path hasPrefix:[candidate stringByAppendingString:@"/"]] &&
        (!best || [candidate length] > [best->path length])) best = node;
  }
  return best;
}

- (NSString *)projectFileForCategoryPath:(NSString *)path
{
  PCSourceItem *item = [self itemForCategoryPath:path];
  return item ? item->file : nil;
}

- (NSString *)categoryPathForFilePath:(NSString *)filePath
{
  NSString *absolute = [filePath stringByStandardizingPath];
  for (PCSourceItem *item in [sourceItems allValues])
    if (item->file && [[[item->owner pathForFile:item->file forKey:[item->owner keyForCategory:item->category]] stringByStandardizingPath] isEqual:absolute])
      return item->path;
  return nil;
}

- (NSArray *)navigatorItemsForFilePath:(NSString *)filePath
{
  NSString *categoryPath = [self categoryPathForFilePath:filePath];
  PCSourceItem *item = categoryPath ? [sourceItems objectForKey:categoryPath] : nil;
  NSMutableArray *items = [NSMutableArray array];

  for (; item; item = item->parent)
  {
    NSImage *icon = [item icon];
    [items insertObject:[NSDictionary dictionaryWithObjectsAndKeys:
                         item->title, @"Title", item->path, @"Path", icon, @"Icon", nil] atIndex:0];
  }
  return [items count] ? items : nil;
}

- (NSString *)nameOfSelectedFile { PCSourceItem *item = [self selectedItem]; return item ? item->file : nil; }
- (NSString *)pathToSelectedFile { return [self nameOfSelectedFile] ? [self path] : nil; }
- (NSString *)nameOfSelectedCategory
{
  NSString *category = nil;
  PCProject *owner = nil;
  NSIndexSet *selection = [outline selectedRowIndexes];
  for (NSUInteger row = [selection firstIndex]; row != NSNotFound; row = [selection indexGreaterThanIndex:row])
  {
    PCSourceItem *item = [outline itemAtRow:row];
    if (!item->category || (category && (![category isEqual:item->category] || owner != item->owner))) return nil;
    category = item->category; owner = item->owner;
  }
  return category;
}
- (NSString *)pathToSelectedCategory
{
  if (![self nameOfSelectedCategory]) return nil;
  PCSourceItem *item = [outline itemAtRow:[[outline selectedRowIndexes] firstIndex]];
  return item->categoryPath;
}
- (NSString *)pathFromSelectedCategory
{
  PCSourceItem *item = [self selectedItem];
  if (!item || !item->category) return nil;
  return [[@"/" stringByAppendingString:item->category] stringByAppendingString:[[self path] substringFromIndex:[item->categoryPath length]]];
}
- (NSString *)nameOfSelectedRootCategory
{
  NSString *path = [self pathToSelectedCategory];
  NSArray *parts = [path pathComponents];
  return [parts count] > 1 ? [parts objectAtIndex:1] : nil;
}
- (NSArray *)selectedFiles
{
  if (![self nameOfSelectedCategory]) return nil;
  NSMutableArray *files = [NSMutableArray array];
  NSIndexSet *selection = [outline selectedRowIndexes];
  for (NSUInteger row = [selection firstIndex]; row != NSNotFound; row = [selection indexGreaterThanIndex:row])
  {
    PCSourceItem *item = [outline itemAtRow:row];
    if (!item->file) return nil;
    [files addObject:item->file];
  }
  return [files count] ? files : nil;
}
- (NSString *)path { return sourcePath; }
- (BOOL)setPath:(NSString *)path
{
  if (!path || ![path length]) path = @"/";
  PCSourceItem *item = [self itemForCategoryPath:path];
  if (!item && ![path isEqual:@"/"]) return NO;
  /* Opening an editor echoes its path back to the navigator. The user's
   * selection is already visible: do not rebuild or scroll that same row. */
  if ((item && item == [self selectedItem]) ||
      (!item && [outline numberOfSelectedRows] == 0 && [sourcePath isEqual:path]))
  {
    if (![sourcePath isEqual:path])
    {
      ASSIGN(sourcePath,path);
      [[NSNotificationCenter defaultCenter] postNotificationName:PCBrowserDidSetPathNotification object:self];
    }
    return YES;
  }
  updatingSelection = YES;
  NSMutableArray *parents = [NSMutableArray array];
  for (PCSourceItem *parent = item ? item->parent : nil; parent; parent = parent->parent) [parents insertObject:parent atIndex:0];
  for (PCSourceItem *parent in parents)
    if (![outline isItemExpanded:parent]) [outline expandItem:parent];
  if (item)
  {
    [self loadChildrenOfItem:item];
    NSInteger row = [outline rowForItem:item];
    if (row >= 0) { [outline selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO]; [outline scrollRowToVisible:row]; }
    [[project projectManager] setActiveProject:item->owner];
  }
  else { [outline deselectAll:nil]; [[project projectManager] setActiveProject:project]; }
  ASSIGN(sourcePath,path);
  updatingSelection = NO;
  [[NSNotificationCenter defaultCenter] postNotificationName:PCBrowserDidSetPathNotification object:self];
  return YES;
}
- (void)reloadLastColumnAndNotify:(BOOL)notify
{
  /* Files are leaves in the navigator; parsing a file does not rebuild it. */
  if (notify) [[NSNotificationCenter defaultCenter] postNotificationName:PCBrowserDidSetPathNotification object:self];
}
- (void)reloadLastColumnAndSelectFile:(NSString *)file
{
  PCSourceItem *selected = [self selectedItem];
  NSString *categoryPath = selected ? selected->categoryPath : nil;
  [self rebuildSourceTree];
  if (categoryPath) [self setPath:[categoryPath stringByAppendingPathComponent:file]];
}
- (void)projectDictDidChange:(NSNotification *)notification
{
  NSDictionary *info = [notification object];
  PCProject *changed = [info objectForKey:@"Project"];
  NSString *key = [info objectForKey:@"Attribute"];
  BOOL relevant = changed == project;
  for (PCSourceItem *item in [sourceItems allValues]) if (item->owner == changed) { relevant = YES; break; }
  if (relevant && [[changed rootKeys] containsObject:key]) [self rebuildSourceTree];
}
- (void)outlineSelectionChanged:(NSNotification *)notification
{
  if (updatingSelection) return;
  PCSourceItem *item = [outline selectedRow] >= 0 ? [outline itemAtRow:[outline selectedRow]] : nil;
  [self loadChildrenOfItem:item];
  ASSIGN(sourcePath,item ? item->path : @"/");
  [[project projectManager] setActiveProject:item ? item->owner : project];
  [self click:outline];
}
- (void)outlineViewSelectionDidChange:(NSNotification *)notification { [self outlineSelectionChanged:notification]; }
- (void)click:(id)sender
{
  PCSourceItem *item = [self selectedItem];
  if (item && item->file && ![item->category isEqual:@"Libraries"])
    [[item->owner projectEditor] openEditorForCategoryPath:sourcePath windowed:NO];
  else if (item && item->projectRoot)
    [[project projectWindow] showProjectOverview];
  [[NSNotificationCenter defaultCenter] postNotificationName:PCBrowserDidSetPathNotification object:self];
}
- (void)doubleClick:(id)sender
{
  NSInteger row = [outline clickedRow] >= 0 ? [outline clickedRow] : [outline selectedRow];
  PCSourceItem *item = row >= 0 ? [outline itemAtRow:row] : nil;
  if (!item) return;
  if (!item->file)
  {
    if ([outline isItemExpanded:item]) [outline collapseItem:item]; else [outline expandItem:item];
  }
  else
  {
    [self setPath:item->path];
    if (([item->category isEqual:@"Interfaces"] && ![[[item->file pathExtension] lowercaseString] isEqual:@"xib"])
        || [item->category isEqual:@"Images"])
      [[NSWorkspace sharedWorkspace] openFile:[item->owner pathForFile:item->file forKey:[item->owner keyForCategory:item->category]]];
    else [[item->owner projectEditor] openEditorForCategoryPath:item->path windowed:YES];
  }
}

- (NSInteger)outlineView:(NSOutlineView *)view numberOfChildrenOfItem:(id)item
{ [self loadChildrenOfItem:item]; return item ? [((PCSourceItem *)item)->children count] : [sourceRoots count]; }
- (id)outlineView:(NSOutlineView *)view child:(NSInteger)index ofItem:(id)item
{ return [(item ? ((PCSourceItem *)item)->children : sourceRoots) objectAtIndex:index]; }
- (BOOL)outlineView:(NSOutlineView *)view isItemExpandable:(id)item
{ return ((PCSourceItem *)item)->subprojectName != nil || [((PCSourceItem *)item)->children count] > 0; }
- (id)outlineView:(NSOutlineView *)view objectValueForTableColumn:(NSTableColumn *)column byItem:(id)item
{
#ifdef GNUSTEP
  return ((PCSourceItem *)item)->title;
#else
  /* Cocoa sets the cell view's objectValue from this; its bindings need
   * the item. */
  return item;
#endif
}
- (NSView *)outlineView:(NSOutlineView *)view viewForTableColumn:(NSTableColumn *)column item:(id)object
{
  PCSourceItem *item = object;
  /* Native list rows reuse their bound bridge by identifier. Build fresh
   * AppKit templates here rather than copying an NSImageView's plain NSCell. */
  NSTableCellView *cell = SourceCell();
  [cell setObjectValue:item];
  return cell;
}
@end

@implementation PCProjectBrowser (FileNameIconDelegate)

// If file was opened in editor:
// 1. Determine editor
// 2. Ask editor for icon
- (NSImage *)_editorIconImageForFile:(NSString *)fileName
{
  PCProjectEditor *projectEditor = [project projectEditor];
  id<CodeEditor>  editor = nil;
  NSString        *categoryName = [self nameOfSelectedCategory];
  NSString        *categoryKey = [project keyForCategory:categoryName];
  NSString        *filePath;

  filePath = [project pathForFile:fileName forKey:categoryKey];
  editor = [projectEditor editorForFile:filePath];
  if (editor != nil)
  {
    return [editor fileIcon];
  }

  return nil;
}

- (NSImage *)fileNameIconImage
{
  NSString  *categoryName = nil;
  NSString  *fileName = nil;
  NSString  *iconName = nil;
  NSImage   *icon = nil;
  PCProject *activeProject = [[project projectManager] activeProject];

  fileName = [self nameOfSelectedFile];
  if (fileName)
  {
    if ((icon = [self _editorIconImageForFile:fileName]))
    {
      return icon;
    }
  }
  else
  {
    categoryName = [self nameOfSelectedCategory];
  }

  /*  PCLogError(self,@"{setFileIcon} file %@ category %@",
   fileName, categoryName);*/

  if ([[self selectedFiles] count] > 1)
  {
    iconName = [[NSString alloc] initWithString:@"MultiFiles"];
  }
  // Nothing or subproject name selected
  else if ((!categoryName && !fileName) ||
           [fileName isEqualToString:[activeProject projectName]])
  {
    iconName = [[NSString alloc] initWithString:@"FileProject"];
  }
  else if ([categoryName isEqualToString: @"Classes"])
  {
    iconName = [[NSString alloc] initWithString:@"classSuitcase"];
  }
  else if ([categoryName isEqualToString: @"Headers"])
  {
    iconName = [[NSString alloc] initWithString:@"headerSuitcase"];
  }
  else if ([categoryName isEqualToString: @"Other Sources"])
  {
    iconName = [[NSString alloc] initWithString:@"genericSuitcase"];
  }
  else if ([categoryName isEqualToString: @"Interfaces"])
  {
    iconName = [[NSString alloc] initWithString:@"nibSuitcase"];
  }
  else if ([categoryName isEqualToString: @"Images"])
  {
    iconName = [[NSString alloc] initWithString:@"iconSuitcase"];
  }
  else if ([categoryName isEqualToString: @"Other Resources"])
  {
    iconName = [[NSString alloc] initWithString:@"otherSuitcase"];
  }
  else if ([categoryName isEqualToString: @"Subprojects"])
  {
    iconName = [[NSString alloc] initWithString:@"subprojectSuitcase"];
  }
  else if ([categoryName isEqualToString: @"Documentation"])
  {
    iconName = [[NSString alloc] initWithString:@"helpSuitcase"];
  }
  else if ([categoryName isEqualToString: @"Supporting Files"])
  {
    iconName = [[NSString alloc] initWithString:@"genericSuitcase"];
  }
  else if ([categoryName isEqualToString: @"Libraries"])
  {
    iconName = [[NSString alloc] initWithString:@"librarySuitcase"];
  }
  else if ([categoryName isEqualToString: @"Non Project Files"])
  {
    iconName = [[NSString alloc] initWithString:@"projectSuitcase"];
  }

  if (iconName != nil)
  {
    icon = IMAGE(iconName);
    RELEASE(iconName);
  }
  else
  {
    icon = [[NSWorkspace sharedWorkspace] iconForFile:fileName];
  }

  return icon;
}

- (NSString *)fileNameIconTitle
{
  NSString *categoryName = [self nameOfSelectedCategory];
  NSString *fileName = [self nameOfSelectedFile];
  int      filesCount = [[self selectedFiles] count];

  if (filesCount > 1)
  {
    return [NSString stringWithFormat:@"%i files", filesCount];
  }
  else if (fileName)
  {
    return fileName;
  }
  else if (categoryName)
  {
    return categoryName;
  }

  return PCFileNameFieldNoFiles;
}

- (NSString *)fileNameIconPath
{
  PCSourceItem *item = [self selectedItem];
  return item && item->file ? [item->owner pathForFile:item->file forKey:[item->owner keyForCategory:item->category]] : nil;
}

- (BOOL)canPerformDraggingOf:(NSArray *)paths
{
  NSString     *category = [self nameOfSelectedCategory];
  NSString     *categoryKey = [project keyForCategory:category];
  NSArray      *fileTypes = [project fileTypesForCategoryKey:categoryKey];
  NSEnumerator *e = [paths objectEnumerator];
  NSString     *s;

  NSLog(@"PCBrowser: canPerformDraggingOf -> %@", category);

  if (!category || ([self nameOfSelectedFile] != nil))
  {
    return NO;
  }

  if (![project isEditableCategory:category])
  {
    return NO;
  }

  // Check if we can accept files of such types
  while ((s = [e nextObject]))
  {
    if (![fileTypes containsObject:[s pathExtension]])
    {
      return NO;
    }
  }

  return YES;
}

- (BOOL)prepareForDraggingOf:(NSArray *)paths
{
  return YES;
}

- (BOOL)performDraggingOf:(NSArray *)paths
{
  NSString     *category = [self nameOfSelectedCategory];
  NSString     *categoryKey = [project keyForCategory:category];
  NSEnumerator *pathsEnum = [paths objectEnumerator];
  NSString     *file = nil;

  while ((file = [[pathsEnum nextObject] lastPathComponent]))
  {
    if (![project doesAcceptFile:file forKey:categoryKey])
    {
      return NO;
    }
  }

  return [project addAndCopyFiles:paths forKey:categoryKey];
}

@end
