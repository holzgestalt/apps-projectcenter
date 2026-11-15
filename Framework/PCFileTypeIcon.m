/* Original vector artwork, distributed under GPL version 2 or later. */
#import "PCFileTypeIcon.h"

NSImage *PCFileTypeIcon(NSString *extension)
{
  extension = [extension lowercaseString];
  if (![@[@"m",@"h",@"c",@"xib",@"plist"] containsObject:extension]) return nil;
  static NSMutableDictionary *icons;
  if (!icons) icons = [NSMutableDictionary new];
  NSImage *image = [icons objectForKey:extension];
  if (image) return image;

  /* Draw at three times the row's logical size, keeping letters readable on
   * high-density displays as well as in the theme's native image widgets. */
  NSBitmapImageRep *bitmap = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
    pixelsWide:48 pixelsHigh:48 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
    isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0] autorelease];
  [NSGraphicsContext saveGraphicsState];
  [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap]];
  NSColor *accent = [extension isEqual:@"h"] ? [NSColor colorWithCalibratedRed:0.30 green:0.53 blue:0.61 alpha:1]
    : [extension isEqual:@"m"] ? [NSColor colorWithCalibratedRed:0.34 green:0.29 blue:0.89 alpha:1]
    : [extension isEqual:@"xib"] ? [NSColor colorWithCalibratedRed:1.0 green:0.74 blue:0.0 alpha:1]
    : [extension isEqual:@"plist"] ? [NSColor colorWithCalibratedRed:0.51 green:0.31 blue:0.68 alpha:1]
    : [NSColor colorWithCalibratedRed:0.16 green:0.43 blue:0.77 alpha:1];
  [accent set];
  if ([extension isEqual:@"plist"])
    {
      NSBezierPath *page = [NSBezierPath bezierPath];
      [page moveToPoint:NSMakePoint(7,3)]; [page lineToPoint:NSMakePoint(41,3)];
      [page lineToPoint:NSMakePoint(41,34)]; [page lineToPoint:NSMakePoint(30,45)];
      [page lineToPoint:NSMakePoint(7,45)]; [page closePath];
      [[NSColor colorWithCalibratedWhite:0.98 alpha:1] set]; [page fill];
      [accent set]; [page setLineWidth:2.4]; [page stroke];
      NSBezierPath *fold = [NSBezierPath bezierPath];
      [fold moveToPoint:NSMakePoint(30,45)]; [fold lineToPoint:NSMakePoint(30,34)];
      [fold lineToPoint:NSMakePoint(41,34)]; [fold setLineWidth:2]; [fold stroke];
    }
  if ([@[@"m",@"h",@"c"] containsObject:extension])
    {
      NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSFont systemFontOfSize:42],NSFontAttributeName,accent,NSForegroundColorAttributeName,nil];
      NSSize size = [extension sizeWithAttributes:attributes];
      [extension drawAtPoint:NSMakePoint(24-size.width/2,0) withAttributes:attributes];
    }
  else if ([extension isEqual:@"xib"])
    {
      /* Crossed brush and pencil, matching the reference's yellow tools. */
      NSBezierPath *handle = [NSBezierPath bezierPath];
      [handle moveToPoint:NSMakePoint(7,40)]; [handle lineToPoint:NSMakePoint(31,16)];
      [handle setLineWidth:4.5]; [handle setLineCapStyle:NSRoundLineCapStyle]; [handle stroke];
      NSBezierPath *brush = [NSBezierPath bezierPath];
      [brush moveToPoint:NSMakePoint(31,17)];
      [brush curveToPoint:NSMakePoint(42,8) controlPoint1:NSMakePoint(39,18) controlPoint2:NSMakePoint(35,10)];
      [brush curveToPoint:NSMakePoint(28,8) controlPoint1:NSMakePoint(37,2) controlPoint2:NSMakePoint(27,2)];
      [brush curveToPoint:NSMakePoint(31,17) controlPoint1:NSMakePoint(25,12) controlPoint2:NSMakePoint(28,15)];
      [brush closePath]; [brush fill];
      NSBezierPath *pencil = [NSBezierPath bezierPath];
      [pencil moveToPoint:NSMakePoint(11,11)]; [pencil lineToPoint:NSMakePoint(38,38)];
      /* Clear a small gap at the crossing without painting a background. */
      NSGraphicsContext *context = [NSGraphicsContext currentContext];
      [context saveGraphicsState]; [context setCompositingOperation:NSCompositeClear];
      [pencil setLineWidth:8]; [pencil stroke]; [context restoreGraphicsState];
      [accent set]; [pencil setLineWidth:4.5]; [pencil stroke];
      NSBezierPath *tip = [NSBezierPath bezierPath];
      [tip moveToPoint:NSMakePoint(5,5)]; [tip lineToPoint:NSMakePoint(8,14)];
      [tip lineToPoint:NSMakePoint(14,8)]; [tip closePath]; [tip fill];
      [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(39,39,5,5)] fill];
    }
  else
    {
      NSBezierPath *tree = [NSBezierPath bezierPath];
      [tree moveToPoint:NSMakePoint(15,29)]; [tree lineToPoint:NSMakePoint(15,12)];
      [tree lineToPoint:NSMakePoint(22,12)];
      [tree moveToPoint:NSMakePoint(15,21)]; [tree lineToPoint:NSMakePoint(22,21)];
      [tree setLineWidth:2]; [tree stroke];
      NSRectFill(NSMakeRect(12,28,7,5));
      NSRectFill(NSMakeRect(23,19,12,4)); NSRectFill(NSMakeRect(23,10,12,4));
    }
  [[NSGraphicsContext currentContext] flushGraphics];
  [NSGraphicsContext restoreGraphicsState];
  [bitmap setSize:NSMakeSize(16,16)];
  image = [[[NSImage alloc] initWithSize:NSMakeSize(16,16)] autorelease];
  [image addRepresentation:bitmap];
  [icons setObject:image forKey:extension];
  return image;
}
