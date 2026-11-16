/*
   GNUstep ProjectCenter - http://www.gnustep.org/experience/ProjectCenter.html

   Copyright (C) 2000-2023 Free Software Foundation

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
#import <ProjectCenter/PCButton.h>

#import <ProjectCenter/PCProjectManager.h>
#import <ProjectCenter/PCProject.h>

#import <ProjectCenter/PCProjectWindow.h>
#import <ProjectCenter/PCProjectBrowser.h>
#import <ProjectCenter/PCProjectEditor.h>
#import <ProjectCenter/PCProjectBuilder.h>
#import <ProjectCenter/PCProjectLauncher.h>
#import <ProjectCenter/PCProjectLoadedFiles.h>
#import <ProjectCenter/PCProjectInspector.h>
#import "PCNavigators.h"
#import "PCXcodeProjectEditor.h"

#import <Protocols/Preferences.h>
#import <Protocols/CodeEditorView.h>
#import <ProjectCenter/PCLogController.h>

#import "Modules/Preferences/Misc/PCMiscPrefs.h"


#import <math.h>

@interface PCProjectWindow (Layout)
- (void)_createToolbar;
- (void)_createNavigatorArea;
- (void)_setBottomAreaVisible:(BOOL)visible;
- (void)_showInBottomArea:(NSView *)view;
- (void)resizeContentSubviews;
- (void)resizeHorizontalSubiewsWithOldSize:(NSSize)oldSize;
@end

@implementation PCProjectWindow

// ============================================================================
// ==== Intialization & deallocation
// ============================================================================

- (void)_createCustomView
{
  customView = [[NSBox alloc] initWithFrame:NSMakeRect(-1,-1,562,252)];
  [customView setTitlePosition:NSNoTitle];
  [customView setBorderType:NSNoBorder];
  [customView setContentViewMargins:NSMakeSize(0.0,0.0)];
  [customView setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];

  // Editor in the Box
  [customView setContentView:[[project projectEditor] componentView]];

  /* Editor above, build/run output below. The bottom area joins the split
   * only while it is shown. */
  contentSplit = [[NSSplitView alloc] initWithFrame:NSMakeRect(0,0,562,252)];
  [contentSplit setVertical:NO];
  [contentSplit setDelegate:self];
  [contentSplit setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
  [contentSplit addSubview:customView];
  RELEASE(customView);

  bottomView = [[NSBox alloc] initWithFrame:NSMakeRect(0,0,562,220)];
  [bottomView setTitlePosition:NSNoTitle];
  [bottomView setBorderType:NSNoBorder];
  [bottomView setContentViewMargins:NSMakeSize(0.0,0.0)];
  bottomHeight = 220;

  [h_split addSubview:contentSplit];
  RELEASE(contentSplit);
  [self resizeHorizontalSubiewsWithOldSize:NSZeroSize];
}

// ============================================================================
// ==== Navigators
// ============================================================================

