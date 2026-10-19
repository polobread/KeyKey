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
static BOOL legacyController;
static NSUInteger frontRequests;

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
static void RecordFrontRequest(id self, SEL selector) { ++frontRequests; }

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
static void CheckLayout(CVSymbolController *controller) {
    if (legacyController) return;
    NSPopUpButton *popup = [controller valueForKey:@"_popUpButton"];
    NSView *content = [controller valueForKey:@"_symbolContentView"];
    Check(NSMinY(popup.frame) - NSMaxY(content.frame) >= 10.0, @"popup and symbols have a visible gap");
    Check(NSContainsRect(controller.window.contentView.bounds, popup.frame), @"popup stays inside the content area");
    Check(NSContainsRect(controller.window.contentView.bounds, content.frame), @"symbol viewport stays inside the content area");
}
static void Snapshot(CVSymbolController *controller, NSString *name) {
    NSString *directory = [[[NSProcessInfo processInfo] environment] objectForKey:@"KEYKEY_SYMBOL_SNAPSHOT_DIR"];
    if (!directory) return;
    NSView *view = controller.window.contentView;
    view.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    [view layoutSubtreeIfNeeded];
    NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
    NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    Check([png writeToFile:[directory stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"png"]] atomically:YES],
          @"save the isolated view snapshot");
}
static void CheckPopulated(CVSymbolController *controller, NSArray *categories) {
    NSPopUpButton *popup = [controller valueForKey:@"_popUpButton"];
    NSArray *views = [controller valueForKey:@"_viewArray"];
    NSView *content = [controller valueForKey:@"_symbolContentView"];
    printf("source_categories=%lu popup_items=%ld view_controllers=%lu content_height=%.0f\n",
           (unsigned long)categories.count, (long)popup.numberOfItems, (unsigned long)views.count,
           content.frame.size.height);
    NSUInteger expected = categories.count + (legacyController ? 0 : 1);
    Check(popup.numberOfItems == (NSInteger)expected && views.count == expected,
          @"the window contains every category");
    Check(content.subviews.count == 1 && content.frame.size.height > 0, @"symbol content is visible in the view");
    Check(!controller.window.isVisible, @"the fixture never displays a window on the user's desktop");
    CheckLayout(controller);
    NSDictionary *first = categories[0];
    Check([first[@"IsSymbolButtonList"] isEqual:@"true"], @"first category contains symbol buttons");
    NSView *firstView = [views[0] view];
    NSButton *button = firstView.subviews[0];
    [button performClick:nil];
    Check([sentText isEqual:first[@"Buttons"][0]], @"selecting a symbol still dispatches the right text");
}
int main(int argc, char **argv) {
    @autoreleasepool {
        Check(argc == 3 || argc == 4, @"usage: SymbolTests DATABASE before|after|retry|refresh|empty|emoji|scale|panel|ordering [legacy]");
        legacyController = argc == 4 && strcmp(argv[3], "legacy") == 0;
        [NSApplication sharedApplication];
        // Keep actual CVSymbolController.showWindow: logic, but prevent AppKit
        // from bringing any test window onto the user's desktop.
        Method method = class_getInstanceMethod([NSWindowController class], @selector(showWindow:));
        class_replaceMethod([NSWindowController class], @selector(showWindow:),
                            (IMP)SuppressWindowOrdering, method_getTypeEncoding(method));
        Method front = class_getInstanceMethod([NSWindow class], @selector(orderFrontRegardless));
        IMP originalFront = method_getImplementation(front);
        class_replaceMethod([NSWindow class], @selector(orderFrontRegardless),
                            (IMP)RecordFrontRequest, method_getTypeEncoding(front));
        NSArray *categories = ReadCategories([NSString stringWithUTF8String:argv[1]]);
        NSString *scenario = [NSString stringWithUTF8String:argv[2]];
        currentCategories = @[];
        if ([scenario isEqual:@"before"]) { currentCategories = categories; PostData(); }
        CVSymbolController *controller = [[CVSymbolController alloc] init];
        if ([scenario isEqual:@"after"] || [scenario isEqual:@"refresh"] || [scenario isEqual:@"empty"] || [scenario isEqual:@"emoji"] || [scenario isEqual:@"scale"] || [scenario isEqual:@"panel"] || [scenario isEqual:@"ordering"]) {
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
            CheckLayout(controller);
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
        if ([scenario isEqual:@"emoji"]) {
            Snapshot(controller, @"symbols-spacing");
            NSPopUpButton *popup = [controller valueForKey:@"_popUpButton"];
            Check([[popup itemTitleAtIndex:17] isEqual:@"Emoji"], @"Emoji is the last category, as on Windows");
            [popup selectItemAtIndex:17]; [controller toggleSymbol:popup];
            CheckLayout(controller);
            NSArray *views = [controller valueForKey:@"_viewArray"];
            NSScrollView *scroll = (NSScrollView *)[views[17] view];
            Check([scroll isKindOfClass:[NSScrollView class]] && scroll.hasVerticalScroller,
                  @"all Emoji are in one scrollable grid");
            NSArray *buttons = [views[17] valueForKey:@"_buttonArray"];
            NSData *json = [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"ExpectedEmoji" ofType:@"json"]];
            NSArray *expected = [NSJSONSerialization JSONObjectWithData:json options:0 error:NULL];
            Check(expected.count == 200 && buttons.count == 200, @"exactly 200 Windows Emoji");
            for (NSUInteger i = 0; i < expected.count; ++i)
                Check([((NSButton *)buttons[i]).title isEqual:expected[i]], @"all Emoji strings and their order match Windows");
            NSButton *first = buttons[0], *last = buttons[199];
            Check(NSContainsRect(scroll.contentView.bounds, first.frame), @"the first Emoji starts in view");
            [first performClick:nil]; Check([sentText isEqual:expected[0]], @"first Emoji sends the full string");
            Snapshot(controller, @"emoji-top");
            [scroll.contentView scrollToPoint:NSZeroPoint]; [scroll reflectScrolledClipView:scroll.contentView];
            Check(NSContainsRect(scroll.contentView.bounds, last.frame), @"the last Emoji can be scrolled into view");
            [last performClick:nil]; Check([sentText isEqual:expected[199]], @"last Emoji sends the full string");
            [buttons[36] performClick:nil]; Check([sentText isEqual:expected[36]], @"variation selectors remain intact");
            Snapshot(controller, @"emoji-bottom");
            [popup selectItemAtIndex:0]; [controller toggleSymbol:popup];
            CheckLayout(controller);
        }
        if ([scenario isEqual:@"scale"]) {
            NSPopUpButton *popup = [controller valueForKey:@"_popUpButton"];
            [popup selectItemAtIndex:17]; [controller toggleSymbol:popup];
            NSView *root = controller.window.contentView;
            CGFloat originalWidth = root.frame.size.width;
            for (NSNumber *ratio in @[@1.5, @0.75, @3.5, @1.0]) {
                [controller setCandidateWindowScale:ratio.floatValue];
                Check(popup.indexOfSelectedItem == 17, @"rescaling preserves the selected category");
                CheckLayout(controller);
                CGFloat scale = root.frame.size.width / root.bounds.size.width;
                CGFloat yScale = root.frame.size.height / root.bounds.size.height;
                Check(fabs(scale - yScale) < 0.01, @"fonts, controls and both axes share one scale");
                Check(scale <= ratio.doubleValue + 0.01 && scale > 0, @"scale fits the requested size");
                Check(fabs(popup.menu.font.pointSize - [NSFont menuFontOfSize:0].pointSize * scale) < 0.1,
                      @"the expanded menu font follows the effective scale");
                if (ratio.doubleValue <= 1.5)
                    Check(fabs(scale - ratio.doubleValue) < 0.01, @"normal requested scales are applied exactly");
                NSScreen *screen = controller.window.screen ?: NSScreen.mainScreen;
                Check(NSContainsRect(NSInsetRect(screen.visibleFrame, -1, -1), controller.window.frame),
                      @"large symbol windows remain on screen");
                NSView *content = [controller valueForKey:@"_symbolContentView"];
                NSRect popupPixels = [popup convertRect:popup.bounds toView:nil];
                NSRect contentPixels = [content convertRect:content.bounds toView:nil];
                Check(NSMinY(popupPixels) - NSMaxY(contentPixels) >= 10.0 * scale,
                      @"spacing scales with the candidate-window ratio");
            }
            Check(fabs(root.frame.size.width - originalWidth) < 1.0, @"repeated scaling does not accumulate");
            [controller setCandidateWindowScale:1.5];
            Snapshot(controller, @"emoji-scale150");
            [popup selectItemAtIndex:0]; [controller toggleSymbol:popup];
            CheckLayout(controller);
            Snapshot(controller, @"symbols-scale150");
            [controller setCandidateWindowScale:1.0];
        }
        if ([scenario isEqual:@"panel"]) {
            NSWindow *window = controller.window;
            Class panelClass = NSClassFromString(@"CVDictionaryWindow");
            Check(panelClass && [window isKindOfClass:panelClass] && [window isKindOfClass:[NSPanel class]],
                  @"the real NIB creates the shipped custom panel, without falling back to NSWindow");
            NSPanel *panel = (NSPanel *)window;
            Check((panel.styleMask & NSWindowStyleMaskNonactivatingPanel) != 0, @"the NIB panel is nonactivating from creation");
            Check(panel.isFloatingPanel && panel.worksWhenModal && panel.becomesKeyOnlyIfNeeded && !panel.hidesOnDeactivate,
                  @"the palette works while other apps and settings are active");
            Check(!panel.canBecomeKeyWindow && !panel.canBecomeMainWindow, @"palette clicks cannot take the editor's keyboard focus");
            Check((panel.collectionBehavior & NSWindowCollectionBehaviorCanJoinAllSpaces) &&
                  (panel.collectionBehavior & NSWindowCollectionBehaviorFullScreenAuxiliary), @"palette supports Spaces and full-screen hosts");
            NSPanel *preferences = [[[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 100, 100)
                styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES] autorelease];
            preferences.level = NSFloatingWindowLevel; // TakaoPreference.m uses this level.
            Check(panel.level > preferences.level && panel.level > NSNormalWindowLevel && panel.level > NSModalPanelWindowLevel,
                  @"symbol panel is above preferences, normal editor windows and modal panels");
            NSArray *views = [controller valueForKey:@"_viewArray"];
            NSButton *button = [[views[0] view] subviews][0];
            Check([button acceptsFirstMouse:nil] && [[controller valueForKey:@"_popUpButton"] acceptsFirstMouse:nil],
                  @"symbol buttons and the category popup accept the initial click without activating the app");
            BOOL wasActive = NSApp.isActive;
            NSUInteger initialFront = frontRequests;
            [controller show:nil];
            Check(controller.isVisible && frontRequests == initialFront + 1, @"show raises the background panel without activating the app");
            [controller restoreWindowStatus];
            Check(frontRequests == initialFront + 2, @"host reactivation raises the open palette");
            [controller hide:nil];
            [controller restoreWindowStatus];
            Check(!controller.isVisible && frontRequests == initialFront + 2, @"explicit hide prevents automatic reopening");
            [controller show:nil];
            Check(![controller windowShouldClose:window] && !controller.isVisible, @"the close button clears visible intent");
            [controller restoreWindowStatus];
            Check(frontRequests == initialFront + 3 && NSApp.isActive == wasActive && !panel.isKeyWindow,
                  @"close stays closed and showing never activates the test app or takes key focus");
        }
        if ([scenario isEqual:@"ordering"]) {
            // Exercise real native ordering with this fixture's own invisible,
            // click-through windows. Never activate the app or inspect/control
            // any browser, Office window, or the user's foreground application.
            class_replaceMethod([NSWindow class], @selector(orderFrontRegardless),
                                originalFront, method_getTypeEncoding(front));
            NSWindow *panel = controller.window;
            panel.alphaValue = 0; panel.ignoresMouseEvents = YES;
            NSWindow *editor = [[[NSWindow alloc] initWithContentRect:NSMakeRect(20, 20, 100, 100)
                styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO] autorelease];
            NSWindow *preferences = [[[NSWindow alloc] initWithContentRect:NSMakeRect(30, 30, 100, 100)
                styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO] autorelease];
            NSPanel *dialog = [[[NSPanel alloc] initWithContentRect:NSMakeRect(40, 40, 100, 100)
                styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO] autorelease];
            editor.alphaValue = preferences.alphaValue = dialog.alphaValue = 0;
            editor.ignoresMouseEvents = preferences.ignoresMouseEvents = dialog.ignoresMouseEvents = YES;
            preferences.level = NSFloatingWindowLevel; dialog.level = NSModalPanelWindowLevel;
            // Model an active host's modal dialog while this test app stays inactive.
            dialog.hidesOnDeactivate = NO;
            BOOL wasActive = NSApp.isActive;
            [editor orderFrontRegardless]; [controller show:nil];
            // Bring settings and a modal-level window forward AFTER the palette.
            [preferences orderFrontRegardless]; [dialog orderFrontRegardless];
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
            // NSApplication.orderedWindows excludes NSPanel. Option 0 asks
            // for this process's window numbers only, including its panels.
            NSArray *ordered = [NSWindow windowNumbersWithOptions:0];
            NSNumber *paletteNumber = @(panel.windowNumber), *editorNumber = @(editor.windowNumber);
            NSNumber *settingsNumber = @(preferences.windowNumber), *dialogNumber = @(dialog.windowNumber);
            NSUInteger paletteIndex = [ordered indexOfObject:paletteNumber];
            printf("ordering own_windows=%lu palette_index=%lu editor_index=%lu settings_index=%lu modal_index=%lu\n",
                (unsigned long)ordered.count, (unsigned long)paletteIndex,
                (unsigned long)[ordered indexOfObject:editorNumber], (unsigned long)[ordered indexOfObject:settingsNumber],
                (unsigned long)[ordered indexOfObject:dialogNumber]);
            Check(paletteIndex != NSNotFound && [ordered containsObject:editorNumber] &&
                  [ordered containsObject:settingsNumber] && [ordered containsObject:dialogNumber],
                  @"all controlled native windows participate in the ordering test");
            Check(paletteIndex < [ordered indexOfObject:settingsNumber] &&
                  paletteIndex < [ordered indexOfObject:dialogNumber] && paletteIndex < [ordered indexOfObject:editorNumber],
                  @"later-raised settings and editor windows remain below the symbol palette");
            Check(NSApp.isActive == wasActive && !panel.isKeyWindow && !panel.isMainWindow,
                  @"real ordering does not activate the input-method app or take keyboard focus");
            [controller hide:nil];
            Check(!panel.isVisible && !controller.isVisible, @"explicit hide removes the native palette");
            [editor orderOut:nil]; [preferences orderOut:nil]; [dialog orderOut:nil];
        }
        [controller release];
        printf("PASS: %s\n", scenario.UTF8String);
    }
    return 0;
}
