/*
 **  PCDebugger.m
 **
 **  Copyright (c) 2008-2021
 **
 **  Author: Gregory Casamento <greg.casamento@gmail.com>
 **          Riccardo Mottola <rm@gnu.org>>
 **
 **  This program is free software; you can redistribute it and/or modify
 **  it under the terms of the GNU General Public License as published by
 **  the Free Software Foundation; either version 2 of the License, or
 **  (at your option) any later version.
 **
 **  This program is distributed in the hope that it will be useful,
 **  but WITHOUT ANY WARRANTY; without even the implied warranty of
 **  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 **  GNU General Public License for more details.
 **
 **  You should have received a copy of the GNU General Public License
 **  along with this program; if not, write to the Free Software
 **  Foundation, Inc., 31 Milk Street #960789 Boston, MA 02196 USA
 */

#ifdef	__MINGW32__
#undef _WIN32_WINNT
#define _WIN32_WINNT 0x0501 // Minimal target is Windows XP

#include <windows.h>

#endif

#import <AppKit/AppKit.h>
#import "PCDebugger.h"
#import "PCDebuggerView.h"

#import <ProjectCenter/PCProject.h>
#import <ProjectCenter/PCProjectBrowser.h>
#import <ProjectCenter/PCProjectEditor.h>
#import <ProjectCenter/PCProjectManager.h>
#import <Protocols/CodeEditor.h>
#import <ProjectCenter/PCEditorManager.h>
#import "PCAppController.h"

#import "Modules/Preferences/EditorFSC/PCEditorFSCPrefs.h"
#import "PCDebuggerWrapperProtocol.h"
#import "GDBWrapper.h"


#ifndef NOTIFICATION_CENTER
#define NOTIFICATION_CENTER [NSNotificationCenter defaultCenter]
#endif

static NSImage	*goImage = nil;
static NSImage	*pauseImage = nil;
static NSImage	*continueImage = nil;
static NSImage	*restartImage = nil;
static NSImage	*nextImage = nil;
static NSImage  *stepInImage = nil;
static NSImage  *stepOutImage = nil;
static NSImage  *upImage = nil;
static NSImage  *downImage = nil;

NSString *PCBreakTypeKey = @"BreakType";
NSString *PCBreakTypeByLine = @"BreakTypeLine";
NSString *PCBreakTypeMethod = @"BreakTypeMethod";
NSString *PCBreakMethod = @"BreakMethod";
NSString *PCBreakFilename = @"BreakFilename";
NSString *PCBreakLineNumber = @"BreakLineNumber";
NSString *PCDBDebuggerStartedNotification = @"PCDBDebuggerStartedNotification";

@interface PCDebugger (Session)
- (void)_updateControls;
- (void)_terminateDebugger;
- (void)go:(id)sender;
- (void)continue:(id)sender;
- (void)next:(id)sender;
@end

@implementation PCDebugger
+ (void) initialize
{
  if (self == [PCDebugger class])
  {
    NSBundle	*bundle;
    NSString	*path;

    bundle = [NSBundle bundleForClass: self];
    path = [bundle pathForImageResource: @"go_button"];
    if (path != nil)
    {
      goImage = [[NSImage alloc] initWithContentsOfFile: path];
    }
    path = [bundle pathForImageResource: @"pause_button"];
    if (path != nil)
    {
      pauseImage = [[NSImage alloc] initWithContentsOfFile: path];
    }
    path = [bundle pathForImageResource: @"continue_button"];
    if (path != nil)
    {
      continueImage = [[NSImage alloc] initWithContentsOfFile: path];
    }
    path = [bundle pathForImageResource: @"restart_button"];
    if (path != nil)
    {
      restartImage = [[NSImage alloc] initWithContentsOfFile: path];
    }
    path = [bundle pathForImageResource: @"next_button"];
    if (path != nil)
    {
      nextImage = [[NSImage alloc] initWithContentsOfFile: path];
    }
    path = [bundle pathForImageResource: @"stepin_button"];
    if (path != nil)
    {
      stepInImage = [[NSImage alloc] initWithContentsOfFile: path];
    }
    path = [bundle pathForImageResource: @"stepout_button"];
    if (path != nil)
    {
      stepOutImage = [[NSImage alloc] initWithContentsOfFile: path];
    }
    path = [bundle pathForImageResource: @"up_button"];
    if (path != nil)
    {
      upImage = [[NSImage alloc] initWithContentsOfFile: path];
    }
    path = [bundle pathForImageResource: @"down_button"];
    if (path != nil)
    {
      downImage = [[NSImage alloc] initWithContentsOfFile: path];
    }
  }
}

