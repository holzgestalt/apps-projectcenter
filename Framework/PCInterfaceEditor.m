/*
 * Embedded visual editing of modern Cocoa XIB XML. Keep the XML graph intact:
 * editing a property must not instantiate application classes or connections.
 * Distributed under the GNU General Public License, version 2 or later.
 */
#import "PCInterfaceEditor.h"
#import <ProjectCenter/PCEditorManager.h>
#include <math.h>

static NSString *Attribute(NSXMLElement *element, NSString *name)
{ return [[element attributeForName:name] stringValue]; }

static void SetAttribute(NSXMLElement *element, NSString *name, NSString *value)
{
  NSXMLNode *attribute = [element attributeForName:name];
  if (attribute) [attribute setStringValue:value];
  else [element addAttribute:[NSXMLNode attributeWithName:name stringValue:value]];
}

static NSXMLElement *FrameElement(NSXMLElement *element)
{
  for (NSXMLNode *child in [element children])
    if ([child kind] == NSXMLElementKind && [[child name] isEqual:@"rect"]
        && [Attribute((id)child,@"key") isEqual:@"frame"]) return (id)child;
  return nil;
}

static NSRect ObjectFrame(NSXMLElement *element)
{
  NSXMLElement *frame = FrameElement(element);
  return NSMakeRect([Attribute(frame,@"x") doubleValue], [Attribute(frame,@"y") doubleValue],
                    [Attribute(frame,@"width") doubleValue], [Attribute(frame,@"height") doubleValue]);
}

static NSXMLElement *TitleElement(NSXMLElement *element)
{
  if ([element attributeForName:@"title"]) return element;
  for (NSXMLNode *child in [element children])
    if ([child kind] == NSXMLElementKind && [[child name] hasSuffix:@"Cell"]
        && [(NSXMLElement *)child attributeForName:@"title"]) return (id)child;
  return element;
}

static NSString *ObjectTitle(NSXMLElement *element)
{
  return Attribute(TitleElement(element),@"title") ?: Attribute(element,@"userLabel")
  ?: Attribute(element,@"customClass") ?: [element name];
}

/* Represent interface objects, skipping XML containers such as <subviews>.
 * Stable items let NSOutlineView preserve expansion across property edits. */
@interface PCInterfaceItem : NSObject
{
  @public
  NSXMLElement *element;
  NSString *filePath;
  PCInterfaceItem *parent;
  NSMutableArray *children;
}
- (PCInterfaceItem *)itemForObject:(NSXMLElement *)object;
@end
@implementation PCInterfaceItem
- (id)init { if ((self = [super init])) children = [NSMutableArray new]; return self; }
- (void)dealloc { [element release]; [filePath release]; [children release]; [super dealloc]; }
- (NSString *)title
{
  return element ? [NSString stringWithFormat:@"%@ (%@)",ObjectTitle(element),[element name]] : [filePath lastPathComponent];
}
- (NSString *)symbolicIconName
{
  if (!element) return @"text-x-generic-symbolic";
  if ([[element name] isEqual:@"window"]) return @"window-new-symbolic";
  if ([[element name] isEqual:@"menu"] || [[element name] isEqual:@"menuItem"]) return @"open-menu-symbolic";
  return [children count] ? @"folder-symbolic" : @"application-x-addon-symbolic";
}
- (NSImage *)icon
{
  if (!element) return [[NSWorkspace sharedWorkspace] iconForFile:filePath];
  return [children count] ? [NSImage imageNamed:@"common_Folder"]
  : [[NSWorkspace sharedWorkspace] iconForFileType:@"h"];
}
- (PCInterfaceItem *)itemForObject:(NSXMLElement *)object
{
  if (object == element) return self;
  for (PCInterfaceItem *child in children)
  { PCInterfaceItem *found = [child itemForObject:object]; if (found) return found; }
  return nil;
}
@end

/* GNUstep can emit selection notifications while reindexing expanded rows.
 * Keep the selected object stable until the complete row update has finished. */
