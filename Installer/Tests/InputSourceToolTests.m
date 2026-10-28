// Copyright (c) 2026 Chui-Ping Cheng. BSD-3-Clause; see ../../LICENSE.txt.
#define KEYKEY_INPUT_SOURCE_TEST 1
#import "../InputSourceTool.m"

@interface FakeSources : NSObject <KKInputSourceOperations>
@property BOOL selected, selectedReadable, fallbackSucceeds, stopSucceeds;
@property(nonatomic, retain) NSMutableArray *calls;
@end
@implementation FakeSources
- (id)init {
    if ((self = [super init])) {
        _calls = [NSMutableArray new];
        _selectedReadable = _fallbackSucceeds = _stopSucceeds = YES;
    }
    return self;
}
- (void)dealloc { [_calls release]; [super dealloc]; }
- (BOOL)stopInstalledInputMethod { [self.calls addObject:@"stop"]; return self.stopSucceeds; }
- (BOOL)stopReplacedInputMethod { return YES; }
- (BOOL)readSelected:(BOOL *)selected { [self.calls addObject:@"selected"]; *selected = self.selected; return self.selectedReadable; }
- (BOOL)selectFallback { [self.calls addObject:@"fallback"]; return self.fallbackSucceeds; }
@end

static int passed;
static void Check(BOOL value, NSString *message) {
    if (!value) { NSLog(@"FAIL: %@", message); exit(1); } passed++;
}
int main(void) {
    @autoreleasepool {
        FakeSources *source = [[[FakeSources alloc] init] autorelease];
        source.selected = YES;
        Check(KKPrepareInputSource(source) && [source.calls isEqual:@[@"selected", @"fallback", @"stop"]],
              @"active KeyKey switches to ASCII before normal exit");
        [source.calls removeAllObjects]; source.fallbackSucceeds = NO;
        Check(!KKPrepareInputSource(source) && ![source.calls containsObject:@"stop"],
              @"failed fallback blocks termination and replacement");
        [source.calls removeAllObjects]; source.selected = NO;
        Check(KKPrepareInputSource(source) && [source.calls isEqual:@[@"selected", @"stop"]],
              @"another selected input method is preserved");
        [source.calls removeAllObjects]; source.stopSucceeds = NO;
        Check(!KKPrepareInputSource(source), @"old process remaining alive blocks replacement");
        [source.calls removeAllObjects]; source.selectedReadable = NO;
        Check(!KKPrepareInputSource(source) && [source.calls isEqual:@[@"selected"]],
              @"unreadable selection blocks replacement without guessing");
        NSLog(@"PASS: %d input-source preparation checks (fake system)", passed);
    }
}
