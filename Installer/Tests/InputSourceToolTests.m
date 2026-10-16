// Copyright (c) 2026 Chui-Ping Cheng. BSD-3-Clause; see ../../LICENSE.txt.
#define KEYKEY_INPUT_SOURCE_TEST 1
#import "../InputSourceTool.m"

@interface FakeSources : NSObject <KKInputSourceOperations>
@property BOOL registrationSucceeds, stopSucceeds;
@property(nonatomic, retain) NSMutableArray *calls;
@end
@implementation FakeSources
- (id)init {
    if ((self = [super init])) {
        _calls = [NSMutableArray new];
        _registrationSucceeds = YES; _stopSucceeds = YES;
    }
    return self;
}
- (void)dealloc { [_calls release]; [super dealloc]; }
- (BOOL)registerInstalledInputMethod { [self.calls addObject:@"register"]; return self.registrationSucceeds; }
- (BOOL)stopInstalledInputMethod { [self.calls addObject:@"stop"]; return self.stopSucceeds; }
@end

static int passed;
static void Check(BOOL value, NSString *message)
{
    if (!value) { NSLog(@"FAIL: %@", message); exit(1); } passed++;
}

int main(void)
{
    @autoreleasepool {
        FakeSources *source = [[[FakeSources alloc] init] autorelease];
        Check(KKRefreshInputSource(source), @"registered source and confirmed old-process exit succeed");
        Check([source.calls isEqual:@[@"register", @"stop"]],
              @"registration must succeed before retiring old processes");
        [source.calls removeAllObjects]; source.registrationSucceeds = NO;
        Check(!KKRefreshInputSource(source) && [source.calls isEqual:@[@"register"]],
              @"registration failure never terminates the existing input method");
        [source.calls removeAllObjects]; source.registrationSucceeds = YES; source.stopSucceeds = NO;
        Check(!KKRefreshInputSource(source) && [source.calls isEqual:@[@"register", @"stop"]],
              @"unconfirmed exit is reported for visible setup guidance");
        NSLog(@"PASS: %d input-source lifecycle checks (fake system; no user settings touched)", passed);
    }
}
