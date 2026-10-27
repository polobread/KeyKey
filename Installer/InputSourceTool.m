// Copyright (c) 2026 Chui-Ping Cheng. BSD-3-Clause; see ../LICENSE.txt.
#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#include <signal.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/proc.h>
#include <libproc.h>
#include <errno.h>

static NSString *const KKSourceID = @"io.github.polobread.inputmethod.chichi77";
static NSString *const KKInstalledPath = @"/Library/Input Methods/chichi77 KeyKey.app";

// Keep policy independently testable without touching the user's input sources.
@protocol KKInputSourceOperations <NSObject>
- (BOOL)readEnabled:(BOOL *)enabled;
- (BOOL)enableInstalledInputMethod;
- (BOOL)readSelected:(BOOL *)selected;
- (BOOL)selectFallback;
- (BOOL)stopInstalledInputMethod;
- (BOOL)stopReplacedInputMethod;
- (BOOL)registerInstalledInputMethod;
@end

static BOOL KKPrepareInputSource(id<KKInputSourceOperations> system, BOOL *enabled)
{
    BOOL selected = NO;
    if (![system readEnabled:enabled] || ![system readSelected:&selected]) return NO;
    if (selected) *enabled = YES;
    if (selected && ![system selectFallback]) return NO;
    // Failure aborts preinstall while the old bundle is still intact.
    return [system stopInstalledInputMethod];
}

static BOOL KKRefreshInputSource(id<KKInputSourceOperations> system, BOOL restoreEnabled)
{
    // Restore only the intent captured by preinstall, before replacement.
    // Never infer that intent from the new bundle's initial TIS state.
    // macOS can relaunch IMK between preinstall and payload replacement. Retire
    // only processes holding a replaced database, keeping genuine new sessions.
    if (![system stopReplacedInputMethod]) return NO;
    if (![system registerInstalledInputMethod]) return NO;
    return !restoreEnabled || [system enableInstalledInputMethod];
}

#ifndef KEYKEY_INPUT_SOURCE_TEST
typedef NS_ENUM(NSInteger, KKDatabaseState) {
    KKDatabaseUnknown, KKDatabaseCurrent, KKDatabaseReplaced
};

@interface KKSystemInputSources : NSObject <KKInputSourceOperations> {
    NSArray *_previousApplications;
}
- (KKDatabaseState)databaseStateForProcess:(pid_t)pid;
@end

static TISInputSourceRef KKCopySource(BOOL *readable)
{
    NSDictionary *filter = @{(id)kTISPropertyInputSourceID: KKSourceID};
    CFArrayRef sources = TISCreateInputSourceList((CFDictionaryRef)filter, true);
    if (readable) *readable = sources != NULL;
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

typedef NS_ENUM(NSInteger, KKProcessState) {
    KKProcessUnreadable, KKProcessRunning, KKProcessExited
};

// AppKit's terminated property is updated asynchronously and can remain false
// in this command-line helper after launchd has already reaped the process.
// Read kernel state instead, retaining the start time to distinguish PID reuse.
static KKProcessState KKReadProcess(pid_t pid, struct proc_bsdinfo *info)
{
    errno = 0;
    int bytes = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, info, sizeof(*info));
    if (bytes <= 0 && errno == ESRCH) return KKProcessExited;
    if (bytes != sizeof(*info) || info->pbi_pid != (uint32_t)pid ||
        info->pbi_uid != geteuid()) return KKProcessUnreadable;
    if (info->pbi_status == SZOMB) return KKProcessExited;
    if (!info->pbi_start_tvsec || info->pbi_start_tvusec >= 1000000) return KKProcessUnreadable;
    return KKProcessRunning;
}

static BOOL KKCapturedProcessExited(pid_t pid, const struct proc_bsdinfo *captured)
{
    struct proc_bsdinfo current = {0};
    KKProcessState state = KKReadProcess(pid, &current);
    return state == KKProcessExited || (state == KKProcessRunning &&
        (current.pbi_start_tvsec != captured->pbi_start_tvsec ||
         current.pbi_start_tvusec != captured->pbi_start_tvusec));
}