- (NSFont *)consoleFont
{
  NSUserDefaults *defs;
  NSString       *fontName;
  CGFloat         fontSize;
  NSFont         *font = nil;

  defs = [NSUserDefaults standardUserDefaults];
  fontName = [defs stringForKey:ConsoleFixedFont];
  fontSize = [defs floatForKey:ConsoleFixedFontSize];

  font = [NSFont fontWithName:fontName size:fontSize];
  if (font == nil)
    font = [NSFont userFixedPitchFontOfSize:0];

  return font;
}

- (id) init
{
  if((self = [super init]) != nil)
  {
    // initialization here...
    if([NSBundle loadNibNamed: @"PCDebugger" owner: self] == NO)
    {
      return nil;
    }

    [(PCDebuggerView *)debuggerView setDebugger:self];
    debuggerWrapper = [[GDBWrapper alloc] init];
    [debuggerWrapper setTextView:debuggerView];
    [debuggerWrapper setDebugger:self];
    [debuggerView setFont: [self consoleFont]];

    subProcessId = 0;
    lastInfoParsed = nil;
    lastFileNameParsed = nil;
    lastLineNumberParsed = NSNotFound;

    breakpoints = nil;
    breakpointNumbers = [[NSMutableDictionary alloc] init];
    symbolNumbers = [[NSMutableDictionary alloc] init];
    state = [PCDebuggerStateExited copy];

    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(handleNotification:)
                                                 name: PCDBDebuggerStartedNotification
                                               object: debuggerWrapper];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleBreakpointNotification:)
                                                 name:PCProjectBreakpointNotification
                                               object:nil];
  }
  return self;
}

-(void) debugExecutableAtPath: (NSString *)filePath
                 withDebugger: (NSString *)debugger
{
  ASSIGN(executablePath,filePath);
  [debuggerWrapper setDebuggerPath: debugger];
  [debuggerWindow setTitle: [NSString stringWithFormat: @"Debugger (%@)",filePath]];
  [self show];
}

- (void) show
{
  [debuggerWindow makeKeyAndOrderFront: self];
  if (![debuggerWrapper debuggerStarted])
    [self startDebugger];
}

- (void) startDebugger
{
  [debuggerView runProgram: executablePath
        inCurrentDirectory: [executablePath stringByDeletingLastPathComponent]
          logStandardError: YES];

}

- (void) initBreakpoints
{
  NSArray *savedBreakpoints;
  NSEnumerator *e;
  NSDictionary *savedBreakpoint;
  PCProject *project;

  RELEASE(breakpoints);
  breakpoints = [[NSMutableArray alloc] init];
  project = [self _project];
  savedBreakpoints = [project breakpoints];
  e = [savedBreakpoints objectEnumerator];
  while ((savedBreakpoint = [e nextObject]) != nil)
  {
    NSString *fileName;
    NSNumber *lineNumber;
    NSDictionary *bp;

    fileName = [project absolutePathForBreakpointFile:
                [savedBreakpoint objectForKey:@"File"]];
    lineNumber = [savedBreakpoint objectForKey:@"Line"];
    if (fileName == nil || lineNumber == nil ||
        ![project canSetBreakpointForFile:fileName
                                     line:[lineNumber unsignedIntegerValue]])
    {
      continue;
    }

    bp = [NSDictionary dictionaryWithObjectsAndKeys:
          PCBreakTypeByLine, PCBreakTypeKey,
          fileName, PCBreakFilename,
          lineNumber, PCBreakLineNumber,
          nil];
    [breakpoints addObject:bp];
  }
  for (NSDictionary *symbolic in [project symbolicBreakpoints])
  {
    [breakpoints addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                            PCBreakTypeMethod, PCBreakTypeKey,
                            [symbolic objectForKey:@"Symbol"], PCBreakMethod,
                            nil]];
  }
  /* CRUDE EXAMPLES * TODO FIXME *
   NSDictionary *dP;
   NSLog(@"initing breakpoints");

   dP = [NSDictionary dictionaryWithObjectsAndKeys: PCBreakTypeMethod, PCBreakTypeKey, @"[NSException raise]", PCBreakMethod, nil];
   //  [breakpoints addObject:dP];
   dP = [NSDictionary dictionaryWithObjectsAndKeys: PCBreakTypeByLine, PCBreakTypeKey, @"AppController.m", PCBreakFilename, [NSNumber numberWithInt:100], PCBreakLineNumber, nil];
   [breakpoints addObject:dP];
   */
  [debuggerWrapper setBreakpoints:breakpoints];
}

- (void) debuggerSetup
{
  [debuggerWrapper debuggerSetup];
}

- (void) handleNotification: (NSNotification *)notification
{
  [self debuggerSetup];
  [self initBreakpoints];
  if (runWhenReady)
  {
    runWhenReady = NO;
    [self go:self];
  }
}

