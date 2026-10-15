// Copyright (c) 2026 Chui Ping Cheng. MIT License.
#import "../../../PreferenceApplications/OSX/TakaoUpdate.h"

static int passed;
static void Check(BOOL value, NSString *message)
{
    if (!value) { NSLog(@"FAIL: %@", message); exit(1); }
    passed++;
}

@interface TestService : NSObject
@property(nonatomic, copy) NSDictionary *status;
@property(nonatomic) int checks;
@property(nonatomic, retain) dispatch_semaphore_t gate;
- (void)setBetaDesktopUpdates:(BOOL)enabled;
@end
@implementation TestService
- (bycopy NSDictionary *)desktopUpdateStatus
{
    if (self.gate) dispatch_semaphore_wait(self.gate, DISPATCH_TIME_FOREVER);
    return self.status;
}
- (void)checkForDesktopUpdates
{
    self.checks++;
    self.status = @{@"canCheck":@NO, @"checking":@YES, @"message":@"正在檢查"};
}
- (void)setBetaDesktopUpdates:(BOOL)enabled
{
    NSMutableDictionary *status = [[self.status mutableCopy] autorelease];
    status[@"beta"] = @(enabled); self.status = status;
}
- (void)dealloc { [_status release]; [_gate release]; [super dealloc]; }
@end

@interface TakaoUpdate (Testing)
- (id)updateService;
- (void)_getVersionInfo;
- (void)stopStatusTimer:(NSNotification *)notification;
@end
@interface TestPreferences : TakaoUpdate
@property(nonatomic, retain) TestService *service;
@property(nonatomic) BOOL realService;
@end
@implementation TestPreferences
- (id)updateService { return self.realService ? [super updateService] : self.service; }
- (void)dealloc { [_service release]; [super dealloc]; }
@end

