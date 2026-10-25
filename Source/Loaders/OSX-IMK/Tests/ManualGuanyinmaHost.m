// Copyright (c) 2026 Chui-Ping Cheng. BSD-3-Clause; see ../../../../LICENSING.md.
// Manual IMK host: no registration, selection or IMK launch occurs at startup.
#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#import <CoreServices/CoreServices.h>
#import <CommonCrypto/CommonDigest.h>
#import "../OpenVanillaService.h"

static NSString *SourceID(TISInputSourceRef source)
{
    if (!source) return nil;
    CFTypeRef value = TISGetInputSourceProperty(source, kTISPropertyInputSourceID);
    return value && CFGetTypeID(value) == CFStringGetTypeID() ? (__bridge NSString *)value : nil;
}

static TISInputSourceRef CopySource(NSString *identifier, CFIndex *count)
{
    NSDictionary *filter = @{(__bridge NSString *)kTISPropertyInputSourceID: identifier};
    CFArrayRef sources = TISCreateInputSourceList((__bridge CFDictionaryRef)filter, true);
    if (count) *count = sources ? CFArrayGetCount(sources) : -1;
    TISInputSourceRef source = sources && CFArrayGetCount(sources) == 1
        ? (TISInputSourceRef)CFRetain(CFArrayGetValueAtIndex(sources, 0)) : NULL;
    if (sources) CFRelease(sources);
    return source;
}

static BOOL ReadSourceBoolean(TISInputSourceRef source, CFStringRef key, BOOL *result)
{
    CFTypeRef value = source ? TISGetInputSourceProperty(source, key) : NULL;
    if (!value || CFGetTypeID(value) != CFBooleanGetTypeID()) return NO;
    *result = CFBooleanGetValue(value);
    return YES;
}

static NSDictionary *SourceProperties(TISInputSourceRef source)
{
    if (!source) return @{@"available": @NO};
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithObject:@YES forKey:@"available"];
    NSArray *names = @[@"sourceID", @"bundleID", @"category", @"type", @"enabled", @"selected", @"enableCapable", @"selectCapable"];
    const CFStringRef keys[] = {kTISPropertyInputSourceID, kTISPropertyBundleID,
        kTISPropertyInputSourceCategory, kTISPropertyInputSourceType, kTISPropertyInputSourceIsEnabled,
        kTISPropertyInputSourceIsSelected, kTISPropertyInputSourceIsEnableCapable, kTISPropertyInputSourceIsSelectCapable};
    for (NSUInteger i = 0; i < names.count; i++) {
        CFTypeRef value = TISGetInputSourceProperty(source, keys[i]);
        result[names[i]] = value ? (__bridge id)value : NSNull.null;
    }
    return result;
}

static CFIndex BundleSourceCount(NSString *bundleID)
{
    NSDictionary *filter = @{(__bridge NSString *)kTISPropertyBundleID: bundleID};
    CFArrayRef sources = TISCreateInputSourceList((__bridge CFDictionaryRef)filter, true);
    CFIndex count = sources ? CFArrayGetCount(sources) : -1;
    if (sources) CFRelease(sources);
    return count;
}

static NSString *CountDescription(CFIndex count)
{
    return count == -1 ? @"NULL" : count == -2 ? @"未查詢" : [NSString stringWithFormat:@"%ld", count];
}

static NSString *SHA256(NSString *path)
{
    NSInputStream *stream = [NSInputStream inputStreamWithFileAtPath:path];
    [stream open];
    CC_SHA256_CTX context;
    CC_SHA256_Init(&context);
    uint8_t buffer[65536];
    NSInteger length;
    while ((length = [stream read:buffer maxLength:sizeof(buffer)]) > 0)
        CC_SHA256_Update(&context, buffer, (CC_LONG)length);
    [stream close];
    if (length < 0) return nil;
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &context);
    NSMutableString *value = [NSMutableString string];
    for (NSUInteger i = 0; i < sizeof(digest); i++) [value appendFormat:@"%02x", digest[i]];
    return value;
}

static id PlainText(id value)
{
    return [value isKindOfClass:NSAttributedString.class] ? [value string] : value;
}

