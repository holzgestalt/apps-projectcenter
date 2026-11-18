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

#import "PCInterfaceDocument.h"

static NSString *Attribute(NSXMLElement *element, NSString *name)
{
  return [[element attributeForName:name] stringValue];
}

static void SetAttribute(NSXMLElement *element, NSString *name, NSString *value)
{
  NSXMLNode *attribute = [element attributeForName:name];

  if (attribute)
  {
    [attribute setStringValue:value];
  }
  else
  {
    [element addAttribute:[NSXMLNode attributeWithName:name stringValue:value]];
  }
}

/* A constraint's attributes in the order Xcode writes them, so that an edit
 * looks in a diff as it would after editing in Xcode. */
static void OrderConstraintAttributes(NSXMLElement *constraint)
{
  NSArray        *order = @[@"firstItem", @"firstAttribute", @"relation", @"secondItem",
                            @"secondAttribute", @"multiplier", @"priority", @"constant",
                            @"symbolic", @"placeholder", @"identifier"];
  NSMutableArray *sorted = [NSMutableArray array];
  NSMutableArray *others = [NSMutableArray array];
  NSXMLNode      *identifier = nil;

  if (![[constraint name] isEqualToString:@"constraint"])
  {
    return;
  }
  for (NSString *name in order)
  {
    NSXMLNode *attribute = [constraint attributeForName:name];

    if (attribute != nil)
    {
      [sorted addObject:[[attribute copy] autorelease]];
    }
  }
  for (NSXMLNode *attribute in [constraint attributes])
  {
    if ([[attribute name] isEqualToString:@"id"])
    {
      identifier = [[attribute copy] autorelease];
    }
    else if (![order containsObject:[attribute name]])
    {
      [others addObject:[[attribute copy] autorelease]];
    }
  }
  [sorted addObjectsFromArray:others];
  if (identifier != nil)
  {
    [sorted addObject:identifier];
  }
  [constraint setAttributes:sorted];
}

static NSArray *ChildElements(NSXMLElement *element)
{
  NSMutableArray *children = [NSMutableArray array];

  for (NSXMLNode *child in [element children])
  {
    if ([child kind] == NSXMLElementKind)
    {
      [children addObject:child];
    }
  }
  return children;
}

static NSXMLElement *ChildNamed(NSXMLElement *element, NSString *name, NSString *key)
{
  for (NSXMLElement *child in ChildElements(element))
  {
    if ([[child name] isEqualToString:name]
        && (key == nil || [Attribute(child, @"key") isEqualToString:key]))
    {
      return child;
    }
  }
  return nil;
}

/* Every element named in names, in document order. */
static void CollectElements(NSXMLElement *element, NSSet *names, NSMutableArray *found)
{
  for (NSXMLElement *child in ChildElements(element))
  {
    if ([names containsObject:[child name]])
    {
      [found addObject:child];
    }
    CollectElements(child, names, found);
  }
}

static void CollectIdentifiers(NSXMLElement *element, NSMutableSet *identifiers)
{
  NSString *identifier = Attribute(element, @"id");

  if (identifier)
  {
    [identifiers addObject:identifier];
  }
  for (NSXMLElement *child in ChildElements(element))
  {
    CollectIdentifiers(child, identifiers);
  }
}

