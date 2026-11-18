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

#import "PCGormXIBWriter.h"
#import "PCGormArchive.h"
#include <math.h>

static NSString * const OwnerID = @"-2";
static NSString * const FirstResponderID = @"-1";
static NSString * const ApplicationID = @"-3";

/* GNUstep images that only stand for a button type or a GNUstep look. */
static NSArray *SwitchImages(void)
{
  return @[@"GSSwitch", @"GSSwitchSelected", @"NSSwitch", @"common_SwitchOff", @"common_SwitchOn"];
}

static NSArray *RadioImages(void)
{
  return @[@"GSRadio", @"GSRadioSelected", @"NSRadioButton", @"common_RadioOff", @"common_RadioOn"];
}

static NSArray *DroppedImages(void)
{
  return @[@"common_ret", @"common_retH", @"NSApplicationIcon",
           @"common_ToolbarCustomizeToolbarItem"];
}

static NSString *Lookup(NSArray *names, long long index, NSString *fallback)
{
  if (index < 0 || index >= (long long)[names count] || [[names objectAtIndex:index] length] == 0)
  {
    return fallback;
  }
  return [names objectAtIndex:index];
}

static NSString *BezelStyle(long long v)
{
  return Lookup(@[@"", @"rounded", @"regularSquare", @"thickSquare", @"thickerSquare",
                  @"disclosure", @"shadowlessSquare", @"circular", @"texturedSquare",
                  @"helpButton", @"smallSquare", @"texturedRounded", @"roundRect",
                  @"recessed", @"roundedDisclosure"], v, nil);
}

static NSString *ImagePosition(long long v)
{
  return Lookup(@[@"noImage", @"only", @"left", @"right", @"below", @"above", @"overlaps"],
                v, @"noImage");
}

/* GNUstep: left 0, center 1, right 2, justified 3, natural 4. */
static NSString *Alignment(long long v, NSString *fallback)
{
  return Lookup(@[@"left", @"center", @"right", @"justified", @"natural"], v, fallback);
}

static NSString *LineBreak(long long v)
{
  return Lookup(@[@"wordWrapping", @"charWrapping", @"clipping", @"truncatingHead",
                  @"truncatingTail", @"truncatingMiddle"], v, @"clipping");
}

static NSString *TitlePosition(long long v)
{
  return Lookup(@[@"noTitle", @"aboveTop", @"atTop", @"belowTop", @"aboveBottom",
                  @"atBottom", @"belowBottom"], v, @"atTop");
}

static NSString *BorderType(long long v)
{
  return Lookup(@[@"none", @"line", @"bezel", @"groove"], v, @"bezel");
}

static NSString *ImageScaling(long long v)
{
  return Lookup(@[@"proportionallyDown", @"axesIndependently", @"none",
                  @"proportionallyUpOrDown"], v, @"proportionallyDown");
}

static NSString *FrameStyle(long long v)
{
  return Lookup(@[@"", @"photo", @"grayBezel", @"groove", @"button"], v, nil);
}

/* NSFont roles (libs-gui, NSFont.m) as XIB meta fonts. */
static NSString *MetaFont(long long role)
{
  return Lookup(@[@"", @"systemBold", @"system", @"fixedUser", @"user", @"titleBar",
                  @"menu", @"message", @"palette", @"toolTip", @"controlContent",
                  @"label", @"menuBar"], role >> 1, @"user");
}

static NSString *Fmt(double v)
{
  NSString *s;

  if (v == floor(v) && fabs(v) < 1e15)
  {
    return [NSString stringWithFormat:@"%lld", (long long)v];
  }
  s = [NSString stringWithFormat:@"%.6f", v];
  while ([s hasSuffix:@"0"])
  {
    s = [s substringToIndex:[s length] - 1];
  }
  if ([s hasSuffix:@"."])
  {
    s = [s substringToIndex:[s length] - 1];
  }
  return s;
}

static NSString *Yes(BOOL b)
{
  return b ? @"YES" : @"NO";
}

/* XML cannot hold most control characters (Info.gorm has an ESC). */
static NSString *Clean(NSString *string)
{
  NSMutableString *result;
  NSUInteger      i;

  if (string == nil)
  {
    return nil;
  }
  result = [NSMutableString stringWithString:string];
  for (i = 0; i < [result length]; i++)
  {
    unichar c = [result characterAtIndex:i];

    if (c < ' ' && c != '\t' && c != '\n' && c != '\r')
    {
      [result replaceCharactersInRange:NSMakeRange(i, 1) withString:@" "];
    }
  }
  return result;
}

static id Key(id object)
{
  return [NSValue valueWithNonretainedObject:object];
}

/* An attribute list: name, value, name, value; nil values are left out. */
#define ATTRS(...) [NSArray arrayWithObjects:__VA_ARGS__, nil]
static id V(id value)
{
  return value ? value : (id)[NSNull null];
}

@implementation PCGormXIBWriter

+ (NSString *)identifierForObject:(PCGormObject *)object
{
  return [NSString stringWithFormat:@"g%lu", (unsigned long)[object identifier]];
}

+ (PCGormObject *)objectForIdentifier:(NSString *)identifier inArchive:(PCGormArchive *)archive
{
  if (![identifier hasPrefix:@"g"])
  {
    return nil;
  }
  return [archive objectWithIdentifier:(NSUInteger)[[identifier substringFromIndex:1] longLongValue]];
}

+ (NSXMLDocument *)documentForArchive:(PCGormArchive *)archive
                         toolsVersion:(NSString *)toolsVersion
                             warnings:(NSArray **)warnings
{
  PCGormXIBWriter *writer = [[[self alloc] initWithArchive:archive toolsVersion:toolsVersion] autorelease];
  NSXMLDocument   *document = [writer document];

  if (warnings)
  {
    *warnings = [[writer->warnings copy] autorelease];
  }
  return document;
}

- (id)initWithArchive:(PCGormArchive *)anArchive toolsVersion:(NSString *)version
{
  if ((self = [super init]))
  {
    archive = [anArchive retain];
    container = [[archive rootObject] retain];
    toolsVersion = [(version ? version : @"22505") copy];
    names = [NSMutableDictionary new];
    byName = [NSMutableDictionary new];
    custom = [NSMutableDictionary new];
    pending = [NSMutableDictionary new];
    sources = [NSMutableArray new];
    images = [NSMutableDictionary new];
    warnings = [NSMutableArray new];
    visible = [NSMutableSet new];

    for (NSArray *pair in [[container objectForField:@"nameTable"] pairsValue])
    {
      PCGormObject *key = [pair objectAtIndex:0];
      PCGormObject *value = [pair objectAtIndex:1];
      NSString     *name;

      if (![key isKindOfClass:[PCGormObject class]] || ![key isString])
      {
        continue;
      }
      name = [key stringValue];
      if ([value isKindOfClass:[PCGormObject class]])
      {
        [byName setObject:value forKey:name];
        if (![value isString])
        {
          [names setObject:name forKey:Key(value)];
        }
      }
    }
    for (NSArray *pair in [[container objectForField:@"customClasses"] pairsValue])
    {
      id key = [pair objectAtIndex:0];
      id value = [pair objectAtIndex:1];

      if ([key isKindOfClass:[PCGormObject class]] && [value isKindOfClass:[PCGormObject class]])
      {
        [custom setObject:[value stringValue] forKey:[key stringValue]];
      }
    }
    for (id window in [[container objectForField:@"visibleWindows"] arrayValue])
    {
      if ([window isKindOfClass:[PCGormObject class]])
      {
        [visible addObject:Key(window)];
      }
    }
  }
  return self;
}

- (void)dealloc
{
  [archive release];
  [container release];
  [toolsVersion release];
  [names release];
  [byName release];
  [custom release];
  [pending release];
  [sources release];
  [images release];
  [warnings release];
  [visible release];
  [super dealloc];
}

// --- Helpers

- (NSString *)newID
{
  return [NSString stringWithFormat:@"x%lu", (unsigned long)++serial];
}

- (NSString *)oid:(PCGormObject *)o
{
  return [PCGormXIBWriter identifierForObject:o];
}

- (void)warn:(NSString *)message
{
  if (![warnings containsObject:message])
  {
    [warnings addObject:message];
  }
}

- (NSString *)customClassOf:(PCGormObject *)o
{
  NSString *name = [names objectForKey:Key(o)];

  if (name && [custom objectForKey:name])
  {
    return [custom objectForKey:name];
  }
  return [o customClass];
}

/* A connector end (a name in the name table) as an XIB object id. */
- (NSString *)refID:(PCGormObject *)reference
{
  id object = reference;

  if ([reference isString])
  {
    NSString *name = [reference stringValue];

    if ([name isEqualToString:@"NSOwner"])
    {
      return OwnerID;
    }
    if ([name isEqualToString:@"NSFirst"])
    {
      return FirstResponderID;
    }
    object = [byName objectForKey:name];
  }
  if ([object isKindOfClass:[PCGormObject class]] && ![object isString])
  {
    return [self oid:object];
  }
  return nil;
}

