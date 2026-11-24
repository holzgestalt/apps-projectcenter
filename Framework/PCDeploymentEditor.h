/*
 PCDeploymentEditor.h

 The Deployment tab of the Xcode project editor: for the selected target,
 its architectures (a Mac target) or the distributions Archive packages it
 for (a Linux target), and the settings of each.

 This file is part of GNUstep ProjectCenter.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation; either version 2 of the License, or
 (at your option) any later version.
 */

#import <AppKit/AppKit.h>

@class PCProject;

/* The views are in the Deployment tab of ProjectEditor.xib. The settings
 * form of the selected distribution is made in code from
 * +[PCDeployment fieldsForKind:], as the fields depend on the kind. Every
 * change is saved at once as a build setting of the target (see
 * PCDeployment.h), and the owner (the project editor) is asked to -reload,
 * which gives the target back with -setTarget:. */
@interface PCDeploymentEditor : NSObject
{
  PCProject           *project;     // not retained
  id                  owner;       // not retained
  NSDictionary        *target;      // an overview entry, or nil
  NSMutableArray      *deployments; // NSMutableDictionary each
  NSArray             *fields;      // of the selected platform
  NSMutableDictionary *controls;    // setting key -> control of the form
  NSView              *form;        // the form scroll view's document

  IBOutlet NSTableView   *platformsTable;
  IBOutlet NSPopUpButton *addButton;
  IBOutlet NSButton      *removeButton;
  IBOutlet NSScrollView  *formScroll;
  IBOutlet NSTextField   *statusField;
}

- (void)setProject:(PCProject *)aProject;
- (void)setOwner:(id)anOwner;
/* The target whose deployment is shown, an entry of +[PCXcodeProject
 * overviewOfProjectAtPath:error:]; nil for none (the project row). */
- (void)setTarget:(NSDictionary *)aTarget;
- (NSDictionary *)target;
/* Reads the target's deployment again. */
- (void)reload;
- (NSArray *)deployments;
- (NSInteger)selectedIndex;
- (void)selectIndex:(NSInteger)index;
/* The form's controls by setting key, for the selected platform. */
- (NSDictionary *)controls;

/* Edits, saved at once; nil, empty or the default removes the setting. */
- (BOOL)setValue:(NSString *)value forSetting:(NSString *)key ofDeploymentAtIndex:(NSUInteger)index;
- (void)addPlatformOfKind:(NSString *)kind;
- (void)removePlatformAtIndex:(NSUInteger)index;

- (IBAction)addPlatform:(id)sender;
- (IBAction)removePlatform:(id)sender;

@end
