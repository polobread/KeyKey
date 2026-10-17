// Copyright (c) 2026 Chui-Ping Cheng. BSD-3-Clause; see ../../LICENSE.txt.
// Exercise real libproc descriptors using only this test's temporary database.
#define main KKUnusedToolMain
#import "../InputSourceTool.m"
#undef main
#include <fcntl.h>

static int passed;
static void Check(BOOL value, NSString *message) {
    if (!value) { NSLog(@"FAIL: %@", message); exit(1); } passed++;
}

int main(void) {
    @autoreleasepool {
        char directory[] = "/private/tmp/keykey-database-identity.XXXXXXXX";
        Check(mkdtemp(directory) != NULL, @"create private test directory");
        NSString *root = [NSString stringWithUTF8String:directory];
        NSString *path = [root stringByAppendingPathComponent:@"KeyKey.db"];
        Check([@"original" writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:NULL], @"create fixture");
        int fd = open(path.fileSystemRepresentation, O_RDONLY);
        Check(fd >= 0, @"hold original descriptor");
        Check(KKDatabaseStateForProcess(getpid(), path) == KKDatabaseCurrent, @"unchanged descriptor is current");
        Check([@"updated" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL], @"replace path atomically");
        Check(KKDatabaseStateForProcess(getpid(), path) == KKDatabaseReplaced, @"replaced vnode is detected despite identical pathname");
        close(fd);
        fd = open(path.fileSystemRepresentation, O_RDONLY);
        Check(fd >= 0 && KKDatabaseStateForProcess(getpid(), path) == KKDatabaseCurrent, @"reopened descriptor uses installed vnode");
        close(fd);
        Check(KKDatabaseStateForProcess(-1, path) == KKDatabaseUnknown, @"unreadable process cannot be verified");
        [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
        NSLog(@"PASS: %d database identity checks (temporary files and own process only)", passed);
    }
}
