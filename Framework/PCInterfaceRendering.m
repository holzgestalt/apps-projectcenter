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

#import "PCInterfaceRendering.h"

static NSString *Attribute(NSXMLElement *element, NSString *name)
{
  return [[element attributeForName:name] stringValue];
}

static BOOL IsYes(NSXMLElement *element, NSString *name)
{
  return [Attribute(element, name) isEqualToString:@"YES"];
}

NSXMLElement *PCInterfaceChild(NSXMLElement *element, NSString *keyOrName)
{
  NSXMLElement *named = nil;

  for (NSXMLNode *node in [element children])
  {
    if ([node kind] != NSXMLElementKind)
    {
      continue;
    }
    if ([Attribute((NSXMLElement *)node, @"key") isEqualToString:keyOrName])
    {
      return (NSXMLElement *)node;
    }
    if (named == nil && [[node name] isEqualToString:keyOrName])
    {
      named = (NSXMLElement *)node;
    }
  }
  return named;
}

/* The cell of a control: <buttonCell key="cell">. */
static NSXMLElement *CellOf(NSXMLElement *object)
{
  return PCInterfaceChild(object, @"cell");
}

static NSArray *ElementsOf(NSXMLElement *element, NSString *container, NSString *name)
{
  NSXMLElement *holder = container ? PCInterfaceChild(element, container) : element;

  return holder ? [holder elementsForName:name] : [NSArray array];
}

// --- Colors and fonts

NSColor *PCInterfaceColor(NSXMLElement *color)
{
  NSString *space = Attribute(color, @"colorSpace");
  CGFloat  alpha = Attribute(color, @"alpha") ? [Attribute(color, @"alpha") doubleValue] : 1;

  if (color == nil)
  {
    return nil;
  }
  if ([space isEqualToString:@"catalog"])
  {
    NSString *name = Attribute(color, @"name");
    SEL      selector = NSSelectorFromString(name);

    /* System colors are class methods of NSColor on both platforms; the
     * active theme supplies them on GNUstep. */
    if (name && [NSColor respondsToSelector:selector])
    {
      return [NSColor performSelector:selector];
    }
    return [NSColor colorWithCatalogName:Attribute(color, @"catalog") ?: @"System"
                               colorName:name ?: @""];
  }
  if (Attribute(color, @"white"))
  {
    return [NSColor colorWithCalibratedWhite:[Attribute(color, @"white") doubleValue] alpha:alpha];
  }
  if (Attribute(color, @"red"))
  {
    return [NSColor colorWithCalibratedRed:[Attribute(color, @"red") doubleValue]
                                     green:[Attribute(color, @"green") doubleValue]
                                      blue:[Attribute(color, @"blue") doubleValue]
                                     alpha:alpha];
  }
  return nil;
}

NSFont *PCInterfaceFont(NSXMLElement *font)
{
  NSString *meta = Attribute(font, @"metaFont");
  CGFloat  size = [Attribute(font, @"size") doubleValue];
  NSFont   *result = nil;

  if (font == nil)
  {
    return nil;
  }
  if (meta)
  {
    if ([meta hasPrefix:@"smallSystem"])
    {
      size = size ?: [NSFont smallSystemFontSize];
    }
    else if ([meta hasPrefix:@"miniSystem"])
    {
      size = size ?: 9;
    }
    if ([meta hasSuffix:@"Bold"])
    {
      result = [NSFont boldSystemFontOfSize:size];
    }
    else if ([meta isEqualToString:@"label"])
    {
      result = [NSFont labelFontOfSize:size];
    }
    else if ([meta isEqualToString:@"menu"] || [meta isEqualToString:@"menuBar"])
    {
      result = [NSFont menuFontOfSize:size];
    }
    else if ([meta isEqualToString:@"message"])
    {
      result = [NSFont messageFontOfSize:size];
    }
    else if ([meta isEqualToString:@"toolTip"])
    {
      result = [NSFont toolTipsFontOfSize:size];
    }
    else if ([meta isEqualToString:@"titleBar"])
    {
      result = [NSFont titleBarFontOfSize:size];
    }
    else if ([meta isEqualToString:@"userFixed"] || [meta isEqualToString:@"fixedUser"])
    {
      result = [NSFont userFixedPitchFontOfSize:size];
    }
    else if ([meta isEqualToString:@"user"])
    {
      result = [NSFont userFontOfSize:size];
    }
    else
    {
      result = [NSFont systemFontOfSize:size];
    }
  }
  else if (Attribute(font, @"name"))
  {
    result = [NSFont fontWithName:Attribute(font, @"name") size:size ?: 13];
  }
  return result ?: [NSFont systemFontOfSize:size];
}

NSString *PCInterfaceFontDescription(NSXMLElement *font)
{
  NSString *meta = Attribute(font, @"metaFont");
  NSString *size = Attribute(font, @"size");
  NSString *name;

  if (font == nil)
  {
    return @"";
  }
  if (meta)
  {
    NSDictionary *names = [NSDictionary dictionaryWithObjectsAndKeys:
                           @"System", @"system", @"System Bold", @"systemBold",
                           @"System Small", @"smallSystem", @"System Small Bold", @"smallSystemBold",
                           @"System Mini", @"miniSystem", @"Label", @"label", @"Message", @"message",
                           @"Menu", @"menu", @"Tool Tip", @"toolTip", @"Title Bar", @"titleBar",
                           @"User Fixed Pitch", @"userFixed", @"User", @"user",
                           @"Control Content", @"controlContent", nil];

    name = [names objectForKey:meta] ?: meta;
    if (size == nil)
    {
      /* As Xcode: the size the font has now. */
      size = [NSString stringWithFormat:@"%g", [PCInterfaceFont(font) pointSize]];
    }
  }
  else
  {
    name = Attribute(font, @"name") ?: @"Font";
  }
  return size ? [NSString stringWithFormat:@"%@ %@", name, size] : name;
}

