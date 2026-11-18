#import <AppKit/AppKit.h>
#import "PCAppController.h"
#import <ProjectCenter/PCProjectManager.h>
#import <ProjectCenter/PCProject.h>
#import <ProjectCenter/PCProjectLauncher.h>
#import <ProjectCenter/PCProjectEditor.h>
#import <ProjectCenter/PCProjectBuilder.h>
#import <ProjectCenter/PCProjectBrowser.h>
#import <ProjectCenter/PCProjectWindow.h>
#import <ProjectCenter/PCFileManager.h>
#import "Framework/PCNavigators.h"
#import "Framework/PCXcodeProjectEditor.h"
#import "Framework/PCInterfaceEditor.h"
#import "Framework/PCFileTypeIcon.h"
#include <gtk/gtk.h>
#include <gdk/x11/gdkx.h>
#include <cairo-xlib.h>
#include <dlfcn.h>
extern GtkWindow *GTK4NativeHostForWindow(NSWindow *window);
extern GtkWidget *GTK4NativeWidgetForView(NSView *view);
extern NSArray *GTK4NativeChildrenForView(NSView *view);
@interface NSObject (NativeSceneProbe)
+ (BOOL)supportsView:(NSView *)view;
@end
static void DumpUnsupportedNativeViews(NSView *view)
{
  Class adapter=NSClassFromString(@"GTK4NativeView");
  if(![adapter supportsView:view]) NSLog(@"Unsupported native project view: %@",NSStringFromClass(view.class));
  if([view isKindOfClass:[NSTableView class]]) return;
  if([view isKindOfClass:[NSScrollView class]]) { DumpUnsupportedNativeViews([(NSScrollView *)view documentView]); return; }
  for(NSView *child in GTK4NativeChildrenForView(view)) DumpUnsupportedNativeViews(child);
}

static GtkWidget *FindLabel(GtkWidget *widget, const char *text)
{
  if (GTK_IS_LABEL(widget) && !strcmp(gtk_label_get_text(GTK_LABEL(widget)),text)) return widget;
  for (GtkWidget *child = gtk_widget_get_first_child(widget); child; child = gtk_widget_get_next_sibling(child))
  {
    GtkWidget *found = FindLabel(child,text);
    if (found) return found;
  }
  return NULL;
}

static GtkWidget *FindIcon(GtkWidget *widget, const char *name)
{
  if (GTK_IS_IMAGE(widget) && !g_strcmp0(gtk_image_get_icon_name(GTK_IMAGE(widget)),name)) return widget;
  for (GtkWidget *child = gtk_widget_get_first_child(widget); child; child = gtk_widget_get_next_sibling(child))
  {
    GtkWidget *found = FindIcon(child,name);
    if (found) return found;
  }
  return NULL;
}

static GtkWidget *FindCustomIcon(GtkWidget *widget)
{
  if (GTK_IS_IMAGE(widget) && gtk_image_get_storage_type(GTK_IMAGE(widget)) == GTK_IMAGE_PAINTABLE
      && gtk_image_get_paintable(GTK_IMAGE(widget))) return widget;
  for (GtkWidget *child=gtk_widget_get_first_child(widget); child; child=gtk_widget_get_next_sibling(child))
  { GtkWidget *found=FindCustomIcon(child); if (found) return found; }
  return NULL;
}

/* Table rows [name, value...] as name -> last value. */
static NSDictionary *RowsByFirstColumn(NSArray *rows)
{
  NSMutableDictionary *result = [NSMutableDictionary dictionary];
  for (NSArray *row in rows)
    if ([row count] > 1) [result setObject:[row lastObject] forKey:[row objectAtIndex:0]];
  return result;
}

static void PumpEvents(double seconds)
{
  NSDate *until = [NSDate dateWithTimeIntervalSinceNow:seconds];
  while ([until timeIntervalSinceNow] > 0)
  {
    NSEvent *event = [NSApp nextEventMatchingMask:NSAnyEventMask untilDate:[NSDate dateWithTimeIntervalSinceNow:0.02] inMode:NSDefaultRunLoopMode dequeue:YES];
    if (event) [NSApp sendEvent:event];
  }
}

static void CountSourceChanges(GListModel *model, guint position, guint removed, guint added, gpointer data)
{
  (*(NSUInteger *)data)++;
}

static void Check(BOOL condition, NSString *message)
{
  if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}

@interface ProjectChooserDriver : NSObject
{
  @public
  NSString *projectPath;
  BOOL navigated;
  BOOL selectedProject;
  BOOL selectedNativeFile;
  BOOL fileChooser;
  NSString *selectionPath;
}
- (void)advance:(NSTimer *)timer;
@end

