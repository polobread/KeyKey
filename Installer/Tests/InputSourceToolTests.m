// Copyright (c) 2026 Chui-Ping Cheng. BSD-3-Clause; see ../../LICENSE.txt.
#define KEYKEY_INPUT_SOURCE_TEST 1
#import "../InputSourceTool.m"

@interface FakeSources : NSObject <KKInputSourceOperations>
@property BOOL enabled, selected;
@property(nonatomic, retain) NSMutableArray *calls;
@property(nonatomic, copy) NSString *failOperation;
@property(nonatomic, copy) NSString *persistentFailure;
@property BOOL partialDisableFailure;
@property BOOL partialSelectFailure;
@end
@implementation FakeSources
- (id)init { if ((self = [super init])) _calls = [NSMutableArray new]; return self; }
- (void)dealloc { [_calls release]; [_failOperation release]; [_persistentFailure release]; [super dealloc]; }
- (BOOL)perform:(NSString *)operation {
    [self.calls addObject:operation];
    if ([self.persistentFailure isEqual:operation]) return NO;
    if ([self.failOperation isEqual:operation]) { self.failOperation = nil; return NO; }
    return YES;
}
- (BOOL)readEnabled:(BOOL *)enabled selected:(BOOL *)selected {
    *enabled = self.enabled; *selected = self.selected; return [self perform:@"read"];
}
- (BOOL)selectFallback { if (![self perform:@"fallback"]) return NO; self.selected = NO; return YES; }
- (BOOL)applyEnabled:(BOOL)value {
    if (!value && self.partialDisableFailure) {
        [self.calls addObject:@"disable"]; self.enabled = NO; self.selected = NO; return NO;
    }
    if (![self perform:value ? @"enable" : @"disable"]) return NO;
    self.enabled = value; if (!value) self.selected = NO; return YES;
}
- (BOOL)stopInstalledInputMethod { return [self perform:@"stop"]; }
- (BOOL)registerInstalledInputMethod { return [self perform:@"register"]; }
- (BOOL)selectInputMethod {
    if (self.partialSelectFailure) { [self.calls addObject:@"select"]; self.selected = YES; return NO; }
    if (![self perform:@"select"]) return NO; self.selected = YES; return YES;
}
@end

static int passed;
static void Check(BOOL value, NSString *message)
{
    if (!value) { NSLog(@"FAIL: %@", message); exit(1); }
    passed++;
}
static FakeSources *Source(BOOL enabled, BOOL selected)
{
    FakeSources *source = [[[FakeSources alloc] init] autorelease];
    source.enabled = enabled; source.selected = selected;
    return source;
}
int main(void)
{
    @autoreleasepool {
        FakeSources *first = Source(NO, NO);
        Check(KKRefreshInputSource(first), @"first installation registers");
        Check([first.calls isEqual:@[@"read", @"register"]] && !first.enabled && !first.selected,
              @"first installation and intentionally disabled source stay disabled");
        FakeSources *active = Source(YES, YES);
        Check(KKRefreshInputSource(active), @"active source refresh succeeds");
        Check([active.calls isEqual:@[@"read", @"fallback", @"disable", @"stop", @"register", @"enable", @"select"]],
              @"switch away and disable before stopping; register before restoring");
        Check(active.enabled && active.selected, @"active selection restored");
        FakeSources *inactive = Source(YES, NO);
        Check(KKRefreshInputSource(inactive), @"enabled inactive source refresh succeeds");
        Check([inactive.calls isEqual:@[@"read", @"disable", @"stop", @"register", @"enable"]] && !inactive.selected,
              @"does not change a different selected input source");
        FakeSources *inconsistent = Source(NO, YES);
        Check(!KKRefreshInputSource(inconsistent) && [inconsistent.calls isEqual:@[@"read"]],
              @"inconsistent snapshot does not mutate sources");
        for (NSString *failure in @[@"read", @"fallback", @"disable", @"stop", @"register", @"enable", @"select"]) {
            FakeSources *source = Source(YES, YES); source.failOperation = failure;
            Check(!KKRefreshInputSource(source), [@"failure reported: " stringByAppendingString:failure]);
            BOOL early = [@[@"read", @"fallback", @"disable"] containsObject:failure];
            Check(source.enabled && source.selected == early, [@"enabled state recovered with safe selection: " stringByAppendingString:failure]);
            if (early) {
                Check(![source.calls containsObject:@"stop"] && ![source.calls containsObject:@"register"],
                      @"early failure prevents process termination and registration");
            }
        }
        FakeSources *partial = Source(YES, YES); partial.partialDisableFailure = YES;
        Check(!KKRefreshInputSource(partial), @"partial disable failure is reported");
        Check([partial.calls isEqual:@[@"read", @"fallback", @"disable", @"enable", @"select"]] &&
              partial.enabled && partial.selected, @"partially disabled source is restored without stopping process");
        FakeSources *partialSelect = Source(YES, YES); partialSelect.partialSelectFailure = YES;
        Check(!KKRefreshInputSource(partialSelect) && partialSelect.enabled && !partialSelect.selected &&
              [partialSelect.calls.lastObject isEqual:@"fallback"], @"partial final selection failure attempts fallback again");
        FakeSources *unrecoverable = Source(YES, YES); unrecoverable.persistentFailure = @"enable";
        Check(!KKRefreshInputSource(unrecoverable), @"persistent enable failure is reported");
        Check([unrecoverable.calls isEqual:@[@"read", @"fallback", @"disable", @"stop", @"register", @"enable", @"enable"]] &&
              !unrecoverable.enabled && !unrecoverable.selected, @"failed recovery preserves fallback and never reselects disabled KeyKey");
        FakeSources *unselected = Source(YES, NO); unselected.failOperation = @"register";
        Check(!KKRefreshInputSource(unselected) && unselected.enabled && !unselected.selected &&
              ![unselected.calls containsObject:@"fallback"] && ![unselected.calls containsObject:@"select"],
              @"inactive source recovery preserves the user's different selection");
        FakeSources *newFailure = Source(NO, NO); newFailure.failOperation = @"register";
        Check(!KKRefreshInputSource(newFailure) && [newFailure.calls isEqual:@[@"read", @"register"]],
              @"first install registration failure never enables or selects source");
        NSLog(@"PASS: %d input-source lifecycle checks (fake system; no user settings touched)", passed);
    }
}