/* The text of a node that is only white space, or nil. */
static NSString *Whitespace(NSXMLNode *node)
{
  NSString *text;

  if (node == nil || [node kind] != NSXMLTextKind)
  {
    return nil;
  }
  text = [node stringValue];
  return [[text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] == 0
  ? text : nil;
}

/* The indentation of an element: four spaces for each level, as Xcode
 * lays out a XIB. (Cocoa keeps the white space between elements to itself,
 * so it can't be read from the document.) */
static NSString *IndentOf(NSXMLNode *node)
{
  NSMutableString *indent = [NSMutableString string];
  NSXMLNode       *parent;

  for (parent = [node parent]; parent != nil && [parent kind] == NSXMLElementKind; parent = [parent parent])
  {
    [indent appendString:@"    "];
  }
  return indent;
}

static NSXMLNode *Text(NSString *string)
{
  NSXMLNode *text = [[[NSXMLNode alloc] initWithKind:NSXMLTextKind] autorelease];

  [text setStringValue:string];
  return text;
}

/* Lays out the children of a new element on lines of their own, as Xcode
 * writes them (four spaces deeper for each level). */
static void LayOut(NSXMLElement *element, NSString *indent)
{
  NSArray    *children = [[[element children] copy] autorelease];
  NSString   *inner = [indent stringByAppendingString:@"    "];
  NSUInteger i, offset = 0;

  if ([ChildElements(element) count] == 0)
  {
    return;
  }
  for (i = 0; i < [children count]; i++)
  {
    NSXMLNode *child = [children objectAtIndex:i];

    if ([child kind] == NSXMLElementKind)
    {
      [element insertChild:Text([@"\n" stringByAppendingString:inner]) atIndex:i + offset];
      offset++;
      LayOut((NSXMLElement *)child, inner);
    }
  }
  [element addChild:Text([@"\n" stringByAppendingString:indent])];
}

/* Adds a new element to parent, after the child "after" (at the end for
 * nil), on a line of its own when the document is laid out in lines. */
static void InsertElement(NSXMLElement *parent, NSXMLElement *element, NSXMLNode *after)
{
  NSString   *indent = IndentOf(parent);
  NSString   *inner = indent ? [indent stringByAppendingString:@"    "] : nil;
  NSArray    *children = [parent children];
  NSUInteger index;

  if (inner && [children count] == 0)
  {
    [parent addChild:Text([@"\n" stringByAppendingString:inner])];
    [parent addChild:element];
    [parent addChild:Text([@"\n" stringByAppendingString:indent])];
    LayOut(element, inner);
    return;
  }
  if (after != nil)
  {
    index = [children indexOfObjectIdenticalTo:after] + 1;
  }
  else
  {
    /* Before the white space that ends the parent. */
    index = [children count];
    if (index > 0 && Whitespace([children lastObject]))
    {
      index--;
    }
  }
  if (inner)
  {
    [parent insertChild:Text([@"\n" stringByAppendingString:inner]) atIndex:index];
    index++;
    LayOut(element, inner);
  }
  [parent insertChild:element atIndex:index];
}

/* A new element written <name/> when it's empty, as Xcode does. */
static NSXMLElement *NewElement(NSString *name)
{
  NSXMLElement *element = [[[NSXMLElement alloc] initWithKind:NSXMLElementKind
                                                      options:NSXMLNodeCompactEmptyElement] autorelease];

  [element setName:name];
  return element;
}

/* Detaches the element with the white space before it, and its container
 * (<connections>, <subviews>...) when that is left empty. */
static void Detach(NSXMLElement *element)
{
  NSXMLElement *container = (NSXMLElement *)[element parent];
  NSXMLNode    *before = [element previousSibling];

  if (Whitespace(before))
  {
    [before detach];
  }
  [element detach];
  if ([container attributeForName:@"key"] == nil && [ChildElements(container) count] == 0
      && [@[@"connections", @"constraints", @"subviews", @"items"] containsObject:[container name]])
  {
    Detach(container);
  }
}

/* Library objects. %1, %2... become new ids. */
static NSDictionary *LibraryTemplates(void)
{
  static NSDictionary *templates = nil;

  if (templates == nil)
  {
    templates = [[NSDictionary alloc] initWithObjectsAndKeys:
                 @"<button verticalHuggingPriority=\"750\" id=\"%1\">"
                 @"<rect key=\"frame\" x=\"0\" y=\"0\" width=\"96\" height=\"32\"/>"
                 @"<autoresizingMask key=\"autoresizingMask\" flexibleMaxX=\"YES\" flexibleMinY=\"YES\"/>"
                 @"<buttonCell key=\"cell\" type=\"push\" title=\"Button\" bezelStyle=\"rounded\" alignment=\"center\""
                 @" borderStyle=\"border\" imageScaling=\"proportionallyDown\" inset=\"2\" id=\"%2\">"
                 @"<behavior key=\"behavior\" pushIn=\"YES\" lightByBackground=\"YES\" lightByGray=\"YES\"/>"
                 @"<font key=\"font\" metaFont=\"system\"/>"
                 @"</buttonCell></button>", @"Push Button",
                 @"<button id=\"%1\">"
                 @"<rect key=\"frame\" x=\"0\" y=\"0\" width=\"100\" height=\"18\"/>"
                 @"<autoresizingMask key=\"autoresizingMask\" flexibleMaxX=\"YES\" flexibleMinY=\"YES\"/>"
                 @"<buttonCell key=\"cell\" type=\"check\" title=\"Check\" bezelStyle=\"regularSquare\""
                 @" imagePosition=\"left\" inset=\"2\" id=\"%2\">"
                 @"<behavior key=\"behavior\" changeContents=\"YES\" doesNotDimImage=\"YES\" lightByContents=\"YES\"/>"
                 @"<font key=\"font\" metaFont=\"system\"/>"
                 @"</buttonCell></button>", @"Check Box",
                 @"<textField focusRingType=\"none\" horizontalHuggingPriority=\"251\" verticalHuggingPriority=\"750\" id=\"%1\">"
                 @"<rect key=\"frame\" x=\"0\" y=\"0\" width=\"100\" height=\"16\"/>"
                 @"<autoresizingMask key=\"autoresizingMask\" flexibleMaxX=\"YES\" flexibleMinY=\"YES\"/>"
                 @"<textFieldCell key=\"cell\" lineBreakMode=\"clipping\" title=\"Label\" id=\"%2\">"
                 @"<font key=\"font\" metaFont=\"system\"/>"
                 @"<color key=\"textColor\" name=\"labelColor\" catalog=\"System\" colorSpace=\"catalog\"/>"
                 @"<color key=\"backgroundColor\" name=\"textBackgroundColor\" catalog=\"System\" colorSpace=\"catalog\"/>"
                 @"</textFieldCell></textField>", @"Label",
                 @"<textField focusRingType=\"none\" verticalHuggingPriority=\"750\" id=\"%1\">"
                 @"<rect key=\"frame\" x=\"0\" y=\"0\" width=\"120\" height=\"21\"/>"
                 @"<autoresizingMask key=\"autoresizingMask\" flexibleMaxX=\"YES\" flexibleMinY=\"YES\"/>"
                 @"<textFieldCell key=\"cell\" scrollable=\"YES\" lineBreakMode=\"clipping\" selectable=\"YES\""
                 @" editable=\"YES\" sendsActionOnEndEditing=\"YES\" borderStyle=\"bezel\" drawsBackground=\"YES\" id=\"%2\">"
                 @"<font key=\"font\" metaFont=\"system\"/>"
                 @"<color key=\"textColor\" name=\"controlTextColor\" catalog=\"System\" colorSpace=\"catalog\"/>"
                 @"<color key=\"backgroundColor\" name=\"textBackgroundColor\" catalog=\"System\" colorSpace=\"catalog\"/>"
                 @"</textFieldCell></textField>", @"Text Field",
                 @"<popUpButton verticalHuggingPriority=\"750\" id=\"%1\">"
                 @"<rect key=\"frame\" x=\"0\" y=\"0\" width=\"110\" height=\"25\"/>"
                 @"<autoresizingMask key=\"autoresizingMask\" flexibleMaxX=\"YES\" flexibleMinY=\"YES\"/>"
                 @"<popUpButtonCell key=\"cell\" type=\"push\" title=\"Item 1\" bezelStyle=\"rounded\" alignment=\"left\""
                 @" lineBreakMode=\"truncatingTail\" state=\"on\" borderStyle=\"borderAndBezel\""
                 @" imageScaling=\"proportionallyDown\" inset=\"2\" selectedItem=\"%4\" id=\"%2\">"
                 @"<behavior key=\"behavior\" lightByBackground=\"YES\" lightByGray=\"YES\"/>"
                 @"<font key=\"font\" metaFont=\"menu\"/>"
                 @"<menu key=\"menu\" id=\"%3\"><items>"
                 @"<menuItem title=\"Item 1\" state=\"on\" id=\"%4\"/>"
                 @"<menuItem title=\"Item 2\" id=\"%5\"/>"
                 @"</items></menu></popUpButtonCell></popUpButton>", @"Pop Up Button",
                 @"<slider verticalHuggingPriority=\"750\" id=\"%1\">"
                 @"<rect key=\"frame\" x=\"0\" y=\"0\" width=\"120\" height=\"24\"/>"
                 @"<autoresizingMask key=\"autoresizingMask\" flexibleMaxX=\"YES\" flexibleMinY=\"YES\"/>"
                 @"<sliderCell key=\"cell\" state=\"on\" alignment=\"left\" maxValue=\"100\" doubleValue=\"50\""
                 @" tickMarkPosition=\"above\" sliderType=\"linear\" id=\"%2\"/>"
                 @"</slider>", @"Slider",
                 @"<imageView horizontalHuggingPriority=\"251\" verticalHuggingPriority=\"251\" id=\"%1\">"
                 @"<rect key=\"frame\" x=\"0\" y=\"0\" width=\"48\" height=\"48\"/>"
                 @"<autoresizingMask key=\"autoresizingMask\" flexibleMaxX=\"YES\" flexibleMinY=\"YES\"/>"
                 @"<imageCell key=\"cell\" refusesFirstResponder=\"YES\" alignment=\"left\""
                 @" imageScaling=\"proportionallyDown\" id=\"%2\"/>"
                 @"</imageView>", @"Image View",
                 @"<box title=\"Box\" id=\"%1\">"
                 @"<rect key=\"frame\" x=\"0\" y=\"0\" width=\"200\" height=\"120\"/>"
                 @"<autoresizingMask key=\"autoresizingMask\" flexibleMaxX=\"YES\" flexibleMinY=\"YES\"/>"
                 @"<view key=\"contentView\" id=\"%2\">"
                 @"<rect key=\"frame\" x=\"3\" y=\"3\" width=\"194\" height=\"102\"/>"
                 @"<autoresizingMask key=\"autoresizingMask\" widthSizable=\"YES\" heightSizable=\"YES\"/>"
                 @"</view></box>", @"Box",
                 @"<customView id=\"%1\">"
                 @"<rect key=\"frame\" x=\"0\" y=\"0\" width=\"160\" height=\"100\"/>"
                 @"<autoresizingMask key=\"autoresizingMask\" flexibleMaxX=\"YES\" flexibleMinY=\"YES\"/>"
                 @"</customView>", @"Custom View",
                 @"<menuItem title=\"Item\" id=\"%1\"/>", @"Menu Item",
                 @"<menuItem isSeparatorItem=\"YES\" id=\"%1\"/>", @"Separator Menu Item",
                 nil];
  }
  return templates;
}

@implementation PCInterfaceDocument

+ (PCInterfaceDocument *)documentWithData:(NSData *)data error:(NSString **)error
{
  NSError            *problem = nil;
  NSXMLDocument      *xml;
  PCInterfaceDocument *result;

  xml = [[NSXMLDocument alloc] initWithData:data
                                    options:NSXMLNodePreserveAll
                                      error:&problem];
  if (xml == nil || ![[[xml rootElement] name] isEqualToString:@"document"]
      || ![Attribute([xml rootElement], @"type") isEqualToString:@"com.apple.InterfaceBuilder3.Cocoa.XIB"])
  {
    if (error)
    {
      *error = problem ? [problem localizedDescription] : @"This is not a Cocoa XIB in the Xcode format.";
    }
    [xml release];
    return nil;
  }
  result = [[[self alloc] init] autorelease];
  result->document = xml;
  {
    NSString *text = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    NSRange  end = [text hasPrefix:@"<?xml"] ? [text rangeOfString:@"?>"] : NSMakeRange(NSNotFound, 0);

    if (end.location != NSNotFound)
    {
      NSUInteger length = NSMaxRange(end);

      if ([text length] > length && [text characterAtIndex:length] == '\n')
      {
        length++;
      }
      result->declaration = [[text substringToIndex:length] retain];
    }
    result->finalNewline = [text hasSuffix:@"\n"];
  }
  result->objects = [[NSMutableArray alloc] init];
  [result reindex];
  return result;
}

- (void)dealloc
{
  [document release];
  [objects release];
  [declaration release];
  [super dealloc];
}

- (void)collectObjects:(NSXMLElement *)element
{
  for (NSXMLElement *child in ChildElements(element))
  {
    if ([child attributeForName:@"id"]
        && ![@[@"action", @"outlet", @"binding", @"constraint"] containsObject:[child name]])
    {
      [objects addObject:child];
    }
    [self collectObjects:child];
  }
}

- (void)reindex
{
  [objects removeAllObjects];
  [self collectObjects:[document rootElement]];
}

- (NSXMLDocument *)XMLDocument
{
  return document;
}

- (NSData *)data
{
  NSMutableString *text = [[[NSMutableString alloc] initWithData:[document XMLData]
                                                        encoding:NSUTF8StringEncoding] autorelease];

  /* NSXMLDocument writes its own declaration (with standalone="yes") and
   * no line break after it. */
  if (declaration && [text hasPrefix:@"<?xml"])
  {
    NSRange end = [text rangeOfString:@"?>"];
    NSUInteger length = NSMaxRange(end);

    if ([text length] > length && [text characterAtIndex:length] == '\n')
    {
      length++;
    }
    [text replaceCharactersInRange:NSMakeRange(0, length) withString:declaration];
  }
  if (finalNewline && ![text hasSuffix:@"\n"])
  {
    [text appendString:@"\n"];
  }
  return [text dataUsingEncoding:NSUTF8StringEncoding];
}

// --- Objects

- (NSArray *)objects
{
  return objects;
}

- (NSXMLElement *)objectWithIdentifier:(NSString *)identifier
{
  if (identifier == nil)
  {
    return nil;
  }
  for (NSXMLElement *object in objects)
  {
    if ([Attribute(object, @"id") isEqualToString:identifier])
    {
      return object;
    }
  }
  return nil;
}

- (NSXMLElement *)objectOfElement:(NSXMLElement *)element
{
  NSXMLNode *node;

  for (node = element; node != nil; node = [node parent])
  {
    if ([objects indexOfObjectIdenticalTo:node] != NSNotFound)
    {
      return (NSXMLElement *)node;
    }
  }
  return nil;
}

- (NSString *)nameOfObject:(NSXMLElement *)object
{
  /* Xcode prefers the label given in Interface Builder to the title. */
  NSString *name = Attribute(object, @"userLabel") ?: Attribute(object, @"title");

  if (name == nil)
  {
    for (NSXMLElement *child in ChildElements(object))
    {
      if ([[child name] hasSuffix:@"Cell"] && Attribute(child, @"title"))
      {
        name = Attribute(child, @"title");
        break;
      }
    }
  }
  if ([name length] == 0)
  {
    name = Attribute(object, @"customClass");
  }
  if ([name length] == 0)
  {
    /* As Xcode: "textField" is "Text Field". */
    NSMutableString *words = [NSMutableString string];
    NSString        *element = [object name];
    NSUInteger      i;

    for (i = 0; i < [element length]; i++)
    {
      unichar c = [element characterAtIndex:i];

      if (i > 0 && [[NSCharacterSet uppercaseLetterCharacterSet] characterIsMember:c])
      {
        [words appendString:@" "];
      }
      [words appendFormat:@"%C", c];
    }
    name = [words length] ? [[[words substringToIndex:1] uppercaseString]
                              stringByAppendingString:[words substringFromIndex:1]] : words;
  }
  return name;
}

- (NSString *)uniqueIdentifierAvoiding:(NSSet *)taken
{
  static const char *characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
  static BOOL       seeded = NO;
  NSMutableSet      *used = [NSMutableSet setWithSet:taken ?: [NSSet set]];
  NSString          *identifier;

  if (!seeded)
  {
    srandom((unsigned)([[NSDate date] timeIntervalSinceReferenceDate] * 1000)
            ^ (unsigned)[[NSProcessInfo processInfo] processIdentifier]);
    seeded = YES;
  }
  CollectIdentifiers([document rootElement], used);
  do
  {
    char       text[11];
    NSUInteger i;

    for (i = 0; i < 10; i++)
    {
      text[i] = (i == 3 || i == 6) ? '-' : characters[random() % 62];
    }
    text[10] = 0;
    identifier = [NSString stringWithUTF8String:text];
  }
  while ([used containsObject:identifier]);
  return identifier;
}

- (NSString *)uniqueIdentifier
{
  return [self uniqueIdentifierAvoiding:nil];
}

// --- Attributes

- (void)addAttributesOfElement:(NSXMLElement *)element
                        prefix:(NSString *)prefix
                        toRows:(NSMutableArray *)rows
{
  for (NSXMLNode *attribute in [element attributes])
  {
    NSString *name = [attribute name];
    BOOL     editable = ![name isEqualToString:@"id"];

    /* The key names the element in its parent; it's part of the label. */
    if ([name isEqualToString:@"key"])
    {
      continue;
    }

    [rows addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                     element, @"Element",
                     name, @"Name",
                     prefix ? [prefix stringByAppendingFormat:@".%@", name] : name, @"Label",
                     [attribute stringValue] ?: @"", @"Value",
                     [NSNumber numberWithBool:editable], @"Editable",
                     nil]];
  }
  if ([ChildElements(element) count] == 0 && [[element stringValue] length] > 0 && prefix != nil)
  {
    /* The text of an element such as <string key="keyEquivalent">. */
    [rows addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                     element, @"Element",
                     prefix, @"Label",
                     [element stringValue], @"Value",
                     [NSNumber numberWithBool:YES], @"Editable",
                     nil]];
  }
  for (NSXMLElement *child in ChildElements(element))
  {
    NSString *key = Attribute(child, @"key") ?: [child name];

    /* A control's cell is an object of its own, but holds most of what
     * the control shows. */
    if (([objects indexOfObjectIdenticalTo:child] != NSNotFound && ![key isEqualToString:@"cell"])
        || [@[@"connections", @"subviews", @"constraints", @"items", @"tabViewItems",
              @"tableColumns", @"objects", @"segments"] containsObject:[child name]])
    {
      continue;
    }
    [self addAttributesOfElement:child
                          prefix:prefix ? [prefix stringByAppendingFormat:@".%@", key] : key
                          toRows:rows];
  }
}