@interface HostTextView : NSTextView
@property(copy) void (^record)(NSDictionary *);
@end
@implementation HostTextView
- (NSDictionary *)hostInputState
{
    NSTextInputContext *context = self.inputContext;
    NSEvent *current = NSApp.currentEvent;
    return @{@"contextSource": context.selectedKeyboardInputSource ?: @"unavailable",
        @"hasInputContext": @(context != nil), @"contextClientMatches": @(context.client == self),
        @"currentContextMatches": @(context != nil && [NSTextInputContext currentInputContext] == context),
        @"appActive": @(NSApp.active), @"keyWindow": @(self.window.keyWindow),
        @"mainWindow": @(self.window.mainWindow), @"firstResponder": @(self.window.firstResponder == self),
        @"editable": @(self.editable), @"hasMarkedText": @(self.hasMarkedText),
        @"markedRange": NSStringFromRange(self.markedRange),
        @"currentEventType": current ? @(current.type) : NSNull.null};
}
- (void)keyDown:(NSEvent *)event
{
    if (self.record) self.record(@{@"event": @"keyDown", @"characters": event.characters ?: @"",
        @"charactersIgnoringModifiers": event.charactersIgnoringModifiers ?: @"",
        @"keyCode": @(event.keyCode), @"modifierFlags": @(event.modifierFlags),
        @"isARepeat": @(event.isARepeat), @"eventTimestamp": @(event.timestamp),
        @"hostState": [self hostInputState]});
    [super keyDown:event];
    if (self.record) self.record(@{@"event": @"keyDownComplete", @"keyCode": @(event.keyCode),
        @"hostText": self.string ?: @"", @"hostState": [self hostInputState]});
}
- (void)insertText:(id)value replacementRange:(NSRange)range
{
    if (self.record) self.record(@{@"event": @"insertText", @"text": PlainText(value) ?: @"",
        @"replacement": NSStringFromRange(range), @"before": self.string ?: @"", @"hostState": [self hostInputState]});
    [super insertText:value replacementRange:range];
    if (self.record) self.record(@{@"event": @"textAfterInsert", @"text": self.string ?: @"",
        @"selection": NSStringFromRange(self.selectedRange)});
}
- (void)setMarkedText:(id)value selectedRange:(NSRange)selected replacementRange:(NSRange)replacement
{
    if (self.record) self.record(@{@"event": @"setMarkedText", @"text": PlainText(value) ?: @"",
        @"selection": NSStringFromRange(selected), @"replacement": NSStringFromRange(replacement),
        @"hostState": [self hostInputState]});
    [super setMarkedText:value selectedRange:selected replacementRange:replacement];
}
- (void)unmarkText
{
    if (self.record) self.record(@{@"event": @"unmarkText", @"text": self.string ?: @"", @"hostState": [self hostInputState]});
    [super unmarkText];
}
@end

@interface ManualHost : NSObject <NSApplicationDelegate, NSWindowDelegate>
@end
@implementation ManualHost {
    NSDictionary *_config;
    NSWindow *_window;
    HostTextView *_text;
    NSTextField *_status;
    NSPopUpButton *_method;
    NSPopUpButton *_core;
    NSFileHandle *_log;
    TISInputSourceRef _previous;
    TISInputSourceRef _testSource;
    BOOL _enabledByHost;
    BOOL _managed;
    BOOL _activationPending;
    NSUInteger _activationGeneration;
    BOOL _serviceLaunchPending;
}