static BOOL KKStopApplication(NSRunningApplication *app, NSTimeInterval timeout)
{
    if (app.terminated) return YES;
    pid_t pid = app.processIdentifier;
    if (pid <= 1 || pid == getpid()) {
        fprintf(stderr, "KeyKey input source: invalid old process identity; termination skipped.\n");
        return NO;
    }
    struct proc_bsdinfo captured = {0};
    KKProcessState state = KKReadProcess(pid, &captured);
    if (state == KKProcessExited) return YES;
    if (state != KKProcessRunning) {
        fprintf(stderr, "KeyKey input source: could not verify old process %d; termination skipped.\n", pid);
        return NO;
    }
    // Keep the identity-bound normal AppKit request; never signal a raw PID.
    // Kernel observation confirms only this captured lifetime's exit. A reused
    // PID belongs to a different process and must not receive another request.
    if (![app terminate]) {
        if (app.terminated || KKCapturedProcessExited(pid, &captured)) return YES;
        fprintf(stderr, "KeyKey input source: old process %d rejected normal termination.\n", pid);
        return NO;
    }
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!app.terminated && !KKCapturedProcessExited(pid, &captured) &&
           [deadline timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    BOOL exited = app.terminated || KKCapturedProcessExited(pid, &captured);
    if (!exited) fprintf(stderr, "KeyKey input source: old process %d did not exit within deadline.\n", pid);
    return exited;
}

// Inspect only the installed input method's database descriptor. Comparing the
// actual vnode with stat(path) catches a process relaunched during replacement,
// even when both bundles advertise the same version and have identical bytes.
static KKDatabaseState KKDatabaseStateForProcess(pid_t pid, NSString *path)
{
    struct stat installed;
    if (stat(path.fileSystemRepresentation, &installed) != 0) return KKDatabaseUnknown;
    int size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, NULL, 0);
    if (size <= 0) return KKDatabaseUnknown;
    size += 32 * sizeof(struct proc_fdinfo);
    struct proc_fdinfo *fds = malloc(size);
    if (!fds) return KKDatabaseUnknown;
    int bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, fds, size);
    KKDatabaseState result = bytes > 0 && bytes < size ? KKDatabaseCurrent : KKDatabaseUnknown;
    for (int i = 0; bytes <= size && i < bytes / (int)sizeof(*fds); i++) {
        if (fds[i].proc_fdtype != PROX_FDTYPE_VNODE) continue;
        struct vnode_fdinfowithpath vnode = {0};
        int count = proc_pidfdinfo(pid, fds[i].proc_fd, PROC_PIDFDVNODEPATHINFO, &vnode, sizeof(vnode));
        if (count != sizeof(vnode)) {
            // A descriptor closed while inspecting is harmless. Other failures
            // cannot establish that the database is current.
            if (errno != EBADF && errno != ENOENT) result = KKDatabaseUnknown;
            continue;
        }
        if (strcmp(vnode.pvip.vip_path, path.fileSystemRepresentation) != 0) continue;
        struct vinfo_stat opened = vnode.pvip.vip_vi.vi_stat;
        if (opened.vst_dev != (uint32_t)installed.st_dev || opened.vst_ino != installed.st_ino) {
            result = KKDatabaseReplaced;
            break;
        }
    }
    free(fds);
    return result;
}