- (NSArray *)attributesOfObject:(NSXMLElement *)object
{
  NSMutableArray *rows = [NSMutableArray array];

  if (object != nil)
  {
    [self addAttributesOfElement:object prefix:nil toRows:rows];
  }
  return rows;
}

- (void)setValue:(NSString *)value
     ofAttribute:(NSString *)name
       ofElement:(NSXMLElement *)element
{
  if (name == nil)
  {
    [element setStringValue:value ?: @""];
  }
  else if ([value length] == 0)
  {
    [element removeAttributeForName:name];
  }
  else
  {
    SetAttribute(element, name, value);
  }
  OrderConstraintAttributes(element);
}

- (void)addAttribute:(NSString *)name
           withValue:(NSString *)value
           toElement:(NSXMLElement *)element
{
  SetAttribute(element, name, value ?: @"");
  OrderConstraintAttributes(element);
}

- (NSXMLElement *)childOfElement:(NSXMLElement *)element
                         withKey:(NSString *)key
                   creatingNamed:(NSString *)name
{
  NSXMLElement *child;

  for (child in ChildElements(element))
  {
    if ([Attribute(child, @"key") isEqualToString:key])
    {
      return child;
    }
  }
  if (element == nil || name == nil)
  {
    return nil;
  }
  child = NewElement(name);
  SetAttribute(child, @"key", key);
  InsertElement(element, child, nil);
  return child;
}

