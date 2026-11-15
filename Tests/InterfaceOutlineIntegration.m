#import <AppKit/AppKit.h>
#import "Framework/PCInterfaceEditor.h"
#include <gtk/gtk.h>
extern GtkWindow *GTK4NativeHostForWindow(NSWindow *window);

static void Check(BOOL condition, NSString *message)
{ if (!condition) { NSLog(@"FAIL: %@",message); exit(1); } }

static void PumpEvents(void)
{
  NSDate *until = [NSDate dateWithTimeIntervalSinceNow:0.2];
  while ([until timeIntervalSinceNow] > 0)
    {
      NSEvent *event = [NSApp nextEventMatchingMask:NSAnyEventMask
        untilDate:[NSDate dateWithTimeIntervalSinceNow:0.02] inMode:NSDefaultRunLoopMode dequeue:YES];
      if (event) [NSApp sendEvent:event];
    }
}

static GtkWidget *FindLabel(GtkWidget *widget, const char *text)
{
  if (GTK_IS_LABEL(widget) && !strcmp(gtk_label_get_text(GTK_LABEL(widget)),text)) return widget;
  for (GtkWidget *child=gtk_widget_get_first_child(widget); child; child=gtk_widget_get_next_sibling(child))
    { GtkWidget *found=FindLabel(child,text); if (found) return found; }
  return NULL;
}

static GtkWidget *FindIcon(GtkWidget *widget, const char *name)
{
  if (GTK_IS_IMAGE(widget) && !g_strcmp0(gtk_image_get_icon_name(GTK_IMAGE(widget)),name)) return widget;
  for (GtkWidget *child=gtk_widget_get_first_child(widget); child; child=gtk_widget_get_next_sibling(child))
    { GtkWidget *found=FindIcon(child,name); if (found) return found; }
  return NULL;
}

static GtkWidget *NativeRow(GtkWidget *label)
{
  GtkWidget *list = label ? gtk_widget_get_ancestor(label,GTK_TYPE_LIST_VIEW) : NULL;
  Check(list != NULL,@"object row belongs to theme's native list");
  while (gtk_widget_get_parent(label) != list) label=gtk_widget_get_parent(label);
  return label;
}

int main(void)
{
  @autoreleasepool
    {
      [NSApplication sharedApplication];
      NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
      [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
      NSString *path = [directory stringByAppendingPathComponent:@"Outline.xib"];
      NSString *xml = @"<document type=\"com.apple.InterfaceBuilder3.Cocoa.XIB\"><objects><window id=\"window\" title=\"Test Window\"><view id=\"view\" key=\"contentView\"><rect key=\"frame\" width=\"400\" height=\"300\"/><subviews><button id=\"button\"><rect key=\"frame\" x=\"20\" y=\"30\" width=\"100\" height=\"24\"/><buttonCell id=\"cell\" title=\"Press Me\"/></button></subviews></view></window><customObject id=\"owner\" userLabel=\"Owner\"/></objects></document>";
      Check([xml writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL],@"write fixture");
      PCInterfaceEditor *editor = [PCInterfaceEditor new];
      Check([editor openFileAtPath:path editorManager:nil editable:YES] != nil,@"open visual editor");
      [editor setWindowed:YES]; [editor show]; PumpEvents();
      NSOutlineView *tree = [editor valueForKey:@"tree"];
      Check([tree isKindOfClass:[NSOutlineView class]],@"interface objects use NSOutlineView");
      id file = [tree itemAtRow:0];
      id window = [tree itemAtRow:1];
      Check([[file valueForKey:@"title"] isEqual:@"Outline.xib"] && [file valueForKey:@"icon"] != nil,@"file row has name and icon");
      Check([tree parentForItem:window] == file && [tree isExpandable:window],@"window subtree belongs to file");
      GtkWidget *host = GTK_WIDGET(GTK4NativeHostForWindow([editor editorWindow]));
      GtkWidget *label = FindLabel(host,"Test Window (window)");
      GtkWidget *row = NativeRow(label);
      Check(FindIcon(row,"window-new-symbolic") != NULL,@"window row has theme-native item icon");
      Check(FindIcon(NativeRow(FindLabel(host,"Outline.xib")),"text-x-generic-symbolic") != NULL,@"file row has native document icon");
      NSInteger collapsedCount = [tree numberOfRows];
      GtkWidget *icon = FindIcon(row,"pan-end-symbolic");
      Check(icon != NULL,@"closed subtree has native disclosure button");
      g_signal_emit_by_name(gtk_widget_get_ancestor(icon,GTK_TYPE_BUTTON),"clicked"); PumpEvents();
      Check([tree isItemExpanded:window] && [tree numberOfRows] == collapsedCount+1,@"native disclosure opens subtree");
      Check([tree itemAtRow:[tree selectedRow]] == window,@"opening subtree preserves selected object");
      row = NativeRow(FindLabel(host,"Test Window (window)"));
      icon = FindIcon(row,"pan-down-symbolic");
      Check(icon != NULL,@"open subtree has native disclosure button");
      g_signal_emit_by_name(gtk_widget_get_ancestor(icon,GTK_TYPE_BUTTON),"clicked"); PumpEvents();
      Check(![tree isItemExpanded:window] && [tree numberOfRows] == collapsedCount,@"native disclosure closes subtree");
      Check([tree itemAtRow:[tree selectedRow]] == window,@"closing subtree preserves selected object");
      NSXMLDocument *document = [editor valueForKey:@"document"];
      NSXMLElement *button = [[document nodesForXPath:@"//*[@id='button']" error:NULL] objectAtIndex:0];
      [editor selectObject:button]; PumpEvents();
      id item = [tree itemAtRow:[tree selectedRow]];
      id view = [tree parentForItem:item];
      Check([item valueForKey:@"element"] == button && [tree parentForItem:view] == window
        && [tree levelForItem:item] == 3,@"selection reveals real hierarchy through XML wrappers");
      Check([tree isItemExpanded:window] && [tree isItemExpanded:view],@"canvas selection expands ancestors");
      Check([[NSData dataWithContentsOfFile:path] isEqual:[xml dataUsingEncoding:NSUTF8StringEncoding]],@"outline navigation does not modify XIB");
      [editor revertFileToSaved]; PumpEvents();
      Check([tree numberOfRows] > 0 && [tree itemAtRow:[tree selectedRow]] != nil,@"outline remains usable after document reload");
      [editor closeFile:nil save:NO]; [editor release]; PumpEvents();
      [[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
      NSLog(@"Interface outline integration passed: native rows, file/item icons, disclosure controls, nested selection, reload");
    }
  return 0;
}