- (void)handleBreakpointNotification:(NSNotification *)notification
{
  NSDictionary *info;
  NSString *fileName;
  NSNumber *lineNumber;
  NSNumber *enabled;
  NSDictionary *bp;
  BOOL enableBreakpoint;

  info = [notification object];
  if (![info isKindOfClass:[NSDictionary class]])
  {
    return;
  }
  if ([[info objectForKey:@"FromDebugger"] boolValue])
  {
    return;
  }
  if ([[info objectForKey:@"Symbol"] isKindOfClass:[NSString class]])
  {
    NSString *symbol = [info objectForKey:@"Symbol"];
    BOOL on = [[info objectForKey:@"Enabled"] boolValue];

    if (![debuggerWrapper debuggerStarted])
    {
      return;
    }
    if (on)
    {
      [debuggerWrapper setBreakpoints:[NSArray arrayWithObject:
                                       [NSDictionary dictionaryWithObjectsAndKeys:
                                        PCBreakTypeMethod, PCBreakTypeKey, symbol, PCBreakMethod, nil]]];
    }
    else if ([symbolNumbers objectForKey:symbol])
    {
      [debuggerWrapper putString:[NSString stringWithFormat:@"-break-delete %@\n",
                                  [symbolNumbers objectForKey:symbol]]];
      [symbolNumbers removeObjectForKey:symbol];
    }
    return;
  }

  fileName = [info objectForKey:@"File"];
  lineNumber = [info objectForKey:@"Line"];
  enabled = [info objectForKey:@"Enabled"];
  if (![fileName isKindOfClass:[NSString class]] ||
      ![lineNumber isKindOfClass:[NSNumber class]])
  {
    return;
  }
  enableBreakpoint = (enabled == nil || [enabled boolValue]);
  if (enableBreakpoint)
  {
    PCProject *project;

    project = [self _project];
    if (project != nil &&
        ![project canSetBreakpointForFile:fileName
                                     line:[lineNumber unsignedIntegerValue]])
    {
      return;
    }
  }

  bp = [NSDictionary dictionaryWithObjectsAndKeys:
        PCBreakTypeByLine, PCBreakTypeKey,
        AUTORELEASE([fileName copy]), PCBreakFilename,
        lineNumber, PCBreakLineNumber,
        nil];
  if (breakpoints == nil)
  {
    breakpoints = [[NSMutableArray alloc] init];
  }

  if (enableBreakpoint)
  {
    if (![breakpoints containsObject:bp])
    {
      [breakpoints addObject:bp];
    }
    if ([debuggerWrapper debuggerStarted])
    {
      [debuggerWrapper setBreakpoints:[NSArray arrayWithObject:bp]];
    }
  }
  else
  {
    [breakpoints removeObject:bp];
    if ([debuggerWrapper debuggerStarted])
    {
      NSString *command;

      command = [NSString stringWithFormat:
                 @"-interpreter-exec console \"clear %@:%@\"\n",
                 fileName, lineNumber];
      [debuggerWrapper putString:command];
    }
  }
}

- (void)recordBreakpointNumber:(NSString *)number
                          file:(NSString *)file
                          line:(NSUInteger)line
{
  NSDictionary *bp;
  PCProject *project;

  if (![number isKindOfClass:[NSString class]] ||
      ![file isKindOfClass:[NSString class]] ||
      line == 0)
  {
    return;
  }

  project = [self _project];
  if (project != nil && ![project canSetBreakpointForFile:file line:line])
  {
    [debuggerWrapper putString:
     [NSString stringWithFormat:@"-break-delete %@\n", number]];
    return;
  }

  bp = [NSDictionary dictionaryWithObjectsAndKeys:
        PCBreakTypeByLine, PCBreakTypeKey,
        AUTORELEASE([file copy]), PCBreakFilename,
        [NSNumber numberWithUnsignedInteger:line], PCBreakLineNumber,
        nil];

  [breakpointNumbers setObject:bp forKey:number];
  if (breakpoints == nil)
  {
    breakpoints = [[NSMutableArray alloc] init];
  }
  if (![breakpoints containsObject:bp])
  {
    [breakpoints addObject:bp];
  }

  if (project != nil)
  {
    [project setBreakpointForFile:file line:line enabled:YES];
  }

  [[NSNotificationCenter defaultCenter]
   postNotificationName:PCProjectBreakpointNotification
   object:[NSDictionary dictionaryWithObjectsAndKeys:
           file, @"File",
           [NSNumber numberWithUnsignedInteger:line], @"Line",
           [NSNumber numberWithBool:YES], @"Enabled",
           [NSNumber numberWithBool:YES], @"FromDebugger",
           nil]];
}

