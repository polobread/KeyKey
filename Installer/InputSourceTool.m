// Copyright (c) 2026 Chui-Ping Cheng. BSD-3-Clause; see ../LICENSE.txt.
#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#include <errno.h>
#include <signal.h>
#include <unistd.h>
#include <sys/stat.h>

static NSString *const KKSourceID = @"io.github.polobread.inputmethod.chichi77";
static NSString *const KKInstalledPath = @"/Library/Input Methods/chichi77 KeyKey.app";

// Keep policy independently testable without touching the user's input sources.
@protocol KKInputSourceOperations <NSObject>
- (BOOL)readEnabled:(BOOL *)enabled selected:(BOOL *)selected;
- (BOOL)selectFallback;
- (BOOL)applyEnabled:(BOOL)enabled;
- (BOOL)stopInstalledInputMethod;
- (BOOL)registerInstalledInputMethod;
- (BOOL)selectInputMethod;
@end

static BOOL KKRefreshInputSource(id<KKInputSourceOperations> system)
{
    BOOL enabled = NO, selected = NO;
    if (![system readEnabled:&enabled selected:&selected]) return NO;
    BOOL needsDisable = enabled;
    // Replacing an input-method bundle can briefly leave TIS reporting the
    // selected source as disabled. Selection is still proof that the user had
    // enabled KeyKey before the upgrade, so preserve that restore intent.
    if (selected) enabled = YES;
    BOOL switched = NO, disabled = NO, safeToReselect = YES;
    if (selected) {
        if (![system selectFallback]) return NO;
        switched = YES;
    }
    if (enabled) {
        disabled = YES; // A failing API may still have partially changed state.
        if (needsDisable && ![system applyEnabled:NO]) goto restore;
        safeToReselect = NO;
        if (![system stopInstalledInputMethod]) goto restore;
    }
    safeToReselect = NO;
    if (![system registerInstalledInputMethod]) goto restore;
    if (enabled && ![system applyEnabled:YES]) goto restore;
    disabled = NO;
    if (selected && ![system selectInputMethod]) {
        // Selection may have changed before its verification failed.
        [system selectFallback];
        goto restore;
    }
    return YES;

restore:
    // Best effort recovery; never remove other input sources or edit HIToolbox
    // preferences. Keep the working fallback if KeyKey cannot be enabled.
    if (!disabled || [system applyEnabled:YES]) {
        if (switched && safeToReselect) [system selectInputMethod];
    }
    return NO;
}

#ifndef KEYKEY_INPUT_SOURCE_TEST
@interface KKSystemInputSources : NSObject <KKInputSourceOperations>
@end

static TISInputSourceRef KKCopySource(void)
{
    NSDictionary *filter = @{(id)kTISPropertyInputSourceID: KKSourceID};
    CFArrayRef sources = TISCreateInputSourceList((CFDictionaryRef)filter, true);
    TISInputSourceRef source = sources && CFArrayGetCount(sources)
        ? (TISInputSourceRef)CFRetain(CFArrayGetValueAtIndex(sources, 0)) : NULL;
    if (sources) CFRelease(sources);
    return source;
}

static BOOL KKBoolean(TISInputSourceRef source, CFStringRef key)
{
    CFTypeRef value = source ? TISGetInputSourceProperty(source, key) : NULL;
    return value && CFGetTypeID(value) == CFBooleanGetTypeID() && CFBooleanGetValue(value);
}

static BOOL KKIsCurrentSource(TISInputSourceRef source)
{
    TISInputSourceRef current = TISCopyCurrentKeyboardInputSource();
    CFStringRef expected = source ? TISGetInputSourceProperty(source, kTISPropertyInputSourceID) : NULL;
    CFStringRef actual = current ? TISGetInputSourceProperty(current, kTISPropertyInputSourceID) : NULL;
    BOOL matches = expected && actual && CFEqual(expected, actual);
    if (current) CFRelease(current);
    return matches;
}

static BOOL KKStatus(OSStatus status, const char *operation)
{
    if (status != noErr) fprintf(stderr, "KeyKey input source: %s failed (%d).\n", operation, (int)status);
    return status == noErr;
}