@interface PCInterfaceOutlineView : NSOutlineView
{
  NSUInteger rowUpdateDepth;
}
- (BOOL)isUpdatingRows;
@end
@implementation PCInterfaceOutlineView
- (BOOL)isUpdatingRows { return rowUpdateDepth > 0; }
- (BOOL)gtk4NativeCompactRows { return YES; }
- (void)restoreSelection:(PCInterfaceItem *)item
{
  PCInterfaceItem *visible = item;
  while (visible && [self rowForItem:visible] < 0) visible = visible->parent;
  if (visible) [self selectRowIndexes:[NSIndexSet indexSetWithIndex:[self rowForItem:visible]] byExtendingSelection:NO];
}
- (void)expandItem:(id)item expandChildren:(BOOL)children
{
  PCInterfaceItem *selected = [[self itemAtRow:[self selectedRow]] retain];
  rowUpdateDepth++;
  [super expandItem:item expandChildren:children];
  [self restoreSelection:selected]; rowUpdateDepth--;
  [selected release];
}
- (void)collapseItem:(id)item collapseChildren:(BOOL)children
{
  PCInterfaceItem *selected = [[self itemAtRow:[self selectedRow]] retain];
  rowUpdateDepth++;
  [super collapseItem:item collapseChildren:children];
  [self restoreSelection:selected]; rowUpdateDepth--;
  if (!rowUpdateDepth && [self itemAtRow:[self selectedRow]] != selected)
    [[self delegate] outlineViewSelectionDidChange:nil];
  [selected release];
}
@end

/* Register view rows so the active theme can supply its native outline. */
@interface NSTableView (PCInterfaceViewSupport)
- (void)_registerPrototypeViews:(NSArray *)views;
@end
@interface PCInterfaceIconView : NSImageView
{
  NSString *symbolicIconName;
}
@end
@implementation PCInterfaceIconView
+ (void)initialize { if (self == [PCInterfaceIconView class]) [self exposeBinding:@"symbolicIconName"]; }
- (NSString *)symbolicIconName { return symbolicIconName; }
- (void)setSymbolicIconName:(NSString *)name { ASSIGNCOPY(symbolicIconName,name); }
- (NSString *)gtk4NativeIconName { return symbolicIconName; }
- (void)dealloc { [symbolicIconName release]; [super dealloc]; }
@end

static NSTableCellView *InterfaceObjectCell(void)
{
  NSTableCellView *cell = [[[NSTableCellView alloc] initWithFrame:NSMakeRect(0,0,230,20)] autorelease];
  [cell setIdentifier:@"InterfaceObject"];
  NSImageView *icon = [[[PCInterfaceIconView alloc] initWithFrame:NSMakeRect(2,3,14,14)] autorelease];
  [icon setImageAlignment:NSImageAlignCenter]; [icon setImageScaling:NSImageScaleProportionallyUpOrDown];
  NSTextField *label = [[[NSTextField alloc] initWithFrame:NSMakeRect(22,0,206,20)] autorelease];
  [label setEditable:NO]; [label setSelectable:NO]; [label setBezeled:NO]; [label setDrawsBackground:NO];
  [label setFont:[NSFont systemFontOfSize:12]];
  [[label cell] setLineBreakMode:NSLineBreakByTruncatingTail];
  [label setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable];
  [cell addSubview:icon]; [cell addSubview:label]; [cell setImageView:icon]; [cell setTextField:label];
  [label bind:NSValueBinding toObject:cell withKeyPath:@"objectValue.title" options:nil];
  [icon bind:NSValueBinding toObject:cell withKeyPath:@"objectValue.icon" options:nil];
  [icon bind:@"symbolicIconName" toObject:cell withKeyPath:@"objectValue.symbolicIconName" options:nil];
  return cell;
}

@interface PCInterfaceCanvas : NSView
{
  @public
  PCInterfaceEditor *editor;
  NSXMLElement *root, *selection;
  NSMutableArray *elements, *rects;
}
- (void)showObject:(NSXMLElement *)object;
@end

