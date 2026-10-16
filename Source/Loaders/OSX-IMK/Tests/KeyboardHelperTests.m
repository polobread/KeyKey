// Copyright (c) 2026 Chui-Ping Cheng. BSD-3-Clause; see ../../../../LICENSE.txt.
#import "../CVKeyboardHelper.h"
#include <unistd.h>

static CFArrayRef fixtures;
static BOOL failList;
static int passed;
static void Check(BOOL value, NSString *message)
{
    if (!value) { NSLog(@"FAIL: %@", message); exit(1); }
    passed++;
}
// Redirect TIS functions for this test and CVKeyboardHelper.m. The identifier
// is dynamically allocated to catch incorrect releases of borrowed properties.
CFArrayRef KKTestCreateInputSourceList(CFDictionaryRef filter, Boolean all)
{
    Check(all && CFEqual(CFDictionaryGetValue(filter, kTISPropertyInputSourceType),
                         kTISTypeKeyboardLayout), @"query is limited to keyboard layouts");
    return failList ? NULL : CFRetain(fixtures);
}
void *KKTestGetInputSourceProperty(TISInputSourceRef source, CFStringRef key)
{
    return (void *)CFDictionaryGetValue((CFDictionaryRef)source, key);
}
int main(void)
{
    @autoreleasepool {
        CFStringRef sourceID = CFStringCreateWithFormat(NULL, NULL, CFSTR("com.example.dynamic.layout.%d"), getpid());
        NSDictionary *valid = @{(id)kTISPropertyInputSourceType: (id)kTISTypeKeyboardLayout,
                                (id)kTISPropertyInputSourceID: (id)sourceID};
        NSDictionary *missing = @{(id)kTISPropertyInputSourceType: (id)kTISTypeKeyboardLayout};
        fixtures = (CFArrayRef)[@[valid, missing] retain];
        CFIndex original = CFGetRetainCount(sourceID);
        CVKeyboardHelper *helper = [CVKeyboardHelper new];
        Check([helper validateKeyboardLayout:(NSString *)sourceID], @"valid layout is available");
        Check([[helper validKeyboardLayouts] count] == 1, @"missing identifiers ignored");
        Check(CFGetRetainCount(sourceID) > original, @"borrowed identifier retained by result array");
        [helper loadValidKeyboardLayouts];
        Check([[helper validKeyboardLayouts] count] == 1, @"reload does not duplicate entries");
        failList = YES;
        [helper loadValidKeyboardLayouts];
        Check([[helper validKeyboardLayouts] count] == 0, @"unavailable TIS list clears stale cache safely");
        [helper release];
        Check(CFGetRetainCount(sourceID) == original, @"Get-rule ownership preserved after cleanup");
        CFRelease(fixtures);
        CFRelease(sourceID);
        NSLog(@"PASS: %d keyboard helper checks (fake TIS)", passed);
    }
}
