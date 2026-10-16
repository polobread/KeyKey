// Copyright (c) 2026 Chui-Ping Cheng. BSD-3-Clause; see ../../LICENSE.txt.
// Compile the production adapter against fake TIS functions, never real TIS.
#define TISCreateInputSourceList KKFakeCreateList
#define TISGetInputSourceProperty KKFakeProperty
#define TISCopyCurrentKeyboardInputSource KKFakeCurrent
#define TISEnableInputSource KKFakeEnable
#define TISDisableInputSource KKFakeDisable
#define TISSelectInputSource KKFakeSelect
#define TISRegisterInputSource KKFakeRegister
#define main KKUnusedToolMain
#import "../InputSourceTool.m"
#undef main

static NSDictionary *keykey, *fallback;
static NSString *current;
static BOOL nullList, absent, nullCurrent, missingCurrentID, enabled, changeEnabled, changeSelection;
static OSStatus enableStatus, selectStatus;
static int passed;
static void Check(BOOL value, NSString *message) {
    if (!value) { NSLog(@"FAIL: %@", message); exit(1); } passed++;
}
CFArrayRef KKFakeCreateList(CFDictionaryRef filter, Boolean all) {
    if (nullList) return NULL;
    NSDictionary *query = (NSDictionary *)filter;
    if (query[(id)kTISPropertyInputSourceID]) {
        Check(all && [query[(id)kTISPropertyInputSourceID] isEqual:KKSourceID], @"precise inclusive KeyKey query");
        return (CFArrayRef)[(absent ? @[] : @[keykey]) retain];
    }
    Check(!all && [query[(id)kTISPropertyInputSourceType] isEqual:(id)kTISTypeKeyboardLayout] &&
          [query[(id)kTISPropertyInputSourceIsASCIICapable] boolValue] &&
          [query[(id)kTISPropertyInputSourceIsSelectCapable] boolValue], @"fallback query excludes disabled and non-ASCII input methods");
    return (CFArrayRef)[@[fallback] retain];
}
void *KKFakeProperty(TISInputSourceRef source, CFStringRef property) {
    if (CFEqual(property, kTISPropertyInputSourceIsEnabled)) return (void *)(enabled ? kCFBooleanTrue : kCFBooleanFalse);
    return (void *)[(NSDictionary *)source objectForKey:(id)property];
}
TISInputSourceRef KKFakeCurrent(void) {
    if (nullCurrent) return NULL;
    if (missingCurrentID) return (TISInputSourceRef)[@{} retain];
    return (TISInputSourceRef)[@{(id)kTISPropertyInputSourceID:current} retain];
}
OSStatus KKFakeEnable(TISInputSourceRef source) { (void)source; if (changeEnabled) enabled = YES; return enableStatus; }
OSStatus KKFakeDisable(TISInputSourceRef source) { (void)source; if (changeEnabled) enabled = NO; return enableStatus; }
OSStatus KKFakeSelect(TISInputSourceRef source) {
    if (changeSelection) current = [(NSDictionary *)source objectForKey:(id)kTISPropertyInputSourceID];
    return selectStatus;
}
OSStatus KKFakeRegister(CFURLRef url) {
    Check([[(NSURL *)url path] isEqual:KKInstalledPath], @"registration uses fixed installed path"); return noErr;
}

@interface FakeApplication : NSObject
@property(getter=isTerminated) BOOL terminated;
@property BOOL acceptsTermination, exitsImmediately;
@property pid_t processIdentifier;
@property int terminateCalls;
- (BOOL)terminate;
@end
@implementation FakeApplication
- (BOOL)terminate { self.terminateCalls++; if (self.exitsImmediately) self.terminated = YES; return self.acceptsTermination; }
@end

int main(void) {
    @autoreleasepool {
        keykey = @{(id)kTISPropertyInputSourceID:KKSourceID};
        fallback = @{(id)kTISPropertyInputSourceID:@"com.apple.keylayout.ABC"};
        current = KKSourceID; enabled = YES; changeEnabled = YES; changeSelection = YES;
        KKSystemInputSources *system = [[[KKSystemInputSources alloc] init] autorelease];
        BOOL wasEnabled = NO, selected = NO;
        Check([system readEnabled:&wasEnabled selected:&selected] && wasEnabled && selected, @"read enabled/current source");
        nullList = YES; Check(![system readEnabled:&wasEnabled selected:&selected], @"NULL snapshot fails safely");
        Check(![system selectFallback], @"NULL fallback list fails safely"); nullList = NO;
        nullCurrent = YES; Check(![system readEnabled:&wasEnabled selected:&selected], @"unreadable current source rejects snapshot"); nullCurrent = NO;
        missingCurrentID = YES; Check(![system readEnabled:&wasEnabled selected:&selected], @"missing current ID rejects snapshot"); missingCurrentID = NO;
        absent = YES;
        Check([system readEnabled:&wasEnabled selected:&selected] && !wasEnabled && selected,
              @"selected KeyKey missing from source list preserves its selection signal");
        current = fallback[(id)kTISPropertyInputSourceID];
        Check([system readEnabled:&wasEnabled selected:&selected] && !wasEnabled && !selected, @"absent source is disabled/unselected");
        Check(![system applyEnabled:YES] && ![system selectInputMethod], @"missing source cannot be enabled or selected"); absent = NO;
        Check([system selectFallback] && [current isEqual:fallback[(id)kTISPropertyInputSourceID]], @"fallback selection verified");
        current = KKSourceID; changeSelection = NO;
        Check(![system selectFallback], @"noErr without actual fallback selection fails");
        current = fallback[(id)kTISPropertyInputSourceID];
        Check(![system selectInputMethod], @"noErr without KeyKey selection fails"); changeSelection = YES;
        Check([system applyEnabled:NO] && !enabled && [system applyEnabled:YES] && enabled, @"enable and disable verified with fresh snapshots");
        changeEnabled = NO; Check(![system applyEnabled:NO], @"noErr without disable state change fails");
        enabled = NO; Check(![system applyEnabled:YES], @"noErr without enable state change fails");
        changeEnabled = YES; enableStatus = -50; Check(![system applyEnabled:YES], @"API failure stays failure despite partial state change"); enableStatus = noErr;
        Check([system registerInstalledInputMethod], @"registration result returned");
        FakeApplication *app = [[[FakeApplication alloc] init] autorelease];
        app.processIdentifier = -1;
        Check(!KKStopApplication((NSRunningApplication *)app, 0) && !app.terminateCalls, @"missing PID never terminates");
        app.processIdentifier = 0;
        Check(!KKStopApplication((NSRunningApplication *)app, 0) && !app.terminateCalls, @"zero PID never terminates");
        app.processIdentifier = getpid();
        Check(!KKStopApplication((NSRunningApplication *)app, 0) && !app.terminateCalls, @"self never terminates");
        app.terminated = YES;
        Check(KKStopApplication((NSRunningApplication *)app, 0) && !app.terminateCalls, @"already exited process needs no termination");
        app.terminated = NO; app.processIdentifier = 12345;
        Check(!KKStopApplication((NSRunningApplication *)app, 0) && app.terminateCalls == 1, @"normal termination rejection is failure");
        app.acceptsTermination = YES;
        Check(!KKStopApplication((NSRunningApplication *)app, 0) && app.terminateCalls == 2, @"termination acceptance without exit times out");
        app.exitsImmediately = YES;
        Check(KKStopApplication((NSRunningApplication *)app, 0) && app.terminateCalls == 3, @"confirmed normal exit succeeds");
        NSLog(@"PASS: %d system-adapter checks (fake TIS and application; no user settings or processes touched)", passed);
    }
}
