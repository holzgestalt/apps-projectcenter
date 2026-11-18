/*
   GNUstep ProjectCenter - http://www.gnustep.org/experience/ProjectCenter.html

   Copyright (C) 2026 Free Software Foundation

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
#import <ProjectCenter/PCProject.h>
#import <ProjectCenter/PCLogController.h>
#import <ProjectCenter/PCConvertController.h>
#import "PCGormXIBWriter.h"

static NSString * const PCConvertColumnSelected = @"Selected";
static NSString * const PCConvertColumnName = @"Name";
static NSString * const PCConvertColumnResult = @"Result";

@implementation PCConvertController

- (void)dealloc
{
  RELEASE(panel);
  RELEASE(root);
  RELEASE(rows);
  [super dealloc];
}

static NSTextField *Label(NSRect frame, NSString *text, NSFont *font)
{
  NSTextField *label = [[[NSTextField alloc] initWithFrame:frame] autorelease];

  [label setStringValue:text];
  [label setFont:font];
  [label setEditable:NO];
  [label setSelectable:NO];
  [label setBezeled:NO];
  [label setDrawsBackground:NO];
  return label;
}

static NSButton *PushButton(NSRect frame, NSString *title, id target, SEL action)
{
  NSButton *button = [[[NSButton alloc] initWithFrame:frame] autorelease];

  [button setTitle:title];
  [button setButtonType:NSMomentaryPushInButton];
  [button setBezelStyle:NSRoundedBezelStyle];
  [button setTarget:target];
  [button setAction:action];
  return button;
}

- (void)_createPanel
{
  NSView       *content;
  NSScrollView *scroll;
  NSButtonCell *check;
  NSButton     *cancel;
  NSArray      *columns;
  NSUInteger   i;

  panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 580, 400)
                                     styleMask:NSTitledWindowMask | NSResizableWindowMask
                                       backing:NSBackingStoreBuffered
                                         defer:YES];
  [panel setTitle:@"Convert to XIB"];
  [panel setMinSize:NSMakeSize(420, 260)];
  [panel setReleasedWhenClosed:NO];
  content = [panel contentView];

  [content addSubview:Label(NSMakeRect(20, 362, 540, 20), @"Convert Gorm interfaces to XIB",
                            [NSFont boldSystemFontOfSize:0])];
  [[[content subviews] lastObject] setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
  [content addSubview:Label(NSMakeRect(20, 318, 540, 40),
                            @"Each XIB is written next to its .gorm, and is the interface's "
                            @"source from then on. Converting an interface that has a XIB "
                            @"replaces that XIB.",
                            [NSFont systemFontOfSize:[NSFont smallSystemFontSize]])];
  [[[content subviews] lastObject] setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];

  scroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(20, 60, 540, 252)] autorelease];
  [scroll setHasVerticalScroller:YES];
  [scroll setBorderType:NSBezelBorder];
  [scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  table = [[[NSTableView alloc] initWithFrame:[[scroll contentView] bounds]] autorelease];
  columns = @[@[PCConvertColumnSelected, @"", @24], @[PCConvertColumnName, @"Interface", @360],
              @[PCConvertColumnResult, @"XIB", @130]];
  for (i = 0; i < [columns count]; i++)
  {
    NSArray       *description = [columns objectAtIndex:i];
    NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:
                              [description objectAtIndex:0]] autorelease];

    [[column headerCell] setStringValue:[description objectAtIndex:1]];
    [column setWidth:[[description objectAtIndex:2] floatValue]];
    [column setEditable:(i == 0)];
    if (i == 0)
    {
      check = [[[NSButtonCell alloc] init] autorelease];
      [check setButtonType:NSSwitchButton];
      [check setTitle:@""];
      [column setDataCell:check];
      [column setResizingMask:NSTableColumnNoResizing];
    }
    [table addTableColumn:column];
  }
  [table setDataSource:(id)self];
  [table setDelegate:(id)self];
  [table setAllowsEmptySelection:YES];
  [scroll setDocumentView:table];
  [content addSubview:scroll];

  summary = Label(NSMakeRect(20, 22, 300, 18), @"", [NSFont systemFontOfSize:0]);
  [summary setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
  [content addSubview:summary];
  cancel = PushButton(NSMakeRect(370, 14, 92, 32), @"Cancel", self, @selector(cancel:));
  [cancel setKeyEquivalent:@"\e"];
  [cancel setAutoresizingMask:NSViewMinXMargin | NSViewMaxYMargin];
  [content addSubview:cancel];
  convertButton = PushButton(NSMakeRect(468, 14, 92, 32), @"Convert", self, @selector(convert:));
  [convertButton setKeyEquivalent:@"\r"];
  [convertButton setAutoresizingMask:NSViewMinXMargin | NSViewMaxYMargin];
  [content addSubview:convertButton];
}

- (void)_updateSummary
{
  NSUInteger selected = 0;
  NSUInteger replaced = 0;

  for (NSDictionary *row in rows)
  {
    if ([[row objectForKey:@"Selected"] boolValue])
    {
      selected++;
      if ([[row objectForKey:@"HasXIB"] boolValue]) replaced++;
    }
  }
  [summary setStringValue:(replaced
                           ? [NSString stringWithFormat:@"%lu of %lu selected, %lu replacing a XIB",
                              (unsigned long)selected, (unsigned long)[rows count],
                              (unsigned long)replaced]
                           : [NSString stringWithFormat:@"%lu of %lu selected",
                              (unsigned long)selected, (unsigned long)[rows count]])];
  [convertButton setEnabled:(selected > 0)];
}

- (void)convertInterfacesOfProject:(PCProject *)project
{
  NSArray *interfaces;

  ASSIGN(root, [project projectPath]);
  interfaces = [PCGormXIBWriter gormInterfacesInDirectory:root];
  if ([interfaces count] == 0)
  {
    NSRunAlertPanel(@"Convert to XIB",
                    @"%@ has no Gorm interfaces (.gorm) to convert.",
                    @"OK", nil, nil, [project projectName]);
    return;
  }
  RELEASE(rows);
  rows = [[NSMutableArray alloc] init];
  for (NSString *path in interfaces)
  {
    NSString *name = [path hasPrefix:[root stringByAppendingString:@"/"]]
      ? [path substringFromIndex:[root length] + 1] : path;
    BOOL hasXIB = [[NSFileManager defaultManager] fileExistsAtPath:
                   [PCGormXIBWriter XIBPathForGorm:path]];

    [rows addObject:[NSMutableDictionary dictionaryWithObjectsAndKeys:
                     path, @"Path", name, @"Name",
                     [NSNumber numberWithBool:hasXIB], @"HasXIB",
                     [NSNumber numberWithBool:!hasXIB], @"Selected", nil]];
  }
  if (panel == nil)
  {
    [self _createPanel];
  }
  [table reloadData];
  [self _updateSummary];
  [panel center];
  [NSApp runModalForWindow:panel];
}

- (void)cancel:(id)sender
{
  [NSApp stopModal];
  [panel orderOut:self];
}

- (void)convert:(id)sender
{
  NSString       *toolsVersion = [PCGormXIBWriter interfaceBuilderVersion];
  NSMutableArray *failures = [NSMutableArray array];
  NSUInteger     converted = 0;
  NSUInteger     warningCount = 0;
  NSString       *message;

  [NSApp stopModal];
  [panel orderOut:self];
  for (NSDictionary *row in rows)
  {
    NSString *xib = [PCGormXIBWriter XIBPathForGorm:[row objectForKey:@"Path"]];
    NSArray  *warnings = nil;
    NSString *error = nil;

    if (![[row objectForKey:@"Selected"] boolValue])
    {
      continue;
    }
    if (![PCGormXIBWriter writeXIBForGormAtPath:[row objectForKey:@"Path"]
                                         toPath:xib
                                   toolsVersion:toolsVersion
                                       warnings:&warnings
                                          error:&error])
    {
      [failures addObject:[NSString stringWithFormat:@"%@: %@", [row objectForKey:@"Name"], error]];
      PCLogError(self, @"%@: %@", [row objectForKey:@"Name"], error);
      continue;
    }
    converted++;
    PCLogInfo(self, @"Converted %@ to %@", [row objectForKey:@"Name"], [xib lastPathComponent]);
    for (NSString *warning in warnings)
    {
      warningCount++;
      PCLogWarning(self, @"%@: %@", [row objectForKey:@"Name"], warning);
    }
  }

  message = [NSString stringWithFormat:@"%lu interface%@ converted.", (unsigned long)converted,
             converted == 1 ? @"" : @"s"];
  if (warningCount)
  {
    message = [message stringByAppendingFormat:
               @" %lu part%@ could not be converted (such as GNUstep theme images); "
               @"the Log Panel lists them.", (unsigned long)warningCount,
               warningCount == 1 ? @"" : @"s"];
  }
  if ([failures count])
  {
    message = [message stringByAppendingFormat:@"\n\nNot converted:\n%@",
               [failures componentsJoinedByString:@"\n"]];
  }
  if (converted)
  {
    message = [message stringByAppendingString:
               @"\n\nAdd the new XIB files to the targets that use the interfaces."];
  }
  NSRunAlertPanel(@"Convert to XIB", @"%@", @"OK", nil, nil, message);
}

// --- Table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTable
{
  return [rows count];
}

- (id)tableView:(NSTableView *)aTable objectValueForTableColumn:(NSTableColumn *)column
            row:(NSInteger)row
{
  NSDictionary *entry = [rows objectAtIndex:row];
  NSString     *identifier = [column identifier];

  if ([identifier isEqual:PCConvertColumnSelected])
  {
    return [entry objectForKey:@"Selected"];
  }
  if ([identifier isEqual:PCConvertColumnName])
  {
    return [entry objectForKey:@"Name"];
  }
  return [[entry objectForKey:@"HasXIB"] boolValue] ? @"Replaces the XIB" : @"New";
}

- (void)tableView:(NSTableView *)aTable setObjectValue:(id)value
   forTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
  if ([[column identifier] isEqual:PCConvertColumnSelected])
  {
    [[rows objectAtIndex:row] setObject:[NSNumber numberWithBool:[value boolValue]]
                                 forKey:@"Selected"];
    [self _updateSummary];
  }
}

@end