- (NSXMLElement *)element:(NSString *)tag
                   parent:(NSXMLElement *)parent
                   object:(PCGormObject *)o
                      key:(NSString *)key
               attributes:(NSArray *)attributes
{
  NSXMLElement *e = [NSXMLElement elementWithName:tag];
  NSUInteger   i;

  if (key)
  {
    [e addAttribute:[NSXMLNode attributeWithName:@"key" stringValue:key]];
  }
  for (i = 0; i + 1 < [attributes count]; i += 2)
  {
    id value = [attributes objectAtIndex:i + 1];

    if (value != [NSNull null])
    {
      [e addAttribute:[NSXMLNode attributeWithName:[attributes objectAtIndex:i]
                                       stringValue:value]];
    }
  }
  if (o)
  {
    NSString *name = [names objectForKey:Key(o)];
    NSString *cc = [self customClassOf:o];
    BOOL     generic = NO;

    for (NSString *prefix in @[@"View(", @"Button(", @"TextField(", @"Box(", @"ButtonCell(",
                               @"MenuItem(", @"ImageView(", @"CustomView("])
    {
      generic = generic || [name hasPrefix:prefix];
    }
    [e addAttribute:[NSXMLNode attributeWithName:@"id" stringValue:[self oid:o]]];
    if (name && !generic)
    {
      [e addAttribute:[NSXMLNode attributeWithName:@"userLabel" stringValue:name]];
    }
    if (cc)
    {
      [e addAttribute:[NSXMLNode attributeWithName:@"customClass" stringValue:cc]];
    }
  }
  [parent addChild:e];
  return e;
}

- (void)setAttribute:(NSString *)name value:(NSString *)value on:(NSXMLElement *)e
{
  NSXMLNode *existing = [e attributeForName:name];

  if (existing)
  {
    [existing setStringValue:value];
  }
  else
  {
    [e addAttribute:[NSXMLNode attributeWithName:name stringValue:value]];
  }
}

- (void)rect:(NSRect)r key:(NSString *)key parent:(NSXMLElement *)parent
{
  [self element:@"rect" parent:parent object:nil key:key
     attributes:ATTRS(@"x", Fmt(r.origin.x), @"y", Fmt(r.origin.y),
                      @"width", Fmt(r.size.width), @"height", Fmt(r.size.height))];
}

- (void)size:(NSSize)s key:(NSString *)key parent:(NSXMLElement *)parent
{
  [self element:@"size" parent:parent object:nil key:key
     attributes:ATTRS(@"width", Fmt(s.width), @"height", Fmt(s.height))];
}

- (void)autoresizing:(long long)mask parent:(NSXMLElement *)parent
{
  NSArray        *flags = @[@"flexibleMinX", @"widthSizable", @"flexibleMaxX",
                            @"flexibleMinY", @"heightSizable", @"flexibleMaxY"];
  NSMutableArray *attributes = [NSMutableArray array];
  NSUInteger     i;

  for (i = 0; i < [flags count]; i++)
  {
    if (mask & (1 << i))
    {
      [attributes addObject:[flags objectAtIndex:i]];
      [attributes addObject:@"YES"];
    }
  }
  [self element:@"autoresizingMask" parent:parent object:nil key:@"autoresizingMask"
     attributes:attributes];
}

- (void)color:(PCGormObject *)c key:(NSString *)key parent:(NSXMLElement *)parent
{
  NSString *space = [c stringForField:@"colorSpaceName"];

  if (![c isKindOfClassNamed:@"NSColor"] || space == nil)
  {
    return;
  }
  if ([space isEqualToString:@"NSNamedColorSpace"])
  {
    NSString *catalog = [c stringForField:@"catalogName"];

    [self element:@"color" parent:parent object:nil key:key
       attributes:ATTRS(@"name", V([c stringForField:@"colorName"]),
                        @"catalog", catalog ? catalog : @"System", @"colorSpace", @"catalog")];
  }
  else if ([space rangeOfString:@"White"].location != NSNotFound)
  {
    [self element:@"color" parent:parent object:nil key:key
       attributes:ATTRS(@"white", Fmt([c doubleForField:@"white"]),
                        @"alpha", Fmt([c doubleForField:@"alpha"]),
                        @"colorSpace", [space rangeOfString:@"Device"].location != NSNotFound
                        ? @"deviceWhite" : @"calibratedWhite")];
  }
  else if ([space rangeOfString:@"RGB"].location != NSNotFound)
  {
    [self element:@"color" parent:parent object:nil key:key
       attributes:ATTRS(@"red", Fmt([c doubleForField:@"red"]),
                        @"green", Fmt([c doubleForField:@"green"]),
                        @"blue", Fmt([c doubleForField:@"blue"]),
                        @"alpha", Fmt([c doubleForField:@"alpha"]),
                        @"colorSpace", [space rangeOfString:@"Device"].location != NSNotFound
                        ? @"deviceRGB" : @"calibratedRGB")];
  }
  else
  {
    [self element:@"color" parent:parent object:nil key:key
       attributes:ATTRS(@"cyan", Fmt([c doubleForField:@"cyan"]),
                        @"magenta", Fmt([c doubleForField:@"magenta"]),
                        @"yellow", Fmt([c doubleForField:@"yellow"]),
                        @"black", Fmt([c doubleForField:@"black"]),
                        @"alpha", Fmt([c doubleForField:@"alpha"]),
                        @"colorSpace", @"deviceCMYK")];
  }
}

- (void)namedColor:(NSString *)name key:(NSString *)key parent:(NSXMLElement *)parent
{
  [self element:@"color" parent:parent object:nil key:key
     attributes:ATTRS(@"name", name, @"catalog", @"System", @"colorSpace", @"catalog")];
}

- (void)font:(PCGormObject *)f key:(NSString *)key parent:(NSXMLElement *)parent
     default:(NSString *)fallback
{
  long long role;
  double    size;
  NSString  *name;

  if (![f isKindOfClassNamed:@"NSFont"])
  {
    [self element:@"font" parent:parent object:nil key:key
       attributes:ATTRS(@"metaFont", fallback)];
    return;
  }
  role = [f integerForField:@"role"];
  if (role != 0)
  {
    size = [f doubleForField:@"size"];
    [self element:@"font" parent:parent object:nil key:key
       attributes:ATTRS(@"metaFont", MetaFont(role), @"size", V(size ? Fmt(size) : nil))];
    return;
  }
  name = [[f stringForField:@"name"] lowercaseString];
  size = [[[[f valueForField:@"matrix"] numbers] firstObject] doubleValue];
  if ([name rangeOfString:@"courier"].location != NSNotFound
      || [name rangeOfString:@"mono"].location != NSNotFound
      || [name rangeOfString:@"fixed"].location != NSNotFound)
  {
    [self element:@"font" parent:parent object:nil key:key
       attributes:ATTRS(@"size", Fmt(size ? size : 12), @"name", @"Menlo-Regular")];
  }
  else
  {
    [self element:@"font" parent:parent object:nil key:key
       attributes:ATTRS(@"metaFont", [name rangeOfString:@"bold"].location != NSNotFound
                        ? @"systemBold" : @"system", @"size", V(size ? Fmt(size) : nil))];
  }
}

- (NSString *)imageName:(PCGormObject *)image
{
  NSString *name;

  if (![image isKindOfClassNamed:@"NSImage"])
  {
    return nil;
  }
  if (![image boolForField:@"archiveByName"])
  {
    NSSize size = [image sizeForField:@"size"];

    [self warn:[NSString stringWithFormat:@"dropped an unnamed image (%dx%d); set it in code "
                @"or add it as a resource", (int)size.width, (int)size.height]];
    return nil;
  }
  name = [image stringForField:@"name"];
  if ([SwitchImages() containsObject:name] || [RadioImages() containsObject:name])
  {
    return nil;
  }
  if ([DroppedImages() containsObject:name])
  {
    [self warn:[NSString stringWithFormat:@"dropped GNUstep image '%@'", name]];
    return nil;
  }
  [images setObject:image forKey:name];
  return name;
}

/* A cell's text alignment; before NSCell version 5, right and center were
 * archived the other way round. */
- (long long)alignmentOf:(PCGormObject *)c
{
  long long alignment = [c integerForField:@"textAlignment"];

  if ([archive versionOfClass:@"NSCell"] < 5 && (alignment == 1 || alignment == 2))
  {
    alignment = 3 - alignment;
  }
  return alignment;
}

- (NSString *)string:(PCGormObject *)o
{
  return [o isString] ? Clean([o stringValue]) : nil;
}

// --- Connections