// --- Connections

- (NSArray *)allElementsNamed:(NSArray *)names
{
  NSMutableArray *found = [NSMutableArray array];

  CollectElements([document rootElement], [NSSet setWithArray:names], found);
  return found;
}

- (NSXMLElement *)sourceOfConnection:(NSXMLElement *)connection
{
  return [self objectOfElement:(NSXMLElement *)[[connection parent] parent]];
}

- (NSXMLElement *)destinationOfConnection:(NSXMLElement *)connection
{
  return [self objectWithIdentifier:Attribute(connection, @"destination")
          ?: Attribute(connection, @"target")];
}

- (NSString *)nameOfConnection:(NSXMLElement *)connection
{
  return Attribute(connection, @"property") ?: Attribute(connection, @"selector")
  ?: Attribute(connection, @"name") ?: @"";
}

- (NSArray *)connectionsOfObject:(NSXMLElement *)object
{
  NSMutableArray *outgoing = [NSMutableArray array];
  NSMutableArray *incoming = [NSMutableArray array];

  for (NSXMLElement *connection in [self allElementsNamed:@[@"outlet", @"action", @"binding"]])
  {
    if ([self sourceOfConnection:connection] == object)
    {
      [outgoing addObject:connection];
    }
    else if ([self destinationOfConnection:connection] == object)
    {
      [incoming addObject:connection];
    }
  }
  return [outgoing arrayByAddingObjectsFromArray:incoming];
}