// --- Cells

static NSTextAlignment Alignment(NSString *value)
{
  if ([value isEqualToString:@"center"])
  {
    return NSCenterTextAlignment;
  }
  if ([value isEqualToString:@"right"])
  {
    return NSRightTextAlignment;
  }
  if ([value isEqualToString:@"justified"])
  {
    return NSJustifiedTextAlignment;
  }
  if ([value isEqualToString:@"natural"])
  {
    return NSNaturalTextAlignment;
  }
  return NSLeftTextAlignment;
}

static NSLineBreakMode LineBreak(NSString *value)
{
  NSArray *modes = @[@"wordWrapping", @"charWrapping", @"clipping",
                     @"truncatingHead", @"truncatingTail", @"truncatingMiddle"];
  NSUInteger index = value ? [modes indexOfObject:value] : NSNotFound;

  return index == NSNotFound ? NSLineBreakByClipping : (NSLineBreakMode)index;
}

static NSInteger IndexOf(NSString *value, NSArray *values, NSInteger missing)
{
  NSUInteger index = value ? [values indexOfObject:value] : NSNotFound;

  return index == NSNotFound ? missing : (NSInteger)index;
}

static NSImage *Image(NSString *name)
{
  return [name length] ? [NSImage imageNamed:name] : nil;
}

/* What every cell takes from the XML: font, alignment, state, enabled. */
static void ConfigureCell(NSCell *cell, NSXMLElement *element)
{
  NSFont   *font = PCInterfaceFont(PCInterfaceChild(element, @"font"));
  NSString *state = Attribute(element, @"state");

  if (font)
  {
    [cell setFont:font];
  }
  if (Attribute(element, @"alignment"))
  {
    [cell setAlignment:Alignment(Attribute(element, @"alignment"))];
  }
  if (Attribute(element, @"lineBreakMode"))
  {
    [cell setLineBreakMode:LineBreak(Attribute(element, @"lineBreakMode"))];
  }
  if ([state isEqualToString:@"on"])
  {
    [cell setState:NSOnState];
  }
  else if ([state isEqualToString:@"mixed"])
  {
    [cell setAllowsMixedState:YES];
    [cell setState:NSMixedState];
  }
  if ([Attribute(element, @"enabled") isEqualToString:@"NO"])
  {
    [cell setEnabled:NO];
  }
  if ([Attribute(element, @"controlSize") isEqualToString:@"small"])
  {
    [cell setControlSize:NSSmallControlSize];
  }
  else if ([Attribute(element, @"controlSize") isEqualToString:@"mini"])
  {
    [cell setControlSize:NSMiniControlSize];
  }
}

static NSBezelStyle BezelStyle(NSString *value)
{
  NSArray *styles = @[@"", @"rounded", @"regularSquare", @"thickSquare", @"thickerSquare",
                      @"disclosure", @"shadowlessSquare", @"circular", @"texturedSquare",
                      @"helpButton", @"smallSquare", @"texturedRounded", @"roundRect",
                      @"recessed", @"roundedDisclosure"];
  NSInteger index = IndexOf(value, styles, 0);

  /* NSRoundedBezelStyle is 1, and the others follow it in both AppKits. */
  return index > 0 ? (NSBezelStyle)index : NSRoundedBezelStyle;
}

static NSButtonCell *ButtonCell(NSXMLElement *cellElement, NSXMLElement *control)
{
  NSString     *type = Attribute(cellElement, @"type");
  NSString     *title = Attribute(cellElement, @"title") ?: @"";
  NSButtonCell *cell = [[[NSButtonCell alloc] initTextCell:title] autorelease];
  NSXMLElement *behavior = PCInterfaceChild(cellElement, @"behavior");
  NSImage      *image = Image(Attribute(cellElement, @"image"));
  NSArray      *positions = @[@"noImage", @"only", @"left", @"right", @"below", @"above", @"overlaps"];

  if ([type isEqualToString:@"check"])
  {
    [cell setButtonType:NSSwitchButton];
  }
  else if ([type isEqualToString:@"radio"])
  {
    [cell setButtonType:NSRadioButton];
  }
  else
  {
    [cell setButtonType:IsYes(behavior, @"pushIn") ? NSMomentaryPushInButton : NSMomentaryLightButton];
    [cell setBezelStyle:BezelStyle(Attribute(cellElement, @"bezelStyle"))];
    [cell setBordered:Attribute(cellElement, @"borderStyle") != nil
                      || Attribute(cellElement, @"bezelStyle") != nil];
    if (IsYes(cellElement, @"transparent"))
    {
      [cell setTransparent:YES];
    }
  }
  [cell setTitle:title];
  ConfigureCell(cell, cellElement);
  if (control && [Attribute(control, @"enabled") isEqualToString:@"NO"])
  {
    [cell setEnabled:NO];
  }
  if (image && ![type isEqualToString:@"check"] && ![type isEqualToString:@"radio"])
  {
    [cell setImage:image];
    [cell setImagePosition:(NSCellImagePosition)IndexOf(Attribute(cellElement, @"imagePosition"), positions,
                                                         [title length] ? NSImageLeft : NSImageOnly)];
  }
  return cell;
}

