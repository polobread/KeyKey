// Copyright (c) 2026 Chui-Ping Cheng. BSD-3-Clause; see ../../LICENSE.txt.
#define KEYKEY_INPUT_SOURCE_TEST 1
#import "../InputSourceTool.m"

@interface FakeSources : NSObject <KKInputSourceOperations>
@property BOOL registrationSucceeds, stopSucceeds, enableSucceeds, enabled, selected, fallbackSucceeds;
@property BOOL enabledReadable, selectedReadable;
@property(nonatomic, retain) NSMutableArray *calls;
@end
@implementation FakeSources
- (id)init {
    if ((self = [super init])) {
        _calls = [NSMutableArray new];
        _registrationSucceeds = YES; _stopSucceeds = YES; _enableSucceeds = YES; _fallbackSucceeds = YES;
        _enabledReadable = YES; _selectedReadable = YES;
    }
    return self;
}
- (void)dealloc { [_calls release]; [super dealloc]; }
- (BOOL)registerInstalledInputMethod { [self.calls addObject:@"register"]; return self.registrationSucceeds; }
- (BOOL)stopInstalledInputMethod { [self.calls addObject:@"stop"]; return self.stopSucceeds; }
- (BOOL)readEnabled:(BOOL *)enabled { [self.calls addObject:@"read"]; *enabled = self.enabled; return self.enabledReadable; }
- (BOOL)readSelected:(BOOL *)selected { [self.calls addObject:@"selected"]; *selected = self.selected; return self.selectedReadable; }
- (BOOL)selectFallback { [self.calls addObject:@"fallback"]; return self.fallbackSucceeds; }
- (BOOL)enableInstalledInputMethod { [self.calls addObject:@"enable"]; return self.enableSucceeds; }
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
        Check(KKRefreshInputSource(source, NO), @"first install or previously disabled source stays unchanged");
        Check([source.calls isEqual:@[@"register"]],
              @"postinstall does not terminate a newly launched input method");
        [source.calls removeAllObjects]; source.registrationSucceeds = NO;
        Check(!KKRefreshInputSource(source, YES) && [source.calls isEqual:@[@"register"]],
              @"registration failure prevents attempted restoration");
        [source.calls removeAllObjects]; source.registrationSucceeds = YES;
        Check(KKRefreshInputSource(source, YES) && [source.calls isEqual:@[@"register", @"enable"]],
              @"upgrade registers and restores only the saved enabled intent");
        [source.calls removeAllObjects]; source.enableSucceeds = NO;
        Check(!KKRefreshInputSource(source, YES), @"failed enabled restoration is reported, never silently accepted");
        [source.calls removeAllObjects]; source.enabled = YES; source.selected = YES;
        BOOL enabled = NO;
        Check(KKPrepareInputSource(source, &enabled) && enabled &&
              [source.calls isEqual:@[@"read", @"selected", @"fallback", @"stop"]],
              @"active source is captured and safely retired before payload replacement");
        [source.calls removeAllObjects]; source.fallbackSucceeds = NO;
        Check(!KKPrepareInputSource(source, &enabled) && ![source.calls containsObject:@"stop"],
              @"failed fallback prevents both termination and payload replacement");
        [source.calls removeAllObjects]; source.selected = NO; source.enabled = NO;
        Check(KKPrepareInputSource(source, &enabled) && !enabled &&
              [source.calls isEqual:@[@"read", @"selected", @"stop"]],
              @"inactive or first install does not change the user's selection");
        [source.calls removeAllObjects]; source.stopSucceeds = NO;
        Check(!KKPrepareInputSource(source, &enabled), @"old process remaining alive prevents replacement");
        [source.calls removeAllObjects]; source.enabledReadable = NO;
        Check(!KKPrepareInputSource(source, &enabled) && [source.calls isEqual:@[@"read"]],
              @"unknown enabled intent prevents replacement before changing selection");
        [source.calls removeAllObjects]; source.enabledReadable = YES; source.selectedReadable = NO;
        Check(!KKPrepareInputSource(source, &enabled) && [source.calls isEqual:@[@"read", @"selected"]],
              @"unknown selected input source prevents replacement before termination");
        NSLog(@"PASS: %d input-source lifecycle checks (fake system; no user settings touched)", passed);
    }
}
