/*
 PCXcodeProjectEditor.h

 Read-only project editor for Xcode projects: the project and its targets,
 with general information, build settings and build phases, as shown by
 Xcode when the project is selected in the navigator.

 This file is part of GNUstep ProjectCenter.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation; either version 2 of the License, or
 (at your option) any later version.
 */

#import <AppKit/AppKit.h>

@class PCProject;
@class PCTargetList;

@interface PCXcodeProjectEditor : NSObject
{
  PCProject     *project;          // not retained
  NSDictionary  *overview;
  NSDictionary  *selection;        // the project or one target
  NSView        *view;
  PCTargetList  *targetList;
  NSSegmentedControl *sections;
  NSTabView     *tabs;
  NSScrollView  *generalScroll;    // the General form
  NSTableView   *settingsTable;
  NSTableView   *phasesTable;
  NSArray       *generalRows;      // [Section] or [Property, Value(, Edit)]
  NSArray       *settingRows;      // [Setting, value per configuration...]
  NSArray       *phaseRows;        // [Phase, Item]
  NSArray       *configurationNames;
}

- (id)initWithProject:(PCProject *)aProject;
- (NSView *)view;
/* Read the project again and show it. */
- (void)reload;
- (NSDictionary *)overview;
/* Show the project (index 0) or a target (1...). */
- (void)selectEntryAtIndex:(NSInteger)index;
- (NSDictionary *)selection;
- (NSTabView *)tabView;
/* General (0), Build Settings (1), Build Phases (2). */
- (void)selectSectionAtIndex:(NSInteger)index;
/* The General pane: [Section title] rows start a section, as Xcode's, and
 * [Property, Value] rows follow. An editable row has a third element, the
 * edit: {Kind, Key} with Kind Setting (a build setting of every
 * Configurations identifier), Info (a key of the Info.plist File), Attribute
 * (of the project Object) or GNUstep (GNUstep/ProjectCenter.plist), and
 * Choices [[Title, Value]] when it has a fixed set of values. */
- (NSArray *)generalRows;
/* Saves the value of an editable row; nil or empty removes it. The pane is
 * read again afterwards. */
- (BOOL)setGeneralValue:(NSString *)value atRow:(NSUInteger)index;
/* Sets a GNUstep setting of the project (GNUstep/ProjectCenter.plist):
 * BuildScript, Executable or Theme; nil or empty removes it. */
- (BOOL)setGNUstepSetting:(NSString *)value forKey:(NSString *)key;
- (NSArray *)settingRows;
- (NSArray *)phaseRows;
- (NSArray *)configurationNames;
- (NSOutlineView *)targetOutlineView;

@end