- (void)collectConnections
{
  for (id connector in [[container objectForField:@"connections"] arrayValue])
  {
    NSString *label, *source, *destination;
    BOOL     action;

    if (![connector isKindOfClass:[PCGormObject class]]
        || [connector isKindOfClassNamed:@"NSNibConnector"])
    {
      continue;
    }
    label = [connector stringForField:@"label"];
    source = [self refID:[connector objectForField:@"source"]];
    destination = [self refID:[connector objectForField:@"destination"]];
    if (!label || !source || !destination)
    {
      [self warn:[NSString stringWithFormat:@"skipped connection %@ -> %@ (%@)",
                  [[connector objectForField:@"source"] stringValue],
                  [[connector objectForField:@"destination"] stringValue], label]];
      continue;
    }
    action = [connector isKindOfClassNamed:@"NSNibControlConnector"];
    [self pending:source kind:action ? @"action" : @"outlet" label:label destination:destination];
  }
}

- (void)pending:(NSString *)source kind:(NSString *)kind label:(NSString *)label
    destination:(NSString *)destination
{
  NSMutableArray *list = [pending objectForKey:source];

  if (list == nil)
  {
    list = [NSMutableArray array];
    [pending setObject:list forKey:source];
    [sources addObject:source];
  }
  [list addObject:@[kind, label, destination]];
}

- (void)attachConnections:(NSXMLElement *)root
{
  NSMutableDictionary *elements = [NSMutableDictionary dictionary];
  NSMutableArray      *stack = [NSMutableArray arrayWithObject:root];

  while ([stack count])
  {
    NSXMLElement *e = [stack lastObject];
    NSString     *identifier = [[e attributeForName:@"id"] stringValue];

    [stack removeLastObject];
    if (identifier)
    {
      [elements setObject:e forKey:identifier];
    }
    for (NSXMLNode *child in [e children])
    {
      if ([child kind] == NSXMLElementKind)
      {
        [stack addObject:child];
      }
    }
  }
  for (NSString *source in sources)
  {
    NSXMLElement *e = [elements objectForKey:source];
    NSXMLElement *connections;

    if (e == nil)
    {
      [self warn:[NSString stringWithFormat:@"no element for connection source %@", source]];
      continue;
    }
    connections = [[e elementsForName:@"connections"] firstObject];
    if (connections == nil)
    {
      connections = [NSXMLElement elementWithName:@"connections"];
      [e addChild:connections];
    }
    for (NSArray *c in [pending objectForKey:source])
    {
      if ([[c objectAtIndex:0] isEqualToString:@"action"])
      {
        [self element:@"action" parent:connections object:nil key:nil
           attributes:ATTRS(@"selector", [c objectAtIndex:1], @"target", [c objectAtIndex:2],
                            @"id", [self newID])];
      }
      else
      {
        [self element:@"outlet" parent:connections object:nil key:nil
           attributes:ATTRS(@"property", [c objectAtIndex:1], @"destination", [c objectAtIndex:2],
                            @"id", [self newID])];
      }
    }
  }
}

// --- Views

- (NSRect)frameOf:(PCGormObject *)v
{
  return [v hasField:@"theFrame"] ? [v rectForField:@"theFrame"] : [v rectForField:@"frame"];
}

- (void)viewCommon:(NSXMLElement *)e view:(PCGormObject *)v
{
  [self rect:[self frameOf:v] key:@"frame" parent:e];
  [self autoresizing:[v integerForField:@"autoresizingMask"] parent:e];
}

- (void)subviews:(PCGormObject *)list parent:(NSXMLElement *)e
{
  NSMutableArray *views = [NSMutableArray array];
  NSXMLElement   *sub;

  for (id view in [list arrayValue])
  {
    if ([view isKindOfClass:[PCGormObject class]])
    {
      [views addObject:view];
    }
  }
  if ([views count] == 0)
  {
    return;
  }
  sub = [NSXMLElement elementWithName:@"subviews"];
  [e addChild:sub];
  for (PCGormObject *view in views)
  {
    [self view:view parent:sub key:nil];
  }
}

- (NSXMLElement *)view:(PCGormObject *)v parent:(NSXMLElement *)parent key:(NSString *)key
{
  NSString *cls = [v realClassName];
  SEL      selector = NSSelectorFromString([NSString stringWithFormat:@"view%@:parent:key:", cls]);

  if ([cls isEqualToString:@"GSNibItem"])
  {
    selector = @selector(viewGSCustomView:parent:key:);
  }
  if (![self respondsToSelector:selector])
  {
    [self warn:[NSString stringWithFormat:@"emitting %@ as a plain view", cls]];
    selector = @selector(viewNSView:parent:key:);
  }
  return ((NSXMLElement *(*)(id, SEL, id, id, id))[self methodForSelector:selector])
    (self, selector, v, parent, key);
}

- (NSXMLElement *)viewNSView:(PCGormObject *)v parent:(NSXMLElement *)parent key:(NSString *)key
{
  NSXMLElement *e = [self element:@"view" parent:parent object:v key:key attributes:nil];

  [self viewCommon:e view:v];
  [self subviews:[v objectForField:@"subviews"] parent:e];
  return e;
}

- (NSXMLElement *)viewGSCustomView:(PCGormObject *)v parent:(NSXMLElement *)parent key:(NSString *)key
{
  NSXMLElement *e = [self element:@"customView" parent:parent object:v key:key attributes:nil];

  [self setAttribute:@"customClass" value:[v stringForField:@"theClass"] on:e];
  [self viewCommon:e view:v];
  return e;
}

- (NSXMLElement *)viewGSTableCornerView:(PCGormObject *)v parent:(NSXMLElement *)parent key:(NSString *)key
{
  return nil;
}

- (NSXMLElement *)viewNSBox:(PCGormObject *)v parent:(NSXMLElement *)parent key:(NSString *)key
{
  PCGormObject  *titleCell = [v objectForField:@"cell"];
  NSString      *title = [self string:[titleCell objectForField:@"contents"]];
  long long     border = [v integerForField:@"borderType"];
  long long     position = [v integerForField:@"titlePosition"];
  NSMutableArray *attributes = [NSMutableArray arrayWithObjects:
                                @"title", title ? title : @"",
                                @"titlePosition", TitlePosition(position), nil];
  NSXMLElement  *e;
  NSMutableArray *content = [NSMutableArray array];

  if (border == 0)
  {
    [attributes addObjectsFromArray:@[@"boxType", @"custom", @"borderType", @"none"]];
  }
  else if (border == 1)
  {
    [attributes addObjectsFromArray:@[@"boxType", @"custom", @"borderType", @"line"]];
  }
  e = [self element:@"box" parent:parent object:v key:key attributes:attributes];
  [self viewCommon:e view:v];
  for (id view in [[v objectForField:@"subviews"] arrayValue])
  {
    if ([view isKindOfClass:[PCGormObject class]])
    {
      [content addObject:view];
    }
  }
  if ([content count])
  {
    PCGormObject *cv = [content objectAtIndex:0];
    NSXMLElement *ce = [self element:@"view" parent:e object:cv key:@"contentView" attributes:nil];

    [self viewCommon:ce view:cv];
    [self subviews:[cv objectForField:@"subviews"] parent:ce];
  }
  if (border == 0)
  {
    [self element:@"color" parent:e object:nil key:@"borderColor"
       attributes:ATTRS(@"white", @"0", @"alpha", @"0", @"colorSpace", @"calibratedWhite")];
    [self element:@"color" parent:e object:nil key:@"fillColor"
       attributes:ATTRS(@"white", @"0", @"alpha", @"0", @"colorSpace", @"calibratedWhite")];
  }
  if (titleCell && position)
  {
    [self font:[titleCell objectForField:@"font"] key:@"titleFont" parent:e default:@"message"];
  }
  return e;
}

- (void)controlCommon:(NSXMLElement *)e control:(PCGormObject *)v
{
  PCGormObject *cell = [v objectForField:@"cell"];

  if (cell && [cell boolForField:@"isDisabled"])
  {
    [self setAttribute:@"enabled" value:@"NO" on:e];
  }
  if ([v integerForField:@"tag"])
  {
    [self setAttribute:@"tag" value:Fmt([v integerForField:@"tag"]) on:e];
  }
}

- (NSXMLElement *)viewNSButton:(PCGormObject *)v parent:(NSXMLElement *)parent key:(NSString *)key
{
  NSXMLElement *e = [self element:@"button" parent:parent object:v key:key attributes:nil];

  [self controlCommon:e control:v];
  [self viewCommon:e view:v];
  if ([v objectForField:@"cell"])
  {
    [self buttonCell:[v objectForField:@"cell"] key:@"cell" parent:e frame:[self frameOf:v]];
  }
  return e;
}

