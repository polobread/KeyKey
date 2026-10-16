// Copyright (c) 2026 Chui-Ping Cheng. BSD-3-Clause; see ../LICENSE.txt.
#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#include <signal.h>
#include <unistd.h>
#include <sys/stat.h>

static NSString *const KKSourceID = @"io.github.polobread.inputmethod.chichi77";
static NSString *const KKInstalledPath = @"/Library/Input Methods/chichi77 KeyKey.app";

// Keep policy independently testable without touching the user's input sources.
@protocol KKInputSourceOperations <NSObject>
- (BOOL)stopInstalledInputMethod;
- (BOOL)registerInstalledInputMethod;
@end

static BOOL KKRefreshInputSource(id<KKInputSourceOperations> system)
{
    // Registration does not require reading the current selection. In
    // particular, a transient post-replacement snapshot is not evidence that
    // the user disabled KeyKey. Leave enabling and selection entirely to TIS
    // and the user's Keyboard settings, including when a step fails or hangs.
    if (![system registerInstalledInputMethod]) return NO;
    return [system stopInstalledInputMethod];
}

#ifndef KEYKEY_INPUT_SOURCE_TEST
@interface KKSystemInputSources : NSObject <KKInputSourceOperations> {
    NSArray *_previousApplications;
}
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
- (id)init
{
    if ((self = [super init])) {
        // Retain process identities before registration: a process macOS
        // launches afterwards belongs to the new installation.
        _previousApplications = [[NSRunningApplication runningApplicationsWithBundleIdentifier:KKSourceID] copy];
    }
    return self;
}
- (void)dealloc
{
    [_previousApplications release];
    [super dealloc];
}
- (BOOL)stopInstalledInputMethod
{
    NSString *executable = [KKInstalledPath stringByAppendingPathComponent:@"Contents/MacOS/chichi77 KeyKey"];
    for (NSRunningApplication *app in _previousApplications) {
        if (![app.executableURL.path isEqualToString:executable]) continue;
        // The helper runs as the console user, never as root. Let macOS
        // relaunch the installed version on demand; no global process kill.
        if (!KKStopApplication(app, 3)) return NO;
    }
    return YES;
}
- (BOOL)registerInstalledInputMethod
{
    if (!KKStatus(TISRegisterInputSource((CFURLRef)[NSURL fileURLWithPath:KKInstalledPath]),
                  "register")) return NO;
    // noErr is only registration's result, not proof that the new source can
    // be found. Disabled sources are valid too; enabling remains the user's
    // choice. This does not verify an IMK text session or actual typing.
    TISInputSourceRef source = KKCopySource();
    if (!source) {
        fprintf(stderr, "KeyKey input source: register returned noErr but the installed source is not available.\n");
        return NO;
    }
    CFRelease(source);
    fprintf(stderr, "KeyKey input source: registered source found.\n");
    return YES;
}
@end

static void KKDeadline(int signalNumber)
{
    (void)signalNumber;
    const char message[] = "KeyKey input source: setup timed out; input-source enabling and selection were not changed by this tool.\n";
    write(STDERR_FILENO, message, sizeof(message) - 1);
    _exit(124);
}

static void KKShowSetupWarning(void)
{
    BOOL chinese = [[[NSLocale preferredLanguages] firstObject] hasPrefix:@"zh"];
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = chinese ? @"琦琦輸入法需要確認" : @"Check KeyKey input-source setup";
    alert.informativeText = chinese
        ? @"檔案已安裝，但目前帳號的輸入法準備未完成。\n\n請從輸入法選單先選 ABC，再選「琦琦輸入法」或「chichi77 KeyKey」，到「文字編輯」試打。\n\n若找不到項目，開啟「系統設定 → 鍵盤 → 文字輸入 → 編輯… → ＋」，從「繁體中文」加入琦琦。仍無法使用時，請回報安裝檔名與 macOS 版本。"
        : @"The files were installed, but setup for this account did not finish.\n\nSelect ABC, then chichi77 KeyKey from the Input menu, and try typing in TextEdit.\n\nIf KeyKey is missing, open System Settings → Keyboard → Text Input → Edit → + and add it under Traditional Chinese. If it still does not work, report the package name and macOS version.";
    [alert addButtonWithTitle:chinese ? @"開啟鍵盤設定" : @"Open Keyboard Settings"];
    [alert addButtonWithTitle:chinese ? @"稍後" : @"Later"];
    [NSApp activateIgnoringOtherApps:YES];
    if ([alert runModal] == NSAlertFirstButtonReturn)
        [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:
            @"x-apple.systempreferences:com.apple.Keyboard-Settings.extension"]];
}

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        BOOL refresh = argc == 2 && strcmp(argv[1], "--refresh") == 0;
        BOOL warning = argc == 2 && strcmp(argv[1], "--show-setup-warning") == 0;
        if ((!refresh && !warning) || geteuid() == 0) {
            fprintf(stderr, "Run KeyKeyInputSourceTool --refresh or --show-setup-warning in the logged-in user's GUI session, not as root.\n");
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
            ![info[@"TISInputSourceID"] isEqual:KKSourceID]) {
            fprintf(stderr, "KeyKey input source: installed bundle identity is invalid.\n");
            return 65;
        }
        if (warning) { KKShowSetupWarning(); return 0; }
        signal(SIGALRM, KKDeadline);
        alarm(20);
        BOOL success = KKRefreshInputSource([[[KKSystemInputSources alloc] init] autorelease]);
        alarm(0);
        fprintf(stderr, "KeyKey input source: setup %s; choose KeyKey from the Input menu and verify typing.\n",
                success ? "completed" : "incomplete");
        return success ? 0 : 1;
    }
}
#endif