static void DrawButton(NSXMLElement *object, NSRect frame, NSView *view)
{
  NSXMLElement *cellElement = CellOf(object);

  if (cellElement)
  {
    [ButtonCell(cellElement, object) drawWithFrame:frame inView:view];
  }
}

static NSPopUpButtonCell *PopUpCell(NSXMLElement *cellElement)
{
  NSPopUpButtonCell *cell = [[[NSPopUpButtonCell alloc] initTextCell:@""
                                                           pullsDown:IsYes(cellElement, @"pullsDown")] autorelease];
  NSString          *selected = Attribute(cellElement, @"selectedItem");
  NSString          *arrow = Attribute(cellElement, @"arrowPosition");
  NSInteger         index = 0, selectedIndex = -1;

  for (NSXMLElement *item in ElementsOf(PCInterfaceChild(cellElement, @"menu"), @"items", @"menuItem"))
  {
    NSString *title = Attribute(item, @"title") ?: @"";

    if (IsYes(item, @"isSeparatorItem"))
    {
      [[cell menu] addItem:[NSMenuItem separatorItem]];
    }
    else
    {
      /* Added to the menu, so equal titles stay separate items. */
      NSMenuItem *menuItem = [[[NSMenuItem alloc] initWithTitle:title action:NULL keyEquivalent:@""] autorelease];

      [menuItem setImage:Image(Attribute(item, @"image"))];
      [[cell menu] addItem:menuItem];
    }
    if ([selected isEqualToString:Attribute(item, @"id")])
    {
      selectedIndex = index;
    }
    index++;
  }
  if ([cell numberOfItems] == 0)
  {
    [cell addItemWithTitle:Attribute(cellElement, @"title") ?: @""];
  }
  if (selectedIndex >= 0)
  {
    [cell selectItemAtIndex:selectedIndex];
  }
  if (IsYes(cellElement, @"pullsDown") && Attribute(cellElement, @"title"))
  {
    [[cell itemAtIndex:0] setTitle:Attribute(cellElement, @"title")];
  }
  [cell setArrowPosition:[arrow isEqualToString:@"noArrow"] ? NSPopUpNoArrow
                         : [arrow isEqualToString:@"arrowAtCenter"] ? NSPopUpArrowAtCenter : NSPopUpArrowAtBottom];
  [cell setBezelStyle:BezelStyle(Attribute(cellElement, @"bezelStyle"))];
  [cell setBordered:Attribute(cellElement, @"borderStyle") != nil];
  ConfigureCell(cell, cellElement);
  [cell setState:NSOffState];
  return cell;
}

static NSTextFieldCell *TextFieldCell(NSXMLElement *cellElement, Class cellClass)
{
  NSTextFieldCell *cell = [[[cellClass alloc] initTextCell:Attribute(cellElement, @"title") ?: @""] autorelease];
  NSString        *border = Attribute(cellElement, @"borderStyle");
  NSColor         *text = PCInterfaceColor(PCInterfaceChild(cellElement, @"textColor"));
  NSColor         *background = PCInterfaceColor(PCInterfaceChild(cellElement, @"backgroundColor"));

  [cell setBezeled:[border isEqualToString:@"bezel"]];
  [cell setBordered:[border isEqualToString:@"border"]];
  if ([Attribute(cellElement, @"bezelStyle") isEqualToString:@"round"])
  {
    [cell setBezelStyle:NSTextFieldRoundedBezel];
  }
  [cell setDrawsBackground:IsYes(cellElement, @"drawsBackground")];
  if (text)
  {
    [cell setTextColor:text];
  }
  if (background)
  {
    [cell setBackgroundColor:background];
  }
  if (Attribute(cellElement, @"placeholderString"))
  {
    [cell setPlaceholderString:Attribute(cellElement, @"placeholderString")];
  }
  [cell setWraps:[Attribute(cellElement, @"lineBreakMode") hasSuffix:@"Wrapping"]];
  ConfigureCell(cell, cellElement);
  return cell;
}

static void DrawTextField(NSXMLElement *object, NSRect frame, NSView *view, Class cellClass)
{
  NSXMLElement    *cellElement = CellOf(object);
  NSTextFieldCell *cell = cellElement ? TextFieldCell(cellElement, cellClass) : nil;

  if (cell == nil)
  {
    return;
  }
#ifndef GNUSTEP
  /* Cocoa draws a field's bezel and background in the NSTextField, not in
   * its cell, so here they are drawn as macOS shows them. GNUstep's cells
   * draw them as the theme does. */
  /* Read from the XML: a Cocoa cell outside a text field forgets its bezel. */
  NSString *border = Attribute(cellElement, @"borderStyle");
  BOOL     bezeled = [border isEqualToString:@"bezel"], bordered = [border isEqualToString:@"border"];
  BOOL     background = IsYes(cellElement, @"drawsBackground");

  if (bezeled || bordered || background)
  {
    BOOL         rounded = bezeled && [Attribute(cellElement, @"bezelStyle") isEqualToString:@"round"];
    CGFloat      radius = rounded ? NSHeight(frame) / 2 : 0;
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(frame, 0.5, 0.5)
                                                         xRadius:radius yRadius:radius];
    NSColor      *fill = PCInterfaceColor(PCInterfaceChild(cellElement, @"backgroundColor"))
                         ?: [NSColor textBackgroundColor];

    if (background || bezeled)
    {
      [(background ? fill : [NSColor textBackgroundColor]) set];
      [path fill];
    }
    if (bezeled || bordered)
    {
      [(bezeled ? [NSColor gridColor] : [NSColor controlTextColor]) set];
      [path stroke];
    }
    [cell setBezeled:NO];
    [cell setBordered:NO];
    [cell setDrawsBackground:NO];
    frame = NSInsetRect(frame, 2, 2);
  }