- (NSXMLElement *)viewNSPopUpButton:(PCGormObject *)v parent:(NSXMLElement *)parent key:(NSString *)key
{
  NSXMLElement *e = [self element:@"popUpButton" parent:parent object:v key:key attributes:nil];
  PCGormObject *cell = [v objectForField:@"cell"];

  [self controlCommon:e control:v];
  [self viewCommon:e view:v];
  if (cell)
  {
    PCGormObject   *menu = [cell objectForField:@"popupMenu"];
    PCGormObject   *selected = [cell objectForField:@"selectedItem"];
    NSString       *title = [self string:[cell objectForField:@"contents"]];
    NSMutableArray *attributes = [NSMutableArray arrayWithObjects:
                                  @"type", @"push", @"bezelStyle", @"rounded",
                                  @"alignment", @"left", @"lineBreakMode", @"truncatingTail",
                                  @"borderStyle", @"borderAndBezel",
                                  @"imageScaling", @"proportionallyDown", @"inset", @"2", nil];
    NSXMLElement   *ce;

    if (menu == nil)
    {
      menu = [cell objectForField:@"menu"];
    }
    if ([cell boolForField:@"pullsDown"])
    {
      [attributes addObjectsFromArray:@[@"pullsDown", @"YES"]];
    }
    ce = [self element:@"popUpButtonCell" parent:e object:cell key:@"cell" attributes:attributes];
    if ([title length])
    {
      [self setAttribute:@"title" value:title on:ce];
    }
    if (selected)
    {
      [self setAttribute:@"selectedItem" value:[self oid:selected] on:ce];
    }
    if ([cell integerForField:@"tag"])
    {
      [self setAttribute:@"tag" value:Fmt([cell integerForField:@"tag"]) on:ce];
    }
    [self element:@"behavior" parent:ce object:nil key:@"behavior"
       attributes:ATTRS(@"lightByBackground", @"YES", @"lightByGray", @"YES")];
    [self font:[cell objectForField:@"font"] key:@"font" parent:ce default:@"menu"];
    if (menu)
    {
      [self menu:menu parent:ce key:@"menu"];
    }
  }
  return e;
}

