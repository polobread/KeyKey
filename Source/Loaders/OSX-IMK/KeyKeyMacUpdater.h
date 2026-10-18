// Copyright (c) 2026 Chui Ping Cheng. MIT License.
#import <Cocoa/Cocoa.h>
#import <Sparkle/Sparkle.h>

// Small adapter seam for isolated tests. Production uses Sparkle's real updater.
@protocol KeyKeyMacUpdateEngine <NSObject>
@property(nonatomic) BOOL automaticallyChecksForUpdates;
@property(nonatomic, readonly) BOOL canCheckForUpdates;
@property(nonatomic, readonly) BOOL sessionInProgress;
@property(nonatomic, readonly) NSDate *lastUpdateCheckDate;
- (BOOL)startUpdater:(NSError **)error;
- (void)checkForUpdates;
- (void)setSendsSystemProfile:(BOOL)value;
- (void)setAutomaticallyDownloadsUpdates:(BOOL)value;
- (void)resetUpdateCycle;
@end

@interface KeyKeyMacUpdater : NSObject <SPUUpdaterDelegate, SPUStandardUserDriverDelegate>
{
    NSBundle *_host;
    id _controller;
    id<KeyKeyMacUpdateEngine> _engine;
    NSURL *_feed;
    NSURL *_stableFeed, *_betaFeed;
    NSUserDefaults *_preferences;
    NSDate *_automaticNotBefore, *_lastUpdateAttempt;
    NSString *_phase;
    NSString *_message;
    NSString *_latestVersion;
    BOOL _configured, _started, _stopped, _busy, _installationRequested;
    BOOL _betaEnabled, _keyValid;
    BOOL _manualCheck, _automaticChecks, _checkTimedOut;
    BOOL (^_compositionCheck)(void);
    void (^_pendingInstallation)(void);
    NSTimer *_installationTimer;
    NSTimer *_checkTimer, *_automaticTimer;
    void (^_cancelCheck)(void);
}
- (instancetype)initWithHostBundle:(NSBundle *)host engine:(id<KeyKeyMacUpdateEngine>)engine
                 compositionCheck:(BOOL (^)(void))compositionCheck;
- (void)start;
- (void)stop;
- (NSDictionary *)snapshot;
- (void)checkForUpdates;
- (void)setAutomaticChecks:(BOOL)enabled;
- (BOOL)setBetaUpdates:(BOOL)enabled;
- (void)resumeInstallationIfSafe;
- (void)beginCheckWithCancellation:(void (^)(void))cancellation;
- (void)checkTimedOut:(NSTimer *)timer;
@end