- (void)record:(NSDictionary *)event
{
    NSMutableDictionary *entry = [event mutableCopy];
    entry[@"time"] = @([NSDate date].timeIntervalSince1970);
    TISInputSourceRef current = TISCopyCurrentKeyboardInputSource();
    entry[@"inputSource"] = SourceID(current) ?: @"unavailable";
    if (current) CFRelease(current);
    NSData *data = [NSJSONSerialization dataWithJSONObject:entry options:0 error:nil];
    if (_log && data) {
        [_log writeData:data];
        [_log writeData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
        [_log synchronizeFile];
    }
}

- (void)status:(NSString *)message
{
    _status.stringValue = message;
    [self record:@{@"event": @"status", @"message": message}];
}

- (BOOL)validateConfiguration
{
    NSString *tag = _config[@"tag"];
    if (![tag isKindOfClass:NSString.class] || !tag.length || tag.length > 40 ||
        [tag rangeOfString:@"^[a-z0-9][a-z0-9-]*$" options:NSRegularExpressionSearch].location == NSNotFound)
        return NO;
    NSString *prefix = [@"io.github.polobread.guanyinma.imktest." stringByAppendingString:tag];
    NSString *expectedPath = [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Input Methods"]
        stringByAppendingPathComponent:[NSString stringWithFormat:@"KeyKey Guanyinma IMK Test %@.app", tag]];
    return [_config[@"bundle_id"] isEqual:[prefix stringByAppendingString:@".inputmethod.KeyKey"]] &&
        [_config[@"source_id"] isEqual:_config[@"bundle_id"]] &&
        [_config[@"loader_identifier"] isEqual:[prefix stringByAppendingString:@".loader"]] &&
        [_config[@"loader_name"] isEqual:[@"KeyKey-Guanyinma-IMK-Test-" stringByAppendingString:tag]] &&
        [_config[@"server_name"] isEqual:[_config[@"bundle_id"] stringByAppendingString:@"_Connection"]] &&
        [_config[@"do_name"] isEqual:[@"GuanyinmaIMKTestService_" stringByAppendingString:tag]] &&
        [_config[@"install_path"] isEqual:expectedPath] &&
        [_config[@"schema_version"] isEqual:@1];
}

- (BOOL)validateInstalledBundle
{
    if (![self validateConfiguration]) return NO;
    NSString *path = _config[@"install_path"];
    // Registration is allowed only for this exact per-user, non-symlink test app.
    if (![[path stringByResolvingSymlinksInPath] isEqual:path]) return NO;
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:
        [path stringByAppendingPathComponent:@"Contents/Info.plist"]];
    if (![info[@"CFBundleIdentifier"] isEqual:_config[@"bundle_id"]] ||
        ![info[@"TISInputSourceID"] isEqual:_config[@"source_id"]] ||
        ![info[@"InputMethodConnectionName"] isEqual:_config[@"server_name"]] ||
        ![info[@"KeyKeyIsolatedIMKTest"] isEqual:_config[@"tag"]] ||
        ![info[@"KeyKeyIsolatedLoaderIdentifier"] isEqual:_config[@"loader_identifier"]] ||
        ![info[@"KeyKeyIsolatedLoaderName"] isEqual:_config[@"loader_name"]] ||
        ![info[@"KeyKeyIsolatedDOName"] isEqual:_config[@"do_name"]] ||
        info[@"CFBundleURLTypes"] || info[@"SUFeedURL"] || info[@"KeyKeyBetaFeedURL"] || info[@"SUPublicEDKey"])
        return NO;
    NSString *executable = info[@"CFBundleExecutable"];
    if (![executable isKindOfClass:NSString.class] || ![executable.lastPathComponent isEqual:executable]) return NO;
    NSString *binary = [path stringByAppendingPathComponent:[@"Contents/MacOS/" stringByAppendingString:executable]];
    NSString *database = [path stringByAppendingPathComponent:_config[@"database_relative_path"]];
    return [SHA256(binary) isEqual:_config[@"executable_sha256"]] &&
        [SHA256(database) isEqual:_config[@"database_sha256"]];
}

- (BOOL)isTestSelected
{
    TISInputSourceRef current = TISCopyCurrentKeyboardInputSource();
    BOOL selected = [SourceID(current) isEqual:_config[@"source_id"]];
    if (current) CFRelease(current);
    return selected;
}

- (id<OpenVanillaService>)service
{
    if (!_managed || ![self isTestSelected]) return nil;
    NSDistantObject *proxy = [NSConnection rootProxyForConnectionWithRegisteredName:_config[@"do_name"] host:nil];
    [proxy setProtocolForProxy:@protocol(OpenVanillaService)];
    [[proxy connectionForProxy] setRequestTimeout:3];
    [[proxy connectionForProxy] setReplyTimeout:3];
    return (id<OpenVanillaService>)proxy;
}