@implementation PCInterfaceCanvas
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)becomeFirstResponder { [editor show]; return YES; }
- (void)setFrameSize:(NSSize)size { [super setFrameSize:size]; [self setNeedsDisplay:YES]; }
- (id)initWithFrame:(NSRect)frame
{
  if ((self = [super initWithFrame:frame]))
  { elements = [NSMutableArray new]; rects = [NSMutableArray new]; }
  return self;
}
- (void)dealloc { [elements release]; [rects release]; [super dealloc]; }
- (void)showObject:(NSXMLElement *)object
{
  selection = object;
  root = object;
  /* Show the enclosing window/view, keeping child coordinates relative to it. */
  for (NSXMLNode *node = object; node && ![[node name] isEqual:@"objects"]; node = [node parent])
    if ([node kind] == NSXMLElementKind && FrameElement((id)node)) root = (id)node;
  if ([[root name] isEqual:@"window"])
    for (NSXMLNode *child in [root children])
      if ([child kind] == NSXMLElementKind && [Attribute((id)child,@"key") isEqual:@"contentView"])
      { root = (id)child; break; }
  if ([[object name] isEqual:@"menuItem"])
  {
    root = (id)[object parent];
    if ([[root name] isEqual:@"items"]) root = (id)[root parent];
    for (NSXMLNode *child in [object children])
      if ([[child name] isEqual:@"menu"]) { root = (id)child; break; }
  }
  NSSize size = ObjectFrame(root).size;
  if ([[root name] isEqual:@"menu"])
  {
    NSArray *containers = [root elementsForName:@"items"];
    if ([containers count]) size.height = [[[containers objectAtIndex:0] elementsForName:@"menuItem"] count]*26+60;
  }
  NSSize viewport = [[self enclosingScrollView] contentSize];
  [self setFrameSize:NSMakeSize(MAX(viewport.width,MAX(640,size.width+80)),MAX(viewport.height,MAX(480,size.height+80)))];
  [self setNeedsDisplay:YES];
}
- (void)drawObject:(NSXMLElement *)object atOrigin:(NSPoint)origin isRoot:(BOOL)isRoot
{
  NSRect rect = ObjectFrame(object);
  BOOL framed = FrameElement(object) != nil;
  if (framed)
  {
    rect.origin = isRoot ? origin : NSMakePoint(origin.x+rect.origin.x,origin.y+rect.origin.y);
    rect.size.width = MAX(1,rect.size.width); rect.size.height = MAX(1,rect.size.height);
    [elements addObject:object]; [rects addObject:[NSValue valueWithRect:rect]];
    [(isRoot ? [NSColor windowBackgroundColor] : [NSColor controlBackgroundColor]) set];
    NSRectFill(rect);
    [[NSColor grayColor] set]; NSFrameRect(rect);
    NSString *title = ObjectTitle(object);
    if ([[object name] isEqual:@"button"])
    {
      NSButtonCell *cell = [[[NSButtonCell alloc] initTextCell:title] autorelease];
      [cell setBezelStyle:NSRoundedBezelStyle];
      [cell drawWithFrame:rect inView:self];
    }
    else if ([[object name] isEqual:@"textField"])
    {
      NSTextFieldCell *cell = [[[NSTextFieldCell alloc] initTextCell:title] autorelease];
      [cell setBezeled:YES]; [cell drawWithFrame:rect inView:self];
    }
    else if (!isRoot && rect.size.height >= 12)
      [title drawInRect:NSInsetRect(rect,4,2) withAttributes:
       [NSDictionary dictionaryWithObjectsAndKeys:[NSFont systemFontOfSize:11],NSFontAttributeName,
        [NSColor controlTextColor],NSForegroundColorAttributeName,nil]];
    origin = rect.origin;
  }
  for (NSXMLNode *child in [object children])
    if ([child kind] == NSXMLElementKind)
      [self drawObject:(id)child atOrigin:origin isRoot:NO];
}
- (void)drawRect:(NSRect)dirty
{
  [[NSColor lightGrayColor] set]; NSRectFill(dirty);
  [elements removeAllObjects]; [rects removeAllObjects];
  if (root && FrameElement(root))
  {
    [self drawObject:root atOrigin:NSMakePoint(40,40) isRoot:YES];
    for (NSUInteger i=0; i<[elements count]; i++)
      if ([elements objectAtIndex:i] == selection)
      { [[NSColor selectedControlColor] set]; NSFrameRectWithWidth([[rects objectAtIndex:i] rectValue],3); }
  }
  else if ([[root name] isEqual:@"menu"])
  {
    NSArray *items = [[root elementsForName:@"items"] count] ?
    [[[root elementsForName:@"items"] objectAtIndex:0] elementsForName:@"menuItem"] : [NSArray array];
    CGFloat y = [self bounds].size.height-60;
    [ObjectTitle(root) drawAtPoint:NSMakePoint(40,y) withAttributes:
     [NSDictionary dictionaryWithObject:[NSFont boldSystemFontOfSize:14] forKey:NSFontAttributeName]];
    for (NSXMLElement *item in items)
    {
      y -= 26; NSRect row = NSMakeRect(40,y,300,26);
      [(item == selection ? [NSColor selectedControlColor] : [NSColor controlBackgroundColor]) set]; NSRectFill(row);
      [elements addObject:item]; [rects addObject:[NSValue valueWithRect:row]];
      if ([Attribute(item,@"isSeparatorItem") isEqual:@"YES"])
      { [[NSColor grayColor] set]; NSRectFill(NSMakeRect(48,y+12,284,1)); }
      else [ObjectTitle(item) drawInRect:NSInsetRect(row,8,4) withAttributes:nil];
    }
  }
  else
  {
    NSString *label = root ? ObjectTitle(root) : @"Select an object to inspect its interface.";
    [label drawAtPoint:NSMakePoint(40,80) withAttributes:
     [NSDictionary dictionaryWithObject:[NSFont systemFontOfSize:16] forKey:NSFontAttributeName]];
    [@"Select a window or view in the object list to see its layout." drawAtPoint:NSMakePoint(40,50)
                                                                   withAttributes:nil];
  }
}
- (void)mouseDown:(NSEvent *)event
{
  NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
  for (NSInteger i=[elements count]-1; i>=0; i--)
    if (NSPointInRect(point,[[rects objectAtIndex:i] rectValue]))
    { [editor selectObject:[elements objectAtIndex:i]]; break; }
}
@end

