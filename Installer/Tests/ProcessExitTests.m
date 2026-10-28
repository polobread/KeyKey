// Copyright (c) 2026 Chui-Ping Cheng. BSD-3-Clause; see ../../LICENSE.txt.
// Real kernel process exits with deliberately stale AppKit state. Own children only.
#define main KKUnusedToolMain
#import "../InputSourceTool.m"
#undef main
#include <sys/wait.h>

static int passed;
static void Check(BOOL value, NSString *message) {
    if (!value) { NSLog(@"FAIL: %@", message); exit(1); }
    passed++;
}

@interface OwnedApplication : NSObject
@property pid_t processIdentifier;
@property int commandFD, terminateCalls;
@property BOOL acceptsTermination, exitsOnRequest, reportsTerminationOnRequest;
- (BOOL)isTerminated;
- (BOOL)terminate;
@end
@implementation OwnedApplication
- (BOOL)isTerminated { return self.terminateCalls && self.reportsTerminationOnRequest; }
- (BOOL)terminate {
    self.terminateCalls++;
    if (self.acceptsTermination && self.exitsOnRequest && self.commandFD >= 0) {
        char command = 'q';
        if (write(self.commandFD, &command, 1) != 1) return NO;
        close(self.commandFD); self.commandFD = -1;
    }
    return self.acceptsTermination;
}
@end

static OwnedApplication *Child(BOOL accepts, BOOL exits) {
    int commands[2];
    Check(pipe(commands) == 0, @"create owned child's command pipe");
    pid_t pid = fork();
    Check(pid >= 0, @"fork owned child");
    if (pid == 0) {
        close(commands[1]);
        char command;
        while (read(commands[0], &command, 1) < 0 && errno == EINTR) {}
        _exit(0);
    }
    close(commands[0]);
    OwnedApplication *app = [[[OwnedApplication alloc] init] autorelease];
    app.processIdentifier = pid; app.commandFD = commands[1];
    app.acceptsTermination = accepts; app.exitsOnRequest = exits;
    return app;
}
static void Reap(OwnedApplication *app) {
    if (app.commandFD >= 0) {
        char command = 'q';
        write(app.commandFD, &command, 1);
        close(app.commandFD); app.commandFD = -1;
    }
    int status = 0;
    Check(waitpid(app.processIdentifier, &status, 0) == app.processIdentifier &&
          WIFEXITED(status) && WEXITSTATUS(status) == 0, @"reap owned child normally");
}
int main(void) {
    @autoreleasepool {
        signal(SIGPIPE, SIG_IGN); // Only this test's pipes and children.
        OwnedApplication *app = Child(YES, YES);
        BOOL stopped = KKStopApplication((NSRunningApplication *)app, 1);
        Reap(app);
        Check(stopped && app.terminateCalls == 1 && !app.isTerminated,
              @"kernel-confirmed exit succeeds even while AppKit keeps reporting running");

        app = Child(YES, NO);
        Reap(app);
        Check(KKStopApplication((NSRunningApplication *)app, 0) && app.terminateCalls == 0,
              @"already reaped process succeeds without sending a new termination request");

        app = Child(NO, NO);
        stopped = KKStopApplication((NSRunningApplication *)app, 0);
        int status = 0;
        BOOL running = waitpid(app.processIdentifier, &status, WNOHANG) == 0;
        Reap(app);
        Check(!stopped && running && app.terminateCalls == 1,
              @"live process rejecting normal termination still blocks replacement");

        app = Child(YES, NO);
        stopped = KKStopApplication((NSRunningApplication *)app, 0.1);
        running = waitpid(app.processIdentifier, &status, WNOHANG) == 0;
        Reap(app);
        Check(!stopped && running && app.terminateCalls == 1,
              @"accepted request without a real exit still blocks replacement");
        app = Child(YES, NO);
        app.reportsTerminationOnRequest = YES;
        stopped = KKStopApplication((NSRunningApplication *)app, 0.1);
        running = waitpid(app.processIdentifier, &status, WNOHANG) == 0;
        Reap(app);
        Check(!stopped && running && app.isTerminated && app.terminateCalls == 1,
              @"an early AppKit flag cannot approve replacement while the captured child is alive");
        NSLog(@"PASS: %d native process-exit checks (own children; no TIS or installed IMK)", passed);
    }
}