@implementation KKSystemInputSources
- (BOOL)readSelected:(BOOL *)selected
{
    TISInputSourceRef current = TISCopyCurrentKeyboardInputSource();
    CFTypeRef identifier = current ? TISGetInputSourceProperty(current, kTISPropertyInputSourceID) : NULL;
    BOOL valid = identifier && CFGetTypeID(identifier) == CFStringGetTypeID();
    if (valid) *selected = CFEqual(identifier, (CFStringRef)KKSourceID);
    if (current) CFRelease(current);
    if (!valid) fprintf(stderr, "KeyKey input source: pre-install selection unavailable; replacement must wait.\n");
    return valid;
}
- (BOOL)selectFallback
{
    NSDictionary *filter = @{
        (id)kTISPropertyInputSourceType: (id)kTISTypeKeyboardLayout,
        (id)kTISPropertyInputSourceIsASCIICapable: @YES,
        (id)kTISPropertyInputSourceIsSelectCapable: @YES
    };
    CFArrayRef sources = TISCreateInputSourceList((CFDictionaryRef)filter, false);
    BOOL selected = NO;
    for (CFIndex i = 0; sources && i < CFArrayGetCount(sources); i++) {
        TISInputSourceRef source = (TISInputSourceRef)CFArrayGetValueAtIndex(sources, i);
        if (TISSelectInputSource(source) != noErr) continue;
        TISInputSourceRef current = TISCopyCurrentKeyboardInputSource();
        CFTypeRef expected = TISGetInputSourceProperty(source, kTISPropertyInputSourceID);
        CFTypeRef actual = current ? TISGetInputSourceProperty(current, kTISPropertyInputSourceID) : NULL;
        selected = expected && actual && CFEqual(expected, actual);
        if (current) CFRelease(current);
        if (selected) break;
    }
    if (sources) CFRelease(sources);
    if (!selected) fprintf(stderr, "KeyKey input source: enabled ASCII fallback could not be selected; replacement must wait.\n");
    return selected;
}
- (BOOL)readEnabled:(BOOL *)enabled
{
    BOOL readable = NO;
    TISInputSourceRef source = KKCopySource(&readable);
    if (!readable) {
        fprintf(stderr, "KeyKey input source: enabled snapshot unavailable.\n");
        return NO;
    }
    *enabled = NO;
    if (!source) return YES; // No registered source before a first install.
    CFTypeRef value = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled);
    BOOL valid = value && CFGetTypeID(value) == CFBooleanGetTypeID();
    if (valid) *enabled = CFBooleanGetValue(value);
    CFRelease(source);
    if (!valid) fprintf(stderr, "KeyKey input source: enabled property unavailable.\n");
    return valid;
}
- (BOOL)enableInstalledInputMethod
{
    TISInputSourceRef source = KKCopySource(NULL);
    if (!source) {
        fprintf(stderr, "KeyKey input source: previously enabled source is unavailable.\n");
        return NO;
    }
    BOOL success = KKStatus(TISEnableInputSource(source), "restore enabled");
    CFRelease(source);
    if (!success) return NO;
    BOOL enabled = NO;
    if (![self readEnabled:&enabled] || !enabled) {
        fprintf(stderr, "KeyKey input source: enabled restoration did not verify.\n");
        return NO;
    }
    fprintf(stderr, "KeyKey input source: pre-install enabled state restored.\n");
    return YES;
}
- (id)init
{
    if ((self = [super init])) {
        // Retain process identities at the start of preinstall preparation.
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
- (BOOL)stopReplacedInputMethod
{
    NSString *executable = [KKInstalledPath stringByAppendingPathComponent:@"Contents/MacOS/chichi77 KeyKey"];
    for (NSRunningApplication *app in _previousApplications) {
        if (app.terminated || ![app.executableURL.path isEqualToString:executable]) continue;
        KKDatabaseState state = [self databaseStateForProcess:app.processIdentifier];
        if (app.terminated) continue;
        if (state == KKDatabaseUnknown) {
            fprintf(stderr, "KeyKey input source: running database identity could not be verified.\n");
            return NO;
        }
        if (state == KKDatabaseReplaced) {
            fprintf(stderr, "KeyKey input source: retiring process holding the replaced database.\n");
            if (!KKStopApplication(app, 3)) return NO;
        }
    }
    return YES;
}
- (KKDatabaseState)databaseStateForProcess:(pid_t)pid
{
    NSString *database = [KKInstalledPath stringByAppendingPathComponent:@"Contents/Resources/Databases/KeyKey.db"];
    return KKDatabaseStateForProcess(pid, database);
}
- (BOOL)registerInstalledInputMethod
{
    if (!KKStatus(TISRegisterInputSource((CFURLRef)[NSURL fileURLWithPath:KKInstalledPath]),
                  "register")) return NO;
    // noErr is only registration's result, not proof that the new source can
    // be found. Disabled sources are valid too; only preinstall's saved enabled
    // intent can authorize restoration. This does not verify actual typing.
    TISInputSourceRef source = KKCopySource(NULL);
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
    const char message[] = "KeyKey input source: setup timed out; this setup step is unconfirmed.\n";
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
        BOOL restoreEnabled = argc == 2 && strcmp(argv[1], "--refresh-enabled") == 0;
        BOOL refresh = restoreEnabled || (argc == 2 && strcmp(argv[1], "--refresh") == 0);
        BOOL snapshot = argc == 2 && strcmp(argv[1], "--snapshot") == 0;
        BOOL prepare = argc == 2 && strcmp(argv[1], "--prepare-upgrade") == 0;
        BOOL warning = argc == 2 && strcmp(argv[1], "--show-setup-warning") == 0;
        if ((!refresh && !warning && !snapshot && !prepare) || geteuid() == 0) {
            fprintf(stderr, "Run KeyKeyInputSourceTool with a supported setup command in the logged-in user's GUI session, not as root.\n");
            return 64;
        }
        struct stat console;
        if (stat("/dev/console", &console) != 0 || console.st_uid != geteuid()) {
            fprintf(stderr, "KeyKey input source: console session changed; refresh skipped.\n");
            return 75;
        }
        if (snapshot || prepare) {
            signal(SIGALRM, KKDeadline); alarm(20);
            BOOL enabled = NO;
            KKSystemInputSources *system = [[[KKSystemInputSources alloc] init] autorelease];
            BOOL success = prepare ? KKPrepareInputSource(system, &enabled) : [system readEnabled:&enabled];
            alarm(0);
            if (success) printf("%s\n", enabled ? "enabled" : "disabled");
            return success ? 0 : 1;
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
        BOOL success = KKRefreshInputSource([[[KKSystemInputSources alloc] init] autorelease], restoreEnabled);
        alarm(0);
        fprintf(stderr, "KeyKey input source: setup %s; choose KeyKey from the Input menu and verify typing.\n",
                success ? "completed" : "incomplete");
        return success ? 0 : 1;
    }
}
#endif
