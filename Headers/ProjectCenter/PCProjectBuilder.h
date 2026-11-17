/*
 GNUstep ProjectCenter - http://www.gnustep.org/experience/ProjectCenter.html

 Copyright (C) 2000-2004 Free Software Foundation

 Authors: Philippe C.D. Robert
 Serg Stoyan

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

#ifndef _PCProjectBuilder_h_
#define _PCProjectBuilder_h_

#import <AppKit/AppKit.h>

@class PCProject;
@class PCButton;
@class PCProjectBuilderOptions;

/* Posted by a project builder (the object) when a build or clean starts, finds
 * an issue or ends. */
extern NSString *PCProjectBuilderDidChangeNotification;

typedef enum _ErrorLevel {
  ELFile,
  ELFunction,
  ELIncluded,
  ELIncludedError,
  ELError,
  ELNone
} ErrorLevel;

@interface PCProjectBuilder : NSObject
{
  PCProject       *project;
  PCProjectBuilderOptions *buildOptions;

  // Preferences
  NSString        *successSound;
  NSString        *failureSound;
  NSString        *buildTool;
  NSString        *rootBuildDir;
  BOOL            promptOnClean;

  // Options panel
  BOOL            verboseBuilding;

  NSString        *buildStatus;
  NSMutableString *buildStatusTarget;
  NSMutableString *buildTarget;
  NSMutableArray  *buildArgs;
  SEL             postProcess;
  NSTask          *makeTask;

  NSPipe          *stdOutPipe;
  NSPipe          *stdErrorPipe;
  NSFileHandle    *stdOutHandle;
  NSFileHandle    *stdErrorHandle;

  BOOL            _isBuilding;
  BOOL            _isCleaning;
  BOOL            _isLogging;
  BOOL            _isErrorLogging;

  // Component view
  BOOL            _isCVLoaded;
  NSBox           *componentView;
  PCButton        *buildButton;
  PCButton        *cleanButton;
  PCButton        *optionsButton;
  NSTextField     *errorsCountField;
  NSSplitView     *split;
  NSTextField     *statusField;
  NSTextField     *targetField;

  // Error logging
  NSMutableArray  *errorArray;
  NSString        *buildResult;
  BOOL            buildSucceeded;
  NSMutableString *errorString;

  ErrorLevel      currentEL;
  ErrorLevel      lastEL;
  ErrorLevel      nextEL;
  NSString        *lastIndentString;
  int             errorsCount;
  int             warningsCount;

  // Output logging
  NSTextView      *logOutput;
  NSMutableString *currentBuildFile;
  NSMutableString *currentBuildPath;
}

- (id)initWithProject:(PCProject *)aProject;
- (void)dealloc;

- (NSView *)componentView;
- (PCProject *)project;
- (void)loadPreferences:(NSNotification *)aNotification;
- (void)updateTargetField;

// --- Accessory
- (BOOL)isBuilding;
- (BOOL)isCleaning;
- (void)performStartBuild;
- (void)performStartClean;
- (void)performStopBuild;
- (NSArray *)buildArguments;

// --- Issues of the last build, for the issue navigator
/* Errors, warnings and notes in the order the compiler reported them. Each
 * has "File", "Line", "Column" (NSNumbers), "Type" ("error", "warning" or
 * "note") and "Message". */
- (NSArray *)issues;
- (int)errorsCount;
- (int)warningsCount;
/* "Build succeeded", "Build failed" and the like for the last build or
 * clean; nil before the first one. */
- (NSString *)buildResult;
- (BOOL)buildSucceeded;
/* Open the issue's file in the editor at its line. */
- (void)showIssue:(NSDictionary *)issue;

// --- Actions
- (void)startBuild:(id)sender;
- (void)startClean:(id)sender;
- (BOOL)stopMake:(id)sender;
- (void)showOptionsPanel:(id)sender;
- (void)cleanupAfterMake:(NSString *)statusString;

- (BOOL)prebuildCheck;
- (void)build:(id)sender;
//- (void)buildDidTerminate;

@end

@interface PCProjectBuilder (Logging)

- (void)updateErrorsCountField;

- (void)logStdOut:(NSNotification *)aNotif;
- (void)logErrOut:(NSNotification *)aNotif;
- (void)logData:(NSData *)data error:(BOOL)isError;

@end

@interface PCProjectBuilder (BuildLogging)

// --- Parsing utilities
- (BOOL)line:(NSString *)lineString startsWithString:(NSString *)substring;
- (NSArray *)componentsOfLine:(NSString *)lineString;
- (void)parseMakeLine:(NSString *)lineString;
- (NSString *)parseCompilerLine:(NSString *)lineString;

- (void)logBuildString:(NSString *)string newLine:(BOOL)newLine;
- (void)appendToLog:(NSString *)string;
- (NSString *)parseBuildLine:(NSString *)string;

@end

@interface PCProjectBuilder (ErrorLogging)

- (void)logErrorString:(NSString *)string;

- (NSString *)lineTail:(NSString*)line afterString:(NSString*)string;
- (NSArray *)parseErrorLine:(NSString *)string;

@end

#endif