- (void)launchIsolatedService:(id)sender
{
    if (_serviceLaunchPending) { [self status:@"隔離服務啟動要求尚未完成；未重複要求。"]; return; }
    if (![self validateInstalledBundle]) {
        [self status:@"隔離安裝路徑／命名／檔案驗證失敗；未啟動服務。"]; return;
    }
    NSURL *installedURL = [NSURL fileURLWithPath:_config[@"install_path"] isDirectory:YES];
    NSURL *preferredURL = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:_config[@"bundle_id"]];
    NSString *expectedCanonical = [installedURL.path stringByResolvingSymlinksInPath];
    NSString *preferredCanonical = [preferredURL.path stringByResolvingSymlinksInPath];
    BOOL preferredMatches = preferredCanonical && [preferredCanonical isEqual:expectedCanonical];
    [self record:@{@"event": @"serviceLaunchValidation", @"expectedPath": installedURL.path,
        @"preferredPath": preferredURL.path ?: @"unavailable", @"preferredMatches": @(preferredMatches)}];
    if (!preferredMatches) {
        [self status:[NSString stringWithFormat:@"LaunchServices preferred=%@，與已驗證安裝路徑不符；未啟動服務。",
            preferredURL.path ?: @"unavailable"]]; return;
    }
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfURL:[installedURL URLByAppendingPathComponent:@"Contents/Info.plist"]];
    NSString *expectedExecutable = [[installedURL.path stringByAppendingPathComponent:@"Contents/MacOS"]
        stringByAppendingPathComponent:info[@"CFBundleExecutable"]];
    NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration configuration];
    configuration.activates = NO;
    configuration.createsNewApplicationInstance = NO;
    configuration.allowsRunningApplicationSubstitution = NO;
    configuration.addsToRecentItems = NO;
    _serviceLaunchPending = YES;
    [self record:@{@"event": @"serviceLaunchRequest", @"applicationURL": installedURL.path,
        @"expectedExecutable": expectedExecutable, @"activates": @NO, @"createsNewApplicationInstance": @NO,
        @"allowsRunningApplicationSubstitution": @NO}];
    [self status:@"已要求正常啟動精確的隔離背景服務；未操作 TIS／模式／按鍵。"];
    __weak ManualHost *weakSelf = self;
    [[NSWorkspace sharedWorkspace] openApplicationAtURL:installedURL configuration:configuration
        completionHandler:^(NSRunningApplication *application, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            ManualHost *host = weakSelf;
            if (!host) return;
            host->_serviceLaunchPending = NO;
            NSString *actualExecutable = application.executableURL.path;
            BOOL exactExecutable = actualExecutable && [[actualExecutable stringByResolvingSymlinksInPath]
                isEqual:[expectedExecutable stringByResolvingSymlinksInPath]];
            BOOL exactBundle = [application.bundleIdentifier isEqual:host->_config[@"bundle_id"]];
            BOOL verified = !error && application && !application.terminated && exactExecutable && exactBundle;
            [host record:@{@"event": @"serviceLaunchResult", @"success": @(verified),
                @"pid": application ? @(application.processIdentifier) : @0,
                @"executableURL": actualExecutable ?: @"unavailable", @"expectedExecutable": expectedExecutable,
                @"executableMatches": @(exactExecutable), @"bundleMatches": @(exactBundle),
                @"bundleID": application.bundleIdentifier ?: @"unavailable", @"terminated": @(application.terminated),
                @"errorDomain": error.domain ?: @"", @"errorCode": error ? @(error.code) : @0,
                @"errorDescription": error.localizedDescription ?: @""}];
            [host status:verified ? [NSString stringWithFormat:@"隔離服務已正常啟動（PID %d），執行檔路徑核對通過；自動啟動仍須另驗。", application.processIdentifier] :
                [NSString stringWithFormat:@"隔離服務啟動／路徑驗證未成功：%@（PID %d）；未操作 TIS。",
                    error.localizedDescription ?: actualExecutable ?: @"沒有服務結果", application.processIdentifier]];
        });
    }];
}

