/*
 main.m

 ArchiveDemo: a small application with a Mac and a Linux target, for trying
 ProjectCenter's Archive. With --smoke-test it opens its window, prints
 "ArchiveDemo started" and quits after a second.

 This file is part of GNUstep ProjectCenter.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation; either version 2 of the License, or
 (at your option) any later version.
 */

#import <AppKit/AppKit.h>

@interface DemoDelegate : NSObject
{
  NSWindow *window;
}
@end

@implementation DemoDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
  NSTextField *label;
  NSArray     *items = @[@"blocks", @"literals"];
  NSString    *(^joined)(NSArray *) = ^NSString *(NSArray *array) {
    return [array componentsJoinedByString:@" and "];
  };

  window = [[NSWindow alloc] initWithContentRect:NSMakeRect(200, 200, 360, 120)
                                       styleMask:NSTitledWindowMask | NSClosableWindowMask
                                         backing:NSBackingStoreBuffered
                                           defer:NO];
  [window setTitle:@"ArchiveDemo"];
  label = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 40, 320, 24)];
  [label setStringValue:[NSString stringWithFormat:@"Built with %@.", joined(items)]];
  [label setEditable:NO];
  [label setBezeled:NO];
  [label setDrawsBackground:NO];
  [[window contentView] addSubview:label];
  [label release];
  [window makeKeyAndOrderFront:nil];
  if ([[[NSProcessInfo processInfo] arguments] containsObject:@"--smoke-test"])
  {
    printf("ArchiveDemo started\n");
    fflush(stdout);
    [NSApp performSelector:@selector(terminate:) withObject:nil afterDelay:1.0];
  }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
  return YES;
}

@end

int main(int argc, const char *argv[])
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  DemoDelegate      *delegate = [[DemoDelegate alloc] init];

  [NSApplication sharedApplication];
  [NSApp setDelegate:(id)delegate];
  [NSApp run];
  [delegate release];
  [pool release];
  return 0;
}
