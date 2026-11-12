// Copyright (c) 2026 Chui Ping Cheng. MIT License.
#import "../KeyKeyMacUpdater.h"
#include <dispatch/dispatch.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#include <string.h>

static int passed;
static void Check(BOOL condition, NSString *message)
{
    if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
    passed++;
}

@interface FakeEngine : NSObject <KeyKeyMacUpdateEngine>
@property(nonatomic) BOOL automaticallyChecksForUpdates;
@property(nonatomic) BOOL canCheckForUpdates;
@property(nonatomic) BOOL sessionInProgress;
@property(nonatomic, retain) NSDate *lastUpdateCheckDate;
@property(nonatomic) int starts, checks;
@property(nonatomic) BOOL failStart, sendsProfile, downloadsAutomatically;
@end
@implementation FakeEngine
- (instancetype)init { if ((self = [super init])) self.canCheckForUpdates = YES; return self; }
- (BOOL)startUpdater:(NSError **)error
{
    self.starts++;
    if (self.failStart && error) *error = [NSError errorWithDomain:@"test" code:3 userInfo:@{NSLocalizedDescriptionKey:@"invalid helper"}];
    return !self.failStart;
}
- (void)checkForUpdates { self.checks++; }
- (void)setSendsSystemProfile:(BOOL)value { self.sendsProfile = value; }
- (void)setAutomaticallyDownloadsUpdates:(BOOL)value { self.downloadsAutomatically = value; }
- (void)resetUpdateCycle { }
- (void)dealloc { [_lastUpdateCheckDate release]; [super dealloc]; }
@end

@interface FakeItem : NSObject
@property(nonatomic, retain) NSURL *fileURL;
@property(nonatomic, copy) NSString *installationType, *displayVersionString, *versionString;
@property(nonatomic) uint64_t contentLength;
@property(nonatomic) SPUAppcastSigningValidationStatus signingValidationStatus;
@property(nonatomic, copy) NSDictionary *propertiesDictionary;
@end
@implementation FakeItem
- (void)dealloc
{
    [_fileURL release]; [_installationType release]; [_displayVersionString release];
    [_versionString release]; [_propertiesDictionary release];
    [super dealloc];
}
@end

@interface FakeUpdateState : NSObject
@property(nonatomic) SPUUserUpdateStage stage;
@end
@implementation FakeUpdateState
@end

static NSString *const CDNFeed = @"https://download.aws.polobread.com/keykey/update";
static NSString *const RawFeed = @"https://raw.githubusercontent.com/polobread/KeyKey/master/update";
static NSString *const CDNPackage = @"https://download.aws.polobread.com/keykey/releases/download";
static NSString *const GitHubPackage = @"https://github.com/polobread/KeyKey/releases/download";

// Exercise the production user-driver wrapper without opening host windows.
@interface FocusRecordingDriver : NSObject
@property(nonatomic, retain) NSMutableArray *events;
@end
@implementation FocusRecordingDriver
- (id)init { if ((self = [super init])) _events = [NSMutableArray new]; return self; }
- (void)dealloc { [_events release]; [super dealloc]; }
- (void)showUpdateFoundWithAppcastItem:(SUAppcastItem *)item state:(SPUUserUpdateState *)state reply:(void (^)(SPUUserUpdateChoice))reply
{ [self.events addObject:@"found"]; }
- (void)showDownloadInitiatedWithCancellation:(void (^)(void))cancel { [self.events addObject:@"download"]; }
- (void)showReadyToInstallAndRelaunch:(void (^)(SPUUserUpdateChoice))reply { [self.events addObject:@"ready"]; }
- (void)showUpdateInFocus { [self.events addObject:@"focus"]; }
@end

@interface FocusRecordingWindow : NSObject
@property(getter=isVisible) BOOL visible;
@property NSInteger level;
@property int orderedFront;
@property(nonatomic, retain) id windowController;
@end
@implementation FocusRecordingWindow
- (void)orderFrontRegardless { self.orderedFront++; }
- (void)dealloc { [_windowController release]; [super dealloc]; }
@end
@interface FocusRecordingApplication : NSObject
@property(nonatomic, retain) NSArray *windows;
@property int activations;
@end
@implementation FocusRecordingApplication
- (void)activateIgnoringOtherApps:(BOOL)ignore { self.activations++; }
- (void)dealloc { [_windows release]; [super dealloc]; }
@end

