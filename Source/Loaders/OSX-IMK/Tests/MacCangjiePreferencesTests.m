// Copyright (c) 2026 Chui Ping Cheng. MIT License.
#import "../../../PreferenceApplications/OSX/TakaoCangjie.h"
#import "../../../PreferenceApplications/OSX/TakaoHelper.h"

static NSString *testPath;
@implementation TakaoHelper
+ (NSString *)plistFilePath:(NSString *)filename { return testPath; }
@end

static void Check(BOOL value, NSString *message) {
    if (!value) { NSLog(@"FAIL: %@", message); exit(1); }
}

static TakaoCangjie *Controller(void) {
    TakaoCangjie *controller = [[[TakaoCangjie alloc] init] autorelease];
    for (NSString *key in @[@"_useDynamicFrequencyCheckBox", @"_shouldCommitAtMaximumRadicalLengthCheckBox",
         @"_clearReadingBufferAtCompositionErrorCheckBox", @"_composeWhenTypingCheckBox",
         @"_prefixCandidatesCheckBox", @"_useCharactersSupportedByEncodingCheckBox"]) {
        NSButton *button = [[[NSButton alloc] initWithFrame:NSZeroRect] autorelease];
        [button setButtonType:NSButtonTypeSwitch];
        [controller setValue:button forKey:key];
    }
    NSPopUpButton *override = [[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO] autorelease];
    [override addItemsWithTitles:@[@"None", @"Mixed", @"Half"]];
    [controller setValue:override forKey:@"_useOverrideTablePopUpButton"];
    [controller awakeFromNib];
    return controller;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        Check(argc == 2, @"isolated profile path required");
        testPath = [NSString stringWithUTF8String:argv[1]];
        [NSApplication sharedApplication]; // Do not activate or connect to the installed IMK.
        TakaoCangjie *controller = Controller();
        NSButton *realtime = [controller valueForKey:@"_composeWhenTypingCheckBox"];
        NSButton *prefix = [controller valueForKey:@"_prefixCandidatesCheckBox"];
        NSButton *clear = [controller valueForKey:@"_clearReadingBufferAtCompositionErrorCheckBox"];
        Check(!realtime.intValue && !prefix.intValue && !prefix.enabled, @"desktop defaults off");
        [realtime setIntValue:1]; [controller setAutoCompose:realtime];
        Check(prefix.enabled && !clear.intValue, @"realtime enables prefix and disables error clearing");
        [prefix setIntValue:1]; [controller writePreference:prefix];
        [clear setIntValue:1]; [controller setClearOnError:clear];
        Check(!realtime.intValue && !prefix.enabled && prefix.intValue, @"clear suspends but preserves prefix");
        controller = Controller();
        realtime = [controller valueForKey:@"_composeWhenTypingCheckBox"];
        prefix = [controller valueForKey:@"_prefixCandidatesCheckBox"];
        clear = [controller valueForKey:@"_clearReadingBufferAtCompositionErrorCheckBox"];
        Check(!realtime.intValue && !prefix.enabled && prefix.intValue && clear.intValue, @"saved values survive reopening");
        [realtime setIntValue:1]; [controller setAutoCompose:realtime];
        Check(prefix.enabled && prefix.intValue && !clear.intValue, @"realtime restores saved prefix");
        NSDictionary *saved = [NSDictionary dictionaryWithContentsOfFile:testPath];
        Check([saved[@"PrefixCandidates"] isEqual:@"true"] &&
              [saved[@"ComposeWhileTyping"] isEqual:@"true"] &&
              [saved[@"ClearReadingBufferAtCompositionError"] isEqual:@"false"], @"plist persists dependencies");
        NSMutableDictionary *legacy = [[saved mutableCopy] autorelease];
        legacy[@"ClearReadingBufferAtCompositionError"] = @"true";
        [legacy writeToFile:testPath atomically:YES];
        controller = Controller();
        Check(![[controller valueForKey:@"_clearReadingBufferAtCompositionErrorCheckBox"] intValue],
              @"legacy conflicts prioritize realtime");
        puts("macOS Cangjie settings: defaults, dependency, exclusion and persistence passed");
    }
    return 0;
}
