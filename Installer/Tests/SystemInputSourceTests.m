// Copyright (c) 2026 Chui-Ping Cheng. BSD-3-Clause; see ../../LICENSE.txt.
// Compile the production adapter against fake TIS functions.
#define TISCreateInputSourceList KKFakeCreateList
#define TISEnableInputSource KKUnexpectedEnable
#define TISDisableInputSource KKUnexpectedDisable
#define TISSelectInputSource KKUnexpectedSelect
#define TISCopyCurrentKeyboardInputSource KKUnexpectedCurrent
#define TISRegisterInputSource KKFakeRegister
#define main KKUnusedToolMain
#import "../InputSourceTool.m"
#undef main

static BOOL nullList, absent;
static int passed, sourceQueries, unexpectedCalls;
static OSStatus registerStatus;
static void Check(BOOL value, NSString *message) {
    if (!value) { NSLog(@"FAIL: %@", message); exit(1); } passed++;
}
CFArrayRef KKFakeCreateList(CFDictionaryRef filter, Boolean all) {
    sourceQueries++;
    Check(all && [((NSDictionary *)filter)[(id)kTISPropertyInputSourceID] isEqual:KKSourceID] &&
          [(NSDictionary *)filter count] == 1, @"inclusive ID query accepts disabled sources too");
    if (nullList) return NULL;
    return (CFArrayRef)[(absent ? @[] : @[@{}]) retain];
}
TISInputSourceRef KKUnexpectedCurrent(void) { unexpectedCalls++; return NULL; }
OSStatus KKUnexpectedEnable(TISInputSourceRef source) { (void)source; unexpectedCalls++; return -50; }
OSStatus KKUnexpectedDisable(TISInputSourceRef source) { (void)source; unexpectedCalls++; return -50; }
OSStatus KKUnexpectedSelect(TISInputSourceRef source) { (void)source; unexpectedCalls++; return -50; }
OSStatus KKFakeRegister(CFURLRef url) {
    Check([[(NSURL *)url path] isEqual:KKInstalledPath], @"registration uses fixed installed path");
    return registerStatus;
}

@interface FakeApplication : NSObject
@property(getter=isTerminated) BOOL terminated;
@property BOOL acceptsTermination, exitsImmediately;
@property pid_t processIdentifier;
@property int terminateCalls;
@property(nonatomic, retain) NSURL *executableURL;
- (BOOL)terminate;
@end
@implementation FakeApplication
- (BOOL)terminate { self.terminateCalls++; if (self.exitsImmediately) self.terminated = YES; return self.acceptsTermination; }
- (void)dealloc { [_executableURL release]; [super dealloc]; }
@end

int main(void) {
    @autoreleasepool {
        KKSystemInputSources *system = [[[KKSystemInputSources alloc] init] autorelease];
        Check([system registerInstalledInputMethod], @"registration works without readable current source or enabled property");
        nullList = YES;
        Check(![system registerInstalledInputMethod], @"noErr with unavailable snapshot is a reported failure"); nullList = NO;
        absent = YES;
        Check(![system registerInstalledInputMethod], @"noErr without the installed source is a reported failure"); absent = NO;
        registerStatus = -50; int previousQueries = sourceQueries;
        Check(![system registerInstalledInputMethod] && sourceQueries == previousQueries,
              @"registration OSStatus failure cannot be mistaken for success"); registerStatus = noErr;
        Check(unexpectedCalls == 0, @"no current-source dependency or enable, disable, select operations");

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
        app.terminated = NO;
        app.executableURL = [NSURL fileURLWithPath:@"/tmp/chichi77 KeyKey.app/Contents/MacOS/chichi77 KeyKey"];
        [system setValue:@[app] forKey:@"_previousApplications"];
        Check([system stopInstalledInputMethod] && app.terminateCalls == 3, @"same bundle in another path is untouched");
        app.executableURL = [NSURL fileURLWithPath:[KKInstalledPath stringByAppendingPathComponent:@"Contents/MacOS/chichi77 KeyKey"]];
        Check([system stopInstalledInputMethod] && app.terminateCalls == 4,
              @"only captured installed process identity is retired");
        [system setValue:@[] forKey:@"_previousApplications"];
        app.terminated = NO;
        Check([system stopInstalledInputMethod] && app.terminateCalls == 4, @"no captured old process needs no termination");
        NSLog(@"PASS: %d system-adapter checks (fake TIS and process termination)", passed);
    }
}