@implementation ProjectChooserDriver
- (void)advance:(NSTimer *)timer
{
  GListModel *windows = gtk_window_get_toplevels();
  for (guint i = 0; i < g_list_model_get_n_items(windows); i++)
  {
    GtkWindow *window = g_list_model_get_item(windows, i);
    if (GTK_IS_FILE_CHOOSER(window) && gtk_widget_get_visible(GTK_WIDGET(window)))
    {
      GtkFileChooser *chooser = GTK_FILE_CHOOSER(window);
      if (fileChooser)
      {
        Check(gtk_file_chooser_get_action(chooser) == GTK_FILE_CHOOSER_ACTION_OPEN, @"File Open uses native GTK file chooser");
        if (!navigated)
        {
          GFile *folder = g_file_new_for_path([[[projectPath stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] fileSystemRepresentation]);
          gtk_file_chooser_set_current_folder(chooser, folder, NULL);
          g_object_unref(folder);
          navigated = YES;
        }
        else if (!selectionPath)
        {
          selectedNativeFile = YES;
          [timer invalidate];
          gtk_dialog_response(GTK_DIALOG(window), GTK_RESPONSE_CANCEL);
        }
        else if (!selectedNativeFile)
        {
          GFile *file = g_file_new_for_path([selectionPath fileSystemRepresentation]);
          Check(gtk_file_chooser_set_file(chooser, file, NULL), @"select pbxproj through File Open");
          g_object_unref(file);
          selectedNativeFile = YES;
        }
        else
        {
          GFile *file = gtk_file_chooser_get_file(chooser);
          char *path = file ? g_file_get_path(file) : NULL;
          BOOL ready = path && [selectionPath isEqual:[NSString stringWithUTF8String:path]];
          g_free(path);
          if (file) g_object_unref(file);
          if (ready)
          {
            selectedProject = YES;
            [timer invalidate];
            gtk_dialog_response(GTK_DIALOG(window), GTK_RESPONSE_ACCEPT);
          }
        }
        g_object_unref(window);
        return;
      }
      Check(gtk_file_chooser_get_action(chooser) == GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER, @"native project chooser selects package directories");
      if (!navigated)
      {
        GFile *parent = g_file_new_for_path([[[projectPath stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] fileSystemRepresentation]);
        gtk_file_chooser_set_current_folder(chooser, parent, NULL);
        g_object_unref(parent);
        navigated = YES;
      }
      else if (!selectedNativeFile)
      {
        GFile *file = g_file_new_for_path([projectPath fileSystemRepresentation]);
        Check(gtk_file_chooser_set_file(chooser, file, NULL), @"select project in native chooser");
        g_object_unref(file);
        selectedNativeFile = YES;
      }
      else
      {
        GFile *file = gtk_file_chooser_get_file(chooser);
        char *path = file ? g_file_get_path(file) : NULL;
        BOOL ready = path && [projectPath isEqual:[NSString stringWithUTF8String:path]];
        g_free(path);
        if (file) g_object_unref(file);
        if (ready)
        {
          selectedProject = YES;
          [timer invalidate];
          gtk_dialog_response(GTK_DIALOG(window), GTK_RESPONSE_ACCEPT);
        }
      }
      g_object_unref(window);
      return;
    }
    g_object_unref(window);
  }
  NSOpenPanel *panel = (NSOpenPanel *)[NSApp modalWindow];
  Check([panel isKindOfClass:[NSOpenPanel class]], @"project chooser is modal");
  if (!navigated)
  {
    /* Fallback chooser still supports directory navigation. */
    [panel setDirectory:[projectPath stringByDeletingLastPathComponent]];
    [panel setNameFieldStringValue:@""];
    navigated = YES;
    return;
  }
  Check([panel isVisible], @"chooser stays visible while browsing project parent");
  NSBrowser *browser = [panel valueForKey:@"_browser"];
  Check([browser setPath:projectPath], @"select xcodeproj package in browser");
  selectedProject = YES;
  [timer invalidate];
  [panel ok:nil];
}
@end

int main(int argc, char **argv)
{
  @autoreleasepool
  {
    Check(argc == 2, @"project path argument required");
    NSString *bundle = [NSString stringWithUTF8String:argv[1]];
    NSString *root = [bundle stringByDeletingLastPathComponent];
    NSArray *protected = @[@"EditGlyphData.xcodeproj/project.pbxproj", @"GNUmakefile", @"EditGlyphDataInfo.plist"];
    NSMutableDictionary *snapshots = [NSMutableDictionary dictionary];
    for (NSString *file in protected)
    {
      NSData *data = [NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:file]];
      Check(data != nil, file);
      [snapshots setObject:data forKey:file];
    }
    NSArray *originalFiles = [[NSFileManager defaultManager] directoryContentsAtPath:root];
    [NSApplication sharedApplication];
    NSMutableSet *iconData = [NSMutableSet set];
    NSArray *iconTypes = @[@"m",@"h",@"c",@"xib",@"plist"];
    for (NSString *type in iconTypes)
    {
      NSImage *icon = PCFileTypeIcon(type);
      Check(icon != nil && NSEqualSizes([icon size],NSMakeSize(16,16)), @"file type has a navigator-size icon");
      NSBitmapImageRep *bitmap = [NSBitmapImageRep imageRepWithData:[icon TIFFRepresentation]];
      Check([bitmap pixelsWide] == 48 && [bitmap pixelsHigh] == 48, @"file artwork keeps its full raster when passed to the native theme");
      Check(PCFileTypeIcon([type uppercaseString]) == icon, @"file icons are cached and extension matching ignores case");
      [iconData addObject:[icon TIFFRepresentation]];
    }
    Check([iconData count] == 5 && PCFileTypeIcon(@"unknown") == nil, @"five distinct file icons with generic fallback for other types");
    const char *iconPreview = getenv("PC_FILE_ICONS_PREVIEW");
    if (iconPreview)
    {
      NSImage *sheet = [[[NSImage alloc] initWithSize:NSMakeSize(480,100)] autorelease];
      [sheet lockFocus]; [[NSColor whiteColor] set]; NSRectFill(NSMakeRect(0,0,480,100));
      for (NSUInteger i=0; i<[iconTypes count]; i++)
      {
        [PCFileTypeIcon([iconTypes objectAtIndex:i]) drawInRect:NSMakeRect(i*96+24,35,48,48) fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1];
        [[@"." stringByAppendingString:[iconTypes objectAtIndex:i]] drawAtPoint:NSMakePoint(i*96+30,12) withAttributes:nil];
      }
      [sheet unlockFocus];
      NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:[sheet TIFFRepresentation]];
      Check([[rep representationUsingType:NSPNGFileType properties:@{}] writeToFile:[NSString stringWithUTF8String:iconPreview] atomically:YES], @"file icon preview");
    }
    /* Test the integrated layout whatever this user has stored; the
     * argument domain overrides without writing to their defaults. */
    [[NSUserDefaults standardUserDefaults] setVolatileDomain:
     [NSDictionary dictionaryWithObject:@"NO" forKey:@"UseTearOffWindows"] forName:NSArgumentDomain];
    PCAppController *controller = [[PCAppController alloc] init];
    PCProjectManager *manager = [controller projectManager];
    ProjectChooserDriver *driver = [ProjectChooserDriver new];
    driver->projectPath = bundle;
    NSTimer *chooserTimer = [NSTimer timerWithTimeInterval:0.15 target:driver selector:@selector(advance:) userInfo:nil repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:chooserTimer forMode:NSModalPanelRunLoopMode];
    NSArray *selected = [[manager fileManager] filesOfTypes:@[@"pcproj", @"project", @"xcodeproj"]
                                                  operation:PCOpenProjectOperation multiple:NO title:@"Open Project" accView:nil];
    [chooserTimer invalidate];
    Check(driver->navigated && driver->selectedProject, @"browsing parent did not dismiss chooser");
    Check(driver->selectedNativeFile, @"GTK native chooser was used");
    Check([selected count] == 1 && [[selected objectAtIndex:0] isEqual:bundle], @"chooser returns selected xcodeproj");
    [driver release];
    driver = [ProjectChooserDriver new];
    driver->projectPath = bundle;
    driver->fileChooser = YES;
    chooserTimer = [NSTimer timerWithTimeInterval:0.15 target:driver selector:@selector(advance:) userInfo:nil repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:chooserTimer forMode:NSModalPanelRunLoopMode];
    Check([[manager fileManager] filesOfTypes:nil operation:PCOpenFileOperation multiple:NO title:@"Open File" accView:nil] == nil, @"native File Open cancellation returns normally");
    [chooserTimer invalidate];
    Check(driver->navigated && driver->selectedNativeFile, @"native File Open browses Apps without dismissing or hanging");
    [driver release];
    PCProject *project = [manager openProjectAt:bundle makeActive:YES];
    Check(project != nil, @"open Xcode project through manager");
    Check([[project projectName] isEqual:@"EditGlyphData"], @"target name");
    PCProjectBrowser *sourceTree = [project projectBrowser];
    NSScrollView *sourceScroll = (NSScrollView *)[sourceTree view];
    NSOutlineView *outline = (NSOutlineView *)[sourceScroll documentView];
    Check([outline isKindOfClass:[NSOutlineView class]], @"source navigator is an outline");
    NSString *sourcePath = @"/Classes/EditGlyphData/GSWindowController.m";
    Check([sourceTree setPath:sourcePath], @"reveal nested source file");
    Check([[sourceTree nameOfSelectedFile] isEqual:@"EditGlyphData/GSWindowController.m"], @"outline selection keeps full source path");
    Check([[sourceTree nameOfSelectedCategory] isEqual:@"Classes"], @"outline selection category");
    /* The navigator mirrors Xcode: project row, its groups, then files. */
    Check([[[outline itemAtRow:0] valueForKey:@"title"] isEqual:@"EditGlyphData"] && [outline levelForRow:0] == 0, @"project row heads the navigator");
    Check([outline levelForRow:[outline selectedRow]] == 2, @"file sits below project and group rows");
    id sourceGroup = [outline parentForItem:[outline itemAtRow:[outline selectedRow]]];
    Check([[sourceGroup valueForKey:@"title"] isEqual:@"EditGlyphData"] && [outline parentForItem:sourceGroup] == [outline itemAtRow:0], @"file is listed in its Xcode group");
    Check([[outline itemAtRow:[outline selectedRow]] valueForKey:@"icon"] != nil, @"file rows have icons");
    NSMutableArray *topTitles = [NSMutableArray array];
    for (NSInteger row = 0; row < [outline numberOfRows]; row++)
      if ([outline levelForRow:row] == 1) [topTitles addObject:[[outline itemAtRow:row] valueForKey:@"title"]];
    Check(![topTitles containsObject:@"Classes"] && ![topTitles containsObject:@"Headers"], @"type categories are replaced by Xcode groups");
    Check([topTitles indexOfObject:@"Supporting Files"] == 2 && [[topTitles objectAtIndex:1] isEqual:@"EditGlyphDataTests"], @"GNUstep build files follow the Xcode groups");
    Check([[sourceTree selectedFiles] count] == 1, @"outline file selection");
    [sourceTree click:outline];
    Check([[[[project projectEditor] activeEditor] path] isEqual:[root stringByAppendingPathComponent:@"EditGlyphData/GSWindowController.m"]], @"outline click opens integrated source editor");
    NSInteger firstRow = [outline selectedRow];
    Check([sourceTree setPath:@"/Classes/EditGlyphData/GSAppDelegate.m"], @"reveal second source");
    NSMutableIndexSet *selection = [NSMutableIndexSet indexSetWithIndex:firstRow];
    [selection addIndex:[outline selectedRow]];
    [outline selectRowIndexes:selection byExtendingSelection:NO];
    Check([[sourceTree selectedFiles] count] == 2 && [sourceTree nameOfSelectedFile] == nil, @"outline multiple selection");
    Check([sourceTree setPath:[sourcePath stringByAppendingString:@"/testSymbol"]], @"editor symbol path reveals source file");
    Check([[sourceTree projectFileForCategoryPath:[sourceTree path]] isEqual:@"EditGlyphData/GSWindowController.m"], @"symbol resolves full file path");
    Check(![sourceTree setPath:@"/Classes/missing.m"], @"unknown source selection is rejected");
    NSSplitView *mainSplit = [[project projectWindow] valueForKey:@"h_split"];
    NSSplitView *sidebar = [[project projectWindow] valueForKey:@"v_split"];
    NSView *editorPane = [[project projectWindow] valueForKey:@"customView"];
    Check([mainSplit isVertical], @"source navigator uses left/right split");
    Check(NSMaxX([sidebar frame]) <= NSMinX([[editorPane superview] frame]), @"sidebar lies left of editor");
    CGFloat sidebarWidth = [sidebar frame].size.width;
    NSWindow *window = [[project projectWindow] valueForKey:@"projectWindow"];
    if(!GTK_IS_PANED(GTK4NativeWidgetForView(mainSplit))) DumpUnsupportedNativeViews(mainSplit);
    Check(GTK_IS_PANED(GTK4NativeWidgetForView(mainSplit)), @"source navigator split is a live GtkPaned");
    Check(GTK_IS_SCROLLED_WINDOW(GTK4NativeWidgetForView([outline enclosingScrollView])), @"source navigator scroll view is a live GtkScrolledWindow");
    NSRect enlarged = [window frame]; enlarged.size.width += 120; enlarged.size.height += 80;
    [window setFrame:enlarged display:YES];
    Check(fabs([sidebar frame].size.width - sidebarWidth) < 1, @"window resize preserves sidebar width");
    Check(fabs([sidebar frame].size.height - [editorPane frame].size.height) < 1, @"sidebar and editor fill available height");
    /* Selecting the project shows targets, build settings and phases. */
    Check([sourceTree setPath:@"/@EditGlyphData"], @"select the project row");
    [sourceTree click:outline];
    PCXcodeProjectEditor *overviewEditor = [[project projectWindow] xcodeProjectEditor];
    Check(overviewEditor != nil && [[overviewEditor view] window] == [[project projectWindow] valueForKey:@"projectWindow"], @"project row shows the project editor");
    NSArray *overviewTargets = [[[overviewEditor overview] objectForKey:@"Targets"] valueForKey:@"Name"];
    Check([overviewTargets containsObject:@"EditGlyphData"] && [overviewTargets containsObject:@"EditGlyphDataTests"], @"project editor lists the targets");
    Check([[[overviewEditor selection] objectForKey:@"Name"] isEqual:@"EditGlyphData"], @"the built target is selected first");
    NSDictionary *general = RowsByFirstColumn([overviewEditor generalRows]);
    Check([[general objectForKey:@"Type"] isEqual:@"Application"] && [[general objectForKey:@"Product Name"] isEqual:@"EditGlyphData"], @"general information for the target");
    Check([[general objectForKey:@"Build Script"] hasSuffix:@"build-editglyphdata.sh"], @"general information shows the GNUstep build");
    Check([[overviewEditor configurationNames] isEqual:(@[@"Debug", @"Release"])], @"build settings per configuration");
    NSArray *settingNames = [RowsByFirstColumn([overviewEditor settingRows]) allKeys];
    Check([settingNames containsObject:@"PRODUCT_BUNDLE_IDENTIFIER"] && [settingNames containsObject:@"CLANG_ENABLE_OBJC_ARC"], @"target settings merged with project settings");
    NSArray *phaseNames = [RowsByFirstColumn([overviewEditor phaseRows]) allKeys];
    Check([phaseNames containsObject:@"Compile Sources"] && [phaseNames containsObject:@"Copy Bundle Resources"], @"build phases of the target");
    NSOutlineView *targetsOutline = [overviewEditor targetOutlineView];
    for (NSInteger row = 0; row < [targetsOutline numberOfRows]; row++)
      if ([[[targetsOutline itemAtRow:row] title] isEqual:@"EditGlyphDataTests"])
        [targetsOutline selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    Check([[[overviewEditor selection] objectForKey:@"Name"] isEqual:@"EditGlyphDataTests"]
          && [[[overviewEditor selection] objectForKey:@"Dependencies"] containsObject:@"EditGlyphData"], @"selecting another target shows it");
    [overviewEditor selectEntryAtIndex:0];
    general = RowsByFirstColumn([overviewEditor generalRows]);
    Check([[general objectForKey:@"Project"] isEqual:@"EditGlyphData"] && [general objectForKey:@"Configurations"], @"project information");
    const char *overviewPreview = getenv("PC_PROJECT_EDITOR_PREVIEW");
    if (overviewPreview)
    {
      [overviewEditor selectEntryAtIndex:1];
      [overviewEditor selectSectionAtIndex:1];
      NSWindow *previewWindow = [[project projectWindow] valueForKey:@"projectWindow"];
      PumpEvents(0.5);
      GtkWindow *host = GTK4NativeHostForWindow(previewWindow);
      GdkSurface *surface = gtk_native_get_surface(GTK_NATIVE(host));
      Display *display = gdk_x11_display_get_xdisplay(gdk_surface_get_display(surface));
      Window xid = gdk_x11_surface_get_xid(surface);
      XWindowAttributes attributes; XGetWindowAttributes(display, xid, &attributes);
      cairo_surface_t *capture = cairo_xlib_surface_create(display, xid, attributes.visual, attributes.width, attributes.height);
      Check(cairo_surface_write_to_png(capture, overviewPreview) == CAIRO_STATUS_SUCCESS, @"project editor screenshot");
      cairo_surface_destroy(capture);
      [overviewEditor selectSectionAtIndex:0];
    }
    Check([sourceTree setPath:sourcePath], @"reveal the source file again");
    [sourceTree click:outline];

    /* Xcode-style window: toolbar, navigator, editor over a bottom area. */
    PCProjectWindow *projectWindow = [project projectWindow];
    NSToolbar *toolbar = [window toolbar];
    Check(toolbar != nil && [[[toolbar items] valueForKey:@"itemIdentifier"] isEqual:
                             (@[@"PCToolbarRun", @"PCToolbarStop", @"PCToolbarBuild", NSToolbarFlexibleSpaceItemIdentifier,
                                @"PCToolbarNavigator", @"PCToolbarBottomArea", @"PCToolbarInspector"])], @"window toolbar holds run, stop, build and pane toggles");
    for (NSToolbarItem *item in [toolbar items])
      if (![[item itemIdentifier] isEqual:NSToolbarFlexibleSpaceItemIdentifier])
        Check([item image] != nil && [item action] != NULL && [[item toolTip] length], @"toolbar items have image, action and tooltip");
    Check(fabs([mainSplit frame].size.height - [[window contentView] bounds].size.height) < 1, @"panes fill the window below the toolbar");
    Check(![projectWindow isBottomAreaVisible], @"bottom area starts hidden");
    CGFloat editorHeight = [editorPane frame].size.height;
    [projectWindow showProjectBuild:nil];
    NSView *buildView = [[project projectBuilder] componentView];
    Check([projectWindow isBottomAreaVisible] && [buildView window] == window, @"build output opens in the bottom area");
    Check([[[project projectEditor] componentView] window] == window, @"editor stays visible beside build output");
    NSRect buildFrame = [buildView convertRect:[buildView bounds] toView:nil];
    NSRect editorFrame = [editorPane convertRect:[editorPane bounds] toView:nil];
    Check(NSMaxY(buildFrame) <= NSMinY(editorFrame) + 1 && [editorPane frame].size.height < editorHeight, @"bottom area lies below the editor");
    [projectWindow showProjectLaunch:nil];
    Check([[[project projectLauncher] componentView] window] == window && [buildView window] == nil, @"run output replaces build output in the bottom area");
    [projectWindow toggleBottomArea:nil];
    Check(![projectWindow isBottomAreaVisible] && fabs([editorPane frame].size.height - editorHeight) < 1, @"hiding the bottom area returns the space to the editor");
    [projectWindow toggleBottomArea:nil];
    Check([projectWindow isBottomAreaVisible] && [[[project projectLauncher] componentView] window] == window, @"bottom area reopens with its last content");
    [projectWindow toggleNavigator:nil];
    Check(![projectWindow isNavigatorVisible] && [sidebar window] == nil && fabs([editorPane frame].size.width - [mainSplit bounds].size.width) < 1, @"hiding the navigator widens the editor");
    [projectWindow toggleNavigator:nil];
    Check([projectWindow isNavigatorVisible] && fabs([sidebar frame].size.width - sidebarWidth) < 1 && NSMaxX([sidebar frame]) <= NSMinX([[editorPane superview] frame]), @"navigator returns at its width on the left");
    [projectWindow showProjectBuild:nil];
    const char *preview = getenv("PC_SOURCE_OUTLINE_PREVIEW");
    if (preview)
    {
      [sourceTree setPath:sourcePath]; [sourceTree click:outline];
      [outline scrollRowToVisible:0];
      PumpEvents(0.5);
      GtkWindow *host = GTK4NativeHostForWindow(window);
      NSView *decoration = [window contentView];
      while ([decoration superview]) decoration = [decoration superview];
      Check([[decoration valueForKey:@"_nativeTables"] count] > 0, @"source outline uses GTK native rows");
      GdkSurface *surface = gtk_native_get_surface(GTK_NATIVE(host));
      Display *display = gdk_x11_display_get_xdisplay(gdk_surface_get_display(surface));
      Window xid = gdk_x11_surface_get_xid(surface);
      XWindowAttributes attributes; XGetWindowAttributes(display,xid,&attributes);
      cairo_surface_t *capture = cairo_xlib_surface_create(display,xid,attributes.visual,attributes.width,attributes.height);
      Check(cairo_surface_write_to_png(capture,preview) == CAIRO_STATUS_SUCCESS, @"source outline screenshot");
      cairo_surface_destroy(capture);
      GtkWidget *label = FindLabel(GTK_WIDGET(host),"GSGlyphInfo.m");
      Check(label != NULL, @"native source file label is visible");
      graphene_rect_t bounds;
      Check(gtk_widget_compute_bounds(label,GTK_WIDGET(host),&bounds), @"native row coordinates");
      GtkWidget *fileIcon = FindCustomIcon(gtk_widget_get_parent(label));
      Check(fileIcon != NULL, @"Objective-C source row uses custom artwork in a native image widget");
      GtkWidget *xibLabel = FindLabel(GTK_WIDGET(host),"GSDocument.xib");
      Check(xibLabel && FindCustomIcon(gtk_widget_get_parent(xibLabel)), @"localized XIB group uses the interface icon");
      Check(gdk_paintable_get_intrinsic_width(gtk_image_get_paintable(GTK_IMAGE(fileIcon))) <= gtk_widget_get_width(fileIcon)
            && gdk_paintable_get_intrinsic_height(gtk_image_get_paintable(GTK_IMAGE(fileIcon))) <= gtk_widget_get_height(fileIcon), @"native file artwork fits the row without clipping");
      Check(FindIcon(GTK_WIDGET(host),"folder-symbolic") != NULL, @"folders use desktop symbolic icons");
      graphene_rect_t iconBounds;
      Check(gtk_widget_compute_bounds(fileIcon,GTK_WIDGET(host),&iconBounds), @"source icon coordinates");
      Check(fabs((iconBounds.origin.y + iconBounds.size.height / 2) - (bounds.origin.y + bounds.size.height / 2)) <= 1, @"source icon and label have aligned centers");
      double dx,dy; gtk_native_get_surface_transform(GTK_NATIVE(host),&dx,&dy);
      int scale = gdk_surface_get_scale_factor(surface);
      int x,y; Window ignored;
      XTranslateCoordinates(display,xid,DefaultRootWindow(display),
                            lround((dx + bounds.origin.x + bounds.size.width / 2) * scale),
                            lround((dy + bounds.origin.y + bounds.size.height / 2) * scale),&x,&y,&ignored);
      void *xtst = dlopen("libXtst.so.6",RTLD_NOW);
      Check(xtst != NULL, @"XTest input library");
      int (*motion)(Display *,int,int,int,unsigned long) = dlsym(xtst,"XTestFakeMotionEvent");
      int (*button)(Display *,unsigned int,int,unsigned long) = dlsym(xtst,"XTestFakeButtonEvent");
      Check(motion && button, @"XTest pointer functions");
      GtkWidget *list = gtk_widget_get_ancestor(label,GTK_TYPE_LIST_VIEW);
      GtkWidget *scroller = gtk_widget_get_ancestor(list,GTK_TYPE_SCROLLED_WINDOW);
      Check(list && scroller, @"native source list and scroller");
      GtkWidget *row = label;
      while (gtk_widget_get_parent(row) && gtk_widget_get_parent(row) != list) row = gtk_widget_get_parent(row);
      NSLog(@"Sidebar row height: %d logical pixels",gtk_widget_get_height(row));
      Check(gtk_widget_get_height(row) <= 26, @"source rows use compact spacing");
      GtkAdjustment *adjustment = gtk_scrolled_window_get_vadjustment(GTK_SCROLLED_WINDOW(scroller));
      double scrollBefore = gtk_adjustment_get_value(adjustment);
      NSUInteger modelChanges = 0;
      GListModel *model = G_LIST_MODEL(gtk_list_view_get_model(GTK_LIST_VIEW(list)));
      gulong changesHandler = g_signal_connect(model,"items-changed",G_CALLBACK(CountSourceChanges),&modelChanges);
      motion(display,-1,x,y,CurrentTime);
      button(display,1,True,CurrentTime); button(display,1,False,CurrentTime); XFlush(display);
      PumpEvents(0.4);
      g_signal_handler_disconnect(model,changesHandler);
      NSLog(@"Source click: %lu model reloads, scroll %.2f -> %.2f",(unsigned long)modelChanges,scrollBefore,gtk_adjustment_get_value(adjustment));
      Check(modelChanges == 0, @"clicking a source file does not reload the sidebar");
      Check(fabs(gtk_adjustment_get_value(adjustment) - scrollBefore) < 0.5, @"clicking a visible file preserves sidebar scroll position");
      Check([[sourceTree nameOfSelectedFile] isEqual:@"EditGlyphData/GSGlyphInfo.m"], @"real native row click selects source");
      Check([[[[project projectEditor] activeEditor] path] isEqual:[root stringByAppendingPathComponent:@"EditGlyphData/GSGlyphInfo.m"]], @"real native row click opens source in editor");
    }
    Check([manager openProjectAt:[bundle stringByAppendingPathComponent:@"project.pbxproj"] makeActive:NO] == project, @"reopening pbxproj reuses project");
    Check([[manager loadedProjects] count] == 1, @"one loaded project");
    driver = [ProjectChooserDriver new];
    driver->projectPath = bundle;
    driver->selectionPath = [bundle stringByAppendingPathComponent:@"project.pbxproj"];
    driver->fileChooser = YES;
    chooserTimer = [NSTimer timerWithTimeInterval:0.15 target:driver selector:@selector(advance:) userInfo:nil repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:chooserTimer forMode:NSModalPanelRunLoopMode];
    [manager openFile];
    [chooserTimer invalidate];
    Check(driver->selectedProject, @"selected pbxproj through native File Open");
    Check([manager activeProject] == project && [[manager loadedProjects] count] == 1, @"File Open routes pbxproj to existing project");
    Check([[[manager editorManager] allEditors] count] == 0, @"File Open did not create a pbxproj text editor");
    [manager openFileAtPath:bundle];
    Check([manager activeProject] == project && [[manager loadedProjects] count] == 1, @"direct folder file-open routing");
    [driver release];
    Check([[project pathForFile:@"EditGlyphData/Base.lproj/MainMenu.xib" forKey:@"INTERFACES"] isEqual:[root stringByAppendingPathComponent:@"EditGlyphData/Base.lproj/MainMenu.xib"]], @"resource path stays source-root-relative");
    NSString *xibPath = [root stringByAppendingPathComponent:@"EditGlyphData/Base.lproj/MainMenu.xib"];
    NSData *originalXib = [NSData dataWithContentsOfFile:xibPath];
    NSString *interfacePath = [sourceTree categoryPathForFilePath:xibPath];
    Check([sourceTree setPath:interfacePath], @"select XIB in source navigator");
    [sourceTree click:outline];
    id interfaceEditor = [[project projectEditor] activeEditor];
    Check([interfaceEditor isKindOfClass:[PCInterfaceEditor class]], @"single XIB selection opens visual editor");
    Check([[interfaceEditor componentView] window] == window, @"visual editor is embedded in project window");
    PumpEvents(0.1);
    NSOutlineView *objectTree = [interfaceEditor valueForKey:@"tree"];
    Check([objectTree isKindOfClass:[NSOutlineView class]], @"interface objects use NSOutlineView");
    id fileItem = [objectTree itemAtRow:0];
    Check([[fileItem valueForKey:@"title"] isEqual:@"MainMenu.xib"]
          && [fileItem valueForKey:@"icon"] != nil, @"outline has a file root and icon");
    id menuItem = [objectTree itemAtRow:[objectTree selectedRow]];
    Check([objectTree parentForItem:menuItem] == fileItem && [objectTree isExpandable:menuItem], @"interface menu is an expandable child of the file");
    GtkWindow *interfaceHost = GTK4NativeHostForWindow(window);
    GtkWidget *menuLabel = FindLabel(GTK_WIDGET(interfaceHost),"Main Menu (menu)");
    Check(menuLabel && gtk_widget_get_ancestor(menuLabel,GTK_TYPE_LIST_VIEW), @"theme supplies native interface outline rows");
    GtkWidget *nativeList = gtk_widget_get_ancestor(menuLabel,GTK_TYPE_LIST_VIEW);
    GtkWidget *nativeRow = menuLabel;
    while (gtk_widget_get_parent(nativeRow) != nativeList) nativeRow = gtk_widget_get_parent(nativeRow);
    Check(FindIcon(nativeRow,"open-menu-symbolic") != NULL, @"interface item uses native symbolic icon");
    GtkWidget *disclosure = FindIcon(nativeRow,"pan-end-symbolic");
    Check(disclosure != NULL, @"collapsed subtree has native disclosure control");
    NSInteger collapsedRows = [objectTree numberOfRows];
    g_signal_emit_by_name(gtk_widget_get_ancestor(disclosure,GTK_TYPE_BUTTON),"clicked");
    PumpEvents(0.1);
    Check([objectTree isItemExpanded:menuItem] && [objectTree numberOfRows] > collapsedRows, @"native disclosure opens interface subtree");
    menuLabel = FindLabel(GTK_WIDGET(interfaceHost),"Main Menu (menu)");
    nativeRow = menuLabel;
    while (gtk_widget_get_parent(nativeRow) != nativeList) nativeRow = gtk_widget_get_parent(nativeRow);
    disclosure = FindIcon(nativeRow,"pan-down-symbolic");
    Check(disclosure != NULL, @"expanded subtree has native disclosure control");
    g_signal_emit_by_name(gtk_widget_get_ancestor(disclosure,GTK_TYPE_BUTTON),"clicked");
    PumpEvents(0.1);
    Check(![objectTree isItemExpanded:menuItem] && [objectTree numberOfRows] == collapsedRows, @"native disclosure closes interface subtree");
    Check([objectTree itemAtRow:[objectTree selectedRow]] == menuItem, @"toggling subtree preserves selected interface object");
    NSView *interfaceCanvas = [interfaceEditor editorView];
    NSSize viewport = [[interfaceCanvas enclosingScrollView] contentSize];
    Check([interfaceCanvas frame].size.width >= viewport.width && [interfaceCanvas frame].size.height >= viewport.height, @"interface canvas fills resized editor viewport");
    const char *xibPreview = getenv("PC_XIB_PREVIEW");
    if (xibPreview)
    {
      GtkWindow *host = GTK4NativeHostForWindow(window);
      GdkSurface *surface = gtk_native_get_surface(GTK_NATIVE(host));
      Display *display = gdk_x11_display_get_xdisplay(gdk_surface_get_display(surface));
      Window xid = gdk_x11_surface_get_xid(surface);
      XWindowAttributes attributes; XGetWindowAttributes(display,xid,&attributes);
      cairo_surface_t *capture = cairo_xlib_surface_create(display,xid,attributes.visual,attributes.width,attributes.height);
      Check(cairo_surface_write_to_png(capture,xibPreview) == CAIRO_STATUS_SUCCESS, @"embedded interface screenshot");
      cairo_surface_destroy(capture);
    }
    [sourceTree doubleClick:outline];
    Check([[project projectEditor] activeEditor] == interfaceEditor && ![interfaceEditor isWindowed], @"double-click reuses embedded XIB editor");
    Check([[NSData dataWithContentsOfFile:xibPath] isEqual:originalXib], @"viewing real XIB does not rewrite it");

    /* Use a disposable document for edits; never rewrite the sample project. */
    NSString *fixture = @"<?xml version=\"1.0\"?><document type=\"com.apple.InterfaceBuilder3.Cocoa.XIB\" useAutolayout=\"YES\"><objects><window id=\"win\" title=\"Window\"><view key=\"contentView\" id=\"view\"><rect key=\"frame\" x=\"0\" y=\"0\" width=\"400\" height=\"300\"/><subviews><button id=\"button\" customClass=\"MyButton\"><rect key=\"frame\" x=\"20\" y=\"30\" width=\"100\" height=\"24\"/><buttonCell title=\"Original\" id=\"cell\"/><connections><action selector=\"clicked:\" target=\"owner\" id=\"action\"/></connections></button></subviews><constraints><constraint firstItem=\"button\" firstAttribute=\"width\" constant=\"100\" id=\"constraint\"/></constraints></view></window><customObject id=\"owner\" customClass=\"Controller\"><connections><outlet property=\"button\" destination=\"button\" id=\"outlet\"/></connections></customObject></objects><customMetadata value=\"keep me\"/></document>";
    NSString *fixturePath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                             [NSString stringWithFormat:@"projectcenter-%@.xib",[[NSProcessInfo processInfo] globallyUniqueString]]];
    Check([fixture writeToFile:fixturePath atomically:YES encoding:NSUTF8StringEncoding error:NULL], @"write XIB fixture");
    PCInterfaceEditor *fixtureEditor = [[PCInterfaceEditor alloc] init];
    Check([fixtureEditor openFileAtPath:fixturePath editorManager:nil editable:YES] != nil, @"open editable interface fixture");
    NSXMLDocument *xml = [fixtureEditor valueForKey:@"document"];
    NSXMLElement *button = [[xml nodesForXPath:@"//*[@id='button']" error:NULL] objectAtIndex:0];
    [fixtureEditor selectObject:button];
    NSOutlineView *fixtureTree = [fixtureEditor valueForKey:@"tree"];
    id buttonItem = [fixtureTree itemAtRow:[fixtureTree selectedRow]];
    id viewItem = [fixtureTree parentForItem:buttonItem];
    id windowItem = [fixtureTree parentForItem:viewItem];
    Check([[[viewItem valueForKey:@"element"] attributeForName:@"id"].stringValue isEqual:@"view"]
          && [[[windowItem valueForKey:@"element"] attributeForName:@"id"].stringValue isEqual:@"win"], @"outline skips XML wrappers and keeps object hierarchy");
    Check([fixtureTree levelForItem:buttonItem] == 3, @"nested object has real outline depth");
    [fixtureTree collapseItem:windowItem];
    Check([fixtureTree rowForItem:buttonItem] < 0, @"closing parent hides nested objects");
    [fixtureEditor selectObject:button];
    Check([fixtureTree isItemExpanded:windowItem] && [fixtureTree isItemExpanded:viewItem]
          && [fixtureTree itemAtRow:[fixtureTree selectedRow]] == buttonItem, @"canvas selection reveals collapsed ancestors and selects matching row");
    NSMutableArray *propertyFields = [NSMutableArray array];
    for (NSView *view in [[fixtureEditor componentView] subviews])
      if ([view isKindOfClass:[NSTextField class]] && [(NSTextField *)view isEditable]) [propertyFields addObject:view];
    Check([propertyFields count] == 5, @"title and four frame properties are available");
    [[propertyFields objectAtIndex:0] setStringValue:@"Edited & preserved"];
    [[propertyFields objectAtIndex:1] setStringValue:@"42"];
    [fixtureEditor applyProperties:nil];
    Check([fixtureTree isItemExpanded:windowItem] && [fixtureTree isItemExpanded:viewItem], @"property edit preserves subtree expansion");
    Check([fixtureEditor isEdited] && [fixtureEditor saveFile], @"visual edits mark document dirty and save successfully");
    NSXMLDocument *saved = [[[NSXMLDocument alloc] initWithContentsOfURL:[NSURL fileURLWithPath:fixturePath] options:0 error:NULL] autorelease];
    Check([[saved nodesForXPath:@"//*[@id='cell' and @title='Edited & preserved']" error:NULL] count] == 1, @"edited title survives XML escaping and reload");
    Check([[saved nodesForXPath:@"//*[@id='button']/rect[@x='42']" error:NULL] count] == 1, @"edited frame survives reload");
    Check([[saved nodesForXPath:@"//*[@id='action' and @selector='clicked:' and @target='owner'] | //*[@id='outlet' and @destination='button'] | //*[@id='constraint' and @constant='100'] | //customMetadata[@value='keep me'] | //*[@id='button' and @customClass='MyButton']" error:NULL] count] == 5, @"save preserves actions, outlets, constraints, custom classes and unknown metadata");
    [[propertyFields objectAtIndex:0] setStringValue:@"Unsaved"];
    [fixtureEditor applyProperties:nil];
    Check([fixtureEditor revertFileToSaved] && ![fixtureEditor isEdited], @"revert reloads saved visual document");
    xml = [fixtureEditor valueForKey:@"document"];
    button = [[xml nodesForXPath:@"//*[@id='button']" error:NULL] objectAtIndex:0];
    [fixtureEditor selectObject:button];
    Check([[[propertyFields objectAtIndex:0] stringValue] isEqual:@"Edited & preserved"], @"revert restores saved properties in inspector");
    [fixtureEditor release];
    PCInterfaceEditor *readOnlyEditor = [[PCInterfaceEditor alloc] init];
    NSData *savedBytes = [NSData dataWithContentsOfFile:fixturePath];
    Check([readOnlyEditor openFileAtPath:fixturePath editorManager:nil editable:NO] != nil, @"open read-only interface");
    [readOnlyEditor applyProperties:nil];
    Check(![readOnlyEditor isEdited] && ![readOnlyEditor saveFile]
          && [[NSData dataWithContentsOfFile:fixturePath] isEqual:savedBytes], @"read-only editor cannot change or save XIB");
    [readOnlyEditor setWindowed:YES]; [readOnlyEditor show];
    Check([readOnlyEditor isWindowed] && [[readOnlyEditor editorWindow] isVisible], @"standalone File Open can show a visual editor window");
    [readOnlyEditor closeFile:nil save:NO]; [readOnlyEditor release];
    [[NSFileManager defaultManager] removeItemAtPath:fixturePath error:NULL];
    Check([project save] && [project writeMakefile] && [project saveProjectWindowsAndPanels], @"safe save paths");
    Check(![project isEditableFile:@"project.pbxproj"], @"Xcode metadata is read-only");
    Check([project isEditableFile:@"GNUmakefile"], @"existing GNUstep build file remains editable");
    Check([[project projectEditor] openEditorForFilePath:[root stringByAppendingPathComponent:@"EditGlyphData/GSWindowController.m"] windowed:NO] != nil, @"open source in integrated editor");
    PumpEvents(0.2); // GTK allocates the newly selected editor before inspecting its geometry.
    Check([[sourceTree nameOfSelectedFile] isEqual:@"EditGlyphData/GSWindowController.m"], @"opening an editor reveals the matching outline file");
    id codeEditor = [[project projectEditor] activeEditor];
    NSScrollView *codeScroll = [[codeEditor editorView] enclosingScrollView];
    Check(![codeScroll hasHorizontalRuler] && [codeScroll hasVerticalRuler], @"code editor has line numbers but no tab ruler");
    NSPathControl *jumpBar = [codeEditor performSelector:@selector(jumpBar)];
    NSLog(@"Native editor geometry: jump=%@ scroll=%@ container=%@ flipped=%d",NSStringFromRect(jumpBar.frame),NSStringFromRect(codeScroll.frame),NSStringFromRect(jumpBar.superview.bounds),jumpBar.superview.isFlipped);
    Check([jumpBar window] == window && NSMaxY([jumpBar frame]) <= NSMaxY([[jumpBar superview] bounds])
          && NSMinY([jumpBar frame]) >= NSMaxY([codeScroll frame]) - 1, @"jump bar sits above the code");
    Check([[[jumpBar pathItems] valueForKey:@"title"] isEqual:(@[@"EditGlyphData", @"EditGlyphData", @"GSWindowController.m"])], @"jump bar shows project, group and file");
    Check([[[jumpBar pathItems] objectAtIndex:2] image] != nil, @"jump bar items have icons");
    [[jumpBar cell] setValue:[[[jumpBar cell] pathComponentCells] objectAtIndex:1] forKey:@"_clickedPathComponentCell"];
    [codeEditor performSelector:@selector(_jumpBarClicked:) withObject:jumpBar];
    Check([[sourceTree path] isEqual:@"/@EditGlyphData/EditGlyphData"] && [sourceTree nameOfSelectedFile] == nil, @"jump bar reveals a group in the navigator");
    PCProjectBuilder *builder = [project projectBuilder];
    [builder startBuild:nil];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:20];
    while ([builder isBuilding] && [deadline timeIntervalSinceNow] > 0)
      [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    Check(![builder isBuilding], @"integrated build completed");
    Check([[[builder valueForKey:@"statusField"] stringValue] rangeOfString:@"succeeded"].location != NSNotFound, @"integrated build script succeeded");
    NSString *executable = [[root stringByAppendingPathComponent:@"../../build/EditGlyphData/EditGlyphData.app/EditGlyphData"] stringByStandardizingPath];
    Check([[[project projectLauncher] executablePath] isEqual:executable], @"configured debugger executable");

    /* Debugger: breakpoints in Xcode's per-user data, sidebar tabs, a
     * session that stops at a line breakpoint and an exception breakpoint. */
    const char *debugTarget = getenv("PC_DEBUG_TARGET");
    if (debugTarget)
    {
      NSString *target = [NSString stringWithUTF8String:debugTarget];
      NSString *targetSource = [NSString stringWithUTF8String:getenv("PC_DEBUG_TARGET_SOURCE")];
      NSString *userData = [bundle stringByAppendingPathComponent:
                            [NSString stringWithFormat:@"xcuserdata/%@.xcuserdatad", NSUserName()]];
      NSString *store = [userData stringByAppendingPathComponent:@"ProjectCenter/Breakpoints.plist"];
      BOOL hadUserData = [[NSFileManager defaultManager] fileExistsAtPath:userData];
      NSArray *previous = [project breakpoints];
      PCBreakpointNavigator *breakpointsTab = [projectWindow breakpointNavigator];
      PCDebugNavigator *debugTab = [projectWindow debugNavigator];
      NSString *delegateFile = [root stringByAppendingPathComponent:@"EditGlyphData/GSAppDelegate.m"];
      NSUInteger logLine = 0, line = 0;

      for (NSString *text in [[NSString stringWithContentsOfFile:targetSource encoding:NSUTF8StringEncoding error:NULL]
                              componentsSeparatedByString:@"\n"])
      {
        line++;
        if ([text rangeOfString:@"NSLog"].location != NSNotFound) logLine = line;
      }
      for (NSDictionary *bp in previous)
        if ([bp objectForKey:@"Symbol"])
          [project setSymbolicBreakpoint:[bp objectForKey:@"Symbol"] kind:[bp objectForKey:@"Kind"] enabled:NO];
      else
        [project setBreakpointForFile:[project absolutePathForBreakpointFile:[bp objectForKey:@"File"]]
                                 line:[[bp objectForKey:@"Line"] unsignedIntegerValue] enabled:NO];

      Check([projectWindow selectedNavigatorIndex] == 0 && [[[project projectBrowser] view] window] == window, @"navigator tabs start on the project");
      [projectWindow selectNavigatorAtIndex:1];
      Check([projectWindow selectedNavigatorIndex] == 1 && [[breakpointsTab view] window] == window, @"breakpoints tab shows in the sidebar");
      [project setBreakpointForFile:delegateFile line:20 enabled:YES];
      [[NSNotificationCenter defaultCenter] postNotificationName:PCProjectBreakpointNotification
                                                          object:[NSDictionary dictionaryWithObjectsAndKeys:delegateFile, @"File", [NSNumber numberWithInt:20], @"Line", [NSNumber numberWithBool:YES], @"Enabled", nil]];
      Check([[NSFileManager defaultManager] fileExistsAtPath:store], @"breakpoints stored in xcuserdata");
      Check(![[NSFileManager defaultManager] fileExistsAtPath:[root stringByAppendingPathComponent:@"Breakpoints.plist"]], @"source tree stays free of breakpoint files");
      NSArray *rows = [breakpointsTab rootItems];
      Check([rows count] == 1 && [[[rows objectAtIndex:0] title] isEqual:@"GSAppDelegate.m"]
            && [[[[[rows objectAtIndex:0] children] objectAtIndex:0] title] hasPrefix:@"Line 20"], @"breakpoints tab lists file breakpoints by file");
      NSOutlineView *bpOutline = [breakpointsTab outlineView];
      [bpOutline selectRowIndexes:[NSIndexSet indexSetWithIndex:1] byExtendingSelection:NO];
      [breakpointsTab removeSelectedBreakpoint:nil];
      Check(![project hasBreakpointForFile:delegateFile line:20] && [[breakpointsTab rootItems] count] == 0, @"breakpoints tab deletes a breakpoint");

      [breakpointsTab addExceptionBreakpoint:nil];
      Check([project hasSymbolicBreakpoint:@"objc_exception_throw"]
            && [[[[breakpointsTab rootItems] objectAtIndex:0] title] isEqual:@"Objective-C Exception"], @"exception breakpoint in the breakpoints tab");
      [project setBreakpointForFile:targetSource line:logLine enabled:YES];

      NSMutableDictionary *dict = (NSMutableDictionary *)[project projectDict];
      id configured = [[dict objectForKey:@"XCODE_Executable"] retain];
      [dict setObject:target forKey:@"XCODE_Executable"];
      PCProjectLauncher *launcher = [project projectLauncher];
      [projectWindow performSelector:@selector(toolbarRun:) withObject:nil];
      Check([launcher isDebugging] && [launcher debugger] != nil, @"Run starts a debug session");
      Check([[[launcher debugger] debugAreaView] window] == window && [projectWindow isBottomAreaVisible], @"debug console and controls in the bottom area");
      NSDate *until = [NSDate dateWithTimeIntervalSinceNow:30];
      while ([[debugTab frames] count] == 0 && [until timeIntervalSinceNow] > 0) PumpEvents(0.1);
      NSArray *frames = [debugTab frames];
      Check([frames count] > 0, @"stopped at the line breakpoint");
      Check([projectWindow selectedNavigatorIndex] == 2, @"debug tab opens when the program pauses");
      NSDictionary *top = [frames objectAtIndex:[debugTab selectedFrameIndex]];
      Check([[top objectForKey:@"Function"] isEqual:@"main"] && [[top objectForKey:@"Line"] unsignedIntegerValue] == logLine, @"line breakpoint frame selected");
      Check([[[[project projectEditor] activeEditor] path] isEqual:targetSource], @"editor shows the paused line");

      [[launcher debugger] continueExecution:nil];
      until = [NSDate dateWithTimeIntervalSinceNow:30];
      BOOL atException = NO;
      while (!atException && [until timeIntervalSinceNow] > 0)
      {
        PumpEvents(0.1);
        for (NSDictionary *frame in [debugTab frames])
          if ([[frame objectForKey:@"Function"] isEqual:@"objc_exception_throw"]) atException = YES;
      }
      Check(atException, @"exception breakpoint stops in objc_exception_throw");
      frames = [debugTab frames];
      Check([[[frames valueForKey:@"Function"] componentsJoinedByString:@" "] rangeOfString:@"Raise"].location != NSNotFound, @"traceback includes the raising function");
      PCNavigatorItem *thread = [[debugTab rootItems] objectAtIndex:0];
      Check([[thread title] hasSuffix:@"Objective-C exception"] && [[thread children] count] == [frames count], @"debug tab shows the thread and its frames");
      NSUInteger raiseIndex = [[frames valueForKey:@"Function"] indexOfObject:@"Raise"];
      NSOutlineView *stack = [debugTab outlineView];
      [stack selectRowIndexes:[NSIndexSet indexSetWithIndex:[stack rowForItem:[[thread children] objectAtIndex:raiseIndex]]] byExtendingSelection:NO];
      PumpEvents(0.3);
      Check([[[[project projectEditor] activeEditor] path] isEqual:targetSource], @"selecting a frame shows its source");

      const char *debugPreview = getenv("PC_DEBUG_PREVIEW");
      if (debugPreview)
      {
        PumpEvents(0.5);
        GtkWindow *host = GTK4NativeHostForWindow(window);
        GdkSurface *surface = gtk_native_get_surface(GTK_NATIVE(host));
        Display *display = gdk_x11_display_get_xdisplay(gdk_surface_get_display(surface));
        Window xid = gdk_x11_surface_get_xid(surface);
        XWindowAttributes attributes; XGetWindowAttributes(display, xid, &attributes);
        cairo_surface_t *capture = cairo_xlib_surface_create(display, xid, attributes.visual, attributes.width, attributes.height);
        Check(cairo_surface_write_to_png(capture, debugPreview) == CAIRO_STATUS_SUCCESS, @"debugger screenshot");
        cairo_surface_destroy(capture);
      }
      [launcher performStop];
      until = [NSDate dateWithTimeIntervalSinceNow:15];
      while ([launcher isDebugging] && [until timeIntervalSinceNow] > 0) PumpEvents(0.1);
      Check(![launcher isDebugging], @"Stop ends the debug session");

      if (configured) [dict setObject:configured forKey:@"XCODE_Executable"]; else [dict removeObjectForKey:@"XCODE_Executable"];
      [configured release];
      [project setSymbolicBreakpoint:@"objc_exception_throw" kind:PCBreakpointKindException enabled:NO];
      [project setBreakpointForFile:targetSource line:logLine enabled:NO];
      for (NSDictionary *bp in previous)
        if ([bp objectForKey:@"Symbol"])
          [project setSymbolicBreakpoint:[bp objectForKey:@"Symbol"] kind:[bp objectForKey:@"Kind"] enabled:YES];
      else
        [project setBreakpointForFile:[project absolutePathForBreakpointFile:[bp objectForKey:@"File"]]
                                 line:[[bp objectForKey:@"Line"] unsignedIntegerValue] enabled:YES];
      if (!hadUserData)
        [[NSFileManager defaultManager] removeItemAtPath:userData error:NULL];
      [projectWindow selectNavigatorAtIndex:0];
    }

    [manager closeProject:project];
    Check([[manager loadedProjects] count] == 0, @"close removes imported project");
    for (NSString *file in protected)
      Check([[NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:file]] isEqual:[snapshots objectForKey:file]], [@"unchanged: " stringByAppendingString:file]);
    Check([[NSSet setWithArray:originalFiles] isEqual:[NSSet setWithArray:[[NSFileManager defaultManager] directoryContentsAtPath:root]]], @"opening and saving created no project or build files");
    NSLog(@"Xcode ProjectCenter integration passed: open, reuse, resource paths, source editor, build, save, launch path, close, unchanged metadata/build files");
  }
  return 0;
}