#endif
  [cell drawWithFrame:frame inView:view];
}

static void DrawSlider(NSXMLElement *object, NSRect frame, NSView *view)
{
  NSXMLElement *cellElement = CellOf(object);
  NSSliderCell *cell = [[[NSSliderCell alloc] init] autorelease];

  [cell setMinValue:[Attribute(cellElement, @"minValue") doubleValue]];
  [cell setMaxValue:Attribute(cellElement, @"maxValue") ? [Attribute(cellElement, @"maxValue") doubleValue] : 100];
  [cell setDoubleValue:[Attribute(cellElement, @"doubleValue") doubleValue]];
  [cell setNumberOfTickMarks:[Attribute(cellElement, @"numberOfTickMarks") integerValue]];
  if ([Attribute(cellElement, @"tickMarkPosition") isEqualToString:@"above"]
      || [Attribute(cellElement, @"tickMarkPosition") isEqualToString:@"leading"])
  {
    [cell setTickMarkPosition:NSTickMarkAbove];
  }
  ConfigureCell(cell, cellElement);
  [cell drawWithFrame:frame inView:view];
}

static void DrawStepper(NSXMLElement *object, NSRect frame, NSView *view)
{
  NSStepperCell *cell = [[[NSStepperCell alloc] init] autorelease];

  ConfigureCell(cell, CellOf(object));
  [cell drawWithFrame:frame inView:view];
}

static void DrawImageView(NSXMLElement *object, NSRect frame, NSView *view)
{
  NSXMLElement *cellElement = CellOf(object);
  NSImageCell  *cell = [[[NSImageCell alloc] initImageCell:Image(Attribute(cellElement, @"image"))] autorelease];
  NSArray      *frames = @[@"none", @"photo", @"grayBezel", @"groove", @"button"];
  NSArray      *alignments = @[@"center", @"top", @"topLeft", @"topRight", @"left",
                               @"bottom", @"bottomLeft", @"bottomRight", @"right"];
  NSArray      *scalings = @[@"proportionallyDown", @"axesIndependently", @"none", @"proportionallyUpOrDown"];

  [cell setImageFrameStyle:(NSImageFrameStyle)IndexOf(Attribute(cellElement, @"imageFrameStyle"), frames, 0)];
  [cell setImageAlignment:(NSImageAlignment)IndexOf(Attribute(cellElement, @"imageAlignment"), alignments, 0)];
  [cell setImageScaling:(NSImageScaling)IndexOf(Attribute(cellElement, @"imageScaling"), scalings, 0)];
  [cell drawWithFrame:frame inView:view];
  if ([cell image] == nil)
  {
    /* An image that isn't in the application: its name, as Xcode does. */
    NSString *name = Attribute(cellElement, @"image") ?: @"Image";
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                [NSFont systemFontOfSize:10], NSFontAttributeName,
                                [NSColor disabledControlTextColor], NSForegroundColorAttributeName, nil];
    NSSize size = [name sizeWithAttributes:attributes];

    [[NSColor gridColor] set];
    NSFrameRect(frame);
    [name drawAtPoint:NSMakePoint(NSMidX(frame) - size.width / 2, NSMidY(frame) - size.height / 2)
       withAttributes:attributes];
  }
}

static void DrawSegments(NSXMLElement *object, NSRect frame, NSView *view)
{
  NSXMLElement     *cellElement = CellOf(object);
  NSArray          *segments = ElementsOf(cellElement, @"segments", @"segment");
  NSSegmentedCell  *cell = [[[NSSegmentedCell alloc] init] autorelease];
  NSInteger        i;

  [cell setSegmentCount:[segments count]];
  for (i = 0; i < (NSInteger)[segments count]; i++)
  {
    NSXMLElement *segment = [segments objectAtIndex:i];

    [cell setLabel:Attribute(segment, @"label") ?: @"" forSegment:i];
    if (Attribute(segment, @"image"))
    {
      [cell setImage:Image(Attribute(segment, @"image")) forSegment:i];
    }
    if (Attribute(segment, @"width"))
    {
      [cell setWidth:[Attribute(segment, @"width") doubleValue] forSegment:i];
    }
    [cell setSelected:IsYes(segment, @"selected") forSegment:i];
  }
  ConfigureCell(cell, cellElement);
  [cell drawWithFrame:frame inView:view];
}

static void DrawColorWell(NSXMLElement *object, NSRect frame, NSView *view)
{
  NSColor *color = PCInterfaceColor(PCInterfaceChild(object, @"color")) ?: [NSColor blackColor];

  NSDrawButton(frame, frame);
  [color set];
  NSRectFill(NSInsetRect(frame, 6, 6));
  [[NSColor controlShadowColor] set];
  NSFrameRect(NSInsetRect(frame, 6, 6));
}

static void DrawProgress(NSXMLElement *object, NSRect frame, NSView *view)
{
  double max = Attribute(object, @"maxValue") ? [Attribute(object, @"maxValue") doubleValue] : 100;
  double min = [Attribute(object, @"minValue") doubleValue];
  double value = [Attribute(object, @"doubleValue") doubleValue];

  if ([Attribute(object, @"style") isEqualToString:@"spinning"])
  {
    NSBezierPath *ring = [NSBezierPath bezierPathWithOvalInRect:
                          NSInsetRect(NSMakeRect(NSMidX(frame) - 8, NSMidY(frame) - 8, 16, 16), 1, 1)];
    [ring setLineWidth:2];
    [[NSColor controlShadowColor] set];
    [ring stroke];
    return;
  }
  NSRect track = NSMakeRect(NSMinX(frame), NSMidY(frame) - 3, NSWidth(frame), 6);
  NSRect done = track;

  done.size.width = max > min ? NSWidth(track) * MAX(0, MIN(1, (value - min) / (max - min))) : 0;
  [[NSColor controlShadowColor] set];
  [[NSBezierPath bezierPathWithRoundedRect:track xRadius:3 yRadius:3] fill];
  [[NSColor selectedControlColor] set];
  [[NSBezierPath bezierPathWithRoundedRect:done xRadius:3 yRadius:3] fill];
}

