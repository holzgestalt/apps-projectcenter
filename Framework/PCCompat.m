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

#import <ProjectCenter/PCCompat.h>

#ifndef GNUSTEP
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#endif

#ifndef GNUSTEP

@implementation NSFont (PCCompat)

- (CGFloat)widthOfString:(NSString *)string
{
  NSDictionary *attributes = [NSDictionary dictionaryWithObject:self forKey:NSFontAttributeName];

  return [string sizeWithAttributes:attributes].width;
}

@end

/* Name Cocoa images after the GNUstep theme images that ProjectCenter asks
 * for, so +[NSImage imageNamed:] finds them on both platforms. */
__attribute__((constructor))
static void PCRegisterGNUstepImageNames(void)
{
  @autoreleasepool
  {
    NSDictionary *names = @{
      @"common_Folder": [NSImage imageNamed:NSImageNameFolder],
      @"common_Unknown": [[NSWorkspace sharedWorkspace]
                          iconForContentType:UTTypeData],
      @"common_ArrowUp": [NSImage imageWithSystemSymbolName:@"chevron.up"
                                   accessibilityDescription:@"Up"],
      @"common_ArrowDown": [NSImage imageWithSystemSymbolName:@"chevron.down"
                                     accessibilityDescription:@"Down"],
    };

    for (NSString *name in names)
    {
      NSImage *image = [[names objectForKey:name] copy];

      if ([NSImage imageNamed:name] == nil && [image setName:name] == NO)
      {
        NSLog(@"PCCompat: could not register image %@", name);
      }
      /* A named image stays registered; the name table keeps it. */
    }
  }
}

@implementation NSString (PCCompat)

- (NSString *)stringByTrimmingSpaces
{
  return [self stringByTrimmingCharactersInSet:
          [NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

@end

@implementation NSUserDefaults (PCCompat)

+ (NSArray *)userLanguages
{
  NSLocale       *english = [NSLocale localeWithLocaleIdentifier:@"en"];
  NSMutableArray *languages = [NSMutableArray array];

  for (NSString *identifier in [NSLocale preferredLanguages])
  {
    NSString *code = [[NSLocale componentsFromLocaleIdentifier:identifier]
                      objectForKey:NSLocaleLanguageCode];
    NSString *name = [english displayNameForKey:NSLocaleLanguageCode
                                          value:code];

    if (name != nil && [languages containsObject:name] == NO)
    {
      [languages addObject:name];
    }
  }
  if ([languages containsObject:@"English"] == NO)
  {
    [languages addObject:@"English"];
  }
  return languages;
}

@end

@implementation NSWorkspace (PCCompat)

- (NSString *)getBestAppInRole:(NSString *)role
                  forExtension:(NSString *)extension
{
  UTType *type;
  NSURL  *app;

  if ([extension length] == 0)
  {
    return nil;
  }
  type = [UTType typeWithFilenameExtension:extension];
  app = type ? [self URLForApplicationToOpenContentType:type] : nil;
  return [app path];
}

@end

@implementation NSText (PCCompat)

- (void)setText:(NSString *)string
{
  [self setString:string];
}

@end

@implementation NSTextField (PCCompat)

- (void)setNextText:(id)anObject
{
  [self setNextKeyView:anObject];
}

@end

#endif // GNUSTEP