static void Refresh(TestPreferences *controller)
{
    [controller _getVersionInfo];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while ([[controller valueForKey:@"_statusRequestPending"] boolValue] && [deadline timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    Check(![[controller valueForKey:@"_statusRequestPending"] boolValue], @"background service request completes");
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication]; // Never activate, launch IMK, or register its service.
        TestPreferences *controller = [[[TestPreferences alloc] init] autorelease];
        TestService *service = [[[TestService alloc] init] autorelease];
        controller.service = service;
        service.status = @{@"canCheck":@NO, @"checking":@NO, @"message":@"尚未設定正式更新網址與公開金鑰"};
        NSView *view = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 480, 171)] autorelease];
        NSProgressIndicator *progress = [[[NSProgressIndicator alloc] initWithFrame:NSMakeRect(375, 135, 16, 16)] autorelease];
        [progress setAutoresizingMask:NSViewMinYMargin]; [view addSubview:progress];
        NSButton *button = [[[NSButton alloc] initWithFrame:NSMakeRect(291, 127, 81, 28)] autorelease];
        [button setAction:@selector(checkUpdateNow:)]; [button setAutoresizingMask:NSViewMinYMargin];
        [view addSubview:button];
        NSBox *box = [[[NSBox alloc] initWithFrame:NSMakeRect(22, 16, 441, 98)] autorelease];
        [view addSubview:box];
        for (NSString *key in @[@"_currentVersionTextField", @"_latestVersionTextField", @"_latestCheckTextField"])
            [controller setValue:[[[NSTextField alloc] initWithFrame:NSZeroRect] autorelease] forKey:key];
        [controller setValue:progress forKey:@"_checkProgressIndicator"];
        [controller awakeFromNib];
        Refresh(controller);
        NSTextField *message = [controller valueForKey:@"_statusTextField"];
        Check(view.frame.size.height == 259 && button.frame.origin.y == 215 && progress.frame.origin.y == 223,
              @"legacy autoresizing does not double-shift existing controls");
        Check(NSMaxY(message.frame) <= NSMinY(box.frame) && NSMaxY(button.frame) <= view.bounds.size.height,
              @"status and original controls fit without overlap");
        Check(!button.enabled && progress.hidden && [message.stringValue containsString:@"公開金鑰"],
              @"unconfigured service disables check and explains configuration");
        NSDate *date = [NSDate date];
        NSButton *beta = [controller valueForKey:@"_betaButton"];
        Check(beta.state == NSControlStateValueOff && !beta.enabled, @"beta checkbox defaults off while unconfigured");
        Check(NSMaxY(message.frame) <= NSMinY(beta.frame) && NSMaxY(beta.frame) <= NSMinY(box.frame), @"beta control fits without overlapping status or version box");
        service.status = @{@"canCheck":@YES, @"checking":@NO, @"latestVersion":@"1.3.3", @"lastCheck":date, @"message":@"可手動檢查",
                           @"beta":@NO, @"canChangeBeta":@YES};
        Refresh(controller);
        Check(button.enabled && [[[controller valueForKey:@"_latestVersionTextField"] stringValue] isEqualToString:@"1.3.3"],
              @"available version and check readiness render");
        Check(![[[controller valueForKey:@"_latestCheckTextField"] stringValue] isEqualToString:@"尚未檢查"], @"last check renders");
        Check(beta.enabled && beta.state == NSControlStateValueOff, @"ready client offers explicit beta opt-in");
        [beta setState:NSControlStateValueOn]; [controller betaUpdatesChanged:beta];
        Refresh(controller);
        Check(beta.state == NSControlStateValueOn && [service.status[@"beta"] boolValue], @"beta checkbox reaches IMK service");
        [controller checkUpdateNow:button];
        [controller checkUpdateNow:button];
        Refresh(controller);
        Check(service.checks == 1 && !button.enabled, @"manual request disables button until status refresh");
        service.status = @{@"canCheck":@NO, @"checking":@YES, @"message":@"正在檢查"};
        Refresh(controller);
        Check(!button.enabled && !progress.hidden, @"busy service renders progress and blocks check");
        service.status = @{@"canCheck":@YES, @"checking":@NO, @"message":@"已取消更新"};
        Refresh(controller);
        Check(button.enabled && progress.hidden && [message.stringValue isEqualToString:@"已取消更新"], @"cancelled cycle allows retry");
        // Exercise the actual NSConnection client while the server services a
        // modal run-loop (the Sparkle no-update alert that caused the hang).
        NSPort *port = [NSPort port];
        NSConnection *server = [NSConnection connectionWithReceivePort:port sendPort:port];
        [server setRootObject:service];
        [server addRequestMode:NSModalPanelRunLoopMode];
        Check([server registerName:OPENVANILLA_DO_CONNECTION_NAME], @"isolated RPC server registers");
        controller.realService = YES;
        [controller _getVersionInfo];
        NSDate *modalDeadline = [NSDate dateWithTimeIntervalSinceNow:3];
        while ([[controller valueForKey:@"_statusRequestPending"] boolValue] && [modalDeadline timeIntervalSinceNow] > 0)
            [[NSRunLoop currentRunLoop] runMode:NSModalPanelRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        // UI completion may be queued in the default run-loop.
        Refresh(controller);
        Check(button.enabled && progress.hidden, @"modal server still answers status without blocking AppKit");
        [server invalidate]; controller.realService = NO;

        controller.service = nil; Refresh(controller);
        Check(!button.enabled && [message.stringValue containsString:@"第一次升級"], @"absent service shows manual bridge message");
        controller.service = service;
        dispatch_semaphore_t gate = dispatch_semaphore_create(0);
        service.gate = gate; [gate release];
        [controller _getVersionInfo];
        __block BOOL uiRan = NO;
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{ uiRan = YES; }];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        Check(uiRan && [[controller valueForKey:@"_statusRequestPending"] boolValue], @"slow RPC never blocks UI events");
        NSString *beforeClose = [[message.stringValue copy] autorelease];
        [controller stopStatusTimer:nil];
        dispatch_semaphore_signal(service.gate);
        [[controller valueForKey:@"_serviceQueue"] waitUntilAllOperationsAreFinished];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        Check([message.stringValue isEqualToString:beforeClose], @"closed window ignores delayed service results");
        Check([controller valueForKey:@"_statusTimer"] == nil, @"close releases repeating timer");
        printf("PASS %d macOS update preferences assertions (offscreen views; no IMK/network/install)\n", passed);
    }
    return 0;
}
