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
 * PCInterfaceDocument: a XIB as the interface editor edits it.
 *
 * The XML is the document. Nothing is instantiated, and every edit changes
 * only the elements it is about, so whatever the editor doesn't know about
 * (constraints, runtime attributes, bindings, Xcode's own metadata) is
 * written back as it was. Interface objects are the elements with an id,
 * except connections and constraints. Constraints are edited as elements:
 * their attributes, and removing them with -removeObject:.
 *
 * Foundation only (NSXMLDocument), so it works with Cocoa as well as with
 * GNUstep, and XcodeProjectTests can test it.
 */

#ifndef _PCInterfaceDocument_h_
#define _PCInterfaceDocument_h_

#import <Foundation/Foundation.h>

@interface PCInterfaceDocument : NSObject
{
  NSXMLDocument  *document;
  NSMutableArray *objects;
  NSString       *declaration;  // the <?xml ...?> line as it was read
  BOOL           finalNewline;
}

/* nil and a reason if the data isn't a Cocoa XIB. */
+ (PCInterfaceDocument *)documentWithData:(NSData *)data error:(NSString **)error;
- (NSXMLDocument *)XMLDocument;
/* The XIB, with the XML declaration and final line break it was read with. */
- (NSData *)data;

// --- Objects

/* The interface objects, in document order. */
- (NSArray *)objects;
- (NSXMLElement *)objectWithIdentifier:(NSString *)identifier;
/* The object an element belongs to: the element itself or the nearest
 * enclosing object. */
- (NSXMLElement *)objectOfElement:(NSXMLElement *)element;
/* Title, label, custom class, or the element name in words ("Text Field"). */
- (NSString *)nameOfObject:(NSXMLElement *)object;
/* An id in Xcode's form ("abc-de-fgh") that isn't used yet. */
- (NSString *)uniqueIdentifier;

// --- Attributes

/* The attributes of an object, of its cell, and of its elements that aren't
 * objects themselves (font, color, frame...). Each row has "Element", "Name" (nil
 * for the text of an element such as a key equivalent), "Label", "Value"
 * and "Editable" (NSNumber). */
- (NSArray *)attributesOfObject:(NSXMLElement *)object;
/* Sets an attribute (or the text, for a nil name); an empty value removes
 * the attribute. */
- (void)setValue:(NSString *)value
     ofAttribute:(NSString *)name
       ofElement:(NSXMLElement *)element;
- (void)addAttribute:(NSString *)name
           withValue:(NSString *)value
           toElement:(NSXMLElement *)element;
/* The child element with the key (<font key="font">); a new one named name
 * when there is none and name isn't nil. */
- (NSXMLElement *)childOfElement:(NSXMLElement *)element
                         withKey:(NSString *)key
                   creatingNamed:(NSString *)name;

// --- Connections

/* Outlets, actions and bindings from the object, then those to it. */
- (NSArray *)connectionsOfObject:(NSXMLElement *)object;
- (NSXMLElement *)sourceOfConnection:(NSXMLElement *)connection;
- (NSXMLElement *)destinationOfConnection:(NSXMLElement *)connection;
/* Property, selector or binding name. */
- (NSString *)nameOfConnection:(NSXMLElement *)connection;
- (NSXMLElement *)addOutlet:(NSString *)property
                 fromObject:(NSXMLElement *)source
                   toObject:(NSXMLElement *)destination;
- (NSXMLElement *)addAction:(NSString *)selector
                 fromObject:(NSXMLElement *)control
                   toObject:(NSXMLElement *)target;
- (void)removeConnection:(NSXMLElement *)connection;

// --- Constraints

/* The constraints with the object as their first or second item. */
- (NSArray *)constraintsOfObject:(NSXMLElement *)object;
/* The views a constraint relates: its first item, then its second. */
- (NSArray *)itemsOfConstraint:(NSXMLElement *)constraint;
/* As in Xcode's outline, without the view that holds the constraint:
 * "OK.width = 96", "Name.leading = leading + 20 @750". */
- (NSString *)descriptionOfConstraint:(NSXMLElement *)constraint;
- (void)removeConstraint:(NSXMLElement *)constraint;

/* What Xcode's inspector shows of a constraint. The view that holds it is
 * its owner; firstItem is left out of the XIB when it is the owner. */
- (NSXMLElement *)ownerOfConstraint:(NSXMLElement *)constraint;
- (NSXMLElement *)firstItemOfConstraint:(NSXMLElement *)constraint;
- (NSXMLElement *)secondItemOfConstraint:(NSXMLElement *)constraint;
/* "Horizontal Space Constraint", "Width Constraint", "Center X Alignment Constraint"... */
- (NSString *)kindOfConstraint:(NSXMLElement *)constraint;
/* The owner and the views inside it. */
- (NSArray *)candidateItemsForConstraint:(NSXMLElement *)constraint;
+ (NSArray *)constraintAttributes;
/* "centerX" is "Center X", "leadingMargin" "Leading Margin". */
+ (NSString *)titleOfConstraintAttribute:(NSString *)attribute;
- (void)setFirstItem:(NSXMLElement *)item
           attribute:(NSString *)attribute
        ofConstraint:(NSXMLElement *)constraint;
/* A nil item makes it a constant constraint. */
- (void)setSecondItem:(NSXMLElement *)item
            attribute:(NSString *)attribute
         ofConstraint:(NSXMLElement *)constraint;
/* constant, priority or multiplier; the default value removes the attribute,
 * and a constant replaces the standard spacing. */
- (void)setNumber:(NSString *)value
      ofAttribute:(NSString *)name
     ofConstraint:(NSXMLElement *)constraint;

// --- Adding and removing objects

/* Names of the objects that can be added ("Push Button", "Label"...). */
+ (NSArray *)libraryItems;
/* Adds a library object next to or into the selection: a view into the
 * enclosing view, a menu item into the menu. nil when it doesn't fit there. */
- (NSXMLElement *)insertLibraryItem:(NSString *)name
                          forObject:(NSXMLElement *)selection;
/* Placeholders, content views and cells belong to their owner. */
- (BOOL)canRemoveObject:(NSXMLElement *)object;
/* Removes the object with its subviews, and the connections and
 * constraints that refer to any of them. */
- (void)removeObject:(NSXMLElement *)object;
@end

#endif