static void DrawLevelIndicator(NSXMLElement *object, NSRect frame, NSView *view)
{
  NSXMLElement         *cellElement = CellOf(object);
  NSLevelIndicatorCell *cell = [[[NSLevelIndicatorCell alloc]
                                 initWithLevelIndicatorStyle:NSContinuousCapacityLevelIndicatorStyle] autorelease];

  [cell setMinValue:[Attribute(cellElement, @"minValue") doubleValue]];
  [cell setMaxValue:Attribute(cellElement, @"maxValue") ? [Attribute(cellElement, @"maxValue") doubleValue] : 100];
  [cell setDoubleValue:[Attribute(cellElement, @"doubleValue") doubleValue]];
  [cell drawWithFrame:frame inView:view];
}

/* A matrix draws its cells in rows and columns. */
static void DrawMatrix(NSXMLElement *object, NSRect frame, NSView *view)
{
  NSArray   *columns = ElementsOf(object, @"cells", @"column");
  NSInteger rows = [Attribute(object, @"numberOfRows") integerValue];
  NSInteger count = [columns count];
  NSXMLElement *size = PCInterfaceChild(object, @"cellSize");
  NSXMLElement *spacing = PCInterfaceChild(object, @"intercellSpacing");
  CGFloat   width = size ? [Attribute(size, @"width") doubleValue] : (count ? NSWidth(frame) / count : 0);
  CGFloat   height = size ? [Attribute(size, @"height") doubleValue] : (rows ? NSHeight(frame) / rows : 0);
  CGFloat   dx = [Attribute(spacing, @"width") doubleValue], dy = [Attribute(spacing, @"height") doubleValue];
  NSInteger column, row;

  for (column = 0; column < count; column++)
  {
    NSMutableArray *cells = [NSMutableArray array];

    for (NSXMLNode *node in [[columns objectAtIndex:column] children])
    {
      if ([node kind] == NSXMLElementKind)
      {
        [cells addObject:node];
      }
    }

    for (row = 0; row < (NSInteger)[cells count]; row++)
    {
      NSXMLElement *cellElement = [cells objectAtIndex:row];
      NSRect       rect = NSMakeRect(NSMinX(frame) + column * (width + dx),
                                     NSMaxY(frame) - (row + 1) * height - row * dy, width, height);

      if ([[cellElement name] isEqualToString:@"buttonCell"])
      {
        [ButtonCell(cellElement, object) drawWithFrame:rect inView:view];
      }
      else if ([[cellElement name] hasSuffix:@"Cell"])
      {
        [TextFieldCell(cellElement, [NSTextFieldCell class]) drawWithFrame:rect inView:view];
      }
    }
  }
}

static void DrawTitle(NSString *title, NSPoint point, NSFont *font, NSColor *color)
{
  [title drawAtPoint:point withAttributes:
   [NSDictionary dictionaryWithObjectsAndKeys:font, NSFontAttributeName,
    color ?: [NSColor controlTextColor], NSForegroundColorAttributeName, nil]];
}

static void DrawBox(NSXMLElement *object, NSRect frame, NSView *view)
{
  NSString *type = Attribute(object, @"boxType");
  NSString *border = Attribute(object, @"borderType") ?: @"bezel";
  NSString *position = Attribute(object, @"titlePosition") ?: @"atTop";
  NSString *title = Attribute(object, @"title") ?: @"Box";
  NSFont   *font = PCInterfaceFont(PCInterfaceChild(object, @"titleFont")) ?: [NSFont systemFontOfSize:11];
  NSRect   body = frame;

  if ([type isEqualToString:@"separator"])
  {
    [[NSColor controlShadowColor] set];
    NSRectFill(NSWidth(frame) >= NSHeight(frame)
               ? NSMakeRect(NSMinX(frame), floor(NSMidY(frame)), NSWidth(frame), 1)
               : NSMakeRect(floor(NSMidX(frame)), NSMinY(frame), 1, NSHeight(frame)));
    return;
  }
  if (![position isEqualToString:@"noTitle"])
  {
    CGFloat height = ceil([font ascender] - [font descender]) + 2;

    if ([position hasSuffix:@"Bottom"])
    {
      DrawTitle(title, NSMakePoint(NSMinX(frame) + 6, NSMinY(frame)), font, nil);
      body.origin.y += height;
      body.size.height -= height;
    }
    else
    {
      DrawTitle(title, NSMakePoint(NSMinX(frame) + 6, NSMaxY(frame) - height), font, nil);
      body.size.height -= height;
    }
  }
  if ([type isEqualToString:@"custom"])
  {
    CGFloat      radius = [Attribute(object, @"cornerRadius") doubleValue];
    CGFloat      width = Attribute(object, @"borderWidth") ? [Attribute(object, @"borderWidth") doubleValue] : 1;
    NSColor      *fill = PCInterfaceColor(PCInterfaceChild(object, @"fillColor"));
    NSColor      *line = PCInterfaceColor(PCInterfaceChild(object, @"borderColor"));
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(body, width / 2, width / 2)
                                                         xRadius:radius yRadius:radius];

    if (IsYes(object, @"transparent"))
    {
      return;
    }
    if (fill)
    {
      [fill set];
      [path fill];
    }
    if (![border isEqualToString:@"none"] && width > 0)
    {
      [(line ?: [NSColor gridColor]) set];
      [path setLineWidth:width];
      [path stroke];
    }
    return;
  }
  if ([border isEqualToString:@"none"])
  {
    return;
  }
  if ([border isEqualToString:@"line"])
  {
    [[NSColor gridColor] set];
    NSFrameRect(body);
  }
  else if ([border isEqualToString:@"groove"])
  {
    NSDrawGroove(body, body);
  }
  else
  {
    /* A primary box: the theme's grouping look, a lighter area with an edge. */
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(body, 0.5, 0.5)
                                                         xRadius:5 yRadius:5];

    [[[NSColor controlShadowColor] colorWithAlphaComponent:0.08] set];
    [path fill];
    [[NSColor gridColor] set];
    [path stroke];
  }
}