- (NSXMLElement *)buttonCell:(PCGormObject *)c key:(NSString *)key parent:(NSXMLElement *)parent
                       frame:(NSRect)frame
{
  PCGormObject   *image = [c objectForField:@"cellImage"];
  NSString       *imageName = [image boolForField:@"archiveByName"] ? [image stringForField:@"name"] : nil;
  NSString       *type;
  NSString       *title = [self string:[c objectForField:@"contents"]];
  NSString       *alternate = [self string:[c objectForField:@"altContents"]];
  NSString       *name = [self imageName:image];
  NSString       *alternateName = [self imageName:[c objectForField:@"altImage"]];
  NSMutableArray *attributes = [NSMutableArray array];
  NSMutableArray *behavior = [NSMutableArray array];
  NSXMLElement   *ce;
  NSString       *keyEquivalent;
  long long      highlights = [c integerForField:@"highlightsByMask"];
  long long      shows = [c integerForField:@"showAltStateMask"];
  BOOL           toggle;

  if ([SwitchImages() containsObject:imageName])
  {
    type = @"check";
  }
  else if ([RadioImages() containsObject:imageName])
  {
    type = @"radio";
  }
  else
  {
    type = [c boolForField:@"isBordered"] ? @"push" : @"square";
  }
  toggle = [type isEqualToString:@"check"] || [type isEqualToString:@"radio"];
  [attributes addObjectsFromArray:@[@"type", type, @"title", title ? title : @""]];
  if ([alternate length])
  {
    [attributes addObjectsFromArray:@[@"alternateTitle", alternate]];
  }
  if (name)
  {
    [attributes addObjectsFromArray:@[@"image", name]];
  }
  if (alternateName)
  {
    [attributes addObjectsFromArray:@[@"alternateImage", alternateName]];
  }
  if (toggle)
  {
    [attributes addObjectsFromArray:@[@"imagePosition", @"left"]];
  }
  else
  {
    NSString *position = ImagePosition(name ? [c integerForField:@"imagePosition"] : 0);

    if (name && ![title length])
    {
      position = @"only";
    }
    [attributes addObjectsFromArray:@[@"imagePosition", position]];
    if ([c boolForField:@"isBordered"])
    {
      NSString *style = BezelStyle([c integerForField:@"bezelStyle"]);

      if (style == nil)
      {
        style = frame.size.height <= 30 ? @"rounded" : @"regularSquare";
      }
      [attributes addObjectsFromArray:@[@"bezelStyle", style, @"borderStyle", @"border"]];
    }
    else
    {
      [attributes addObjectsFromArray:@[@"bezelStyle", @"shadowlessSquare", @"bordered", @"NO"]];
    }
  }
  [attributes addObjectsFromArray:@[@"alignment", Alignment([self alignmentOf:c], @"center")]];
  if ([c integerForField:@"state"])
  {
    [attributes addObjectsFromArray:@[@"state", @"on"]];
  }
  if ([c integerForField:@"tag"])
  {
    [attributes addObjectsFromArray:@[@"tag", Fmt([c integerForField:@"tag"])]];
  }
  if ([c boolForField:@"isTransparent"])
  {
    [attributes addObjectsFromArray:@[@"transparent", @"YES"]];
  }
  if (!toggle)
  {
    [attributes addObjectsFromArray:@[@"imageScaling", @"proportionallyDown"]];
  }
  [attributes addObjectsFromArray:@[@"inset", @"2"]];
  ce = [self element:@"buttonCell" parent:parent object:c key:key attributes:attributes];

  if (toggle)
  {
    [behavior addObjectsFromArray:@[@"changeContents", @"YES", @"doesNotDimImage", @"YES",
                                    @"lightByContents", @"YES"]];
  }
  else
  {
    NSArray    *lights = @[@"pushIn", @"lightByContents", @"lightByGray", @"lightByBackground"];
    NSArray    *states = @[@"", @"changeContents", @"changeGray", @"changeBackground"];
    NSUInteger i;

    for (i = 0; i < 4; i++)
    {
      if (highlights & (1 << i))
      {
        [behavior addObjectsFromArray:@[[lights objectAtIndex:i], @"YES"]];
      }
    }
    for (i = 1; i < 4; i++)
    {
      if (shows & (1 << i))
      {
        [behavior addObjectsFromArray:@[[states objectAtIndex:i], @"YES"]];
      }
    }
  }
  [self element:@"behavior" parent:ce object:nil key:@"behavior" attributes:behavior];
  [self font:[c objectForField:@"font"] key:@"font" parent:ce default:@"system"];
  keyEquivalent = [[c objectForField:@"keyEquivalent"] isString]
    ? [[c objectForField:@"keyEquivalent"] stringValue] : nil;
  if ([keyEquivalent length])
  {
    NSXMLElement *string = [self element:@"string" parent:ce object:nil key:@"keyEquivalent"
                              attributes:nil];

    if ([keyEquivalent isEqualToString:@"\n"])
    {
      keyEquivalent = @"\r";
    }
    if (![Clean(keyEquivalent) isEqualToString:keyEquivalent]
        || [keyEquivalent rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location != NSNotFound)
    {
      /* XML can't hold it (Escape, for instance), or a parser changes it
       * (Return becomes a line feed); Interface Builder writes such keys
       * base64-encoded. */
      [string addAttribute:[NSXMLNode attributeWithName:@"base64-UTF8" stringValue:@"YES"]];
      keyEquivalent = [[[keyEquivalent dataUsingEncoding:NSUTF8StringEncoding]
                        base64EncodedStringWithOptions:0]
                       stringByTrimmingCharactersInSet:
                       [NSCharacterSet characterSetWithCharactersInString:@"="]];
    }
    [string setStringValue:keyEquivalent];
  }
  if ([c integerForField:@"keyEquivalentModifierMask"])
  {
    long long mask = [c integerForField:@"keyEquivalentModifierMask"];

    /* NSButtonCell up to version 2 archived the mask shifted down. */
    if ([archive versionOfClass:@"NSButtonCell"] <= 2)
    {
      mask <<= 16;
    }
    [self modifierMask:mask parent:ce];
  }
  return ce;
}

- (void)modifierMask:(long long)mask parent:(NSXMLElement *)parent
{
  NSMutableArray *attributes = [NSMutableArray array];

  if (mask & (1 << 17)) [attributes addObjectsFromArray:@[@"shift", @"YES"]];
  if (mask & (1 << 18)) [attributes addObjectsFromArray:@[@"control", @"YES"]];
  if (mask & (1 << 19)) [attributes addObjectsFromArray:@[@"option", @"YES"]];
  if (mask & (1 << 20)) [attributes addObjectsFromArray:@[@"command", @"YES"]];
  [self element:@"modifierMask" parent:parent object:nil key:@"keyEquivalentModifierMask"
     attributes:attributes];
}

- (NSXMLElement *)viewNSTextField:(PCGormObject *)v parent:(NSXMLElement *)parent key:(NSString *)key
{
  NSXMLElement *e = [self element:@"textField" parent:parent object:v key:key attributes:nil];

  [self controlCommon:e control:v];
  [self viewCommon:e view:v];
  if ([v objectForField:@"cell"])
  {
    [self textFieldCell:[v objectForField:@"cell"] key:@"cell" parent:e tag:@"textFieldCell"];
  }
  return e;
}

- (NSXMLElement *)textFieldCell:(PCGormObject *)c key:(NSString *)key parent:(NSXMLElement *)parent
                            tag:(NSString *)tag
{
  NSMutableArray *attributes = [NSMutableArray array];
  NSString       *title = [self string:[c objectForField:@"contents"]];
  NSXMLElement   *ce;

  if ([c boolForField:@"isScrollable"])
  {
    [attributes addObjectsFromArray:@[@"scrollable", @"YES"]];
  }
  if ([c hasField:@"lineBreakMode"])
  {
    [attributes addObjectsFromArray:@[@"lineBreakMode", LineBreak([c integerForField:@"lineBreakMode"])]];
  }
  if ([c boolForField:@"isSelectable"])
  {
    [attributes addObjectsFromArray:@[@"selectable", @"YES"]];
  }
  if ([c boolForField:@"isEditable"])
  {
    [attributes addObjectsFromArray:@[@"editable", @"YES"]];
  }
  if ([c boolForField:@"sendsActionOnEndEditing"])
  {
    [attributes addObjectsFromArray:@[@"sendsActionOnEndEditing", @"YES"]];
  }
  if ([c boolForField:@"isBezeled"])
  {
    [attributes addObjectsFromArray:@[@"borderStyle", @"bezel"]];
  }
  else if ([c boolForField:@"isBordered"])
  {
    [attributes addObjectsFromArray:@[@"borderStyle", @"border"]];
  }
  [attributes addObjectsFromArray:@[@"alignment", Alignment([self alignmentOf:c], @"left")]];
  if (title)
  {
    [attributes addObjectsFromArray:@[@"title", title]];
  }
  if ([c integerForField:@"tag"])
  {
    [attributes addObjectsFromArray:@[@"tag", Fmt([c integerForField:@"tag"])]];
  }
  if ([c boolForField:@"drawsBackground"])
  {
    [attributes addObjectsFromArray:@[@"drawsBackground", @"YES"]];
  }
  ce = [self element:tag parent:parent object:c key:key attributes:attributes];
  [self font:[c objectForField:@"font"] key:@"font" parent:ce default:@"system"];
  if ([c objectForField:@"textColor"])
  {
    [self color:[c objectForField:@"textColor"] key:@"textColor" parent:ce];
  }
  else
  {
    [self namedColor:@"controlTextColor" key:@"textColor" parent:ce];
  }
  if ([c objectForField:@"backgroundColor"])
  {
    [self color:[c objectForField:@"backgroundColor"] key:@"backgroundColor" parent:ce];
  }
  else
  {
    [self namedColor:@"textBackgroundColor" key:@"backgroundColor" parent:ce];
  }
  return ce;
}

- (NSXMLElement *)viewNSImageView:(PCGormObject *)v parent:(NSXMLElement *)parent key:(NSString *)key
{
  NSXMLElement *e = [self element:@"imageView" parent:parent object:v key:key attributes:nil];
  PCGormObject *c = [v objectForField:@"cell"];

  [self controlCommon:e control:v];
  [self viewCommon:e view:v];
  if (c)
  {
    NSMutableArray *attributes = [NSMutableArray arrayWithObjects:
                                  @"refusesFirstResponder", @"YES",
                                  @"alignment", Alignment([self alignmentOf:c], @"left"),
                                  @"imageScaling", ImageScaling([c integerForField:@"imageScaling"]), nil];
    NSString       *style = FrameStyle([c integerForField:@"frameStyle"]);
    PCGormObject   *image = [c objectForField:@"cellImage"];
    NSString       *name;

    if ([c objectForField:@"objectValue"] && image == nil)
    {
      image = [c objectForField:@"objectValue"];
    }
    if (style)
    {
      [attributes addObjectsFromArray:@[@"imageFrameStyle", style]];
    }
    name = [self imageName:image];
    if (name)
    {
      [attributes addObjectsFromArray:@[@"image", name]];
    }
    [self element:@"imageCell" parent:e object:c key:@"cell" attributes:attributes];
  }
  return e;
}

- (NSXMLElement *)viewNSSlider:(PCGormObject *)v parent:(NSXMLElement *)parent key:(NSString *)key
{
  NSXMLElement *e = [self element:@"slider" parent:parent object:v key:key attributes:nil];
  PCGormObject *c = [v objectForField:@"cell"];

  [self controlCommon:e control:v];
  [self viewCommon:e view:v];
  if (c)
  {
    NSMutableArray *attributes = [NSMutableArray arrayWithObjects:
                                  @"alignment", @"left",
                                  @"minValue", Fmt([c doubleForField:@"minValue"]),
                                  @"maxValue", Fmt([c doubleForField:@"maxValue"]),
                                  @"tickMarkPosition", @"above", @"sliderType", @"linear", nil];
    PCGormObject   *value = [c objectForField:@"objectValue"];
    NSXMLElement   *ce;

    if ([c integerForField:@"numberOfTickMarks"])
    {
      [attributes addObjectsFromArray:@[@"numberOfTickMarks", Fmt([c integerForField:@"numberOfTickMarks"])]];
    }
    if ([c boolForField:@"allowsTickMarkValuesOnly"])
    {
      [attributes addObjectsFromArray:@[@"allowsTickMarkValuesOnly", @"YES"]];
    }
    if ([value hasField:@"value"])
    {
      [attributes addObjectsFromArray:@[@"doubleValue", Fmt([value numberValue])]];
    }
    if ([c boolForField:@"isContinuous"])
    {
      [attributes addObjectsFromArray:@[@"continuous", @"YES"]];
    }
    ce = [self element:@"sliderCell" parent:e object:c key:@"cell" attributes:attributes];
    [self font:[c objectForField:@"font"] key:@"font" parent:ce default:@"system"];
  }
  return e;
}

- (NSXMLElement *)viewNSColorWell:(PCGormObject *)v parent:(NSXMLElement *)parent key:(NSString *)key
{
  NSXMLElement *e = [self element:@"colorWell" parent:parent object:v key:key attributes:nil];

  if (![v boolForField:@"isBordered"])
  {
    [self setAttribute:@"bordered" value:@"NO" on:e];
  }
  [self controlCommon:e control:v];
  [self viewCommon:e view:v];
  [self color:[v objectForField:@"color"] key:@"color" parent:e];
  return e;
}

- (NSXMLElement *)viewNSMatrix:(PCGormObject *)v parent:(NSXMLElement *)parent key:(NSString *)key
{
  NSString     *mode = Lookup(@[@"", @"highlight", @"list", @"track"], [v integerForField:@"mode"], nil);
  NSXMLElement *e = [self element:@"matrix" parent:parent object:v key:key
                       attributes:ATTRS(@"mode", V(mode),
                                        @"allowsEmptySelection", Yes([v boolForField:@"allowsEmptySelection"]),
                                        @"autosizesCells", Yes([v boolForField:@"autosizesCells"]))];
  long long    rows = [v integerForField:@"rows"], columns = [v integerForField:@"columns"];
  NSArray      *cells = [[v objectForField:@"cells"] arrayValue];
  NSXMLElement *ce;
  long long    row, column;

  [self controlCommon:e control:v];
  [self viewCommon:e view:v];
  [self size:[v sizeForField:@"cellSize"] key:@"cellSize" parent:e];
  [self size:[v sizeForField:@"intercell"] key:@"intercellSpacing" parent:e];
  if ([v objectForField:@"cellPrototype"])
  {
    [self matrixCell:[v objectForField:@"cellPrototype"] key:@"prototype" parent:e];
  }
  ce = [NSXMLElement elementWithName:@"cells"];
  [e addChild:ce];
  for (column = 0; column < columns; column++)
  {
    NSXMLElement *list = [NSXMLElement elementWithName:@"column"];

    [ce addChild:list];
    for (row = 0; row < rows; row++)
    {
      long long i = row * columns + column;

      if (i < (long long)[cells count] && [[cells objectAtIndex:i] isKindOfClass:[PCGormObject class]])
      {
        [self matrixCell:[cells objectAtIndex:i] key:nil parent:list];
      }
    }
  }
  return e;
}

- (void)matrixCell:(PCGormObject *)c key:(NSString *)key parent:(NSXMLElement *)parent
{
  if ([c isKindOfClassNamed:@"NSButtonCell"])
  {
    [self buttonCell:c key:key parent:parent frame:NSZeroRect];
  }
  else if ([c isKindOfClassNamed:@"NSTextFieldCell"] || [c isKindOfClassNamed:@"NSFormCell"])
  {
    [self textFieldCell:c key:key parent:parent tag:@"textFieldCell"];
  }
  else
  {
    [self warn:[NSString stringWithFormat:@"unsupported matrix cell %@", [c realClassName]]];
  }
}

- (NSXMLElement *)viewNSScroller:(PCGormObject *)v parent:(NSXMLElement *)parent key:(NSString *)key
{
  NSRect       frame = [self frameOf:v];
  NSXMLElement *e = [self element:@"scroller" parent:parent object:v key:key
                       attributes:ATTRS(@"horizontal", Yes(frame.size.width > frame.size.height))];

  [self viewCommon:e view:v];
  return e;
}

- (NSXMLElement *)viewNSScrollView:(PCGormObject *)v parent:(NSXMLElement *)parent key:(NSString *)key
{
  NSXMLElement *e = [self element:@"scrollView" parent:parent object:v key:key
                       attributes:ATTRS(@"borderType", BorderType([v integerForField:@"borderType"]),
                                        @"horizontalLineScroll", Fmt([v doubleForField:@"hLineScroll"]),
                                        @"horizontalPageScroll", Fmt([v doubleForField:@"hPageScroll"]),
                                        @"verticalLineScroll", Fmt([v doubleForField:@"vLineScroll"]),
                                        @"verticalPageScroll", Fmt([v doubleForField:@"vPageScroll"]),
                                        @"hasHorizontalScroller", Yes([v boolForField:@"hasHorizScroller"]),
                                        @"hasVerticalScroller", Yes([v boolForField:@"hasVertScroller"]),
                                        @"usesPredominantAxisScrolling", @"NO")];
  PCGormObject *clip = [v objectForField:@"contentView"];
  PCGormObject *header = nil;

  [self viewCommon:e view:v];
  if (clip)
  {
    NSXMLElement   *ce = [self element:@"clipView" parent:e object:clip key:@"contentView"
                            attributes:ATTRS(@"drawsBackground", Yes([clip boolForField:@"drawsBackground"]),
                                             @"copiesOnScroll", Yes([clip boolForField:@"copiesOnScroll"]))];
    NSMutableArray *documents = [NSMutableArray array];

    [self viewCommon:ce view:clip];
    for (id view in [[clip objectForField:@"subviews"] arrayValue])
    {
      if ([view isKindOfClass:[PCGormObject class]])
      {
        [documents addObject:view];
      }
    }
    if ([documents count])
    {
      NSXMLElement *sub = [NSXMLElement elementWithName:@"subviews"];

      [ce addChild:sub];
      for (PCGormObject *document in documents)
      {
        NSXMLElement *de = [self view:document parent:sub key:nil];

        if ([document isKindOfClassNamed:@"NSTableView"] && [document objectForField:@"headerView"])
        {
          header = [document objectForField:@"headerView"];
          [self setAttribute:@"headerView" value:[self oid:header] on:de];
        }
      }
    }
    if ([clip objectForField:@"backgroundColor"])
    {
      [self color:[clip objectForField:@"backgroundColor"] key:@"backgroundColor" parent:ce];
    }
  }
  if ([v objectForField:@"horizScroller"])
  {
    [self viewNSScroller:[v objectForField:@"horizScroller"] parent:e key:@"horizontalScroller"];
  }
  if ([v objectForField:@"vertScroller"])
  {
    [self viewNSScroller:[v objectForField:@"vertScroller"] parent:e key:@"verticalScroller"];
  }
  if (header)
  {
    NSXMLElement *he = [self element:@"tableHeaderView" parent:e object:header key:@"headerView"
                          attributes:nil];

    [self viewCommon:he view:header];
  }
  return e;
}

- (NSXMLElement *)viewNSClipView:(PCGormObject *)v parent:(NSXMLElement *)parent key:(NSString *)key
{
  NSXMLElement *e = [self element:@"clipView" parent:parent object:v key:key attributes:nil];

  [self viewCommon:e view:v];
  [self subviews:[v objectForField:@"subviews"] parent:e];
  return e;
}

- (NSXMLElement *)viewNSTableView:(PCGormObject *)v parent:(NSXMLElement *)parent key:(NSString *)key
{
  BOOL         reordering = [v hasField:@"allowsColumnReordering"]
    ? [v boolForField:@"allowsColumnReordering"] : YES;
  NSXMLElement *e = [self element:@"tableView" parent:parent object:v key:key
                       attributes:ATTRS(@"verticalHuggingPriority", @"750",
                                        @"columnAutoresizingStyle",
                                        [v boolForField:@"autoresizesAllColumnsToFit"] ? @"lastColumnOnly" : @"none",
                                        @"multipleSelection", Yes([v boolForField:@"allowsMultipleSelection"]),
                                        @"emptySelection", Yes([v boolForField:@"allowsEmptySelection"]),
                                        @"columnSelection", Yes([v boolForField:@"allowsColumnSelection"]),
                                        @"columnResizing", Yes([v boolForField:@"allowsColumnResizing"]),
                                        @"columnReordering", Yes(reordering),
                                        @"autosaveColumns", @"NO",
                                        @"rowHeight", Fmt([v doubleForField:@"rowHeight"]))];
  NSXMLElement *columns;

  [self viewCommon:e view:v];
  [self size:[v sizeForField:@"intercellSpacing"] key:@"intercellSpacing" parent:e];
  if ([v objectForField:@"backgroundColor"])
  {
    [self color:[v objectForField:@"backgroundColor"] key:@"backgroundColor" parent:e];
  }
  if ([v objectForField:@"gridColor"])
  {
    [self color:[v objectForField:@"gridColor"] key:@"gridColor" parent:e];
  }
  columns = [NSXMLElement elementWithName:@"tableColumns"];
  [e addChild:columns];
  for (id column in [[v objectForField:@"tableColumns"] arrayValue])
  {
    PCGormObject *header, *data;
    NSXMLElement *ce;

    if (![column isKindOfClass:[PCGormObject class]])
    {
      continue;
    }
    ce = [self element:@"tableColumn" parent:columns object:column key:nil
            attributes:ATTRS(@"identifier", V([self string:[column objectForField:@"identifier"]]),
                             @"width", Fmt([column doubleForField:@"width"]),
                             @"minWidth", Fmt([column doubleForField:@"minWidth"]),
                             @"maxWidth", Fmt([column doubleForField:@"maxWidth"]),
                             @"editable", V([column boolForField:@"isEditable"] ? nil : @"NO"))];
    header = [column objectForField:@"headerCell"];
    if (header)
    {
      /* Interface Builder writes header cells without an id; ibtool
       * asserts while upgrading a document that has one. */
      NSString     *title = [self string:[header objectForField:@"contents"]];
      NSXMLElement *he = [self element:@"tableHeaderCell" parent:ce object:nil key:@"headerCell"
                            attributes:ATTRS(@"lineBreakMode", @"truncatingTail",
                                             @"borderStyle", @"border",
                                             @"alignment", Alignment([self alignmentOf:header], @"left"),
                                             @"title", title ? title : @"")];

      [self font:[header objectForField:@"font"] key:@"font" parent:he default:@"message"];
      [self namedColor:@"headerTextColor" key:@"textColor" parent:he];
      [self namedColor:@"headerColor" key:@"backgroundColor" parent:he];
    }
    data = [column objectForField:@"dataCell"];
    if ([data isKindOfClassNamed:@"NSButtonCell"])
    {
      [self buttonCell:data key:@"dataCell" parent:ce frame:NSZeroRect];
    }
    else if ([data isKindOfClassNamed:@"NSImageCell"])
    {
      [self element:@"imageCell" parent:ce object:data key:@"dataCell"
         attributes:ATTRS(@"refusesFirstResponder", @"YES", @"alignment", @"left",
                          @"imageScaling", @"proportionallyDown")];
    }
    else if (data)
    {
      [self textFieldCell:data key:@"dataCell" parent:ce tag:@"textFieldCell"];
    }
    [self element:@"tableColumnResizingMask" parent:ce object:nil key:@"resizingMask"
       attributes:[column boolForField:@"isResizable"]
       ? ATTRS(@"resizeWithTable", @"YES", @"userResizable", @"YES") : nil];
  }
  return e;
}

- (NSXMLElement *)viewNSTextView:(PCGormObject *)v parent:(NSXMLElement *)parent key:(NSString *)key
{
  NSXMLElement *e = [self element:@"textView" parent:parent object:v key:key
                       attributes:ATTRS(@"editable", V([v boolForField:@"isEditable"] ? nil : @"NO"),
                                        @"selectable", V([v boolForField:@"isSelectable"] ? nil : @"NO"),
                                        @"importsGraphics", Yes([v boolForField:@"importsGraphics"]),
                                        @"richText", Yes([v boolForField:@"isRichText"]),
                                        @"horizontallyResizable", Yes([v boolForField:@"isHorizontallyResizable"]),
                                        @"verticallyResizable", Yes([v boolForField:@"isVerticallyResizable"]),
                                        @"usesFontPanel", Yes([v boolForField:@"usesFontPanel"]),
                                        @"usesRuler", Yes([v boolForField:@"usesRuler"]),
                                        @"allowsUndo", Yes([v boolForField:@"allowsUndo"]),
                                        @"smartInsertDelete", Yes([v boolForField:@"smartInsertDelete"]),
                                        @"drawsBackground", V([v boolForField:@"drawsBackground"] ? nil : @"NO"),
                                        @"findStyle", V([v boolForField:@"usesFindPanel"] ? @"panel" : nil),
                                        @"allowsNonContiguousLayout", @"YES")];

  [self viewCommon:e view:v];
  if ([v objectForField:@"backgroundColor"])
  {
    [self color:[v objectForField:@"backgroundColor"] key:@"backgroundColor" parent:e];
  }
  [self size:[v sizeForField:@"minSize"] key:@"minSize" parent:e];
  [self size:[v sizeForField:@"maxSize"] key:@"maxSize" parent:e];
  if ([v objectForField:@"insertionPointColor"])
  {
    [self color:[v objectForField:@"insertionPointColor"] key:@"insertionPointColor" parent:e];
  }
  return e;
}

// --- Menus

- (NSXMLElement *)menu:(PCGormObject *)m parent:(NSXMLElement *)parent key:(NSString *)key
{
  NSString     *special = [names objectForKey:Key(m)];
  NSDictionary *systemMenus = @{@"NSMenu": @"main", @"NSWindowsMenu": @"window",
                                @"NSServicesMenu": @"services",
                                @"NSRecentDocumentsMenu": @"recentDocuments"};
  NSString     *title = [self string:[m objectForField:@"title"]];
  NSXMLElement *e = [self element:@"menu" parent:parent object:m key:key
                       attributes:ATTRS(@"title", title ? title : @"",
                                        @"systemMenu", V([systemMenus objectForKey:special]))];
  NSMutableArray *items = [NSMutableArray array];

  if (![m boolForField:@"autoenablesItems"])
  {
    [self setAttribute:@"autoenablesItems" value:@"NO" on:e];
  }
  for (id item in [[m objectForField:@"items"] arrayValue])
  {
    if ([item isKindOfClass:[PCGormObject class]])
    {
      [items addObject:item];
    }
  }
  if ([items count])
  {
    NSXMLElement *list = [NSXMLElement elementWithName:@"items"];

    [e addChild:list];
    for (PCGormObject *item in items)
    {
      [self menuItem:item parent:list];
    }
  }
  return e;
}

- (NSXMLElement *)menuItem:(PCGormObject *)item parent:(NSXMLElement *)parent
{
  NSString       *title = [self string:[item objectForField:@"title"]];
  NSString       *keyEquivalent = [self string:[item objectForField:@"keyEquivalent"]];
  NSMutableArray *attributes = [NSMutableArray arrayWithObjects:@"title", title ? title : @"", nil];
  long long      state = [item integerForField:@"state"];
  long long      mask = [item integerForField:@"keyEquivalentModifierMask"];
  NSString       *image = [self imageName:[item objectForField:@"image"]];
  NSXMLElement   *e;

  if ([keyEquivalent length])
  {
    [attributes addObjectsFromArray:@[@"keyEquivalent", keyEquivalent]];
  }
  if (state == 1)
  {
    [attributes addObjectsFromArray:@[@"state", @"on"]];
  }
  else if (state == -1)
  {
    [attributes addObjectsFromArray:@[@"state", @"mixed"]];
  }
  if ([item integerForField:@"tag"])
  {
    [attributes addObjectsFromArray:@[@"tag", Fmt([item integerForField:@"tag"])]];
  }
  if (image)
  {
    [attributes addObjectsFromArray:@[@"image", image]];
  }
  e = [self element:@"menuItem" parent:parent object:item key:nil attributes:attributes];
  /* NSMenuItem up to version 3 archived the mask shifted down. */
  if ([archive versionOfClass:@"NSMenuItem"] <= 3)
  {
    mask <<= 16;
  }
  if ([keyEquivalent length] && mask != (1 << 20))
  {
    [self modifierMask:mask parent:e];
  }
  if ([item objectForField:@"submenu"])
  {
    [self menu:[item objectForField:@"submenu"] parent:e key:@"submenu"];
  }
  return e;
}

// --- Windows and top-level objects

- (NSXMLElement *)window:(PCGormObject *)w parent:(NSXMLElement *)parent
{
  NSString       *title = [self string:[w objectForField:@"title"]];
  NSXMLElement   *e = [self element:@"window" parent:parent object:w key:nil
                         attributes:ATTRS(@"title", title ? title : @"",
                                          @"allowsToolTipsWhenApplicationIsInactive", @"NO",
                                          @"autorecalculatesKeyViewLoop", @"NO",
                                          @"releasedWhenClosed", Yes([w boolForField:@"isReleasedWhenClosed"]),
                                          @"hidesOnDeactivate", V([w boolForField:@"hidesOnDeactivate"] ? @"YES" : nil),
                                          @"oneShot", V([w boolForField:@"isOneShot"] ? nil : @"NO"),
                                          @"visibleAtLaunch", Yes([visible containsObject:Key(w)]),
                                          @"animationBehavior", @"default")];
  long long      style = [w integerForField:@"styleMask"];
  NSArray        *styles = @[@[@1, @"titled"], @[@2, @"closable"], @[@4, @"miniaturizable"],
                             @[@8, @"resizable"], @[@16, @"utility"], @[@32, @"docModal"],
                             @[@64, @"nonactivatingPanel"], @[@8192, @"HUD"]];
  NSMutableArray *mask = [NSMutableArray array];
  NSRect         content = [w rectForField:@"contentRect"];
  NSRect         screen = [w hasField:@"screenRect"] ? [w rectForField:@"screenRect"] : NSZeroRect;
  NSSize         minSize = [w sizeForField:@"minSize"];
  NSSize         maxSize = [w sizeForField:@"maxSize"];
  PCGormObject   *contentView = [w objectForField:@"contentView"];
  PCGormObject   *first = [w objectForField:@"initialFirstResponder"];

  if ([self customClassOf:w] == nil && [w isKindOfClassNamed:@"NSPanel"])
  {
    [self setAttribute:@"customClass" value:@"NSPanel" on:e];
  }
  for (NSArray *s in styles)
  {
    if (style & [[s objectAtIndex:0] longLongValue])
    {
      [mask addObjectsFromArray:@[[s objectAtIndex:1], @"YES"]];
    }
  }
  [self element:@"windowStyleMask" parent:e object:nil key:@"styleMask" attributes:mask];
  [self element:@"windowPositionMask" parent:e object:nil key:@"initialPositionMask"
     attributes:ATTRS(@"leftStrut", @"YES", @"bottomStrut", @"YES")];
  [self rect:content key:@"contentRect" parent:e];
  if (screen.size.width <= 0 || screen.size.height <= 0)
  {
    screen = NSMakeRect(0, 0, 1440, 900);
  }
  [self rect:screen key:@"screenRect" parent:e];
  /* Gorm stores the frame minimum; keep it within the content size. */
  minSize.width = MIN(minSize.width, content.size.width);
  minSize.height = MIN(minSize.height, content.size.height);
  if (minSize.width || minSize.height)
  {
    [self element:@"value" parent:e object:nil key:@"minSize"
       attributes:ATTRS(@"type", @"size", @"width", Fmt(minSize.width), @"height", Fmt(minSize.height))];
  }
  if (maxSize.width < 100000 && maxSize.height < 100000)
  {
    [self element:@"value" parent:e object:nil key:@"maxSize"
       attributes:ATTRS(@"type", @"size", @"width", Fmt(maxSize.width), @"height", Fmt(maxSize.height))];
  }
  if (contentView)
  {
    NSXMLElement *ce = [self view:contentView parent:e key:@"contentView"];
    NSXMLElement *frame = [[ce elementsForName:@"rect"] firstObject];

    [[frame attributeForName:@"x"] setStringValue:@"0.0"];
    [[frame attributeForName:@"y"] setStringValue:@"0.0"];
  }
  if (first)
  {
    [self pending:[self oid:w] kind:@"outlet" label:@"initialFirstResponder"
      destination:[self oid:first]];
  }
  return e;
}

- (void)topLevel:(PCGormObject *)o parent:(NSXMLElement *)objects
{
  NSString *cls = [o realClassName];

  if ([cls isEqualToString:@"NSWindow"] || [cls isEqualToString:@"NSPanel"])
  {
    [self window:o parent:objects];
  }
  else if ([cls isEqualToString:@"NSMenu"])
  {
    [self menu:o parent:objects key:nil];
  }
  else if ([cls isEqualToString:@"GSNibItem"] || [cls isEqualToString:@"GSCustomView"])
  {
    NSRect frame = [o rectForField:@"theFrame"];

    if (frame.size.width > 0 && frame.size.height > 0)
    {
      [self viewGSCustomView:o parent:objects key:nil];
    }
    else
    {
      NSXMLElement *e = [self element:@"customObject" parent:objects object:o key:nil attributes:nil];

      [self setAttribute:@"customClass" value:[o stringForField:@"theClass"] on:e];
    }
  }
  else if ([o hasField:@"frame"])
  {
    [self view:o parent:objects key:nil];
  }
  else
  {
    [self warn:[NSString stringWithFormat:@"skipped top-level %@", cls]];
  }
}

static NSInteger TopLevelOrder(PCGormObject *a, PCGormObject *b, void *context)
{
  NSDictionary *order = @{@"NSMenu": @0, @"NSWindow": @1, @"NSPanel": @1};
  NSNumber     *x = [order objectForKey:[a realClassName]];
  NSNumber     *y = [order objectForKey:[b realClassName]];
  NSInteger    ox = x ? [x integerValue] : 2;
  NSInteger    oy = y ? [y integerValue] : 2;

  if (ox != oy)
  {
    return ox < oy ? NSOrderedAscending : NSOrderedDescending;
  }
  if ([a identifier] != [b identifier])
  {
    return [a identifier] < [b identifier] ? NSOrderedAscending : NSOrderedDescending;
  }
  return NSOrderedSame;
}

- (NSXMLDocument *)document
{
  NSXMLElement   *root = [NSXMLElement elementWithName:@"document"];
  NSXMLDocument  *document = [[[NSXMLDocument alloc] initWithRootElement:root] autorelease];
  NSXMLElement   *dependencies = [NSXMLElement elementWithName:@"dependencies"];
  NSXMLElement   *objects = [NSXMLElement elementWithName:@"objects"];
  NSMutableArray *top = [NSMutableArray array];
  id             owner = [byName objectForKey:@"NSOwner"];
  NSString       *ownerClass = [owner isKindOfClass:[PCGormObject class]] && [owner isString]
    ? [owner stringValue] : @"NSObject";

  [document setVersion:@"1.0"];
  [document setCharacterEncoding:@"UTF-8"];
  [self collectConnections];
  for (NSArray *a in @[@[@"type", @"com.apple.InterfaceBuilder3.Cocoa.XIB"], @[@"version", @"3.0"],
                       @[@"toolsVersion", toolsVersion], @[@"targetRuntime", @"MacOSX.Cocoa"],
                       @[@"propertyAccessControl", @"none"], @[@"useAutolayout", @"NO"]])
  {
    [root addAttribute:[NSXMLNode attributeWithName:[a objectAtIndex:0] stringValue:[a objectAtIndex:1]]];
  }
  [root addChild:dependencies];
  [self element:@"plugIn" parent:dependencies object:nil key:nil
     attributes:ATTRS(@"identifier", @"com.apple.InterfaceBuilder.CocoaPlugin", @"version", toolsVersion)];
  [self element:@"capability" parent:dependencies object:nil key:nil
     attributes:ATTRS(@"name", @"documents saved in the Xcode 8 format", @"minToolsVersion", @"8.0")];
  [root addChild:objects];
  [self element:@"customObject" parent:objects object:nil key:nil
     attributes:ATTRS(@"id", OwnerID, @"userLabel", @"File's Owner", @"customClass", ownerClass)];
  [self element:@"customObject" parent:objects object:nil key:nil
     attributes:ATTRS(@"id", FirstResponderID, @"userLabel", @"First Responder",
                      @"customClass", @"FirstResponder")];
  [self element:@"customObject" parent:objects object:nil key:nil
     attributes:ATTRS(@"id", ApplicationID, @"userLabel", @"Application", @"customClass", @"NSObject")];

  for (id o in [[container objectForField:@"topLevelObjects"] arrayValue])
  {
    if ([o isKindOfClass:[PCGormObject class]])
    {
      [top addObject:o];
    }
  }
  /* Gorm also lists named objects outside any window (controllers, the
   * font manager) only in the name table on older containers. */
  for (NSArray *pair in [[container objectForField:@"nameTable"] pairsValue])
  {
    id value = [pair objectAtIndex:1];

    if ([value isKindOfClass:[PCGormObject class]] && [value isKindOfClassNamed:@"GSNibItem"]
        && [top indexOfObjectIdenticalTo:value] == NSNotFound)
    {
      [top addObject:value];
    }
  }
  [top sortUsingFunction:(NSInteger (*)(id, id, void *))TopLevelOrder context:NULL];
  for (PCGormObject *o in top)
  {
    if ([[names objectForKey:Key(o)] isEqualToString:@"NSOwner"])
    {
      continue;
    }
    [self topLevel:o parent:objects];
  }
  [self attachConnections:root];
  if ([images count])
  {
    NSXMLElement *resources = [NSXMLElement elementWithName:@"resources"];

    [root addChild:resources];
    for (NSString *name in [[images allKeys] sortedArrayUsingSelector:@selector(compare:)])
    {
      NSSize size = [[images objectForKey:name] sizeForField:@"size"];

      [self element:@"image" parent:resources object:nil key:nil
         attributes:ATTRS(@"name", name, @"width", Fmt(size.width ? size.width : 32),
                          @"height", Fmt(size.height ? size.height : 32))];
    }
  }
  return document;
}

// --- Converting interfaces

static BOOL IsBundle(NSString *path)
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString      *extension = [[path pathExtension] lowercaseString];

  if ([@[@"app", @"framework", @"bundle", @"plugin", @"xcodeproj", @"xcworkspace",
         @"build", @"gorm"] containsObject:extension])
  {
    return YES;
  }
  /* A built bundle of any extension: Cocoa's or GNUstep's layout. */
  return [fm fileExistsAtPath:[path stringByAppendingPathComponent:@"Contents/Info.plist"]]
    || [fm fileExistsAtPath:[path stringByAppendingPathComponent:@"Resources/Info-gnustep.plist"]];
}

