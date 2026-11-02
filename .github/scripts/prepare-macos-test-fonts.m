// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
// Prepare the production font without NSFont triggering FontRegistryUI in CI.
#import <Foundation/Foundation.h>
#import <CoreText/CoreText.h>
#import <dispatch/dispatch.h>
static BOOL PrepareFont(NSString *requestedFont) {
    CTFontDescriptorRef descriptor = CTFontDescriptorCreateWithNameAndSize((__bridge CFStringRef)requestedFont, 13);
    __block BOOL matched = NO, failed = NO;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    bool started = CTFontDescriptorMatchFontDescriptorsWithProgressHandler(
        (__bridge CFArrayRef)@[(__bridge id)descriptor], NULL,
        ^bool(CTFontDescriptorMatchingState state, CFDictionaryRef parameters) {
            if (state == kCTFontDescriptorMatchingDidMatch) {
                NSArray *results = ((__bridge NSDictionary *)parameters)[(__bridge id)kCTFontDescriptorMatchingResult];
                for (id result in results) {
                    id name = CFBridgingRelease(CTFontDescriptorCopyAttribute((__bridge CTFontDescriptorRef)result, kCTFontNameAttribute));
                    id url = CFBridgingRelease(CTFontDescriptorCopyAttribute((__bridge CTFontDescriptorRef)result, kCTFontURLAttribute));
                    NSLog(@"Matched font %@ at %@", name, url);
                    if ([name isEqual:requestedFont] && [url isKindOfClass:NSURL.class] && [url isFileURL]
                        && [[NSFileManager defaultManager] isReadableFileAtPath:[url path]]) {
                        matched = YES;
                    }
                }
            } else if (state == kCTFontDescriptorMatchingDidFailWithError) {
                NSLog(@"Font preparation failed: %@", ((__bridge NSDictionary *)parameters)[(__bridge id)kCTFontDescriptorMatchingError]);
                failed = YES;
            } else if (state == kCTFontDescriptorMatchingDidFinish) {
                dispatch_semaphore_signal(done);
            } else if (state == kCTFontDescriptorMatchingWillBeginDownloading) {
                NSLog(@"Downloading Apple %@ font through Core Text", requestedFont);
            }
            return true;
        });
    CFRelease(descriptor);
    if (!started || dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC))) {
        NSLog(@"Timed out preparing Apple %@ font", requestedFont); return NO;
    }
    return matched && !failed;
}
int main(int argc, const char **argv) { @autoreleasepool {
    if (argc == 1) return PrepareFont(@"STHeiti") ? 0 : 1;
    for (int index = 1; index < argc; ++index) {
        if (!PrepareFont([NSString stringWithUTF8String:argv[index]])) return 1;
    }
    return 0;
}}
