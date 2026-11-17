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

#import "PCGormArchive.h"

/* Type tags of the GNUstep archive format (libs-base, NSData.h). */
#define GSC_NONE      0x00
#define GSC_XREF      0x80
#define GSC_SIZE      0x60
#define GSC_MASK      0x1f
#define GSC_MAYX      0x10
#define GSC_CHR       0x01
#define GSC_UCHR      0x02
#define GSC_SHT       0x03
#define GSC_USHT      0x04
#define GSC_INT       0x05
#define GSC_UINT      0x06
#define GSC_LNG       0x07
#define GSC_ULNG      0x08
#define GSC_LNG_LNG   0x09
#define GSC_ULNG_LNG  0x0a
#define GSC_FLT       0x0b
#define GSC_DBL       0x0c
#define GSC_BOOL      0x0d
#define GSC_ID        0x10
#define GSC_CLASS     0x11
#define GSC_SEL       0x12
#define GSC_PTR       0x13
#define GSC_CHARPTR   0x14
#define GSC_ARY_B     0x15
#define GSC_STRUCT_B  0x16
#define GSC_CID       0x17

static NSString * const PCGormPrefix = @"GNUstep archive";
static NSString * const PCGormDecodeException = @"PCGormDecodeException";

static BOOL IsScalarTag(uint8_t tag)
{
  uint8_t base = tag & GSC_MASK;
  return base >= GSC_CHR && base <= GSC_BOOL;
}

static NSUInteger ScalarWidth(uint8_t tag)
{
  switch (tag & GSC_MASK)
  {
    case GSC_CHR: case GSC_UCHR: case GSC_BOOL: return 1;
    case GSC_FLT: return 4;
    case GSC_DBL: return 8;
    default:
      switch (tag & GSC_SIZE)
      {
        case 0x00: return 2;
        case 0x20: return 4;
        case 0x40: return 8;
        default:   return 16;
      }
  }
}

static BOOL IsSigned(uint8_t tag)
{
  uint8_t base = tag & GSC_MASK;
  return base == GSC_CHR || base == GSC_SHT || base == GSC_INT
    || base == GSC_LNG || base == GSC_LNG_LNG;
}

/* Big-endian bytes of a scalar as a double. */
static double ScalarDouble(uint8_t tag, const uint8_t *p)
{
  uint8_t base = tag & GSC_MASK;
  NSUInteger width = ScalarWidth(tag);
  uint64_t raw = 0;
  NSUInteger i;

  if (base == GSC_FLT)
  {
    uint32_t bits = ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16)
      | ((uint32_t)p[2] << 8) | p[3];
    float f;

    memcpy(&f, &bits, 4);
    return f;
  }
  if (base == GSC_DBL)
  {
    double d;

    for (i = 0; i < 8; i++)
    {
      raw = (raw << 8) | p[i];
    }
    memcpy(&d, &raw, 8);
    return d;
  }
  /* 128-bit integers: the low 64 bits. */
  for (i = (width > 8 ? width - 8 : 0); i < width; i++)
  {
    raw = (raw << 8) | p[i];
  }
  if (IsSigned(tag) && width < 8 && (raw & ((uint64_t)1 << (width * 8 - 1))))
  {
    raw |= ~(uint64_t)0 << (width * 8);
  }
  return IsSigned(tag) ? (double)(int64_t)raw : (double)raw;
}

static long long ScalarLongLong(uint8_t tag, const uint8_t *p)
{
  uint8_t base = tag & GSC_MASK;
  NSUInteger width = ScalarWidth(tag);
  uint64_t raw = 0;
  NSUInteger i;

  if (base == GSC_FLT || base == GSC_DBL)
  {
    return (long long)ScalarDouble(tag, p);
  }
  for (i = (width > 8 ? width - 8 : 0); i < width; i++)
  {
    raw = (raw << 8) | p[i];
  }
  if (IsSigned(tag) && width < 8 && (raw & ((uint64_t)1 << (width * 8 - 1))))
  {
    raw |= ~(uint64_t)0 << (width * 8);
  }
  return (long long)raw;
}

static NSData *ScalarBytes(uint8_t tag, double value)
{
  uint8_t base = tag & GSC_MASK;
  NSUInteger width = ScalarWidth(tag);
  uint8_t buffer[16];
  uint64_t raw;
  NSUInteger i;

  memset(buffer, 0, sizeof(buffer));
  if (base == GSC_FLT)
  {
    float f = (float)value;
    uint32_t bits;

    memcpy(&bits, &f, 4);
    raw = bits;
  }
  else if (base == GSC_DBL)
  {
    memcpy(&raw, &value, 8);
  }
  else
  {
    raw = IsSigned(tag) ? (uint64_t)(int64_t)llround(value) : (uint64_t)llround(value);
  }
  for (i = 0; i < width && i < 8; i++)
  {
    buffer[width - 1 - i] = (uint8_t)(raw >> (8 * i));
  }
  return [NSData dataWithBytes:buffer length:width];
}

// ============================================================================
// ==== Values and objects
// ============================================================================

@implementation PCGormValue

+ (PCGormValue *)valueWithDouble:(double)value likeValue:(PCGormValue *)other
{
  PCGormValue *result = [[[PCGormValue alloc] init] autorelease];

  result->kind = PCGormScalar;
  result->tag = other->tag;
  result->bytes = [ScalarBytes(other->tag, value) retain];
  return result;
}

- (void)dealloc
{
  [bytes release];
  [types release];
  [countBytes release];
  [members release];
  [object release];
  [definition release];
  [className release];
  [super dealloc];
}

- (PCGormValueKind)kind
{
  return kind;
}

- (double)doubleValue
{
  return kind == PCGormScalar ? ScalarDouble(tag, [bytes bytes]) : 0.0;
}

- (long long)longLongValue
{
  return kind == PCGormScalar ? ScalarLongLong(tag, [bytes bytes]) : 0;
}

- (BOOL)boolValue
{
  return [self longLongValue] != 0;
}

- (NSArray *)numbers
{
  NSMutableArray *result = [NSMutableArray array];
  NSUInteger     width = ScalarWidth(elementTag);
  const uint8_t  *p = [bytes bytes];
  NSUInteger     i;

  for (i = 0; kind == PCGormScalarArray && i < count; i++)
  {
    [result addObject:[NSNumber numberWithDouble:ScalarDouble(elementTag, p + i * width)]];
  }
  return result;
}

- (NSString *)stringValue
{
  PCGormValue *source = definition ? definition : self;

  if (source->bytes == nil)
  {
    return nil;
  }
  return [[[NSString alloc] initWithData:source->bytes encoding:NSUTF8StringEncoding] autorelease];
}

- (NSArray *)flattenedNumbers
{
  NSMutableArray *result = [NSMutableArray array];

  if (kind == PCGormScalar)
  {
    [result addObject:[NSNumber numberWithDouble:[self doubleValue]]];
  }
  for (PCGormValue *member in members)
  {
    [result addObjectsFromArray:[member flattenedNumbers]];
  }
  return result;
}

- (PCGormObject *)object
{
  return kind == PCGormObjectValue ? object : nil;
}

@end

@interface PCGormArchive (Private)
- (PCGormObject *)_newObjectOfClass:(NSString *)name;
- (void)_registerObject:(PCGormObject *)object;
- (unsigned)_version;
@end

@implementation PCGormObject

- (id)init
{
  if ((self = [super init]))
  {
    names = [NSMutableArray new];
    values = [NSMutableArray new];
  }
  return self;
}

- (void)dealloc
{
  [className release];
  [realClassName release];
  [customClass release];
  [names release];
  [values release];
  [super dealloc];
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"<%@ #%lu>", customClass ? customClass : [self realClassName],
          (unsigned long)identifier];
}

- (NSUInteger)identifier { return identifier; }
- (NSString *)className { return className; }
- (NSString *)realClassName { return realClassName ? realClassName : className; }
- (NSString *)customClass { return customClass; }

- (BOOL)isKindOfClassNamed:(NSString *)name
{
  return [[self realClassName] isEqualToString:name];
}

- (void)_addField:(NSString *)name value:(PCGormValue *)value
{
  [names addObject:name];
  [values addObject:value];
}

- (PCGormValue *)valueForField:(NSString *)name
{
  NSUInteger index = [names indexOfObject:name];

  return index == NSNotFound ? nil : [values objectAtIndex:index];
}

- (BOOL)hasField:(NSString *)name
{
  return [names containsObject:name];
}

- (PCGormObject *)objectForField:(NSString *)name
{
  return [[self valueForField:name] object];
}

