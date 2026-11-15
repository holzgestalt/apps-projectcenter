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
#include <gtk/gtk.h>
#include <gdk/x11/gdkx.h>
#include <cairo-xlib.h>
#include <dlfcn.h>
extern GtkWindow *GTK4NativeHostForWindow(NSWindow *window);

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
      NSRect enlarged = [window frame]; enlarged.size.width += 120; enlarged.size.height += 80;
      [window setFrame:enlarged display:YES];
      Check(fabs([sidebar frame].size.width - sidebarWidth) < 1, @"window resize preserves sidebar width");
      Check(fabs([sidebar frame].size.height - [editorPane frame].size.height) < 1, @"sidebar and editor fill available height");
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
      Check([project save] && [project writeMakefile] && [project saveProjectWindowsAndPanels], @"safe save paths");
      Check(![project isEditableFile:@"project.pbxproj"], @"Xcode metadata is read-only");
      Check([project isEditableFile:@"GNUmakefile"], @"existing GNUstep build file remains editable");
      Check([[project projectEditor] openEditorForFilePath:[root stringByAppendingPathComponent:@"EditGlyphData/GSWindowController.m"] windowed:NO] != nil, @"open source in integrated editor");
      Check([[sourceTree nameOfSelectedFile] isEqual:@"EditGlyphData/GSWindowController.m"], @"opening an editor reveals the matching outline file");
      id codeEditor = [[project projectEditor] activeEditor];
      NSScrollView *codeScroll = [[codeEditor editorView] enclosingScrollView];
      Check(![codeScroll hasHorizontalRuler] && [codeScroll hasVerticalRuler], @"code editor has line numbers but no tab ruler");
      NSPathControl *jumpBar = [codeEditor performSelector:@selector(jumpBar)];
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