static void DrawScrollBorder(NSXMLElement *object, NSRect frame)
{
  NSString *border = Attribute(object, @"borderType") ?: @"bezel";

  if ([border isEqualToString:@"bezel"])
  {
    NSDrawGrayBezel(frame, frame);
  }
  else if ([border isEqualToString:@"groove"])
  {
    NSDrawGroove(frame, frame);
  }
  else if ([border isEqualToString:@"line"])
  {
    [[NSColor gridColor] set];
    NSFrameRect(frame);
  }
}

static void DrawScroller(NSXMLElement *object, NSRect frame)
{
  BOOL    vertical = NSHeight(frame) > NSWidth(frame);
  double  proportion = Attribute(object, @"knobProportion") ? [Attribute(object, @"knobProportion") doubleValue] : 0.3;
  double  value = [Attribute(object, @"doubleValue") doubleValue];
  NSRect  knob = NSInsetRect(frame, 3, 3);

  if (IsYes(object, @"hidden"))
  {
    return;
  }
  [[[NSColor controlShadowColor] colorWithAlphaComponent:0.15] set];
  NSRectFill(frame);
  if (vertical)
  {
    knob.size.height = MAX(16, NSHeight(knob) * proportion);
    knob.origin.y = NSMaxY(NSInsetRect(frame, 3, 3)) - NSHeight(knob)
                    - value * (NSHeight(NSInsetRect(frame, 3, 3)) - NSHeight(knob));
  }
  else
  {
    knob.size.width = MAX(16, NSWidth(knob) * proportion);
    knob.origin.x += value * (NSWidth(NSInsetRect(frame, 3, 3)) - NSWidth(knob));
  }
  [[[NSColor controlShadowColor] colorWithAlphaComponent:0.6] set];
  [[NSBezierPath bezierPathWithRoundedRect:knob xRadius:MIN(NSWidth(knob), NSHeight(knob)) / 2
                                   yRadius:MIN(NSWidth(knob), NSHeight(knob)) / 2] fill];
}

/* Rows, column headers and grid of a table or outline view. */
static void DrawTable(NSXMLElement *object, NSRect frame, NSView *view)
{
  NSColor *background = PCInterfaceColor(PCInterfaceChild(object, @"backgroundColor"))
                        ?: [NSColor controlBackgroundColor];
  CGFloat rowHeight = Attribute(object, @"rowHeight") ? [Attribute(object, @"rowHeight") doubleValue] : 17;
  BOOL    alternating = IsYes(object, @"alternatingRowBackgroundColors");
  CGFloat y;
  NSInteger row = 0;

  [background set];
  NSRectFill(frame);
  if (rowHeight < 4)
  {
    return;
  }
  for (y = NSMaxY(frame) - rowHeight; y > NSMinY(frame) - rowHeight; y -= rowHeight, row++)
  {
    if (alternating && row % 2 == 1)
    {
      [[[NSColor controlAlternatingRowBackgroundColors] lastObject] set];
      NSRectFill(NSIntersectionRect(frame, NSMakeRect(NSMinX(frame), y, NSWidth(frame), rowHeight)));
    }
  }
  /* Column lines where the columns end. */
  CGFloat x = NSMinX(frame);
  for (NSXMLElement *column in ElementsOf(object, @"tableColumns", @"tableColumn"))
  {
    x += [Attribute(column, @"width") doubleValue] + 3;
    if (x < NSMaxX(frame) - 1 && [Attribute(object, @"gridStyleMask") length])
    {
      [[NSColor gridColor] set];
      NSRectFill(NSMakeRect(x, NSMinY(frame), 1, NSHeight(frame)));
    }
  }
}

