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
 * PCGormXIBWriter: a Gorm interface (PCGormArchive) as an Interface Builder
 * XIB document, with autoresizing masks and Gorm's frames.
 *
 * Every object of the interface gets the id "g<identifier>" of its
 * PCGormObject, so an edit of the XIB can be applied to the archive (see
 * PCInterfaceEditor). The macOS build compiles the XIBs made from
 * ProjectCenter's own .gorm files (Tools/gorm2xib).
 *
 * Foundation only (NSXMLDocument), like PCGormArchive.
 */

#ifndef _PCGormXIBWriter_h_
#define _PCGormXIBWriter_h_

#import <Foundation/Foundation.h>

@class PCGormArchive;
@class PCGormObject;

@interface PCGormXIBWriter : NSObject
{
  PCGormArchive       *archive;
  PCGormObject        *container;
  NSString            *toolsVersion;
  NSMutableDictionary *names;       // object -> name in the name table
  NSMutableDictionary *byName;      // name -> object (or the owner's class)
  NSMutableDictionary *custom;      // name -> custom class
  NSMutableDictionary *pending;     // xib id -> connections to add
  NSMutableArray      *sources;     // the xib ids in pending, in order
  NSMutableDictionary *images;      // image name -> PCGormObject
  NSMutableArray      *warnings;
  NSMutableSet        *visible;
  NSUInteger          serial;
}

/* The XIB of the archive. toolsVersion is the Interface Builder version
 * written into the document (nil: a version every Xcode reads). */
+ (NSXMLDocument *)documentForArchive:(PCGormArchive *)archive
                         toolsVersion:(NSString *)toolsVersion
                             warnings:(NSArray **)warnings;
/* The id of an object in the XIB. */
+ (NSString *)identifierForObject:(PCGormObject *)object;
/* The object an XIB id stands for, or nil. */
+ (PCGormObject *)objectForIdentifier:(NSString *)identifier
                            inArchive:(PCGormArchive *)archive;
@end

#endif
