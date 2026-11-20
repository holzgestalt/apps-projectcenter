//
// GNUstep ProjectCenter - http://www.gnustep.org/experience/ProjectCenter.html
//
// Copyright (C) 2001-2011 Free Software Foundation
//
// Authors: Sergii Stoian
//
// Description:
//
// This file is part of GNUstep.
//
// This application is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License as published
// by the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
//
// This application is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
// Library General Public License for more details.
//
// You should have received a copy of the GNU General Public
// License along with this library; if not, write to the Free Software
// Foundation, Inc., 31 Milk Street #960789 Boston, MA 02196 USA.

#import <ProjectCenter/PCFileManager.h>

#import "PCMiscPrefs.h"

@implementation PCMiscPrefs

// ----------------------------------------------------------------------------
// --- Init and free
// ----------------------------------------------------------------------------

- (id)initWithPrefController:(id <PCPreferences>)aPrefs
{
  self = [super init];

  if ([NSBundle loadNibNamed:@"MiscPrefs" owner:self] == NO)
  {
    NSLog(@"PCMiscPrefs: error loading NIB file!");
  }

  prefs = aPrefs;

  RETAIN(miscView);

  return self;
}

- (void)awakeFromNib
{
  [promptWhenQuit setRefusesFirstResponder:YES];
  [fullPathInFilePanels setRefusesFirstResponder:YES];
  [rememberWindows setRefusesFirstResponder:YES];
  [displayLog setRefusesFirstResponder:YES];
  [useTearOffWindows setRefusesFirstResponder:YES];

  [debuggerButton setRefusesFirstResponder:YES];
  [editorButton setRefusesFirstResponder:YES];
  [gnustepButton setRefusesFirstResponder:YES];
}

/* PCXcodeProject's GNUstep lookup, which is in the framework. */
static NSString *GNUstepMakefiles(SEL selector, NSString *path)
{
  Class project = NSClassFromString(@"PCXcodeProject");

  if (project == Nil || ![project respondsToSelector:selector]) return nil;
  return path ? [project performSelector:selector withObject:path] : [project performSelector:selector];
}

/* The field shows the chosen GNUstep, or in grey the one found. */
- (void)_showGNUstep
{
  NSString *chosen = [prefs stringForKey:GNUstepInstallation];
  NSString *found = GNUstepMakefiles(@selector(foundGNUstepMakefiles), nil);
  NSString *used = [chosen length] ? GNUstepMakefiles(@selector(GNUstepMakefilesInFolder:), chosen) : found;

  [gnustepField setStringValue:chosen ? chosen : @""];
  [[gnustepField cell] setPlaceholderString:found ? found : @"None found"];
  [gnustepField setToolTip:used
   ? [NSString stringWithFormat:@"Builds with %@/GNUstep.sh. Empty finds GNUstep by itself.", used]
   : @"The GNUstep installation to build with: its prefix or the folder of GNUstep.sh. "
     @"Empty finds GNUstep by itself."];
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];

  RELEASE(miscView);

  [super dealloc];
}

// Protocol
- (void)readPreferences
{
  NSString *val;
  BOOL     bVal;
  int      state;
  NSString       *debuggerToolDefault;
  PCFileManager  *pcfm = [PCFileManager defaultManager];

  /* some heuristic to find the best debugger default */
  debuggerToolDefault = [pcfm findExecutableToolFrom:
                         [NSArray arrayWithObjects:
                          @"usr/local/bin/gdb",
                          @"usr/bin/gdb",
                          @"bin/gdb",
                          nil]];
  NSLog(@"Debugger tool found: %@", debuggerToolDefault);

  bVal = [prefs boolForKey:PromptOnQuit defaultValue:YES];
  state = bVal ? NSOnState : NSOffState;
  [promptWhenQuit setState:state];

  bVal = [prefs boolForKey:FullPathInFilePanels defaultValue:YES];
  state = bVal ? NSOnState : NSOffState;
  [fullPathInFilePanels setState:state];

  bVal = [prefs boolForKey:RememberWindows defaultValue:YES];
  state = bVal ? NSOnState : NSOffState;
  [rememberWindows setState:state];

  bVal = [prefs boolForKey:DisplayLog defaultValue:NO];
  state = bVal ? NSOnState : NSOffState;
  [displayLog setState:state];

  /* Build and run output open in the project window unless the user chooses
   * separate panels (PCProjectManager registers the same default). */
  bVal = [prefs boolForKey:UseTearOffWindows defaultValue:NO];
  state = bVal ? NSOnState : NSOffState;
  [useTearOffWindows setState:state];

  val = [prefs stringForKey:Debugger defaultValue:debuggerToolDefault];
  if (val)
    [debuggerField setStringValue:val];

  val = [prefs stringForKey:Editor defaultValue:@"ProjectCenter"];
  [editorField setStringValue:val];

  [self _showGNUstep];
}

- (NSView *)view
{
  return miscView;
}

// Actions
- (void)setPromptWhenQuit:(id)sender
{
  BOOL state;

  if (promptWhenQuit == nil)
  {// HACK!!! need to be fixed in GNUstep
    promptWhenQuit = sender;
    return;
  }

  state = ([sender state] == NSOffState) ? NO : YES;
  [prefs setBool:state forKey:PromptOnQuit notify:YES];
}