static void DrawTableHeader(NSXMLElement *object, NSRect frame, NSView *view)
{
  /* The header belongs to the table in the scroll view's clip view. */
  NSXMLElement *scroll = (NSXMLElement *)[object parent];
  NSXMLElement *table = nil;
  CGFloat      x = NSMinX(frame);

  for (NSXMLElement *clip in [scroll elementsForName:@"clipView"])
  {
    for (NSXMLNode *node in [PCInterfaceChild(clip, @"subviews") children])
    {
      if ([[node name] isEqualToString:@"tableView"] || [[node name] isEqualToString:@"outlineView"])
      {
        table = (NSXMLElement *)node;
      }
    }
  }
  for (NSXMLElement *column in ElementsOf(table, @"tableColumns", @"tableColumn"))
  {
    NSXMLElement      *header = PCInterfaceChild(column, @"headerCell");
    NSTableHeaderCell *cell = [[[NSTableHeaderCell alloc] initTextCell:Attribute(header, @"title") ?: @""] autorelease];
    CGFloat           width = [Attribute(column, @"width") doubleValue] + 3;

    ConfigureCell(cell, header);
    [cell drawWithFrame:NSMakeRect(x, NSMinY(frame), MIN(width, NSMaxX(frame) - x), NSHeight(frame))
                 inView:view];
    x += width;
    if (x >= NSMaxX(frame))
    {
      break;
    }
  }
  if (x < NSMaxX(frame))
  {
    NSTableHeaderCell *rest = [[[NSTableHeaderCell alloc] initTextCell:@""] autorelease];

    [rest drawWithFrame:NSMakeRect(x, NSMinY(frame), NSMaxX(frame) - x, NSHeight(frame)) inView:view];
  }
}

static void DrawTabView(NSXMLElement *object, NSRect frame, NSView *view)
{
  NSArray         *items = ElementsOf(object, @"tabViewItems", @"tabViewItem");
  NSSegmentedCell *tabs = [[[NSSegmentedCell alloc] init] autorelease];
  NSRect          body = frame;
  NSInteger       i;

  if ([Attribute(object, @"type") isEqualToString:@"noTabsNoBorder"])
  {
    return;
  }
  body.size.height -= 12;
  [[[NSColor controlShadowColor] colorWithAlphaComponent:0.12] set];
  [[NSBezierPath bezierPathWithRoundedRect:body xRadius:5 yRadius:5] fill];
  [[[NSColor controlShadowColor] colorWithAlphaComponent:0.5] set];
  [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(body, 0.5, 0.5) xRadius:5 yRadius:5] stroke];
  if ([items count] == 0 || [[Attribute(object, @"type") lowercaseString] hasPrefix:@"notabs"])
  {
    return;
  }
  [tabs setSegmentCount:[items count]];
  for (i = 0; i < (NSInteger)[items count]; i++)
  {
    [tabs setLabel:Attribute([items objectAtIndex:i], @"label") ?: @"" forSegment:i];
  }
  [tabs setSelected:YES forSegment:0];
  NSSize size = [tabs cellSize];
  [tabs drawWithFrame:NSMakeRect(floor(NSMidX(frame) - size.width / 2), NSMaxY(frame) - size.height,
                                 size.width, size.height)
               inView:view];
}

static void DrawCustomView(NSXMLElement *object, NSRect frame, NSView *view)
{
  NSString     *name = Attribute(object, @"customClass") ?: @"Custom View";
  CGFloat      pattern[2] = {3, 3};
  NSBezierPath *path = [NSBezierPath bezierPathWithRect:NSInsetRect(frame, 0.5, 0.5)];
  NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                              [NSFont systemFontOfSize:11], NSFontAttributeName,
                              [NSColor disabledControlTextColor], NSForegroundColorAttributeName, nil];
  NSSize       size = [name sizeWithAttributes:attributes];

  [path setLineDash:pattern count:2 phase:0];
  [[NSColor gridColor] set];
  [path stroke];
  if (NSHeight(frame) > size.height && NSWidth(frame) > size.width)
  {
    [name drawAtPoint:NSMakePoint(floor(NSMidX(frame) - size.width / 2), floor(NSMidY(frame) - size.height / 2))
       withAttributes:attributes];
  }
}

static void DrawBackground(NSXMLElement *object, NSRect frame, NSColor *fallback)
{
  NSColor *color = PCInterfaceColor(PCInterfaceChild(object, @"backgroundColor")) ?: fallback;

  if (color == nil || [Attribute(object, @"drawsBackground") isEqualToString:@"NO"])
  {
    return;
  }
  [color set];
  NSRectFill(frame);
}

BOOL PCInterfaceDrawObject(NSXMLElement *object, NSRect frame, NSView *view)
{
  NSString *name = [object name];

  if (IsYes(object, @"hidden"))
  {
    return NO;
  }
  if ([name isEqualToString:@"button"])
  {
    DrawButton(object, frame, view);
  }
  else if ([name isEqualToString:@"popUpButton"])
  {
    [PopUpCell(CellOf(object)) drawWithFrame:frame inView:view];
  }
  else if ([name isEqualToString:@"textField"])
  {
    DrawTextField(object, frame, view, [NSTextFieldCell class]);
  }
  else if ([name isEqualToString:@"secureTextField"])
  {
    DrawTextField(object, frame, view, [NSSecureTextFieldCell class]);
  }
  else if ([name isEqualToString:@"searchField"])
  {
    DrawTextField(object, frame, view, [NSSearchFieldCell class]);
  }
  else if ([name isEqualToString:@"comboBox"])
  {
    DrawTextField(object, frame, view, [NSComboBoxCell class]);
  }
  else if ([name isEqualToString:@"tokenField"])
  {
    DrawTextField(object, frame, view, [NSTokenFieldCell class]);
  }
  else if ([name isEqualToString:@"slider"])
  {
    DrawSlider(object, frame, view);
  }
  else if ([name isEqualToString:@"stepper"])
  {
    DrawStepper(object, frame, view);
  }
  else if ([name isEqualToString:@"imageView"])
  {
    DrawImageView(object, frame, view);
  }
  else if ([name isEqualToString:@"segmentedControl"])
  {
    DrawSegments(object, frame, view);
  }
  else if ([name isEqualToString:@"colorWell"])
  {
    DrawColorWell(object, frame, view);
  }
  else if ([name isEqualToString:@"progressIndicator"])
  {
    DrawProgress(object, frame, view);
  }
  else if ([name isEqualToString:@"levelIndicator"])
  {
    DrawLevelIndicator(object, frame, view);
  }
  else if ([name isEqualToString:@"matrix"])
  {
    DrawMatrix(object, frame, view);
  }
  else if ([name isEqualToString:@"box"])
  {
    DrawBox(object, frame, view);
    return YES;
  }
  else if ([name isEqualToString:@"scrollView"])
  {
    DrawScrollBorder(object, frame);
    return YES;
  }
  else if ([name isEqualToString:@"clipView"])
  {
    DrawBackground(object, frame, [NSColor controlBackgroundColor]);
    return YES;
  }
  else if ([name isEqualToString:@"scroller"])
  {
    DrawScroller(object, frame);
  }
  else if ([name isEqualToString:@"tableView"] || [name isEqualToString:@"outlineView"])
  {
    DrawTable(object, frame, view);
    return YES;
  }
  else if ([name isEqualToString:@"tableHeaderView"])
  {
    DrawTableHeader(object, frame, view);
  }
  else if ([name isEqualToString:@"textView"])
  {
    DrawBackground(object, frame, [NSColor textBackgroundColor]);
  }
  else if ([name isEqualToString:@"tabView"])
  {
    DrawTabView(object, frame, view);
    return YES;
  }
  else if ([name isEqualToString:@"customView"])
  {
    DrawCustomView(object, frame, view);
    return YES;
  }
  else if ([name isEqualToString:@"splitView"])
  {
    /* The dividers: where the subviews leave a gap. */
    [[NSColor gridColor] set];
    NSRectFill(frame);
    return YES;
  }
  else
  {
    /* Plain views, and objects this editor doesn't draw, show what is inside them. */
    return YES;
  }
  return NO;
}

