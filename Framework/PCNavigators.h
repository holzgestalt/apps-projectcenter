/*
 PCNavigators.h

 Breakpoint and debug navigators for the project window's sidebar.

 This file is part of GNUstep ProjectCenter.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation; either version 2 of the License, or
 (at your option) any later version.
 */

#import <AppKit/AppKit.h>
#import <Protocols/CodeDebugger.h>

@class PCProject;

/* Describe the layout of a navigator's icon and label. */
void PCAlignNavigatorCell(NSTableCellView *cell);

/* One row in a navigator outline. */
@interface PCNavigatorItem : NSObject
{
  @public
  NSString       *title;
  NSImage        *icon;
  NSString       *toolTip;
  NSDictionary   *info;
  NSMutableArray *children;
}
+ (PCNavigatorItem *)itemWithTitle:(NSString *)title icon:(NSImage *)icon info:(NSDictionary *)info;
- (NSString *)title;
- (NSImage *)icon;
- (NSDictionary *)info;
- (NSMutableArray *)children;
@end

/* Base: an outline in a scroll view, with an optional bar below it. */
@interface PCNavigator : NSObject
{
  PCProject     *project;        // not retained
  NSView        *view;
  NSScrollView  *scrollView;
  NSOutlineView *outline;
  NSMutableArray *roots;
  BOOL           updatingSelection;
}
- (id)initWithProject:(PCProject *)aProject;
- (NSView *)view;
- (NSOutlineView *)outlineView;
- (NSArray *)rootItems;
- (void)reloadItems;
- (void)selectionDidChange:(PCNavigatorItem *)item;
- (void)_reloadOutlineExpandingAll;
@end

/* Exception, symbolic and file breakpoints. */
@interface PCBreakpointNavigator : PCNavigator
{
  NSPopUpButton *addButton;
  NSButton      *removeButton;
}
- (void)addExceptionBreakpoint:(id)sender;
- (void)addSymbolicBreakpoint:(id)sender;
- (void)addSymbolicBreakpointForSymbol:(NSString *)symbol;
- (void)removeSelectedBreakpoint:(id)sender;
@end

/* The stopped thread's call stack. */
@interface PCDebugNavigator : PCNavigator
{
  id<CodeDebugger> debugger;     // not retained
  NSArray          *frames;
  NSString         *reason;
  NSString         *state;
}
- (NSArray *)frames;
- (NSInteger)selectedFrameIndex;
@end

/* Errors and warnings of the last build, by file, like Xcode's issue
 * navigator. */
@interface PCIssueNavigator : PCNavigator
{
  id        builder;             // not retained
  NSButton  *logButton;
}
- (void)showBuildLog:(id)sender;
@end
