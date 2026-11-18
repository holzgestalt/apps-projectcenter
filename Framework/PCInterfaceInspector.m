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
 * The interface editor's inspector, laid out as Xcode's: Identity,
 * Attributes, Size and Connections panes. The Attributes pane has a section
 * for each class of the object ("Pop Up Button", "Button", "Control",
 * "View"), with the controls Xcode has for what the XIB holds. A constraint
 * shows its items, relation and numbers. Attributes no section covers are
 * listed under Other Attributes, so everything in the XIB stays editable.
 *
 * The panes are made anew for each selection and after each edit. Each
 * control has a PCInspectorBinding that says what in the XML it edits.
 */

#import "PCInterfaceEditor.h"
#import "PCInterfaceDocument.h"
#import "PCInterfaceRendering.h"
#include <math.h>

static NSString *Attribute(NSXMLElement *element, NSString *name)
{
  return [[element attributeForName:name] stringValue];
}

static NSXMLElement *FrameElement(NSXMLElement *element)
{
  for (NSXMLNode *child in [element children])
  {
    if ([child kind] == NSXMLElementKind && [[child name] isEqualToString:@"rect"]
        && [Attribute((NSXMLElement *)child, @"key") isEqualToString:@"frame"])
    {
      return (NSXMLElement *)child;
    }
  }
  return nil;
}

static NSXMLElement *TitleElement(NSXMLElement *element)
{
  if ([element attributeForName:@"title"])
  {
    return element;
  }
  for (NSXMLNode *child in [element children])
  {
    if ([child kind] == NSXMLElementKind && [[child name] hasSuffix:@"Cell"]
        && [(NSXMLElement *)child attributeForName:@"title"])
    {
      return (NSXMLElement *)child;
    }
  }
  return element;
}

// --- What the inspector shows of each kind of object

typedef enum
{
  PCText,           // text field; an empty one removes the attribute
  PCNumber,         // a number; the default removes the attribute
  PCCheck,          // a check box; options "Title" or "Title|on|off"
  PCPopUp,          // options "value:Title|value:Title"
  PCColor,          // a color well for a <color> element
  PCFont,           // the font of a <font> element, and its size
  PCImage,          // an image name, from the XIB's resources
  PCTitle,          // the object's title, also in a Gorm archive
  PCSelectedItem,   // the selected item of a pop up button
  PCButtonStyle,    // options "type/bezelStyle:Title"
  PCButtonType,     // the flags of a button's <behavior>
  PCTextBehavior,   // None, Selectable or Editable
  PCReadOnly
} PCPropertyKind;

typedef struct
{
  const char     *label;
  const char     *path;        // "." the object, "cell", "cell/font"; "a,b" the first that has it
  const char     *attribute;
  PCPropertyKind kind;
  const char     *options;
  const char     *defaultValue;
  const char     *only;        // element names it is for; NULL for all of the section's
} PCProperty;

typedef struct
{
  const char       *title;
  const char       *elements;  // " button popUpButton ", or "@control", "@view"
  const PCProperty *properties;
  NSUInteger       count;
} PCSection;

#define COUNT(array) (sizeof(array) / sizeof(*array))

/* Options several properties share. */
#define Alignments "left:Left|center:Center|right:Right|justified:Justified|natural:Natural"
#define Scalings "proportionallyDown:Proportionally Down|axesIndependently:Axes Independently" \
  "|none:None|proportionallyUpOrDown:Proportionally Up or Down"
#define States "off:Off|on:On|mixed:Mixed"

static const PCProperty PopUpProperties[] = {
  {"Type", "cell", "pullsDown", PCPopUp, "NO:Pop Up|YES:Pull Down", "NO", NULL},
  {"Arrow", "cell", "arrowPosition", PCPopUp, "noArrow:No Arrow|arrowAtCenter:Center|arrowAtBottom:Bottom",
   "arrowAtBottom", NULL},
  {"Menu Edge", "cell", "preferredEdge", PCPopUp, "minX:Left|minY:Top|maxX:Right|maxY:Bottom", "maxY", NULL},
  {"Selected Item", "cell", "selectedItem", PCSelectedItem, NULL, NULL, NULL},
  {"Items", "cell", "autoenablesItems", PCCheck, "Autoenables", "YES", NULL},
  {"", "cell", "altersStateOfSelectedItem", PCCheck, "Alters State", "YES", NULL},
};

static const PCProperty ButtonProperties[] = {
  {"Style", "cell", "type", PCButtonStyle,
   "push/rounded:Push|bevel/regularSquare:Bevel|square/shadowlessSquare:Square|smallSquare/smallSquare:Gradient"
   "|roundRect/roundedRect:Round Rect|recessed/recessed:Recessed|inline/inline:Inline"
   "|roundTextured/texturedRounded:Textured Rounded|square/texturedSquare:Textured Square"
   "|disclosure/roundedDisclosure:Disclosure|disclosureTriangle/disclosure:Disclosure Triangle"
   "|help/helpButton:Help|check/regularSquare:Checkbox|radio/regularSquare:Radio", NULL, "button"},
  {"Style", "cell", "type", PCButtonStyle,
   "push/rounded:Push|bevel/regularSquare:Bevel|square/shadowlessSquare:Square|smallSquare/smallSquare:Gradient"
   "|roundRect/roundedRect:Round Rect|recessed/recessed:Recessed"
   "|roundTextured/texturedRounded:Textured Rounded|square/texturedSquare:Textured Square", NULL, "popUpButton"},
  {"Type", "cell/behavior", NULL, PCButtonType, NULL, NULL, NULL},
  {"Visual", "cell", "borderStyle", PCCheck, "Bordered|border|", "", NULL},
  {"", "cell", "transparent", PCCheck, "Transparent", "NO", NULL},
  {"State", "cell", "state", PCPopUp, States, "off", NULL},
  {"", "cell", "allowsMixedState", PCCheck, "Allows Mixed State", "NO", NULL},
  {"Title", "cell", "title", PCTitle, NULL, NULL, "button"},
  {"Alternate", "cell", "alternateTitle", PCText, NULL, NULL, "button"},
  {"Alignment", "cell", "alignment", PCPopUp, Alignments, NULL, NULL},
  {"Font", "cell/font", NULL, PCFont, NULL, NULL, NULL},
  {"Image", "cell", "image", PCImage, NULL, NULL, NULL},
  {"Alternate", "cell", "alternateImage", PCImage, NULL, NULL, "button"},
  {"Position", "cell", "imagePosition", PCPopUp,
   "noImage:No Image|only:Image Only|left:Left|right:Right|leading:Leading|trailing:Trailing"
   "|above:Above|below:Below|overlaps:Overlaps", NULL, NULL},
  {"Scaling", "cell", "imageScaling", PCPopUp, Scalings, NULL, NULL},
  {"Key Equivalent", "cell/keyEquivalent", NULL, PCText, NULL, NULL, "button"},
};

static const PCProperty TextFieldProperties[] = {
  {"Title", "cell", "title", PCTitle, NULL, NULL, NULL},
  {"Placeholder", "cell", "placeholderString", PCText, NULL, NULL, NULL},
  {"Alignment", "cell", "alignment", PCPopUp, Alignments, NULL, NULL},
  {"Font", "cell/font", NULL, PCFont, NULL, NULL, NULL},
  {"Text Color", "cell/textColor", NULL, PCColor, NULL, NULL, NULL},
  {"Background", "cell/backgroundColor", NULL, PCColor, NULL, NULL, NULL},
  {"", "cell", "drawsBackground", PCCheck, "Draws Background", "NO", NULL},
  {"Border", "cell", "borderStyle", PCPopUp, ":None|border:Line|bezel:Bezel", "", NULL},
  {"Bezel Style", "cell", "bezelStyle", PCPopUp, "square:Square|round:Rounded", "square", NULL},
  {"Behavior", "cell", NULL, PCTextBehavior, NULL, NULL, NULL},
  {"Action", "cell", "sendsActionOnEndEditing", PCCheck, "Send On End Editing", "NO", NULL},
  {"Layout", "cell", "scrollable", PCCheck, "Scrollable", "NO", NULL},
  {"", "cell", "usesSingleLineMode", PCCheck, "Uses Single Line Mode", "NO", NULL},
};

static const PCProperty BoxProperties[] = {
  {"Title", ".", "title", PCTitle, NULL, NULL, NULL},
  {"Title Position", ".", "titlePosition", PCPopUp,
   "noTitle:None|aboveTop:Above Top|atTop:Top|belowTop:Below Top|aboveBottom:Above Bottom"
   "|atBottom:Bottom|belowBottom:Below Bottom", "atTop", NULL},
  {"Box Type", ".", "boxType", PCPopUp, "primary:Primary|secondary:Secondary|separator:Separator|custom:Custom",
   "primary", NULL},
  {"Border Type", ".", "borderType", PCPopUp, "none:None|line:Line|bezel:Bezel|groove:Groove", "bezel", NULL},
  {"Border Width", ".", "borderWidth", PCNumber, NULL, "1", NULL},
  {"Corner Radius", ".", "cornerRadius", PCNumber, NULL, "0", NULL},
  {"Border Color", "borderColor", NULL, PCColor, NULL, NULL, NULL},
  {"Fill Color", "fillColor", NULL, PCColor, NULL, NULL, NULL},
  {"", ".", "transparent", PCCheck, "Transparent", "NO", NULL},
  {"Font", "titleFont", NULL, PCFont, NULL, NULL, NULL},
};

static const PCProperty SliderProperties[] = {
  {"Type", "cell", "sliderType", PCPopUp, "linear:Linear|circular:Circular", "linear", NULL},
  {"Minimum", "cell", "minValue", PCNumber, NULL, "0", NULL},
  {"Maximum", "cell", "maxValue", PCNumber, NULL, NULL, NULL},
  {"Current", "cell", "doubleValue", PCNumber, NULL, "0", NULL},
  {"Tick Marks", "cell", "numberOfTickMarks", PCNumber, NULL, "0", NULL},
  {"Position", "cell", "tickMarkPosition", PCPopUp, "below:Below|above:Above|leading:Leading|trailing:Trailing",
   "below", NULL},
  {"", "cell", "allowsTickMarkValuesOnly", PCCheck, "Only Stop on Tick Marks", "NO", NULL},
};

static const PCProperty StepperProperties[] = {
  {"Minimum", "cell", "minValue", PCNumber, NULL, "0", NULL},
  {"Maximum", "cell", "maxValue", PCNumber, NULL, NULL, NULL},
  {"Current", "cell", "doubleValue", PCNumber, NULL, "0", NULL},
  {"Increment", "cell", "increment", PCNumber, NULL, "1", NULL},
  {"Behavior", "cell", "valueWraps", PCCheck, "Value Wraps", "NO", NULL},
  {"", "cell", "autorepeat", PCCheck, "Autorepeat", "YES", NULL},
};

static const PCProperty ImageViewProperties[] = {
  {"Image", "cell", "image", PCImage, NULL, NULL, NULL},
  {"Scaling", "cell", "imageScaling", PCPopUp, Scalings, "proportionallyDown", NULL},
  {"Alignment", "cell", "imageAlignment", PCPopUp,
   "center:Center|top:Top|topLeft:Top Left|topRight:Top Right|left:Left|bottom:Bottom"
   "|bottomLeft:Bottom Left|bottomRight:Bottom Right|right:Right", "center", NULL},
  {"Border", "cell", "imageFrameStyle", PCPopUp,
   "none:None|photo:Photo|grayBezel:Gray Bezel|groove:Groove|button:Button", "none", NULL},
  {"Behavior", ".", "editable", PCCheck, "Editable", "NO", NULL},
  {"", ".", "animates", PCCheck, "Animates", "NO", NULL},
};

