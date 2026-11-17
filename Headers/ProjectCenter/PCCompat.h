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

/*
 * GNUstep-base conveniences that Apple's Foundation does not provide.
 * Included by PCDefines.h and used as the prefix header of the Xcode
 * project; it does nothing when building against GNUstep.
 */

#ifndef _PCCompat_h_
#define _PCCompat_h_

#ifndef GNUSTEP

#include <string.h>

#ifdef __OBJC__
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@interface NSFont (PCCompat)

/* Width of string set in the receiver, like GNUstep's -widthOfString:. */
- (CGFloat)widthOfString:(NSString *)string;

@end

@interface NSString (PCCompat)

/* The receiver without leading and trailing white space. */
- (NSString *)stringByTrimmingSpaces;

@end

@interface NSUserDefaults (PCCompat)

/* The user's languages as English names ("English", "German"), like
 * GNUstep's +userLanguages, which ProjectCenter stores in projects. */
+ (NSArray *)userLanguages;

@end

@interface NSWorkspace (PCCompat)

/* Path of the default application for files with the extension, or nil.
 * The role is ignored. */
- (NSString *)getBestAppInRole:(NSString *)role
                  forExtension:(NSString *)extension;

@end

@interface NSText (PCCompat)

- (void)setText:(NSString *)string;

@end

@interface NSTextField (PCCompat)

- (void)setNextText:(id)anObject;

@end
#endif

#ifndef RETAIN
#define RETAIN(object) [(object) retain]
#endif

#ifndef RELEASE
#define RELEASE(object) [(object) release]
#endif

#ifndef AUTORELEASE
#define AUTORELEASE(object) [(object) autorelease]
#endif

#ifndef TEST_RELEASE
#define TEST_RELEASE(object) ({ \
  id __o = (id)(object); \
  if (__o != nil) \
  { \
    [__o release]; \
  } \
})
#endif

#ifndef ASSIGN
#define ASSIGN(object, value) ({ \
  id __value = (id)(value); \
  id __object = (id)(object); \
  if (__value != __object) \
  { \
    if (__value != nil) \
    { \
      [__value retain]; \
    } \
    object = __value; \
    if (__object != nil) \
    { \
      [__object release]; \
    } \
  } \
})
#endif

#ifndef ASSIGNCOPY
#define ASSIGNCOPY(object, value) ({ \
  id __value = [(id)(value) copy]; \
  id __object = (id)(object); \
  object = __value; \
  if (__object != nil) \
  { \
    [__object release]; \
  } \
})
#endif

#ifndef DESTROY
#define DESTROY(object) ({ \
  id __o = (id)(object); \
  object = nil; \
  if (__o != nil) \
  { \
    [__o release]; \
  } \
})
#endif

#ifndef CREATE_AUTORELEASE_POOL
#define CREATE_AUTORELEASE_POOL(X) NSAutoreleasePool *X = [NSAutoreleasePool new]
#endif

#ifndef _
#define _(X) NSLocalizedString(X, @"")
#endif

/* GNUstep only prints these when debugging is switched on for the level. */
#ifndef NSDebugLog
#define NSDebugLog(format, ...) do { } while (0)
#endif

#ifndef NSDebugLLog
#define NSDebugLLog(level, format, ...) do { } while (0)
#endif

#endif // GNUSTEP

#endif // _PCCompat_h_
