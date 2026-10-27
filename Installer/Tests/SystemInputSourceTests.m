// Copyright (c) 2026 Chui-Ping Cheng. BSD-3-Clause; see ../../LICENSE.txt.
// Compile the production adapter against fake TIS functions.
#define TISCreateInputSourceList KKFakeCreateList
#define TISEnableInputSource KKFakeEnable
#define TISGetInputSourceProperty KKFakeProperty
#define TISDisableInputSource KKUnexpectedDisable
#define TISSelectInputSource KKFakeSelect
#define TISCopyCurrentKeyboardInputSource KKFakeCurrent
#define TISRegisterInputSource KKFakeRegister
#define proc_pidinfo KKFakeProcPidInfo
#define main KKUnusedToolMain
#import "../InputSourceTool.m"
#undef main

static BOOL nullList, absent, enabled, missingEnabled, enableChangesState = YES;
static BOOL selectionChangesState = YES;
static NSArray *fallbackSources;
static NSDictionary *currentSource;
static int passed, sourceQueries, unexpectedCalls, enableCalls, selectCalls, currentCalls;
static OSStatus registerStatus, enableStatus, selectStatus;
static BOOL databaseReplaced, processUnreadable;
static int processInfoError, processInfoBytes = sizeof(struct proc_bsdinfo);
static BOOL terminationRequested, kernelExitAfterRequest, kernelReuseAfterRequest, kernelUnknownAfterRequest;
int KKFakeProcPidInfo(int pid, int flavor, uint64_t arg, void *buffer, int size) {
    (void)arg;
    if (flavor != PROC_PIDTBSDINFO || size != sizeof(struct proc_bsdinfo)) { errno = EINVAL; return 0; }
    if (processInfoError || (terminationRequested && kernelUnknownAfterRequest)) {
        errno = processInfoError ?: EPERM; return 0;
    }
    if (terminationRequested && kernelExitAfterRequest) { errno = ESRCH; return 0; }
    struct proc_bsdinfo info = {0};
    info.pbi_pid = pid; info.pbi_uid = geteuid(); info.pbi_start_tvsec = 100;
    info.pbi_start_tvusec = terminationRequested && kernelReuseAfterRequest ? 2 : 1;
    memcpy(buffer, &info, sizeof(info));
    return processInfoBytes;
}

static void Check(BOOL value, NSString *message) {
    if (!value) { NSLog(@"FAIL: %@", message); exit(1); } passed++;
}
CFArrayRef KKFakeCreateList(CFDictionaryRef filter, Boolean all) {
    NSDictionary *properties = (NSDictionary *)filter;
    if (properties[(id)kTISPropertyInputSourceType]) {
        Check(!all && [properties[(id)kTISPropertyInputSourceType] isEqual:(id)kTISTypeKeyboardLayout] &&
              [properties[(id)kTISPropertyInputSourceIsASCIICapable] isEqual:@YES] &&
              [properties[(id)kTISPropertyInputSourceIsSelectCapable] isEqual:@YES] &&
              properties.count == 3, @"fallback query uses only enabled selectable ASCII layouts");
        return fallbackSources ? (CFArrayRef)[fallbackSources retain] : NULL;
    }
    sourceQueries++;
    Check(all && [properties[(id)kTISPropertyInputSourceID] isEqual:KKSourceID] &&
          properties.count == 1, @"inclusive ID query accepts disabled sources too");
    if (nullList) return NULL;
    return (CFArrayRef)[(absent ? @[] : @[@{}]) retain];
}
TISInputSourceRef KKFakeCurrent(void) { currentCalls++; return (TISInputSourceRef)[currentSource retain]; }
void *KKFakeProperty(TISInputSourceRef source, CFStringRef key) {
    if (CFEqual(key, kTISPropertyInputSourceID)) return [(NSDictionary *)source objectForKey:(id)key];
    if (missingEnabled || !CFEqual(key, kTISPropertyInputSourceIsEnabled)) return NULL;
    return (void *)(enabled ? kCFBooleanTrue : kCFBooleanFalse);
}
OSStatus KKFakeEnable(TISInputSourceRef source) {
    (void)source; enableCalls++;
    if (enableChangesState && enableStatus == noErr) enabled = YES;
    return enableStatus;
}
OSStatus KKUnexpectedDisable(TISInputSourceRef source) { (void)source; unexpectedCalls++; return -50; }
OSStatus KKFakeSelect(TISInputSourceRef source) {
    selectCalls++;
    if (selectStatus == noErr && selectionChangesState) currentSource = (NSDictionary *)source;
    return selectStatus;
}
OSStatus KKFakeRegister(CFURLRef url) {
    Check([[(NSURL *)url path] isEqual:KKInstalledPath], @"registration uses fixed installed path");
    return registerStatus;
}
@interface FakeSystemInputSources : KKSystemInputSources
@end
@implementation FakeSystemInputSources
- (KKDatabaseState)databaseStateForProcess:(pid_t)pid {
    (void)pid;
    return processUnreadable ? KKDatabaseUnknown : databaseReplaced ? KKDatabaseReplaced : KKDatabaseCurrent;
}
@end