static NSBundle *Bundle(NSString *root, id feed, id key)
{
    NSString *app = [root stringByAppendingPathComponent:[[NSUUID UUID].UUIDString stringByAppendingString:@".app"]];
    NSString *contents = [app stringByAppendingPathComponent:@"Contents"];
    [[NSFileManager defaultManager] createDirectoryAtPath:contents withIntermediateDirectories:YES attributes:nil error:NULL];
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithDictionary:@{
        @"CFBundleIdentifier":[@"io.github.polobread.KeyKeyUpdaterIsolatedTest." stringByAppendingString:[NSUUID UUID].UUIDString],
        @"CFBundleVersion":@"1.3.2", @"CFBundleShortVersionString":@"1.3.2", @"CFBundlePackageType":@"APPL"}];
    if (feed) [info setObject:feed forKey:@"SUFeedURL"];
    if ([feed isEqual:@"https://example.invalid/channels/stable.xml"])
        [info setObject:@"https://example.invalid/channels/beta.xml" forKey:@"KeyKeyBetaFeedURL"];
    if ([feed isEqual:[CDNFeed stringByAppendingString:@"/stable/macos-arm64.xml"]])
        [info setObject:[CDNFeed stringByAppendingString:@"/beta/macos-arm64.xml"] forKey:@"KeyKeyBetaFeedURL"];
    if (key) [info setObject:key forKey:@"SUPublicEDKey"];
    [info writeToFile:[contents stringByAppendingPathComponent:@"Info.plist"] atomically:YES];
    return [NSBundle bundleWithPath:app];
}

static NSError *SparkleError(SUError code, NSError *underlying)
{
    return [NSError errorWithDomain:@"SUSparkleErrorDomain" code:code
        userInfo:underlying ? @{NSUnderlyingErrorKey:underlying} : nil];
}

static void DrainMainQueue(void)
{
    __block BOOL drained = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ drained = YES; });
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:1];
    while (!drained && [deadline timeIntervalSinceNow] > 0)
        [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    Check(drained, @"main queue executes scheduled retry");
}

static FakeItem *PackageItem(NSURL *url, unsigned char signatureByte)
{
    FakeItem *item = [[[FakeItem alloc] init] autorelease];
    item.fileURL = url;
    item.versionString = item.displayVersionString = @"2.4.6";
    item.installationType = @"package";
    item.contentLength = 43160000;
    NSData *signature = [NSData dataWithBytes:(unsigned char[64]){signatureByte} length:64];
    item.propertiesDictionary = @{@"enclosure":@{@"url":url.absoluteString, @"length":@"43160000",
        @"sparkle:edSignature":[signature base64EncodedStringWithOptions:0], @"sparkle:installationType":@"package"}};
    return item;
}

static void CheckFeedFallback(NSString *root, NSString *key, BOOL beta)
{
    NSString *stable = [CDNFeed stringByAppendingString:@"/stable/macos-arm64.xml"];
    NSString *suffix = beta ? @"/beta/macos-arm64.xml" : @"/stable/macos-arm64.xml";
    NSString *primary = [CDNFeed stringByAppendingString:suffix];
    NSString *fallback = [RawFeed stringByAppendingString:suffix];
    NSBundle *host = Bundle(root, stable, key);
    FakeEngine *engine = [[[FakeEngine alloc] init] autorelease];
    SPUUpdater *updater = (SPUUpdater *)engine;
    KeyKeyMacUpdater *client = [[[KeyKeyMacUpdater alloc] initWithHostBundle:host engine:engine compositionCheck:nil] autorelease];
    [client start];
    if (beta) Check([client setBetaUpdates:YES], @"test selects the reviewed beta channel");
    [client checkForUpdates];
    Check(engine.checks == 1 && [[client feedURLStringForUpdater:updater] isEqualToString:primary], @"check starts at the selected AWS feed");
    NSURL *primaryURL = [NSURL URLWithString:primary];
    NSError *transport = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut
        userInfo:@{NSURLErrorFailingURLErrorKey:primaryURL}];
    NSError *downloader = SparkleError(SUDownloadError, transport);
    if (beta) {
        NSString *status = [NSHTTPURLResponse localizedStringForStatusCode:403];
        downloader = [NSError errorWithDomain:@"SUSparkleErrorDomain" code:SUDownloadError userInfo:@{
            NSLocalizedDescriptionKey:[NSString stringWithFormat:@"A network error occurred while downloading %@. %@ (403)", primary, status]
        }];
    }
    NSError *feedFailure = SparkleError(SUDownloadError, SparkleError(SUDownloadError, downloader));
    [client updater:updater didFinishUpdateCycleForUpdateCheck:SPUUpdateCheckUpdates error:feedFailure];
    DrainMainQueue();
    Check(engine.checks == 2 && [[client feedURLStringForUpdater:updater] isEqualToString:fallback],
        @"CDN feed transport failure retries the same GitHub Raw channel once");
    [client updater:updater didFinishUpdateCycleForUpdateCheck:SPUUpdateCheckUpdates error:feedFailure];
    DrainMainQueue();
    Check(engine.checks == 2 && [[client snapshot][@"phase"] isEqualToString:@"failed"], @"failed GitHub feed does not loop");
    [client checkForUpdates];
    Check(engine.checks == 3 && [[client feedURLStringForUpdater:updater] isEqualToString:primary], @"new check prefers AWS again");
    [client updater:updater didFinishUpdateCycleForUpdateCheck:SPUUpdateCheckUpdates error:SparkleError(SUNoUpdateError, nil)];
    DrainMainQueue();
    Check(engine.checks == 3 && [[client snapshot][@"phase"] isEqualToString:@"no-update"], @"successful feed with no update does not fall back");
    [client checkForUpdates];
    NSError *badCertificate = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorServerCertificateUntrusted userInfo:nil];
    [client updater:updater didFinishUpdateCycleForUpdateCheck:SPUUpdateCheckUpdates
        error:SparkleError(SUDownloadError, SparkleError(SUDownloadError, badCertificate))];
    DrainMainQueue();
    Check(engine.checks == 4 && [[client snapshot][@"phase"] isEqualToString:@"failed"], @"feed certificate failure does not fall back");
    [client stop];
    [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:host.bundleIdentifier];
}