static const PCProperty ProgressProperties[] = {
  {"Style", ".", "style", PCPopUp, "bar:Bar|spinning:Spinning", "bar", NULL},
  {"Behavior", ".", "indeterminate", PCCheck, "Indeterminate", "NO", NULL},
  {"", ".", "displayedWhenStopped", PCCheck, "Display When Stopped", "YES", NULL},
  {"Minimum", ".", "minValue", PCNumber, NULL, "0", NULL},
  {"Maximum", ".", "maxValue", PCNumber, NULL, "100", NULL},
  {"Current", ".", "doubleValue", PCNumber, NULL, "0", NULL},
};

static const PCProperty SegmentedProperties[] = {
  {"Style", "cell", "segmentStyle", PCPopUp,
   "automatic:Automatic|rounded:Rounded|texturedRounded:Textured Rounded|roundRect:Round Rect"
   "|texturedSquare:Textured Square|capsule:Capsule|smallSquare:Small Square|separated:Separated",
   "automatic", NULL},
  {"Mode", "cell", "trackingMode", PCPopUp, "selectOne:Select One|selectAny:Select Any|momentary:Momentary",
   "selectOne", NULL},
};

static const PCProperty ColorWellProperties[] = {
  {"Color", "color", NULL, PCColor, NULL, NULL, NULL},
  {"", ".", "bordered", PCCheck, "Bordered", "YES", NULL},
};

static const PCProperty ScrollViewProperties[] = {
  {"Border", ".", "borderType", PCPopUp, "none:None|line:Line|bezel:Bezel|groove:Groove", "bezel", NULL},
  {"Scrollers", ".", "hasHorizontalScroller", PCCheck, "Show Horizontal Scroller", "YES", NULL},
  {"", ".", "hasVerticalScroller", PCCheck, "Show Vertical Scroller", "YES", NULL},
  {"", ".", "autohidesScrollers", PCCheck, "Automatically Hide Scrollers", "NO", NULL},
  {"Scrolling", ".", "usesPredominantAxisScrolling", PCCheck, "Predominant Axis", "YES", NULL},
};

static const PCProperty TableViewProperties[] = {
  {"Content Mode", ".", "viewBased", PCPopUp, "NO:Cell Based|YES:View Based", "NO", NULL},
  {"Row Height", ".", "rowHeight", PCNumber, NULL, NULL, NULL},
  {"Highlight", ".", "selectionHighlightStyle", PCPopUp, "regular:Regular|sourceList:Source List|none:None",
   "regular", NULL},
  {"", ".", "alternatingRowBackgroundColors", PCCheck, "Alternating Rows", "NO", NULL},
  {"Selection", ".", "multipleSelection", PCCheck, "Multiple", "YES", NULL},
  {"", ".", "emptySelection", PCCheck, "Empty", "YES", NULL},
  {"", ".", "columnSelection", PCCheck, "Column", "NO", NULL},
  {"", ".", "typeSelect", PCCheck, "Type Select", "YES", NULL},
  {"Columns", ".", "columnReordering", PCCheck, "Reordering", "YES", NULL},
  {"", ".", "columnResizing", PCCheck, "Resizing", "YES", NULL},
  {"Column Sizing", ".", "columnAutoresizingStyle", PCPopUp,
   "none:None|uniform:Uniform|sequential:Sequential|reverseSequential:Reverse Sequential"
   "|lastColumnOnly:Last Column Only|firstColumnOnly:First Column Only", "uniform", NULL},
};

static const PCProperty TextViewProperties[] = {
  {"Behavior", ".", "editable", PCCheck, "Editable", "YES", NULL},
  {"", ".", "selectable", PCCheck, "Selectable", "YES", NULL},
  {"Allows", ".", "richText", PCCheck, "Rich Text", "YES", NULL},
  {"", ".", "importsGraphics", PCCheck, "Graphics", "YES", NULL},
  {"", ".", "allowsUndo", PCCheck, "Undo", "NO", NULL},
  {"", ".", "usesFontPanel", PCCheck, "Font Panel", "NO", NULL},
  {"", ".", "usesRuler", PCCheck, "Ruler", "NO", NULL},
  {"Find", ".", "findStyle", PCPopUp, ":None|panel:Panel|bar:Bar", "", NULL},
  {"Background", "backgroundColor", NULL, PCColor, NULL, NULL, NULL},
  {"Text Color", "textColor", NULL, PCColor, NULL, NULL, NULL},
};

static const PCProperty TabViewProperties[] = {
  {"Style", ".", "type", PCPopUp,
   "topTabsBezelBorder:Top|leftTabsBezelBorder:Left|bottomTabsBezelBorder:Bottom|rightTabsBezelBorder:Right"
   "|noTabsBezelBorder:Tabless|noTabsLineBorder:Tabless Line|noTabsNoBorder:Tabless No Border",
   "topTabsBezelBorder", NULL},
  {"Drawing", ".", "drawsBackground", PCCheck, "Draws Background", "YES", NULL},
  {"", ".", "allowsTruncatedLabels", PCCheck, "Truncates Labels", "YES", NULL},
};

static const PCProperty SplitViewProperties[] = {
  {"Arrangement", ".", "vertical", PCPopUp, "NO:Horizontal|YES:Vertical", "NO", NULL},
  {"Divider", ".", "dividerStyle", PCPopUp, "thick:Thick|thin:Thin|paneSplitter:Pane Splitter", "thick", NULL},
};

static const PCProperty WindowProperties[] = {
  {"Title", ".", "title", PCTitle, NULL, NULL, NULL},
  {"Autosave", ".", "frameAutosaveName", PCText, NULL, NULL, NULL},
  {"Controls", "styleMask", "closable", PCCheck, "Close", "NO", NULL},
  {"", "styleMask", "miniaturizable", PCCheck, "Minimize", "NO", NULL},
  {"", "styleMask", "resizable", PCCheck, "Resize", "NO", NULL},
  {"Appearance", "styleMask", "titled", PCCheck, "Title Bar", "NO", NULL},
  {"", "styleMask", "utility", PCCheck, "Utility", "NO", NULL},
  {"", "styleMask", "texturedBackground", PCCheck, "Textured", "NO", NULL},
  {"", "styleMask", "fullSizeContentView", PCCheck, "Full Size Content View", "NO", NULL},
  {"Behavior", ".", "visibleAtLaunch", PCCheck, "Visible At Launch", "YES", NULL},
  {"", ".", "releasedWhenClosed", PCCheck, "Release When Closed", "YES", NULL},
  {"", ".", "hidesOnDeactivate", PCCheck, "Hide On Deactivate", "NO", NULL},
  {"", ".", "restorable", PCCheck, "Restorable", "YES", NULL},
  {"Memory", ".", "oneShot", PCCheck, "One Shot", "YES", NULL},
  {"Animation", ".", "animationBehavior", PCPopUp,
   "default:Default|none:None|documentWindow:Document Window|utilityWindow:Utility Window"
   "|alertPanel:Alert Panel", "default", NULL},
  {"Tabbing Mode", ".", "tabbingMode", PCPopUp, ":Automatic|preferred:Preferred|disallowed:Disallowed", "", NULL},
  {"Background", "backgroundColor", NULL, PCColor, NULL, NULL, NULL},
};

static const PCProperty MenuItemProperties[] = {
  {"Title", ".", "title", PCTitle, NULL, NULL, NULL},
  {"Key Equivalent", ".", "keyEquivalent", PCText, NULL, NULL, NULL},
  {"State", ".", "state", PCPopUp, States, "off", NULL},
  {"Tag", ".", "tag", PCNumber, NULL, "0", NULL},
  {"Indentation", ".", "indentationLevel", PCNumber, NULL, "0", NULL},
  {"Behavior", ".", "enabled", PCCheck, "Enabled", "YES", NULL},
  {"", ".", "hidden", PCCheck, "Hidden", "NO", NULL},
  {"", ".", "isAlternate", PCCheck, "Alternate", "NO", NULL},
  {"Image", ".", "image", PCImage, NULL, NULL, NULL},
};

static const PCProperty MenuProperties[] = {
  {"Title", ".", "title", PCTitle, NULL, NULL, NULL},
  {"Items", ".", "autoenablesItems", PCCheck, "Auto Enables Items", "YES", NULL},
  {"System Menu", ".", "systemMenu", PCPopUp,
   ":None|apple:Apple|main:Main|services:Services|window:Window|help:Help|font:Font"
   "|recentDocuments:Open Recent", "", NULL},
};

static const PCProperty ControlProperties[] = {
  {"Line Break", "cell", "lineBreakMode", PCPopUp,
   "clipping:Clip|charWrapping:Character Wrap|wordWrapping:Word Wrap|truncatingHead:Truncate Head"
   "|truncatingTail:Truncate Tail|truncatingMiddle:Truncate Middle", NULL, NULL},
  {"", "cell", "truncatesLastVisibleLine", PCCheck, "Truncates Last Visible Line", "NO", NULL},
  {"State", "cell,.", "enabled", PCCheck, "Enabled", "YES", NULL},
  {"", "cell,.", "continuous", PCCheck, "Continuous", "NO", NULL},
  {"", "cell,.", "refusesFirstResponder", PCCheck, "Refuses First Responder", "NO", NULL},
  {"Tooltips", ".", "allowsExpansionToolTips", PCCheck, "Allows Expansion Tooltips", "NO", NULL},
  {"Control Size", "cell,.", "controlSize", PCPopUp, "regular:Regular|small:Small|mini:Mini|large:Large",
   "regular", NULL},
  {"Text Direction", "cell", "baseWritingDirection", PCPopUp,
   "natural:Natural|leftToRight:Left To Right|rightToLeft:Right To Left", "natural", NULL},
  {"Layout", ".", "userInterfaceLayoutDirection", PCPopUp, "leftToRight:Left To Right|rightToLeft:Right To Left",
   "leftToRight", NULL},
};

static const PCProperty ViewProperties[] = {
  {"Tag", ".,cell", "tag", PCNumber, NULL, "0", NULL},
  {"Focus Ring", ".", "focusRingType", PCPopUp, "default:Default|none:None|exterior:Exterior", "default", NULL},
  {"Drawing", ".", "hidden", PCCheck, "Hidden", "NO", NULL},
  {"", ".", "canDrawConcurrently", PCCheck, "Can Draw Concurrently", "NO", NULL},
  {"Autoresizing", ".", "autoresizesSubviews", PCCheck, "Autoresizes Subviews", "YES", NULL},
};

