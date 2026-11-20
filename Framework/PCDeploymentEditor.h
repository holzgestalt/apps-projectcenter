/*
 PCDeploymentEditor.h

 The Deployment tab of the Xcode project editor: the platforms that
 Archive builds shippable applications for, and the settings of each.

 This file is part of GNUstep ProjectCenter.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation; either version 2 of the License, or
 (at your option) any later version.
 */

#import <AppKit/AppKit.h>

@class PCProject;

/* The views are in the Deployment tab of ProjectEditor.xib. The settings
 * form of the selected platform is made in code from
 * +[PCDeployment fieldsForKind:], as the fields depend on the kind. Every
 * change is saved at once in GNUstep/ProjectCenter.plist. */
@interface PCDeploymentEditor : NSObject
{
  PCProject           *project;     // not retained
  NSMutableArray      *deployments; // NSMutableDictionary each
  NSArray             *fields;      // of the selected platform
  NSMutableDictionary *controls;    // setting key -> control of the form
  NSView              *form;        // the form scroll view's document

  IBOutlet NSTableView   *platformsTable;
  IBOutlet NSPopUpButton *addButton;
  IBOutlet NSButton      *removeButton;
  IBOutlet NSScrollView  *formScroll;
  IBOutlet NSTextField   *statusField;
  IBOutlet NSButton      *archiveButton;
}

- (void)setProject:(PCProject *)aProject;
/* Reads the platforms from the project again. */
- (void)reload;
- (NSArray *)deployments;
- (NSInteger)selectedIndex;
- (void)selectIndex:(NSInteger)index;
/* The form's controls by setting key, for the selected platform. */
- (NSDictionary *)controls;

/* Edits, saved at once; nil or empty takes the default. */
- (BOOL)setValue:(NSString *)value forSetting:(NSString *)key ofDeploymentAtIndex:(NSUInteger)index;
- (void)addPlatformOfKind:(NSString *)kind;
- (void)removePlatformAtIndex:(NSUInteger)index;

- (IBAction)addPlatform:(id)sender;
- (IBAction)removePlatform:(id)sender;
- (IBAction)archive:(id)sender;

@end