static BOOL KKStopApplication(NSRunningApplication *app, NSTimeInterval timeout)
{
    if (app.terminated) return YES;
    pid_t pid = app.processIdentifier;
    if (pid <= 1 || pid == getpid()) {
        fprintf(stderr, "KeyKey input source: invalid old process identity; termination skipped.\n");
        return NO;
    }
    // NSRunningApplication retains the process identity. A raw kill(pid) could
    // target an unrelated process after PID reuse (or broadcast for pid -1).
    if (![app terminate]) {
        if (app.terminated) return YES;
        fprintf(stderr, "KeyKey input source: old process rejected normal termination.\n");
        return NO;
    }
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!app.terminated && [deadline timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    if (!app.terminated) fprintf(stderr, "KeyKey input source: old process did not exit within deadline.\n");
    return app.terminated;
}

@implementation KKSystemInputSources
- (BOOL)readEnabled:(BOOL *)enabled selected:(BOOL *)selected
{
    // A fresh, narrowly filtered TIS snapshot is authoritative. Reading the
    // private AppleEnabledInputSources preference is not a supported TIS API.
    NSDictionary *filter = @{(id)kTISPropertyInputSourceID: KKSourceID};
    CFArrayRef sources = TISCreateInputSourceList((CFDictionaryRef)filter, true);
    if (!sources) return NO;
    TISInputSourceRef current = TISCopyCurrentKeyboardInputSource();
    CFTypeRef currentID = current ? TISGetInputSourceProperty(current, kTISPropertyInputSourceID) : NULL;
    if (!currentID || CFGetTypeID(currentID) != CFStringGetTypeID()) {
        if (current) CFRelease(current);
        CFRelease(sources);
        return NO;
    }
    *enabled = NO; *selected = NO;
    BOOL currentIsKeyKey = CFEqual(currentID, (CFStringRef)KKSourceID);
    if (CFArrayGetCount(sources)) {
        TISInputSourceRef source = (TISInputSourceRef)CFArrayGetValueAtIndex(sources, 0);
        *enabled = KKBoolean(source, kTISPropertyInputSourceIsEnabled);
        *selected = currentIsKeyKey;
    } else if (currentIsKeyKey) {
        // Atomic package replacement can temporarily remove the old bundle
        // from an inclusive source-list query while it remains selected.
        // Preserve the selection signal and let registration recreate it.
        *enabled = NO;
        *selected = YES;
    }
    CFRelease(current);
    CFRelease(sources);
    return YES;
}
- (BOOL)selectFallback
{
    // Use an already-enabled ASCII keyboard layout, not another third-party
    // input method. Switching first lets IMK deactivate the old input session.
    NSDictionary *filter = @{
        (id)kTISPropertyInputSourceType: (id)kTISTypeKeyboardLayout,
        (id)kTISPropertyInputSourceIsASCIICapable: @YES,
        (id)kTISPropertyInputSourceIsSelectCapable: @YES
    };
    CFArrayRef sources = TISCreateInputSourceList((CFDictionaryRef)filter, false);
    BOOL success = NO;
    if (sources) {
        for (CFIndex i = 0; i < CFArrayGetCount(sources); i++) {
            TISInputSourceRef source = (TISInputSourceRef)CFArrayGetValueAtIndex(sources, i);
            if (TISSelectInputSource(source) == noErr && KKIsCurrentSource(source)) {
                success = YES;
                break;
            }
        }
        CFRelease(sources);
    }
    if (!success) fprintf(stderr, "KeyKey input source: no selectable enabled ASCII layout.\n");
    return success;
}
- (BOOL)applyEnabled:(BOOL)enabled
{
    TISInputSourceRef source = KKCopySource();
    if (!source) return NO;
    BOOL success = KKStatus(enabled ? TISEnableInputSource(source) : TISDisableInputSource(source),
                            enabled ? "enable" : "disable");
    CFRelease(source);
    if (!success) return NO;
    // Do not treat noErr alone as proof that the state actually changed.
    source = KKCopySource();
    success = source && KKBoolean(source, kTISPropertyInputSourceIsEnabled) == enabled;
    if (source) CFRelease(source);
    if (!success) fprintf(stderr, "KeyKey input source: enable state verification failed.\n");
    return success;
}
- (BOOL)stopInstalledInputMethod
{
    NSString *executable = [KKInstalledPath stringByAppendingPathComponent:@"Contents/MacOS/chichi77 KeyKey"];
    for (NSRunningApplication *app in [NSRunningApplication runningApplicationsWithBundleIdentifier:KKSourceID]) {
        if (![app.executableURL.path isEqualToString:executable]) continue;
        // The helper runs as the console user, never as root. The old source has
        // already been deselected and disabled; no global process-name kill.
        if (!KKStopApplication(app, 3)) return NO;
    }
    return YES;
}
- (BOOL)registerInstalledInputMethod
{
    // Apple TextInputSources.h documents this specifically for installers:
    // notify TIS of the installed bundle and rebuild its source caches.
    return KKStatus(TISRegisterInputSource((CFURLRef)[NSURL fileURLWithPath:KKInstalledPath]),
                    "register");
}
- (BOOL)selectInputMethod
{
    TISInputSourceRef source = KKCopySource();
    if (!source) return NO;
    BOOL success = KKStatus(TISSelectInputSource(source), "select") && KKIsCurrentSource(source);
    CFRelease(source);
    return success;
}
@end

static void KKDeadline(int signalNumber)
{
    (void)signalNumber;
    const char message[] = "KeyKey input source: registration timed out; use Keyboard settings to re-add KeyKey before logging out.\n";
    write(STDERR_FILENO, message, sizeof(message) - 1);
    _exit(124);
}

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        if (argc != 2 || strcmp(argv[1], "--refresh") != 0 || geteuid() == 0) {
            fprintf(stderr, "Run KeyKeyInputSourceTool --refresh in the logged-in user's GUI session, not as root.\n");
            return 64;
        }
        struct stat console;
        if (stat("/dev/console", &console) != 0 || console.st_uid != geteuid()) {
            fprintf(stderr, "KeyKey input source: console session changed; refresh skipped.\n");
            return 75;
        }
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:
            [KKInstalledPath stringByAppendingPathComponent:@"Contents/Info.plist"]];
        if (![info[@"CFBundleIdentifier"] isEqual:KKSourceID] ||
            ![info[@"TISInputSourceID"] isEqual:KKSourceID]) return 65;
        signal(SIGALRM, KKDeadline);
        alarm(20);
        BOOL success = KKRefreshInputSource([[[KKSystemInputSources alloc] init] autorelease]);
        alarm(0);
        if (!success) fprintf(stderr, "KeyKey input source: refresh incomplete; re-add KeyKey in Keyboard settings before logging out.\n");
        return success ? 0 : 1;
    }
}
#endif
