// Copyright (c) 2026 Chui Ping Cheng. MIT License.
#import "KeyKeyMacUpdater.h"

// Keep Sparkle's download/install UI and signature validation. Query progress,
// no-update results and query errors belong in Preferences instead of modal
// dialogs owned by the background input method.
@interface KeyKeyMacUpdater (UpdateFocus)
- (BOOL)shouldFocusUpdateUI;
@end

@interface KeyKeyMacUserDriver : NSObject <SPUUserDriver>
@property(nonatomic, assign) KeyKeyMacUpdater *owner;
@property(nonatomic, retain) id<SPUUserDriver> standard;
@end

@implementation KeyKeyMacUserDriver
- (void)dealloc { [_standard release]; [super dealloc]; }
- (void)focusManualUpdate
{
    if ([_owner shouldFocusUpdateUI]) {
        [NSApp activateIgnoringOtherApps:YES];
        [self showUpdateInFocus];
        // IMK is LSBackgroundOnly, and Preferences uses a floating window.
        // Public focus alone cannot expose a normal update window. Raise only
        // windows controlled by the standard driver's framework, below system
        // modal panels; input-method panels and other windows stay untouched.
        NSBundle *driverBundle = [NSBundle bundleForClass:[_standard class]];
        for (NSWindow *window in [NSApp windows]) {
            NSWindowController *controller = [window windowController];
            if (window.visible && controller &&
                [[NSBundle bundleForClass:[controller class]] isEqual:driverBundle]) {
                [window setLevel:MAX(window.level, NSFloatingWindowLevel + 1)];
                [window orderFrontRegardless];
            }
        }
    }
}
- (void)showUpdatePermissionRequest:(SPUUpdatePermissionRequest *)request reply:(void (^)(SUUpdatePermissionResponse *))reply
{ [_standard showUpdatePermissionRequest:request reply:reply]; }
- (void)showUserInitiatedUpdateCheckWithCancellation:(void (^)(void))cancellation
{ [_owner beginCheckWithCancellation:cancellation]; }
- (void)showUpdateFoundWithAppcastItem:(SUAppcastItem *)item state:(SPUUserUpdateState *)state reply:(void (^)(SPUUserUpdateChoice))reply
{ [_standard showUpdateFoundWithAppcastItem:item state:state reply:reply]; [self focusManualUpdate]; }
- (void)showUpdateReleaseNotesWithDownloadData:(SPUDownloadData *)data
{ [_standard showUpdateReleaseNotesWithDownloadData:data]; }
- (void)showUpdateReleaseNotesFailedToDownloadWithError:(NSError *)error
{ [_standard showUpdateReleaseNotesFailedToDownloadWithError:error]; }
- (void)showUpdateNotFoundWithError:(NSError *)error acknowledgement:(void (^)(void))acknowledgement
{ acknowledgement(); }
- (void)showUpdaterError:(NSError *)error acknowledgement:(void (^)(void))acknowledgement
{
    NSString *phase = [_owner snapshot][@"phase"];
    if ([phase isEqualToString:@"checking"] || [phase isEqualToString:@"failed"])
        acknowledgement();
    else [_standard showUpdaterError:error acknowledgement:acknowledgement];
}
- (void)showDownloadInitiatedWithCancellation:(void (^)(void))cancellation
{ [_standard showDownloadInitiatedWithCancellation:cancellation]; [self focusManualUpdate]; }
- (void)showDownloadDidReceiveExpectedContentLength:(uint64_t)length
{ [_standard showDownloadDidReceiveExpectedContentLength:length]; }
- (void)showDownloadDidReceiveDataOfLength:(uint64_t)length
{ [_standard showDownloadDidReceiveDataOfLength:length]; }
- (void)showDownloadDidStartExtractingUpdate { [_standard showDownloadDidStartExtractingUpdate]; }
- (void)showExtractionReceivedProgress:(double)progress { [_standard showExtractionReceivedProgress:progress]; }
- (void)showReadyToInstallAndRelaunch:(void (^)(SPUUserUpdateChoice))reply
{ [_standard showReadyToInstallAndRelaunch:reply]; [self focusManualUpdate]; }
- (void)showInstallingUpdateWithApplicationTerminated:(BOOL)terminated retryTerminatingApplication:(void (^)(void))retry
{ [_standard showInstallingUpdateWithApplicationTerminated:terminated retryTerminatingApplication:retry]; }
- (void)showUpdateInstalledAndRelaunched:(BOOL)relaunched acknowledgement:(void (^)(void))acknowledgement
{ [_standard showUpdateInstalledAndRelaunched:relaunched acknowledgement:acknowledgement]; }
- (void)dismissUpdateInstallation { [_standard dismissUpdateInstallation]; }
- (void)showUpdateInFocus { if ([_standard respondsToSelector:_cmd]) [_standard showUpdateInFocus]; }
@end

