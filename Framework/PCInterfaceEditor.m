/*
 * Embedded visual editing of modern Cocoa XIB XML. Keep the XML graph intact:
 * editing a property must not instantiate application classes or connections.
 * Distributed under the GNU General Public License, version 2 or later.
 */
#import "PCInterfaceEditor.h"
#import "PCGormArchive.h"
#import "PCGormXIBWriter.h"
#import "PCInterfaceDocument.h"
#import "PCInterfaceRendering.h"
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
  PCInterfaceDocument *model;  // not retained; names the item
  BOOL group;                  // the Constraints group of a view
}
- (PCInterfaceItem *)itemForObject:(NSXMLElement *)object;
- (PCInterfaceItem *)itemWithKey:(NSString *)key;
- (NSString *)key;
@end
@implementation PCInterfaceItem
- (id)init { if ((self = [super init])) children = [NSMutableArray new]; return self; }
- (void)dealloc { [element release]; [filePath release]; [children release]; [super dealloc]; }
- (NSString *)title
{
  if (group) return @"Constraints";
  if ([[element name] isEqual:@"constraint"]) return [model descriptionOfConstraint:element];
  /* As in Xcode's outline: the object's name, without its class. */
  return element ? [model nameOfObject:element] : [filePath lastPathComponent];
}
- (NSString *)symbolicIconName
{
  if (!element) return @"text-x-generic-symbolic";
  if (group) return @"folder-symbolic";
  if ([[element name] isEqual:@"constraint"]) return @"insert-link-symbolic";
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
  if (object == element && !group) return self;
  for (PCInterfaceItem *child in children)
  { PCInterfaceItem *found = [child itemForObject:object]; if (found) return found; }
  return nil;
}
/* What identifies the item in another version of the document: the id of
 * its element, or of the view a Constraints group belongs to. */
- (NSString *)key
{
  if (group) return [@"Constraints of " stringByAppendingString:[parent key] ?: @""];
  return element ? Attribute(element,@"id") : filePath;
}
- (PCInterfaceItem *)itemWithKey:(NSString *)key
{
  if ([[self key] isEqual:key]) return self;
  for (PCInterfaceItem *child in children)
  { PCInterfaceItem *found = [child itemWithKey:key]; if (found) return found; }
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
#ifdef GNUSTEP
@interface NSTableView (PCInterfaceViewSupport)
- (void)_registerPrototypeViews:(NSArray *)views;
@end
#endif
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

/* What the canvas and the component view ask of the editor. */
@interface PCInterfaceEditor (PCInterfaceEditing)
- (BOOL)canEditStructure;
- (BOOL)canMoveObject:(NSXMLElement *)object;
- (NSArray *)itemsOfConstraint:(NSXMLElement *)constraint;
- (void)beginFrameChange;
- (void)setFrame:(NSRect)frame ofObject:(NSXMLElement *)object;
- (void)endFrameChangeOfObject:(NSXMLElement *)object;
- (void)undo:(id)sender;
- (void)redo:(id)sender;
@end

/* The editor's view. Undo, Redo and Delete from the Edit menu reach the
 * editor through it from every view inside. */
@interface PCInterfaceComponentView : NSView
{
  @public
  PCInterfaceEditor *editor;
}
@end

@implementation PCInterfaceComponentView
- (NSUndoManager *)undoManager
{
  return [editor undoManager];
}
- (void)undo:(id)sender
{
  [editor undo:sender];
}
- (void)redo:(id)sender
{
  [editor redo:sender];
}
- (void)delete:(id)sender
{
  [editor deleteObject:sender];
}
- (BOOL)validateMenuItem:(NSMenuItem *)item
{
  NSUndoManager *undo = [editor undoManager];

  if ([item action] == @selector(undo:))
  {
    [item setTitle:[undo undoMenuItemTitle]];
    return [undo canUndo];
  }
  if ([item action] == @selector(redo:))
  {
    [item setTitle:[undo redoMenuItemTitle]];
    return [undo canRedo];
  }
  if ([item action] == @selector(delete:))
  {
    return [editor canEditStructure];
  }
  return YES;
}
@end

@interface PCInterfaceCanvas : NSView
{
  @public
  PCInterfaceEditor *editor;
  NSXMLElement *root, *selection;
  NSMutableArray *elements, *rects;
}
- (void)showObject:(NSXMLElement *)object;
- (NSXMLElement *)windowOfRoot;
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
  if ([self windowOfRoot]) size.height += PCInterfaceTitleBarHeight();
  if ([[root name] isEqual:@"menu"])
  {
    NSArray *containers = [root elementsForName:@"items"];
    if ([containers count]) size.height = [[[containers objectAtIndex:0] elementsForName:@"menuItem"] count]*22+60;
  }
  NSSize viewport = [[self enclosingScrollView] contentSize];
  [self setFrameSize:NSMakeSize(MAX(viewport.width,MAX(640,size.width+80)),MAX(viewport.height,MAX(480,size.height+80)))];
  [self setNeedsDisplay:YES];
}
/* The window whose content view the canvas shows. */
- (NSXMLElement *)windowOfRoot
{
  NSXMLElement *parent = (NSXMLElement *)[root parent];
  return [Attribute(root,@"key") isEqual:@"contentView"] && [[parent name] isEqual:@"window"] ? parent : nil;
}
/* Draws an object and what is inside it. Views are drawn by the renderer,
 * with the cells of the active theme, and clipped to their superview. */