@implementation PCInterfaceEditor
- (void)dealloc
{
  [_path release]; [_categoryPath release]; [_document release]; [_objects release];
  [_tree setDelegate:nil]; [_tree setDataSource:nil]; [_rootItem release];
  [_window setDelegate:nil]; [_window close]; [_window release];
  [_component release]; [super dealloc];
}
- (void)collectObjects:(NSXMLElement *)element
{
  /* IDs identify document objects; rects, constraints and connections are metadata. */
  NSString *name = [element name];
  if ([element attributeForName:@"id"] && ![@[@"action",@"outlet",@"binding",@"constraint"] containsObject:name])
    [_objects addObject:element];
  for (NSXMLNode *child in [element children])
    if ([child kind] == NSXMLElementKind) [self collectObjects:(id)child];
}
- (BOOL)loadDocument
{
  NSError *error = nil;
  NSData *data = [NSData dataWithContentsOfFile:_path];
  NSXMLDocument *document = [[NSXMLDocument alloc] initWithData:data options:NSXMLNodePreserveAll error:&error];
  if (!document || ![[[document rootElement] name] isEqual:@"document"]
      || ![Attribute([document rootElement],@"type") isEqual:@"com.apple.InterfaceBuilder3.Cocoa.XIB"])
  {
    [document release];
    NSRunAlertPanel(@"Interface Editor",@"Cannot open %@ as a modern Cocoa XIB. %@",@"OK",nil,nil,
                    [_path lastPathComponent],error ? [error localizedDescription] : @"This XIB format is not supported.");
    return NO;
  }
  [_document release]; _document = document;
  [_objects removeAllObjects]; [self collectObjects:[document rootElement]];
  [_rootItem release]; _rootItem = [PCInterfaceItem new];
  _rootItem->filePath = [_path copy];
  [self addObjectsFromElement:[document rootElement] toItem:_rootItem];
  _selected = nil;
  return YES;
}
- (void)addObjectsFromElement:(NSXMLElement *)element toItem:(PCInterfaceItem *)parent
{
  for (NSXMLNode *child in [element children])
    if ([child kind] == NSXMLElementKind)
    {
      PCInterfaceItem *container = parent;
      if ([_objects indexOfObjectIdenticalTo:child] != NSNotFound)
      {
        container = [[[PCInterfaceItem alloc] init] autorelease];
        container->element = [(NSXMLElement *)child retain]; container->parent = parent;
        [parent->children addObject:container];
      }
      [self addObjectsFromElement:(id)child toItem:container];
    }
}
- (id)openFileAtPath:(NSString *)path editorManager:(id)manager editable:(BOOL)editable
{
  _manager = manager; _editable = editable; [self setPath:path];
  _objects = [NSMutableArray new];
  if (![self loadDocument]) return nil;
  _component = [[NSView alloc] initWithFrame:NSMakeRect(0,0,900,600)];
  [_component setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable];
  NSSplitView *split = [[[NSSplitView alloc] initWithFrame:NSMakeRect(0,100,900,500)] autorelease];
  [split setVertical:YES]; [split setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable];
  NSScrollView *treeScroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,230,500)] autorelease];
  [treeScroll setHasVerticalScroller:YES];
  _tree = [[[PCInterfaceOutlineView alloc] initWithFrame:[treeScroll bounds]] autorelease];
  NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:@"Object"] autorelease];
  [[column headerCell] setStringValue:@"Interface Objects"]; [column setWidth:225];
  [_tree addTableColumn:column]; [_tree setOutlineTableColumn:column];
  [_tree setHeaderView:nil];
  [_tree _registerPrototypeViews:@[InterfaceObjectCell()]];
  [_tree setIndentationPerLevel:14];
  [_tree setColumnAutoresizingStyle:NSTableViewFirstColumnOnlyAutoresizingStyle];
  [_tree setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable];
  [_tree setDataSource:(id)self]; [_tree setDelegate:(id)self];
  [_tree setGridStyleMask:NSTableViewGridNone]; [_tree setRowHeight:20];
  [_tree setAllowsEmptySelection:NO]; [treeScroll setDocumentView:_tree]; [split addSubview:treeScroll];
  NSScrollView *canvasScroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(235,0,665,500)] autorelease];
  [canvasScroll setHasHorizontalScroller:YES]; [canvasScroll setHasVerticalScroller:YES];
  PCInterfaceCanvas *canvas = [[[PCInterfaceCanvas alloc] initWithFrame:NSMakeRect(0,0,640,480)] autorelease];
  [canvas setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable];
  canvas->editor = self; _canvas = canvas;
  [canvasScroll setDocumentView:canvas]; [split addSubview:canvasScroll]; [_component addSubview:split];
  NSArray *names = @[@"Title",@"X",@"Y",@"Width",@"Height"];
  CGFloat x = 8;
  for (NSUInteger i=0; i<5; i++)
  {
    CGFloat width = i == 0 ? 160 : 60;
    NSTextField *label = [[[NSTextField alloc] initWithFrame:NSMakeRect(x,73,width,20)] autorelease];
    [label setStringValue:[names objectAtIndex:i]]; [label setEditable:NO]; [label setBezeled:NO]; [label setDrawsBackground:NO];
    [_component addSubview:label];
    _fields[i] = [[[NSTextField alloc] initWithFrame:NSMakeRect(x,45,width,25)] autorelease];
    [_fields[i] setTarget:self]; [_fields[i] setAction:@selector(applyProperties:)];
    [_component addSubview:_fields[i]]; x += width+8;
  }
  NSButton *apply = [[[NSButton alloc] initWithFrame:NSMakeRect(x,45,80,26)] autorelease];
  [apply setTitle:@"Apply"]; [apply setTarget:self]; [apply setAction:@selector(applyProperties:)];
  [apply setEnabled:editable]; [_component addSubview:apply];
  _status = [[[NSTextField alloc] initWithFrame:NSMakeRect(8,8,880,25)] autorelease];
  [_status setEditable:NO]; [_status setBezeled:NO]; [_status setDrawsBackground:NO];
  [_status setAutoresizingMask:NSViewWidthSizable]; [_component addSubview:_status];
  [_tree reloadData];
  NSXMLElement *initial = [_objects count] ? [_objects objectAtIndex:0] : nil;
  for (NSXMLElement *object in _objects)
    if ([[object name] isEqual:@"menu"] || FrameElement(object)) { initial = object; break; }
  for (NSXMLElement *object in _objects) if ([[object name] isEqual:@"window"]) { initial = object; break; }
  [self selectObject:initial];
  [[NSNotificationCenter defaultCenter] postNotificationName:PCEditorDidOpenNotification object:self];
  return self;
}
- (NSInteger)outlineView:(NSOutlineView *)view numberOfChildrenOfItem:(id)item
{ return item ? [((PCInterfaceItem *)item)->children count] : (_rootItem ? 1 : 0); }
- (id)outlineView:(NSOutlineView *)view child:(NSInteger)index ofItem:(id)item
{ return item ? [((PCInterfaceItem *)item)->children objectAtIndex:index] : _rootItem; }
- (BOOL)outlineView:(NSOutlineView *)view isItemExpandable:(id)item
{ return [((PCInterfaceItem *)item)->children count] > 0; }
- (id)outlineView:(NSOutlineView *)view objectValueForTableColumn:(NSTableColumn *)column byItem:(id)item
{ return [item title]; }
- (NSView *)outlineView:(NSOutlineView *)view viewForTableColumn:(NSTableColumn *)column item:(id)item
{
  NSTableCellView *cell = InterfaceObjectCell(); [cell setObjectValue:item]; return cell;
}
- (BOOL)outlineView:(NSOutlineView *)view shouldEditTableColumn:(NSTableColumn *)column item:(id)item { return NO; }
- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{
  if (_updatingSelection || [(PCInterfaceOutlineView *)_tree isUpdatingRows]) return;
  PCInterfaceItem *item = [_tree itemAtRow:[_tree selectedRow]];
  if (item) [self selectObject:item->element];
}
- (void)revealItem:(PCInterfaceItem *)item
{
  if (!item) return;
  [self revealItem:item->parent];
  if (![_tree isItemExpanded:item]) [_tree expandItem:item];
}
- (void)selectObject:(NSXMLElement *)object
{
  _updatingSelection = YES;
  _selected = object;
  PCInterfaceItem *item = [_rootItem itemForObject:object];
  if (item) [self revealItem:item->parent];
  NSInteger row = item ? [_tree rowForItem:item] : -1;
  if (row >= 0 && [_tree selectedRow] != row)
  { [_tree selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO]; [_tree scrollRowToVisible:row]; }
  NSXMLElement *frame = FrameElement(object);
  [_fields[0] setStringValue:Attribute(TitleElement(object),@"title") ?: @""];
  [_fields[0] setEnabled:_editable && [TitleElement(object) attributeForName:@"title"] != nil];
  NSArray *keys = @[@"x",@"y",@"width",@"height"];
  for (NSUInteger i=1; i<5; i++)
  { [_fields[i] setStringValue:Attribute(frame,[keys objectAtIndex:i-1]) ?: @"0"]; [_fields[i] setEnabled:_editable && frame != nil]; }
  [_status setStringValue:object ? [NSString stringWithFormat:@"%@ · %@ · Frame edits preserve existing Auto Layout constraints",[object name],Attribute(object,@"id") ?: @""] : @"No interface objects"];
  [(PCInterfaceCanvas *)_canvas showObject:object];
  _updatingSelection = NO;
}
- (void)applyProperties:(id)sender
{
  if (!_editable || !_selected) return;
  NSXMLElement *frame = FrameElement(_selected);
  double values[4];
  for (NSUInteger i=0; frame && i<4; i++)
  {
    NSScanner *scanner = [NSScanner scannerWithString:[_fields[i+1] stringValue]];
    if (![scanner scanDouble:&values[i]] || ![scanner isAtEnd] || !isfinite(values[i]) || (i>=2 && values[i]<0))
    { NSRunAlertPanel(@"Interface Editor",@"Enter valid frame numbers and nonnegative dimensions.",@"OK",nil,nil); return; }
  }
  BOOL changed = NO;
  if ([_fields[0] isEnabled] && ![Attribute(TitleElement(_selected),@"title") isEqual:[_fields[0] stringValue]])
  { SetAttribute(TitleElement(_selected),@"title",[_fields[0] stringValue]); changed = YES; }
  NSArray *keys = @[@"x",@"y",@"width",@"height"];
  for (NSUInteger i=0; frame && i<4; i++)
    if ([Attribute(frame,[keys objectAtIndex:i]) doubleValue] != values[i])
    { SetAttribute(frame,[keys objectAtIndex:i],[NSString stringWithFormat:@"%.15g",values[i]]); changed = YES; }
  if (changed)
  {
    [self setIsEdited:YES]; [_tree reloadData]; [self selectObject:_selected];
    [[NSNotificationCenter defaultCenter] postNotificationName:PCEditorDidChangeNotification object:self];
  }
}
- (NSView *)componentView { return _component; }
- (NSView *)editorView { return _canvas; }
- (NSWindow *)editorWindow { return [_component window]; }
- (id)editorManager { return _manager; }
- (NSString *)path { return _path; }
- (void)setPath:(NSString *)path { ASSIGN(_path,path); }
- (NSString *)categoryPath { return _categoryPath; }
- (void)setCategoryPath:(NSString *)path { ASSIGN(_categoryPath,path); }
- (BOOL)isEdited { return _edited; }
- (void)setIsEdited:(BOOL)edited { _edited = edited; }
- (NSImage *)fileIcon { return [[NSWorkspace sharedWorkspace] iconForFile:_path]; }
- (void)setParser:(id)parser {}
- (NSArray *)browserItemsForItem:(NSString *)item { return nil; }
- (void)fileStructureItemSelected:(NSString *)item {}
- (void)scrollToLineNumber:(NSUInteger)line {}
/* Project documents stay embedded even on double-click. Standalone File Open
 * still needs its own ProjectCenter window when there is no project pane. */
