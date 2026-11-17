/* Embedded editor for modern Cocoa XIB documents. */
#import <AppKit/AppKit.h>
#import <Protocols/CodeEditor.h>
@class PCInterfaceItem;

@interface PCInterfaceEditor : NSObject <CodeEditor>
{
  NSString *_path, *_categoryPath;
  id _manager;
  NSXMLDocument *_document;
  id _gorm;                 // PCGormArchive of a .gorm, which saves are written to
  NSMutableArray *_objects;
  PCInterfaceItem *_rootItem;
  NSXMLElement *_selected;
  NSView *_component;
  NSView *_canvas;
  NSWindow *_window;
  NSOutlineView *_tree;
  NSTextField *_fields[5];
  NSTextField *_status;
  BOOL _editable, _edited, _updatingSelection;
}
- (void)selectObject:(NSXMLElement *)object;
- (void)applyProperties:(id)sender;
@end