- (void)drawObject:(NSXMLElement *)object inRect:(NSRect)parent flipped:(BOOL)flipped isRoot:(BOOL)isRoot
{
  NSRect rect = ObjectFrame(object);
  BOOL framed = FrameElement(object) != nil;
  BOOL inside = YES;
  if (framed)
  {
    rect.size.width = MAX(1,rect.size.width); rect.size.height = MAX(1,rect.size.height);
    if (isRoot) rect.origin = parent.origin;
    else rect.origin = NSMakePoint(NSMinX(parent)+rect.origin.x,
                                   flipped ? NSMaxY(parent)-rect.origin.y-NSHeight(rect) : NSMinY(parent)+rect.origin.y);
    [elements addObject:object]; [rects addObject:[NSValue valueWithRect:rect]];
    if (isRoot)
    {
      if (![self windowOfRoot]) { [[NSColor windowBackgroundColor] set]; NSRectFill(rect); }
    }
    else inside = PCInterfaceDrawObject(object,rect,self);
    parent = rect;
    flipped = PCInterfaceIsFlipped(object);
  }
  if (!inside) return;
  if (framed) { [NSGraphicsContext saveGraphicsState]; NSRectClip(rect); }
  for (NSXMLNode *child in [object children])
    if ([child kind] == NSXMLElementKind)
    {
      [self drawObject:(id)child inRect:parent flipped:flipped isRoot:NO];
      /* A tab view shows its first tab. */
      if ([[object name] isEqual:@"tabViewItems"]) break;
    }
  if (framed) [NSGraphicsContext restoreGraphicsState];
}
/* The handles that resize the selection: corners and edge centers, as in
 * Xcode. Each is a fraction of the width and height. */
