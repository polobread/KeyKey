// Copyright (c) 2026 Chui Ping Cheng. MIT License.
#import "../KeyKeyMacUpdater.h"

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
- (void)dealloc { [_lastUpdateCheckDate release]; [super dealloc]; }
@end

@interface FakeItem : NSObject
@property(nonatomic, retain) NSURL *fileURL;
@property(nonatomic, copy) NSString *installationType, *displayVersionString;
@end
@implementation FakeItem
- (void)dealloc { [_fileURL release]; [_installationType release]; [_displayVersionString release]; [super dealloc]; }
@end

static NSBundle *Bundle(NSString *root, id feed, id key)
{
    NSString *app = [root stringByAppendingPathComponent:[[NSUUID UUID].UUIDString stringByAppendingString:@".app"]];
    NSString *contents = [app stringByAppendingPathComponent:@"Contents"];
    [[NSFileManager defaultManager] createDirectoryAtPath:contents withIntermediateDirectories:YES attributes:nil error:NULL];
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithDictionary:@{
        @"CFBundleIdentifier":@"io.github.polobread.KeyKeyUpdaterIsolatedTest",
        @"CFBundleVersion":@"1.3.2", @"CFBundleShortVersionString":@"1.3.2", @"CFBundlePackageType":@"APPL"}];
    if (feed) [info setObject:feed forKey:@"SUFeedURL"];
    if (key) [info setObject:key forKey:@"SUPublicEDKey"];
    [info writeToFile:[contents stringByAppendingPathComponent:@"Info.plist"] atomically:YES];
    return [NSBundle bundleWithPath:app];
}

int main(int argc, const char *argv[])
{
    @autoreleasepool {
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
        Check(!engine.automaticallyChecksForUpdates, @"first start does not opt in");
        [client setAutomaticChecks:YES]; Check(engine.automaticallyChecksForUpdates, @"explicit opt in works");
        [client setAutomaticChecks:NO]; Check(!engine.automaticallyChecksForUpdates, @"explicit opt out works");
        Check([[client feedURLStringForUpdater:nil] isEqualToString:@"https://example.invalid/feed.xml"], @"reviewed feed is pinned");
        Check([[client feedParametersForUpdater:nil sendingSystemProfile:YES] count] == 0, @"no custom profiling parameters");
        [client checkForUpdates]; [client checkForUpdates];
        Check(engine.checks == 1 && [[client snapshot][@"checking"] boolValue], @"duplicate checks are blocked");
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
        __block int installs = 0;
        composing = YES;
        Check([client updater:nil shouldPostponeRelaunchForUpdate:(id)item untilInvokingBlock:^{ installs++; }], @"pending composition postpones restart");
        [client resumeInstallationIfSafe];
        Check(installs == 0 && ![client mayTerminateForUpdate], @"composition is never committed/discarded by updater");
        composing = NO;
        [client resumeInstallationIfSafe]; [client resumeInstallationIfSafe];
        Check(installs == 1 && [client mayTerminateForUpdate], @"finished composition resumes exactly once");
        composing = YES;
        Check(![client mayTerminateForUpdate], @"late new composition blocks termination");
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
        [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
        printf("PASS %d macOS updater assertions (isolated engine; no install or network)\n", passed);
    }
    return 0;
}
