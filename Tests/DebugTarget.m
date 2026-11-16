/* A tiny program for the ProjectCenter debugger test: a line breakpoint
 * stops at the log call, the exception breakpoint stops at the raise. */
#import <Foundation/Foundation.h>

static void Raise(void)
{
  [NSException raise:@"PCDebugTargetException" format:@"raised for the debugger test"];
}

int main(int argc, char **argv)
{
  @autoreleasepool
  {
    NSLog(@"debug target started");
    Raise();
  }
  return 0;
}
