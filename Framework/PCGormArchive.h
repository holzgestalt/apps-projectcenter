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
 * PCGormArchive: the objects.gorm of a Gorm interface, read without
 * instantiating anything, edited, and written back.
 *
 * A .gorm is a GNUstep NSArchiver archive. Every value in it carries a type
 * tag, so the reader keeps each value exactly as archived: its tag, its
 * width and its bytes. Objects are split into the fields that the
 * non-keyed -initWithCoder: of the archived class reads in libs-gui and
 * libs-base, under the names of the instance variables they fill. Writing
 * the archive back numbers the objects, classes and selectors in the order
 * it writes them, as NSArchiver does, so an unchanged archive is written
 * byte for byte as it was read, and an edited one stays consistent.
 *
 * Foundation only, so it works with Cocoa as well as with GNUstep.
 */

#ifndef _PCGormArchive_h_
#define _PCGormArchive_h_

#import <Foundation/Foundation.h>

@class PCGormObject;
@class PCGormArchive;

typedef enum
{
  PCGormScalar,        // char, int, float... with the tag's width
  PCGormStruct,        // members in order
  PCGormObjectValue,   // an object (its definition or a reference to it)
  PCGormNil,           // nil object, class, selector or C string
  PCGormClassValue,    // a Class value
  PCGormSelector,      // a SEL
  PCGormCString,       // a char *
  PCGormScalarArray,   // a C array of scalars
  PCGormObjectArray    // a C array of objects
} PCGormValueKind;

@interface PCGormValue : NSObject
{
@public
  PCGormValueKind kind;
  uint8_t         tag;          // as archived; crossref widths are recomputed
  NSData          *bytes;       // scalar or array element bytes, big-endian;
                                // selector name or C string bytes
  NSData          *types;       // selector type string
  NSData          *countBytes;  // array count as archived
  NSUInteger      count;        // array element count
  uint8_t         elementTag;   // scalar arrays
  NSMutableArray  *members;     // struct members, object array elements
  PCGormObject    *object;      // object values
  PCGormValue     *definition;  // selector and C string references
  NSString        *className;   // class values
  BOOL            isReference;  // refers to an earlier object or pointer
}
+ (PCGormValue *)valueWithDouble:(double)value likeValue:(PCGormValue *)value;
- (PCGormValueKind)kind;
/* Scalars */
- (double)doubleValue;
- (long long)longLongValue;
- (BOOL)boolValue;
/* Scalar arrays: the elements as numbers. */
- (NSArray *)numbers;
/* Selectors and C strings */
- (NSString *)stringValue;
/* Structs: the scalar members, flattened (a rect is x, y, width, height). */
- (NSArray *)flattenedNumbers;
/* Object values */
- (PCGormObject *)object;
@end

@interface PCGormObject : NSObject
{
@public
  PCGormArchive  *archive;      // not retained
  NSUInteger     identifier;    // the crossref number when read; stable
  NSString       *className;    // the archived class (GSWindowTemplate...)
  NSString       *realClassName;// the class it stands for (NSPanel...)
  NSString       *customClass;  // the custom class of a class swapper
  NSMutableArray *names;        // field names, in archive order
  NSMutableArray *values;       // PCGormValue for each name
}
- (NSUInteger)identifier;
- (NSString *)className;
/* NSPanel for a GSWindowTemplate; else the archived class. */
- (NSString *)realClassName;
/* The custom class a template stands in for, or nil. */
- (NSString *)customClass;
- (BOOL)isKindOfClassNamed:(NSString *)name;

/* Fields, by the name of the instance variable they fill. */
- (PCGormValue *)valueForField:(NSString *)name;
- (BOOL)hasField:(NSString *)name;
- (PCGormObject *)objectForField:(NSString *)name;
- (NSString *)stringForField:(NSString *)name;
- (double)doubleForField:(NSString *)name;
- (long long)integerForField:(NSString *)name;
- (BOOL)boolForField:(NSString *)name;
- (NSRect)rectForField:(NSString *)name;
- (NSSize)sizeForField:(NSString *)name;
- (NSPoint)pointForField:(NSString *)name;

/* Foundation values */
- (BOOL)isString;
- (NSString *)stringValue;
/* Elements of an NSArray or NSSet (PCGormObject or nil). */
- (NSArray *)arrayValue;
/* Pairs of an NSDictionary, each an NSArray of key and value. */
- (NSArray *)pairsValue;
/* Contents of NSData */
- (NSData *)dataValue;
/* NSNumber */
- (double)numberValue;

/* Editing. The string becomes a new NSString in the archive. */
- (void)setString:(NSString *)string forField:(NSString *)name;
- (void)setRect:(NSRect)rect forField:(NSString *)name;
- (void)setSize:(NSSize)size forField:(NSString *)name;
@end

@interface PCGormArchive : NSObject
{
  NSString            *header;     // after the prefix: version and counts
  unsigned            version;
  PCGormValue         *root;
  NSMutableDictionary *versions;   // class name -> version
  NSMutableDictionary *supers;     // class name -> superclass, as archived
  NSMutableArray      *objects;    // every object, in archive order
  NSUInteger          nextIdentifier;
}
+ (PCGormArchive *)archiveWithData:(NSData *)data error:(NSString **)error;
+ (PCGormArchive *)archiveWithContentsOfFile:(NSString *)path error:(NSString **)error;
/* The archive written back. */
- (NSData *)data;
- (PCGormObject *)rootObject;
/* Every object, in archive order (new ones last). */
- (NSArray *)allObjects;
- (PCGormObject *)objectWithIdentifier:(NSUInteger)identifier;
/* The version a class was archived with (0 if it isn't in the archive). */
- (unsigned)versionOfClass:(NSString *)name;
@end

#endif