- (void)removeBreakpointNumber:(NSString *)number
{
  NSDictionary *bp;
  NSString *file;
  NSNumber *line;
  PCProject *project;

  if (![number isKindOfClass:[NSString class]])
  {
    return;
  }

  bp = RETAIN([breakpointNumbers objectForKey:number]);
  if (bp == nil)
  {
    return;
  }

  file = RETAIN([bp objectForKey:PCBreakFilename]);
  line = RETAIN([bp objectForKey:PCBreakLineNumber]);
  if (![file isKindOfClass:[NSString class]] ||
      ![line isKindOfClass:[NSNumber class]])
  {
    [breakpointNumbers removeObjectForKey:number];
    [breakpoints removeObject:bp];
    RELEASE(file);
    RELEASE(line);
    RELEASE(bp);
    return;
  }

  [breakpointNumbers removeObjectForKey:number];
  if (breakpoints != nil)
  {
    [breakpoints removeObject:bp];
  }

  project = [self _project];
  if (project != nil)
  {
    [project setBreakpointForFile:file line:[line unsignedIntegerValue] enabled:NO];
  }

  [[NSNotificationCenter defaultCenter]
   postNotificationName:PCProjectBreakpointNotification
   object:[NSDictionary dictionaryWithObjectsAndKeys:
           file, @"File",
           line, @"Line",
           [NSNumber numberWithBool:NO], @"Enabled",
           [NSNumber numberWithBool:YES], @"FromDebugger",
           nil]];

  RELEASE(file);
  RELEASE(line);
  RELEASE(bp);
}


// ===========================================================================
// ==== Integrated session
// ===========================================================================

- (BOOL)isLineBreakpointRecord:(NSDictionary *)bkpt
{
  NSString *location = [bkpt objectForKey:@"original-location"];

  /* Symbolic breakpoints also resolve to a file and line; only those set
   * on a line belong in the editor gutter. */
  if ([location isKindOfClass:[NSString class]] && [location length])
  {
    NSRange colon = [location rangeOfString:@":" options:NSBackwardsSearch];
    return colon.location != NSNotFound
    && [[location substringFromIndex:NSMaxRange(colon)] intValue] > 0;
  }
  return YES;
}

- (void)recordSymbolicBreakpoint:(NSDictionary *)bkpt
{
  NSString *number = [bkpt objectForKey:@"number"];
  NSString *location = [bkpt objectForKey:@"original-location"];

  if (![location isKindOfClass:[NSString class]])
  {
    location = [bkpt objectForKey:@"pending"];
  }
  if ([number isKindOfClass:[NSString class]] && [location isKindOfClass:[NSString class]]
      && ![self isLineBreakpointRecord:bkpt])
  {
    [symbolNumbers setObject:number forKey:location];
  }
}

- (void)_postState:(NSString *)newState info:(NSDictionary *)extra
{
  NSMutableDictionary *info = [NSMutableDictionary dictionaryWithObject:newState forKey:@"State"];

  ASSIGN(state, newState);
  if (extra)
  {
    [info addEntriesFromDictionary:extra];
  }
  [self _updateControls];
  [[NSNotificationCenter defaultCenter]
   postNotificationName:PCDebuggerStateDidChangeNotification
   object:self
   userInfo:info];
}

- (NSDictionary *)_stoppedInfo
{
  NSMutableDictionary *info = [NSMutableDictionary dictionary];
  NSDictionary *frame = selectedFrame < [frames count] ? [frames objectAtIndex:selectedFrame] : nil;

  [info setObject:(frames ? frames : [NSArray array]) forKey:@"Frames"];
  [info setObject:[NSNumber numberWithUnsignedInteger:selectedFrame] forKey:@"SelectedFrame"];
  if (stopReason)
  {
    [info setObject:stopReason forKey:@"Reason"];
  }
  if ([frame objectForKey:@"File"])
  {
    [info setObject:[frame objectForKey:@"File"] forKey:@"File"];
    [info setObject:[frame objectForKey:@"Line"] forKey:@"Line"];
  }
  return info;
}

- (void)setProject:(id)aProject
{
  project = aProject;
}

- (PCProject *)_project
{
  if (project)
  {
    return project;
  }
  return [[(PCAppController *)[NSApp delegate] projectManager] rootActiveProject];
}