@implementation KeyKeyMacUpdater

static NSURL *ReviewedFeed(id value)
{
    if (![value isKindOfClass:[NSString class]] || ![value length]) return nil;
    NSURL *url = [NSURL URLWithString:value];
    return [[url scheme] isEqualToString:@"https"] && [url host].length > 0 &&
        ![url user] && ![url password] && ![url fragment] ? url : nil;
}

- (void)setPhase:(NSString *)phase message:(NSString *)message
{
    [_phase release]; _phase = [phase copy];
    [_message release]; _message = [message copy];
}

- (instancetype)initWithHostBundle:(NSBundle *)host engine:(id<KeyKeyMacUpdateEngine>)engine
                 compositionCheck:(BOOL (^)(void))compositionCheck
{
    if ((self = [super init])) {
        _host = [host retain]; _engine = [engine retain];
        _compositionCheck = [compositionCheck copy];
        _stableFeed = [ReviewedFeed([host objectForInfoDictionaryKey:@"SUFeedURL"]) retain];
        _betaFeed = [ReviewedFeed([host objectForInfoDictionaryKey:@"KeyKeyBetaFeedURL"]) retain];
        id key = [host objectForInfoDictionaryKey:@"SUPublicEDKey"];
        if ([key isKindOfClass:[NSString class]] && [key length] <= 64) {
            NSData *bytes = [[[NSData alloc] initWithBase64EncodedString:key options:0] autorelease];
            _keyValid = [bytes length] == 32;
        }
        // A suite with the running app's own identifier is rejected by Foundation.
        NSBundle *mainBundle = [NSBundle mainBundle];
        BOOL mainHost = host == mainBundle ||
            [[host bundleIdentifier] isEqualToString:[mainBundle bundleIdentifier]];
        _preferences = mainHost ? [[NSUserDefaults standardUserDefaults] retain] :
            [[NSUserDefaults alloc] initWithSuiteName:[host bundleIdentifier]];
        id lastAttempt = [_preferences objectForKey:@"KeyKeyLastUpdateAttempt"];
        if (![lastAttempt isKindOfClass:[NSDate class]]) lastAttempt = [_preferences objectForKey:@"SULastCheckTime"];
        if ([lastAttempt isKindOfClass:[NSDate class]]) _lastUpdateAttempt = [lastAttempt retain];
        id automatic = [_preferences objectForKey:@"KeyKeyAutomaticChecks"];
        if (!automatic) automatic = [_preferences objectForKey:@"SUEnableAutomaticChecks"];
        // New installations check weekly; preserve an existing explicit choice.
        _automaticChecks = !automatic || ([automatic isKindOfClass:[NSNumber class]] && [automatic boolValue]);
        id consent = [_preferences objectForKey:@"KeyKeyBetaUpdates"];
        _betaEnabled = [consent isKindOfClass:[NSNumber class]] && [consent boolValue];
        _feed = [(_betaEnabled ? _betaFeed : _stableFeed) retain];
        _configured = _keyValid && _feed != nil;
        [self setPhase:@"unconfigured" message:@"尚未設定正式更新網址與公開金鑰；此建置不會連線。"];
        _latestVersion = [@"" copy];
    }
    return self;
}

- (void)dealloc
{
    [self stop];
    [_host release]; [_feed release]; [_phase release]; [_message release]; [_latestVersion release];
    [_stableFeed release]; [_betaFeed release]; [_preferences release];
    [_automaticNotBefore release]; [_lastUpdateAttempt release];
    [_compositionCheck release];
    [super dealloc];
}

