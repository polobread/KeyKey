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
@end

@interface KeyKeyMacUpdater : NSObject <SPUUpdaterDelegate>
{
    NSBundle *_host;
    id _controller;
    id<KeyKeyMacUpdateEngine> _engine;
    NSURL *_feed;
    NSString *_phase;
    NSString *_message;
    NSString *_latestVersion;
    BOOL _configured, _started, _stopped, _busy, _installationRequested;
    BOOL (^_compositionCheck)(void);
    void (^_pendingInstallation)(void);
    NSTimer *_installationTimer;
}
- (instancetype)initWithHostBundle:(NSBundle *)host engine:(id<KeyKeyMacUpdateEngine>)engine
                 compositionCheck:(BOOL (^)(void))compositionCheck;
- (void)start;
- (void)stop;
- (NSDictionary *)snapshot;
- (void)checkForUpdates;
- (void)setAutomaticChecks:(BOOL)enabled;
- (BOOL)mayTerminateForUpdate;
- (void)resumeInstallationIfSafe;
@end