static const PCSection Sections[] = {
  {"Window", " window panel ", WindowProperties, COUNT(WindowProperties)},
  {"Menu", " menu ", MenuProperties, COUNT(MenuProperties)},
  {"Menu Item", " menuItem ", MenuItemProperties, COUNT(MenuItemProperties)},
  {"Pop Up Button", " popUpButton ", PopUpProperties, COUNT(PopUpProperties)},
  {"Button", " button popUpButton ", ButtonProperties, COUNT(ButtonProperties)},
  {"Text Field", " textField secureTextField searchField comboBox tokenField ", TextFieldProperties,
   COUNT(TextFieldProperties)},
  {"Slider", " slider ", SliderProperties, COUNT(SliderProperties)},
  {"Stepper", " stepper ", StepperProperties, COUNT(StepperProperties)},
  {"Image View", " imageView ", ImageViewProperties, COUNT(ImageViewProperties)},
  {"Progress Indicator", " progressIndicator ", ProgressProperties, COUNT(ProgressProperties)},
  {"Segmented Control", " segmentedControl ", SegmentedProperties, COUNT(SegmentedProperties)},
  {"Color Well", " colorWell ", ColorWellProperties, COUNT(ColorWellProperties)},
  {"Box", " box ", BoxProperties, COUNT(BoxProperties)},
  {"Scroll View", " scrollView ", ScrollViewProperties, COUNT(ScrollViewProperties)},
  {"Table View", " tableView outlineView ", TableViewProperties, COUNT(TableViewProperties)},
  {"Text View", " textView ", TextViewProperties, COUNT(TextViewProperties)},
  {"Tab View", " tabView ", TabViewProperties, COUNT(TabViewProperties)},
  {"Split View", " splitView ", SplitViewProperties, COUNT(SplitViewProperties)},
  {"Control", "@control", ControlProperties, COUNT(ControlProperties)},
  {"View", "@view", ViewProperties, COUNT(ViewProperties)},
};

/* The element a new child of a path is made as. */
static NSString *ElementNameForKey(NSString *key)
{
  NSDictionary *names = [NSDictionary dictionaryWithObjectsAndKeys:
                         @"font", @"font", @"font", @"titleFont",
                         @"color", @"textColor", @"color", @"backgroundColor", @"color", @"fillColor",
                         @"color", @"borderColor", @"color", @"color",
                         @"string", @"keyEquivalent", @"behavior", @"behavior",
                         @"windowStyleMask", @"styleMask", @"autoresizingMask", @"autoresizingMask", nil];

  return [names objectForKey:key];
}

/* "value:Title|value:Title" as values and titles. */
static void ParseOptions(const char *options, NSMutableArray *values, NSMutableArray *titles)
{
  NSArray *entries = [[NSString stringWithUTF8String:options ?: ""] componentsSeparatedByString:@"|"];

  for (NSString *entry in entries)
  {
    NSRange colon = [entry rangeOfString:@":" options:NSBackwardsSearch];

    if (colon.location == NSNotFound)
    {
      [values addObject:entry];
      [titles addObject:entry];
    }
    else
    {
      [values addObject:[entry substringToIndex:colon.location]];
      [titles addObject:[entry substringFromIndex:NSMaxRange(colon)]];
    }
  }
}

static NSString *String(const char *text)
{
  return text ? [NSString stringWithUTF8String:text] : nil;
}

/* "popUpButton" is NSPopUpButton, "customObject" NSObject. */
static NSString *DefaultClassOfObject(NSXMLElement *object)
{
  NSString *name = [object name];

  if ([name isEqualToString:@"customObject"])
  {
    return @"NSObject";
  }
  if ([name isEqualToString:@"customView"])
  {
    return @"NSView";
  }
  if ([name length] == 0)
  {
    return @"";
  }
  return [NSString stringWithFormat:@"NS%@%@", [[name substringToIndex:1] uppercaseString],
          [name substringFromIndex:1]];
}

// --- Bindings: what a control of the inspector edits

typedef enum
{
  PCBindProperty,      // a PCProperty
  PCBindFrame,         // the frame fields
  PCBindAutoresizing,  // a flag of the autoresizing mask
  PCBindConstraint,    // a control of the constraint form
  PCBindSelect,        // selects an object (the constraints of a view)
  PCBindRaw,           // an attribute under Other Attributes
  PCBindAddAttribute,  // name=value
  PCBindToggleOther,   // shows or hides Other Attributes
  PCBindFontSize
} PCBindingKind;

@interface PCInspectorBinding : NSObject
{
  @public
  PCBindingKind  kind;
  PCProperty     property;
  NSXMLElement   *object;    // the selection
  NSXMLElement   *element;   // the element to change, when it is known
  NSString       *attribute;
  NSArray        *values;
  NSDictionary   *row;       // of -attributesOfObject:, for PCBindRaw
}
@end

@implementation PCInspectorBinding
- (void)dealloc
{
  [object release];
  [element release];
  [attribute release];
  [values release];
  [row release];
  [super dealloc];
}
@end

// --- A form of labeled rows, top to bottom

@interface PCInspectorForm : NSView
{
  CGFloat        y;
}
- (void)reset;
- (void)addHeader:(NSString *)title;
- (void)addRow:(NSString *)label views:(NSArray *)views height:(CGFloat)height;
- (void)addNote:(NSString *)text;
- (void)finish;
@end

static const CGFloat LabelWidth = 92;

@implementation PCInspectorForm
- (BOOL)isFlipped
{
  return YES;
}
- (id)initWithFrame:(NSRect)frame
{
  if ((self = [super initWithFrame:frame]))
  {
    [self setAutoresizingMask:NSViewWidthSizable];
  }
  return self;
}
- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [super dealloc];
}
/* The form is as wide as the scroll view it is in. */
- (void)viewDidMoveToSuperview
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  if ([self superview])
  {
    [[self superview] setPostsFrameChangedNotifications:YES];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(superviewFrameDidChange:)
                                                 name:NSViewFrameDidChangeNotification
                                               object:[self superview]];
  }
}
- (void)superviewFrameDidChange:(NSNotification *)notification
{
  [self finish];
}
- (void)reset
{
  while ([[self subviews] count])
  {
    [[[self subviews] lastObject] removeFromSuperview];
  }
  y = 4;
}
- (void)addHeader:(NSString *)title
{
  NSTextField *label = [[[NSTextField alloc] initWithFrame:NSMakeRect(8, y + 8, NSWidth([self frame]) - 16, 16)]
                        autorelease];

  if (y > 4)
  {
    NSBox *separator = [[[NSBox alloc] initWithFrame:NSMakeRect(8, y + 2, NSWidth([self frame]) - 16, 1)] autorelease];
    [separator setBoxType:NSBoxSeparator];
    [separator setAutoresizingMask:NSViewWidthSizable];
    [self addSubview:separator];
  }
  [label setStringValue:title];
  [label setEditable:NO];
  [label setSelectable:NO];
  [label setBezeled:NO];
  [label setDrawsBackground:NO];
  [label setFont:[NSFont boldSystemFontOfSize:11]];
  [label setTextColor:[NSColor disabledControlTextColor]];
  [label setAutoresizingMask:NSViewWidthSizable];
  [self addSubview:label];
  y += 28;
}
- (void)addRow:(NSString *)label views:(NSArray *)views height:(CGFloat)height
{
  CGFloat x = LabelWidth + 8, right = NSWidth([self frame]) - 8;
  CGFloat fixed = 0, flexible = 0, gap = 4;

  if ([label length])
  {
    NSTextField *text = [[[NSTextField alloc] initWithFrame:NSMakeRect(4, y + floor((height - 15) / 2),
                                                                       LabelWidth, 15)] autorelease];

    [text setStringValue:label];
    [text setEditable:NO];
    [text setSelectable:NO];
    [text setBezeled:NO];
    [text setDrawsBackground:NO];
    [text setAlignment:NSRightTextAlignment];
    [text setFont:[NSFont systemFontOfSize:11]];
    [[text cell] setLineBreakMode:NSLineBreakByTruncatingTail];
    [self addSubview:text];
  }
  /* Views with a width keep it; the others share the rest. */
  for (NSView *view in views)
  {
    if (NSWidth([view frame]) > 0)
    {
      fixed += NSWidth([view frame]);
    }
    else
    {
      flexible++;
    }
  }
  fixed += gap * ([views count] - 1);
  CGFloat share = floor((right - x - fixed) / MAX(1, flexible));
  for (NSView *view in views)
  {
    BOOL    hasWidth = NSWidth([view frame]) > 0;
    CGFloat width = hasWidth ? NSWidth([view frame]) : share;

    [view setFrame:NSMakeRect(x, y, width, height)];
    if ([views count] == 1)
    {
      [view setAutoresizingMask:NSViewWidthSizable];
    }
    else if (hasWidth)
    {
      /* Fixed views keep their place relative to the flexible ones. */
      [view setAutoresizingMask:flexible ? NSViewMinXMargin | NSViewMaxXMargin : NSViewMinXMargin];
    }
    else
    {
      [view setAutoresizingMask:NSViewWidthSizable];
    }
    if ([view isKindOfClass:[NSControl class]])
    {
      [[(NSControl *)view cell] setControlSize:NSSmallControlSize];
      if (![view isKindOfClass:[NSColorWell class]])
      {
        [(NSControl *)view setFont:[NSFont systemFontOfSize:11]];
      }
    }
    [self addSubview:view];
    x += width + gap;
  }
  y += height + 5;
}
- (void)addNote:(NSString *)text
{
  NSTextField *note = [[[NSTextField alloc] initWithFrame:NSMakeRect(8, y, NSWidth([self frame]) - 16, 30)]
                       autorelease];

  [note setStringValue:text];
  [note setEditable:NO];
  [note setSelectable:NO];
  [note setBezeled:NO];
  [note setDrawsBackground:NO];
  [note setFont:[NSFont systemFontOfSize:11]];
  [note setTextColor:[NSColor disabledControlTextColor]];
  [[note cell] setWraps:YES];
  [note setAutoresizingMask:NSViewWidthSizable];
  [self addSubview:note];
  y += 34;
}
- (void)finish
{
  NSSize visible = [[self enclosingScrollView] contentSize];

  [self setFrameSize:NSMakeSize(visible.width, MAX(y + 8, visible.height))];
  [self setNeedsDisplay:YES];
}
@end

// --- The editor's inspector

/* What the inspector asks of the editor (PCInterfaceEditor.m). */
@interface PCInterfaceEditor (PCInterfaceInspectorEditing)
- (BOOL)canEditStructure;
- (NSDictionary *)snapshot;
- (void)registerUndo:(NSDictionary *)snapshot named:(NSString *)name;
- (void)didChangeStructure:(BOOL)structural;
- (void)gormSetTitle:(NSString *)title ofElement:(NSXMLElement *)element;
- (void)gormSetFrame:(NSRect)frame ofElement:(NSXMLElement *)element;
- (NSString *)titleOfConstraintItem:(NSXMLElement *)item ofConstraint:(NSXMLElement *)constraint;
- (void)updateConnections;
@end

@implementation PCInterfaceEditor (PCInterfaceInspector)

static NSScrollView *FormScrollView(NSRect frame)
{
  NSScrollView    *scroll = [[[NSScrollView alloc] initWithFrame:frame] autorelease];
  PCInspectorForm *form;

  [scroll setHasVerticalScroller:YES];
  [scroll setBorderType:NSNoBorder];
  [scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  form = [[[PCInspectorForm alloc] initWithFrame:NSMakeRect(0, 0, [scroll contentSize].width, 100)] autorelease];
  [scroll setDocumentView:form];
  return scroll;
}

static NSView *PaneView(NSView *content, NSRect frame)
{
  NSView *pane = [[[NSView alloc] initWithFrame:frame] autorelease];

  [pane setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [content setFrame:[pane bounds]];
  [pane addSubview:content];
  return pane;
}

static NSButton *InspectorButton(NSString *title, NSRect frame, id target, SEL action)
{
  NSButton *button = [[[NSButton alloc] initWithFrame:frame] autorelease];

  [button setTitle:title];
  [button setBezelStyle:NSRoundedBezelStyle];
  [button setTarget:target];
  [button setAction:action];
  return button;
}

/* A cell-based table in a scroll view, with a column for each identifier. */
static NSTableView *Table(NSView *superview, NSRect frame, NSArray *columns, NSArray *widths, id owner)
{
  NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:frame] autorelease];
  NSTableView  *table;
  NSUInteger   i;

  [scroll setHasVerticalScroller:YES];
  [scroll setBorderType:NSBezelBorder];
  [scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  table = [[[NSTableView alloc] initWithFrame:[[scroll contentView] bounds]] autorelease];
  for (i = 0; i < [columns count]; i++)
  {
    NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:[columns objectAtIndex:i]] autorelease];

    [[column headerCell] setStringValue:[columns objectAtIndex:i]];
    [column setWidth:[[widths objectAtIndex:i] doubleValue]];
    [[column dataCell] setFont:[NSFont systemFontOfSize:11]];
    [table addTableColumn:column];
  }
  [table setColumnAutoresizingStyle:NSTableViewLastColumnOnlyAutoresizingStyle];
  [table setRowHeight:17];
  [table setAllowsMultipleSelection:NO];
  [table setDataSource:owner];
  [table setDelegate:owner];
  [scroll setDocumentView:table];
  [superview addSubview:scroll];
  return table;
}