- (void)debuggerDidStop:(NSDictionary *)info
{
  NSString *reason = [info objectForKey:@"reason"];

  if ([reason hasPrefix:@"exited"])
  {
    /* The program ended: end the session as well. */
    [self setSubProcessId:0];
    [debuggerWrapper putString:@"-gdb-exit\n"];
    return;
  }
  if ([reason isEqual:@"breakpoint-hit"])
  {
    NSString *number = [info objectForKey:@"bkptno"];
    reason = @"Breakpoint";
    for (NSString *symbol in symbolNumbers)
    {
      if ([[symbolNumbers objectForKey:symbol] isEqual:number])
      {
        reason = [symbol isEqual:@"objc_exception_throw"]
        ? @"Objective-C exception" : symbol;
      }
    }
  }
  else if ([reason isEqual:@"signal-received"])
  {
    reason = [NSString stringWithFormat:@"%@",
              [info objectForKey:@"signal-name"] ? [info objectForKey:@"signal-name"] : @"Signal"];
  }
  else if ([reason isEqual:@"end-stepping-range"] || [reason isEqual:@"function-finished"])
  {
    reason = @"Step";
  }
  else if (reason == nil)
  {
    reason = @"Paused";
  }
  ASSIGN(stopReason, reason);
  [debuggerWrapper putString:@"-stack-list-frames\n"];
}

- (void)debuggerDidResume
{
  DESTROY(frames);
  [self _postState:PCDebuggerStateRunning info:nil];
}

- (void)debuggerDidExit
{
  if (exitPosted)
  {
    return;
  }
  exitPosted = YES;
  DESTROY(frames);
  [self setSubProcessId:0];
  [self _postState:PCDebuggerStateExited info:nil];
}

- (void)setStackFrames:(NSArray *)miFrames
{
  NSMutableArray *list = [NSMutableArray array];
  PCProject *project = [self _project];
  NSUInteger firstSource = NSNotFound;
  NSUInteger firstProject = NSNotFound;

  for (NSDictionary *frame in miFrames)
  {
    NSMutableDictionary *entry = [NSMutableDictionary dictionary];
    NSString *function = [frame objectForKey:@"func"];
    NSString *file = [frame objectForKey:@"fullname"];
    NSString *line = [frame objectForKey:@"line"];

    if (![frame isKindOfClass:[NSDictionary class]])
    {
      continue;
    }
    [entry setObject:[NSNumber numberWithInteger:[[frame objectForKey:@"level"] integerValue]]
              forKey:@"Level"];
    [entry setObject:(function ? function : ([frame objectForKey:@"addr"] ? [frame objectForKey:@"addr"] : @"??"))
              forKey:@"Function"];
    if (file && line && [[NSFileManager defaultManager] fileExistsAtPath:file])
    {
      [entry setObject:file forKey:@"File"];
      [entry setObject:[NSNumber numberWithInteger:[line integerValue]] forKey:@"Line"];
      if (firstSource == NSNotFound)
      {
        firstSource = [list count];
      }
      if (firstProject == NSNotFound
          && [[project projectBrowser] categoryPathForFilePath:file] != nil)
      {
        firstProject = [list count];
      }
    }
    [list addObject:entry];
  }
  ASSIGN(frames, list);
  /* Like Xcode, show the first frame with the project's own code. */
  selectedFrame = firstProject != NSNotFound ? firstProject
  : (firstSource != NSNotFound ? firstSource : 0);
  [self _postState:PCDebuggerStateStopped info:[self _stoppedInfo]];
  [self selectFrameAtIndex:selectedFrame];
}

- (void)selectFrameAtIndex:(NSUInteger)index
{
  NSDictionary *frame;

  if (![state isEqual:PCDebuggerStateStopped] || index >= [frames count])
  {
    return;
  }
  frame = [frames objectAtIndex:index];
  if (index != selectedFrame)
  {
    selectedFrame = index;
    [debuggerWrapper putString:[NSString stringWithFormat:@"-stack-select-frame %@\n",
                                [frame objectForKey:@"Level"]]];
    [self _postState:PCDebuggerStateStopped info:[self _stoppedInfo]];
  }
  else if ([[frame objectForKey:@"Level"] integerValue] != 0)
  {
    [debuggerWrapper putString:[NSString stringWithFormat:@"-stack-select-frame %@\n",
                                [frame objectForKey:@"Level"]]];
  }
  if ([frame objectForKey:@"File"])
  {
    PCProjectEditor *editor = [[self _project] projectEditor];
    id<CodeEditor> codeEditor = [editor openEditorForFilePath:[frame objectForKey:@"File"]
                                                     windowed:NO];
    [codeEditor scrollToLineNumber:[[frame objectForKey:@"Line"] unsignedIntegerValue]];
  }
}

- (BOOL)isDebugging
{
  return [debuggerWrapper isRunning];
}

- (void)runExecutableAtPath:(NSString *)filePath withDebugger:(NSString *)debuggerPath
{
  ASSIGN(executablePath, filePath);
  [debuggerWrapper setDebuggerPath:debuggerPath];
  [debuggerWindow setTitle:[NSString stringWithFormat:@"Debugger (%@)", filePath]];
  exitPosted = NO;
  runWhenReady = YES;
  [self startDebugger];
  [self _postState:PCDebuggerStateRunning info:nil];
}