- (void)_createNavigatorArea
{
  NSRect frame = NSMakeRect(0, 0, 240, 400);
  NSArray *images = [NSArray arrayWithObjects:@"GSNavigatorProjectTemplate",
    @"GSNavigatorBreakpointsTemplate", @"GSNavigatorDebugTemplate", nil];
  NSArray *labels = [NSArray arrayWithObjects:@"Project", @"Breakpoints", @"Debug", nil];
  NSArray *views;
  NSInteger i;

  navigatorArea = [[NSView alloc] initWithFrame:frame];
  [navigatorArea setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

  navigatorSelector = [[[NSSegmentedControl alloc] initWithFrame:
    NSMakeRect(8, NSHeight(frame) - 30, 120, 24)] autorelease];
  [navigatorSelector setSegmentCount:[images count]];
  for (i = 0; i < [images count]; i++)
    {
      [navigatorSelector setImage:[NSImage imageNamed:[images objectAtIndex:i]] forSegment:i];
      [navigatorSelector setWidth:36 forSegment:i];
      [[navigatorSelector cell] setToolTip:[labels objectAtIndex:i] forSegment:i];
    }
  [[navigatorSelector cell] setTrackingMode:NSSegmentSwitchTrackingSelectOne];
  [navigatorSelector setSelectedSegment:0];
  [navigatorSelector setTarget:self];
  [navigatorSelector setAction:@selector(navigatorSelectorChanged:)];
  [navigatorSelector setAutoresizingMask:NSViewMaxXMargin | NSViewMinYMargin];
  [navigatorArea addSubview:navigatorSelector];

  navigatorTabs = [[[NSTabView alloc] initWithFrame:
    NSMakeRect(0, 0, NSWidth(frame), NSHeight(frame) - 36)] autorelease];
  [navigatorTabs setTabViewType:NSNoTabsNoBorder];
  [navigatorTabs setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  breakpointNavigator = [[PCBreakpointNavigator alloc] initWithProject:project];
  debugNavigator = [[PCDebugNavigator alloc] initWithProject:project];
  views = [NSArray arrayWithObjects:[[project projectBrowser] view],
    [breakpointNavigator view], [debugNavigator view], nil];
  for (i = 0; i < [views count]; i++)
    {
      NSTabViewItem *item = [[[NSTabViewItem alloc] initWithIdentifier:[labels objectAtIndex:i]] autorelease];
      [item setLabel:[labels objectAtIndex:i]];
      [item setView:[views objectAtIndex:i]];
      [navigatorTabs addTabViewItem:item];
    }
  [navigatorArea addSubview:navigatorTabs];

  [[NSNotificationCenter defaultCenter] addObserver:self
    selector:@selector(debuggerStateDidChange:)
        name:PCDebuggerStateDidChangeNotification object:nil];
}

- (void)navigatorSelectorChanged:(id)sender
{
  [self selectNavigatorAtIndex:[navigatorSelector selectedSegment]];
}

- (void)selectNavigatorAtIndex:(NSInteger)index
{
  if (index < 0 || index >= [navigatorTabs numberOfTabViewItems]) return;
  if ([navigatorSelector selectedSegment] != index)
    [navigatorSelector setSelectedSegment:index];
  [navigatorTabs selectTabViewItemAtIndex:index];
}

- (NSInteger)selectedNavigatorIndex
{
  return [navigatorTabs indexOfTabViewItem:[navigatorTabs selectedTabViewItem]];
}

- (id)breakpointNavigator { return breakpointNavigator; }
- (id)debugNavigator { return debugNavigator; }

- (void)debuggerStateDidChange:(NSNotification *)aNotif
{
  if ([aNotif object] != [[project projectLauncher] debugger])
    {
      return;
    }
  /* Like Xcode: show the call stack whenever the program pauses. */
  if ([[[aNotif userInfo] objectForKey:@"State"] isEqual:PCDebuggerStateStopped])
    {
      [self selectNavigatorAtIndex:2];
    }
}

- (void)showProjectOverview
{
  if (![[project projectDict] objectForKey:@"XCODE_PROJECT_PATH"])
    {
      return;
    }
  if (xcodeProjectEditor == nil)
    {
      xcodeProjectEditor = [[PCXcodeProjectEditor alloc] initWithProject:project];
    }
  [xcodeProjectEditor reload];
  [self setCustomContentView:[xcodeProjectEditor view]];
}

- (id)xcodeProjectEditor
{
  return xcodeProjectEditor;
}

- (void)showDebugArea:(NSView *)view
{
  [self _showInBottomArea:view];
}

// ============================================================================
// ==== Toolbar
// ============================================================================

static NSString * const PCToolbarRun = @"PCToolbarRun";
static NSString * const PCToolbarStop = @"PCToolbarStop";
static NSString * const PCToolbarBuild = @"PCToolbarBuild";
static NSString * const PCToolbarClean = @"PCToolbarClean";
static NSString * const PCToolbarFind = @"PCToolbarFind";
static NSString * const PCToolbarNavigator = @"PCToolbarNavigator";
static NSString * const PCToolbarBottomArea = @"PCToolbarBottomArea";
static NSString * const PCToolbarInspector = @"PCToolbarInspector";

- (void)_createToolbar
{
  NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"PCProjectWindowToolbar"];
  [toolbar setDelegate:(id)self];
  [toolbar setAllowsUserCustomization:YES];
  [toolbar setDisplayMode:NSToolbarDisplayModeIconOnly];
  [projectWindow setToolbar:toolbar];
  RELEASE(toolbar);
}

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar
{
  return [NSArray arrayWithObjects:PCToolbarRun, PCToolbarStop, PCToolbarBuild,
    PCToolbarClean, PCToolbarFind, PCToolbarNavigator,
    PCToolbarBottomArea, PCToolbarInspector, NSToolbarFlexibleSpaceItemIdentifier,
    NSToolbarSpaceItemIdentifier, NSToolbarSeparatorItemIdentifier, nil];
}

- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar
{
  return [NSArray arrayWithObjects:PCToolbarRun, PCToolbarStop, PCToolbarBuild,
    NSToolbarFlexibleSpaceItemIdentifier, PCToolbarNavigator,
    PCToolbarBottomArea, PCToolbarInspector, nil];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
     itemForItemIdentifier:(NSString *)identifier
 willBeInsertedIntoToolbar:(BOOL)flag
{
  NSDictionary *items = [NSDictionary dictionaryWithObjectsAndKeys:
    @[@"Run", @"Run the application", @"toolbarRun:", @"NSTouchBarPlayTemplate"], PCToolbarRun,
    @[@"Stop", @"Stop the running build or application", @"toolbarStop:", @"NSTouchBarRecordStopTemplate"], PCToolbarStop,
    @[@"Build", @"Build the project", @"toolbarBuild:", @"GSBuildTemplate"], PCToolbarBuild,
    @[@"Clean", @"Clean the project", @"toolbarClean:", @"NSTouchBarDeleteTemplate"], PCToolbarClean,
    @[@"Find", @"Find in project", @"toolbarFind:", @"NSTouchBarSearchTemplate"], PCToolbarFind,
    @[@"Navigator", @"Hide or show the navigator", @"toggleNavigator:", @"NSTouchBarSidebarTemplate"], PCToolbarNavigator,
    @[@"Debug Area", @"Hide or show build and run output", @"toggleBottomArea:", @"GSBottomPaneTemplate"], PCToolbarBottomArea,
    @[@"Inspector", @"Show the project inspector", @"showProjectInspector:", @"GSInspectorPaneTemplate"], PCToolbarInspector,
    nil];
  NSArray *description = [items objectForKey:identifier];
  if (!description) return nil;
  NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier:identifier] autorelease];
  NSString *artwork = [description objectAtIndex:3];
  [item setLabel:[description objectAtIndex:0]];
  [item setPaletteLabel:[description objectAtIndex:0]];
  [item setToolTip:[description objectAtIndex:1]];
  [item setTarget:self];
  [item setAction:NSSelectorFromString([description objectAtIndex:2])];
  [item setImage:[NSImage imageNamed:artwork]];
  return item;
}

