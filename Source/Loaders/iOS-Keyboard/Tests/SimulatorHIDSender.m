// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
// Host-only Simulator diagnostic tool. Never linked into the App or extension.
// Uses the selected Xcode's private SimulatorKit API; runtime availability is
// checked, so an incompatible installation fails rather than posting elsewhere.
// NSEvent is only message data: no CGEventPost or global macOS keyboard events.
#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#include <dlfcn.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

// Signatures were read from this Xcode installation's Objective-C runtime
// method encodings. No private struct layout or Swift ABI is assumed.
@interface NSObject (LocalSimulatorHID)
+ (id)sharedServiceContextForDeveloperDir:(NSString *)directory error:(NSError **)error;
- (id)defaultDeviceSetWithError:(NSError **)error;
- (NSArray *)availableDevices;
- (NSUUID *)UDID;
- (NSString *)name;
- (NSUInteger)state;
- (id)initWithDevice:(id)device error:(NSError **)error;
- (void)sendWithMessage:(void *)message
         freeWhenDone:(BOOL)freeWhenDone
      completionQueue:(dispatch_queue_t)queue
           completion:(void (^)(NSError *error))completion;
@end

typedef void *(*KeyboardMessageFactory)(NSEvent *event);

static void Usage(void) {
    fprintf(stderr, "Usage: SimulatorHIDSender --udid UUID --developer-dir PATH [--keycode 117|36|53] [--hold-ms 50] [--dry-run]\n");
    fprintf(stderr, "117 = Forward Delete, 36 = Return, 53 = Escape (macOS virtual key codes).\n");
    fprintf(stderr, "Only an exact, booted CoreSimulator device is accepted. --dry-run sends nothing.\n");
}

static int Fail(NSString *message) {
    fprintf(stderr, "%s\n", message.UTF8String);
    return 1;
}

static BOOL Send(id client, KeyboardMessageFactory factory, unsigned short keyCode,
                 NSString *characters, BOOL down, NSString *udid) {
    NSEvent *event = [NSEvent keyEventWithType:down ? NSEventTypeKeyDown : NSEventTypeKeyUp
                                     location:NSZeroPoint
                                modifierFlags:0
                                    timestamp:NSProcessInfo.processInfo.systemUptime
                                 windowNumber:0 context:nil
                                   characters:characters
                  charactersIgnoringModifiers:characters
                                    isARepeat:NO keyCode:keyCode];
    if (!event) {
        fprintf(stderr, "Could not create the local NSEvent message object\n");
        return NO;
    }
    void *message = factory(event);
    if (!message) {
        fprintf(stderr, "SimulatorKit rejected the keyboard message\n");
        return NO;
    }
    dispatch_semaphore_t completion = dispatch_semaphore_create(0);
    __block NSError *sendError = nil;
    [client sendWithMessage:message freeWhenDone:YES
           completionQueue:dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0)
                completion:^(NSError *error) {
                    sendError = error;
                    dispatch_semaphore_signal(completion);
                }];
    if (dispatch_semaphore_wait(completion, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC))) {
        fprintf(stderr, "Timed out waiting for SimulatorKit keyboard delivery completion\n");
        return NO;
    }
    if (sendError) {
        fprintf(stderr, "SimulatorKit delivery error: %s\n", sendError.localizedDescription.UTF8String);
        return NO;
    }
    printf("sent %s to %s: mac-keycode=%hu\n", down ? "down" : "up",
           udid.UTF8String, keyCode);
    fflush(stdout);
    return YES;
}

static BOOL ReadInteger(NSString *text, NSInteger *value) {
    NSScanner *scanner = [NSScanner scannerWithString:text];
    return [scanner scanInteger:value] && scanner.isAtEnd;
}