- (NSView *)inspectorWithFrame:(NSRect)frame
{
  NSView        *inspector = [[[NSView alloc] initWithFrame:frame] autorelease];
  NSArray       *names = @[@"Identity", @"Attributes", @"Size", @"Connections"];
  CGFloat       width = NSWidth(frame), height = NSHeight(frame) - 32;
  NSRect        paneFrame = NSMakeRect(0, 0, width, height);
  NSTabViewItem *item;
  NSView        *view;
  NSUInteger    i;

  [inspector setAutoresizingMask:NSViewHeightSizable | NSViewMinXMargin];
  _inspectorBindings = [NSMutableArray new];
  _inspectedAttributes = [NSMutableSet new];

  /* The pane selector, as the icons above Xcode's inspector. */
  _inspectorTabs = [[[NSSegmentedControl alloc] initWithFrame:NSMakeRect(6, height + 4, width - 12, 24)]
                    autorelease];
  [_inspectorTabs setSegmentCount:[names count]];
  [[_inspectorTabs cell] setControlSize:NSSmallControlSize];
  [_inspectorTabs setFont:[NSFont systemFontOfSize:11]];
  for (i = 0; i < [names count]; i++)
  {
    [_inspectorTabs setLabel:[names objectAtIndex:i] forSegment:i];
    [_inspectorTabs setWidth:floor((width - 16) / [names count]) forSegment:i];
  }
  [_inspectorTabs setSelectedSegment:1];
  [_inspectorTabs setTarget:self];
  [_inspectorTabs setAction:@selector(showInspectorPane:)];
  [_inspectorTabs setAutoresizingMask:NSViewMinYMargin];
  [inspector addSubview:_inspectorTabs];

  _inspectorPanes = [[[NSTabView alloc] initWithFrame:paneFrame] autorelease];
  [_inspectorPanes setTabViewType:NSNoTabsNoBorder];
  [_inspectorPanes setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [inspector addSubview:_inspectorPanes];

  _identityScroll = FormScrollView(paneFrame);
  _attributesScroll = FormScrollView(paneFrame);
  _sizeScroll = FormScrollView(paneFrame);
  NSScrollView *scrolls[3] = {_identityScroll, _attributesScroll, _sizeScroll};
  for (i = 0; i < 3; i++)
  {
    item = [[[NSTabViewItem alloc] initWithIdentifier:[names objectAtIndex:i]] autorelease];
    [item setLabel:[names objectAtIndex:i]];
    [item setView:PaneView(scrolls[i], paneFrame)];
    [_inspectorPanes addTabViewItem:item];
  }

  /* Connections: those of the object; new outlets and actions. */
  view = [[[NSView alloc] initWithFrame:paneFrame] autorelease];
  [view setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  _connectionTable = Table(view, NSMakeRect(6, 120, width - 12, height - 126), @[@"Kind", @"Name", @"Object"],
                           @[@50, @100, @100], self);
  _removeConnectionButton = InspectorButton(@"Remove", NSMakeRect(6, 88, 90, 26), self,
                                            @selector(removeConnection:));
  [view addSubview:_removeConnectionButton];
  _connectionKindPopUp = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(6, 54, 90, 26) pullsDown:NO] autorelease];
  [_connectionKindPopUp addItemsWithTitles:@[@"Outlet", @"Action"]];
  [view addSubview:_connectionKindPopUp];
  _connectionNameField = [[[NSTextField alloc] initWithFrame:NSMakeRect(102, 56, width - 108, 22)] autorelease];
  [[_connectionNameField cell] setPlaceholderString:@"property or action:"];
  [_connectionNameField setAutoresizingMask:NSViewWidthSizable];
  [view addSubview:_connectionNameField];
  _connectionTargetPopUp = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(6, 20, width - 102, 26)
                                                        pullsDown:NO] autorelease];
  [_connectionTargetPopUp setAutoresizingMask:NSViewWidthSizable];
  [view addSubview:_connectionTargetPopUp];
  _addConnectionButton = InspectorButton(@"Connect", NSMakeRect(width - 92, 20, 86, 26), self,
                                         @selector(addConnection:));
  [_addConnectionButton setAutoresizingMask:NSViewMinXMargin];
  [view addSubview:_addConnectionButton];
  item = [[[NSTabViewItem alloc] initWithIdentifier:@"Connections"] autorelease];
  [item setLabel:@"Connections"];
  [item setView:view];
  [_inspectorPanes addTabViewItem:item];
  [_inspectorPanes selectTabViewItemAtIndex:1];
  return inspector;
}

- (void)showInspectorPane:(id)sender
{
  [_inspectorPanes selectTabViewItemAtIndex:[_inspectorTabs selectedSegment]];
}

// --- Finding what a property edits

/* The element at a path below the object: ".", "cell", "cell/font". A
 * missing element is made when create is set and it can be. */
- (NSXMLElement *)elementAtPath:(NSString *)path ofObject:(NSXMLElement *)object create:(BOOL)create
{
  NSXMLElement *element = object;

  if ([path length] == 0 || [path isEqualToString:@"."])
  {
    return object;
  }
  for (NSString *key in [path componentsSeparatedByString:@"/"])
  {
    NSXMLElement *child = [_model childOfElement:element withKey:key
                                   creatingNamed:create ? ElementNameForKey(key) : nil];

    if (child == nil)
    {
      return nil;
    }
    element = child;
  }
  return element;
}

/* For "a,b": the first element that has the attribute, else the first there is. */
- (NSXMLElement *)elementOfProperty:(const PCProperty *)property
                           ofObject:(NSXMLElement *)object
                             create:(BOOL)create
{
  NSArray      *paths = [String(property->path) componentsSeparatedByString:@","];
  NSString     *attribute = String(property->attribute);
  NSXMLElement *first = nil;

  for (NSString *path in paths)
  {
    NSXMLElement *element = [self elementAtPath:path ofObject:object create:NO];

    if (element && attribute && [element attributeForName:attribute])
    {
      return element;
    }
    if (first == nil)
    {
      first = element;
    }
  }
  if (first == nil && create)
  {
    first = [self elementAtPath:[paths objectAtIndex:0] ofObject:object create:YES];
  }
  return first;
}

- (BOOL)objectIsControl:(NSXMLElement *)object
{
  return FrameElement(object) && PCInterfaceChild(object, @"cell") != nil;
}

- (BOOL)section:(const PCSection *)section isForObject:(NSXMLElement *)object
{
  NSString *elements = String(section->elements);

  if ([elements isEqualToString:@"@control"])
  {
    return [self objectIsControl:object];
  }
  if ([elements isEqualToString:@"@view"])
  {
    return FrameElement(object) != nil && ![[object name] isEqualToString:@"window"];
  }
  return [elements rangeOfString:[NSString stringWithFormat:@" %@ ", [object name]]].location != NSNotFound;
}

- (PCInspectorBinding *)bind:(PCBindingKind)kind control:(NSControl *)control
{
  PCInspectorBinding *binding = [[[PCInspectorBinding alloc] init] autorelease];

  binding->kind = kind;
  binding->object = [_selected retain];
  [control setTag:[_inspectorBindings count]];
  [control setTarget:self];
  [control setAction:@selector(inspectorChanged:)];
  [_inspectorBindings addObject:binding];
  return binding;
}

- (void)markInspected:(NSXMLElement *)element attribute:(NSString *)attribute
{
  if (element)
  {
    [_inspectedAttributes addObject:[NSString stringWithFormat:@"%p %@", (void *)element, attribute ?: @""]];
  }
}

- (BOOL)isInspected:(NSXMLElement *)element attribute:(NSString *)attribute
{
  return [_inspectedAttributes containsObject:[NSString stringWithFormat:@"%p %@", (void *)element,
                                               attribute ?: @""]];
}

// --- Controls for properties

static NSTextField *Field(NSString *value, NSString *placeholder)
{
  NSTextField *field = [[[NSTextField alloc] initWithFrame:NSZeroRect] autorelease];

  [field setStringValue:value ?: @""];
  if (placeholder)
  {
    [[field cell] setPlaceholderString:placeholder];
  }
  [[field cell] setScrollable:YES];
  /* As in Xcode, leaving a field applies it. */
  [[field cell] setSendsActionOnEndEditing:YES];
  return field;
}

static NSTextField *ReadOnlyText(NSString *value)
{
  NSTextField *field = Field(value, nil);

  [field setEditable:NO];
  [field setSelectable:YES];
  [field setBezeled:NO];
  [field setDrawsBackground:NO];
  return field;
}

static NSButton *CheckBox(NSString *title, BOOL on)
{
  NSButton *button = [[[NSButton alloc] initWithFrame:NSZeroRect] autorelease];

  [button setButtonType:NSSwitchButton];
  [button setTitle:title];
  [button setState:on ? NSOnState : NSOffState];
  return button;
}

/* A pop up with the titles; a value that isn't one of them is added as it is. */
static NSPopUpButton *PopUp(NSArray *titles, NSArray *values, NSString *value, NSMutableArray *shownValues)
{
  NSPopUpButton *popup = [[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO] autorelease];
  NSUInteger    index = [values indexOfObject:value ?: @""];

  for (NSString *title in titles)
  {
    [[popup menu] addItemWithTitle:title action:NULL keyEquivalent:@""];
  }
  [shownValues addObjectsFromArray:values];
  if (index == NSNotFound && value)
  {
    [[popup menu] addItemWithTitle:value action:NULL keyEquivalent:@""];
    [shownValues addObject:value];
    index = [shownValues count] - 1;
  }
  if (index != NSNotFound)
  {
    [popup selectItemAtIndex:index];
  }
  return popup;
}

static const char *ButtonTypeFlags[] = {"pushIn", "lightByBackground", "lightByGray", "lightByContents",
                                        "changeContents", "changeBackground", "changeGray"};
/* The flags of each button type, as NSButtonCell sets them. */
static NSArray *ButtonTypes(void)
{
  return @[@[@"Momentary Push In", @"pushIn lightByBackground lightByGray"],
           @[@"Momentary Light", @"lightByBackground lightByGray"],
           @[@"Momentary Change", @"lightByContents"],
           @[@"Push On Push Off", @"pushIn lightByBackground lightByGray changeBackground changeGray"],
           @[@"On Off", @"lightByBackground lightByGray changeBackground changeGray"],
           @[@"Toggle", @"pushIn lightByContents changeContents"],
           @[@"Switch", @"lightByContents changeContents"]];
}