- (BOOL)validateToolbarItem:(NSToolbarItem *)item
{
  NSString *identifier = [item itemIdentifier];
  PCProjectBuilder *builder = [project projectBuilder];
  PCProjectLauncher *launcher = [project projectLauncher];
  BOOL building = [builder isBuilding] || [builder isCleaning];
  BOOL running = [launcher isRunning] || [launcher isDebugging];

  if ([identifier isEqual:PCToolbarRun])
    return [project isExecutable] && !running && !building;
  if ([identifier isEqual:PCToolbarStop]) return building || running;
  if ([identifier isEqual:PCToolbarBuild] || [identifier isEqual:PCToolbarClean])
    return !building;
  return YES;
}

- (void)toolbarBuild:(id)sender
{
  [self showProjectBuild:self];
  [[project projectBuilder] performStartBuild];
}

- (void)toolbarClean:(id)sender
{
  [self showProjectBuild:self];
  [[project projectBuilder] performStartClean];
}

- (void)toolbarRun:(id)sender
{
  /* Like Xcode, Run starts the program under the debugger. */
  [[project projectLauncher] performDebug];
}

- (void)toolbarStop:(id)sender
{
  PCProjectBuilder *builder = [project projectBuilder];
  if ([builder isBuilding] || [builder isCleaning]) [builder performStopBuild];
  else [[project projectLauncher] performStop];
}

- (void)toolbarFind:(id)sender
{
  [NSApp sendAction:@selector(findShowPanel:) to:nil from:self];
}

