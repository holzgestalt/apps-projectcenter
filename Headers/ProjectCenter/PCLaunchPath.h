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

/* The path an NSTask launches a tool at. Foundation only, as PCXcodeProject.m
 * is also built into the Foundation-only XcodeProjectTests.
 *
 * On Windows, ProjectCenter is a native program, but the tools it runs
 * (/usr/bin/env, /bin/sh, make) are MSYS2's, named by their MSYS2 paths. Such a
 * path is looked up below the MSYS2 installation: the folder of the PATH entry
 * that holds msys-2.0.dll is its usr/bin. /bin is MSYS2's /usr/bin, and /c/...
 * is C:/.... A path that isn't found there is looked up by its last component on
 * the PATH. Elsewhere the path is returned as it is.
 *
 * PCMSYS2Path() is the other way round, for paths handed to MSYS2's programs as
 * arguments: they read C:/msys64/home/x as a relative path, so it becomes
 * /home/x, and D:/x becomes /d/x. Elsewhere, again, the path as it is. */

#ifndef _PCLaunchPath_h_
#define _PCLaunchPath_h_

#import <Foundation/Foundation.h>

#if defined(_WIN32) && defined(GNUSTEP)
#import <GNUstepBase/NSTask+GNUstepBase.h>

static inline NSString *PCExecutableAtPath(NSString *path)
{
  NSFileManager *manager = [NSFileManager defaultManager];
  NSString *exe = [path stringByAppendingPathExtension:@"exe"];

  if ([[path pathExtension] length] == 0 && [manager isExecutableFileAtPath:exe]) return exe;
  if ([manager isExecutableFileAtPath:path]) return path;
  return nil;
}

/* The MSYS2 installation, as C:/msys64, or nil. */
static inline NSString *PCMSYS2Root(void)
{
  static NSString *root = nil;
  static BOOL looked = NO;

  if (!looked)
  {
    NSDictionary *environment = [[NSProcessInfo processInfo] environment];
    NSString *list = [environment objectForKey:@"PATH"] ?: [environment objectForKey:@"Path"];

    looked = YES;
    for (NSString *folder in [list componentsSeparatedByString:@";"])
    {
      folder = [folder stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
      while ([folder hasSuffix:@"/"]) folder = [folder substringToIndex:[folder length] - 1];
      if ([[[folder lowercaseString] lastPathComponent] isEqual:@"bin"]
          && [[[[folder stringByDeletingLastPathComponent] lastPathComponent] lowercaseString] isEqual:@"usr"]
          && [[NSFileManager defaultManager] fileExistsAtPath:
               [folder stringByAppendingPathComponent:@"msys-2.0.dll"]])
      {
        root = [[[folder stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] retain];
        break;
      }
    }
  }
  return root;
}

static inline NSString *PCLaunchPath(NSString *path)
{
  NSString *found;
  NSString *root;

  if ([path length] == 0) return path;
  if ((found = PCExecutableAtPath(path)) != nil) return found;
  path = [path stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
  if ([path hasPrefix:@"/"] && ![path hasPrefix:@"//"])
  {
    NSString *mapped = nil;

    if ([path hasPrefix:@"/bin/"]) path = [@"/usr" stringByAppendingString:path];
    if ([path length] >= 3 && [[NSCharacterSet letterCharacterSet] characterIsMember:[path characterAtIndex:1]]
        && [path characterAtIndex:2] == '/')
    {
      mapped = [NSString stringWithFormat:@"%@:%@", [[path substringWithRange:NSMakeRange(1, 1)] uppercaseString],
                [path substringFromIndex:2]];
    }
    else if ((root = PCMSYS2Root()) != nil)
    {
      mapped = [root stringByAppendingString:path];
    }
    if (mapped && (found = PCExecutableAtPath(mapped)) != nil) return found;
  }
  found = [NSTask launchPathForTool:[path lastPathComponent]];
  return found ? found : path;
}

static inline NSString *PCMSYS2Path(NSString *path)
{
  NSString *root = PCMSYS2Root();

  path = [path stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
  if ([path length] < 2 || [path characterAtIndex:1] != ':'
      || ![[NSCharacterSet letterCharacterSet] characterIsMember:[path characterAtIndex:0]])
  {
    return path;
  }
  if (root && [[path lowercaseString] hasPrefix:[[root lowercaseString] stringByAppendingString:@"/"]])
  {
    return [path substringFromIndex:[root length]];
  }
  return [NSString stringWithFormat:@"/%@%@", [[path substringToIndex:1] lowercaseString],
          [path substringFromIndex:2]];
}

#else

static inline NSString *PCLaunchPath(NSString *path)
{
  return path;
}

static inline NSString *PCMSYS2Path(NSString *path)
{
  return path;
}

#endif

#endif