- (NSXMLElement *)addConnection:(NSString *)kind
                     attributes:(NSArray *)attributes
                       toObject:(NSXMLElement *)source
{
  NSXMLElement *connections = ChildNamed(source, @"connections", nil);
  NSXMLElement *connection = NewElement(kind);
  NSUInteger   i;

  for (i = 0; i + 1 < [attributes count]; i += 2)
  {
    SetAttribute(connection, [attributes objectAtIndex:i], [attributes objectAtIndex:i + 1]);
  }
  SetAttribute(connection, @"id", [self uniqueIdentifier]);
  if (connections == nil)
  {
    connections = NewElement(@"connections");
    [connections addChild:connection];
    InsertElement(source, connections, nil);
  }
  else
  {
    InsertElement(connections, connection, nil);
  }
  return connection;
}

- (NSXMLElement *)addOutlet:(NSString *)property
                 fromObject:(NSXMLElement *)source
                   toObject:(NSXMLElement *)destination
{
  if ([property length] == 0 || source == nil || Attribute(destination, @"id") == nil)
  {
    return nil;
  }
  return [self addConnection:@"outlet"
                  attributes:@[@"property", property, @"destination", Attribute(destination, @"id")]
                    toObject:source];
}

- (NSXMLElement *)addAction:(NSString *)selector
                 fromObject:(NSXMLElement *)control
                   toObject:(NSXMLElement *)target
{
  if ([selector length] == 0 || control == nil || Attribute(target, @"id") == nil)
  {
    return nil;
  }
  if (![selector hasSuffix:@":"])
  {
    selector = [selector stringByAppendingString:@":"];
  }
  return [self addConnection:@"action"
                  attributes:@[@"selector", selector, @"target", Attribute(target, @"id")]
                    toObject:control];
}

- (void)removeConnection:(NSXMLElement *)connection
{
  Detach(connection);
}

// --- Constraints