@interface FakeApplication : NSObject
@property(getter=isTerminated) BOOL terminated;
@property BOOL acceptsTermination, exitsImmediately;
@property pid_t processIdentifier;
@property int terminateCalls;
@property(nonatomic, retain) NSURL *executableURL;
- (BOOL)terminate;
@end
@implementation FakeApplication
- (BOOL)terminate { terminationRequested = YES; self.terminateCalls++; if (self.exitsImmediately) self.terminated = YES; return self.acceptsTermination; }
- (void)dealloc { [_executableURL release]; [super dealloc]; }
@end

int main(void) {
    @autoreleasepool {
        KKSystemInputSources *system = [[[FakeSystemInputSources alloc] init] autorelease];
        Check([system registerInstalledInputMethod], @"registration works without readable current source or enabled property");
        nullList = YES;
        Check(![system registerInstalledInputMethod], @"noErr with unavailable snapshot is a reported failure"); nullList = NO;
        absent = YES;
        Check(![system registerInstalledInputMethod], @"noErr without the installed source is a reported failure"); absent = NO;
        registerStatus = -50; int previousQueries = sourceQueries;
        Check(![system registerInstalledInputMethod] && sourceQueries == previousQueries,
              @"registration OSStatus failure cannot be mistaken for success"); registerStatus = noErr;
        BOOL snapshot = YES;
        Check([system readEnabled:&snapshot] && !snapshot, @"pre-install disabled state is captured explicitly");
        enabled = YES;
        Check([system readEnabled:&snapshot] && snapshot, @"pre-install enabled state is captured explicitly");
        absent = YES;
        Check([system readEnabled:&snapshot] && !snapshot, @"first install has no enabled source"); absent = NO;
        nullList = YES;
        Check(![system readEnabled:&snapshot], @"unreadable state is unknown, not disabled"); nullList = NO;
        missingEnabled = YES;
        Check(![system readEnabled:&snapshot], @"missing enabled property cannot fabricate intent"); missingEnabled = NO;
        enabled = NO;
        Check([system enableInstalledInputMethod] && enabled, @"upgrade restores a source lost during replacement");
        enabled = NO; enableChangesState = NO;
        Check(![system enableInstalledInputMethod], @"enable noErr without state change is a failure");
        enableStatus = -50;
        Check(![system enableInstalledInputMethod], @"failed enable status is a failure");
        Check(unexpectedCalls == 0 && enableCalls == 3 && selectCalls == 0 && currentCalls == 0,
              @"postinstall restoration never disables or changes selection");
        BOOL selected = NO;
        Check(![system readSelected:&selected], @"unreadable pre-install selection prevents unsafe replacement");
        currentSource = @{};
        Check(![system readSelected:&selected], @"missing selected ID prevents unsafe replacement");
        currentSource = @{(id)kTISPropertyInputSourceID: @42};
        Check(![system readSelected:&selected], @"invalid selected ID prevents unsafe replacement");
        NSDictionary *keykey = @{(id)kTISPropertyInputSourceID: KKSourceID};
        NSDictionary *abc = @{(id)kTISPropertyInputSourceID: @"com.apple.keylayout.ABC"};
        currentSource = keykey;
        Check([system readSelected:&selected] && selected, @"preinstall recognizes selected KeyKey");
        fallbackSources = nil;
        Check(![system selectFallback] && selectCalls == 0, @"unavailable layout list cannot fabricate a fallback");
        fallbackSources = @[];
        Check(![system selectFallback] && selectCalls == 0, @"no enabled ASCII layout prevents unsafe replacement");
        fallbackSources = @[abc]; selectStatus = -50;
        Check(![system selectFallback] && currentSource == keykey, @"fallback OSStatus failure is reported");
        selectStatus = noErr; selectionChangesState = NO;
        Check(![system selectFallback] && currentSource == keykey, @"fallback noErr must verify selection changed");
        selectionChangesState = YES;
        Check([system selectFallback] && currentSource == abc && unexpectedCalls == 0,
              @"preinstall can select an existing ASCII layout without disabling any source");
        Check([system readSelected:&selected] && !selected, @"another selected source remains distinct from KeyKey");

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
        [system setValue:@[app] forKey:@"_previousApplications"];
        Check([system stopReplacedInputMethod] && app.terminateCalls == 4,
              @"postinstall preserves a process holding the current database");
        processUnreadable = YES;
        Check(![system stopReplacedInputMethod] && app.terminateCalls == 4,
              @"unreadable process state is reported without termination"); processUnreadable = NO;
        databaseReplaced = YES;
        app.executableURL = [NSURL fileURLWithPath:@"/tmp/chichi77 KeyKey.app/Contents/MacOS/chichi77 KeyKey"];
        Check([system stopReplacedInputMethod] && app.terminateCalls == 4,
              @"postinstall leaves other executable paths untouched");
        app.executableURL = [NSURL fileURLWithPath:[KKInstalledPath stringByAppendingPathComponent:@"Contents/MacOS/chichi77 KeyKey"]];
        app.acceptsTermination = NO; app.exitsImmediately = NO;
        Check(![system stopReplacedInputMethod] && app.terminateCalls == 5,
              @"stale process refusing normal exit is a setup failure");
        app.acceptsTermination = YES; app.exitsImmediately = YES;
        Check([system stopReplacedInputMethod] && app.terminateCalls == 6,
              @"process relaunched during replacement is normally retired after payload installation");
        app = [[[FakeApplication alloc] init] autorelease];
        app.processIdentifier = 12345;
        processInfoError = EPERM;
        Check(!KKStopApplication((NSRunningApplication *)app, 0) && !app.terminateCalls,
              @"unreadable kernel identity blocks replacement without termination");
        processInfoError = ESRCH;
        Check(KKStopApplication((NSRunningApplication *)app, 0) && !app.terminateCalls,
              @"already absent process succeeds despite stale AppKit state");
        processInfoError = 0; processInfoBytes = 0;
        Check(!KKStopApplication((NSRunningApplication *)app, 0) && !app.terminateCalls,
              @"empty kernel response without ESRCH cannot confirm exit");
        processInfoBytes = sizeof(struct proc_bsdinfo) - 1;
        Check(!KKStopApplication((NSRunningApplication *)app, 0) && !app.terminateCalls,
              @"partial kernel response cannot establish process identity");
        processInfoBytes = sizeof(struct proc_bsdinfo);
        terminationRequested = NO; kernelReuseAfterRequest = YES; app.acceptsTermination = YES;
        Check(KKStopApplication((NSRunningApplication *)app, 0) && app.terminateCalls == 1,
              @"PID reuse confirms captured lifetime ended without terminating its replacement");
        terminationRequested = NO; kernelReuseAfterRequest = NO; kernelExitAfterRequest = YES;
        app.acceptsTermination = NO;
        Check(KKStopApplication((NSRunningApplication *)app, 0) && app.terminateCalls == 2,
              @"exit racing with a rejected normal request is independently confirmed");
        terminationRequested = NO; kernelExitAfterRequest = NO; kernelUnknownAfterRequest = YES;
        app.acceptsTermination = YES;
        Check(!KKStopApplication((NSRunningApplication *)app, 0) && app.terminateCalls == 3,
              @"lost kernel visibility after request cannot fabricate an exit");
        NSLog(@"PASS: %d system-adapter checks (fake TIS and process termination)", passed);
    }
}