- (void)activate:(id)sender
{
    if (_managed) { [self status:_activationPending ? @"啟用確認中；可按還原取消。" : @"已啟用隔離來源；先還原後再重新啟用。"]; return; }
    if (![self validateInstalledBundle]) {
        [self status:@"隔離 App 尚未 stage，或命名／檔案驗證失敗；未呼叫 TIS。"]; return;
    }
    NSURL *installedURL = [NSURL fileURLWithPath:_config[@"install_path"] isDirectory:YES];
    OSStatus lsResult = LSRegisterURL((__bridge CFURLRef)installedURL, true);
    NSURL *preferredURL = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:_config[@"bundle_id"]];
    NSString *expectedCanonical = [installedURL.path stringByResolvingSymlinksInPath];
    NSString *preferredCanonical = [preferredURL.path stringByResolvingSymlinksInPath];
    BOOL preferredMatches = preferredCanonical && [preferredCanonical isEqual:expectedCanonical];
    [self record:@{@"event": @"launchServicesRegistration", @"registerResult": @(lsResult),
        @"expectedPath": installedURL.path, @"expectedCanonicalPath": expectedCanonical,
        @"preferredPath": preferredURL.path ?: @"unavailable",
        @"preferredCanonicalPath": preferredCanonical ?: @"unavailable", @"preferredMatches": @(preferredMatches)}];
    if (lsResult != noErr || !preferredMatches) {
        [self status:[NSString stringWithFormat:@"LaunchServices result=%d；preferred=%@；與已驗證安裝路徑不符或註冊失敗，未呼叫 TIS。",
            (int)lsResult, preferredURL.path ?: @"unavailable"]];
        return;
    }
    _previous = TISCopyCurrentKeyboardInputSource();
    if (!SourceID(_previous) || [SourceID(_previous) isEqual:_config[@"source_id"]]) {
        if (_previous) CFRelease(_previous);
        _previous = NULL;
        [self status:@"無法保存原來源，或目前已選此測試來源；未註冊。"]; return;
    }
    NSString *previousID = [SourceID(_previous) copy];
    OSStatus registerResult = TISRegisterInputSource((__bridge CFURLRef)[NSURL fileURLWithPath:_config[@"install_path"]]);
    CFIndex sourceCount = -2, bundleCount = -2;
    if (registerResult == noErr) {
        _testSource = CopySource(_config[@"source_id"], &sourceCount);
        bundleCount = BundleSourceCount(_config[@"bundle_id"]);
    }
    [self record:@{@"event": @"registrationResult", @"registerResult": @(registerResult),
        @"sourceQueryCount": @(sourceCount), @"bundleQueryCount": @(bundleCount),
        @"expectedSourceID": _config[@"source_id"], @"expectedBundleID": _config[@"bundle_id"],
        @"previousSourceID": previousID, @"sourceProperties": SourceProperties(_testSource)}];
    if (registerResult != noErr || !_testSource) {
        CFRelease(_previous); _previous = NULL;
        [self status:[NSString stringWithFormat:@"TIS 註冊 result=%d；source=%@／bundle=%@；未選取。須先確認系統可發現此來源。",
            (int)registerResult, CountDescription(sourceCount), CountDescription(bundleCount)]];
        return;
    }
    BOOL wasEnabled = NO;
    if (!ReadSourceBoolean(_testSource, kTISPropertyInputSourceIsEnabled, &wasEnabled)) {
        CFRelease(_previous); _previous = NULL; CFRelease(_testSource); _testSource = NULL;
        [self status:@"無法讀取測試來源原啟用狀態；未啟用／選取。"]; return;
    }
    _enabledByHost = !wasEnabled;
    _managed = YES;
    NSDictionary *recovery = @{@"schema_version": @1, @"previous_source_id": previousID,
        @"test_source_id": _config[@"source_id"], @"enabled_by_host": @(_enabledByHost)};
    BOOL saved = [recovery writeToFile:_config[@"recovery_path"] atomically:YES];
    [self record:@{@"event": @"recoverySaved", @"success": @(saved), @"originallyEnabled": @(wasEnabled)}];
    if (!saved) {
        BOOL restored = [self restoreSelection];
        [self status:[NSString stringWithFormat:@"無法保存還原資訊；未啟用／選取，restore=%@。", restored ? @"成功" : @"失敗"]]; return;
    }
    OSStatus enableResult = _enabledByHost ? TISEnableInputSource(_testSource) : noErr;
    [self record:@{@"event": @"enableResult", @"enableAttempted": @(_enabledByHost),
        @"enableResult": @(enableResult), @"originallyEnabled": @(wasEnabled)}];
    if (enableResult != noErr) {
        [self record:@{@"event": @"selectionResult", @"skipped": @YES, @"reason": @"enableFailed"}];
        BOOL restored = [self restoreSelection];
        [self status:[NSString stringWithFormat:@"隔離來源啟用 result=%d；未選取，restore=%@。",
            (int)enableResult, restored ? @"成功" : @"失敗"]]; return;
    }
    _activationPending = YES;
    NSUInteger generation = ++_activationGeneration;
    NSTimeInterval started = NSProcessInfo.processInfo.systemUptime;
    [self record:@{@"event": @"enableVerificationScheduled", @"generation": @(generation),
        @"intervalSeconds": @0.25, @"timeoutSeconds": @5.0}];
    [self status:@"啟用已接受；正等候系統狀態同步（最多 5 秒）。可按還原取消。"];
    __weak ManualHost *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf verifyEnabledForGeneration:generation attempt:1 started:started enableResult:enableResult];
    });
}

- (void)verifyEnabledForGeneration:(NSUInteger)generation attempt:(NSUInteger)attempt
                         started:(NSTimeInterval)started enableResult:(OSStatus)enableResult
{
    // The callback can never select after Restore/Close or a newer activation.
    if (!_managed || !_activationPending || generation != _activationGeneration) {
        [self record:@{@"event": @"enableVerificationCancelled", @"generation": @(generation),
            @"currentGeneration": @(_activationGeneration), @"attempt": @(attempt)}];
        return;
    }
    NSTimeInterval elapsed = NSProcessInfo.processInfo.systemUptime - started;
    CFIndex freshCount = -2;
    TISInputSourceRef fresh = CopySource(_config[@"source_id"], &freshCount);
    BOOL enabled = NO;
    BOOL enabledReadable = ReadSourceBoolean(fresh, kTISPropertyInputSourceIsEnabled, &enabled);
    [self record:@{@"event": @"enableVerification", @"generation": @(generation), @"attempt": @(attempt),
        @"elapsedSeconds": @(elapsed), @"sourceQueryCount": @(freshCount),
        @"enabledReadable": @(enabledReadable), @"enabled": @(enabled), @"sourceProperties": SourceProperties(fresh)}];
    if (fresh) {
        CFRelease(_testSource);
        _testSource = fresh;
    }
    if (fresh && enabledReadable && enabled) {
        _activationPending = NO;
        // Recheck after the query as well: no stale callback may cross this boundary.
        if (!_managed || generation != _activationGeneration) return;
        OSStatus selectResult = TISSelectInputSource(_testSource);
        BOOL selected = [self isTestSelected];
        [self record:@{@"event": @"selectionResult", @"generation": @(generation),
            @"selectResult": @(selectResult), @"selectedVerification": @(selected)}];
        if (selectResult != noErr || !selected) {
            BOOL restored = [self restoreSelection];
            [self status:[NSString stringWithFormat:@"隔離來源選取 result=%d／selected=%@（enable=%d）；restore=%@。",
                (int)selectResult, selected ? @"true" : @"false", (int)enableResult, restored ? @"成功" : @"失敗"]]; return;
        }
        _text.editable = YES;
        [_window makeFirstResponder:_text];
        [self record:@{@"event": @"activationComplete", @"success": @YES, @"generation": @(generation),
            @"enableResult": @(enableResult), @"selectResult": @(selectResult), @"elapsedSeconds": @(elapsed)}];
        [self status:@"已選隔離 IMK；請用實體鍵／Cua 在下方 NSTextView 輸入。註冊成功尚不代表中文輸入成功。"];
        return;
    }
    if (elapsed >= 5.0) {
        [self record:@{@"event": @"enableVerificationTimeout", @"generation": @(generation),
            @"attempt": @(attempt), @"elapsedSeconds": @(elapsed), @"rollback": @YES}];
        [self record:@{@"event": @"selectionResult", @"skipped": @YES, @"reason": @"enableVerificationTimeout"}];
        BOOL restored = [self restoreSelection];
        [self status:[NSString stringWithFormat:@"Enable result=%d，但 5 秒內未確認 enabled；未選取，rollback=%@。",
            (int)enableResult, restored ? @"成功" : @"失敗"]];
        return;
    }
    __weak ManualHost *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf verifyEnabledForGeneration:generation attempt:attempt + 1 started:started enableResult:enableResult];
    });
}

