/* Embedded editor for modern Cocoa XIB documents. */
#import <AppKit/AppKit.h>
#import <Protocols/CodeEditor.h>
@class PCInterfaceItem;
@class PCInterfaceDocument;

@interface PCInterfaceEditor : NSObject <CodeEditor>
{
  NSString *_path, *_categoryPath;
  id _manager;
  PCInterfaceDocument *_model;  // the XIB being edited (generated for a .gorm)
  id _gorm;                 // PCGormArchive of a .gorm, which saves are written to
  PCInterfaceItem *_rootItem;
  NSXMLElement *_selected;
  NSView *_component;
  NSView *_canvas;
  NSWindow *_window;
  NSOutlineView *_tree;
  NSTextField *_status;
  NSUndoManager *_undoManager;
  NSDictionary *_frameSnapshot;  // state before a drag on the canvas
  // Inspector, as Xcode's: Identity, Attributes, Size and Connections
  NSSegmentedControl *_inspectorTabs;
  NSTabView *_inspectorPanes;
  NSScrollView *_identityScroll, *_attributesScroll, *_sizeScroll;
  NSMutableArray *_inspectorBindings;  // what each inspector control edits
  NSMutableSet *_inspectedAttributes;  // shown in a form, not in Other Attributes
  NSTextField *_frameFields[4];
  NSString *_inspectedIdentifier;  // keeps the panes' scroll position for it
  BOOL _showsOtherAttributes;
  NSTableView *_connectionTable;
  NSArray *_connectionRows, *_connectionTargets;
  NSPopUpButton *_connectionKindPopUp, *_connectionTargetPopUp;
  NSTextField *_connectionNameField;
  NSButton *_addConnectionButton, *_removeConnectionButton;
  NSArray *_constraintItems;
  // Library
  NSPopUpButton *_libraryPopUp;
  NSButton *_addObjectButton, *_deleteObjectButton;
  BOOL _editable, _edited, _updatingSelection;
}
- (void)selectObject:(NSXMLElement *)object;
- (NSUndoManager *)undoManager;
/* Adds the object chosen in the library next to or into the selection. */
- (void)addLibraryObject:(id)sender;
- (void)deleteObject:(id)sender;
- (void)addConnection:(id)sender;
- (void)removeConnection:(id)sender;
@end

/* The inspector (PCInterfaceInspector.m). */
@interface PCInterfaceEditor (PCInterfaceInspector)
- (NSView *)inspectorWithFrame:(NSRect)frame;
/* Shows the selection in the inspector's panes. */
- (void)updateInspector;
/* Shows the frame of the selection while it is dragged on the canvas. */
- (void)updateFrameFields;
- (void)showInspectorPane:(id)sender;
@end