- (NSXMLElement *)firstItemOfConstraint:(NSXMLElement *)constraint
{
  /* Without firstItem, the constraint is about the view that holds it. */
  return Attribute(constraint, @"firstItem")
  ? [self objectWithIdentifier:Attribute(constraint, @"firstItem")]
  : [self objectOfElement:(NSXMLElement *)[[constraint parent] parent]];
}

- (NSArray *)itemsOfConstraint:(NSXMLElement *)constraint
{
  NSMutableArray *items = [NSMutableArray array];
  NSXMLElement   *first = [self firstItemOfConstraint:constraint];
  NSXMLElement   *second = [self objectWithIdentifier:Attribute(constraint, @"secondItem")];

  if (first != nil)
  {
    [items addObject:first];
  }
  if (second != nil && second != first)
  {
    [items addObject:second];
  }
  return items;
}

- (NSArray *)constraintsOfObject:(NSXMLElement *)object
{
  NSMutableArray *found = [NSMutableArray array];

  for (NSXMLElement *constraint in [self allElementsNamed:@[@"constraint"]])
  {
    if ([self firstItemOfConstraint:constraint] == object
        || [self objectWithIdentifier:Attribute(constraint, @"secondItem")] == object)
    {
      [found addObject:constraint];
    }
  }
  return found;
}

/* As Xcode's document outline writes it: the view that holds the
 * constraint is left out, so "Name.leading = leading + 20" relates the
 * leading edges of Name and of its superview. */
- (NSString *)descriptionOfConstraint:(NSXMLElement *)constraint
{
  NSMutableString *text = [NSMutableString string];
  NSXMLElement    *owner = [self objectOfElement:(NSXMLElement *)[[constraint parent] parent]];
  NSXMLElement    *first = [self firstItemOfConstraint:constraint];
  NSXMLElement    *second = [self objectWithIdentifier:Attribute(constraint, @"secondItem")];
  NSString        *relation = Attribute(constraint, @"relation");
  NSString        *multiplier = Attribute(constraint, @"multiplier");
  NSString        *constant = Attribute(constraint, @"constant");
  NSString        *priority = Attribute(constraint, @"priority");
  NSString        *firstAttribute = Attribute(constraint, @"firstAttribute") ?: @"?";
  NSString        *secondAttribute = Attribute(constraint, @"secondAttribute") ?: @"?";

  if (first == owner || first == nil)
  {
    [text appendString:firstAttribute];
  }
  else
  {
    [text appendFormat:@"%@.%@", [self nameOfObject:first], firstAttribute];
  }
  [text appendString:[relation isEqualToString:@"greaterThanOrEqual"] ? @" \u2265 "
   : [relation isEqualToString:@"lessThanOrEqual"] ? @" \u2264 " : @" = "];
  if (second)
  {
    if (multiplier && [multiplier doubleValue] != 1.0)
    {
      [text appendFormat:@"%@ \u00D7 ", multiplier];
    }
    if (second == owner)
    {
      [text appendString:secondAttribute];
    }
    else
    {
      [text appendFormat:@"%@.%@", [self nameOfObject:second], secondAttribute];
    }
    /* A symbolic constant is the standard spacing, which Xcode doesn't show. */
    if (constant && [constant doubleValue] != 0.0 && ![Attribute(constraint, @"symbolic") isEqualToString:@"YES"])
    {
      [text appendFormat:[constant hasPrefix:@"-"] ? @" - %@" : @" + %@",
       [constant hasPrefix:@"-"] ? [constant substringFromIndex:1] : constant];
    }
  }
  else
  {
    [text appendString:constant ?: @"0"];
  }
  if (priority && [priority intValue] != 1000)
  {
    [text appendFormat:@" @%@", priority];
  }
  return text;
}


// --- Editing constraints, as Xcode's inspector shows them

- (NSXMLElement *)ownerOfConstraint:(NSXMLElement *)constraint
{
  return [self objectOfElement:(NSXMLElement *)[[constraint parent] parent]];
}

- (NSXMLElement *)secondItemOfConstraint:(NSXMLElement *)constraint
{
  return [self objectWithIdentifier:Attribute(constraint, @"secondItem")];
}

+ (NSArray *)constraintAttributes
{
  return @[@"leading", @"trailing", @"left", @"right", @"top", @"bottom", @"width", @"height",
           @"centerX", @"centerY", @"firstBaseline", @"lastBaseline",
           @"leadingMargin", @"trailingMargin", @"leftMargin", @"rightMargin", @"topMargin",
           @"bottomMargin", @"centerXWithinMargins", @"centerYWithinMargins"];
}

+ (NSString *)titleOfConstraintAttribute:(NSString *)attribute
{
  NSMutableString *words = [NSMutableString string];
  NSUInteger      i;

  if ([attribute isEqualToString:@"centerX"]) return @"Center X";
  if ([attribute isEqualToString:@"centerY"]) return @"Center Y";
  if ([attribute isEqualToString:@"centerXWithinMargins"]) return @"Center X Within Margins";
  if ([attribute isEqualToString:@"centerYWithinMargins"]) return @"Center Y Within Margins";
  for (i = 0; i < [attribute length]; i++)
  {
    unichar c = [attribute characterAtIndex:i];

    if (i > 0 && [[NSCharacterSet uppercaseLetterCharacterSet] characterIsMember:c])
    {
      [words appendString:@" "];
    }
    [words appendFormat:@"%C", c];
  }
  return [words length] ? [[[words substringToIndex:1] uppercaseString]
                           stringByAppendingString:[words substringFromIndex:1]] : words;
}