- (BOOL)restoreSelection
{
    if (_activationPending) {
        [self record:@{@"event": @"activationCancelled", @"generation": @(_activationGeneration), @"reason": @"restoreOrClose"}];
    }
    _activationPending = NO;
    ++_activationGeneration;
    if (!_managed) {
        [self record:@{@"event": @"restoreResult", @"success": @YES, @"skipped": @YES, @"reason": @"notManaged"}];
        return YES;
    }
    BOOL testSelected = [self isTestSelected];
    [self record:@{@"event": @"restoreBegin", @"testSelected": @(testSelected), @"enabledByHost": @(_enabledByHost)}];
    // Preserve a later user choice; only restore selection if still our source.
    if (testSelected) {
        NSString *previousID = SourceID(_previous);
        CFIndex previousCount = -2;
        TISInputSourceRef previous = previousID ? CopySource(previousID, &previousCount) : NULL;
        [self record:@{@"event": @"restorePreviousLookup", @"sourceQueryCount": @(previousCount),
            @"sourceProperties": SourceProperties(previous)}];
        if (!previous) {
            [self record:@{@"event": @"restoreResult", @"success": @NO, @"phase": @"previousLookup"}];
            return NO;
        }
        OSStatus selectResult = TISSelectInputSource(previous);
        CFRelease(previous);
        TISInputSourceRef current = TISCopyCurrentKeyboardInputSource();
        BOOL selectedPrevious = [SourceID(current) isEqual:previousID];
        if (current) CFRelease(current);
        [self record:@{@"event": @"restoreSelectionResult", @"selectResult": @(selectResult),
            @"selectedPreviousVerification": @(selectedPrevious), @"previousSourceID": previousID}];
        if (selectResult != noErr || !selectedPrevious) {
            [self record:@{@"event": @"restoreResult", @"success": @NO, @"phase": @"previousSelection"}];
            return NO;
        }
    } else {
        [self record:@{@"event": @"restoreSelectionResult", @"skipped": @YES, @"reason": @"preserveCurrentSelection"}];
    }
    if (_enabledByHost) {
        CFIndex count = -2;
        TISInputSourceRef source = CopySource(_config[@"source_id"], &count);
        BOOL enabled = NO;
        BOOL readable = ReadSourceBoolean(source, kTISPropertyInputSourceIsEnabled, &enabled);
        [self record:@{@"event": @"restoreDisableLookup", @"sourceQueryCount": @(count),
            @"enabledReadable": @(readable), @"sourceProperties": SourceProperties(source)}];
        if (!source || !readable || [self isTestSelected]) {
            if (source) CFRelease(source);
            [self record:@{@"event": @"restoreResult", @"success": @NO, @"phase": @"disableLookup"}];
            return NO;
        }
        OSStatus disableResult = enabled ? TISDisableInputSource(source) : noErr;
        CFRelease(source);
        [self record:@{@"event": @"restoreDisableResult", @"disableAttempted": @(enabled), @"disableResult": @(disableResult)}];
        CFIndex verifiedCount = -2;
        TISInputSourceRef verified = CopySource(_config[@"source_id"], &verifiedCount);
        BOOL stillEnabled = YES;
        BOOL verifiedReadable = ReadSourceBoolean(verified, kTISPropertyInputSourceIsEnabled, &stillEnabled);
        [self record:@{@"event": @"restoreDisableVerification", @"sourceQueryCount": @(verifiedCount),
            @"enabledReadable": @(verifiedReadable), @"enabled": @(stillEnabled), @"sourceProperties": SourceProperties(verified)}];
        if (verified) CFRelease(verified);
        if (disableResult != noErr || !verifiedReadable || stillEnabled) {
            [self record:@{@"event": @"restoreResult", @"success": @NO, @"phase": @"disableVerification"}];
            return NO;
        }
    } else {
        [self record:@{@"event": @"restoreDisableResult", @"skipped": @YES, @"reason": @"originallyEnabled"}];
    }
    if (_previous) CFRelease(_previous);
    if (_testSource) CFRelease(_testSource);
    _previous = _testSource = NULL;
    _enabledByHost = _managed = NO;
    _text.editable = NO;
    NSError *cleanupError = nil;
    BOOL removed = ![[NSFileManager defaultManager] fileExistsAtPath:_config[@"recovery_path"]] ||
        [[NSFileManager defaultManager] removeItemAtPath:_config[@"recovery_path"] error:&cleanupError];
    [self record:@{@"event": @"restoreResult", @"success": @YES, @"recoveryRemoved": @(removed),
        @"cleanupError": cleanupError.localizedDescription ?: @""}];
    return YES;
}

