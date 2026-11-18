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
 * PCInterfaceRendering: draws the objects of a XIB on the interface editor's
 * canvas. Controls are drawn by AppKit cells set up from the XML, so they
 * look as the active theme draws them (GSTheme on GNUstep, Aqua on macOS).
 * Nothing of the application is instantiated.
 */

#ifndef _PCInterfaceRendering_h_
#define _PCInterfaceRendering_h_

#import <AppKit/AppKit.h>

/* The child of an element with the key, or else the first child named so. */
NSXMLElement *PCInterfaceChild(NSXMLElement *element, NSString *keyOrName);
/* <color> and <font> elements of a XIB; nil when there is none. */
NSColor *PCInterfaceColor(NSXMLElement *color);
NSFont *PCInterfaceFont(NSXMLElement *font);
/* "System 13", "Helvetica Bold 12" */
NSString *PCInterfaceFontDescription(NSXMLElement *font);

/* Draws an object (not its subviews) in its frame on the canvas view.
 * Returns NO when the object draws what is inside it itself, so its child
 * elements are not to be drawn (a pop up button's menu, a matrix's cells). */
BOOL PCInterfaceDrawObject(NSXMLElement *object, NSRect frame, NSView *view);
/* Whether the subviews of a view are laid out from its top, as in a
 * scroll view. */
BOOL PCInterfaceIsFlipped(NSXMLElement *object);
/* A window's title bar and frame around its content; returns the window's
 * rectangle. */
NSRect PCInterfaceDrawWindowFrame(NSXMLElement *window, NSRect content, NSView *view);
/* The height of the title bar PCInterfaceDrawWindowFrame draws. */
CGFloat PCInterfaceTitleBarHeight(void);

#endif
