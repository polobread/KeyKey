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
- (BOOL)readSelected:(BOOL *)selected;
- (BOOL)selectFallback;
- (BOOL)stopInstalledInputMethod;
- (BOOL)stopReplacedInputMethod;
@end

static BOOL KKPrepareInputSource(id<KKInputSourceOperations> system)
{
    BOOL selected = NO;
    if (![system readSelected:&selected]) return NO;
    if (selected && ![system selectFallback]) return NO;
    // Failure aborts preinstall while the old bundle is still intact.
    return [system stopInstalledInputMethod];
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

typedef NS_ENUM(NSInteger, KKProcessState) {
    KKProcessUnreadable, KKProcessRunning, KKProcessExited
};

// AppKit can retain a running snapshot after launchd reports a normal exit.
// Confirm the captured lifetime with the kernel instead of relying on its
// asynchronous terminated property. Unknown or changed identities fail closed.
static KKProcessState KKReadProcess(pid_t pid, const struct proc_bsdinfo *captured,
                                   struct proc_bsdinfo *snapshot)
{
    struct proc_bsdinfo current = {0};
    errno = 0;
    int bytes = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &current, sizeof(current));
    if (bytes <= 0 && errno == ESRCH) return KKProcessExited;
    if (bytes != sizeof(current) || current.pbi_pid != (uint32_t)pid ||
        current.pbi_uid != geteuid() || !current.pbi_start_tvsec ||
        current.pbi_start_tvusec >= 1000000) return KKProcessUnreadable;
    if (captured && (current.pbi_start_tvsec != captured->pbi_start_tvsec ||
                     current.pbi_start_tvusec != captured->pbi_start_tvusec))
        return KKProcessUnreadable;
    if (snapshot) *snapshot = current;
    return current.pbi_status == SZOMB ? KKProcessExited : KKProcessRunning;
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
    KKProcessState state = KKReadProcess(pid, NULL, &captured);
    if (state == KKProcessExited) return YES;
    if (state != KKProcessRunning) {
        fprintf(stderr, "KeyKey input source: could not verify old process %d; termination skipped.\n", pid);
        return NO;
    }
    // NSRunningApplication binds this request to the captured app identity.
    // Never signal a raw PID or retry termination against a reused PID.
    BOOL accepted = [app terminate];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    do {
        state = KKReadProcess(pid, &captured, NULL);
        if (state == KKProcessExited) return YES;
        if (state == KKProcessUnreadable) {
            fprintf(stderr, "KeyKey input source: old process %d identity or exit could not be verified.\n", pid);
            return NO;
        }
        if (!accepted) {
            fprintf(stderr, "KeyKey input source: old process %d rejected normal termination.\n", pid);
            return NO;
        }
        if ([deadline timeIntervalSinceNow] <= 0) break;
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    } while (YES);
    fprintf(stderr, "KeyKey input source: old process %d did not exit within deadline.\n", pid);
    return NO;
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
@end

static void KKDeadline(int signalNumber)
{
    (void)signalNumber;
    const char message[] = "KeyKey input source: setup timed out; this setup step is unconfirmed.\n";
    write(STDERR_FILENO, message, sizeof(message) - 1);
    _exit(124);
}

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        BOOL prepare = argc == 2 && strcmp(argv[1], "--prepare-upgrade") == 0;
        BOOL finish = argc == 2 && strcmp(argv[1], "--finish-upgrade") == 0;
        if ((!prepare && !finish) || geteuid() == 0) {
            fprintf(stderr, "Run KeyKeyInputSourceTool with --prepare-upgrade or --finish-upgrade in the logged-in user's GUI session, not as root.\n");
            return 64;
        }
        struct stat console;
        if (stat("/dev/console", &console) != 0 || console.st_uid != geteuid()) {
            fprintf(stderr, "KeyKey input source: console session changed; preparation skipped.\n");
            return 75;
        }
        if (finish) {
            NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:
                [KKInstalledPath stringByAppendingPathComponent:@"Contents/Info.plist"]];
            if (![info[@"CFBundleIdentifier"] isEqual:KKSourceID] ||
                ![info[@"TISInputSourceID"] isEqual:KKSourceID]) {
                fprintf(stderr, "KeyKey input source: installed bundle identity is invalid.\n");
                return 65;
            }
        }
        signal(SIGALRM, KKDeadline);
        alarm(20);
        KKSystemInputSources *system = [[[KKSystemInputSources alloc] init] autorelease];
        BOOL success = prepare ? KKPrepareInputSource(system) : [system stopReplacedInputMethod];
        alarm(0);
        return success ? 0 : 1;
    }
}
#endif