- (void)restore:(id)sender
{
    [self status:[self restoreSelection] ? @"已還原先前來源；僅停用由本工具啟用的隔離來源。" :
        @"還原／停用失敗；保留還原資訊，請在系統輸入選單手動還原後再試。"];
}

- (BOOL)readyForControlAllowMarked:(BOOL)allowMarked
{
    if (!_managed || ![self isTestSelected]) {
        [self status:@"先啟用並選取隔離測試來源。"]; return NO;
    }
    if (!allowMarked && _text.hasMarkedText) {
        [self status:@"仍有 marked text；請先確認／取消組字，再切換測試設定。"]; return NO;
    }
    return YES;
}

- (void)applyCore:(id)sender
{
    if (![self readyForControlAllowMarked:YES]) return;
    @try {
        id<OpenVanillaService> service = [self service];
        if (!service) { [self status:@"隔離 DO 尚未就緒；先在文字欄按一下，再重試。"]; return; }
        BOOL hadMarkedText = _text.hasMarkedText;
        NSString *textBefore = [_text.string copy] ?: @"";
        NSString *markedRangeBefore = NSStringFromRange(_text.markedRange);
        [self record:@{@"event": @"coreSelectionRequest", @"requestedGuanyinma": @(_core.indexOfSelectedItem == 1),
            @"hasMarkedText": @(hadMarkedText), @"hostText": textBefore, @"markedRange": markedRangeBefore}];
        NSDictionary *reply = [service setUseGuanyinmaCore:_core.indexOfSelectedItem == 1];
        [self record:@{@"event": @"coreSelection", @"reply": reply ?: @{},
            @"hasMarkedTextBefore": @(hadMarkedText), @"hostTextBefore": textBefore,
            @"markedRangeBefore": markedRangeBefore, @"hasMarkedTextAfter": @(_text.hasMarkedText),
            @"hostTextAfter": _text.string ?: @""}];
        [self status:[NSString stringWithFormat:@"隔離核心：%@", reply ?: @{}]];
        [_window makeFirstResponder:_text];
    } @catch (NSException *error) { [self status:[@"隔離 DO：" stringByAppendingString:error.reason ?: @"失敗"]]; }
}

- (void)applyMethod:(id)sender
{
    if (![self readyForControlAllowMarked:NO]) return;
    @try {
        id<OpenVanillaService> service = [self service];
        if (!service) { [self status:@"隔離 DO 尚未就緒；未改設定。"]; return; }
        NSString *path = [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Preferences"]
            stringByAppendingPathComponent:[_config[@"loader_identifier"] stringByAppendingString:@".plist"]];
        NSMutableDictionary *settings = [[NSDictionary dictionaryWithContentsOfFile:path] mutableCopy] ?: [NSMutableDictionary dictionary];
        NSString *method = _method.selectedItem.representedObject;
        settings[@"PrimaryInputMethod"] = method;
        if (![settings writeToFile:path atomically:YES]) { [self status:@"無法寫隔離設定；未 reload。"]; return; }
        [service reloadOpenVanilla];
        NSString *active = [service primaryInputMethod];
        [self record:@{@"event": @"methodSelection", @"requested": method, @"active": active ?: @"unavailable"}];
        [self status:[NSString stringWithFormat:@"隔離輸入法：%@", active ?: @"待 reload"]];
        [_window makeFirstResponder:_text];
    } @catch (NSException *error) { [self status:[@"隔離 DO：" stringByAppendingString:error.reason ?: @"失敗"]]; }
}