static NSString *ButtonTypeFlagsOf(NSXMLElement *behavior)
{
  NSMutableArray *flags = [NSMutableArray array];
  NSUInteger     i;

  for (i = 0; i < COUNT(ButtonTypeFlags); i++)
  {
    if ([Attribute(behavior, String(ButtonTypeFlags[i])) isEqualToString:@"YES"])
    {
      [flags addObject:String(ButtonTypeFlags[i])];
    }
  }
  return [flags componentsJoinedByString:@" "];
}

- (NSArray *)imageNames
{
  NSMutableArray *names = [NSMutableArray array];
  NSXMLElement   *resources = [[[[_model XMLDocument] rootElement] elementsForName:@"resources"] lastObject];

  for (NSXMLElement *image in [resources elementsForName:@"image"])
  {
    if (Attribute(image, @"name"))
    {
      [names addObject:Attribute(image, @"name")];
    }
  }
  return names;
}

- (void)addProperty:(const PCProperty *)property toForm:(PCInspectorForm *)form
{
  NSXMLElement       *element = [self elementOfProperty:property ofObject:_selected create:NO];
  NSString           *attribute = String(property->attribute);
  NSString           *value = attribute ? Attribute(element, attribute) : [element stringValue];
  NSString           *label = String(property->label);
  NSMutableArray     *values = [NSMutableArray array], *titles = [NSMutableArray array];
  BOOL               editable = [self canEditStructure];
  NSControl          *control = nil;
  PCInspectorBinding *binding;

  if (property->only && [[String(property->only) componentsSeparatedByString:@" "]
                         indexOfObject:[_selected name]] == NSNotFound)
  {
    return;
  }
  /* A cell's attributes need the cell; other elements are made on a change. */
  if (element == nil && [String(property->path) hasPrefix:@"cell"]
      && PCInterfaceChild(_selected, @"cell") == nil)
  {
    return;
  }
  ParseOptions(property->options, values, titles);
  switch (property->kind)
  {
    case PCText:
    case PCNumber:
      control = Field(value, property->defaultValue ? String(property->defaultValue) : nil);
      break;
    case PCCheck:
    {
      NSString *on = [values count] > 1 ? [values objectAtIndex:1] : @"YES";
      NSString *current = value ?: String(property->defaultValue) ?: @"NO";

      control = CheckBox([titles objectAtIndex:0], [on isEqualToString:@"YES"] ? [current isEqualToString:@"YES"]
                                                                              : [value length] > 0);
      break;
    }
    case PCPopUp:
    {
      NSMutableArray *shown = [NSMutableArray array];

      control = PopUp(titles, values, value ?: String(property->defaultValue), shown);
      [values setArray:shown];
      break;
    }
    case PCColor:
    {
      NSColorWell *well = [[[NSColorWell alloc] initWithFrame:NSMakeRect(0, 0, 64, 0)] autorelease];
      NSColor     *color = PCInterfaceColor(element);

      [well setColor:color ?: [NSColor clearColor]];
      control = well;
      if (Attribute(element, @"name") || element == nil)
      {
        /* A system color: its name next to the well, as Xcode shows it. */
        NSTextField *name = ReadOnlyText(element ? Attribute(element, @"name") : @"Default");

        binding = [self bind:PCBindProperty control:control];
        binding->property = *property;
        binding->element = [element retain];
        [control setEnabled:editable];
        [form addRow:label views:@[name, control] height:22];
        [self markInspected:element attribute:nil];
        return;
      }
      break;
    }
    case PCFont:
    {
      NSArray        *metaFonts = @[@"system", @"systemBold", @"smallSystem", @"smallSystemBold", @"miniSystem",
                                    @"label", @"message", @"menu", @"toolTip", @"userFixed"];
      NSArray        *metaTitles = @[@"System", @"System Bold", @"System Small", @"System Small Bold",
                                     @"System Mini", @"Label", @"Message", @"Menu", @"Tool Tip",
                                     @"User Fixed Pitch"];
      NSMutableArray *shown = [NSMutableArray array];
      NSString       *current = Attribute(element, @"metaFont") ?: Attribute(element, @"name");
      NSTextField    *size;
      NSStepper      *stepper;
      PCInspectorBinding *sizeBinding;

      control = PopUp(metaTitles, metaFonts, element ? current : nil, shown);
      [values setArray:shown];
      if (element == nil)
      {
        [(NSPopUpButton *)control addItemWithTitle:@"Default"];
        [(NSPopUpButton *)control selectItemAtIndex:[(NSPopUpButton *)control numberOfItems] - 1];
      }
      size = Field(Attribute(element, @"size"), element
                   ? [NSString stringWithFormat:@"%g", [PCInterfaceFont(element) pointSize]] : @"");
      [size setFrame:NSMakeRect(0, 0, 40, 0)];
      stepper = [[[NSStepper alloc] initWithFrame:NSMakeRect(0, 0, 15, 0)] autorelease];
      [stepper setMinValue:1];
      [stepper setMaxValue:512];
      [stepper setDoubleValue:element ? [PCInterfaceFont(element) pointSize] : 13];
      binding = [self bind:PCBindProperty control:control];
      binding->property = *property;
      binding->element = [element retain];
      binding->values = [values copy];
      for (NSControl *sizeControl in @[size, stepper])
      {
        sizeBinding = [self bind:PCBindFontSize control:sizeControl];
        sizeBinding->property = *property;
        sizeBinding->element = [element retain];
        [sizeControl setEnabled:editable && element != nil];
      }
      [control setEnabled:editable];
      [form addRow:label views:@[control, size, stepper] height:22];
      [self markInspected:element attribute:nil];
      return;
    }
    case PCImage:
    {
      NSComboBox *combo = [[[NSComboBox alloc] initWithFrame:NSZeroRect] autorelease];

      [combo addItemsWithObjectValues:[self imageNames]];
      [combo setStringValue:value ?: @""];
      [[combo cell] setPlaceholderString:[label isEqualToString:@"Alternate"] ? @"Alternate Image" : @"Image"];
      control = combo;
      break;
    }
    case PCTitle:
    {
      NSXMLElement *titled = TitleElement(_selected);

      element = titled;
      attribute = @"title";
      control = Field(Attribute(titled, @"title"), @"Title");
      editable = _editable && [titled attributeForName:@"title"] != nil;
      break;
    }
    case PCSelectedItem:
    {
      NSPopUpButton *popup = [[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO] autorelease];
      NSXMLElement  *menu = PCInterfaceChild(element, @"menu");

      for (NSXMLElement *item in [[[menu elementsForName:@"items"] lastObject] elementsForName:@"menuItem"])
      {
        [[popup menu] addItemWithTitle:Attribute(item, @"title") ?: @"" action:NULL keyEquivalent:@""];
        [values addObject:Attribute(item, @"id") ?: @""];
        if ([Attribute(item, @"id") isEqualToString:value])
        {
          [popup selectItemAtIndex:[popup numberOfItems] - 1];
        }
      }
      [[popup menu] addItemWithTitle:@"None" action:NULL keyEquivalent:@""];
      [values addObject:@""];
      if (value == nil)
      {
        [popup selectItemAtIndex:[popup numberOfItems] - 1];
      }
      control = popup;
      break;
    }
    case PCButtonStyle:
    {
      NSString       *type = Attribute(element, @"type"), *bezel = Attribute(element, @"bezelStyle");
      NSMutableArray *shown = [NSMutableArray array];
      NSString       *selected = nil;

      for (NSString *pair in values)
      {
        if ([pair isEqualToString:[NSString stringWithFormat:@"%@/%@", type, bezel]])
        {
          selected = pair;
        }
      }
      for (NSString *pair in values)
      {
        if (selected == nil && [[[pair componentsSeparatedByString:@"/"] objectAtIndex:0] isEqualToString:type])
        {
          selected = pair;
        }
      }
      control = PopUp(titles, values, selected ?: [NSString stringWithFormat:@"%@/%@", type, bezel], shown);
      [values setArray:shown];
      [self markInspected:element attribute:@"bezelStyle"];
      break;
    }
    case PCButtonType:
    {
      NSString       *flags = ButtonTypeFlagsOf(element);
      NSMutableArray *shown = [NSMutableArray array];
      NSUInteger     i;

      for (NSArray *type in ButtonTypes())
      {
        [titles addObject:[type objectAtIndex:0]];
        [values addObject:[type objectAtIndex:1]];
      }
      [titles removeObjectAtIndex:0];
      [values removeObjectAtIndex:0];
      control = PopUp(titles, values, element ? flags : nil, shown);
      [values setArray:shown];
      for (i = 0; i < COUNT(ButtonTypeFlags); i++)
      {
        [self markInspected:element attribute:String(ButtonTypeFlags[i])];
      }
      break;
    }
    case PCTextBehavior:
    {
      BOOL           editableText = [Attribute(element, @"editable") isEqualToString:@"YES"];
      BOOL           selectable = [Attribute(element, @"selectable") isEqualToString:@"YES"];
      NSMutableArray *shown = [NSMutableArray array];

      [values setArray:@[@"none", @"selectable", @"editable"]];
      control = PopUp(@[@"None", @"Selectable", @"Editable"], values,
                      editableText ? @"editable" : selectable ? @"selectable" : @"none", shown);
      [self markInspected:element attribute:@"editable"];
      [self markInspected:element attribute:@"selectable"];
      break;
    }
    case PCReadOnly:
      control = ReadOnlyText(value);
      editable = NO;
      break;
  }
  binding = [self bind:PCBindProperty control:control];
  binding->property = *property;
  binding->element = [element retain];
  binding->attribute = [attribute copy];
  binding->values = [values copy];
  [control setEnabled:editable];
  [self markInspected:element attribute:attribute];
  [form addRow:label views:@[control] height:property->kind == PCCheck ? 18 : 22];
}

// --- The panes

- (void)fillIdentityForm:(PCInspectorForm *)form
{
  NSXMLElement *object = _selected;
  NSXMLElement *runtime = PCInterfaceChild(object, @"userDefinedRuntimeAttributes");
  PCProperty   classProperty = {"Class", ".", "customClass", PCText, NULL, NULL, NULL};
  PCProperty   moduleProperty = {"Module", ".", "customModule", PCText, NULL, "None", NULL};
  PCProperty   labelProperty = {"Label", ".", "userLabel", PCText, NULL, "Xcode Specific Label", NULL};
  PCProperty   identifierProperty = {"Identifier", ".", "identifier", PCText, NULL, "Automatic", NULL};
  PCProperty   toolTipProperty = {"Tool Tip", ".", "toolTip", PCText, NULL, NULL, NULL};
  PCProperty   idProperty = {"Object ID", ".", "id", PCReadOnly, NULL, NULL, NULL};

  if ([[object name] isEqualToString:@"constraint"])
  {
    [form addHeader:@"Constraint"];
    [self addProperty:&identifierProperty toForm:form];
    [self addProperty:&idProperty toForm:form];
    return;
  }
  [form addHeader:@"Custom Class"];
  [self addProperty:&classProperty toForm:form];
  [[(NSTextField *)[[form subviews] lastObject] cell] setPlaceholderString:DefaultClassOfObject(object)];
  [self addProperty:&moduleProperty toForm:form];
  if (FrameElement(object) || [[object name] isEqualToString:@"window"])
  {
    [form addHeader:@"Identity"];
    [self addProperty:&identifierProperty toForm:form];
  }
  [form addHeader:@"Document"];
  [self addProperty:&labelProperty toForm:form];
  [self addProperty:&idProperty toForm:form];
  if (FrameElement(object) || [[object name] isEqualToString:@"menuItem"])
  {
    [form addHeader:@"Tool Tip"];
    [self addProperty:&toolTipProperty toForm:form];
  }
  if (runtime)
  {
    [form addHeader:@"User Defined Runtime Attributes"];
    for (NSXMLElement *attribute in [runtime elementsForName:@"userDefinedRuntimeAttribute"])
    {
      NSString *value = Attribute(attribute, @"value");

      if (value == nil)
      {
        /* A value of another type is an element, such as <color key="value">. */
        for (NSXMLNode *child in [attribute children])
        {
          if ([child kind] == NSXMLElementKind)
          {
            value = [child name];
          }
        }
      }

      [form addRow:Attribute(attribute, @"keyPath") ?: @""
             views:@[ReadOnlyText([NSString stringWithFormat:@"%@ %@", Attribute(attribute, @"type") ?: @"",
                                   value ?: @""])]
            height:18];
    }
  }
}

