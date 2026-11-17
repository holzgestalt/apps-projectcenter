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
 * gorm2xib: write the XIB of a Gorm interface.
 *
 *   gorm2xib Interface.gorm [Interface.xib]
 *
 * Uses PCGormArchive and PCGormXIBWriter from ProjectCenter.framework's
 * sources; see README.md and regenerate.sh.
 */

#import <Foundation/Foundation.h>
#import "PCGormArchive.h"
#import "PCGormXIBWriter.h"

/* The installed Interface Builder version, which ibtool expects to find in
 * the document; nil without Xcode. */
static NSString *ToolsVersion(void)
{
  NSTask *task = [[[NSTask alloc] init] autorelease];
  NSPipe *pipe = [NSPipe pipe];
  NSData *data;
  id     plist;

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
  plist = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL];
  return [[plist objectForKey:@"com.apple.ibtool.version"] objectForKey:@"bundle-version"];
}

int main(int argc, char **argv)
{
  @autoreleasepool
  {
    NSString      *source, *target, *error = nil;
    PCGormArchive *archive;
    NSXMLDocument *document;
    NSArray       *warnings = nil;
    NSData        *xml;

    if (argc < 2)
    {
      fprintf(stderr, "usage: gorm2xib Interface.gorm [Interface.xib]\n");
      return 2;
    }
    source = [[NSString stringWithUTF8String:argv[1]] stringByStandardizingPath];
    target = argc > 2 ? [NSString stringWithUTF8String:argv[2]]
                      : [[source stringByDeletingPathExtension] stringByAppendingPathExtension:@"xib"];
    archive = [PCGormArchive archiveWithContentsOfFile:
               [source stringByAppendingPathComponent:@"objects.gorm"] error:&error];
    if (archive == nil)
    {
      fprintf(stderr, "%s: %s\n", argv[1], [error UTF8String]);
      return 1;
    }
    document = [PCGormXIBWriter documentForArchive:archive toolsVersion:ToolsVersion()
                                          warnings:&warnings];
    xml = [document XMLDataWithOptions:NSXMLNodePrettyPrint | NSXMLNodeCompactEmptyElement];
    if (![xml writeToFile:target atomically:YES])
    {
      fprintf(stderr, "%s: cannot write %s\n", argv[1], [target UTF8String]);
      return 1;
    }
    for (NSString *warning in warnings)
    {
      fprintf(stderr, "%s: warning: %s\n", [[source lastPathComponent] UTF8String],
              [warning UTF8String]);
    }
  }
  return 0;
}