- (void)start
{
    NSAssert([NSThread isMainThread], @"macOS updater runs on the main thread");
    if (_started || _stopped || !_configured) return;
    if (!_engine) {
        NSString *path = [[_host privateFrameworksPath] stringByAppendingPathComponent:@"Sparkle.framework"];
        NSError *error = nil;
        if (![[NSBundle bundleWithPath:path] loadAndReturnError:&error]) {
            _configured = NO;
            [self setPhase:@"failed" message:@"無法載入已嵌入的 Sparkle 更新元件。"];
            return;
        }
        KeyKeyMacUserDriver *driver = [[KeyKeyMacUserDriver alloc] init];
        driver.owner = self;
        driver.standard = [[[NSClassFromString(@"SPUStandardUserDriver") alloc]
            initWithHostBundle:_host delegate:self] autorelease];
        _controller = driver;
        _engine = (id<KeyKeyMacUpdateEngine>)[[NSClassFromString(@"SPUUpdater") alloc]
            initWithHostBundle:_host applicationBundle:_host userDriver:driver delegate:self];
    }
    // Enforce privacy and visible, consent-based package installation even when
    // an old user default requests profile submission or automatic downloads.
    [_engine setSendsSystemProfile:NO];
    [_engine setAutomaticallyDownloadsUpdates:NO];
    // Use one cancellable 10-second query path for manual and weekly checks.
    // Sparkle's own background query has no public cancellation handle.
    if (_automaticChecks && ![_preferences objectForKey:@"KeyKeyAutomaticChecks"])
        [_preferences setBool:YES forKey:@"KeyKeyAutomaticChecks"];
    [_engine setAutomaticallyChecksForUpdates:NO];
    NSError *error = nil;
    if (![_engine startUpdater:&error]) {
        _configured = NO;
        [self setPhase:@"failed" message:[NSString stringWithFormat:@"更新服務無法啟用：%@", [error localizedDescription] ?: @"設定無效"]];
        return;
    }
    _started = YES;
    _automaticNotBefore = [[NSDate dateWithTimeIntervalSinceNow:600] retain];
    [self updateAutomaticTimer];
    [self setPhase:@"idle" message:@"啟動 10 分鐘後檢查新版，之後每 7 天一次。不預先下載；按下更新後才下載與安裝。"];
}

- (void)clearPendingInstallation
{
    [_installationTimer invalidate]; [_installationTimer release]; _installationTimer = nil;
    [_pendingInstallation release]; _pendingInstallation = nil;
}

- (void)stop
{
    _stopped = YES; _busy = NO; _installationRequested = NO;
    void (^cancel)(void) = [_cancelCheck copy];
    [self clearCheckDeadline];
    if (cancel) { cancel(); [cancel release]; }
    [_automaticTimer invalidate]; [_automaticTimer release]; _automaticTimer = nil;
    [self clearPendingInstallation];
    if ([_controller isKindOfClass:[KeyKeyMacUserDriver class]]) [(KeyKeyMacUserDriver *)_controller setOwner:nil];
    [_controller release]; _controller = nil;
    [_engine release]; _engine = nil;
}