/* The constraint form, as Xcode's Size inspector shows a constraint. */
- (NSPopUpButton *)constraintItemPopUp:(BOOL)second ofConstraint:(NSXMLElement *)constraint
{
  NSPopUpButton  *popup = [[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:YES] autorelease];
  NSXMLElement   *item = second ? [_model secondItemOfConstraint:constraint] : [_model firstItemOfConstraint:constraint];
  NSString       *attribute = Attribute(constraint, second ? @"secondAttribute" : @"firstAttribute")
                              ?: Attribute(constraint, @"firstAttribute");
  NSString       *name = item ? [self titleOfConstraintItem:item ofConstraint:constraint] : @"None";
  NSMenu         *menu = [popup menu];
  NSMenuItem     *menuItem;

  /* The title of a pull-down is its first item. */
  [popup addItemWithTitle:item ? [NSString stringWithFormat:@"%@.%@", name,
                                  [PCInterfaceDocument titleOfConstraintAttribute:attribute ?: @""]] : @"None"];
  if (item)
  {
    for (NSString *candidate in [PCInterfaceDocument constraintAttributes])
    {
      menuItem = [menu addItemWithTitle:[PCInterfaceDocument titleOfConstraintAttribute:candidate]
                                 action:NULL keyEquivalent:@""];
      [menuItem setRepresentedObject:@[@"attribute", candidate]];
      [menuItem setState:[candidate isEqualToString:attribute] ? NSOnState : NSOffState];
    }
    [menu addItem:[NSMenuItem separatorItem]];
  }
  for (NSXMLElement *candidate in _constraintItems)
  {
    menuItem = [menu addItemWithTitle:[self titleOfConstraintItem:candidate ofConstraint:constraint]
                               action:NULL keyEquivalent:@""];
    [menuItem setRepresentedObject:@[@"item", candidate]];
    [menuItem setState:candidate == item ? NSOnState : NSOffState];
  }
  if (second)
  {
    menuItem = [menu addItemWithTitle:@"None" action:NULL keyEquivalent:@""];
    [menuItem setRepresentedObject:@[@"item", [NSNull null]]];
    [menuItem setState:item == nil ? NSOnState : NSOffState];
  }
  if ([_model secondItemOfConstraint:constraint])
  {
    [menu addItem:[NSMenuItem separatorItem]];
    menuItem = [menu addItemWithTitle:@"Reverse First And Second Item" action:NULL keyEquivalent:@""];
    [menuItem setRepresentedObject:@[@"reverse"]];
  }
  return popup;
}

- (void)fillConstraintForm:(PCInspectorForm *)form
{
  NSXMLElement   *constraint = _selected;
  NSString       *relation = Attribute(constraint, @"relation");
  BOOL           editable = [self canEditStructure];
  BOOL           hasSecond = [_model secondItemOfConstraint:constraint] != nil;
  NSPopUpButton  *popup;
  NSTextField    *field;
  NSComboBox     *combo;
  NSButton       *check;
  NSArray        *names = @[@"firstAttribute", @"relation", @"constant", @"priority", @"multiplier",
                            @"secondItem", @"secondAttribute", @"firstItem", @"symbolic", @"placeholder",
                            @"identifier"];

  ASSIGN(_constraintItems, [_model candidateItemsForConstraint:constraint]);
  for (NSString *name in names)
  {
    [self markInspected:constraint attribute:name];
  }
  [form addHeader:[_model kindOfConstraint:constraint]];

  popup = [self constraintItemPopUp:NO ofConstraint:constraint];
  [self bind:PCBindConstraint control:popup]->attribute = [@"firstItem" copy];
  [popup setEnabled:editable];
  [form addRow:@"First Item" views:@[popup] height:22];

  popup = PopUp(@[@"Equal", @"Less Than or Equal", @"Greater Than or Equal"],
                @[@"", @"lessThanOrEqual", @"greaterThanOrEqual"], relation ?: @"", [NSMutableArray array]);
  [self bind:PCBindConstraint control:popup]->attribute = [@"relation" copy];
  [popup setEnabled:editable];
  [form addRow:@"Relation" views:@[popup] height:22];

  popup = [self constraintItemPopUp:YES ofConstraint:constraint];
  [self bind:PCBindConstraint control:popup]->attribute = [@"secondItem" copy];
  [popup setEnabled:editable];
  [form addRow:@"Second Item" views:@[popup] height:22];

  /* A symbolic constant is the standard spacing. */
  combo = [[[NSComboBox alloc] initWithFrame:NSZeroRect] autorelease];
  [combo addItemsWithObjectValues:@[@"Standard", @"0", @"8", @"20"]];
  [combo setStringValue:[Attribute(constraint, @"symbolic") isEqualToString:@"YES"] ? @"Standard"
                        : Attribute(constraint, @"constant") ?: @"0"];
  [self bind:PCBindConstraint control:combo]->attribute = [@"constant" copy];
  [combo setEnabled:editable];
  [form addRow:@"Constant" views:@[combo] height:22];

  combo = [[[NSComboBox alloc] initWithFrame:NSZeroRect] autorelease];
  [combo addItemsWithObjectValues:@[@"Required (1000)", @"High (750)", @"Low (250)", @"Fitting Size (50)"]];
  [combo setStringValue:Attribute(constraint, @"priority") ?: @"1000"];
  [self bind:PCBindConstraint control:combo]->attribute = [@"priority" copy];
  [combo setEnabled:editable];
  [form addRow:@"Priority" views:@[combo] height:22];

  field = Field(Attribute(constraint, @"multiplier") ?: @"1", nil);
  [self bind:PCBindConstraint control:field]->attribute = [@"multiplier" copy];
  [field setEnabled:editable && hasSecond];
  [form addRow:@"Multiplier" views:@[field] height:22];

  [form addHeader:@""];
  field = Field(Attribute(constraint, @"identifier"), @"Identifier");
  [self bind:PCBindConstraint control:field]->attribute = [@"identifier" copy];
  [field setEnabled:editable];
  [form addRow:@"Identifier" views:@[field] height:22];

  check = CheckBox(@"Remove at build time", [Attribute(constraint, @"placeholder") isEqualToString:@"YES"]);
  [self bind:PCBindConstraint control:check]->attribute = [@"placeholder" copy];
  [check setEnabled:editable];
  [form addRow:@"Placeholder" views:@[check] height:18];
}

- (void)fillAttributesForm:(PCInspectorForm *)form
{
  NSUInteger i, j;
  NSButton   *disclosure;
  NSArray    *rows;
  NSUInteger shown = 0;

  if ([[_selected name] isEqualToString:@"constraint"])
  {
    [self fillConstraintForm:form];
    return;
  }
  for (i = 0; i < COUNT(Sections); i++)
  {
    if (![self section:&Sections[i] isForObject:_selected])
    {
      continue;
    }
    [form addHeader:String(Sections[i].title)];
    for (j = 0; j < Sections[i].count; j++)
    {
      [self addProperty:&Sections[i].properties[j] toForm:form];
    }
  }

  /* What no section shows, as attribute and value. */
  rows = [_model attributesOfObject:_selected];
  for (NSDictionary *row in rows)
  {
    if (![self isInspected:[row objectForKey:@"Element"] attribute:[row objectForKey:@"Name"]])
    {
      shown++;
    }
  }
  disclosure = [[[NSButton alloc] initWithFrame:NSZeroRect] autorelease];
  [disclosure setBezelStyle:NSRoundedBezelStyle];
  [disclosure setTitle:[NSString stringWithFormat:_showsOtherAttributes ? @"Hide (%lu)" : @"Show (%lu)",
                        (unsigned long)shown]];
  [disclosure setState:_showsOtherAttributes ? NSOnState : NSOffState];
  [self bind:PCBindToggleOther control:disclosure];
  [form addHeader:@"Other Attributes"];
  [form addRow:@"" views:@[disclosure] height:22];
  if (!_showsOtherAttributes)
  {
    return;
  }
  for (NSDictionary *row in rows)
  {
    NSTextField        *field;
    PCInspectorBinding *binding;

    if ([self isInspected:[row objectForKey:@"Element"] attribute:[row objectForKey:@"Name"]])
    {
      continue;
    }
    field = Field([row objectForKey:@"Value"], nil);
    binding = [self bind:PCBindRaw control:field];
    binding->row = [row retain];
    [field setEnabled:[self canEditStructure] && [[row objectForKey:@"Editable"] boolValue]];
    [field setToolTip:[row objectForKey:@"Label"]];
    [form addRow:[row objectForKey:@"Label"] views:@[field] height:22];
  }
  if ([self canEditStructure])
  {
    NSTextField *field = Field(@"", @"name=value");

    [self bind:PCBindAddAttribute control:field];
    [form addRow:@"Add" views:@[field] height:22];
  }
}

