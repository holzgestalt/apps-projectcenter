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

#import <AppKit/AppKit.h>

#import "PCAppController.h"

@interface PCProjectDocument : NSDocument
{
}
@end

@implementation PCProjectDocument

- (BOOL)_openProjectURL:(NSURL *)url
{
  id appDelegate = [NSApp delegate];

  if (![url isFileURL]
      || ![appDelegate respondsToSelector:@selector(application:openFile:)])
  {
    return NO;
  }

  return [appDelegate application:NSApp openFile:[url path]];
}

- (BOOL)readFromURL:(NSURL *)url ofType:(NSString *)type
{
  return [self _openProjectURL:url];
}

- (BOOL)readFromFile:(NSString *)fileName ofType:(NSString *)type
{
  return [self _openProjectURL:[NSURL fileURLWithPath:fileName]];
}

- (void)makeWindowControllers
{
}

- (void)showWindows
{
  NSURL *url = nil;

  if ([self respondsToSelector:@selector(fileURL)])
  {
    url = [self fileURL];
  }
  if (url == nil && [self fileName] != nil)
  {
    url = [NSURL fileURLWithPath:[self fileName]];
  }

  if (url != nil)
  {
    [self _openProjectURL:url];
  }
}

@end

#ifndef GNUSTEP
/* Cocoa: projects open through the application delegate, not as NSDocuments,
 * so File > Open Recent hands the Xcode and GNUstep projects that
 * PCProjectManager records there to -application:openFile:. */
@interface PCDocumentController : NSDocumentController
@end

@implementation PCDocumentController

- (void)openDocumentWithContentsOfURL:(NSURL *)url
                              display:(BOOL)display
                    completionHandler:(void (^)(NSDocument *, BOOL, NSError *))completionHandler
{
  id   delegate = [NSApp delegate];
  BOOL opened;

  if (![url isFileURL]
      || ![delegate respondsToSelector:@selector(application:openFile:)])
  {
    [super openDocumentWithContentsOfURL:url
                                 display:display
                       completionHandler:completionHandler];
    return;
  }

  opened = [delegate application:NSApp openFile:[url path]];
  completionHandler(nil, NO, opened ? nil
                    : [NSError errorWithDomain:NSCocoaErrorDomain
                                          code:NSUserCancelledError
                                      userInfo:nil]);
}

@end

/* The first document controller made becomes the shared one. */
void PCInstallDocumentController(void)
{
  [PCDocumentController sharedDocumentController];
}
#endif