- (void)clearText:(id)sender
{
    if (_text.hasMarkedText) { [self status:@"請先確認／取消組字，再清空宿主文字。"]; return; }
    [self record:@{@"event": @"clearHostText", @"previousText": _text.string ?: @""}];
    _text.string = @"";
    [_window makeFirstResponder:_text];
}

- (NSButton *)button:(NSString *)title frame:(NSRect)frame action:(SEL)action
{
    NSButton *button = [NSButton buttonWithTitle:title target:self action:action];
    button.frame = frame;
    [_window.contentView addSubview:button];
    return button;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    NSURL *configURL = [[NSBundle mainBundle] URLForResource:@"HostConfiguration" withExtension:@"plist"];
    _config = [NSDictionary dictionaryWithContentsOfURL:configURL];
    if (![self validateConfiguration]) { NSLog(@"Invalid isolated IMK host configuration"); [NSApp terminate:nil]; return; }
    NSString *logPath = _config[@"log_path"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:logPath])
        [[NSFileManager defaultManager] createFileAtPath:logPath contents:nil attributes:nil];
    _log = [NSFileHandle fileHandleForWritingAtPath:logPath];
    [_log seekToEndOfFile];
    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 920, 630)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    _window.title = [@"Guanyinma 真 IMK 宿主 — " stringByAppendingString:_config[@"tag"]];
    _window.delegate = self;
    [_window center];
    [self button:@"啟用隔離測試輸入法" frame:NSMakeRect(16, 582, 210, 32) action:@selector(activate:)];
    [self button:@"還原來源" frame:NSMakeRect(234, 582, 120, 32) action:@selector(restore:)];
    [self button:@"清空文字" frame:NSMakeRect(360, 582, 110, 32) action:@selector(clearText:)];
    [self button:@"啟動隔離服務" frame:NSMakeRect(480, 582, 190, 32) action:@selector(launchIsolatedService:)];
    _core = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(16, 540, 180, 28) pullsDown:NO];
    [_core addItemsWithTitles:@[@"Manjusri", @"Guanyinma (Rust)"]];
    [_window.contentView addSubview:_core];
    [self button:@"套用核心" frame:NSMakeRect(202, 539, 110, 30) action:@selector(applyCore:)];
    _method = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(330, 540, 180, 28) pullsDown:NO];
    NSArray *methods = @[@[@"好打注音", @"SmartMandarin"], @[@"傳統注音", @"TraditionalMandarin"],
        @[@"倉頡", @"Generic-cj-cin"], @[@"簡易", @"Generic-simplex-cin"]];
    for (NSArray *method in methods) { [_method addItemWithTitle:method[0]]; _method.lastItem.representedObject = method[1]; }
    [_window.contentView addSubview:_method];
    [self button:@"套用輸入法" frame:NSMakeRect(518, 539, 130, 30) action:@selector(applyMethod:)];
    _status = [NSTextField wrappingLabelWithString:@"尚未呼叫 TIS。啟用按鈕才會註冊、啟用並暫時選取隔離來源。"];
    _status.frame = NSMakeRect(16, 476, 885, 52);
    [_window.contentView addSubview:_status];
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(16, 16, 888, 450)];
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    _text = [[HostTextView alloc] initWithFrame:NSMakeRect(0, 0, 870, 450)];
    _text.font = [NSFont systemFontOfSize:24];
    _text.richText = NO;
    _text.editable = NO;
    _text.verticallyResizable = YES;
    _text.horizontallyResizable = NO;
    _text.textContainer.widthTracksTextView = YES;
    __weak ManualHost *weakSelf = self;
    _text.record = ^(NSDictionary *event) { [weakSelf record:event]; };
    scroll.documentView = _text;
    [_window.contentView addSubview:scroll];
    [_window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [self record:@{@"event": @"hostReady", @"registeredByStartup": @NO}];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
    if ([self restoreSelection]) return NSTerminateNow;
    [self status:@"還原失敗，保留視窗及還原資訊；請手動還原後再退出。"]; return NSTerminateCancel;
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return YES; }
- (BOOL)windowShouldClose:(NSWindow *)sender
{
    if ([self restoreSelection]) return YES;
    [self status:@"還原失敗，暫不關閉；請手動還原後再試。"]; return NO;
}
- (void)applicationWillTerminate:(NSNotification *)notification { [self restoreSelection]; [_log closeFile]; }
@end

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        ManualHost *delegate = [ManualHost new];
        NSApp.delegate = delegate;
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        [NSApp run];
    }
    return 0;
}