static BOOL IsHorizontal(NSString *attribute)
{
  return [@[@"leading", @"trailing", @"left", @"right", @"centerX", @"leadingMargin", @"trailingMargin",
            @"leftMargin", @"rightMargin", @"centerXWithinMargins"] containsObject:attribute ?: @""];
}

- (NSString *)kindOfConstraint:(NSXMLElement *)constraint
{
  NSString     *first = Attribute(constraint, @"firstAttribute") ?: @"";
  NSString     *second = Attribute(constraint, @"secondAttribute");
  NSXMLElement *firstItem = [self firstItemOfConstraint:constraint];
  NSXMLElement *secondItem = [self secondItemOfConstraint:constraint];
  NSXMLElement *owner = [self ownerOfConstraint:constraint];

  if (secondItem == nil)
  {
    return [first isEqualToString:@"height"] ? @"Height Constraint" : @"Width Constraint";
  }
  if ([first isEqualToString:@"width"] || [first isEqualToString:@"height"])
  {
    if (firstItem == secondItem) return @"Aspect Ratio Constraint";
    return [first isEqualToString:@"width"] ? @"Equal Widths Constraint" : @"Equal Heights Constraint";
  }
  if ([first hasPrefix:@"center"] && [first isEqualToString:second])
  {
    return [NSString stringWithFormat:@"%@ Alignment Constraint",
            [PCInterfaceDocument titleOfConstraintAttribute:first]];
  }
  if ([first isEqualToString:second] && firstItem != owner && secondItem != owner)
  {
    return [NSString stringWithFormat:@"%@ Alignment Constraint",
            [PCInterfaceDocument titleOfConstraintAttribute:first]];
  }
  return IsHorizontal(first) ? @"Horizontal Space Constraint" : @"Vertical Space Constraint";
}

- (NSArray *)candidateItemsForConstraint:(NSXMLElement *)constraint
{
  NSMutableArray *items = [NSMutableArray array];
  NSXMLElement   *owner = [self ownerOfConstraint:constraint];

  for (NSXMLElement *object in objects)
  {
    NSXMLNode *node;

    if ([[object name] hasSuffix:@"Cell"] || ChildNamed(object, @"rect", @"frame") == nil)
    {
      continue;
    }
    /* The view that holds the constraint and the views inside it. */
    for (node = object; node != nil && node != owner; node = [node parent]);
    if (node == owner)
    {
      [items addObject:object];
    }
  }
  return items;
}

- (void)setFirstItem:(NSXMLElement *)item
           attribute:(NSString *)attribute
        ofConstraint:(NSXMLElement *)constraint
{
  /* Without firstItem, a constraint is about the view that holds it. */
  if (item == nil || item == [self ownerOfConstraint:constraint])
  {
    [constraint removeAttributeForName:@"firstItem"];
  }
  else
  {
    SetAttribute(constraint, @"firstItem", Attribute(item, @"id"));
  }
  SetAttribute(constraint, @"firstAttribute", attribute);
  OrderConstraintAttributes(constraint);
}

- (void)setSecondItem:(NSXMLElement *)item
            attribute:(NSString *)attribute
         ofConstraint:(NSXMLElement *)constraint
{
  if (item == nil)
  {
    [constraint removeAttributeForName:@"secondItem"];
    [constraint removeAttributeForName:@"secondAttribute"];
    [constraint removeAttributeForName:@"multiplier"];
  }
  else
  {
    SetAttribute(constraint, @"secondItem", Attribute(item, @"id"));
    SetAttribute(constraint, @"secondAttribute", attribute);
  }
  OrderConstraintAttributes(constraint);
}

- (void)setNumber:(NSString *)value
      ofAttribute:(NSString *)name
     ofConstraint:(NSXMLElement *)constraint
{
  /* Xcode leaves out the defaults: constant 0, priority 1000, multiplier 1. */
  NSString *standard = [name isEqualToString:@"priority"] ? @"1000"
  : [name isEqualToString:@"multiplier"] ? @"1" : @"0";

  if ([name isEqualToString:@"constant"])
  {
    [constraint removeAttributeForName:@"symbolic"];
  }
  if ([value length] == 0 || ([value doubleValue] == [standard doubleValue] && [value rangeOfString:@":"].location == NSNotFound))
  {
    [constraint removeAttributeForName:name];
  }
  else
  {
    SetAttribute(constraint, name, value);
  }
  OrderConstraintAttributes(constraint);
}

- (void)removeConstraint:(NSXMLElement *)constraint
{
  Detach(constraint);
}

// --- Adding and removing objects

+ (NSArray *)libraryItems
{
  return @[@"Push Button", @"Check Box", @"Label", @"Text Field", @"Pop Up Button",
           @"Slider", @"Image View", @"Box", @"Custom View", @"Menu Item",
           @"Separator Menu Item"];
}

/* The view that takes subviews added for the selection. */
- (NSXMLElement *)viewContainerForObject:(NSXMLElement *)object
{
  NSXMLElement *element;

  for (element = object; element != nil; element = [self objectOfElement:(NSXMLElement *)[element parent]])
  {
    NSString *name = [element name];

    if ([name isEqualToString:@"window"])
    {
      return ChildNamed(element, @"view", @"contentView");
    }
    if ([name isEqualToString:@"box"])
    {
      return ChildNamed(element, @"view", @"contentView");
    }
    if ([name isEqualToString:@"tabViewItem"])
    {
      return ChildNamed(element, @"view", @"view");
    }
    if ([@[@"view", @"customView", @"visualEffectView"] containsObject:name])
    {
      return element;
    }
    if ([name isEqualToString:@"menu"] || [name isEqualToString:@"menuItem"]
        || [element parent] == nil)
    {
      return nil;
    }
  }
  return nil;
}

