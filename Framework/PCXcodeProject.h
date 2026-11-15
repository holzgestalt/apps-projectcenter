#import <Foundation/Foundation.h>

/* Read-only project metadata adapter. Source files remain editable. */
@interface PCXcodeProject : NSObject
+ (NSDictionary *)projectAtPath:(NSString *)path error:(NSString **)error;
@end
