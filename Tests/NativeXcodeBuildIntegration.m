#import <AppKit/AppKit.h>
#import "PCAppController.h"
#import <ProjectCenter/PCProjectManager.h>
#import <ProjectCenter/PCProject.h>
#import <ProjectCenter/PCProjectBuilder.h>
#import <ProjectCenter/PCProjectLauncher.h>
#import "Framework/PCXcodeProject.h"
#include <gtk/gtk.h>

static void check(BOOL value,NSString *message) { if(!value) { NSLog(@"FAIL %@",message); exit(1); } }
static void pump(double seconds) {
  NSDate *end=[NSDate dateWithTimeIntervalSinceNow:seconds];
  while(end.timeIntervalSinceNow>0) {
    while(g_main_context_pending(NULL)) g_main_context_iteration(NULL,FALSE);
    NSEvent *event=[NSApp nextEventMatchingMask:NSAnyEventMask untilDate:[NSDate dateWithTimeIntervalSinceNow:.01]
      inMode:NSDefaultRunLoopMode dequeue:YES];
    if(event) [NSApp sendEvent:event];
    [NSApp updateWindows];
  }
}
int main(int argc,char **argv) { @autoreleasepool { @try {
  check(argc==2,@"project argument");
  [NSApplication sharedApplication];
  [[NSUserDefaults standardUserDefaults] setVolatileDomain:@{@"UseTearOffWindows":@"NO"} forName:NSArgumentDomain];
  NSString *path=[NSString stringWithUTF8String:argv[1]];
  NSString *root=path.stringByDeletingLastPathComponent;
  NSData *original=[NSData dataWithContentsOfFile:[path stringByAppendingPathComponent:@"project.pbxproj"]];
  check(![[NSFileManager defaultManager] fileExistsAtPath:[root stringByAppendingPathComponent:@"GNUstep/ProjectCenter.plist"]],@"no sidecar exists");
  PCAppController *app=[PCAppController new];
  PCProjectManager *manager=app.projectManager;
  PCProject *project=[manager openProjectAt:path makeActive:YES];
  check(project!=nil,@"ProjectCenter opens bare Xcode project");
  check([project.projectDict objectForKey:@"XCODE_BuildScript"]==nil && [project.projectDict objectForKey:@"XCODE_Executable"]==nil,@"no configured script or executable");
  check(![[NSFileManager defaultManager] fileExistsAtPath:[root stringByAppendingPathComponent:@"GNUmakefile"]],@"no app makefile exists");
  check([PCXcodeProject GNUstepBuildTool]!=nil,@"built-in compiler is packaged");
  PCProjectBuilder *builder=project.projectBuilder;
  [builder startBuild:nil];
  NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:90];
  while(!builder.buildResult && deadline.timeIntervalSinceNow>0) pump(.05);
  check(builder.buildSucceeded,[NSString stringWithFormat:@"ProjectCenter Build: %@",builder.buildResult]);
  NSString *executable=project.projectLauncher.executablePath;
  check([[NSFileManager defaultManager] isExecutableFileAtPath:executable],@"Run resolves executable from PBX metadata");
  check([executable hasPrefix:[root stringByAppendingPathComponent:@"build/ProjectCenter/"]],@"Run uses the built-in compiler product");
  [project.projectLauncher run:nil]; pump(1.5);
  check(project.projectLauncher.isRunning,@"ProjectCenter Run launches the freshly built application");
  [project.projectLauncher performStop]; pump(.3);
  check([original isEqual:[NSData dataWithContentsOfFile:[path stringByAppendingPathComponent:@"project.pbxproj"]]],@"Build leaves Xcode project unchanged");
  check(![[NSFileManager defaultManager] fileExistsAtPath:[root stringByAppendingPathComponent:@"GNUstep/ProjectCenter.plist"]],@"Build does not create a sidecar");
  check(![[NSFileManager defaultManager] fileExistsAtPath:[root stringByAppendingPathComponent:@"GNUmakefile"]],@"Build does not generate an app makefile");
  [manager closeProject:project];
  NSLog(@"PASS ProjectCenter: open FontTableViewer, Build and Run directly from Xcode metadata without a sidecar or application build script");
  return 0;
} @catch(NSException *exception) { NSLog(@"FAIL %@ %@",exception,exception.callStackSymbols); return 1; } } }