BOOL PCInterfaceIsFlipped(NSXMLElement *object)
{
  /* As AppKit's isFlipped: the subviews' frames are from the top. */
  return [@[@"scrollView", @"clipView", @"tableView", @"outlineView", @"textView", @"splitView",
            @"collectionView", @"stackView", @"matrix"] containsObject:[object name]];
}

CGFloat PCInterfaceTitleBarHeight(void)
{
  return 28;
}

NSRect PCInterfaceDrawWindowFrame(NSXMLElement *window, NSRect content, NSView *view)
{
  NSXMLElement *mask = PCInterfaceChild(window, @"styleMask");
  BOOL         titled = mask == nil || IsYes(mask, @"titled");
  CGFloat      bar = titled ? PCInterfaceTitleBarHeight() : 0;
  NSRect       whole = NSMakeRect(NSMinX(content), NSMinY(content), NSWidth(content), NSHeight(content) + bar);
  NSRect       title = NSMakeRect(NSMinX(whole), NSMaxY(whole) - bar, NSWidth(whole), bar);
  NSColor      *background = PCInterfaceColor(PCInterfaceChild(window, @"backgroundColor"))
                             ?: [NSColor windowBackgroundColor];

  /* A shadow around the window, as on a desktop. */
  [[[NSColor shadowColor] colorWithAlphaComponent:0.25] set];
  [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(NSOffsetRect(whole, 0, -2), -2, -2)
                                   xRadius:8 yRadius:8] fill];
  [NSGraphicsContext saveGraphicsState];
  [[NSBezierPath bezierPathWithRoundedRect:whole xRadius:6 yRadius:6] addClip];
  [background set];
  NSRectFill(whole);
  if (titled)
  {
    NSWindowButton buttons[3] = {NSWindowCloseButton, NSWindowMiniaturizeButton, NSWindowZoomButton};
    BOOL           shown[3] = {IsYes(mask, @"closable"), IsYes(mask, @"miniaturizable"), IsYes(mask, @"resizable")};
    NSUInteger     style = NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask;
    CGFloat        x = NSMinX(title) + 8;
    NSUInteger     i;
    NSFont         *font = [NSFont titleBarFontOfSize:0];
    NSString       *text = Attribute(window, @"title") ?: @"Window";
    NSDictionary   *attributes = [NSDictionary dictionaryWithObjectsAndKeys:font, NSFontAttributeName,
                                  [NSColor windowFrameTextColor], NSForegroundColorAttributeName, nil];
    NSSize         size = [text sizeWithAttributes:attributes];

    [[[NSColor controlShadowColor] colorWithAlphaComponent:0.12] set];
    NSRectFill(title);
    [[NSColor gridColor] set];
    NSRectFill(NSMakeRect(NSMinX(title), NSMinY(title), NSWidth(title), 1));
    /* The theme's own window buttons, drawn by their cells. */
    for (i = 0; i < 3; i++)
    {
      NSButton *button = [NSWindow standardWindowButton:buttons[i] forStyleMask:style];
      NSSize   buttonSize = button ? [button frame].size : NSZeroSize;

      if (button == nil || buttonSize.width < 1)
      {
        continue;
      }
      [[button cell] setEnabled:shown[i]];
      [[button cell] drawWithFrame:NSMakeRect(x, floor(NSMidY(title) - buttonSize.height / 2),
                                              buttonSize.width, buttonSize.height)
                            inView:view];
      x += buttonSize.width + 6;
    }
    [text drawAtPoint:NSMakePoint(floor(NSMidX(title) - size.width / 2), floor(NSMidY(title) - size.height / 2))
       withAttributes:attributes];
  }
  [NSGraphicsContext restoreGraphicsState];
  [[NSColor gridColor] set];
  [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(whole, -0.5, -0.5) xRadius:6 yRadius:6] stroke];
  return whole;
}