- (void)fillSizeForm:(PCInspectorForm *)form
{
  NSXMLElement *object = _selected;
  NSXMLElement *frame = FrameElement(object);
  NSArray      *keys = @[@"x", @"y", @"width", @"height"];
  NSArray      *names = @[@"X", @"Y", @"Width", @"Height"];
  NSUInteger   i;

  for (i = 0; i < 4; i++)
  {
    _frameFields[i] = nil;
  }
  if ([[object name] isEqualToString:@"constraint"])
  {
    [self fillConstraintForm:form];
    return;
  }
  if ([[object name] isEqualToString:@"window"])
  {
    NSXMLElement *content = PCInterfaceChild(object, @"contentRect");
    PCProperty   properties[] = {
      {"X", "contentRect", "x", PCNumber, NULL, NULL, NULL},
      {"Y", "contentRect", "y", PCNumber, NULL, NULL, NULL},
      {"Width", "contentRect", "width", PCNumber, NULL, NULL, NULL},
      {"Height", "contentRect", "height", PCNumber, NULL, NULL, NULL},
      {"Minimum Width", "minSize", "width", PCNumber, NULL, NULL, NULL},
      {"Minimum Height", "minSize", "height", PCNumber, NULL, NULL, NULL},
      {"Maximum Width", "maxSize", "width", PCNumber, NULL, NULL, NULL},
      {"Maximum Height", "maxSize", "height", PCNumber, NULL, NULL, NULL},
    };

    [form addHeader:@"Content Rect"];
    for (i = 0; i < COUNT(properties); i++)
    {
      if (i == 4)
      {
        [form addHeader:@"Content Size Limits"];
      }
      [self addProperty:&properties[i] toForm:form];
    }
    if (content == nil)
    {
      [form addNote:@"The window has no content rect in the XIB."];
    }
    return;
  }
  if (frame == nil)
  {
    [form addNote:@"This object has no size: only views and windows have one."];
    return;
  }

  /* The frame, two fields to a row as in Xcode. */
  [form addHeader:@"View"];
  for (i = 0; i < 4; i += 2)
  {
    NSMutableArray *views = [NSMutableArray array];
    NSUInteger     k;

    for (k = i; k < i + 2; k++)
    {
      NSTextField *field = Field(Attribute(frame, [keys objectAtIndex:k]), nil);

      if (k % 2)
      {
        NSTextField *label = ReadOnlyText([names objectAtIndex:k]);

        [label setFrame:NSMakeRect(0, 0, 44, 0)];
        [label setAlignment:NSRightTextAlignment];
        [views addObject:label];
      }
      [self bind:PCBindFrame control:field];
      [field setEnabled:_editable && [object attributeForName:@"key"] == nil];
      _frameFields[k] = field;
      [views addObject:field];
      [self markInspected:frame attribute:[keys objectAtIndex:k]];
    }
    [form addRow:[names objectAtIndex:i] views:views height:22];
  }

  /* Constraints or the autoresizing mask lay the view out. */
  BOOL         autoresizes = ![Attribute(object, @"translatesAutoresizingMaskIntoConstraints") isEqualToString:@"NO"];
  PCProperty   layout = {"Layout", ".", "translatesAutoresizingMaskIntoConstraints", PCPopUp,
                         "YES:Autoresizing Mask|NO:Constraints", "YES", NULL};

  [form addHeader:@"Layout"];
  [self addProperty:&layout toForm:form];
  if (autoresizes)
  {
    NSXMLElement *mask = PCInterfaceChild(object, @"autoresizingMask");
    NSArray      *flags = @[@[@"flexibleMinX", @"Left"], @[@"widthSizable", @"Width"], @[@"flexibleMaxX", @"Right"],
                            @[@"flexibleMaxY", @"Top"], @[@"heightSizable", @"Height"], @[@"flexibleMinY", @"Bottom"]];

    for (i = 0; i < 6; i += 3)
    {
      NSMutableArray *views = [NSMutableArray array];
      NSUInteger     k;

      for (k = i; k < i + 3; k++)
      {
        NSArray  *flag = [flags objectAtIndex:k];
        NSButton *check = CheckBox([flag objectAtIndex:1],
                                   [Attribute(mask, [flag objectAtIndex:0]) isEqualToString:@"YES"]);
        PCInspectorBinding *binding = [self bind:PCBindAutoresizing control:check];

        binding->attribute = [[flag objectAtIndex:0] copy];
        [check setEnabled:[self canEditStructure]];
        [views addObject:check];
        [self markInspected:mask attribute:[flag objectAtIndex:0]];
      }
      [form addRow:i == 0 ? @"Horizontal" : @"Vertical" views:views height:18];
    }
  }

  PCProperty priorities[] = {
    {"Horizontal", ".", "horizontalHuggingPriority", PCNumber, NULL, "250", NULL},
    {"Vertical", ".", "verticalHuggingPriority", PCNumber, NULL, "250", NULL},
    {"Horizontal", ".", "horizontalCompressionResistancePriority", PCNumber, NULL, "750", NULL},
    {"Vertical", ".", "verticalCompressionResistancePriority", PCNumber, NULL, "750", NULL},
  };
  [form addHeader:@"Content Hugging Priority"];
  [self addProperty:&priorities[0] toForm:form];
  [self addProperty:&priorities[1] toForm:form];
  [form addHeader:@"Content Compression Resistance Priority"];
  [self addProperty:&priorities[2] toForm:form];
  [self addProperty:&priorities[3] toForm:form];

  /* The constraints of the view; a click selects one, as in Xcode. */
  NSArray *constraints = [_model constraintsOfObject:object];
  if ([constraints count])
  {
    [form addHeader:@"Constraints"];
    for (NSXMLElement *constraint in constraints)
    {
      NSButton           *button = [[[NSButton alloc] initWithFrame:NSZeroRect] autorelease];
      PCInspectorBinding *binding;

      [button setTitle:[_model descriptionOfConstraint:constraint]];
      [button setBezelStyle:NSRecessedBezelStyle];
      [button setAlignment:NSLeftTextAlignment];
      [[button cell] setLineBreakMode:NSLineBreakByTruncatingTail];
      binding = [self bind:PCBindSelect control:button];
      binding->element = [constraint retain];
      [form addRow:@"" views:@[button] height:20];
    }
  }
}

- (void)updateFrameFields
{
  NSXMLElement *frame = FrameElement(_selected);
  NSArray      *keys = @[@"x", @"y", @"width", @"height"];
  NSUInteger   i;

  for (i = 0; i < 4; i++)
  {
    [_frameFields[i] setStringValue:Attribute(frame, [keys objectAtIndex:i]) ?: @""];
  }
}

/* Set while the panes are made anew: a field that ends its editing then
 * belongs to the panes being replaced. */
static BOOL Rebuilding = NO;

- (void)updateInspector
{
  NSScrollView    *scrolls[3] = {_identityScroll, _attributesScroll, _sizeScroll};
  NSPoint         positions[3];
  BOOL            same = _selected && [Attribute(_selected, @"id") isEqualToString:_inspectedIdentifier];
  NSResponder     *responder = [[_component window] firstResponder];
  NSUInteger      i;

  if (_inspectorPanes == nil || Rebuilding)
  {
    return;
  }
  Rebuilding = YES;
  /* The panes are made anew, so a field being edited ends its editing. */
  if ([responder isKindOfClass:[NSView class]] && [(NSView *)responder isDescendantOf:_inspectorPanes])
  {
    [[_component window] makeFirstResponder:nil];
  }
  for (i = 0; i < 3; i++)
  {
    positions[i] = [[scrolls[i] contentView] bounds].origin;
  }
  ASSIGN(_inspectedIdentifier, Attribute(_selected, @"id"));
  [_inspectorBindings removeAllObjects];
  [_inspectedAttributes removeAllObjects];
  for (i = 0; i < 3; i++)
  {
    PCInspectorForm *form = [scrolls[i] documentView];

    [form reset];
    [form setFrameSize:NSMakeSize([scrolls[i] contentSize].width, NSHeight([form frame]))];
  }
  if (_selected)
  {
    [self fillIdentityForm:[_identityScroll documentView]];
    [self fillSizeForm:[_sizeScroll documentView]];
    [self fillAttributesForm:[_attributesScroll documentView]];
  }
  else
  {
    [[_attributesScroll documentView] addNote:@"No Selection"];
  }
  for (i = 0; i < 3; i++)
  {
    [[scrolls[i] documentView] finish];
    [[scrolls[i] contentView] scrollToPoint:same ? positions[i] : NSZeroPoint];
    [scrolls[i] reflectScrolledClipView:[scrolls[i] contentView]];
  }
  Rebuilding = NO;
  [self updateConnections];
}

// --- Changes made in the inspector

/* Ends an edit: undoable when the XIB changed, else the inspector shows
 * what the XIB has. */
- (void)finishInspectorEdit:(NSDictionary *)before named:(NSString *)name
{
  if ([[_model data] isEqual:[before objectForKey:@"XIB"]]
      && (_gorm == nil || [[before objectForKey:@"Gorm"] isEqual:[(id)_gorm data]]))
  {
    [self updateInspector];
    return;
  }
  [self registerUndo:before named:name];
  [self didChangeStructure:NO];
}

static BOOL IsNumber(NSString *text)
{
  NSScanner *scanner = [NSScanner scannerWithString:text];
  double    number;

  return [scanner scanDouble:&number] && [scanner isAtEnd] && isfinite(number);
}