- (void)setFullPathInFilePanels:(id)sender
{
  BOOL state;

  if (fullPathInFilePanels == nil)
  {// HACK!!! need to be fixed in GNUstep
    fullPathInFilePanels = sender;
    return;
  }

  state = ([sender state] == NSOffState) ? NO : YES;
  [prefs setBool:state forKey:FullPathInFilePanels notify:YES];
}

- (void)setRememberWindows:(id)sender
{
  BOOL state;

  if (rememberWindows == nil)
  {
    rememberWindows = sender;
    return;
  }

  state = ([sender state] == NSOffState) ? NO : YES;
  [prefs setBool:state forKey:RememberWindows notify:YES];
}

- (void)setDisplayLog:(id)sender
{
  BOOL state;

  if (displayLog == nil)
  {
    displayLog = sender;
    return;
  }

  state = ([sender state] == NSOffState) ? NO : YES;
  [prefs setBool:state forKey:DisplayLog notify:YES];
}

- (void)setUseTearOffWindows:(id)sender
{
  BOOL state;

  if (useTearOffWindows == nil)
  {
    useTearOffWindows = sender;
    return;
  }

  state = ([sender state] == NSOffState) ? NO : YES;
  [prefs setBool:state forKey:UseTearOffWindows notify:YES];
}

- (void)setDebugger:(id)sender
{
  NSArray       *files;
  NSString      *path;
  NSFileManager *fm = [NSFileManager defaultManager];

  // Choose
  if (sender == debuggerField)
  {
    path = [debuggerField stringValue];
  }
  else
  {
    files = [[PCFileManager defaultManager]
             filesOfTypes:nil
             operation:PCOpenFileOperation
             multiple:NO
             title:@"Choose Debugger Tool"
             accView:nil];
    path = [files objectAtIndex:0];
  }

  [[miscView window] makeFirstResponder:debuggerField];
  if (!path)
  {
    return;
  }

  // Check
  if (path && ![fm fileExistsAtPath:path])
  {
    NSRunAlertPanel(@"Set Debugger Tool",
                    @"File %@ doesn't exist!\n"
                    @"Setting field to default value.",
                    @"Close", nil, nil, path);
    path = @"";
  }
  else if (path && ![fm isExecutableFileAtPath:path])
  {
    NSRunAlertPanel(@"Set Debugger Tool",
                    @"File %@ exists but is not executable!\n"
                    @"Setting field to default value.",
                    @"Close", nil, nil, path);
    path = @"";
  }

  if ([path isEqualToString:@""])
  {
    path = PCDefaultDebugger;
  }

  // Set
  [debuggerField setStringValue:path];
  [prefs setString:path forKey:Debugger notify:YES];
}

- (void)setEditor:(id)sender
{
  NSArray       *files;
  NSString      *path;
  NSString      *editorPath;
  NSFileManager *fm = [NSFileManager defaultManager];
  NSWorkspace   *ws = [NSWorkspace sharedWorkspace];

  // Choose
  if (sender == editorField)
  {
    path = [editorField stringValue];
  }
  else if ([path = [editorField stringValue] isEqualToString:@""])
  {
    files = [[PCFileManager defaultManager]
             filesOfTypes:nil
             operation:PCOpenFileOperation
             multiple:NO
             title:@"Choose Editor"
             accView:nil];
    path = [files objectAtIndex:0];
  }

  [[miscView window] makeFirstResponder:editorField];
  if (!path)
  {
    return;
  }

  // Check
  if (path && ![ws fullPathForApplication:path])
  {
    editorPath = [[path componentsSeparatedByString:@" "] objectAtIndex:0];
    if (![fm fileExistsAtPath:editorPath])
    {
      [editorField selectText:self];
      NSRunAlertPanel(@"Set Editor",
                      @"Editor %@ doesn't exist!\n"
                      @"Setting field to default value.",
                      @"Close", nil, nil, path);
      path = @"";
    }
    else if (path && ![fm isExecutableFileAtPath:editorPath])
    {
      [editorField selectText:self];
      NSRunAlertPanel(@"Set Editor",
                      @"File %@ exists but is not executable!\n"
                      @"Setting field to default value.",
                      @"Close", nil, nil, path);
      path = @"";
    }
  }
  
  if ([path isEqualToString:@""] || !path)
  {
    path = @"ProjectCenter";
  }

  // Set
  [editorField setStringValue:path];
  [prefs setString:path forKey:Editor notify:YES];
}

- (void)setGNUstep:(id)sender
{
  NSString *path;

  if (sender == gnustepField)
  {
    path = [gnustepField stringValue];
  }
  else
  {
    NSArray *files = [[PCFileManager defaultManager]
                      filesOfTypes:nil
                      operation:PCOpenDirectoryOperation
                      multiple:NO
                      title:@"Choose GNUstep Installation"
                      accView:nil];

    if ([files count] == 0) return;
    path = [files objectAtIndex:0];
  }
  path = [path stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([path length] && GNUstepMakefiles(@selector(GNUstepMakefilesInFolder:), path) == nil)
  {
    NSRunAlertPanel(@"Choose GNUstep",
                    @"There is no GNUstep.sh in %@.\n"
                    @"Choose the prefix GNUstep is installed in, or the folder of GNUstep.sh.",
                    @"OK", nil, nil, path);
    [self _showGNUstep];
    return;
  }
  [prefs setString:path forKey:GNUstepInstallation notify:YES];
  [self _showGNUstep];
}

@end