static const CGFloat Handles[8][2] = {{0,0},{0.5,0},{1,0},{0,0.5},{1,0.5},{0,1},{0.5,1},{1,1}};
- (NSRect)handle:(NSUInteger)index ofRect:(NSRect)rect
{
  return NSMakeRect(floor(NSMinX(rect)+Handles[index][0]*NSWidth(rect))-3.5,
                    floor(NSMinY(rect)+Handles[index][1]*NSHeight(rect))-3.5,7,7);
}
- (void)drawRect:(NSRect)dirty
{
  NSColor *background = [NSColor respondsToSelector:@selector(underPageBackgroundColor)]
  ? [NSColor performSelector:@selector(underPageBackgroundColor)] : [NSColor lightGrayColor];
  [background set]; NSRectFill(dirty);
  [elements removeAllObjects]; [rects removeAllObjects];
  if (root && FrameElement(root))
  {
    NSXMLElement *window = [self windowOfRoot];
    NSPoint origin = NSMakePoint(40,40);
    if (window)
    {
      NSRect whole = PCInterfaceDrawWindowFrame(window,NSMakeRect(origin.x,origin.y,NSWidth(ObjectFrame(root)),
                                                                  NSHeight(ObjectFrame(root))),self);
      [elements addObject:window]; [rects addObject:[NSValue valueWithRect:whole]];
    }
    [self drawObject:root inRect:NSMakeRect(origin.x,origin.y,0,0) flipped:NO isRoot:YES];
    /* A constraint: the views it relates. */
    if ([[selection name] isEqual:@"constraint"])
    {
      NSArray *items = [editor itemsOfConstraint:selection];
      for (NSUInteger i=0; i<[elements count]; i++)
        if ([items indexOfObjectIdenticalTo:[elements objectAtIndex:i]] != NSNotFound)
        {
          [[NSColor orangeColor] set]; NSFrameRectWithWidth([[rects objectAtIndex:i] rectValue],2);
        }
    }
    for (NSUInteger i=0; i<[elements count]; i++)
      if ([elements objectAtIndex:i] == selection)
      {
        NSRect rect = [[rects objectAtIndex:i] rectValue];
        [[NSColor alternateSelectedControlColor] set]; NSFrameRectWithWidth(NSInsetRect(rect,-1,-1),1);
        if (selection != root && [editor canMoveObject:selection])
          for (NSUInteger h=0; h<8; h++)
          {
            NSRect handle = [self handle:h ofRect:rect];
            [[NSColor whiteColor] set]; NSRectFill(handle);
            [[NSColor alternateSelectedControlColor] set]; NSFrameRect(handle);
          }
      }
  }
  else if ([[root name] isEqual:@"menu"])
  {
    NSArray *items = [[root elementsForName:@"items"] count] ?
    [[[root elementsForName:@"items"] objectAtIndex:0] elementsForName:@"menuItem"] : [NSArray array];
    CGFloat y = [self bounds].size.height-60;
    NSFont *font = [NSFont menuFontOfSize:0];
    [ObjectTitle(root) drawAtPoint:NSMakePoint(40,y) withAttributes:
     [NSDictionary dictionaryWithObject:[NSFont boldSystemFontOfSize:14] forKey:NSFontAttributeName]];
    NSRect menu = NSMakeRect(40,y-22*[items count]-4,300,22*[items count]+4);
    [[NSColor controlBackgroundColor] set]; NSRectFill(menu);
    [[NSColor gridColor] set]; NSFrameRect(menu);
    y -= 2;
    for (NSXMLElement *item in items)
    {
      y -= 22; NSRect row = NSMakeRect(41,y,298,22);
      BOOL selected = item == selection;
      NSColor *text = selected ? [NSColor selectedMenuItemTextColor] : [NSColor controlTextColor];
      if (selected) { [[NSColor selectedMenuItemColor] set]; NSRectFill(row); }
      [elements addObject:item]; [rects addObject:[NSValue valueWithRect:row]];
      if ([Attribute(item,@"isSeparatorItem") isEqual:@"YES"])
      { [[NSColor gridColor] set]; NSRectFill(NSMakeRect(48,y+11,284,1)); continue; }
      NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:font,NSFontAttributeName,
                                  [Attribute(item,@"enabled") isEqual:@"NO"] ? [NSColor disabledControlTextColor] : text,
                                  NSForegroundColorAttributeName,nil];
      if ([Attribute(item,@"state") isEqual:@"on"]) [@"✓" drawAtPoint:NSMakePoint(46,y+3) withAttributes:attributes];
      [ObjectTitle(item) drawAtPoint:NSMakePoint(62,y+3) withAttributes:attributes];
      NSString *key = Attribute(item,@"keyEquivalent");
      if ([key length])
      {
        NSString *shortcut = [@"⌘" stringByAppendingString:[key uppercaseString]];
        [shortcut drawAtPoint:NSMakePoint(NSMaxX(row)-12-[shortcut sizeWithAttributes:attributes].width,y+3)
               withAttributes:attributes];
      }
      if ([[item elementsForName:@"menu"] count])
        [@"▸" drawAtPoint:NSMakePoint(NSMaxX(row)-16,y+3) withAttributes:attributes];
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
/* A click selects; dragging moves the view, or resizes it from a handle
 * of the selection. */
- (void)mouseDown:(NSEvent *)event
{
  NSPoint      start = [self convertPoint:[event locationInWindow] fromView:nil];
  NSXMLElement *object = nil;
  NSInteger    handle = -1;
  BOOL         dragged = NO;

  for (NSInteger i=[elements count]-1; i>=0 && object == nil; i--)
    if ([elements objectAtIndex:i] == selection && selection != root && [editor canMoveObject:selection])
      for (NSUInteger h=0; h<8; h++)
        if (NSPointInRect(start,NSInsetRect([self handle:h ofRect:[[rects objectAtIndex:i] rectValue]],-2,-2)))
        { object = selection; handle = h; break; }
  if (object == nil)
    for (NSInteger i=[elements count]-1; i>=0; i--)
      if (NSPointInRect(start,[[rects objectAtIndex:i] rectValue]))
      { object = [elements objectAtIndex:i]; break; }
  if (object == nil) return;
  if (object != selection) [editor selectObject:object];
  if (object == root || ![editor canMoveObject:object]) return;

  NSRect frame = ObjectFrame(object);
  while (YES)
  {
    NSEvent *next = [[self window] nextEventMatchingMask:NSLeftMouseDraggedMask|NSLeftMouseUpMask];
    if ([next type] == NSLeftMouseUp) break;
    NSPoint point = [self convertPoint:[next locationInWindow] fromView:nil];
    CGFloat dx = round(point.x-start.x), dy = round(point.y-start.y);
    if (!dragged)
    {
      if (fabs(dx) < 3 && fabs(dy) < 3) continue;
      [editor beginFrameChange]; dragged = YES;
    }
    NSRect changed = frame;
    if (handle >= 0)
    {
      /* Each handle moves the edges it is on. */
      CGFloat fx = Handles[handle][0], fy = Handles[handle][1];
      if (fx == 0) { dx = MIN(dx,frame.size.width-1); changed.origin.x += dx; changed.size.width -= dx; }
      else if (fx == 1) changed.size.width = MAX(1,frame.size.width+dx);
      if (fy == 0) { dy = MIN(dy,frame.size.height-1); changed.origin.y += dy; changed.size.height -= dy; }
      else if (fy == 1) changed.size.height = MAX(1,frame.size.height+dy);
    }
    else
    {
      changed.origin.x += dx; changed.origin.y += dy;
    }
    [editor setFrame:changed ofObject:object];
    [self setNeedsDisplay:YES];
  }
  if (dragged) [editor endFrameChangeOfObject:object];
}
@end

@implementation PCInterfaceEditor
- (void)dealloc
{
  [_path release]; [_categoryPath release]; [_model release];
  [_gorm release];
  [_tree setDelegate:nil]; [_tree setDataSource:nil]; [_rootItem release];
  [_connectionTable setDataSource:nil]; [_connectionTable setDelegate:nil];
  [_connectionRows release]; [_inspectorBindings release]; [_inspectedAttributes release];
  [_inspectedIdentifier release];
  [_connectionTargets release]; [_frameSnapshot release]; [_constraintItems release];
  [_undoManager removeAllActionsWithTarget:self]; [_undoManager release];
  [_window setDelegate:nil]; [_window close]; [_window release];
  ((PCInterfaceComponentView *)_component)->editor = nil;
  ((PCInterfaceCanvas *)_canvas)->editor = nil;
  /* The nib's top-level object. */
  [_component release]; [super dealloc];
}
- (BOOL)isGorm
{
  return [[[_path pathExtension] lowercaseString] isEqual:@"gorm"];
}
/* Titles and frames of a .gorm are edited in its archive too; everything
 * else only in a XIB. */
- (BOOL)canEditStructure
{
  return _editable && _gorm == nil;
}
/* A .gorm is a GNUstep archive. PCGormArchive reads it as archived and
 * writes it back; the editor works on its XIB (PCGormXIBWriter), and each
 * edit is made in the archive too (-applyEdit...), so saving writes the
 * archive Gorm and GNUstep read, not a conversion of the XIB. */
- (PCInterfaceDocument *)modelFromGorm:(PCGormArchive *)archive
{
  NSData *data = [[PCGormXIBWriter documentForArchive:archive toolsVersion:nil warnings:NULL] XMLData];

  return [PCInterfaceDocument documentWithData:data error:NULL];
}
/* The archived object an XIB element stands for. */
- (PCGormObject *)gormObjectForElement:(NSXMLElement *)element
{
  return [PCGormXIBWriter objectForIdentifier:Attribute(element, @"id") inArchive:_gorm];
}
- (void)gormSetTitle:(NSString *)title ofElement:(NSXMLElement *)element
{
  PCGormObject *object = [self gormObjectForElement:element];

  /* Windows, menus and items have a title; cells their contents; a box
   * the contents of its title cell. */
  if ([object hasField:@"title"]) [object setString:title forField:@"title"];
  else if ([object hasField:@"contents"]) [object setString:title forField:@"contents"];
  else if ([[object objectForField:@"cell"] hasField:@"contents"])
    [[object objectForField:@"cell"] setString:title forField:@"contents"];
}
- (void)gormSetFrame:(NSRect)frame ofElement:(NSXMLElement *)element
{
  PCGormObject *object = [self gormObjectForElement:element];

  if ([object hasField:@"theFrame"])
  {
    [object setRect:frame forField:@"theFrame"];
  }
  else if ([object hasField:@"frame"])
  {
    /* A view's bounds follow its frame size, as -setFrame: does. */
    [object setRect:frame forField:@"frame"];
    if ([object hasField:@"bounds"])
    {
      NSRect bounds = [object rectForField:@"bounds"];
      bounds.size = frame.size;
      [object setRect:bounds forField:@"bounds"];
    }
  }
}
- (void)rebuildTree
{
  [_rootItem release]; _rootItem = [PCInterfaceItem new];
  _rootItem->filePath = [_path copy];
  [self addObjectsFromElement:[[_model XMLDocument] rootElement] toItem:_rootItem];
}
- (void)setModel:(PCInterfaceDocument *)model
{
  ASSIGN(_model, model);
  [self rebuildTree];
  _selected = nil;
}
- (BOOL)loadDocument
{
  NSString *problem = nil;
  PCInterfaceDocument *model;

  if ([self isGorm])
  {
    PCGormArchive *archive = [PCGormArchive archiveWithContentsOfFile:
                              [_path stringByAppendingPathComponent:@"objects.gorm"]
                                                                error:&problem];
    model = archive ? [self modelFromGorm:archive] : nil;
    if (model == nil)
    {
      NSRunAlertPanel(@"Interface Editor",@"Cannot open %@. %@",@"OK",nil,nil,
                      [_path lastPathComponent], problem ?: @"");
      return NO;
    }
    ASSIGN(_gorm, archive);
  }
  else
  {
    model = [PCInterfaceDocument documentWithData:[NSData dataWithContentsOfFile:_path] error:&problem];
    if (model == nil)
    {
      NSRunAlertPanel(@"Interface Editor",@"Cannot open %@ as a modern Cocoa XIB. %@",@"OK",nil,nil,
                      [_path lastPathComponent], problem ?: @"");
      return NO;
    }
  }
  [self setModel:model];
  [_undoManager removeAllActions];
  return YES;
}
- (void)addObjectsFromElement:(NSXMLElement *)element toItem:(PCInterfaceItem *)parent
{
  NSArray *objects = [_model objects];
  NSMutableArray *groups = [NSMutableArray array];
  for (NSXMLNode *child in [element children])
    if ([child kind] == NSXMLElementKind)
    {
      PCInterfaceItem *container = parent;
      if ([[child name] isEqual:@"constraints"] && parent->element)
      {
        /* As in Xcode, a view's constraints are a group below its subviews. */
        PCInterfaceItem *constraints = [[[PCInterfaceItem alloc] init] autorelease];
        constraints->element = [(NSXMLElement *)child retain]; constraints->parent = parent;
        constraints->group = YES;
        for (NSXMLElement *constraint in [(NSXMLElement *)child elementsForName:@"constraint"])
        {
          PCInterfaceItem *item = [[[PCInterfaceItem alloc] init] autorelease];
          item->element = [constraint retain]; item->parent = constraints; item->model = _model;
          [constraints->children addObject:item];
        }
        if ([constraints->children count]) [groups addObject:constraints];
        continue;
      }
      if ([objects indexOfObjectIdenticalTo:child] != NSNotFound)
      {
        container = [[[PCInterfaceItem alloc] init] autorelease];
        container->element = [(NSXMLElement *)child retain]; container->parent = parent;
        container->model = _model;
        [parent->children addObject:container];
      }
      [self addObjectsFromElement:(id)child toItem:container];
    }
  [parent->children addObjectsFromArray:groups];
}

// --- Undo: each edit records the document as it was before.

- (NSUndoManager *)undoManager
{
  return _undoManager;
}
- (NSDictionary *)snapshot
{
  NSMutableDictionary *snapshot = [NSMutableDictionary dictionary];
  [snapshot setObject:[_model data] forKey:@"XIB"];
  if (_gorm) [snapshot setObject:[(PCGormArchive *)_gorm data] forKey:@"Gorm"];
  if (Attribute(_selected,@"id")) [snapshot setObject:Attribute(_selected,@"id") forKey:@"Selection"];
  return snapshot;
}
- (void)registerUndo:(NSDictionary *)snapshot named:(NSString *)name
{
  NSMutableDictionary *named = [[snapshot mutableCopy] autorelease];
  [named setObject:name forKey:@"Action"];
  [[_undoManager prepareWithInvocationTarget:self] restoreSnapshot:named];
  [_undoManager setActionName:name];
}
- (void)restoreSnapshot:(NSDictionary *)snapshot
{
  NSString *name = [snapshot objectForKey:@"Action"] ?: @"";
  PCInterfaceDocument *model;

  [self registerUndo:[self snapshot] named:name];
  if ([snapshot objectForKey:@"Gorm"])
  {
    /* Writing an archive renumbers its objects, so the XIB is made anew. */
    PCGormArchive *archive = [PCGormArchive archiveWithData:[snapshot objectForKey:@"Gorm"] error:NULL];
    ASSIGN(_gorm, archive);
    model = [self modelFromGorm:archive];
  }
  else
  {
    model = [PCInterfaceDocument documentWithData:[snapshot objectForKey:@"XIB"] error:NULL];
  }
  if (model == nil) return;
  [self setModel:model];
  /* Constraints aren't objects, but can be selected. */
  PCInterfaceItem *selection = [_rootItem itemWithKey:[snapshot objectForKey:@"Selection"]];
  _selected = selection && !selection->group ? selection->element : nil;
  [self didChangeStructure:YES];
}
- (void)undo:(id)sender
{
  if ([_undoManager canUndo]) [_undoManager undo];
}
- (void)redo:(id)sender
{
  if ([_undoManager canRedo]) [_undoManager redo];
}
/* After an edit: the outline (rebuilt when objects were added or removed),
 * the inspector and the canvas show it. */
- (void)didChangeStructure:(BOOL)structural
{
  NSMutableArray *expanded = [NSMutableArray array];

  if (structural)
  {
    /* The new items are expanded as the old ones were. */
    for (NSInteger row = 0; row < [_tree numberOfRows]; row++)
      if ([_tree isItemExpanded:[_tree itemAtRow:row]] && [[_tree itemAtRow:row] key])
        [expanded addObject:[[_tree itemAtRow:row] key]];
    [self rebuildTree];
  }
  if (_selected == nil && [[_model objects] count]) _selected = [[_model objects] objectAtIndex:0];
  [self setIsEdited:YES];
  _updatingSelection = YES;
  [_tree reloadData];
  for (NSString *key in expanded)
  {
    PCInterfaceItem *item = [_rootItem itemWithKey:key];
    if (item) [_tree expandItem:item];
  }
  _updatingSelection = NO;
  [self selectObject:_selected];
  [[NSNotificationCenter defaultCenter] postNotificationName:PCEditorDidChangeNotification object:self];
}

// --- Views

/* The owner reads "Superview" when the constraint relates it to a view inside it. */
- (NSString *)titleOfConstraintItem:(NSXMLElement *)item ofConstraint:(NSXMLElement *)constraint
{
  if (item == [_model ownerOfConstraint:constraint] && [_model secondItemOfConstraint:constraint]
      && !([_model firstItemOfConstraint:constraint] == item && [_model secondItemOfConstraint:constraint] == item))
    return @"Superview";
  return [_model nameOfObject:item];
}
- (id)openFileAtPath:(NSString *)path editorManager:(id)manager editable:(BOOL)editable
{
  _manager = manager; [self setPath:path];
  _editable = editable;
  _undoManager = [[NSUndoManager alloc] init];
  if (![self loadDocument]) return nil;
  if (![NSBundle loadNibNamed:@"InterfaceEditor" owner:self] || _component == nil)
  {
    NSLog(@"PCInterfaceEditor: error loading InterfaceEditor");
    return nil;
  }
  ((PCInterfaceComponentView *)_component)->editor = self;
  ((PCInterfaceCanvas *)_canvas)->editor = self;
  [_tree setOutlineTableColumn:[[_tree tableColumns] objectAtIndex:0]];
#ifdef GNUSTEP
  [_tree _registerPrototypeViews:@[InterfaceObjectCell()]];
#endif
  [self setUpInspector];
  [_libraryPopUp addItemsWithTitles:[PCInterfaceDocument libraryItems]];
  [_tree reloadData];
  NSArray *objects = [_model objects];
  NSXMLElement *initial = [objects count] ? [objects objectAtIndex:0] : nil;
  for (NSXMLElement *object in objects)
    if ([[object name] isEqual:@"menu"] || FrameElement(object)) { initial = object; break; }
  for (NSXMLElement *object in objects) if ([[object name] isEqual:@"window"]) { initial = object; break; }
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
{
#ifdef GNUSTEP
  return [item title];
#else
  /* Cocoa sets the cell view's objectValue from this; its bindings need
   * the item. */
  return item;
#endif
}
- (NSView *)outlineView:(NSOutlineView *)view viewForTableColumn:(NSTableColumn *)column item:(id)item
{
  NSTableCellView *cell = InterfaceObjectCell(); [cell setObjectValue:item]; return cell;
}
- (BOOL)outlineView:(NSOutlineView *)view shouldEditTableColumn:(NSTableColumn *)column item:(id)item { return NO; }
- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{
  if (_updatingSelection || [(PCInterfaceOutlineView *)_tree isUpdatingRows]) return;
  PCInterfaceItem *item = [_tree itemAtRow:[_tree selectedRow]];
  if (item && item->element && !item->group) [self selectObject:item->element];
}
- (void)revealItem:(PCInterfaceItem *)item
{
  if (!item) return;
  [self revealItem:item->parent];
  if (![_tree isItemExpanded:item]) [_tree expandItem:item];
}

// --- Inspector

/* The connections pane: those of the selection, and what can be connected. */
- (void)updateConnections
{
  ASSIGN(_connectionRows, _selected ? [_model connectionsOfObject:_selected] : [NSArray array]);
  [_connectionTable reloadData];
  [_connectionTable deselectAll:nil];

  /* Every object can be the other end of a connection. Items are added to
   * the menu so that equal titles stay separate items. */
  NSMutableArray *targets = [NSMutableArray array];
  NSString *previous = [[_connectionTargetPopUp selectedItem] title];
  [_connectionTargetPopUp removeAllItems];
  for (NSXMLElement *object in [_model objects])
  {
    if ([[object name] hasSuffix:@"Cell"] || [[object name] isEqual:@"menuItem"]) continue;
    [targets addObject:object];
    [[_connectionTargetPopUp menu] addItemWithTitle:[NSString stringWithFormat:@"%@ (%@)",
                                                     [_model nameOfObject:object],[object name]]
                                             action:NULL keyEquivalent:@""];
  }
  ASSIGN(_connectionTargets, targets);
  if (previous && [_connectionTargetPopUp indexOfItemWithTitle:previous] >= 0)
    [_connectionTargetPopUp selectItemWithTitle:previous];
  /* Connections start at objects, not at constraints. */
  BOOL structure = [self canEditStructure] && _selected != nil && ![[_selected name] isEqual:@"constraint"];
  [_connectionKindPopUp setEnabled:structure]; [_connectionNameField setEnabled:structure];
  [_connectionTargetPopUp setEnabled:structure]; [_addConnectionButton setEnabled:structure];
  [_removeConnectionButton setEnabled:NO];
  [_libraryPopUp setEnabled:[self canEditStructure]]; [_addObjectButton setEnabled:[self canEditStructure]];
  [_deleteObjectButton setEnabled:[self canEditStructure] && [_model canRemoveObject:_selected]];
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
  [self updateInspector];
  NSString *note = [self isGorm] ? @"Gorm interface: titles and frames can be edited; saved as a Gorm archive"
                                 : @"Edits change only the XML of what is edited";
  NSString *what = [[object name] isEqual:@"constraint"] ? [_model descriptionOfConstraint:object] : [object name];
  [_status setStringValue:object ? [NSString stringWithFormat:@"%@ · %@ · %@",what,Attribute(object,@"id") ?: @"",note] : @"No interface objects"];
  [(PCInterfaceCanvas *)_canvas showObject:object];
  _updatingSelection = NO;
}
// --- Inspector tables

- (NSInteger)numberOfRowsInTableView:(NSTableView *)table
{
  if (table == _connectionTable) return [_connectionRows count];
  return 0;
}
- (id)tableView:(NSTableView *)table objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
  NSString *identifier = [column identifier];
  if (table == _connectionTable)
  {
    NSXMLElement *connection = [_connectionRows objectAtIndex:row];
    if ([identifier isEqual:@"Kind"]) return [[connection name] capitalizedString];
    if ([identifier isEqual:@"Name"]) return [_model nameOfConnection:connection];
    /* The object at the other end: → for connections from the selection. */
    NSXMLElement *source = [_model sourceOfConnection:connection];
    NSXMLElement *other = source == _selected ? [_model destinationOfConnection:connection] : source;
    return [NSString stringWithFormat:@"%@ %@",source == _selected ? @"→" : @"←",
            other ? [_model nameOfObject:other] : @"?"];
  }
  return nil;
}
- (BOOL)tableView:(NSTableView *)table shouldEditTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
  return NO;
}
- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
  BOOL structure = [self canEditStructure];
  [_removeConnectionButton setEnabled:structure && [_connectionTable selectedRow] >= 0];
}