static void CheckPackageFallback(NSString *root, NSString *key, BOOL changed)
{
    NSString *stable = [CDNFeed stringByAppendingString:@"/stable/macos-arm64.xml"];
    NSString *name = @"/v2.4.6/KeyKey-2.4.6-macos-arm64-0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef.pkg.zip";
    NSURL *cdnURL = [NSURL URLWithString:[CDNPackage stringByAppendingString:name]];
    NSURL *githubURL = [NSURL URLWithString:[GitHubPackage stringByAppendingString:name]];
    NSBundle *host = Bundle(root, stable, key);
    FakeEngine *engine = [[[FakeEngine alloc] init] autorelease];
    SPUUpdater *updater = (SPUUpdater *)engine;
    KeyKeyMacUpdater *client = [[[KeyKeyMacUpdater alloc] initWithHostBundle:host engine:engine compositionCheck:nil] autorelease];
    [client start]; [client checkForUpdates];
    FakeItem *item = PackageItem(changed ? cdnURL : githubURL, 1);
    FakeUpdateState *state = [[[FakeUpdateState alloc] init] autorelease];
    state.stage = SPUUserUpdateStageNotDownloaded;
    [client updater:updater didFindValidUpdate:(id)item];
    [client updater:updater userDidMakeChoice:SPUUserUpdateChoiceInstall forUpdate:(id)item state:(id)state];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:item.fileURL];
    [client updater:updater willDownloadUpdate:(id)item withRequest:request];
    Check([request.URL isEqual:cdnURL], @"reviewed macOS enclosure downloads from AWS first");
    NSError *offline = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCannotConnectToHost
        userInfo:@{NSURLErrorFailingURLErrorKey:cdnURL}];
    [client updater:updater failedToDownloadUpdate:(id)item error:offline];
    [client updater:updater didFinishUpdateCycleForUpdateCheck:SPUUpdateCheckUpdates error:SparkleError(SUDownloadError, offline)];
    DrainMainQueue();
    Check(engine.checks == 2, @"failed AWS package queues one retry");
    FakeItem *refetched = PackageItem(item.fileURL, changed ? 2 : 1);
    [client updater:updater didFindValidUpdate:(id)refetched];
    if (!changed) {
        refetched.signingValidationStatus = SPUAppcastSigningValidationStatusFailed;
        Check(![client shouldResumeDownloadForItem:(id)refetched],
            @"an appcast signature failure cannot inherit download consent");
        refetched.signingValidationStatus = SPUAppcastSigningValidationStatusSkipped;
    }
    id<SPUUserDriver> driver = [[[NSClassFromString(@"KeyKeyMacUserDriver") alloc] init] autorelease];
    FocusRecordingDriver *standard = [[[FocusRecordingDriver alloc] init] autorelease];
    [(id)driver setValue:client forKey:@"owner"];
    [(id)driver setValue:standard forKey:@"standard"];
    __block int replies = 0;
    [driver showUpdateFoundWithAppcastItem:(id)refetched state:(id)state reply:^(SPUUserUpdateChoice choice) {
        Check(choice == SPUUserUpdateChoiceInstall, @"the fallback resumes the download choice");
        replies++;
        [client updater:updater userDidMakeChoice:choice forUpdate:(id)refetched state:(id)state];
    }];
    Check(changed ? replies == 0 && [standard.events containsObject:@"found"] : replies == 1 && standard.events.count == 0,
        @"only the same package and signature inherit the user's download choice");
    if (!changed) {
        request = [NSMutableURLRequest requestWithURL:refetched.fileURL];
        [client updater:updater willDownloadUpdate:(id)refetched withRequest:request];
        Check([request.URL isEqual:githubURL], @"same signed package retries from GitHub Release");
        [client updater:updater failedToDownloadUpdate:(id)refetched error:offline];
        [client updater:updater didFinishUpdateCycleForUpdateCheck:SPUUpdateCheckUpdates error:SparkleError(SUDownloadError, offline)];
        DrainMainQueue();
        Check(engine.checks == 2 && [[client snapshot][@"phase"] isEqualToString:@"failed"], @"GitHub package failure does not loop");

        [client checkForUpdates];
        [client updater:updater didFindValidUpdate:(id)item];
        [client updater:updater userDidMakeChoice:SPUUserUpdateChoiceInstall forUpdate:(id)item state:(id)state];
        request = [NSMutableURLRequest requestWithURL:item.fileURL];
        [client updater:updater willDownloadUpdate:(id)item withRequest:request];
        Check([request.URL isEqual:cdnURL], @"a later download prefers AWS again");
        [client updater:updater didDownloadUpdate:(id)item];
        [client updater:updater willExtractUpdate:(id)item];
        [client updater:updater didFinishUpdateCycleForUpdateCheck:SPUUpdateCheckUpdates error:SparkleError(SUSignatureError, nil)];
        DrainMainQueue();
        Check(engine.checks == 3 && [[client snapshot][@"phase"] isEqualToString:@"failed"],
            @"a downloaded package with an invalid signature fails without changing sources");

        [client checkForUpdates];
        [client updater:updater didFindValidUpdate:(id)item];
        [client updater:updater userDidMakeChoice:SPUUserUpdateChoiceInstall forUpdate:(id)item state:(id)state];
        request = [NSMutableURLRequest requestWithURL:item.fileURL];
        [client updater:updater willDownloadUpdate:(id)item withRequest:request];
        [client userDidCancelDownload:updater];
        [client updater:updater didFinishUpdateCycleForUpdateCheck:SPUUpdateCheckUpdates
            error:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]];
        DrainMainQueue();
        Check(engine.checks == 4 && [[client snapshot][@"phase"] isEqualToString:@"cancelled"],
            @"cancelling the CDN package download does not restart it");
    }
    [client stop];
    [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:host.bundleIdentifier];
}

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        if (argc > 1 && strcmp(argv[1], "--self-host") == 0) {
            NSBundle *host = [NSBundle mainBundle];
            Check([[host bundleIdentifier] hasPrefix:@"io.github.polobread.KeyKeyUpdaterIsolatedTest.SelfHost."],
                  @"self-host regression must use an isolated app identity");
            FakeEngine *localEngine = [[[FakeEngine alloc] init] autorelease];
            KeyKeyMacUpdater *local = [[[KeyKeyMacUpdater alloc] initWithHostBundle:host
                engine:localEngine compositionCheck:nil] autorelease];
            Check([local valueForKey:@"_preferences"] == [NSUserDefaults standardUserDefaults],
                  @"own bundle must use standard defaults, not an invalid same-name suite");
            [local start];
            NSTimer *first = [local valueForKey:@"_automaticTimer"];
            Check(first && [first.fireDate timeIntervalSinceNow] > 590 &&
                  [first.fireDate timeIntervalSinceNow] <= 600 && first.timeInterval == 0,
                  @"first check is one deadline ten minutes after startup");
            Check(localEngine.checks == 0, @"startup does not immediately contact the feed");
            [local checkForUpdates];
            NSTimer *next = [local valueForKey:@"_automaticTimer"];
            Check([next.fireDate timeIntervalSinceNow] > 604790 &&
                  [next.fireDate timeIntervalSinceNow] <= 604800 && next.timeInterval == 0,
                  @"an attempt schedules one weekly deadline without minute polling");
            Check([[NSUserDefaults standardUserDefaults] objectForKey:@"KeyKeyLastUpdateAttempt"] != nil,
                  @"production identity persists its attempt date");
            [local updater:nil didFinishUpdateCycleForUpdateCheck:SPUUpdateCheckUpdates error:nil];
            // A missing preferences store must still retain the weekly memory deadline.
            [local setValue:nil forKey:@"_preferences"];
            [local checkForUpdates];
            Check([[[local valueForKey:@"_automaticTimer"] fireDate] timeIntervalSinceNow] > 604790,
                  @"persistence failure cannot cause a rapid retry");
            [local stop];
            Check([local valueForKey:@"_automaticTimer"] == nil, @"stop removes weekly scheduling");
            KeyKeyMacUpdater *reopened = [[[KeyKeyMacUpdater alloc] initWithHostBundle:host
                engine:[[[FakeEngine alloc] init] autorelease] compositionCheck:nil] autorelease];
            [reopened start];
            Check([[[reopened valueForKey:@"_automaticTimer"] fireDate] timeIntervalSinceNow] > 604780,
                  @"restart retains the last attempt instead of checking again in ten minutes");
            [reopened stop];
            [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[host bundleIdentifier]];
            NSLog(@"Self-host update scheduling checks passed");
            return 0;
        }
        // Load only the pinned SDK's comparator; never start its network updater.
        NSString *framework = [NSString stringWithUTF8String:getenv("KEYKEY_TEST_SPARKLE_FRAMEWORK") ?: ""];
        NSError *loadError = nil;
        Check([[NSBundle bundleWithPath:framework] loadAndReturnError:&loadError], @"pinned Sparkle comparator loads");
        id<SUVersionComparison> comparator = [[[NSClassFromString(@"SUStandardVersionComparator") alloc] init] autorelease];
        for (NSArray *pair in @[@[@"1.3.1", @"1.3.2b1"], @[@"1.3.2b1", @"1.3.2b2"],
                               @[@"1.3.2b2", @"1.3.2b10"], @[@"1.3.2b10", @"1.3.2"],
                               @[@"1.3.2", @"1.3.3b1"]]) {
            Check([comparator compareVersion:pair[0] toVersion:pair[1]] == NSOrderedAscending,
                @"beta iterations and final release are monotonically ordered");
        }
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
        NSString *key = [[NSData dataWithBytes:(unsigned char[32]){1} length:32] base64EncodedStringWithOptions:0];
        // Missing/malformed configuration must never start or call a network engine.
        NSArray *feeds = @[@"", @"http://example.invalid/feed.xml", @"https://user:pass@example.invalid/feed.xml",
            @"https://example.invalid/feed.xml#fragment", @42];
        for (id feed in feeds) {
            FakeEngine *engine = [[[FakeEngine alloc] init] autorelease];
            KeyKeyMacUpdater *client = [[[KeyKeyMacUpdater alloc] initWithHostBundle:Bundle(root, feed, key) engine:engine compositionCheck:nil] autorelease];
            [client start]; [client checkForUpdates]; [client setAutomaticChecks:YES];
            Check(![[client snapshot][@"configured"] boolValue] && engine.starts == 0 && engine.checks == 0,
                @"unsafe/missing feed remains offline");
            Check(!engine.automaticallyChecksForUpdates, @"unconfigured automatic toggle cannot opt in");
        }
        for (id invalidKey in @[@"", @"not-base64", @42, [[NSMutableData dataWithLength:31] base64EncodedStringWithOptions:0]]) {
            FakeEngine *engine = [[[FakeEngine alloc] init] autorelease];
            KeyKeyMacUpdater *client = [[[KeyKeyMacUpdater alloc] initWithHostBundle:Bundle(root, @"https://example.invalid/feed.xml", invalidKey) engine:engine compositionCheck:nil] autorelease];
            [client start]; Check(engine.starts == 0, @"bad public key remains offline");
        }
        FakeEngine *engine = [[[FakeEngine alloc] init] autorelease];
        engine.sendsProfile = YES; engine.downloadsAutomatically = YES;
        __block BOOL composing = NO;
        KeyKeyMacUpdater *client = [[[KeyKeyMacUpdater alloc] initWithHostBundle:Bundle(root, @"https://example.invalid/feed.xml", key)
            engine:engine compositionCheck:^BOOL { return composing; }] autorelease];
        [client start]; [client start];
        Check(engine.starts == 1 && [[client snapshot][@"configured"] boolValue], @"start is idempotent");
        Check(!engine.sendsProfile && !engine.downloadsAutomatically, @"privacy and visible installation are enforced");
        Check([[client snapshot][@"automatic"] boolValue] && [client valueForKey:@"_automaticTimer"] != nil &&
            !engine.automaticallyChecksForUpdates, @"fresh client defaults to bounded weekly checks with native scheduling disabled");
        for (NSString *preference in @[@"KeyKeyAutomaticChecks", @"SUEnableAutomaticChecks"]) {
            for (NSNumber *saved in @[@NO, @YES]) {
                NSBundle *host = Bundle(root, @"https://example.invalid/feed.xml", key);
                NSUserDefaults *defaults = [[[NSUserDefaults alloc] initWithSuiteName:[host bundleIdentifier]] autorelease];
                [defaults setBool:[saved boolValue] forKey:preference];
                FakeEngine *savedEngine = [[[FakeEngine alloc] init] autorelease];
                KeyKeyMacUpdater *savedClient = [[[KeyKeyMacUpdater alloc] initWithHostBundle:host
                    engine:savedEngine compositionCheck:nil] autorelease];
                [savedClient start];
                Check([[savedClient snapshot][@"automatic"] boolValue] == [saved boolValue],
                    @"saved automatic preference survives initialization");
                [savedClient setAutomaticChecks:NO];
                [savedClient stop];
                KeyKeyMacUpdater *reopened = [[[KeyKeyMacUpdater alloc] initWithHostBundle:host
                    engine:[[[FakeEngine alloc] init] autorelease] compositionCheck:nil] autorelease];
                [reopened start];
                Check(![[reopened snapshot][@"automatic"] boolValue], @"explicit opt-out survives restart");
                [reopened stop];
                [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[host bundleIdentifier]];
            }
        }
        [client setAutomaticChecks:YES]; Check([[client snapshot][@"automatic"] boolValue] && !engine.automaticallyChecksForUpdates,
            @"explicit opt in uses the bounded weekly query path instead of native background queries");
        [client setAutomaticChecks:NO]; Check(![[client snapshot][@"automatic"] boolValue], @"explicit opt out works");
        Check([[client feedURLStringForUpdater:nil] isEqualToString:@"https://example.invalid/feed.xml"], @"reviewed feed is pinned");
        Check([[client feedParametersForUpdater:nil sendingSystemProfile:YES] count] == 0, @"no custom profiling parameters");
        [client checkForUpdates]; [client checkForUpdates];
        Check(engine.checks == 1 && [[client snapshot][@"checking"] boolValue], @"duplicate checks are blocked");
        id<SPUUserDriver> focusDriver = [[[NSClassFromString(@"KeyKeyMacUserDriver") alloc] init] autorelease];
        FocusRecordingDriver *recording = [[[FocusRecordingDriver alloc] init] autorelease];
        [(id)focusDriver setValue:client forKey:@"owner"];
        [(id)focusDriver setValue:recording forKey:@"standard"];
        NSApplication *originalApplication = NSApp;
        FocusRecordingApplication *focusApplication = [[[FocusRecordingApplication alloc] init] autorelease];
        FocusRecordingWindow *updateWindow = [[[FocusRecordingWindow alloc] init] autorelease];
        updateWindow.visible = YES; updateWindow.level = NSNormalWindowLevel; updateWindow.windowController = recording;
        FocusRecordingWindow *otherWindow = [[[FocusRecordingWindow alloc] init] autorelease];
        otherWindow.visible = YES; otherWindow.level = NSNormalWindowLevel; otherWindow.windowController = [NSNull null];
        focusApplication.windows = @[updateWindow, otherWindow];
        NSApp = (NSApplication *)focusApplication;
        [focusDriver showUpdateFoundWithAppcastItem:nil state:nil reply:^(SPUUserUpdateChoice choice) {}];
        [focusDriver showDownloadInitiatedWithCancellation:^{}];
        [focusDriver showReadyToInstallAndRelaunch:^(SPUUserUpdateChoice choice) {}];
        Check([recording.events isEqual:@[@"found", @"focus", @"download", @"focus", @"ready", @"focus"]],
              @"manual update windows receive focus after creation, including ready to install");
        Check(updateWindow.level > NSFloatingWindowLevel && updateWindow.level < NSModalPanelWindowLevel &&
              updateWindow.orderedFront == 3, @"manual Sparkle windows stay above Preferences and below system modal panels");
        Check(otherWindow.level == NSNormalWindowLevel && otherWindow.orderedFront == 0,
              @"input-method and unrelated windows are never raised");
        updateWindow.level = NSNormalWindowLevel; updateWindow.orderedFront = 0;

        [recording.events removeAllObjects];
        [client setValue:@NO forKey:@"_manualCheck"];
        [focusDriver showUpdateFoundWithAppcastItem:nil state:nil reply:^(SPUUserUpdateChoice choice) {}];
        Check([recording.events isEqual:@[@"found"]], @"weekly checks never request foreground focus");
        Check(updateWindow.level == NSNormalWindowLevel && updateWindow.orderedFront == 0,
              @"weekly checks never change update window level or ordering");
        NSApp = originalApplication;

        [client setValue:@YES forKey:@"_manualCheck"];

        FakeItem *item = [[[FakeItem alloc] init] autorelease];
        item.displayVersionString = @"1.3.3"; item.installationType = @"package";
        item.fileURL = [NSURL URLWithString:@"https://example.invalid/KeyKey.pkg.zip"];
        NSError *error = nil;
        Check([client updater:nil shouldProceedWithUpdate:(id)item updateCheck:SPUUpdateCheckUpdates error:&error], @"HTTPS package is accepted for Sparkle validation");
        for (NSString *url in @[@"http://example.invalid/KeyKey.pkg.zip", @"https://example.invalid/update.exe",
                               @"https://user@example.invalid/KeyKey.pkg.zip", @"https://example.invalid/KeyKey.pkg.zip#x"]) {
            item.fileURL = [NSURL URLWithString:url];
            Check(![client updater:nil shouldProceedWithUpdate:(id)item updateCheck:SPUUpdateCheckUpdates error:&error] && error,
                @"non-package/unsafe enclosure is rejected");
        }
        item.fileURL = [NSURL URLWithString:@"https://example.invalid/KeyKey.pkg.zip"];
        [client updater:nil didFindValidUpdate:(id)item];
        Check([[client snapshot][@"latestVersion"] isEqualToString:@"1.3.3"], @"found version is visible");
        [client updater:nil willDownloadUpdate:(id)item withRequest:nil];
        Check([[client snapshot][@"phase"] isEqualToString:@"downloading"], @"download state is visible");
        [client userDidCancelDownload:nil];
        [client updater:nil didFinishUpdateCycleForUpdateCheck:SPUUpdateCheckUpdates
            error:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]];
        Check([[client snapshot][@"phase"] isEqualToString:@"cancelled"] && [[client snapshot][@"canCheck"] boolValue], @"cancel allows retry");
        [client checkForUpdates];
        [client updater:nil didFinishUpdateCycleForUpdateCheck:SPUUpdateCheckUpdates
            error:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:nil]];
        Check([[client snapshot][@"phase"] isEqualToString:@"failed"] && ![[client snapshot][@"checking"] boolValue], @"offline error clears busy state");
        [client checkForUpdates];
        [client updater:(id)engine didFinishUpdateCycleForUpdateCheck:SPUUpdateCheckUpdates
            error:[NSError errorWithDomain:@"SUSparkleErrorDomain" code:SUNoUpdateError userInfo:nil]];
        Check([[client snapshot][@"phase"] isEqualToString:@"no-update"] && [[client snapshot][@"canCheck"] boolValue],
              @"no-update result is not reported as a failure and allows retry");
        [client checkForUpdates];
        __block int cancellations = 0;
        [client beginCheckWithCancellation:^{ cancellations++; }];
        NSTimer *deadlineTimer = [client valueForKey:@"_checkTimer"];
        Check(fabs([deadlineTimer.fireDate timeIntervalSinceNow] - 10) < 0.5, @"query total deadline is 10 seconds");
        [client checkTimedOut:deadlineTimer];
        [client updater:(id)engine didFinishUpdateCycleForUpdateCheck:SPUUpdateCheckUpdates error:nil];
        Check(cancellations == 1 && ![[client snapshot][@"checking"] boolValue] &&
            [[client snapshot][@"canCheck"] boolValue] && [[client snapshot][@"message"] containsString:@"逾時"],
            @"timeout cancels native query, preserves timeout result, and permits manual retry");
        int previousChecks = engine.checks;
        [client updater:nil didFindValidUpdate:(id)item];
        Check([[client snapshot][@"message"] containsString:@"逾時"] && [client valueForKey:@"_checkTimer"] == nil,
            @"late results cannot replace timeout and no retry is scheduled");
        [client checkForUpdates];
        Check(engine.checks == previousChecks + 1, @"manual retry starts a new native query");
        [client beginCheckWithCancellation:^{ cancellations++; }];
        [client updaterDidNotFindUpdate:(id)engine error:nil];
        Check([client valueForKey:@"_checkTimer"] == nil && ![[client snapshot][@"checking"] boolValue],
            @"no-update result ends checking before any user acknowledgement");
        [client updater:(id)engine didFinishUpdateCycleForUpdateCheck:SPUUpdateCheckUpdates error:nil];
        __block int installs = 0;
        composing = YES;
        Check([client updater:nil shouldPostponeRelaunchForUpdate:(id)item untilInvokingBlock:^{ installs++; }], @"pending composition postpones restart");
        [client resumeInstallationIfSafe];
        Check(installs == 0 && ![client updaterShouldRelaunchApplication:(id)engine], @"composition is never committed/discarded by updater");
        composing = NO;
        [client resumeInstallationIfSafe]; [client resumeInstallationIfSafe];
        Check(installs == 1 && [client updaterShouldRelaunchApplication:(id)engine], @"finished composition resumes exactly once");
        composing = YES;
        Check(![client updaterShouldRelaunchApplication:(id)engine], @"new composition also blocks resumed native installation");
        Check([client updater:nil shouldPostponeRelaunchForUpdate:(id)item untilInvokingBlock:^{ installs++; }], @"second pending install can be cancelled on stop");
        [client stop]; composing = NO; [client resumeInstallationIfSafe];
        NSDictionary *stopped = [client snapshot];
        Check(![client updaterShouldRelaunchApplication:(id)engine], @"stopped client cannot resume native installation");
        Check(![client updater:(id)engine shouldProceedWithUpdate:(id)item updateCheck:SPUUpdateCheckUpdates error:NULL],
              @"stopped updater rejects late update selection without changing state");
        [client updater:nil didFindValidUpdate:(id)item];
        [client updater:nil didFinishUpdateCycleForUpdateCheck:SPUUpdateCheckUpdates error:nil];
        Check(installs == 1 && [[client snapshot] isEqualToDictionary:stopped], @"stop ignores stale callbacks and cancels pending install");
        FakeEngine *broken = [[[FakeEngine alloc] init] autorelease]; broken.failStart = YES;
        KeyKeyMacUpdater *failed = [[[KeyKeyMacUpdater alloc] initWithHostBundle:Bundle(root, @"https://example.invalid/feed.xml", key)
            engine:broken compositionCheck:nil] autorelease];
        [failed start]; [failed checkForUpdates];
        Check(![[failed snapshot][@"configured"] boolValue] && broken.checks == 0, @"initialization failure stays offline");
        Check([[failed snapshot][@"message"] containsString:@"invalid helper"], @"initialization error is reported");
        NSBundle *channelHost = Bundle(root, @"https://example.invalid/channels/stable.xml", key);
        FakeEngine *channelEngine = [[[FakeEngine alloc] init] autorelease];
        KeyKeyMacUpdater *channelClient = [[[KeyKeyMacUpdater alloc] initWithHostBundle:channelHost
            engine:channelEngine compositionCheck:nil] autorelease];
        [channelClient start];
        Check(![[channelClient snapshot][@"beta"] boolValue], @"beta defaults off including beta-capable builds");
        Check([[channelClient feedURLStringForUpdater:nil] hasSuffix:@"/stable.xml"], @"fresh client uses stable");
        Check([channelClient setBetaUpdates:YES] && [[channelClient snapshot][@"beta"] boolValue] &&
            [[channelClient feedURLStringForUpdater:nil] hasSuffix:@"/beta.xml"], @"explicit beta opt-in uses reviewed endpoint");
        Check(channelEngine.checks == 0, @"channel toggle does not initiate a network check");
        [channelClient checkForUpdates];
        Check(![channelClient setBetaUpdates:NO], @"cannot change channels during update cycle");
        [channelClient updater:nil didFinishUpdateCycleForUpdateCheck:SPUUpdateCheckUpdates error:nil];
        channelEngine.sessionInProgress = YES;
        Check(![channelClient setBetaUpdates:NO], @"cannot change channels during native session");
        channelEngine.sessionInProgress = NO;
        Check([channelClient setBetaUpdates:NO] && ![[channelClient snapshot][@"beta"] boolValue] &&
            [[channelClient feedURLStringForUpdater:nil] hasSuffix:@"/stable.xml"], @"opt-out returns to stable");
        Check(![failed setBetaUpdates:YES], @"missing beta endpoint cannot silently fall back");
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[channelHost bundleIdentifier]];
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[client valueForKey:@"_host"] bundleIdentifier]];

        CheckFeedFallback(root, key, NO);
        CheckFeedFallback(root, key, YES);
        CheckPackageFallback(root, key, NO);
        CheckPackageFallback(root, key, YES);

        // Real pinned Sparkle + a loopback TCP listener that never completes
        // TLS. This models a dead CDN without any external traffic or alerts.
        [NSApplication sharedApplication];
        int listener = socket(AF_INET, SOCK_STREAM, 0);
        struct sockaddr_in address = {0};
        address.sin_family = AF_INET; address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        Check(listener >= 0 && bind(listener, (struct sockaddr *)&address, sizeof(address)) == 0 && listen(listener, 4) == 0,
            @"inert loopback endpoint starts");
        socklen_t addressSize = sizeof(address);
        getsockname(listener, (struct sockaddr *)&address, &addressSize);
        NSBundle *networkHost = Bundle(root, [NSString stringWithFormat:@"https://127.0.0.1:%u/feed.xml", ntohs(address.sin_port)], key);
        KeyKeyMacUpdater *networkClient = [[[KeyKeyMacUpdater alloc] initWithHostBundle:networkHost engine:nil compositionCheck:nil] autorelease];
        id<SPUUserDriver> driver = [[[NSClassFromString(@"KeyKeyMacUserDriver") alloc] init] autorelease];
        [(id)driver setValue:networkClient forKey:@"owner"];
        id<KeyKeyMacUpdateEngine> native = [[[NSClassFromString(@"SPUUpdater") alloc]
            initWithHostBundle:networkHost applicationBundle:networkHost userDriver:driver delegate:networkClient] autorelease];
        [networkClient setValue:native forKey:@"_engine"];
        [networkClient start];
        Check([[networkClient snapshot][@"configured"] boolValue], [NSString stringWithFormat:@"real updater starts: %@", [networkClient snapshot][@"message"]]);
        NSTimeInterval began = [NSDate timeIntervalSinceReferenceDate];
        [networkClient checkForUpdates];
        __block BOOL heartbeat = NO;
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{ heartbeat = YES; }];
        while ([NSDate timeIntervalSinceReferenceDate] - began < 13 &&
            (![[networkClient snapshot][@"message"] containsString:@"逾時"] || [native sessionInProgress]))
            [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        NSTimeInterval elapsed = [NSDate timeIntervalSinceReferenceDate] - began;
        Check(heartbeat && elapsed >= 9.5 && elapsed < 12 && [[networkClient snapshot][@"message"] containsString:@"逾時"] &&
            ![native sessionInProgress] && [[networkClient snapshot][@"canCheck"] boolValue],
            [NSString stringWithFormat:@"native stalled query cancels after 10 seconds without blocking UI (%.2fs, %@)", elapsed, [networkClient snapshot]]);
        [networkClient stop]; close(listener);
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[networkHost bundleIdentifier]];
        [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
        printf("PASS %d macOS updater assertions (isolated engine + stalled loopback TLS; no install/external network)\n", passed);
    }
    return 0;
}