static NSString *ExistingFramework(NSArray<NSString *> *candidates) {
    for (NSString *candidate in candidates) {
        if ([NSFileManager.defaultManager fileExistsAtPath:candidate]) return candidate;
    }
    return nil;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *requestedUDID = nil;
        NSString *developerDirectory = nil;
        NSInteger keyCode = -1;
        NSInteger holdMilliseconds = 50;
        BOOL dryRun = NO;
        for (int i = 1; i < argc; i++) {
            NSString *argument = @(argv[i]);
            if ([argument isEqualToString:@"--help"]) { Usage(); return 0; }
            if ([argument isEqualToString:@"--dry-run"]) { dryRun = YES; continue; }
            if (i + 1 >= argc) { Usage(); return 1; }
            NSString *value = @(argv[++i]);
            if ([argument isEqualToString:@"--udid"]) requestedUDID = value;
            else if ([argument isEqualToString:@"--developer-dir"]) developerDirectory = value;
            else if ([argument isEqualToString:@"--keycode"]) {
                if (!ReadInteger(value, &keyCode)) return Fail(@"Invalid key code");
            } else if ([argument isEqualToString:@"--hold-ms"]) {
                if (!ReadInteger(value, &holdMilliseconds)) return Fail(@"Invalid hold duration");
            } else { Usage(); return 1; }
        }
        if (!requestedUDID.length || !developerDirectory.isAbsolutePath) {
            Usage(); return Fail(@"An explicit Simulator UUID and active Xcode Developer directory are required");
        }
        NSUUID *selectedUUID = [[NSUUID alloc] initWithUUIDString:requestedUDID];
        if (!selectedUUID) return Fail(@"The device selector is not a Simulator UUID");
        requestedUDID = selectedUUID.UUIDString;
        developerDirectory = developerDirectory.stringByResolvingSymlinksInPath;
        if ((!dryRun && keyCode == -1)
                || (keyCode != -1 && !(keyCode == 117 || keyCode == 36 || keyCode == 53))
                || holdMilliseconds < 0 || holdMilliseconds > 5000) {
            Usage(); return 1;
        }
        NSString *contents = developerDirectory.stringByDeletingLastPathComponent;
        NSString *coreSimulatorPath = ExistingFramework(@[
            [developerDirectory stringByAppendingPathComponent:@"Library/PrivateFrameworks/CoreSimulator.framework/CoreSimulator"],
            [contents stringByAppendingPathComponent:@"SharedFrameworks/CoreSimulator.framework/CoreSimulator"],
            @"/Library/Developer/PrivateFrameworks/CoreSimulator.framework/CoreSimulator"
        ]);
        NSString *simulatorKitPath = ExistingFramework(@[
            [contents stringByAppendingPathComponent:@"SharedFrameworks/SimulatorKit.framework/SimulatorKit"]
        ]);
        if (!coreSimulatorPath || !simulatorKitPath) {
            return Fail(@"The selected Xcode installation lacks CoreSimulator or SimulatorKit");
        }
        if (!dlopen(coreSimulatorPath.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL)) {
            return Fail([NSString stringWithFormat:@"Cannot load CoreSimulator: %s", dlerror()]);
        }
        void *simulatorKit = dlopen(simulatorKitPath.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
        if (!simulatorKit) {
            return Fail([NSString stringWithFormat:@"Cannot load SimulatorKit: %s", dlerror()]);
        }
        KeyboardMessageFactory factory = (KeyboardMessageFactory)dlsym(
                simulatorKit, "IndigoHIDMessageForKeyboardNSEvent");
        if (!factory) return Fail(@"The selected SimulatorKit lacks the keyboard message factory");
        Class contextClass = NSClassFromString(@"SimServiceContext");
        Class clientClass = NSClassFromString(@"_TtC12SimulatorKit24SimDeviceLegacyHIDClient");
        if (!contextClass || !clientClass) return Fail(@"The required Simulator classes are unavailable");
        NSError *error = nil;
        id context = [contextClass sharedServiceContextForDeveloperDir:developerDirectory error:&error];
        if (!context) return Fail([NSString stringWithFormat:@"Cannot get Simulator service: %@", error]);
        id deviceSet = [context defaultDeviceSetWithError:&error];
        if (!deviceSet) return Fail([NSString stringWithFormat:@"Cannot get Simulator device set: %@", error]);
        id target = nil;
        for (id device in [deviceSet availableDevices]) {
            if ([[device UDID] isEqual:selectedUUID]) { target = device; break; }
        }
        if (!target) return Fail(@"The selected UUID is not an available CoreSimulator device");
        // CoreSimulator's Booted state is 3. Do not boot, choose a default,
        // match by approximate name, or target a physical device.
        if ([target state] != 3) {
            return Fail([NSString stringWithFormat:@"The selected Simulator is not booted: %@ state=%lu",
                         [target name], (unsigned long)[target state]]);
        }
        printf("validated target: %s (%s), state=3\n", [[target name] UTF8String], requestedUDID.UTF8String);
        fflush(stdout);
        if (dryRun) return 0;
        id client = [[clientClass alloc] initWithDevice:target error:&error];
        if (!client) return Fail([NSString stringWithFormat:@"Cannot get Simulator HID client: %@", error]);
        NSString *characters = keyCode == 117 ? @"\uF728" : keyCode == 36 ? @"\r" : @"\x1B";
        BOOL downSucceeded = Send(client, factory, (unsigned short)keyCode, characters, YES, requestedUDID);
        if (downSucceeded && holdMilliseconds) usleep((useconds_t)holdMilliseconds * 1000);
        // Always attempt release, even if down delivery times out.
        BOOL upSucceeded = Send(client, factory, (unsigned short)keyCode, characters, NO, requestedUDID);
        return downSucceeded && upSucceeded ? 0 : 1;
    }
}