- (NSString *)stringForField:(NSString *)name
{
  PCGormObject *value = [self objectForField:name];

  return [value isString] ? [value stringValue] : nil;
}

- (double)doubleForField:(NSString *)name
{
  return [[self valueForField:name] doubleValue];
}

- (long long)integerForField:(NSString *)name
{
  return [[self valueForField:name] longLongValue];
}

- (BOOL)boolForField:(NSString *)name
{
  return [[self valueForField:name] boolValue];
}

- (NSRect)rectForField:(NSString *)name
{
  NSArray *n = [[self valueForField:name] flattenedNumbers];

  if ([n count] < 4)
  {
    return NSZeroRect;
  }
  return NSMakeRect([[n objectAtIndex:0] doubleValue], [[n objectAtIndex:1] doubleValue],
                    [[n objectAtIndex:2] doubleValue], [[n objectAtIndex:3] doubleValue]);
}

- (NSSize)sizeForField:(NSString *)name
{
  NSArray *n = [[self valueForField:name] flattenedNumbers];

  if ([n count] < 2)
  {
    return NSZeroSize;
  }
  return NSMakeSize([[n objectAtIndex:0] doubleValue], [[n objectAtIndex:1] doubleValue]);
}

- (NSPoint)pointForField:(NSString *)name
{
  NSSize size = [self sizeForField:name];

  return NSMakePoint(size.width, size.height);
}

// --- Foundation values

- (BOOL)isString
{
  return [self hasField:@"characters"] || ([self hasField:@"count"]
                                           && [names count] == 1
                                           && [className rangeOfString:@"String"].location != NSNotFound);
}

