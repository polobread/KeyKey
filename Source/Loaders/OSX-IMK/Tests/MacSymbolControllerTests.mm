// Copyright (c) 2026 Chui Ping Cheng. MIT License.
// Exercise the real symbol controller, views and NIBs with an isolated data
// provider. Never create an IMK server, activate the app, or touch user data.
#import "../CVSymbolController.h"
#import "../OpenVanillaController.h"
#import <objc/runtime.h>
#include <sqlite3.h>

NSString *CVLoaderUpdateCannedMessagesNotification = @"CVLoaderUpdateCannedMessagesNotification";
static NSArray *currentCategories;
static NSString *sentText;

@implementation OpenVanillaLoader
+ (OpenVanillaLoader *)sharedInstance {
    static OpenVanillaLoader *instance = [[OpenVanillaLoader alloc] init];
    return instance;
}
+ (PVLoaderService *)sharedLoaderService {
    static PVLoaderService service("zh-Hant");
    return currentCategories.count ? &service : NULL;
}
- (NSArray *)mergedCannedMessagesArray { return currentCategories; }
@end

@implementation OpenVanillaController
+ (void)sendComposedStringToCurrentlyActiveContext:(NSString *)text {
    [sentText release]; sentText = [text copy];
}
@end

static void Check(BOOL value, NSString *message) {
    if (!value) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
static void SuppressWindowOrdering(id self, SEL selector, id sender) {}

static NSArray *ReadCategories(NSString *path) {
    sqlite3 *db = NULL;
    Check(sqlite3_open_v2(path.fileSystemRepresentation, &db, SQLITE_OPEN_READONLY, NULL) == SQLITE_OK,
          @"open the bundled database read-only");
    sqlite3_stmt *stmt = NULL;
    Check(sqlite3_prepare_v2(db, "SELECT value FROM prepopulated_service_data WHERE key='canned_messages'",
                           -1, &stmt, NULL) == SQLITE_OK && sqlite3_step(stmt) == SQLITE_ROW,
          @"read the shipped symbol data");
    NSData *data = [NSData dataWithBytes:sqlite3_column_blob(stmt, 0) length:sqlite3_column_bytes(stmt, 0)];
    NSDictionary *plist = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable
                                                                    format:NULL error:NULL];
    NSArray *categories = [[plist objectForKey:@"CannedMessages"] retain];
    sqlite3_finalize(stmt); sqlite3_close(db);
    Check(categories.count == 17, @"all 17 shipped categories are present");
    return [categories autorelease];
}
static void PostData(void) {
    [[NSNotificationCenter defaultCenter] postNotificationName:CVLoaderUpdateCannedMessagesNotification
                                                       object:[OpenVanillaLoader sharedInstance]];
}
static void CheckPopulated(CVSymbolController *controller, NSArray *categories) {
    NSPopUpButton *popup = [controller valueForKey:@"_popUpButton"];
    NSArray *views = [controller valueForKey:@"_viewArray"];
    NSView *content = [controller valueForKey:@"_symbolContentView"];
    printf("source_categories=%lu popup_items=%ld view_controllers=%lu content_height=%.0f\n",
           (unsigned long)categories.count, (long)popup.numberOfItems, (unsigned long)views.count,
           content.frame.size.height);
    Check(popup.numberOfItems == (NSInteger)categories.count && views.count == categories.count,
          @"the window contains every category");
    Check(content.subviews.count == 1 && content.frame.size.height > 0, @"symbol content is visible in the view");
    Check(!controller.window.isVisible, @"the fixture never displays a window on the user's desktop");
    NSDictionary *first = categories[0];
    Check([first[@"IsSymbolButtonList"] isEqual:@"true"], @"first category contains symbol buttons");
    NSView *firstView = [views[0] view];
    NSButton *button = firstView.subviews[0];
    [button performClick:nil];
    Check([sentText isEqual:first[@"Buttons"][0]], @"selecting a symbol still dispatches the right text");
}
int main(int argc, char **argv) {
    @autoreleasepool {
        Check(argc == 3, @"usage: SymbolTests DATABASE before|after|retry|refresh|empty");
        [NSApplication sharedApplication];
        // Keep actual CVSymbolController.showWindow: logic, but prevent AppKit
        // from bringing any test window onto the user's desktop.
        Method method = class_getInstanceMethod([NSWindowController class], @selector(showWindow:));
        class_replaceMethod([NSWindowController class], @selector(showWindow:),
                            (IMP)SuppressWindowOrdering, method_getTypeEncoding(method));
        NSArray *categories = ReadCategories([NSString stringWithUTF8String:argv[1]]);
        NSString *scenario = [NSString stringWithUTF8String:argv[2]];
        currentCategories = @[];
        if ([scenario isEqual:@"before"]) { currentCategories = categories; PostData(); }
        CVSymbolController *controller = [[CVSymbolController alloc] init];
        if ([scenario isEqual:@"after"] || [scenario isEqual:@"refresh"] || [scenario isEqual:@"empty"]) {
            currentCategories = categories; PostData();
        }
        if ([scenario isEqual:@"retry"]) {
            currentCategories = categories;
            [controller showWindow:nil]; // Data is ready even if no notification reaches us.
        }
        CheckPopulated(controller, categories);
        if ([scenario isEqual:@"refresh"]) {
            PostData(); PostData();
            CheckPopulated(controller, categories); // No duplicate categories after repeated refresh.
            NSPopUpButton *popup = [controller valueForKey:@"_popUpButton"];
            [popup selectItemAtIndex:16]; [controller toggleSymbol:popup];
            NSArray *views = [controller valueForKey:@"_viewArray"];
            NSView *content = [controller valueForKey:@"_symbolContentView"];
            Check(content.subviews[0] == [views[16] view], @"the real SmileyView NIB is usable");
        }
        if ([scenario isEqual:@"empty"]) {
            currentCategories = @[]; PostData();
            NSPopUpButton *popup = [controller valueForKey:@"_popUpButton"];
            NSView *content = [controller valueForKey:@"_symbolContentView"];
            Check(popup.numberOfItems == 0 && content.subviews.count == 0 && content.frame.size.height == 0,
                  @"an empty refresh removes stale content");
            [controller toggleSymbol:popup]; // A pending selection must not index an empty array.
            currentCategories = categories; PostData();
            CheckPopulated(controller, categories);
        }
        [controller release];
        printf("PASS: %s\n", scenario.UTF8String);
    }
    return 0;
}