- (NSXMLElement *)menuForObject:(NSXMLElement *)object
{
  if ([[object name] isEqualToString:@"menu"])
  {
    return object;
  }
  if ([[object name] isEqualToString:@"menuItem"])
  {
    return [self objectOfElement:(NSXMLElement *)[object parent]];
  }
  return nil;
}

- (NSXMLElement *)elementForTemplate:(NSString *)name
{
  NSMutableString *text = [[[LibraryTemplates() objectForKey:name] mutableCopy] autorelease];
  NSXMLElement    *element;
  NSMutableSet    *taken = [NSMutableSet set];
  NSInteger       i;

  if (text == nil)
  {
    return nil;
  }
  for (i = 9; i >= 1; i--)
  {
    NSString *placeholder = [NSString stringWithFormat:@"%%%ld", (long)i];

    if ([text rangeOfString:placeholder].location != NSNotFound)
    {
      NSString *identifier = [self uniqueIdentifierAvoiding:taken];

      [text replaceOccurrencesOfString:placeholder
                            withString:identifier
                               options:0
                                 range:NSMakeRange(0, [text length])];
      [taken addObject:identifier];
    }
  }
  {
    /* Parsed as a document, so that its empty elements stay <name/>. */
    NSXMLDocument *parsed = [[NSXMLDocument alloc] initWithXMLString:text
                                                             options:NSXMLNodePreserveEmptyElements
                                                               error:NULL];
    element = [[[parsed rootElement] retain] autorelease];
    [element detach];
    [parsed release];
  }
  return element;
}

- (NSXMLElement *)insertLibraryItem:(NSString *)name
                          forObject:(NSXMLElement *)selection
{
  NSXMLElement *element;

  if ([name hasSuffix:@"Menu Item"])
  {
    NSXMLElement *menu = [self menuForObject:selection];
    NSXMLElement *items;
    NSUInteger   index;

    if (menu == nil)
    {
      return nil;
    }
    element = [self elementForTemplate:name];
    items = ChildNamed(menu, @"items", nil);
    if (items == nil)
    {
      items = NewElement(@"items");
      [items addChild:element];
      InsertElement(menu, items, nil);
    }
    else
    {
      index = [[items children] indexOfObjectIdenticalTo:selection];
      InsertElement(items, element, index == NSNotFound ? nil : selection);
    }
  }
  else
  {
    NSXMLElement *container = [self viewContainerForObject:selection];
    NSXMLElement *subviews, *frame, *containerFrame;
    NSUInteger   i;
    double       height, top;

    if (container == nil || [LibraryTemplates() objectForKey:name] == nil)
    {
      return nil;
    }
    element = [self elementForTemplate:name];
    subviews = ChildNamed(container, @"subviews", nil);
    /* Near the top left, below the views added before. */
    frame = ChildNamed(element, @"rect", @"frame");
    containerFrame = ChildNamed(container, @"rect", @"frame");
    height = [Attribute(frame, @"height") doubleValue];
    top = containerFrame ? [Attribute(containerFrame, @"height") doubleValue] : 200;
    i = [ChildElements(subviews) count] % 8;
    SetAttribute(frame, @"x", [NSString stringWithFormat:@"%lu", (unsigned long)(20 + 10 * i)]);
    SetAttribute(frame, @"y", [NSString stringWithFormat:@"%.15g", MAX(0, top - 20 - height - 10 * i)]);
    if (subviews == nil)
    {
      /* After the frame and the autoresizing mask, as Xcode writes it. */
      NSXMLElement *after = nil;

      for (NSXMLElement *child in ChildElements(container))
      {
        if ([[child name] isEqualToString:@"rect"] || [[child name] isEqualToString:@"autoresizingMask"])
        {
          after = child;
        }
      }
      subviews = NewElement(@"subviews");
      [subviews addChild:element];
      InsertElement(container, subviews, after);
    }
    else
    {
      InsertElement(subviews, element, nil);
    }
  }
  [self reindex];
  return element;
}

- (BOOL)canRemoveObject:(NSXMLElement *)object
{
  NSString *identifier = Attribute(object, @"id");

  return object != nil && identifier != nil && ![identifier hasPrefix:@"-"]
  && [object attributeForName:@"key"] == nil;
}

- (void)removeObject:(NSXMLElement *)object
{
  NSMutableSet *removed = [NSMutableSet set];

  if (![self canRemoveObject:object])
  {
    return;
  }
  CollectIdentifiers(object, removed);
  for (NSXMLElement *element in [self allElementsNamed:@[@"outlet", @"action", @"binding", @"constraint"]])
  {
    for (NSString *reference in @[@"destination", @"target", @"firstItem", @"secondItem"])
    {
      if ([removed containsObject:Attribute(element, reference) ?: @""])
      {
        Detach(element);
        break;
      }
    }
  }
  for (NSXMLElement *element in [self allElementsNamed:@[@"popUpButtonCell", @"tabView", @"window"]])
  {
    for (NSString *reference in @[@"selectedItem", @"initialItem", @"initialFirstResponder"])
    {
      if ([removed containsObject:Attribute(element, reference) ?: @""])
      {
        [element removeAttributeForName:reference];
      }
    }
  }
  Detach(object);
  [self reindex];
}

@end