- (NSDictionary *)snapshot
{
    BOOL ready = _configured && _started && !_stopped;
    return [NSDictionary dictionaryWithObjectsAndKeys:
        @(ready), @"configured", @(ready && _automaticChecks), @"automatic",
        @(_betaEnabled), @"beta", @(!_stopped && _keyValid && _stableFeed && _betaFeed && !_busy &&
            !_pendingInstallation && !_installationRequested && ![_engine sessionInProgress]), @"canChangeBeta",
        @(ready && !_busy && !_pendingInstallation && [_engine canCheckForUpdates] && ![_engine sessionInProgress]), @"canCheck",
        @(_busy && [_phase isEqualToString:@"checking"]), @"checking", _phase ?: @"unconfigured", @"phase", _message ?: @"", @"message",
        [_host objectForInfoDictionaryKey:@"KeyKeyReleaseVersion"] ?: [_host objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"", @"currentVersion",
        _latestVersion ?: @"", @"latestVersion", [_engine lastUpdateCheckDate] ?: (id)@"", @"lastCheck", nil];
}

- (void)checkForUpdates
{
    NSAssert([NSThread isMainThread], @"macOS updater runs on the main thread");
    if (![[[self snapshot] objectForKey:@"canCheck"] boolValue]) return;
    _manualCheck = YES;
    _checkTimedOut = NO;
    [_lastUpdateAttempt release];
    _lastUpdateAttempt = [[NSDate date] retain];
    [_preferences setObject:_lastUpdateAttempt forKey:@"KeyKeyLastUpdateAttempt"];
    // Keep a memory deadline too: a failed disk write must never cause a retry loop.
    [self updateAutomaticTimer];
    _busy = YES;
    [self setPhase:@"checking" message:@"正在檢查簽章更新…"];
    [_engine checkForUpdates];
}

- (void)setAutomaticChecks:(BOOL)enabled
{
    if (_stopped || !_configured || !_started) return;
    if (enabled && !_automaticChecks) {
        [_automaticNotBefore release];
        _automaticNotBefore = [[NSDate dateWithTimeIntervalSinceNow:600] retain];
    }
    _automaticChecks = enabled;
    [_preferences setBool:enabled forKey:@"KeyKeyAutomaticChecks"];
    [self updateAutomaticTimer];
}

- (void)updateAutomaticTimer
{
    [_automaticTimer invalidate]; [_automaticTimer release]; _automaticTimer = nil;
    if (!_automaticChecks || _stopped || !_started) return;

    NSDate *next = _automaticNotBefore ?: [NSDate dateWithTimeIntervalSinceNow:600];
    if (_lastUpdateAttempt) {
        NSDate *weekly = [_lastUpdateAttempt dateByAddingTimeInterval:604800];
        if ([weekly compare:next] == NSOrderedDescending) next = weekly;
    }
    // One deadline, no per-minute polling. Resume from sleep with at most one check.
    _automaticTimer = [[NSTimer alloc] initWithFireDate:next interval:0 target:self
        selector:@selector(checkAutomatically:) userInfo:nil repeats:NO];
    [[NSRunLoop mainRunLoop] addTimer:_automaticTimer forMode:NSRunLoopCommonModes];
}

- (void)checkAutomatically:(NSTimer *)timer
{
    if (_stopped || !_automaticChecks || timer != _automaticTimer) return;
    // Even if the engine is busy or persistence is unavailable, defer for another week.
    [_automaticNotBefore release];
    _automaticNotBefore = [[NSDate dateWithTimeIntervalSinceNow:604800] retain];
    if ([[[self snapshot] objectForKey:@"canCheck"] boolValue]) {
        [self checkForUpdates];
        _manualCheck = NO;
    } else {
        [self updateAutomaticTimer];
    }
}

- (void)clearCheckDeadline
{
    [_checkTimer invalidate]; [_checkTimer release]; _checkTimer = nil;
    [_cancelCheck release]; _cancelCheck = nil;
}

- (void)beginCheckWithCancellation:(void (^)(void))cancellation
{
    [self clearCheckDeadline];
    if (_stopped) { cancellation(); return; }
    _cancelCheck = [cancellation copy];
    _checkTimer = [[NSTimer timerWithTimeInterval:10 target:self selector:@selector(checkTimedOut:)
        userInfo:nil repeats:NO] retain];
    [[NSRunLoop mainRunLoop] addTimer:_checkTimer forMode:NSRunLoopCommonModes];
}

- (void)checkTimedOut:(NSTimer *)timer
{
    if (_stopped || timer != _checkTimer) return;
    void (^cancel)(void) = [_cancelCheck copy];
    [self clearCheckDeadline];
    _checkTimedOut = YES;
    _busy = NO;
    [self setPhase:@"failed" message:@"檢查更新逾時（10 秒）；請稍後按「立即檢查」再試。"];
    if (cancel) { cancel(); [cancel release]; }
}

- (BOOL)setBetaUpdates:(BOOL)enabled
{
    NSAssert([NSThread isMainThread], @"macOS updater runs on the main thread");
    if (enabled == _betaEnabled) return YES;
    if (![[self snapshot][@"canChangeBeta"] boolValue]) return NO;
    _betaEnabled = enabled;
    [_preferences setBool:enabled forKey:@"KeyKeyBetaUpdates"];
    [_feed release]; _feed = [(enabled ? _betaFeed : _stableFeed) retain];
    _configured = _keyValid && _feed != nil;
    [_latestVersion release]; _latestVersion = [@"" copy];
    if (!_started) [self start];
    if (!_started) return NO;
    // Recompute the schedule without performing a network check here.
    if ([_engine respondsToSelector:@selector(resetUpdateCycle)]) [_engine resetUpdateCycle];
    [self setPhase:@"idle" message:enabled ? @"已選擇 beta 測試版來源；下載與安裝仍需確認。" : @"已選擇正式版來源。"];
    return YES;
}

- (NSString *)feedURLStringForUpdater:(SPUUpdater *)updater
{
    // A mutable SUFeedURL user default must not select a different feed.
    return [_feed absoluteString];
}

- (NSArray *)feedParametersForUpdater:(SPUUpdater *)updater sendingSystemProfile:(BOOL)sendingProfile
{
    return [NSArray array];
}

- (BOOL)updater:(SPUUpdater *)updater mayPerformUpdateCheck:(SPUUpdateCheck)check error:(NSError **)error
{
    if (_stopped || !_configured || _pendingInstallation) {
        if (error) *error = [NSError errorWithDomain:@"KeyKeyMacUpdater" code:1
            userInfo:@{NSLocalizedDescriptionKey: @"更新服務未啟用或正在等待完成輸入。"}];
        return NO;
    }
    _busy = YES;
    [self setPhase:@"checking" message:@"正在檢查簽章更新…"];
    return YES;
}

- (BOOL)updater:(SPUUpdater *)updater shouldProceedWithUpdate:(SUAppcastItem *)item
    updateCheck:(SPUUpdateCheck)check error:(NSError **)error
{
    if (_stopped || _checkTimedOut) return NO;
    NSURL *url = [item fileURL];
    NSString *path = [[url path] lowercaseString];
    BOOL valid = [[url scheme] isEqualToString:@"https"] && [url host].length > 0 &&
        ![url user] && ![url password] && ![url fragment] &&
        [[item installationType] isEqualToString:@"package"] &&
        ([path hasSuffix:@".pkg.zip"] || [path hasSuffix:@".pkg"]);
    if (!valid) {
        [self setPhase:@"failed" message:@"更新項目不是受支援的 HTTPS macOS 安裝套件。"];
        if (error) *error = [NSError errorWithDomain:@"KeyKeyMacUpdater" code:2
            userInfo:@{NSLocalizedDescriptionKey: _message}];
    }
    return valid;
}

- (void)updater:(SPUUpdater *)updater didFindValidUpdate:(SUAppcastItem *)item
{
    if (_stopped || _checkTimedOut) return;
    [self clearCheckDeadline];
    [_latestVersion release]; _latestVersion = [[item displayVersionString] copy];
    [self setPhase:@"available" message:@"找到可安裝的新版本；請在更新視窗確認是否下載。"];
}

- (void)updaterDidNotFindUpdate:(SPUUpdater *)updater error:(NSError *)error
{
    if (_stopped || _checkTimedOut) return;
    [self clearCheckDeadline];
    [self setPhase:@"no-update" message:@"目前沒有適用的更新。"];
}

- (BOOL)shouldFocusUpdateUI
{
    return !_stopped && _manualCheck;
}

- (void)standardUserDriverWillShowModalAlert
{
    // The updater belongs to the background IMK app, not Preferences. Bring a
    // manual check's result forward so it cannot wait unseen behind Settings.
    if ([self shouldFocusUpdateUI]) [NSApp activateIgnoringOtherApps:YES];
}

- (void)updater:(SPUUpdater *)updater willDownloadUpdate:(SUAppcastItem *)item withRequest:(NSMutableURLRequest *)request
{
    if (!_stopped) [self setPhase:@"downloading" message:@"正在下載；Sparkle 更新視窗顯示下載進度。"];
}

- (void)updater:(SPUUpdater *)updater didDownloadUpdate:(SUAppcastItem *)item
{
    if (!_stopped) [self setPhase:@"downloaded" message:@"下載完成，更新元件仍須驗證簽章與套件。"];
}

- (void)updater:(SPUUpdater *)updater willExtractUpdate:(SUAppcastItem *)item
{
    if (!_stopped) [self setPhase:@"extracting" message:@"正在驗證及準備安裝套件…"];
}

- (void)userDidCancelDownload:(SPUUpdater *)updater
{
    if (!_stopped) [self setPhase:@"cancelled" message:@"已取消下載；沒有安裝更新。"];
}

- (void)updater:(SPUUpdater *)updater userDidMakeChoice:(SPUUserUpdateChoice)choice
    forUpdate:(SUAppcastItem *)item state:(SPUUserUpdateState *)state
{
    if (!_stopped && choice != SPUUserUpdateChoiceInstall)
        [self setPhase:@"dismissed" message:choice == SPUUserUpdateChoiceSkip ? @"已略過此版本。" : @"已保留目前版本；稍後可再檢查。"];
}

- (void)updater:(SPUUpdater *)updater willInstallUpdate:(SUAppcastItem *)item
{
    if (_stopped) return;
    _installationRequested = YES;
    [self setPhase:@"installing" message:@"安裝將要求管理員授權；完成後請儲存工作、登出 macOS 再登入，再選回琦琦試打。升級請保留原有輸入法項目，不必移除重加。"];
}

- (BOOL)updater:(SPUUpdater *)updater shouldPostponeRelaunchForUpdate:(SUAppcastItem *)item
    untilInvokingBlock:(void (^)(void))handler
{
    if (_stopped) return NO;
    _installationRequested = YES;
    if (!_compositionCheck || !_compositionCheck()) return NO;
    [self clearPendingInstallation];
    _pendingInstallation = [handler copy];
    _installationTimer = [[NSTimer scheduledTimerWithTimeInterval:1 target:self
        selector:@selector(resumeInstallationIfSafe) userInfo:nil repeats:YES] retain];
    [self setPhase:@"waiting-for-input" message:@"請先完成目前組字，再繼續更新；不會自行送字或清除輸入。"];
    return YES;
}

- (void)resumeInstallationIfSafe
{
    if (_stopped || !_pendingInstallation || (_compositionCheck && _compositionCheck())) return;
    void (^handler)(void) = [_pendingInstallation copy];
    [self clearPendingInstallation];
    [self setPhase:@"installing" message:@"組字已完成，繼續更新；完成後從輸入法選單選取琦琦，並試打確認。"];
    handler();
    [handler release];
}

- (BOOL)mayRelaunchForUpdate
{
    if (!_stopped && _installationRequested && _compositionCheck && _compositionCheck()) {
        [self setPhase:@"waiting-for-input" message:@"更新暫停：請先完成目前組字，再重新選擇安裝更新。"];
        return NO;
    }
    return YES;
}

- (BOOL)updaterShouldRelaunchApplication:(SPUUpdater *)updater
{
    // Sparkle rechecks this before sending its installer the resume request,
    // including retries that no longer call the one-shot postponement delegate.
    // The first attempt must reach that delegate so it can wait for composition.
    // This guard belongs only to Sparkle's update restart. Normal quit,
    // logout and shutdown use AppKit's termination flow without this veto.
    return !_stopped && [self mayRelaunchForUpdate];
}

- (void)updater:(SPUUpdater *)updater didFinishUpdateCycleForUpdateCheck:(SPUUpdateCheck)check error:(NSError *)error
{
    if (_stopped) return;
    [self clearCheckDeadline];
    _busy = NO;
    _manualCheck = NO;
    if (_checkTimedOut) return;
    if (error) {
        if ([error code] == SUNoUpdateError && [[error domain] isEqualToString:@"SUSparkleErrorDomain"])
            [self updaterDidNotFindUpdate:updater error:error];
        else if (([error code] == SUInstallationCanceledError && [[error domain] isEqualToString:@"SUSparkleErrorDomain"]) ||
                 [[_phase description] isEqualToString:@"cancelled"])
            [self setPhase:@"cancelled" message:@"已取消更新；未確認安裝成功。"];
        else
            [self setPhase:@"failed" message:[NSString stringWithFormat:@"更新失敗：%@", [error localizedDescription]]];
        _installationRequested = NO;
        [self clearPendingInstallation];
    } else if ([_phase isEqualToString:@"checking"]) {
        [self setPhase:@"idle" message:@"檢查已結束。"];
    }
}
@end
