#import <Foundation/Foundation.h>

/* Read-only project metadata adapter. Source files remain editable. */
@interface PCXcodeProject : NSObject
+ (NSDictionary *)projectAtPath:(NSString *)path error:(NSString **)error;
/* A read-only description of the project for the project editor:
 * {Name, Format, DevelopmentRegion, KnownRegions, Configurations, Targets}.
 * Configurations are [{Name, Base, Settings}]; each target is {Name, Kind,
 * ProductType, ProductName, Configurations, Phases, Dependencies}, a phase
 * {Name, Kind, Files, Script}. */
+ (NSDictionary *)overviewOfProjectAtPath:(NSString *)path error:(NSString **)error;
@end