- (void)changeProperty:(PCInspectorBinding *)binding control:(id)control
{
  const PCProperty *property = &binding->property;
  NSString         *attribute = binding->attribute;
  NSString         *defaultValue = String(property->defaultValue);
  NSString         *name = [NSString stringWithFormat:@"Change %@", String(property->label)];
  NSDictionary     *before = [self snapshot];
  NSXMLElement     *element;
  NSString         *value = nil;

  if ([name isEqualToString:@"Change "])
  {
    name = @"Change Attribute";
  }
  if (property->kind == PCTitle)
  {
    NSXMLElement *titled = binding->element;

    if (!_editable || [titled attributeForName:@"title"] == nil
        || [Attribute(titled, @"title") isEqualToString:[control stringValue]])
    {
      return;
    }
    [_model setValue:[control stringValue] ofAttribute:@"title" ofElement:titled];
    if ([[control stringValue] length] == 0)
    {
      /* An empty title stays an attribute, as titles are. */
      [_model addAttribute:@"title" withValue:@"" toElement:titled];
    }
    if (_gorm)
    {
      [self gormSetTitle:[control stringValue] ofElement:titled];
    }
    [self finishInspectorEdit:before named:@"Change Title"];
    return;
  }
  if (![self canEditStructure])
  {
    return;
  }
  element = [self elementOfProperty:property ofObject:binding->object create:YES];
  if (element == nil)
  {
    NSBeep();
    return;
  }
  switch (property->kind)
  {
    case PCText:
    case PCImage:
      value = [control stringValue];
      break;
    case PCNumber:
      value = [[control stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
      if ([value length] && !IsNumber(value))
      {
        NSBeep();
        [self updateInspector];
        return;
      }
      break;
    case PCCheck:
    {
      NSMutableArray *values = [NSMutableArray array], *titles = [NSMutableArray array];

      ParseOptions(property->options, values, titles);
      if ([values count] > 1)
      {
        value = [control state] == NSOnState ? [values objectAtIndex:1]
                : [values count] > 2 ? [values objectAtIndex:2] : @"";
        if ([control state] == NSOnState && [Attribute(element, attribute) length])
        {
          value = Attribute(element, attribute);  // "borderAndBezel" stays
        }
      }
      else
      {
        value = [control state] == NSOnState ? @"YES" : @"NO";
        defaultValue = defaultValue ?: @"NO";
      }
      break;
    }
    case PCPopUp:
    case PCSelectedItem:
      value = [binding->values objectAtIndex:[control indexOfSelectedItem]];
      break;
    case PCColor:
    {
      NSColor *color = [[control color] colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
      CGFloat red, green, blue, alpha;

      if (color == nil)
      {
        return;
      }
      [color getRed:&red green:&green blue:&blue alpha:&alpha];
      for (NSString *old in @[@"white", @"name", @"catalog", @"customColorSpace", @"colorSpace"])
      {
        [_model setValue:@"" ofAttribute:old ofElement:element];
      }
      [_model setValue:[NSString stringWithFormat:@"%g", red] ofAttribute:@"red" ofElement:element];
      [_model setValue:[NSString stringWithFormat:@"%g", green] ofAttribute:@"green" ofElement:element];
      [_model setValue:[NSString stringWithFormat:@"%g", blue] ofAttribute:@"blue" ofElement:element];
      [_model setValue:[NSString stringWithFormat:@"%g", alpha] ofAttribute:@"alpha" ofElement:element];
      [_model setValue:@"calibratedRGB" ofAttribute:@"colorSpace" ofElement:element];
      [self finishInspectorEdit:before named:name];
      return;
    }
    case PCFont:
    {
      NSInteger index = [control indexOfSelectedItem];

      if (index < 0 || index >= (NSInteger)[binding->values count])
      {
        return;
      }
      for (NSString *old in @[@"name", @"family"])
      {
        [_model setValue:@"" ofAttribute:old ofElement:element];
      }
      [_model setValue:[binding->values objectAtIndex:index] ofAttribute:@"metaFont" ofElement:element];
      [self finishInspectorEdit:before named:@"Change Font"];
      return;
    }
    case PCButtonStyle:
    {
      NSArray *pair = [[binding->values objectAtIndex:[control indexOfSelectedItem]]
                       componentsSeparatedByString:@"/"];

      [_model setValue:[pair objectAtIndex:0] ofAttribute:@"type" ofElement:element];
      if ([pair count] > 1)
      {
        [_model setValue:[pair objectAtIndex:1] ofAttribute:@"bezelStyle" ofElement:element];
      }
      [self finishInspectorEdit:before named:@"Change Style"];
      return;
    }
    case PCButtonType:
    {
      NSArray    *flags = [[binding->values objectAtIndex:[control indexOfSelectedItem]]
                           componentsSeparatedByString:@" "];
      NSUInteger i;

      for (i = 0; i < COUNT(ButtonTypeFlags); i++)
      {
        NSString *flag = String(ButtonTypeFlags[i]);

        [_model setValue:[flags containsObject:flag] ? @"YES" : @"" ofAttribute:flag ofElement:element];
      }
      [self finishInspectorEdit:before named:@"Change Type"];
      return;
    }
    case PCTextBehavior:
    {
      NSString *behavior = [binding->values objectAtIndex:[control indexOfSelectedItem]];

      [_model setValue:[behavior isEqualToString:@"none"] ? @"" : @"YES" ofAttribute:@"selectable"
             ofElement:element];
      [_model setValue:[behavior isEqualToString:@"editable"] ? @"YES" : @"" ofAttribute:@"editable"
             ofElement:element];
      [self finishInspectorEdit:before named:@"Change Behavior"];
      return;
    }
    case PCTitle:
    case PCReadOnly:
      return;
  }
  /* As Xcode, the default is left out of the XIB. */
  if (defaultValue && [value isEqualToString:defaultValue])
  {
    value = @"";
  }
  if (property->kind == PCSelectedItem)
  {
    /* The selected item is the one with its state on. */
    for (NSXMLElement *item in [[[PCInterfaceChild(element, @"menu") elementsForName:@"items"] lastObject]
                                elementsForName:@"menuItem"])
    {
      [_model setValue:[Attribute(item, @"id") isEqualToString:value] ? @"on" : @"" ofAttribute:@"state"
             ofElement:item];
    }
  }
  [_model setValue:value ofAttribute:attribute ofElement:element];
  [self finishInspectorEdit:before named:name];
}

- (void)changeFontSize:(PCInspectorBinding *)binding control:(id)control
{
  NSDictionary *before = [self snapshot];
  NSString     *size = [control isKindOfClass:[NSStepper class]]
                       ? [NSString stringWithFormat:@"%g", [control doubleValue]] : [control stringValue];

  if (![self canEditStructure] || binding->element == nil || ([size length] && !IsNumber(size)))
  {
    NSBeep();
    [self updateInspector];
    return;
  }
  [_model setValue:size ofAttribute:@"size" ofElement:binding->element];
  [self finishInspectorEdit:before named:@"Change Font Size"];
}

- (void)changeFrame
{
  NSXMLElement *frame = FrameElement(_selected);
  NSArray      *keys = @[@"x", @"y", @"width", @"height"];
  NSDictionary *before = [self snapshot];
  double       values[4];
  NSUInteger   i;

  if (!_editable || frame == nil)
  {
    return;
  }
  for (i = 0; i < 4; i++)
  {
    NSString *text = [_frameFields[i] stringValue];

    if (!IsNumber(text) || (i >= 2 && [text doubleValue] < 0))
    {
      NSBeep();
      [self updateFrameFields];
      return;
    }
    values[i] = [text doubleValue];
  }
  for (i = 0; i < 4; i++)
  {
    if ([Attribute(frame, [keys objectAtIndex:i]) doubleValue] != values[i])
    {
      [_model addAttribute:[keys objectAtIndex:i] withValue:[NSString stringWithFormat:@"%.15g", values[i]]
                 toElement:frame];
    }
  }
  if (_gorm)
  {
    [self gormSetFrame:NSMakeRect(values[0], values[1], values[2], values[3]) ofElement:_selected];
  }
  [self finishInspectorEdit:before named:@"Change Frame"];
}

- (void)changeAutoresizing:(PCInspectorBinding *)binding control:(id)control
{
  NSDictionary *before = [self snapshot];
  NSXMLElement *mask;

  if (![self canEditStructure])
  {
    return;
  }
  mask = [_model childOfElement:binding->object withKey:@"autoresizingMask" creatingNamed:@"autoresizingMask"];
  [_model setValue:[control state] == NSOnState ? @"YES" : @"" ofAttribute:binding->attribute ofElement:mask];
  [self finishInspectorEdit:before named:@"Change Autoresizing"];
}

/* "Required (1000)" is 1000. */
static NSString *PriorityNumber(NSString *text)
{
  NSRange open = [text rangeOfString:@"("], close = [text rangeOfString:@")"];

  if (open.location != NSNotFound && close.location != NSNotFound && close.location > open.location)
  {
    return [text substringWithRange:NSMakeRange(NSMaxRange(open), close.location - NSMaxRange(open))];
  }
  return [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

- (void)changeConstraint:(PCInspectorBinding *)binding control:(id)control
{
  NSXMLElement *constraint = binding->object;
  NSString     *which = binding->attribute;
  NSDictionary *before = [self snapshot];

  if (![self canEditStructure] || ![[constraint name] isEqualToString:@"constraint"])
  {
    return;
  }
  if ([which isEqualToString:@"firstItem"] || [which isEqualToString:@"secondItem"])
  {
    BOOL         second = [which isEqualToString:@"secondItem"];
    NSArray      *choice = [[control selectedItem] representedObject];
    NSXMLElement *first = [_model firstItemOfConstraint:constraint];
    NSXMLElement *other = [_model secondItemOfConstraint:constraint];
    NSString     *firstAttribute = Attribute(constraint, @"firstAttribute");
    NSString     *secondAttribute = Attribute(constraint, @"secondAttribute") ?: firstAttribute;

    if ([choice count] == 0)
    {
      return;
    }
    if ([[choice objectAtIndex:0] isEqualToString:@"reverse"])
    {
      [_model setFirstItem:other attribute:secondAttribute ofConstraint:constraint];
      [_model setSecondItem:first attribute:firstAttribute ofConstraint:constraint];
    }
    else if ([[choice objectAtIndex:0] isEqualToString:@"attribute"])
    {
      if (second)
      {
        [_model setSecondItem:other attribute:[choice objectAtIndex:1] ofConstraint:constraint];
      }
      else
      {
        [_model setFirstItem:first attribute:[choice objectAtIndex:1] ofConstraint:constraint];
      }
    }
    else
    {
      id item = [choice objectAtIndex:1];

      if (second)
      {
        [_model setSecondItem:item == [NSNull null] ? nil : item attribute:secondAttribute ofConstraint:constraint];
      }
      else
      {
        [_model setFirstItem:item attribute:firstAttribute ofConstraint:constraint];
      }
    }
  }
  else if ([which isEqualToString:@"relation"])
  {
    NSArray *relations = @[@"", @"lessThanOrEqual", @"greaterThanOrEqual"];

    [_model setValue:[relations objectAtIndex:[control indexOfSelectedItem]] ofAttribute:@"relation"
           ofElement:constraint];
  }
  else if ([which isEqualToString:@"constant"])
  {
    NSString *text = [[control stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

    /* The standard spacing is Xcode's to set: it stays as it is. */
    if ([text length] == 0 || [text isEqualToString:@"Standard"])
    {
      [self updateInspector];
      return;
    }
    if (!IsNumber(text))
    {
      NSBeep();
      [self updateInspector];
      return;
    }
    if ([Attribute(constraint, @"symbolic") isEqualToString:@"YES"]
        || ![(Attribute(constraint, @"constant") ?: @"0") isEqualToString:text])
    {
      [_model setNumber:text ofAttribute:@"constant" ofConstraint:constraint];
    }
  }
  else if ([which isEqualToString:@"priority"] || [which isEqualToString:@"multiplier"])
  {
    NSString *text = [which isEqualToString:@"priority"] ? PriorityNumber([control stringValue])
                     : [[control stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSString *current = Attribute(constraint, which) ?: ([which isEqualToString:@"priority"] ? @"1000" : @"1");

    /* A multiplier can be a ratio like 4:3. */
    if (!IsNumber(text) && !([which isEqualToString:@"multiplier"] && [text rangeOfString:@":"].location != NSNotFound))
    {
      NSBeep();
      [self updateInspector];
      return;
    }
    if (![current isEqualToString:text])
    {
      [_model setNumber:text ofAttribute:which ofConstraint:constraint];
    }
  }
  else if ([which isEqualToString:@"identifier"])
  {
    [_model setValue:[control stringValue] ofAttribute:@"identifier" ofElement:constraint];
  }
  else if ([which isEqualToString:@"placeholder"])
  {
    [_model setValue:[control state] == NSOnState ? @"YES" : @"" ofAttribute:@"placeholder" ofElement:constraint];
  }
  [self finishInspectorEdit:before named:@"Change Constraint"];
}

- (void)changeRawAttribute:(PCInspectorBinding *)binding control:(id)control
{
  NSDictionary *row = binding->row;
  NSDictionary *before = [self snapshot];

  if (![self canEditStructure] || [[row objectForKey:@"Value"] isEqual:[control stringValue]])
  {
    return;
  }
  [_model setValue:[control stringValue] ofAttribute:[row objectForKey:@"Name"]
         ofElement:[row objectForKey:@"Element"]];
  [self finishInspectorEdit:before named:@"Change Attribute"];
}

/* name=value adds an attribute to the object. */
- (void)addRawAttribute:(id)control
{
  NSString     *text = [control stringValue];
  NSRange      equals = [text rangeOfString:@"="];
  NSString     *name = [(equals.location == NSNotFound ? text : [text substringToIndex:equals.location])
                        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
  NSDictionary *before = [self snapshot];

  if (![self canEditStructure] || [name length] == 0)
  {
    return;
  }
  [_model addAttribute:name
             withValue:equals.location == NSNotFound ? @"" : [text substringFromIndex:NSMaxRange(equals)]
             toElement:_selected];
  [self finishInspectorEdit:before named:@"Add Attribute"];
}

- (void)inspectorChanged:(id)sender
{
  NSInteger          index = [sender tag];
  PCInspectorBinding *binding;

  if (Rebuilding || index < 0 || index >= (NSInteger)[_inspectorBindings count])
  {
    return;
  }
  binding = [[[_inspectorBindings objectAtIndex:index] retain] autorelease];
  /* A change can come for a selection the panes no longer show. */
  if (binding->object != _selected)
  {
    return;
  }
  switch (binding->kind)
  {
    case PCBindProperty:
      [self changeProperty:binding control:sender];
      break;
    case PCBindFontSize:
      [self changeFontSize:binding control:sender];
      break;
    case PCBindFrame:
      [self changeFrame];
      break;
    case PCBindAutoresizing:
      [self changeAutoresizing:binding control:sender];
      break;
    case PCBindConstraint:
      [self changeConstraint:binding control:sender];
      break;
    case PCBindSelect:
      [self selectObject:binding->element];
      break;
    case PCBindRaw:
      [self changeRawAttribute:binding control:sender];
      break;
    case PCBindAddAttribute:
      [self addRawAttribute:sender];
      break;
    case PCBindToggleOther:
      _showsOtherAttributes = !_showsOtherAttributes;
      [self updateInspector];
      break;
  }
}

@end