+ (NSArray *)gormInterfacesInDirectory:(NSString *)directory
{
  NSFileManager         *fm = [NSFileManager defaultManager];
  NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:directory];
  NSMutableArray        *interfaces = [NSMutableArray array];
  NSString              *entry;

  while ((entry = [enumerator nextObject]))
  {
    NSString *name = [entry lastPathComponent];
    NSString *path = [directory stringByAppendingPathComponent:entry];
    BOOL     isDirectory = NO;

    if (![fm fileExistsAtPath:path isDirectory:&isDirectory] || !isDirectory)
    {
      continue;
    }
    if ([[[name pathExtension] lowercaseString] isEqual:@"gorm"])
    {
      if ([fm fileExistsAtPath:[path stringByAppendingPathComponent:@"objects.gorm"]])
      {
        [interfaces addObject:path];
      }
      [enumerator skipDescendents];
    }
    else if ([name hasPrefix:@"."] || [@[@"build", @"obj", @"DerivedData"] containsObject:name]
             || [[[enumerator fileAttributes] fileType] isEqual:NSFileTypeSymbolicLink]
             || IsBundle(path))
    {
      [enumerator skipDescendents];
    }
  }
  [interfaces sortUsingSelector:@selector(compare:)];
  return interfaces;
}

+ (NSString *)XIBPathForGorm:(NSString *)gormPath
{
  return [[gormPath stringByDeletingPathExtension] stringByAppendingPathExtension:@"xib"];
}