- (void)setWindowed:(BOOL)windowed
{
  if ([_manager respondsToSelector:@selector(project)] || !windowed || _window) return;
  _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100,100,900,600)
                                        styleMask:NSTitledWindowMask|NSClosableWindowMask|NSResizableWindowMask|NSMiniaturizableWindowMask
                                          backing:NSBackingStoreBuffered defer:NO];
  [_window setReleasedWhenClosed:NO]; [_window setTitle:[_path lastPathComponent]];
  [_window setContentView:_component]; [_window setDelegate:(id)self];
}
- (BOOL)isWindowed { return _window != nil; }
- (void)show
{
  if (_window) [_window makeKeyAndOrderFront:nil];
  [[NSNotificationCenter defaultCenter] postNotificationName:PCEditorDidBecomeActiveNotification object:self];
}
- (BOOL)windowShouldClose:(id)sender { return [self close:sender]; }
- (BOOL)saveFileIfNeeded { return !_edited || [self saveFile]; }
- (BOOL)saveFile { return [self saveFileTo:_path]; }
- (BOOL)saveFileTo:(NSString *)path
{
  if (!_editable) return NO;
  NSError *error = nil;
  if (![[_document XMLData] writeToFile:path options:NSDataWritingAtomic error:&error])
  { NSRunAlertPanel(@"Save Interface",@"%@",@"OK",nil,nil,[error localizedDescription]); return NO; }
  _edited = NO;
  [[NSNotificationCenter defaultCenter] postNotificationName:PCEditorDidSaveNotification object:self];
  return YES;
}
- (BOOL)revertFileToSaved
{
  if (![self loadDocument]) return NO;
  _edited = NO; [_tree reloadData]; [self selectObject:[_objects count] ? [_objects objectAtIndex:0] : nil];
  return YES;
}
- (BOOL)closeFile:(id)sender save:(BOOL)save
{
  if (save && ![self saveFileIfNeeded]) return NO;
  [[self retain] autorelease];
  [_window orderOut:nil];
  [[NSNotificationCenter defaultCenter] postNotificationName:PCEditorDidCloseNotification object:self];
  return YES;
}
- (BOOL)close:(id)sender
{
  if (_edited)
  {
    NSInteger result = NSRunAlertPanel(@"Save Interface",@"Save changes to %@?",@"Save",@"Cancel",@"Don't Save",[_path lastPathComponent]);
    if (result == NSAlertAlternateReturn || (result == NSAlertDefaultReturn && ![self saveFile])) return NO;
  }
  return [self closeFile:sender save:NO];
}
@end