- (void)awakeFromNib
{
  id <PCPreferences> prefs = [[project projectManager] prefController];
  NSRect rect;

  [buildButton setToolTip:@"Project Builder"];
  [buildButton setImage:IMAGE(@"Build")];

  [launchButton setToolTip:@"Project Launcher"];
  [launchButton setImage:IMAGE(@"Run")];
  if (![project isExecutable])
    {
      [launchButton setEnabled:NO];
    }

  [loadedFilesButton setToolTip:@"Loaded Files"];
  [loadedFilesButton setImage:IMAGE(@"Files")];
  if (![prefs boolForKey:UseTearOffWindows])
    {
      [loadedFilesButton setEnabled:NO];
    }

  [findButton setToolTip:@"Project Finder"];
  [findButton setImage:IMAGE(@"Find")];

  [inspectorButton setToolTip:@"Project Inspector"];
  [inspectorButton setImage:IMAGE(@"Inspector")];

  [fileIcon setFileNameField:fileIconTitle];
  [fileIcon setDelegate:[project projectBrowser]];
  [fileIcon updateIcon];

  [statusLine setStringValue:@""];
    
  /*
   * Horizontal split view
   */
  /* The window toolbar replaces the nib's button row; the navigator and
   * editor fill the window. The nib's views stay alive for their outlets. */
  RETAIN(toolbarView);
  RETAIN(statusLine);
  for (NSView *view in [NSArray arrayWithArray:[[projectWindow contentView] subviews]])
    if (view != h_split) [view removeFromSuperview];
  [h_split setFrame:[[projectWindow contentView] bounds]];
  [h_split setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [self _createToolbar];
  [h_split setDelegate:self];
  [h_split setVertical:YES];

  /*
   * Vertical split view
   */
  rect = [h_split bounds];
  CGFloat savedWidth = [[[[project projectDict] objectForKey:PCWindows] objectForKey:@"SourceOutlineWidth"] doubleValue];
  rect.size.width = savedWidth > 0 ? savedWidth : 240;
  v_split = [[NSSplitView alloc] initWithFrame:rect];
  [v_split setAutoresizingMask:NSViewHeightSizable];
  [v_split setVertical:NO];
  [v_split setDelegate:self];

  /*
   * Navigators: project files, breakpoints and the debugger's call stack
   */
  [self _createNavigatorArea];
  browserView = navigatorArea;
  [v_split addSubview:browserView];
  
  /*
   * LoadedFiles
   */
  if (![prefs boolForKey:UseTearOffWindows])
    {
      [self showProjectLoadedFiles:self];
    }

  [h_split addSubview:v_split];
  RELEASE(v_split);

  /*
   * Custom view
   * View where non-separated Builder, Launcher, Editor goes.
   */ 
  [self _createCustomView];
}

- (id)initWithProject:(PCProject *)owner 
{
  if ((self = [super init]))
    {
      NSDictionary *pcWindows;
      NSString     *windowFrame;

      project = owner;
      _isToolbarVisible = YES;
      _splitViewsRestored = NO;

      if (projectWindow == nil)
	{
	  if ([NSBundle loadNibNamed:@"ProjectWindow" owner:self] == NO)
	    {
	      PCLogError(self, @"error loading ProjectWindow NIB file!");
	      return nil;
	    }
	}
      [self setTitle];
      
      // Window
      [projectWindow setFrameAutosaveName:@"ProjectWindow"];

      pcWindows = [[project projectDict] objectForKey:PCWindows];
      windowFrame = [pcWindows objectForKey:@"ProjectWindow"];
//      PCLogInfo(self, @"window frame %@", windowFrame);
      if (windowFrame != nil)
	{
	  PCLogStatus(self, @"PCProjectWindow: set frame from project");
	  [projectWindow setFrameFromString:windowFrame];
	}
      else if (![projectWindow setFrameUsingName: @"ProjectWindow"])
	{
	  [projectWindow center];
	}
	
      // Toolbar
      if ([[pcWindows objectForKey:@"ShowToolbar"] isEqualToString:@"NO"])
	{
	  [self toggleToolbar];
	}

      // Project dictionary
      [[NSNotificationCenter defaultCenter] 
	addObserver:self
	   selector:@selector(projectDictDidChange:)
	       name:PCProjectDictDidChangeNotification
	     object:nil];

      [[NSNotificationCenter defaultCenter] 
	addObserver:self
	   selector:@selector(projectDictDidSave:)
	       name:PCProjectDictDidSaveNotification
	     object:nil];

      // Active project changing
      [[NSNotificationCenter defaultCenter] 
	addObserver:self
	   selector:@selector(activeProjectDidChange:)
	       name:PCActiveProjectDidChangeNotification
	     object:nil];
	     
      // ProjectCenter preferences
      [[NSNotificationCenter defaultCenter] 
	addObserver:self
	   selector:@selector(preferencesDidChange:)
	       name:PCPreferencesDidChangeNotification
	     object:nil];
	     
      // Track Browser selection changes for file icon updates
      [[NSNotificationCenter defaultCenter] 
	addObserver:self
	   selector:@selector (browserDidSetPath:)
	       name:PCBrowserDidSetPathNotification
	     object:[project projectBrowser]];

      // Editor changes
      [[NSNotificationCenter defaultCenter] 
	addObserver:self
	   selector:@selector (editorDidChange:)
	       name:PCEditorDidChangeNotification
	     object:nil];
      [[NSNotificationCenter defaultCenter] 
	addObserver:self
	   selector:@selector (editorDidSave:)
	       name:PCEditorDidSaveNotification
	     object:nil];
      [[NSNotificationCenter defaultCenter] 
	addObserver:self
	   selector:@selector (editorDidRevert:)
	       name:PCEditorDidRevertNotification
	     object:nil];
    }
  
  return self;
}

- (void)setTitle
{
  NSString *name = [project projectName];
  NSString *path = [[project projectPath] stringByAbbreviatingWithTildeInPath];
  NSString *language = [[project projectDict] objectForKey:PCLanguage];

  [projectWindow 
    setTitle:[NSString stringWithFormat:@"%@ - %@ [%@]",name,path,language]];
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [h_split setDelegate:nil];
  [v_split setDelegate:nil];
  [contentSplit setDelegate:nil];
  [[projectWindow toolbar] setDelegate:nil];
  [projectWindow close];
  RELEASE(bottomView);
  RELEASE(navigatorArea);
  RELEASE(breakpointNavigator);
  RELEASE(debugNavigator);
  RELEASE(xcodeProjectEditor);
  RELEASE(toolbarView);
  RELEASE(statusLine);

  [super dealloc];
}

// ============================================================================
// ==== Accessory methods
// ============================================================================

// TODO: Should be removed when two modes will be implemented:
// Build, Launch and Loaded Files are tear-off and tear-on.
// Custom view is always shown because editor always opened on
// one click in Browser. External editor will be opened only on
// double click.
- (NSView *)customContentView
{
  return [customView contentView];
}

- (void)setCustomContentView:(NSView *)subview
{
  if (!customView)
    {
      return;
    }

  [customView setContentView:subview];
  [customView display];
}

- (void)updateStatusLineWithText:(NSString *)text
{
  [statusLine setStringValue:text];
}

// ============================================================================
// ==== Actions
// ============================================================================

- (void)showProjectBuild:(id)sender
{
  id <PCPreferences> prefs = [[project projectManager] prefController];
  NSView             *view = [[project projectBuilder] componentView];
  NSPanel            *buildPanel = [[project projectManager] buildPanel];
  PCProject          *rootActiveProject;

  rootActiveProject = [[project projectManager] rootActiveProject];
  
//  NSLog(@"ProjectWindow showProjectBuild: componentView RC:%i", 
//	[view retainCount]);

  if ([prefs boolForKey:UseTearOffWindows])
    {
      if ([bottomView contentView] == view)
	{
	  [self _setBottomAreaVisible:NO];
	}
      if (rootActiveProject == project)
	{
	  [buildPanel orderFront:nil];
	}
    }
  else
    {
      if ((rootActiveProject == project) && [buildPanel isVisible])
	{
	  [buildPanel close];
	}
      [self _showInBottomArea:view];
    }
}

- (void)showProjectLaunch:(id)sender
{
  id <PCPreferences> prefs = [[project projectManager] prefController];
  NSView             *view = nil;
  NSPanel            *launchPanel = nil;

  view = [[project projectLauncher] componentView];
  launchPanel = [[project projectManager] launchPanel];

  if ([prefs boolForKey:UseTearOffWindows])
    {
      if ([bottomView contentView] == view)
	{
	  [self _setBottomAreaVisible:NO];
	}
      [launchPanel orderFront:nil];
    }
  else
    {
      if ([launchPanel isVisible])
	{
	  [launchPanel close];
	}
      [self _showInBottomArea:view];
    }
}

- (void)showProjectLoadedFiles:(id)sender
{
  id <PCPreferences> prefs = [[project projectManager] prefController];
  NSPanel            *panel = [[project projectManager] loadedFilesPanel];
  PCProject          *rootActiveProject;
  NSScrollView       *componentView;

  rootActiveProject = [[project projectManager] rootActiveProject];
  componentView = (NSScrollView *)[[project projectLoadedFiles] componentView];
      
//  PCLogInfo(self, @"showProjectLoadedFiles");

  if ([prefs boolForKey:UseTearOffWindows])
    {
      [componentView setBorderType:NSNoBorder];
      [componentView removeFromSuperview];
      if (rootActiveProject == project)
	{
	  [panel orderFront:nil];
	}
      [v_split adjustSubviews];
    }
  else
    {
      if ((rootActiveProject == project) && panel && [panel isVisible])
	{
	  [panel close];
	}

      [componentView setBorderType:NSBezelBorder];
      // Preserve width of view in panel
//      [componentView setFrame:NSMakeRect(0,0,128,130)];
      [v_split addSubview:componentView];
      [v_split adjustSubviews];
    }
}

- (void)showProjectInspector:(id)sender
{
  [[project projectManager] showProjectInspector:sender];
}

- (void)showProjectEditor:(id)sender
{
  [self setCustomContentView:[[project projectEditor] componentView]];
  [self makeFirstResponder:firstResponder];
}

- (void)_setBottomAreaVisible:(BOOL)visible
{
  if (visible == [self isBottomAreaVisible]) return;
  if (visible)
    {
      [contentSplit addSubview:bottomView];
    }
  else
    {
      bottomHeight = [bottomView frame].size.height;
      [bottomView removeFromSuperview];
    }
  [self resizeContentSubviews];
  [contentSplit setNeedsDisplay:YES];
}

- (void)_showInBottomArea:(NSView *)view
{
  if ([bottomView contentView] != view) [bottomView setContentView:view];
  [self _setBottomAreaVisible:YES];
}

- (BOOL)isBottomAreaVisible
{
  return [bottomView superview] == contentSplit;
}

- (void)toggleBottomArea:(id)sender
{
  if ([self isBottomAreaVisible])
    {
      [self _setBottomAreaVisible:NO];
    }
  else if ([[[bottomView contentView] subviews] count])
    {
      [self _setBottomAreaVisible:YES];
    }
  else
    {
      [self showProjectBuild:self];
    }
}

- (BOOL)isNavigatorVisible
{
  return [v_split superview] == h_split;
}

- (void)toggleNavigator:(id)sender
{
  if ([self isNavigatorVisible])
    {
      RETAIN(v_split);
      [v_split removeFromSuperview];
    }
  else
    {
      [h_split addSubview:v_split positioned:NSWindowBelow relativeTo:contentSplit];
      RELEASE(v_split);
    }
  [self resizeHorizontalSubiewsWithOldSize:NSZeroSize];
  [h_split setNeedsDisplay:YES];
}

- (BOOL)isToolbarVisible
{
  return [[projectWindow toolbar] isVisible];
}

- (void)toggleToolbar
{
  NSToolbar *toolbar = [projectWindow toolbar];
  [toolbar setVisible:![toolbar isVisible]];
  _isToolbarVisible = [toolbar isVisible];
}

// ============================================================================
// ==== Notifications
// ============================================================================

- (void)projectDictDidChange:(NSNotification *)aNotif
{
  NSDictionary *notifObject = [aNotif object];
  PCProject    *changedProject = [notifObject objectForKey:@"Project"];

  if (changedProject != project 
      && changedProject != [project activeSubproject])
    {
      return;
    }
    
  [self setTitle];

  // TODO: if window isn't visible and "edited" attribute set, after ordering
  // front window doesn't show broken close button. Fix it in GNUstep.
  // Workaround is in windowDidBecomeKey.
  [projectWindow setDocumentEdited:YES];
}

- (void)projectDictDidSave:(NSNotification *)aNotif
{
  PCProject *savedProject = [aNotif object];
  
  if (savedProject != project 
      && savedProject != [project activeSubproject]
      && [savedProject superProject] != [project activeSubproject])
    {
      return;
    }

  [projectWindow setDocumentEdited:NO];
}

- (void)activeProjectDidChange:(NSNotification *)aNotif 
{
/*  PCProject *activeProject = [aNotif object];
  
  if (activeProject != project 
      && activeProject != [project activeSubproject]
      && [activeProject superProject] != [project activeSubproject])
    {
      return;
    }

  [self makeKeyWindow];*/
}

// TODO: Review determining of tear-off panels. Current implementation
// loads Build, Launch and Loaded Files to check visibility status.
// It is incorrect behaviour; Build. Launch and LoadedFiles initialized
// even if not in use.
- (void)preferencesDidChange:(NSNotification *)aNotif
{
  id <PCPreferences> prefs = [aNotif object];
 
  NSLog(@"ProjectWindow: Preferences did change");

/*  if ([[project projectManager] rootActiveProject] != project)
    {
      return;
    }*/

  if ([prefs boolForKey:UseTearOffWindows])
    {
      // Project Build 
      if ([[[project projectBuilder] componentView] window] == projectWindow)
	{
	  [self showProjectBuild:self];
	}
      // Project Launch
      if ([[[project projectLauncher] componentView] window] == projectWindow)
	{
	  [self showProjectLaunch:self];
	}
      // Loaded Files
      if ([[v_split subviews] count] == 2)
	{
	  [self showProjectLoadedFiles:self];
	}
      [loadedFilesButton setEnabled:YES];
    }
  else
    {
      NSPanel *buildPanel = [[project projectManager] buildPanel];
      NSPanel *launchPanel = [[project projectManager] launchPanel];
      
      // Project Build 
      if ([buildPanel isVisible] == YES)
	{
	  [self showProjectBuild:self];
	}
      // Project Launch
      if ([launchPanel isVisible] == YES)
	{
	  [self showProjectLaunch:self];
	}
      // Loaded Files
      if ([[v_split subviews] count] == 1)
	{
	  [self showProjectLoadedFiles:self];
	}
      [loadedFilesButton setEnabled:NO];
    }
}

- (void)browserDidSetPath:(NSNotification *)aNotif
{
  PCProjectBrowser *browser = [aNotif object];

  if (browser != [project projectBrowser])
    {
      return;
    }
  
  [fileIcon updateIcon];
}

- (void)editorDidChange:(NSNotification *)aNotif
{
  id<CodeEditor> editor = [aNotif object];
  
  if ([editor editorManager] != [project projectEditor])
    {
      return;
    }

  [fileIcon updateIcon];
}

- (void)editorDidSave:(NSNotification *)aNotif
{
  id<CodeEditor> editor = [aNotif object];
  
  if ([editor editorManager] != [project projectEditor])
    {
      return;
    }

  [fileIcon updateIcon];
}

- (void)editorDidRevert:(NSNotification *)aNotif
{
  id<CodeEditor> editor = [aNotif object];
  
  if ([editor editorManager] != [project projectEditor])
    {
      return;
    }

  [fileIcon updateIcon];
}

// ============================================================================
// ==== Window delegate
// ============================================================================

- (NSString *)stringWithSavedFrame
{
  return [projectWindow stringWithSavedFrame];
}

- (void)makeKeyAndOrderFront:(id)sender
{
//  PCLogInfo(self, @"makeKeyAndOrderFront % @ sender: %@", [projectWindow title], [sender className]);
//  NSLog(@"makeKeyAndOrderFront %@ sender: %@", [projectWindow title], [sender className]);
  [projectWindow makeKeyAndOrderFront:self];
}

- (void)makeKeyWindow
{
  [projectWindow makeKeyWindow];
}

- (void)orderFront:(id)sender
{
  if (projectWindow)
    {
      [projectWindow orderFront:sender];
    }
}

- (void)center
{
  [projectWindow center];
}

// [NSWindow close] doesn't send windowShouldClose
- (void)close
{
  [projectWindow close];
}

- (void)performClose:(id)sender
{
  [projectWindow performClose:sender];
}

- (BOOL)isDocumentEdited 
{
  return [projectWindow isDocumentEdited];
}

- (BOOL)isKeyWindow
{
  return [projectWindow isKeyWindow];
}

- (BOOL)makeFirstResponder:(NSResponder *)aResponder
{
  firstResponder = aResponder;
  [projectWindow makeFirstResponder:firstResponder];

  return YES;
}

- (void)windowDidBecomeKey:(NSNotification *)aNotification
{
  [projectWindow makeMainWindow];
//  [projectWindow makeFirstResponder:(NSResponder *)firstResponder];

/*  PCLogInfo(self, @"windowDidBecomeKey: activeSubproject %@",
	    [[project activeSubproject] projectName]);*/

  if ([[project projectManager] rootActiveProject] != project)
    {
      if ([project activeSubproject] != nil)
	{
	  [[project projectManager] 
	    setActiveProject:[project activeSubproject]];
	}
      else
	{
	  [[project projectManager] setActiveProject:project];
	}
    }

  // Workaround
  if ([projectWindow isDocumentEdited])
    {
      [projectWindow setDocumentEdited:NO];
      [projectWindow setDocumentEdited:YES];
    }
}

- (void)windowDidResignKey:(NSNotification *)aNotification
{
//  [projectWindow makeFirstResponder:nil];
}

- (void)windowDidBecomeMain:(NSNotification *)aNotification
{
}

- (BOOL)windowShouldClose:(id)sender
{
  return [project close:self];
}

- (void)windowWillClose:(NSNotification *)aNotification
{
}

- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window
{
  id responder;

  responder = [window firstResponder];
  if ([responder conformsToProtocol: @protocol(CodeEditorView)])
    {
      return [[responder editor] windowWillReturnUndoManager: window];
    }
  return nil;
}

// ============================================================================
// ==== SplitView delegate
// ============================================================================

// Sidebar: source outline above the optional loaded-files list.
- (void)resizeVerticalSubiewsWithOldSize:(NSSize)oldSize
{
  NSSize size = [v_split bounds].size;
  NSArray *views = [v_split subviews];
  if ([views count] < 2)
    {
      [browserView setFrame:NSMakeRect(0,0,size.width,size.height)];
      return;
    }
  NSView *loaded = [views objectAtIndex:1];
  CGFloat divider = [v_split dividerThickness];
  CGFloat loadedHeight = [loaded frame].size.height;
  if (loadedHeight <= 0) loadedHeight = 140;
  loadedHeight = MIN(MAX(80,loadedHeight),size.height * 0.4);
  CGFloat outlineHeight = MAX(0,size.height - divider - loadedHeight);
  BOOL flipped = [v_split isFlipped];
  [browserView setFrame:NSMakeRect(0,flipped ? 0 : loadedHeight + divider,size.width,outlineHeight)];
  [loaded setFrame:NSMakeRect(0,flipped ? outlineHeight + divider : 0,size.width,loadedHeight)];
}

// Main split: a fixed-width source sidebar on the left, flexible content right.
- (void)resizeHorizontalSubiewsWithOldSize:(NSSize)oldSize
{
  if (!v_split || !contentSplit) return;
  NSSize size = [h_split bounds].size;
  if (![self isNavigatorVisible])
    {
      [contentSplit setFrame:NSMakeRect(0,0,size.width,size.height)];
      [self resizeContentSubviews];
      return;
    }
  CGFloat divider = [h_split dividerThickness];
  CGFloat width = [v_split frame].size.width;
  if (width <= 0) width = 240;
  width = MIN(MAX(160,width),MAX(100,size.width - divider - 220));
  [v_split setFrame:NSMakeRect(0,0,width,size.height)];
  [contentSplit setFrame:NSMakeRect(width + divider,0,MAX(0,size.width - width - divider),size.height)];
  [self resizeVerticalSubiewsWithOldSize:NSZeroSize];
  [self resizeContentSubviews];
  _splitViewsRestored = YES;
}

// Content: the editor takes what the bottom area leaves.
- (void)resizeContentSubviews
{
  if (!contentSplit || !customView) return;
  NSSize size = [contentSplit bounds].size;
  if (![self isBottomAreaVisible])
    {
      [customView setFrame:NSMakeRect(0,0,size.width,size.height)];
      return;
    }
  CGFloat divider = [contentSplit dividerThickness];
  CGFloat height = [bottomView frame].size.height;
  if (height <= 0 || [bottomView frame].size.width <= 0) height = bottomHeight;
  height = MAX(0,MIN(MAX(80,height),size.height - divider - 120));
  CGFloat editorHeight = MAX(0,size.height - divider - height);
  BOOL flipped = [contentSplit isFlipped];
  [customView setFrame:NSMakeRect(0,flipped ? 0 : height + divider,size.width,editorHeight)];
  [bottomView setFrame:NSMakeRect(0,flipped ? editorHeight + divider : 0,size.width,height)];
}

- (CGFloat)splitView:(NSSplitView *)split constrainMinCoordinate:(CGFloat)proposed ofSubviewAt:(NSInteger)index
{
  if (split == contentSplit) return MAX(120,proposed);
  return split == h_split ? MAX(160,proposed) : MAX(80,proposed);
}

- (CGFloat)splitView:(NSSplitView *)split constrainMaxCoordinate:(CGFloat)proposed ofSubviewAt:(NSInteger)index
{
  return split == h_split ? MIN(proposed,[split bounds].size.width - 220) : MIN(proposed,[split bounds].size.height - 80);
}

- (void)         splitView:(NSSplitView *)sender
 resizeSubviewsWithOldSize:(NSSize)oldSize
{
  if (sender == contentSplit)
    {
      [self resizeContentSubviews];
    }
  else if (sender == v_split)
    {
      [self resizeVerticalSubiewsWithOldSize:oldSize];
    }
  else
    {
      [self resizeHorizontalSubiewsWithOldSize:oldSize];
    }

  return;
}

@end