+ (BOOL)writeXIBForGormAtPath:(NSString *)gormPath
                       toPath:(NSString *)xibPath
                 toolsVersion:(NSString *)toolsVersion
                     warnings:(NSArray **)warnings
                        error:(NSString **)error
{
  NSString      *problem = nil;
  PCGormArchive *archive = [PCGormArchive archiveWithContentsOfFile:
                            [gormPath stringByAppendingPathComponent:@"objects.gorm"]
                                                              error:&problem];
  NSXMLDocument *document;
  NSData        *xml;

  if (warnings)
  {
    *warnings = nil;
  }
  if (archive == nil)
  {
    if (error) *error = problem;
    return NO;
  }
  document = [self documentForArchive:archive toolsVersion:toolsVersion warnings:warnings];
  xml = [document XMLDataWithOptions:NSXMLNodePrettyPrint | NSXMLNodeCompactEmptyElement];
  if (![xml writeToFile:xibPath atomically:YES])
  {
    if (error) *error = [NSString stringWithFormat:@"Cannot write %@", xibPath];
    return NO;
  }
  if (error) *error = nil;
  return YES;
}

+ (NSString *)interfaceBuilderVersion
{
#ifdef GNUSTEP
  return nil;
#else
  static NSString *version = nil;
  static BOOL     asked = NO;
  NSTask          *task;
  NSPipe          *pipe;
  NSData          *data = nil;
  id              plist;

  if (asked)
  {
    return version;
  }
  asked = YES;
  if (![[NSFileManager defaultManager] isExecutableFileAtPath:@"/usr/bin/xcrun"])
  {
    return nil;
  }
  task = [[[NSTask alloc] init] autorelease];
  pipe = [NSPipe pipe];
  [task setLaunchPath:@"/usr/bin/xcrun"];
  [task setArguments:@[@"ibtool", @"--version", @"--output-format", @"xml1"]];
  [task setStandardOutput:pipe];
  [task setStandardError:[NSFileHandle fileHandleWithNullDevice]];
  @try
  {
    [task launch];
    data = [[pipe fileHandleForReading] readDataToEndOfFile];
    [task waitUntilExit];
  }
  @catch (NSException *exception)
  {
    return nil;
  }
  plist = data ? [NSPropertyListSerialization propertyListWithData:data options:0
                                                             format:NULL error:NULL] : nil;
  version = [[[plist objectForKey:@"com.apple.ibtool.version"]
              objectForKey:@"bundle-version"] copy];
  return version;
#endif
}

@end
