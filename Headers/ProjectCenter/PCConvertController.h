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

#ifndef _PCCONVERTCONTROLLER_H
#define _PCCONVERTCONTROLLER_H

#import <AppKit/AppKit.h>

@class PCProject;

/* Edit → Convert → To XIB...: writes a XIB next to each Gorm interface of a
 * project, as Xcode's Edit → Convert → To String Catalogs... moves strings
 * files to the current format. A panel lists the interfaces; those that
 * have no XIB yet are selected, as the XIB is the interface's source from
 * then on. */
@interface PCConvertController : NSObject
{
  NSPanel        *panel;
  NSTableView    *table;
  NSTextField    *summary;
  NSButton       *convertButton;
  NSString       *root;
  NSMutableArray *rows;  // {Path, Name, HasXIB, Selected}
}

- (void)convertInterfacesOfProject:(PCProject *)project;

@end

#endif