// --- Editing actions

- (void)addLibraryObject:(id)sender
{
  if (![self canEditStructure]) return;
  NSDictionary *before = [self snapshot];
  NSString *name = [_libraryPopUp titleOfSelectedItem];
  NSXMLElement *added = [_model insertLibraryItem:name forObject:_selected];
  if (added == nil)
  {
    NSBeep();
    [_status setStringValue:[name hasSuffix:@"Menu Item"]
     ? @"Select a menu or menu item to add a menu item."
     : @"Select a window or view to add a view to it."];
    return;
  }
  [self registerUndo:before named:[NSString stringWithFormat:@"Add %@",name]];
  _selected = added;
  [self didChangeStructure:YES];
}
- (void)deleteObject:(id)sender
{
  if (![self canEditStructure] || ![_model canRemoveObject:_selected]) { NSBeep(); return; }
  NSDictionary *before = [self snapshot];
  NSXMLElement *parent = [_model objectOfElement:(NSXMLElement *)[_selected parent]];
  [_model removeObject:_selected];
  [self registerUndo:before named:@"Delete"];
  _selected = parent;
  [self didChangeStructure:YES];
}
- (void)addConnection:(id)sender
{
  NSInteger index = [_connectionTargetPopUp indexOfSelectedItem];
  NSString *name = [[_connectionNameField stringValue]
                    stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
  if (![self canEditStructure] || !_selected || index < 0 || index >= (NSInteger)[_connectionTargets count]
      || [name length] == 0)
  { NSBeep(); return; }
  NSDictionary *before = [self snapshot];
  NSXMLElement *target = [_connectionTargets objectAtIndex:index];
  BOOL outlet = [_connectionKindPopUp indexOfSelectedItem] == 0;
  if (!(outlet ? [_model addOutlet:name fromObject:_selected toObject:target]
        : [_model addAction:name fromObject:_selected toObject:target]))
  { NSBeep(); return; }
  [self registerUndo:before named:outlet ? @"Add Outlet" : @"Add Action"];
  [_connectionNameField setStringValue:@""];
  [self didChangeStructure:NO];
}
- (void)removeConnection:(id)sender
{
  NSInteger row = [_connectionTable selectedRow];
  if (![self canEditStructure] || row < 0) return;
  NSDictionary *before = [self snapshot];
  [_model removeConnection:[_connectionRows objectAtIndex:row]];
  [self registerUndo:before named:@"Remove Connection"];
  [self didChangeStructure:NO];
}

// --- Moving and resizing on the canvas

- (NSArray *)itemsOfConstraint:(NSXMLElement *)constraint
{
  return [_model itemsOfConstraint:constraint];
}
- (BOOL)canMoveObject:(NSXMLElement *)object
{
  return _editable && FrameElement(object) != nil && [object attributeForName:@"key"] == nil;
}
- (void)beginFrameChange
{
  ASSIGN(_frameSnapshot, [self snapshot]);
}
- (void)setFrame:(NSRect)frame ofObject:(NSXMLElement *)object
{
  NSXMLElement *element = FrameElement(object);
  SetAttribute(element,@"x",[NSString stringWithFormat:@"%.15g",frame.origin.x]);
  SetAttribute(element,@"y",[NSString stringWithFormat:@"%.15g",frame.origin.y]);
  SetAttribute(element,@"width",[NSString stringWithFormat:@"%.15g",frame.size.width]);
  SetAttribute(element,@"height",[NSString stringWithFormat:@"%.15g",frame.size.height]);
  [self updateFrameFields];
}
- (void)endFrameChangeOfObject:(NSXMLElement *)object
{
  if (_gorm) [self gormSetFrame:ObjectFrame(object) ofElement:object];
  if (_frameSnapshot) [self registerUndo:_frameSnapshot named:@"Change Frame"];
  DESTROY(_frameSnapshot);
  [self didChangeStructure:NO];
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
  _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100,100,1000,600)
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
  NSData *data = _gorm ? [(PCGormArchive *)_gorm data] : [_model data];
  if (_gorm)
  {
    /* objects.gorm inside the .gorm; data.classes and data.info stay. A
     * new .gorm gets copies of them. */
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![[path stringByStandardizingPath] isEqual:[_path stringByStandardizingPath]])
    {
      [fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:NULL];
      for (NSString *file in [fm contentsOfDirectoryAtPath:_path error:NULL])
      {
        NSString *target = [path stringByAppendingPathComponent:file];
        if (![file isEqual:@"objects.gorm"] && ![fm fileExistsAtPath:target])
          [fm copyItemAtPath:[_path stringByAppendingPathComponent:file] toPath:target error:NULL];
      }
    }
    path = [path stringByAppendingPathComponent:@"objects.gorm"];
  }
  if (![data writeToFile:path options:NSDataWritingAtomic error:&error])
  { NSRunAlertPanel(@"Save Interface",@"%@",@"OK",nil,nil,[error localizedDescription]); return NO; }
  _edited = NO;
  [[NSNotificationCenter defaultCenter] postNotificationName:PCEditorDidSaveNotification object:self];
  return YES;
}
- (BOOL)revertFileToSaved
{
  if (![self loadDocument]) return NO;
  _edited = NO; [_tree reloadData];
  [self selectObject:[[_model objects] count] ? [[_model objects] objectAtIndex:0] : nil];
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
