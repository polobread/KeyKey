// Copyright (c) 2026 Chui Ping Cheng. MIT License.
#import "KeyKeyMacUpdater.h"

@implementation KeyKeyMacUpdater

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
        id feed = [host objectForInfoDictionaryKey:@"SUFeedURL"];
        id key = [host objectForInfoDictionaryKey:@"SUPublicEDKey"];
        if ([feed isKindOfClass:[NSString class]] && [key isKindOfClass:[NSString class]] &&
            [feed length] > 0 && [key length] <= 64) {
            NSURL *url = [NSURL URLWithString:feed];
            NSData *bytes = [[[NSData alloc] initWithBase64EncodedString:key options:0] autorelease];
            _configured = [[url scheme] isEqualToString:@"https"] && [url host].length > 0 &&
                ![url user] && ![url password] && ![url fragment] && [bytes length] == 32;
            if (_configured) _feed = [url retain];
        }
        [self setPhase:@"unconfigured" message:@"尚未設定正式更新網址與公開金鑰；此建置不會連線。"];
        _latestVersion = [@"" copy];
    }
    return self;
}

- (void)dealloc
{
    [self stop];
    [_host release]; [_feed release]; [_phase release]; [_message release]; [_latestVersion release];
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
        Class controllerClass = NSClassFromString(@"SPUStandardUpdaterController");
        _controller = [[controllerClass alloc] initWithStartingUpdater:NO updaterDelegate:self userDriverDelegate:nil];
        _engine = [(id<KeyKeyMacUpdateEngine>)[_controller updater] retain];
    }
    // Enforce privacy and visible, consent-based package installation even when
    // an old user default requests profile submission or automatic downloads.
    [_engine setSendsSystemProfile:NO];
    [_engine setAutomaticallyDownloadsUpdates:NO];
    NSError *error = nil;
    if (![_engine startUpdater:&error]) {
        _configured = NO;
        [self setPhase:@"failed" message:[NSString stringWithFormat:@"更新服務無法啟用：%@", [error localizedDescription] ?: @"設定無效"]];
        return;
    }
    _started = YES;
    [self setPhase:@"idle" message:@"可手動檢查，或開啟每日自動檢查。下載與安裝仍需確認。"];
}

- (void)clearPendingInstallation
{
    [_installationTimer invalidate]; [_installationTimer release]; _installationTimer = nil;
    [_pendingInstallation release]; _pendingInstallation = nil;
}

- (void)stop
{
    _stopped = YES; _busy = NO; _installationRequested = NO;
    [self clearPendingInstallation];
    [_controller release]; _controller = nil;
    [_engine release]; _engine = nil;
}

- (NSDictionary *)snapshot
{
    BOOL ready = _configured && _started && !_stopped;
    return [NSDictionary dictionaryWithObjectsAndKeys:
        @(ready), @"configured", @(ready && [_engine automaticallyChecksForUpdates]), @"automatic",
        @(ready && !_busy && !_pendingInstallation && [_engine canCheckForUpdates] && ![_engine sessionInProgress]), @"canCheck",
        @(_busy), @"checking", _phase ?: @"unconfigured", @"phase", _message ?: @"", @"message",
        [_host objectForInfoDictionaryKey:@"KeyKeyReleaseVersion"] ?: [_host objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"", @"currentVersion",
        _latestVersion ?: @"", @"latestVersion", [_engine lastUpdateCheckDate] ?: (id)@"", @"lastCheck", nil];
}

- (void)checkForUpdates
{
    NSAssert([NSThread isMainThread], @"macOS updater runs on the main thread");
    if (![[[self snapshot] objectForKey:@"canCheck"] boolValue]) return;
    _busy = YES;
    [self setPhase:@"checking" message:@"正在檢查簽章更新…"];
    [_engine checkForUpdates];
}

- (void)setAutomaticChecks:(BOOL)enabled
{
    if (!_stopped && _configured && _started) [_engine setAutomaticallyChecksForUpdates:enabled];
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
    if (_stopped) return NO;
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
    if (_stopped) return;
    [_latestVersion release]; _latestVersion = [[item displayVersionString] copy];
    [self setPhase:@"available" message:@"找到可安裝的新版本；請在更新視窗確認是否下載。"];
}

- (void)updaterDidNotFindUpdate:(SPUUpdater *)updater error:(NSError *)error
{
    if (!_stopped) [self setPhase:@"no-update" message:@"目前沒有適用的更新。版本或系統需求請以更新視窗說明為準。"];
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
    [self setPhase:@"installing" message:@"安裝將要求管理員授權；完成後請登出再登入。"];
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
    [self setPhase:@"installing" message:@"組字已完成，繼續更新；安裝後請登出再登入。"];
    handler();
    [handler release];
}

- (BOOL)mayTerminateForUpdate
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
    return !_stopped && [self mayTerminateForUpdate];
}

- (void)updater:(SPUUpdater *)updater didFinishUpdateCycleForUpdateCheck:(SPUUpdateCheck)check error:(NSError *)error
{
    if (_stopped) return;
    _busy = NO;
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