- (void)stopDebugging
{
  if (subProcessId != 0)
  {
#ifndef __MINGW32__
    kill(subProcessId, SIGKILL);
#endif
    subProcessId = 0;
  }
  [debuggerWrapper putString:@"-gdb-exit\n"];
  [self performSelector:@selector(_terminateDebugger) withObject:nil afterDelay:2.0];
}

- (void)_terminateDebugger
{
  if ([debuggerWrapper isRunning])
  {
    [debuggerWrapper terminate];
  }
}

- (void)continueExecution:(id)sender
{
  if ([state isEqual:PCDebuggerStateStopped])
  {
    [self continue:sender];
  }
}

- (void)pauseExecution:(id)sender
{
  if ([state isEqual:PCDebuggerStateRunning])
  {
    [self interrupt];
  }
}

- (void)_continueOrPause:(id)sender
{
  if ([state isEqual:PCDebuggerStateStopped])
    [self continueExecution:sender];
  else
    [self pauseExecution:sender];
}

- (void)stepOver:(id)sender
{
  if ([state isEqual:PCDebuggerStateStopped]) [self next:sender];
}

- (void)_updateControls
{
  BOOL stopped = [state isEqual:PCDebuggerStateStopped];
  BOOL running = [state isEqual:PCDebuggerStateRunning];

  [continueButton setImage:[NSImage imageNamed:stopped ? @"NSTouchBarPlayTemplate" : @"NSTouchBarPauseTemplate"]];
  [continueButton setToolTip:stopped ? @"Continue program execution" : @"Pause program execution"];
  [continueButton setEnabled:stopped || running];
  [stepOverButton setEnabled:stopped];
  [stepIntoButton setEnabled:stopped];
  [stepOutButton setEnabled:stopped];
  if (stopped)
    [stateField setStringValue:[NSString stringWithFormat:@"Paused: %@", stopReason ? stopReason : @""]];
  else if (running)
    [stateField setStringValue:@"Running"];
  else
    [stateField setStringValue:@"Not running"];
}

static NSButton *DebugBarButton(NSString *image, NSString *toolTip, SEL action, id target, CGFloat x)
{
  NSButton *button = [[[NSButton alloc] initWithFrame:NSMakeRect(x, 3, 28, 24)] autorelease];
  [button setBezelStyle:NSTexturedRoundedBezelStyle];
  [button setBordered:NO];
  [button setImagePosition:NSImageOnly];
  [button setImage:[NSImage imageNamed:image]];
  [button setToolTip:toolTip];
  [button setTarget:target];
  [button setAction:action];
  [button setAutoresizingMask:NSViewMaxXMargin | NSViewMinYMargin];
  return button;
}

