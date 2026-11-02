// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#include <assert.h>
#include <limits.h>
static void check(BOOL value) { assert(value); }
@interface OpenVanillaLoader : NSObject
@property(retain) NSMutableArray* edits;
- (NSString*)userPhraseDBBackendIdentifier;
- (BOOL)applyUserPhraseEdit:(NSDictionary*)edit expectedBackend:(NSString*)backend;
- (void)userPhraseDBDeleteRow:(int)row;
- (void)userPhraseDBSetNewReading:(NSString*)value forPhraseAtRow:(int)row;
- (void)userPhraseDBSetPhrase:(NSString*)value atRow:(int)row;
@end
@implementation OpenVanillaLoader
- (void)record:(NSString*)type row:(int)row value:(NSString*)value {
    [self.edits addObject:@{@"backend": [self userPhraseDBBackendIdentifier],
        @"type": type, @"row": @(row), @"value": value ?: @""}];
}
- (void)userPhraseDBDeleteRow:(int)row { [self record:@"remove" row:row value:nil]; }
- (void)userPhraseDBSetNewReading:(NSString*)value forPhraseAtRow:(int)row { [self record:@"reading" row:row value:value]; }
- (void)userPhraseDBSetPhrase:(NSString*)value atRow:(int)row { [self record:@"phrase" row:row value:value]; }
// ACTUAL_LOADER_METHODS
@end
int main(void) {
    @autoreleasepool {
        OpenVanillaLoader* server = [[[OpenVanillaLoader alloc] init] autorelease];
        server.edits = [NSMutableArray array];
        NSString* rustToken = [[server userPhraseDBBackendIdentifier] copy];
        check([rustToken isEqualToString:@"guanyinma"]);
        check([server applyUserPhraseEdit:@{@"type": @"remove", @"row": @2} expectedBackend:rustToken]);
        check([server applyUserPhraseEdit:@{@"type": @"phrase", @"row": @0, @"value": @"士事"} expectedBackend:rustToken]);
        check([server applyUserPhraseEdit:@{@"type": @"reading", @"row": @0, @"value": @"ㄕˋ,ㄕˋ"} expectedBackend:rustToken]);
        check(server.edits.count == 3 && [server.edits.lastObject[@"backend"] isEqualToString:@"guanyinma"]);
        NSUInteger before = server.edits.count;
        for (id token in @[[NSNull null], @0, @"unknown", @"manjusri"]) {
            check(![server applyUserPhraseEdit:@{@"type": @"remove", @"row": @0} expectedBackend:token]);
        }
        check(![server applyUserPhraseEdit:@{@"type": @"remove", @"row": @0} expectedBackend:nil]);
        for (id edit in @[
            @[], @{}, @{@"type": @"remove"}, @{@"type": @"unknown", @"row": @0},
            @{@"type": @"remove", @"row": @0, @"extra": @1},
            @{@"type": @"remove", @"row": @(-1)}, @{@"type": @"remove", @"row": @1.5},
            @{@"type": @"remove", @"row": @((long long)INT_MAX + 1)},
            @{@"type": @"remove", @"row": @"0"},
            @{@"type": @"phrase", @"row": @0, @"value": @""},
            @{@"type": @"reading", @"row": @0, @"value": @1},
            @{@"type": @"phrase", @"row": @0, @"value": @"字", @"extra": @1}
        ]) check(![server applyUserPhraseEdit:edit expectedBackend:rustToken]);
        check(server.edits.count == before);
        check([server applyUserPhraseEdit:@{@"type": @"phrase", @"row": @0, @"value": @"新"} expectedBackend:rustToken]);
        check([server.edits.lastObject[@"backend"] isEqualToString:@"guanyinma"]);
        [rustToken release];
        puts("PASS: actual loader accepts only the Rust store token and rejects invalid edits before mutation");
    }
}