- (NSString *)stringValue
{
  PCGormValue *characters = [self valueForField:@"characters"];
  long long   encoding = [self integerForField:@"encoding"];
  NSData      *data;

  if (characters == nil)
  {
    return @"";
  }
  data = characters->bytes;
  if ((characters->elementTag & GSC_MASK) == GSC_USHT || encoding == 10)
  {
    NSUInteger length = characters->count;
    unichar    *buffer = malloc(sizeof(unichar) * (length ? length : 1));
    const uint8_t *p = [data bytes];
    NSUInteger i;
    NSString   *string;

    for (i = 0; i < length; i++)
    {
      buffer[i] = (unichar)((p[2 * i] << 8) | p[2 * i + 1]);
    }
    string = [NSString stringWithCharacters:buffer length:length];
    free(buffer);
    return string;
  }
  if (encoding == 4)
  {
    return [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
  }
  if (encoding == 1)
  {
    return [[[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding] autorelease];
  }
  return [[[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] autorelease];
}

- (NSArray *)arrayValue
{
  NSMutableArray *result = [NSMutableArray array];
  PCGormValue    *list = [self valueForField:@"objects"];
  NSUInteger     i;

  for (PCGormValue *value in (list ? list->members : nil))
  {
    [result addObject:[value object] ? (id)[value object] : (id)[NSNull null]];
  }
  /* Sets keep each member in an "object" field. */
  for (i = 0; i < [names count]; i++)
  {
    if ([[names objectAtIndex:i] isEqualToString:@"object"])
    {
      PCGormObject *member = [[values objectAtIndex:i] object];

      [result addObject:member ? (id)member : (id)[NSNull null]];
    }
  }
  return result;
}

- (NSArray *)pairsValue
{
  NSMutableArray *result = [NSMutableArray array];
  NSUInteger     i;

  for (i = 0; i + 1 < [names count]; i++)
  {
    if ([[names objectAtIndex:i] isEqualToString:@"key"]
        && [[names objectAtIndex:i + 1] isEqualToString:@"value"])
    {
      id key = [[values objectAtIndex:i] object];
      id value = [[values objectAtIndex:i + 1] object];

      [result addObject:[NSArray arrayWithObjects:key ? key : (id)[NSNull null],
                         value ? value : (id)[NSNull null], nil]];
      i++;
    }
  }
  return result;
}

- (NSData *)dataValue
{
  PCGormValue *contents = [self valueForField:@"bytes"];

  return contents ? contents->bytes : [NSData data];
}

- (double)numberValue
{
  return [self doubleForField:@"value"];
}

// --- Editing

- (void)_replaceField:(NSString *)name with:(PCGormValue *)value
{
  NSUInteger index = [names indexOfObject:name];

  if (index != NSNotFound)
  {
    [values replaceObjectAtIndex:index withObject:value];
  }
}

- (void)setString:(NSString *)string forField:(NSString *)name
{
  PCGormObject   *text = [archive _newObjectOfClass:@"NSString"];
  PCGormValue    *value = [[[PCGormValue alloc] init] autorelease];
  PCGormValue    *count = [[[PCGormValue alloc] init] autorelease];
  NSData         *latin = [string dataUsingEncoding:NSISOLatin1StringEncoding];
  NSUInteger     length = latin ? [latin length] : [string length];

  /* As NSString's -encodeWithCoder: in libs-base: count, then encoding
   * and characters unless empty. */
  count->kind = PCGormScalar;
  count->tag = GSC_UINT | 0x20;
  count->bytes = [ScalarBytes(count->tag, length) retain];
  [text _addField:@"count" value:count];
  if (length > 0)
  {
    PCGormValue *encoding = [[[PCGormValue alloc] init] autorelease];
    PCGormValue *characters = [[[PCGormValue alloc] init] autorelease];
    NSMutableData *data = [NSMutableData data];
    uint8_t     count32[4];

    encoding->kind = PCGormScalar;
    encoding->tag = GSC_INT | 0x20;
    encoding->bytes = [ScalarBytes(encoding->tag, latin ? 5 : 10) retain];
    [text _addField:@"encoding" value:encoding];

    characters->kind = PCGormScalarArray;
    characters->tag = GSC_ARY_B;
    characters->count = length;
    if (latin)
    {
      characters->elementTag = GSC_UCHR;
      [data appendData:latin];
    }
    else
    {
      NSUInteger i;

      characters->elementTag = GSC_USHT;
      for (i = 0; i < length; i++)
      {
        unichar c = [string characterAtIndex:i];
        uint8_t pair[2] = { (uint8_t)(c >> 8), (uint8_t)c };

        [data appendBytes:pair length:2];
      }
    }
    characters->bytes = [data copy];
    if ([archive _version] == 12402)
    {
      characters->countBytes = nil;   // the writer encodes it
    }
    else
    {
      count32[0] = (uint8_t)(length >> 24);
      count32[1] = (uint8_t)(length >> 16);
      count32[2] = (uint8_t)(length >> 8);
      count32[3] = (uint8_t)length;
      characters->countBytes = [[NSData alloc] initWithBytes:count32 length:4];
    }
    [text _addField:@"characters" value:characters];
  }
  value->kind = PCGormObjectValue;
  value->tag = GSC_ID;
  value->object = [text retain];
  if ([self hasField:name])
  {
    [self _replaceField:name with:value];
  }
}

- (void)_setNumbers:(NSArray *)numbers forField:(NSString *)name
{
  PCGormValue    *value = [self valueForField:name];
  NSMutableArray *scalars = [NSMutableArray array];
  NSMutableArray *stack = [NSMutableArray arrayWithObject:value];
  NSUInteger     i;

  /* The scalar members, in order, of a (nested) struct. */
  while ([stack count])
  {
    PCGormValue *top = [[[stack objectAtIndex:0] retain] autorelease];

    [stack removeObjectAtIndex:0];
    if (top->kind == PCGormScalar)
    {
      [scalars addObject:top];
    }
    else
    {
      [stack replaceObjectsInRange:NSMakeRange(0, 0) withObjectsFromArray:top->members];
    }
  }
  for (i = 0; i < [scalars count] && i < [numbers count]; i++)
  {
    PCGormValue *scalar = [scalars objectAtIndex:i];

    [scalar->bytes release];
    scalar->bytes = [ScalarBytes(scalar->tag, [[numbers objectAtIndex:i] doubleValue]) retain];
  }
}

- (void)setRect:(NSRect)rect forField:(NSString *)name
{
  [self _setNumbers:[NSArray arrayWithObjects:
                     [NSNumber numberWithDouble:rect.origin.x],
                     [NSNumber numberWithDouble:rect.origin.y],
                     [NSNumber numberWithDouble:rect.size.width],
                     [NSNumber numberWithDouble:rect.size.height], nil]
           forField:name];
}

- (void)setSize:(NSSize)size forField:(NSString *)name
{
  [self _setNumbers:[NSArray arrayWithObjects:
                     [NSNumber numberWithDouble:size.width],
                     [NSNumber numberWithDouble:size.height], nil]
           forField:name];
}

@end

// ============================================================================
// ==== Reading
// ============================================================================

/* The superclass of each class a .gorm may contain. The archive names a
 * superclass only the first time it is written, so the hierarchy needed to
 * call each class's decoding comes from here. */
static NSDictionary *SuperclassTable(void)
{
  static NSDictionary *table = nil;

  if (table == nil)
  {
    table = [[NSDictionary alloc] initWithObjectsAndKeys:
             @"NSObject", @"NSResponder", @"NSResponder", @"NSView",
             @"NSView", @"NSControl", @"NSControl", @"NSButton",
             @"NSButton", @"NSPopUpButton", @"NSControl", @"NSTextField",
             @"NSTextField", @"NSSecureTextField", @"NSTextField", @"NSSearchField",
             @"NSTextField", @"NSComboBox", @"NSControl", @"NSImageView",
             @"NSControl", @"NSSlider", @"NSControl", @"NSMatrix",
             @"NSControl", @"NSColorWell", @"NSControl", @"NSTableView",
             @"NSTableView", @"NSOutlineView", @"NSControl", @"NSBrowser",
             @"NSControl", @"NSStepper", @"NSControl", @"NSScroller",
             @"NSView", @"NSBox", @"NSView", @"NSScrollView", @"NSView", @"NSClipView",
             @"NSView", @"NSSplitView", @"NSView", @"NSTabView",
             @"NSView", @"NSTableHeaderView", @"NSView", @"GSTableCornerView",
             @"NSView", @"NSText", @"NSText", @"NSTextView",
             @"NSResponder", @"NSWindow", @"NSWindow", @"NSPanel",
             @"NSObject", @"NSCell", @"NSCell", @"NSActionCell",
             @"NSActionCell", @"NSButtonCell", @"NSButtonCell", @"NSMenuItemCell",
             @"NSMenuItemCell", @"NSPopUpButtonCell", @"NSActionCell", @"NSTextFieldCell",
             @"NSTextFieldCell", @"NSTableHeaderCell", @"NSCell", @"NSImageCell",
             @"NSActionCell", @"NSSliderCell", @"NSCell", @"NSBrowserCell",
             @"NSObject", @"NSMenu", @"NSObject", @"NSMenuItem",
             @"NSObject", @"NSTableColumn", @"NSObject", @"NSImage",
             @"NSObject", @"NSImageRep", @"NSImageRep", @"NSBitmapImageRep",
             @"NSObject", @"NSColor", @"NSObject", @"NSFont",
             @"NSObject", @"NSNibConnector", @"NSNibConnector", @"NSNibControlConnector",
             @"NSNibConnector", @"NSNibOutletConnector",
             @"NSObject", @"GSNibContainer", @"NSObject", @"GSNibItem",
             @"GSNibItem", @"GSCustomView", @"NSObject", @"GSClassSwapper",
             @"GSClassSwapper", @"GSWindowTemplate", @"GSClassSwapper", @"GSViewTemplate",
             @"GSClassSwapper", @"GSTextTemplate", @"GSClassSwapper", @"GSTextViewTemplate",
             @"GSClassSwapper", @"GSMenuTemplate", @"GSClassSwapper", @"GSControlTemplate",
             @"GSClassSwapper", @"GSObjectTemplate",
             nil];
  }
  return table;
}

static BOOL ClassIn(NSString *name, NSArray *list)
{
  return [list containsObject:name];
}

@interface PCGormReader : NSObject
{
@public
  const uint8_t       *bytes;
  NSUInteger          length;
  NSUInteger          pos;
  unsigned            version;
  PCGormArchive       *archive;
  NSMutableDictionary *classes;    // xref -> name
  NSMutableDictionary *objects;    // xref -> PCGormObject
  NSMutableDictionary *pointers;   // xref -> PCGormValue
  NSMutableDictionary *versions;   // name -> version
  NSMutableDictionary *supers;     // name -> super, as archived
}
@end

@implementation PCGormReader

- (id)init
{
  if ((self = [super init]))
  {
    classes = [NSMutableDictionary new];
    objects = [NSMutableDictionary new];
    pointers = [NSMutableDictionary new];
    versions = [NSMutableDictionary new];
    supers = [NSMutableDictionary new];
  }
  return self;
}

- (void)dealloc
{
  [classes release];
  [objects release];
  [pointers release];
  [versions release];
  [supers release];
  [super dealloc];
}

- (void)fail:(NSString *)format, ...
{
  va_list  args;
  NSString *reason;

  va_start(args, format);
  reason = [[[NSString alloc] initWithFormat:format arguments:args] autorelease];
  va_end(args);
  [NSException raise:PCGormDecodeException format:@"%@ (at byte %lu)", reason, (unsigned long)pos];
}

- (const uint8_t *)read:(NSUInteger)n
{
  const uint8_t *p;

  if (pos + n > length)
  {
    [self fail:@"unexpected end of archive"];
  }
  p = bytes + pos;
  pos += n;
  return p;
}

- (unsigned)u8 { return *[self read:1]; }
- (unsigned)u16 { const uint8_t *p = [self read:2]; return (p[0] << 8) | p[1]; }
- (unsigned)u32
{
  const uint8_t *p = [self read:4];
  return ((unsigned)p[0] << 24) | ((unsigned)p[1] << 16) | ((unsigned)p[2] << 8) | p[3];
}

- (uint8_t)peekTag
{
  if (pos >= length)
  {
    [self fail:@"unexpected end of archive"];
  }
  return bytes[pos];
}

- (uint8_t)tag:(unsigned *)xref
{
  uint8_t tag = [self u8];

  *xref = 0;
  if (tag & GSC_MAYX)
  {
    switch (tag & GSC_SIZE)
    {
      case 0x20: *xref = [self u8]; break;
      case 0x40: *xref = [self u16]; break;
      case 0x60: *xref = [self u32]; break;
      default: break;
    }
  }
  return tag;
}

- (unsigned)version:(NSString *)name
{
  return [[versions objectForKey:name] unsignedIntValue];
}

// --- Values

- (PCGormValue *)scalar
{
  unsigned    xref;
  uint8_t     tag = [self tag:&xref];
  PCGormValue *value;

  if (!IsScalarTag(tag))
  {
    pos--;
    [self fail:@"expected a scalar, found tag 0x%02x", tag];
  }
  value = [[[PCGormValue alloc] init] autorelease];
  value->kind = PCGormScalar;
  value->tag = tag;
  value->bytes = [[NSData alloc] initWithBytes:[self read:ScalarWidth(tag)]
                                        length:ScalarWidth(tag)];
  return value;
}

/* A struct with the given members: numbers are scalars, arrays nested
 * structs (a rect is @[@2, @2]). */
- (PCGormValue *)structOf:(NSArray *)layout
{
  unsigned    xref;
  uint8_t     tag = [self tag:&xref];
  PCGormValue *value;

  if ((tag & GSC_MASK) != GSC_STRUCT_B)
  {
    [self fail:@"expected a struct, found tag 0x%02x", tag];
  }
  value = [[[PCGormValue alloc] init] autorelease];
  value->kind = PCGormStruct;
  value->tag = tag;
  value->members = [NSMutableArray new];
  for (id member in layout)
  {
    if ([member isKindOfClass:[NSArray class]])
    {
      [value->members addObject:[self structOf:member]];
    }
    else
    {
      NSUInteger i;

      for (i = 0; i < [member unsignedIntegerValue]; i++)
      {
        [value->members addObject:[self scalar]];
      }
    }
  }
  return value;
}

- (PCGormValue *)rect
{
  return [self structOf:@[@[@2], @[@2]]];
}

- (PCGormValue *)size
{
  return [self structOf:@[@2]];
}

- (NSData *)countBytes:(NSUInteger *)count
{
  NSUInteger start = pos;

  *count = 0;
  if (version == 12402)
  {
    for (;;)
    {
      unsigned c = [self u8];

      *count *= 128;
      if (c & 128)
      {
        *count += c & 127;
      }
      else
      {
        *count += c;
        break;
      }
    }
  }
  else
  {
    *count = [self u32];
    if (*count == 0xffffffff)
    {
      const uint8_t *p = [self read:8];
      NSUInteger i;

      *count = 0;
      for (i = 0; i < 8; i++)
      {
        *count = (*count << 8) | p[i];
      }
    }
  }
  return [NSData dataWithBytes:bytes + start length:pos - start];
}

- (PCGormValue *)scalarArray
{
  unsigned    xref;
  uint8_t     tag = [self tag:&xref];
  PCGormValue *value;
  NSUInteger  count;

  if ((tag & GSC_MASK) != GSC_ARY_B)
  {
    [self fail:@"expected an array, found tag 0x%02x", tag];
  }
  value = [[[PCGormValue alloc] init] autorelease];
  value->kind = PCGormScalarArray;
  value->tag = tag;
  value->countBytes = [[self countBytes:&count] retain];
  value->count = count;
  value->elementTag = [self tag:&xref];
  if (!IsScalarTag(value->elementTag))
  {
    [self fail:@"expected scalar array elements"];
  }
  value->bytes = [[NSData alloc] initWithBytes:[self read:count * ScalarWidth(value->elementTag)]
                                        length:count * ScalarWidth(value->elementTag)];
  return value;
}

- (PCGormValue *)objectArray
{
  unsigned    xref;
  uint8_t     tag = [self tag:&xref];
  PCGormValue *value;
  NSUInteger  count, i;

  if ((tag & GSC_MASK) != GSC_ARY_B)
  {
    [self fail:@"expected an array, found tag 0x%02x", tag];
  }
  value = [[[PCGormValue alloc] init] autorelease];
  value->kind = PCGormObjectArray;
  value->tag = tag;
  value->countBytes = [[self countBytes:&count] retain];
  value->count = count;
  value->members = [NSMutableArray new];
  for (i = 0; i < count; i++)
  {
    [value->members addObject:[self object]];
  }
  return value;
}

- (PCGormValue *)selector
{
  unsigned    xref;
  uint8_t     tag = [self tag:&xref];
  PCGormValue *value = [[[PCGormValue alloc] init] autorelease];

  if ((tag & GSC_MASK) != GSC_SEL)
  {
    [self fail:@"expected a selector, found tag 0x%02x", tag];
  }
  value->tag = tag;
  if ((tag & GSC_SIZE) == 0)
  {
    value->kind = PCGormNil;
    return value;
  }
  value->kind = PCGormSelector;
  if (tag & GSC_XREF)
  {
    value->isReference = YES;
    value->definition = [[pointers objectForKey:[NSNumber numberWithUnsignedInt:xref]] retain];
    if (value->definition == nil)
    {
      [self fail:@"dangling selector reference %u", xref];
    }
    return value;
  }
  {
    unsigned nameLength = [self u16];
    unsigned typesLength = [self u16];

    value->bytes = [[NSData alloc] initWithBytes:[self read:nameLength] length:nameLength];
    value->types = [[NSData alloc] initWithBytes:[self read:typesLength] length:typesLength];
  }
  [pointers setObject:value forKey:[NSNumber numberWithUnsignedInt:xref]];
  return value;
}

/* A class (and the superclasses written with it). */
- (PCGormValue *)classValue
{
  unsigned    xref;
  uint8_t     tag = [self tag:&xref];
  PCGormValue *value = [[[PCGormValue alloc] init] autorelease];
  NSString    *previous = nil;

  if ((tag & GSC_MASK) != GSC_CLASS)
  {
    [self fail:@"expected a class, found tag 0x%02x", tag];
  }
  value->tag = tag;
  if ((tag & GSC_SIZE) == 0)
  {
    value->kind = PCGormNil;
    return value;
  }
  value->kind = PCGormClassValue;
  if (tag & GSC_XREF)
  {
    value->isReference = YES;
    value->className = [[classes objectForKey:[NSNumber numberWithUnsignedInt:xref]] copy];
    if (value->className == nil)
    {
      [self fail:@"dangling class reference %u", xref];
    }
    return value;
  }
  while ((tag & GSC_MASK) == GSC_CLASS)
  {
    unsigned nameLength = [self u16];
    NSString *name = [[[NSString alloc] initWithBytes:[self read:nameLength]
                                               length:nameLength
                                             encoding:NSUTF8StringEncoding] autorelease];
    unsigned classVersion = [self u32];

    [classes setObject:name forKey:[NSNumber numberWithUnsignedInt:xref]];
    [versions setObject:[NSNumber numberWithUnsignedInt:classVersion] forKey:name];
    if (previous)
    {
      [supers setObject:name forKey:previous];
    }
    else
    {
      value->className = [name copy];
    }
    previous = name;
    tag = [self tag:&xref];
  }
  if (tag != GSC_NONE)
  {
    [self fail:@"class list improperly terminated"];
  }
  return value;
}

- (PCGormValue *)object
{
  unsigned    xref;
  uint8_t     tag = [self tag:&xref];
  PCGormValue *value = [[[PCGormValue alloc] init] autorelease];
  NSNumber    *key = [NSNumber numberWithUnsignedInt:xref];
  PCGormValue *classValue;
  PCGormObject *object;

  if ((tag & GSC_MASK) != GSC_ID && (tag & GSC_MASK) != GSC_CID)
  {
    pos--;
    [self fail:@"expected an object, found tag 0x%02x", tag];
  }
  value->tag = tag;
  if ((tag & GSC_SIZE) == 0)
  {
    value->kind = PCGormNil;
    return value;
  }
  value->kind = PCGormObjectValue;
  if (tag & GSC_XREF)
  {
    value->isReference = YES;
    value->object = [[objects objectForKey:key] retain];
    if (value->object == nil)
    {
      [self fail:@"dangling object reference %u", xref];
    }
    return value;
  }
  classValue = [self classValue];
  if (classValue->kind != PCGormClassValue)
  {
    [self fail:@"object of nil class"];
  }
  object = [[PCGormObject alloc] init];
  object->archive = archive;
  object->identifier = xref;
  object->className = [classValue->className copy];
  value->object = object;
  [objects setObject:object forKey:key];
  [archive _registerObject:object];
  [self decodeObject:object asClass:object->className];
  return value;
}

/* The class and its superclasses, root first, without NSObject. */
- (NSArray *)hierarchyOf:(NSString *)name
{
  NSMutableArray *chain = [NSMutableArray array];
  NSString       *c = name;

  while (c != nil && ![c isEqualToString:@"NSObject"])
  {
    NSString *next = [SuperclassTable() objectForKey:c];

    [chain insertObject:c atIndex:0];
    if (next == nil)
    {
      next = [supers objectForKey:c];
    }
    if (next == nil)
    {
      [self fail:@"unknown superclass of %@", c];
    }
    c = next;
  }
  return chain;
}

- (void)decodeObject:(PCGormObject *)o asClass:(NSString *)name
{
  NSArray *strings = @[@"NSString", @"NSMutableString", @"GSString", @"GSCString",
                       @"GSUnicodeString", @"GSMutableString", @"NSConstantString"];
  NSArray *arrays = @[@"NSArray", @"NSMutableArray", @"GSArray", @"GSMutableArray"];
  NSArray *sets = @[@"NSSet", @"NSMutableSet", @"GSSet", @"GSMutableSet", @"NSCountedSet"];
  NSArray *dicts = @[@"NSDictionary", @"NSMutableDictionary", @"GSDictionary",
                     @"GSMutableDictionary"];
  NSArray *datas = @[@"NSData", @"NSMutableData", @"NSDataMalloc", @"NSMutableDataMalloc"];

  if (ClassIn(name, strings))
  {
    PCGormValue *count = [self scalar];

    [o _addField:@"count" value:count];
    if ([count longLongValue] > 0)
    {
      [o _addField:@"encoding" value:[self scalar]];
      [o _addField:@"characters" value:[self scalarArray]];
    }
  }
  else if (ClassIn(name, arrays))
  {
    PCGormValue *count = [self scalar];

    [o _addField:@"count" value:count];
    if ([count longLongValue] > 0)
    {
      [o _addField:@"objects" value:[self objectArray]];
    }
  }
  else if (ClassIn(name, sets))
  {
    PCGormValue *count = [self scalar];
    long long   i;

    [o _addField:@"count" value:count];
    for (i = 0; i < [count longLongValue]; i++)
    {
      [o _addField:@"object" value:[self object]];
    }
  }
  else if (ClassIn(name, dicts))
  {
    PCGormValue *count = [self scalar];
    long long   i;

    [o _addField:@"count" value:count];
    for (i = 0; i < [count longLongValue]; i++)
    {
      [o _addField:@"key" value:[self object]];
      [o _addField:@"value" value:[self object]];
    }
  }
  else if (ClassIn(name, datas))
  {
    PCGormValue *count = [self scalar];

    [o _addField:@"length" value:count];
    if ([count longLongValue] > 0)
    {
      [o _addField:@"type" value:[self scalar]];
      [o _addField:@"bytes" value:[self scalarArray]];
    }
  }
  else if ([name isEqualToString:@"NSNumber"] || [name hasSuffix:@"Number"])
  {
    [o _addField:@"type" value:[self scalar]];
    [o _addField:@"value" value:[self scalar]];
  }
  else if ([name isEqualToString:@"NSValue"] || [name hasSuffix:@"Value"])
  {
    PCGormValue *type;
    NSString    *typeString;

    [o _addField:@"size" value:[self scalar]];
    type = [self scalarArray];
    [o _addField:@"type" value:type];
    typeString = [[[NSString alloc] initWithData:type->bytes encoding:NSASCIIStringEncoding] autorelease];
    typeString = [typeString stringByTrimmingCharactersInSet:
                  [NSCharacterSet characterSetWithCharactersInString:@"\0"]];
    [o _addField:@"value" value:[self valueOfType:typeString]];
  }
  else
  {
    for (NSString *c in [self hierarchyOf:name])
    {
      SEL selector = NSSelectorFromString([NSString stringWithFormat:@"decode%@:", c]);

      if (![self respondsToSelector:selector])
      {
        [self fail:@"no decoding known for class %@", c];
      }
      [self performSelector:selector withObject:o];
    }
  }
}

- (PCGormValue *)valueOfType:(NSString *)type
{
  if ([type hasPrefix:@"{"])
  {
    unsigned    xref;
    uint8_t     tag = [self tag:&xref];
    PCGormValue *value = [[[PCGormValue alloc] init] autorelease];
    NSRange     equals = [type rangeOfString:@"="];
    NSString    *body = [type substringWithRange:
                         NSMakeRange(NSMaxRange(equals), [type length] - NSMaxRange(equals) - 1)];
    NSUInteger  i = 0;

    if ((tag & GSC_MASK) != GSC_STRUCT_B)
    {
      [self fail:@"expected a struct for %@", type];
    }
    value->kind = PCGormStruct;
    value->tag = tag;
    value->members = [NSMutableArray new];
    while (i < [body length])
    {
      if ([body characterAtIndex:i] == '{')
      {
        NSUInteger j = i;
        int depth = 0;

        do
        {
          unichar c = [body characterAtIndex:j];

          if (c == '{') depth++;
          if (c == '}') depth--;
          j++;
        }
        while (depth > 0);
        [value->members addObject:[self valueOfType:[body substringWithRange:NSMakeRange(i, j - i)]]];
        i = j;
      }
      else
      {
        [value->members addObject:[self scalar]];
        i++;
      }
    }
    return value;
  }
  if ([type isEqualToString:@"@"])
  {
    return [self object];
  }
  return [self scalar];
}

// --- Gorm templates (libs-gui, GSGormLoading.m)

- (void)decodeGSNibContainer:(PCGormObject *)o
{
  unsigned v = [self version:@"GSNibContainer"];

  if (v == 2)
  {
    for (NSString *n in @[@"topLevelObjects", @"visibleWindows", @"deferredWindows",
                          @"nameTable", @"connections", @"customClasses"])
    {
      [o _addField:n value:[self object]];
    }
  }
  else if (v == 1)
  {
    for (NSString *n in @[@"nameTable", @"connections", @"topLevelObjects"])
    {
      [o _addField:n value:[self object]];
    }
  }
  else
  {
    [o _addField:@"nameTable" value:[self object]];
    [o _addField:@"connections" value:[self object]];
  }
}

- (void)decodeGSNibItem:(PCGormObject *)o
{
  unsigned v = [versions objectForKey:o->className] ? [self version:o->className]
                                                     : [self version:@"GSNibItem"];

  [o _addField:@"theClass" value:[self object]];
  [o _addField:@"theFrame" value:[self rect]];
  if (v >= 1)
  {
    [o _addField:@"autoresizingMask" value:[self scalar]];
  }
}

- (void)decodeGSCustomView:(PCGormObject *)o
{
}

- (void)decodeGSClassSwapper:(PCGormObject *)o
{
  PCGormValue *custom = [self object];
  PCGormValue *superClass = [self classValue];
  NSString    *customName;

  [o _addField:@"className" value:custom];
  [o _addField:@"superClass" value:superClass];
  if (superClass->kind != PCGormClassValue)
  {
    [self fail:@"class swapper without a class"];
  }
  o->realClassName = [superClass->className copy];
  customName = [[custom object] isString] ? [[custom object] stringValue] : nil;
  if (customName && ![customName isEqualToString:o->realClassName])
  {
    o->customClass = [customName copy];
  }
  /* The object archives itself in place of the template. */
  for (NSString *c in [self hierarchyOf:superClass->className])
  {
    SEL selector = NSSelectorFromString([NSString stringWithFormat:@"decode%@:", c]);

    if (![self respondsToSelector:selector])
    {
      [self fail:@"no decoding known for class %@", c];
    }
    [self performSelector:selector withObject:o];
  }
}

- (void)decodeGSWindowTemplate:(PCGormObject *)o
{
  [o _addField:@"deferFlag" value:[self scalar]];
  if ([self version:@"GSWindowTemplate"] >= 1)
  {
    [o _addField:@"autoPositionMask" value:[self scalar]];
    [o _addField:@"screenRect" value:[self rect]];
  }
}

- (void)decodeGSViewTemplate:(PCGormObject *)o { }
- (void)decodeGSTextTemplate:(PCGormObject *)o { }
- (void)decodeGSTextViewTemplate:(PCGormObject *)o { }
- (void)decodeGSMenuTemplate:(PCGormObject *)o { }
- (void)decodeGSControlTemplate:(PCGormObject *)o { }
- (void)decodeGSObjectTemplate:(PCGormObject *)o { }

- (void)decodeNSNibConnector:(PCGormObject *)o
{
  [o _addField:@"source" value:[self object]];
  [o _addField:@"destination" value:[self object]];
  [o _addField:@"label" value:[self object]];
}

- (void)decodeNSNibControlConnector:(PCGormObject *)o { }
- (void)decodeNSNibOutletConnector:(PCGormObject *)o { }

// --- AppKit (libs-gui, non-keyed -initWithCoder:)

- (void)fields:(NSArray *)fieldList of:(PCGormObject *)o
{
  /* "name:k": k is o (object), s (scalar), r (rect), z (size), p (point),
   * c (selector), C (class), a (scalar array). */
  for (NSString *field in fieldList)
  {
    NSRange  colon = [field rangeOfString:@":"];
    NSString *name = [field substringToIndex:colon.location];
    unichar  kind = [field characterAtIndex:NSMaxRange(colon)];
    PCGormValue *value = nil;

    switch (kind)
    {
      case 'o': value = [self object]; break;
      case 's': value = [self scalar]; break;
      case 'r': value = [self rect]; break;
      case 'z': value = [self size]; break;
      case 'p': value = [self size]; break;
      case 'c': value = [self selector]; break;
      case 'C': value = [self classValue]; break;
      case 'a': value = [self scalarArray]; break;
    }
    [o _addField:name value:value];
  }
}

- (void)decodeNSResponder:(PCGormObject *)o
{
  [self fields:@[@"interfaceStyle:s", @"menu:o"] of:o];
}

- (void)decodeNSView:(PCGormObject *)o
{
  [self fields:@[@"frame:r", @"bounds:r", @"isRotatedFromBase:s",
                 @"isRotatedOrScaledFromBase:s", @"postFrameChanges:s",
                 @"autoresizesSubviews:s", @"autoresizingMask:s",
                 @"nextKeyView:o", @"previousKeyView:o", @"subviews:o"] of:o];
  if ([self version:@"NSView"] >= 2)
  {
    [self fields:@[@"shadow:o"] of:o];
  }
}

- (void)decodeNSControl:(PCGormObject *)o
{
  [self fields:@[@"tag:s", @"cell:o", @"ignoresMultiClick:s"] of:o];
}

- (void)decodeNSButton:(PCGormObject *)o { }
- (void)decodeNSPopUpButton:(PCGormObject *)o { }
- (void)decodeNSSlider:(PCGormObject *)o { }
- (void)decodeNSTableHeaderView:(PCGormObject *)o { }
- (void)decodeGSTableCornerView:(PCGormObject *)o { }
- (void)decodeNSText:(PCGormObject *)o { }

- (void)decodeNSTextField:(PCGormObject *)o
{
  [self fields:@[@"delegate:o", @"errorAction:c"] of:o];
}

- (void)decodeNSImageView:(PCGormObject *)o
{
  unsigned v = [self version:@"NSImageView"];

  if (v >= 2)
  {
    [self fields:@[@"target:o", @"action:c"] of:o];
  }
  if (v >= 3)
  {
    [self fields:@[@"contentTintColor:o"] of:o];
  }
}

- (void)decodeNSColorWell:(PCGormObject *)o
{
  [self fields:@[@"color:o", @"isActive:s", @"isBordered:s", @"target:o", @"action:c"] of:o];
}

- (void)decodeNSBox:(PCGormObject *)o
{
  [self fields:@[@"cell:o", @"offsets:z", @"borderType:s", @"titlePosition:s"] of:o];
}

- (void)decodeNSScroller:(PCGormObject *)o
{
  [self fields:@[@"arrowsPosition:s", @"isEnabled:s", @"target:o", @"action:c"] of:o];
}

- (void)decodeNSScrollView:(PCGormObject *)o
{
  NSArray    *parts = @[@"hasHorizScroller", @"horizScroller", @"hasVertScroller",
                        @"vertScroller", @"hasHorizRuler", @"horizRuler",
                        @"hasVertRuler", @"vertRuler"];
  NSUInteger i;

  [self fields:@[@"contentView:o", @"borderType:s", @"scrollsDynamically:s",
                 @"rulersVisible:s", @"hLineScroll:s", @"hPageScroll:s",
                 @"vLineScroll:s", @"vPageScroll:s"] of:o];
  /* Each scroller and ruler follows its flag only when there is one. */
  for (i = 0; i < [parts count]; i += 2)
  {
    PCGormValue *flag = [self scalar];

    [o _addField:[parts objectAtIndex:i] value:flag];
    if ([flag boolValue])
    {
      [o _addField:[parts objectAtIndex:i + 1] value:[self object]];
    }
  }
  if ([self version:@"NSScrollView"] == 2)
  {
    PCGormValue *flag = [self scalar];

    [o _addField:@"hasHeaderView" value:flag];
    if ([flag boolValue])
    {
      [o _addField:@"headerClipView" value:[self object]];
    }
    [o _addField:@"hasCornerView" value:[self scalar]];
  }
}

- (void)decodeNSClipView:(PCGormObject *)o
{
  [self fields:@[@"backgroundColor:o", @"copiesOnScroll:s", @"drawsBackground:s",
                 @"cursor:o"] of:o];
}

- (void)decodeNSTableView:(PCGormObject *)o
{
  unsigned v = [self version:@"NSTableView"];

  [self fields:@[@"dataSource:o", @"tableColumns:o", @"gridColor:o", @"backgroundColor:o",
                 @"headerView:o", @"cornerView:o", @"delegate:o", @"target:o",
                 @"numberOfRows:s", @"numberOfColumns:s", @"drawsGrid:s", @"rowHeight:s",
                 @"doubleAction:c", @"intercellSpacing:z", @"allowsMultipleSelection:s",
                 @"allowsEmptySelection:s", @"allowsColumnSelection:s",
                 @"allowsColumnResizing:s"] of:o];
  if (v >= 3) [self fields:@[@"allowsColumnReordering:s"] of:o];
  if (v >= 2) [self fields:@[@"autoresizesAllColumnsToFit:s"] of:o];
  if (v >= 4) [self fields:@[@"verticalMotionDrag:s"] of:o];
  if (v >= 5) [self fields:@[@"sortDescriptors:o"] of:o];
  if (v >= 6) [self fields:@[@"viewBased:s"] of:o];
}

- (void)decodeNSTableColumn:(PCGormObject *)o
{
  unsigned v = [self version:@"NSTableColumn"];

  if (v >= 2)
  {
    [self fields:@[@"identifier:o", @"width:s", @"minWidth:s", @"maxWidth:s",
                   @"isResizable:s", @"isEditable:s", @"headerCell:o", @"dataCell:o"] of:o];
    if (v >= 3) [self fields:@[@"sortDescriptorPrototype:o"] of:o];
    if (v >= 4) [self fields:@[@"tableView:o", @"prototypeCellViews:o"] of:o];
  }
  else
  {
    [self fields:@[@"identifier:o", @"headerCell:o", @"dataCell:o", @"width:s",
                   @"minWidth:s", @"maxWidth:s", @"isResizable:s", @"isEditable:s"] of:o];
  }
}

- (void)decodeNSTextView:(PCGormObject *)o
{
  unsigned v = [self version:@"NSTextView"];

  [self fields:@[@"delegate:o", @"isFieldEditor:s", @"isEditable:s", @"isSelectable:s",
                 @"isRichText:s", @"importsGraphics:s", @"drawsBackground:s",
                 @"isHorizontallyResizable:s", @"isVerticallyResizable:s",
                 @"usesFontPanel:s", @"usesRuler:s", @"isRulerVisible:s",
                 @"backgroundColor:o", @"minSize:z", @"maxSize:z",
                 @"smartInsertDelete:s", @"allowsUndo:s"] of:o];
  if (v >= 3) [self fields:@[@"usesFindPanel:s"] of:o];
  if (v >= 2)
  {
    [self fields:@[@"insertionPointColor:o", @"containerSize:z",
                   @"widthTracksTextView:s", @"heightTracksTextView:s"] of:o];
  }
  if (v >= 4)
  {
    [self fields:@[@"defaultParagraphStyle:o", @"markedTextAttributes:o",
                   @"linkTextAttributes:o", @"continuousSpellChecking:s"] of:o];
  }
}

- (void)decodeNSMatrix:(PCGormObject *)o
{
  [self fields:@[@"mode:s", @"allowsEmptySelection:s", @"selectionByRect:s",
                 @"autosizesCells:s", @"autoscroll:s", @"cellSize:z", @"intercell:z",
                 @"backgroundColor:o", @"cellBackgroundColor:o", @"drawsBackground:s",
                 @"drawsCellBackground:s", @"cellClass:o", @"cellPrototype:o",
                 @"rows:s", @"columns:s", @"cells:o", @"delegate:o", @"target:o",
                 @"action:c", @"doubleAction:c", @"errorAction:c",
                 @"tabKeyTraversesCells:s", @"keyCell:o"] of:o];
}

- (void)decodeNSWindow:(PCGormObject *)o
{
  unsigned v = [self version:@"NSWindow"];

  [self fields:@[@"contentRect:r", @"styleMask:s", @"backingType:s", @"topLeftPoint:p",
                 @"contentView:o", @"backgroundColor:o", @"representedFilename:o",
                 @"miniwindowTitle:o", @"title:o", @"minSize:z", @"maxSize:z",
                 @"level:s", @"excludedFromWindowsMenu:s", @"isOneShot:s",
                 @"isAutodisplay:s", @"optimizedDrawing:s", @"dynamicDepthLimit:s",
                 @"cursorRectsEnabled:s", @"isReleasedWhenClosed:s",
                 @"hidesOnDeactivate:s", @"acceptsMouseMovedEvents:s",
                 @"miniaturizedImage:o", @"initialFirstResponder:o"] of:o];
  if (v > 3)
  {
    [self fields:@[@"toolbar:o"] of:o];
  }
}

- (void)decodeNSPanel:(PCGormObject *)o
{
  [self fields:@[@"becomesKeyOnlyIfNeeded:s", @"isFloatingPanel:s", @"worksWhenModal:s"] of:o];
}

- (void)decodeNSMenu:(PCGormObject *)o
{
  [self fields:@[@"title:o", @"items:o", @"autoenablesItems:s"] of:o];
}

- (void)decodeNSMenuItem:(PCGormObject *)o
{
  unsigned v = [self version:@"NSMenuItem"];

  [self fields:@[@"title:o", @"keyEquivalent:o", @"keyEquivalentModifierMask:s",
                 @"mnemonicLocation:s", @"state:s", @"enabled:s", @"image:o",
                 @"onStateImage:o", @"offStateImage:o", @"mixedStateImage:o",
                 @"changesState:s"] of:o];
  if (v == 1) [self fields:@[@"target:o"] of:o];
  [self fields:@[@"action:c", @"tag:s", @"representedObject:o", @"submenu:o"] of:o];
  if (v >= 2) [self fields:@[@"target:o"] of:o];
  if (v >= 3) [self fields:@[@"isAlternate:s", @"indentation:s", @"toolTip:o"] of:o];
}

- (void)decodeNSCell:(PCGormObject *)o
{
  unsigned v = [self version:@"NSCell"];

  [self fields:@[@"contents:o", @"cellImage:o", @"font:o", @"objectValue:o",
                 @"containsAttributedString:s", @"isHighlighted:s", @"isDisabled:s",
                 @"isEditable:s", @"isRichText:s", @"importsGraphics:s",
                 @"showsFirstResponder:s", @"refusesFirstResponder:s",
                 @"sendsActionOnEndEditing:s", @"isBordered:s", @"isBezeled:s",
                 @"isScrollable:s", @"isSelectable:s", @"isContinuous:s",
                 @"allowsMixedState:s", @"wraps:s", @"textAlignment:s", @"type:s",
                 @"imagePosition:s", @"entryType:s", @"state:s", @"mnemonicLocation:s",
                 @"mouseDownFlags:s", @"actionMask:s", @"formatter:o", @"menu:o",
                 @"representedObject:o"] of:o];
  if (v >= 2)
  {
    [self fields:@[@"allowsUndo:s", @"lineBreakMode:s", @"controlTint:s", @"controlSize:s",
                   @"focusRingType:s", @"baseWritingDirection:s"] of:o];
  }
  if (v >= 4)
  {
    [self fields:@[@"usesSingleLineMode:s"] of:o];
  }
}

- (void)decodeNSActionCell:(PCGormObject *)o
{
  [self fields:@[@"tag:s", @"target:o", @"action:c", @"controlView:o"] of:o];
}

- (void)decodeNSButtonCell:(PCGormObject *)o
{
  unsigned v = [self version:@"NSButtonCell"];

  [self fields:@[@"keyEquivalent:o", @"keyEquivalentFont:o", @"altContents:o",
                 @"altImage:o", @"isTransparent:s", @"keyEquivalentModifierMask:s",
                 @"highlightsByMask:s", @"showAltStateMask:s"] of:o];
  if (v >= 2)
  {
    [self fields:@[@"sound:o", @"backgroundColor:o", @"delayInterval:s",
                   @"repeatInterval:s", @"bezelStyle:s", @"gradientType:s",
                   @"imageDimsWhenDisabled:s", @"showsBorderOnlyWhileMouseInside:s"] of:o];
  }
  if (v >= 4)
  {
    [self fields:@[@"contentTintColor:o"] of:o];
  }
}

- (void)decodeNSMenuItemCell:(PCGormObject *)o
{
  [self fields:@[@"menuItem:o"] of:o];
  if ([self version:@"NSMenuItemCell"] < 2)
  {
    [self fields:@[@"menuView:o"] of:o];
  }
}

- (void)decodeNSPopUpButtonCell:(PCGormObject *)o
{
  [self fields:@[@"popupMenu:o", @"selectedItem:o", @"pullsDown:s", @"preferredEdge:s",
                 @"usesItemFromMenu:s", @"altersStateOfSelectedItem:s",
                 @"arrowPosition:s"] of:o];
}

- (void)decodeNSTextFieldCell:(PCGormObject *)o
{
  [self fields:@[@"backgroundColor:o", @"textColor:o", @"drawsBackground:s"] of:o];
}

- (void)decodeNSTableHeaderCell:(PCGormObject *)o { }

- (void)decodeNSImageCell:(PCGormObject *)o
{
  [self fields:@[@"imageAlignment:s", @"frameStyle:s", @"imageScaling:s",
                 @"originalImageSize:z"] of:o];
}

- (void)decodeNSSliderCell:(PCGormObject *)o
{
  [self fields:@[@"minValue:s", @"maxValue:s", @"altIncrementValue:s", @"isVertical:s",
                 @"titleCell:o", @"knobCell:o"] of:o];
  if ([self version:@"NSSliderCell"] >= 2)
  {
    [self fields:@[@"allowsTickMarkValuesOnly:s", @"numberOfTickMarks:s",
                   @"tickMarkPosition:s"] of:o];
  }
}

// --- Graphics

- (void)decodeNSImage:(PCGormObject *)o
{
  PCGormValue *byName = [self scalar];

  [o _addField:@"archiveByName" value:byName];
  if ([byName boolValue])
  {
    [self fields:@[@"name:o"] of:o];
    return;
  }
  [self fields:@[@"size:z", @"color:o", @"scalable:s", @"dataRetained:s", @"flipDraw:s",
                 @"sizeWasExplicitlySet:s", @"useEPSOnResolutionMismatch:s",
                 @"colorMatchPreferred:s", @"multipleResolutionMatching:s",
                 @"cacheSeparately:s", @"unboundedCacheDepth:s", @"reps:o"] of:o];
}

- (void)decodeNSImageRep:(PCGormObject *)o
{
  [self fields:@[@"colorSpace:o", @"size:z", @"hasAlpha:s", @"isOpaque:s",
                 @"bitsPerSample:s", @"pixelsWide:s", @"pixelsHigh:s"] of:o];
}

- (void)decodeNSBitmapImageRep:(PCGormObject *)o
{
  [self fields:@[@"data:o"] of:o];
}

- (void)decodeNSColor:(PCGormObject *)o
{
  PCGormValue *space = [self object];
  NSString    *name;

  [o _addField:@"colorSpaceName" value:space];
  name = [[space object] stringValue];
  if ([name isEqualToString:@"NSNamedColorSpace"])
  {
    [self fields:@[@"catalogName:o", @"colorName:o"] of:o];
  }
  else if ([name isEqualToString:@"NSDeviceWhiteColorSpace"]
           || [name isEqualToString:@"NSCalibratedWhiteColorSpace"])
  {
    [self fields:@[@"white:s", @"alpha:s"] of:o];
  }
  else if ([name isEqualToString:@"NSDeviceCMYKColorSpace"])
  {
    [self fields:@[@"cyan:s", @"magenta:s", @"yellow:s", @"black:s", @"alpha:s"] of:o];
  }
  else if ([name isEqualToString:@"NSDeviceRGBColorSpace"]
           || [name isEqualToString:@"NSCalibratedRGBColorSpace"])
  {
    [self fields:@[@"red:s", @"green:s", @"blue:s", @"hue:s", @"saturation:s",
                   @"brightness:s", @"alpha:s"] of:o];
  }
  else
  {
    [self fail:@"unknown color space %@", name];
  }
}

- (void)decodeNSFont:(PCGormObject *)o
{
  unsigned    v = [self version:@"NSFont"];
  long long   role = 0;

  if (v == 3)
  {
    PCGormValue *roleValue = [self scalar];

    [o _addField:@"role" value:roleValue];
    role = [roleValue longLongValue];
  }
  if (role == 0)
  {
    [self fields:@[@"name:o", @"matrix:a"] of:o];
    if (v >= 2)
    {
      [self fields:@[@"fix:s"] of:o];
    }
  }
  else if (role & 1)
  {
    [self fields:@[@"size:s"] of:o];
  }
}

@end

// ============================================================================
// ==== Writing
// ============================================================================

@interface PCGormWriter : NSObject
{
@public
  NSMutableData       *out;
  unsigned            version;
  NSDictionary        *versions;
  NSDictionary        *supers;
  NSMutableDictionary *objectNumbers;   // object -> xref
  NSMutableDictionary *classNumbers;    // name -> xref
  NSMutableDictionary *pointerNumbers;  // pointer definition -> xref
  unsigned            objectCount, classCount, pointerCount;
}
@end

static id Key(id object)
{
  return [NSValue valueWithNonretainedObject:object];
}

@implementation PCGormWriter

- (id)init
{
  if ((self = [super init]))
  {
    out = [NSMutableData new];
    objectNumbers = [NSMutableDictionary new];
    classNumbers = [NSMutableDictionary new];
    pointerNumbers = [NSMutableDictionary new];
  }
  return self;
}

- (void)dealloc
{
  [out release];
  [objectNumbers release];
  [classNumbers release];
  [pointerNumbers release];
  [super dealloc];
}

- (void)u8:(unsigned)v { uint8_t b = (uint8_t)v; [out appendBytes:&b length:1]; }
- (void)u16:(unsigned)v { uint8_t b[2] = { (uint8_t)(v >> 8), (uint8_t)v }; [out appendBytes:b length:2]; }
- (void)u32:(unsigned)v
{
  uint8_t b[4] = { (uint8_t)(v >> 24), (uint8_t)(v >> 16), (uint8_t)(v >> 8), (uint8_t)v };
  [out appendBytes:b length:4];
}

/* As -[NSMutableData serializeTypeTag:andCrossRef:]: the smallest width. */
- (void)tag:(uint8_t)tag xref:(unsigned)xref
{
  tag &= ~GSC_SIZE;
  if (xref <= 0xff)
  {
    [self u8:tag | 0x20];
    [self u8:xref];
  }
  else if (xref <= 0xffff)
  {
    [self u8:tag | 0x40];
    [self u16:xref];
  }
  else
  {
    [self u8:tag | 0x60];
    [self u32:xref];
  }
}

- (void)countBytes:(PCGormValue *)value
{
  /* Unchanged counts keep their archived form. */
  if (value->countBytes != nil)
  {
    [out appendData:value->countBytes];
    return;
  }
  if (version == 12402)
  {
    uint8_t    digits[10];
    NSUInteger n = value->count, i = 0;

    do
    {
      digits[i++] = n & 127;
      n >>= 7;
    }
    while (n > 0);
    while (i-- > 1)
    {
      [self u8:digits[i] | 128];
    }
    [self u8:digits[0]];
  }
  else
  {
    [self u32:(unsigned)value->count];
  }
}

- (void)writeClass:(NSString *)name tag:(uint8_t)tag
{
  NSNumber *number = [classNumbers objectForKey:name];
  NSString *c = name;

  if (number != nil)
  {
    [self tag:(tag & GSC_MASK) | GSC_XREF xref:[number unsignedIntValue]];
    return;
  }
  /* The class and its superclasses not written yet, as NSArchiver does. */
  while (c != nil && [classNumbers objectForKey:c] == nil)
  {
    NSData *nameBytes = [c dataUsingEncoding:NSUTF8StringEncoding];

    classCount++;
    [classNumbers setObject:[NSNumber numberWithUnsignedInt:classCount] forKey:c];
    [self tag:GSC_CLASS xref:classCount];
    [self u16:(unsigned)[nameBytes length]];
    [out appendData:nameBytes];
    [self u32:[[versions objectForKey:c] unsignedIntValue]];
    c = [supers objectForKey:c];
  }
  [self u8:GSC_NONE];
}

- (void)writeValue:(PCGormValue *)value
{
  switch (value->kind)
  {
    case PCGormScalar:
      [self u8:value->tag];
      [out appendData:value->bytes];
      break;

    case PCGormStruct:
      [self u8:value->tag];
      for (PCGormValue *member in value->members)
      {
        [self writeValue:member];
      }
      break;

    case PCGormNil:
      [self u8:value->tag];
      break;

    case PCGormClassValue:
      [self writeClass:value->className tag:value->tag];
      break;

    case PCGormSelector:
    case PCGormCString:
    {
      PCGormValue *definition = value->definition ? value->definition : value;
      NSNumber    *number = [pointerNumbers objectForKey:Key(definition)];

      if (number != nil)
      {
        [self tag:(value->tag & GSC_MASK) | GSC_XREF xref:[number unsignedIntValue]];
        break;
      }
      pointerCount++;
      [pointerNumbers setObject:[NSNumber numberWithUnsignedInt:pointerCount]
                         forKey:Key(definition)];
      [self tag:value->tag & GSC_MASK xref:pointerCount];
      if (value->kind == PCGormSelector)
      {
        [self u16:(unsigned)[definition->bytes length]];
        [self u16:(unsigned)[definition->types length]];
        [out appendData:definition->bytes];
        [out appendData:definition->types];
      }
      else
      {
        [self u32:(unsigned)[definition->bytes length]];
        [out appendData:definition->bytes];
      }
      break;
    }

    case PCGormScalarArray:
      [self u8:value->tag];
      [self countBytes:value];
      [self u8:value->elementTag];
      [out appendData:value->bytes];
      break;

    case PCGormObjectArray:
      [self u8:value->tag];
      [self countBytes:value];
      for (PCGormValue *member in value->members)
      {
        [self writeValue:member];
      }
      break;

    case PCGormObjectValue:
    {
      PCGormObject *object = value->object;
      NSNumber     *number = [objectNumbers objectForKey:Key(object)];
      uint8_t      base = value->tag & GSC_MASK;

      if (number != nil)
      {
        [self tag:base | GSC_XREF xref:[number unsignedIntValue]];
        break;
      }
      objectCount++;
      [objectNumbers setObject:[NSNumber numberWithUnsignedInt:objectCount] forKey:Key(object)];
      [self tag:base xref:objectCount];
      [self writeClass:object->className tag:GSC_CLASS];
      for (PCGormValue *field in object->values)
      {
        [self writeValue:field];
      }
      break;
    }
  }
}

@end

// ============================================================================
// ==== Archive
// ============================================================================

@implementation PCGormArchive

+ (PCGormArchive *)archiveWithContentsOfFile:(NSString *)path error:(NSString **)error
{
  NSData *data = [NSData dataWithContentsOfFile:path];

  if (data == nil)
  {
    if (error) *error = [NSString stringWithFormat:@"Cannot read %@", path];
    return nil;
  }
  return [self archiveWithData:data error:error];
}

+ (PCGormArchive *)archiveWithData:(NSData *)data error:(NSString **)error
{
  PCGormArchive *archive = [[[PCGormArchive alloc] init] autorelease];
  PCGormReader  *reader = [[[PCGormReader alloc] init] autorelease];
  NSUInteger    prefixLength = [PCGormPrefix length];
  NSString      *header;
  unsigned      v = 0;

  if ([data length] < prefixLength + 36
      || memcmp([data bytes], [PCGormPrefix UTF8String], prefixLength) != 0)
  {
    if (error) *error = @"Not a GNUstep archive.";
    return nil;
  }
  header = [[[NSString alloc] initWithBytes:(const char *)[data bytes] + prefixLength
                                     length:36
                                   encoding:NSASCIIStringEncoding] autorelease];
  if (sscanf([header UTF8String], "%x:", &v) != 1)
  {
    if (error) *error = @"The archive header cannot be read.";
    return nil;
  }
  archive->header = [header copy];
  archive->version = v;
  reader->bytes = [data bytes];
  reader->length = [data length];
  reader->pos = prefixLength + 36;
  reader->version = v;
  reader->archive = archive;
  @try
  {
    archive->root = [[reader object] retain];
    if (reader->pos != reader->length)
    {
      [reader fail:@"%lu bytes after the root object",
       (unsigned long)(reader->length - reader->pos)];
    }
  }
  @catch (NSException *exception)
  {
    if (![[exception name] isEqualToString:PCGormDecodeException])
    {
      @throw;
    }
    if (error) *error = [exception reason];
    return nil;
  }
  [archive->versions addEntriesFromDictionary:reader->versions];
  [archive->supers addEntriesFromDictionary:reader->supers];
  return archive;
}

- (id)init
{
  if ((self = [super init]))
  {
    versions = [NSMutableDictionary new];
    supers = [NSMutableDictionary new];
    objects = [NSMutableArray new];
  }
  return self;
}

- (void)dealloc
{
  [header release];
  [root release];
  [versions release];
  [supers release];
  [objects release];
  [super dealloc];
}

- (void)_registerObject:(PCGormObject *)object
{
  [objects addObject:object];
  if (object->identifier >= nextIdentifier)
  {
    nextIdentifier = object->identifier + 1;
  }
}

- (unsigned)_version
{
  return version;
}

- (PCGormObject *)_newObjectOfClass:(NSString *)name
{
  PCGormObject *object = [[[PCGormObject alloc] init] autorelease];

  object->archive = self;
  object->identifier = nextIdentifier++;
  object->className = [name copy];
  [objects addObject:object];
  if ([versions objectForKey:name] == nil)
  {
    /* NSString is version 1 in libs-base; its superclass is NSObject. */
    [versions setObject:[NSNumber numberWithUnsignedInt:1] forKey:name];
  }
  return object;
}

- (PCGormObject *)rootObject
{
  return [root object];
}

- (NSArray *)allObjects
{
  return objects;
}

- (unsigned)versionOfClass:(NSString *)name
{
  return [[versions objectForKey:name] unsignedIntValue];
}

- (PCGormObject *)objectWithIdentifier:(NSUInteger)identifier
{
  for (PCGormObject *object in objects)
  {
    if (object->identifier == identifier)
    {
      return object;
    }
  }
  return nil;
}

- (NSData *)data
{
  PCGormWriter  *writer = [[[PCGormWriter alloc] init] autorelease];
  NSMutableData *result = [NSMutableData data];
  NSString      *counts;

  writer->version = version;
  writer->versions = versions;
  writer->supers = supers;
  [writer writeValue:root];
  /* Version and the sizes of the class, object and pointer tables, as
   * -[NSArchiver serializeHeaderAt:...] writes them. NSArchiver's table
   * sizes can exceed what the archive defines; the unarchiver only takes
   * them as capacities. Keep the archived ones unless more are needed. */
  {
    unsigned archived[4] = { 0, 0, 0, 0 };

    sscanf([header UTF8String], "%x:%x:%x:%x:", &archived[0], &archived[1],
           &archived[2], &archived[3]);
    counts = [NSString stringWithFormat:@"%@%08x:%08x:%08x:%08x:", PCGormPrefix, version,
              MAX(archived[1], writer->classCount), MAX(archived[2], writer->objectCount),
              MAX(archived[3], writer->pointerCount)];
  }
  [result appendData:[counts dataUsingEncoding:NSASCIIStringEncoding]];
  [result appendData:writer->out];
  return result;
}

@end