- (NSView *)debugAreaView
{
  NSScrollView *console;
  NSView *bar;

  if (debugAreaView)
  {
    return debugAreaView;
  }
  debugAreaView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 220)];
  [debugAreaView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

  /* Xcode's debug bar: continue/pause and the three step commands. */
  bar = [[[NSView alloc] initWithFrame:NSMakeRect(0, 190, 600, 30)] autorelease];
  [bar setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
  continueButton = DebugBarButton(@"NSTouchBarPauseTemplate", @"Pause program execution",
                                  @selector(_continueOrPause:), self, 6);
  stepOverButton = DebugBarButton(@"GSStepOverTemplate", @"Step over", @selector(stepOver:), self, 38);
  stepIntoButton = DebugBarButton(@"GSStepIntoTemplate", @"Step into", @selector(stepInto:), self, 70);
  stepOutButton = DebugBarButton(@"GSStepOutTemplate", @"Step out", @selector(stepOut:), self, 102);
  [bar addSubview:continueButton];
  [bar addSubview:stepOverButton];
  [bar addSubview:stepIntoButton];
  [bar addSubview:stepOutButton];
  stateField = [[[NSTextField alloc] initWithFrame:NSMakeRect(140, 6, 450, 18)] autorelease];
  [stateField setEditable:NO];
  [stateField setSelectable:NO];
  [stateField setBezeled:NO];
  [stateField setBordered:NO];
  [stateField setDrawsBackground:NO];
  [stateField setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
  [bar addSubview:stateField];
  [debugAreaView addSubview:bar];

  /* The console from the debugger window: gdb and program output, input. */
  console = [debuggerView enclosingScrollView];
  [console retain];
  [console removeFromSuperview];
  [console setFrame:NSMakeRect(0, 0, 600, 190)];
  [console setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [debugAreaView addSubview:console];
  [console release];

  [self _updateControls];
  return debugAreaView;
}

- (void) awakeFromNib
{
  NSToolbar *toolbar = [(NSToolbar *)[NSToolbar alloc] initWithIdentifier: @"PCDebuggerToolbar"];
  [toolbar setAllowsUserCustomization: NO];
  [toolbar setDelegate: self];
  [debuggerWindow setToolbar: toolbar];
  RELEASE(toolbar);

  [debuggerWindow setFrameAutosaveName: @"PCDebuggerWindow"];
  [self setStatus: @"Idle."];
}

- (id <PCDebuggerWrapperProtocol>)debuggerWrapper
{
  return debuggerWrapper;
}

- (NSWindow *)debuggerWindow
{
  return debuggerWindow;
}

- (void)setDebuggerWindow: (NSWindow *)window
{
  debuggerWindow = window;
}

- (NSView *)debuggerView
{
  return debuggerView;
}

- (void)setDebuggerView: (id)view
{
  debuggerView = view;
}

- (NSString *)executablePath
{
  return executablePath;
}

- (void)setExecutablePath:(NSString *)p
{
  ASSIGN(executablePath,p);
}

- (int) subProcessId
{
  return subProcessId;
}

- (void) setSubProcessId: (int)pid
{
  subProcessId = pid;
}

- (NSDictionary *)lastInfoParsed
{
  return lastInfoParsed;
}

- (void)setSetInfoParsed: (NSDictionary *)dict
{
  ASSIGN(lastInfoParsed, dict);
}

- (NSString *)lastFileNameParsed
{
  return lastFileNameParsed;
}

- (void) setLastFileNameParsed: (NSString *)fname
{
  ASSIGN(lastFileNameParsed, fname);
}

- (NSUInteger)lastLineNumberParsed
{
  return lastLineNumberParsed;
}

- (void)setLastLineNumberParsed: (NSUInteger)num
{
  lastLineNumberParsed = num;
}

- (void) updateEditor
{
  PCAppController *controller = (PCAppController *)[NSApp delegate];
  PCProjectManager *pm = [controller projectManager];
  PCEditorManager *em = [pm editorManager];
  if (lastFileNameParsed != nil &&
      lastLineNumberParsed != NSNotFound &&
      lastLineNumberParsed > 0)
  {
    [em gotoFile:lastFileNameParsed
          atLine:lastLineNumberParsed];
  }
}

// kill process
- (void) interrupt
{
  if(subProcessId != 0)
  {
#ifndef	__MINGW32__
    kill(subProcessId,SIGINT);
#else
    HANDLE proc;

    proc = OpenProcess(PROCESS_ALL_ACCESS, FALSE, (DWORD)subProcessId);
    if (proc == NULL)
    {
      DWORD lastError = GetLastError();
      NSLog(@"error opening process %lu", (unsigned long)lastError);
      return;
    }
    if (DebugBreakProcess(proc))
    {
      DWORD lastError = GetLastError();
      NSLog(@"error sending break %lu", (unsigned long)lastError);
    }
    else
    {
      NSLog(@"break sent successfully");
    }
    CloseHandle(proc);
#endif
  }
}

// action methods for toolbar...
- (void) go: (id) sender
{
  /* each run makes a new PID but we parse it only if non-zero */
  [self setSubProcessId:0];
  [debuggerWrapper putString: @"-exec-run\n"];
}

- (void) pause: (id) sender
{
  [self setStatus: @"Stopped."];
  [self interrupt];
}

- (void) continue: (id) sender
{
  [debuggerWrapper putString: @"-exec-continue\n"];
}

- (void) restart: (id) sender
{
  [self interrupt];
  /* each run makes a new PID but we parse it only if non-zero */
  [self setSubProcessId:0];
  [debuggerWrapper putString: @"-exec-run\n"];
}

- (void) next: (id) sender
{
  [debuggerWrapper putString: @"-exec-next\n"];
}

- (void) stepInto: (id) sender
{
  [debuggerWrapper putString: @"-exec-step\n"];
}

- (void) stepOut: (id) sender
{
  [debuggerWrapper putString: @"-exec-finish\n"];
}

- (void) up: (id) sender
{
  [debuggerWrapper putString: @"-interpreter-exec console \"up\"\n"];
}

- (void) down: (id) sender
{
  [debuggerWrapper putString: @"-interpreter-exec console \"down\"\n"];
}

// Status..
- (void) setStatus: (NSString *) status
{
  [statusField setStringValue: status];
}

- (NSString *) status
{
  return [statusField stringValue];
}

- (void) dealloc
{
  [NSObject cancelPreviousPerformRequestsWithTarget:self];
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [debuggerWrapper setDebugger:nil];
  RELEASE(debuggerWrapper);
  RELEASE(breakpoints);
  RELEASE(breakpointNumbers);
  RELEASE(symbolNumbers);
  RELEASE(frames);
  RELEASE(stopReason);
  RELEASE(state);
  RELEASE(debugAreaView);
  RELEASE(executablePath);
  RELEASE(lastInfoParsed);
  RELEASE(lastFileNameParsed);
  [super dealloc];
}
@end

@implementation PCDebugger (NSToolbarDelegate)

- (NSToolbarItem*)toolbar: (NSToolbar*)toolbar
    itemForItemIdentifier: (NSString*)itemIdentifier
willBeInsertedIntoToolbar: (BOOL)flag
{
  NSToolbarItem *toolbarItem = AUTORELEASE([[NSToolbarItem alloc]
                                            initWithItemIdentifier: itemIdentifier]);

  if([itemIdentifier isEqual: @"GoItem"])
  {
    [toolbarItem setLabel: @"Go"];
    [toolbarItem setImage: goImage];
    [toolbarItem setTarget: self];
    [toolbarItem setAction: @selector(go:)];
    [toolbarItem setTag: 0];
  }
  else if([itemIdentifier isEqual: @"PauseItem"])
  {
    [toolbarItem setLabel: @"Pause"];
    [toolbarItem setImage: pauseImage];
    [toolbarItem setTarget: self];
    [toolbarItem setAction: @selector(pause:)];
    [toolbarItem setTag: 1];
  }
  else if([itemIdentifier isEqual: @"ContinueItem"])
  {
    [toolbarItem setLabel: @"Continue"];
    [toolbarItem setImage: continueImage];
    [toolbarItem setTarget: self];
    [toolbarItem setAction: @selector(continue:)];
    [toolbarItem setTag: 1];
  }
  else if([itemIdentifier isEqual: @"RestartItem"])
  {
    [toolbarItem setLabel: @"Restart"];
    [toolbarItem setImage: restartImage];
    [toolbarItem setTarget: self];
    [toolbarItem setAction: @selector(restart:)];
    [toolbarItem setTag: 2];
  }
  else if([itemIdentifier isEqual: @"NextItem"])
  {
    [toolbarItem setLabel: @"Next"];
    [toolbarItem setImage: nextImage];
    [toolbarItem setTarget: self];
    [toolbarItem setAction: @selector(next:)];
    [toolbarItem setTag: 3];
  }
  else if([itemIdentifier isEqual: @"StepIntoItem"])
  {
    [toolbarItem setLabel: @"Step Into"];
    [toolbarItem setImage: stepInImage];
    [toolbarItem setTarget: self];
    [toolbarItem setAction: @selector(stepInto:)];
    [toolbarItem setTag: 4];
  }
  else if([itemIdentifier isEqual: @"StepOutItem"])
  {
    [toolbarItem setLabel: @"Step Out"];
    [toolbarItem setImage: stepOutImage];
    [toolbarItem setTarget: self];
    [toolbarItem setAction: @selector(stepOut:)];
    [toolbarItem setTag: 5];
  }
  else if([itemIdentifier isEqual: @"UpItem"])
  {
    [toolbarItem setLabel: @"Up"];
    [toolbarItem setImage: upImage];
    [toolbarItem setTarget: self];
    [toolbarItem setAction: @selector(up:)];
    [toolbarItem setTag: 6];
  }
  else if([itemIdentifier isEqual: @"DownItem"])
  {
    [toolbarItem setLabel: @"Down"];
    [toolbarItem setImage: downImage];
    [toolbarItem setTarget: self];
    [toolbarItem setAction: @selector(down:)];
    [toolbarItem setTag: 7];
  }

  return toolbarItem;
}

- (NSArray*) toolbarAllowedItemIdentifiers: (NSToolbar*)toolbar
{
  return [NSArray arrayWithObjects: @"GoItem",
          @"PauseItem",
          @"ContinueItem",
          @"RestartItem",
          @"NextItem",
          @"StepIntoItem",
          @"StepOutItem",
          @"UpItem",
          @"DownItem",
          nil];
}

- (NSArray*) toolbarDefaultItemIdentifiers: (NSToolbar*)toolbar
{
  return [NSArray arrayWithObjects: @"GoItem",
          @"PauseItem",
          @"ContinueItem",
          @"RestartItem",
          @"NextItem",
          @"StepIntoItem",
          @"StepOutItem",
          @"UpItem",
          @"DownItem",
          nil];
}

- (NSArray*) toolbarSelectableItemIdentifiers: (NSToolbar*)toolbar
{
  return [NSArray arrayWithObjects: @"GoItem",
          @"PauseItem",
          @"ContinueItem",
          @"RestartItem",
          @"NextItem",
          @"StepIntoItem",
          @"StepOutItem",
          @"UpItem",
          @"DownItem",
          nil];
}
@end
