#import "../../../PreferenceApplications/OSX/TakaoGlobal.h"
#import "../../../PreferenceApplications/OSX/TakaoHelper.h"
#include <assert.h>
static NSString *testPath;
static NSDictionary *coreReply;
static NSNumber *lastCoreRequest;
static NSUInteger coreQueries, coreWrites;
@interface TakaoGlobal (CoreTestContract)
- (void)requestInputCoreStatus:(NSNumber*)enabled;
- (void)renderInputCoreStatus:(NSDictionary*)status;
- (IBAction)setInputCore:(id)sender;
- (void)refreshInputCoreStatus:(id)sender;
- (void)stopInputCoreService:(NSNotification *)notification;
@end
@implementation TakaoHelper
+ (NSString *)plistFilePath:(NSString *)filename { return testPath; }
@end
@interface QuietColorPopup : NSPopUpButton
- (void)setColorSelection:(NSString*)color;
@end
@implementation QuietColorPopup
- (void)setColorSelection:(NSString*)color {}
@end
@interface TestGlobal : TakaoGlobal
@end
@implementation TestGlobal
- (void)setKeyboardLayoutUI {}
- (void)setSoundUI {}
- (void)requestUpdateConsent:(NSNumber*)enabled {}
- (void)requestInputCoreStatus:(NSNumber*)enabled {
    if (enabled) {
        ++coreWrites;
        [lastCoreRequest release]; lastCoreRequest = [enabled retain];
    } else ++coreQueries;
    [self renderInputCoreStatus:coreReply];
}
@end
@interface TestWindow : NSWindow { @public BOOL testVisible; }
@end
@implementation TestWindow
- (BOOL)isVisible { return testVisible; }
@end
@interface TestPane : NSView
@end
@implementation TestPane
- (void)drawRect:(NSRect)dirty { [[NSColor windowBackgroundColor] setFill]; NSRectFill(dirty); }
@end
static NSRect Frame(NSDictionary *entry) {
    NSArray *r = entry[@"rect"];
    return NSMakeRect([r[0] doubleValue], [r[1] doubleValue], [r[2] doubleValue], [r[3] doubleValue]);
}
static TestGlobal *Make(NSDictionary *layout, NSView **pane) {
    TestGlobal *controller = [[[TestGlobal alloc] init] autorelease];
    NSView *container = [[[TestPane alloc] initWithFrame:Frame(layout)] autorelease];
    NSMutableDictionary *views = [NSMutableDictionary dictionary];
    for (NSDictionary *child in layout[@"children"]) {
        NSRect rect = Frame(child);
        NSString *kind = child[@"kind"];
        NSView *view;
        if ([kind isEqual:@"button"]) {
            NSButton *button = [[[NSButton alloc] initWithFrame:rect] autorelease];
            button.buttonType = NSSwitchButton; button.title = child[@"title"] ?: @"";
            view = button;
        } else if ([kind isEqual:@"matrix"]) {
            NSButtonCell *cell = [[[NSButtonCell alloc] init] autorelease]; cell.buttonType = NSRadioButton;
            NSMatrix *matrix = [[[NSMatrix alloc] initWithFrame:rect mode:NSRadioModeMatrix prototype:cell numberOfRows:1 numberOfColumns:2] autorelease];
            [[matrix cellAtRow:0 column:0] setTitle:@"Vertical"]; [[matrix cellAtRow:0 column:1] setTitle:@"Horizontal"];
            view = matrix;
        } else if ([kind isEqual:@"scrollView"]) {
            NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:rect] autorelease];
            NSTableView *table = [[[NSTableView alloc] initWithFrame:NSMakeRect(0,0,rect.size.width,rect.size.height)] autorelease];
            scroll.documentView = table; views[child[@"table"]] = table; view = scroll;
        } else if ([kind isEqual:@"textField"]) {
            NSTextField *label = [[[NSTextField alloc] initWithFrame:rect] autorelease];
            label.bezeled = NO; label.drawsBackground = NO; label.editable = NO;
            label.font = [NSFont systemFontOfSize:13]; label.stringValue = child[@"title"] ?: @"";
            view = label;
        } else if ([kind isEqual:@"popUpButton"]) {
            NSPopUpButton *popup = [[[QuietColorPopup alloc] initWithFrame:rect pullsDown:NO] autorelease];
            [popup addItemWithTitle:child[@"title"] ?: @"Default"]; view = popup;
        } else { view = [[[NSView alloc] initWithFrame:rect] autorelease]; }
        views[child[@"id"]] = view; [container addSubview:view];
    }
    for (NSString *key in layout[@"outlets"]) {
        id view = views[layout[@"outlets"][key]];
        if (view) [controller setValue:view forKey:key];
    }
    [controller awakeFromNib];
    *pane = container;
    return controller;
}
int main(int argc, char **argv) {
    @autoreleasepool {
        assert(argc >= 4); [NSApplication sharedApplication];
        NSDictionary *layout = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]] options:0 error:nil];
        testPath = [NSString stringWithUTF8String:argv[2]];
        coreReply = @{@"supported": @YES, @"active": @"manjusri", @"requested": @NO, @"pending": @NO};
        NSView *pane;
        TestGlobal *controller = Make(layout, &pane);
        NSButton *shift = [controller valueForKey:@"_useShiftToggleInputMode"];
        NSPopUpButton *startup = [controller valueForKey:@"_defaultInputModePopUpButton"];
        NSButton *ctrl = [controller valueForKey:@"_useCtrlBackSlashToggleInputMethod"];
        assert(shift.intValue == 1 && startup.indexOfSelectedItem == 0);
        assert(shift.target == controller && shift.action == @selector(writePreference:));
        assert(startup.target == controller && startup.action == @selector(writePreference:));
        assert(pane.frame.size.height == Frame(layout).size.height + 116);
        NSPopUpButton *core = [controller valueForKey:@"_inputCorePopUpButton"];
        NSTextField *coreStatus = [controller valueForKey:@"_inputCoreStatusTextField"];
        assert(core && coreStatus && coreQueries == 1 && coreWrites == 0);
        assert(core.enabled && core.indexOfSelectedItem == 0);
        assert(core.target == controller && core.action == @selector(setInputCore:));
        assert([coreStatus.stringValue containsString:@"Manjusri"]);
        for (NSView *view in pane.subviews) {
            if (view != core) assert(!NSIntersectsRect(view.frame, core.frame));
            if (view != coreStatus) assert(!NSIntersectsRect(view.frame, coreStatus.frame));
        }
        assert(NSMaxY(shift.frame) <= NSMinY(ctrl.frame));
        assert(NSMaxY(startup.frame) <= NSMinY(shift.frame));
        for (NSView *view in pane.subviews) {
            if (view != shift) assert(!NSIntersectsRect(view.frame, shift.frame));
            if (view != startup) assert(!NSIntersectsRect(view.frame, startup.frame));
        }
        NSRect before = pane.frame; [controller awakeFromNib]; assert(NSEqualRects(before, pane.frame));
        [shift setIntValue:0]; [startup selectItemAtIndex:1]; [controller writePreference:shift];
        NSDictionary *saved = [NSDictionary dictionaryWithContentsOfFile:testPath];
        assert([saved[@"ToggleInputModeWithShift"] isEqual:@"false"] && [saved[@"DefaultInputMode"] isEqual:@"English"]);
        controller = Make(layout, &pane); shift = [controller valueForKey:@"_useShiftToggleInputMode"]; startup = [controller valueForKey:@"_defaultInputModePopUpButton"];
        assert(shift.intValue == 0 && startup.indexOfSelectedItem == 1);
        [shift setIntValue:1]; [controller writePreference:shift];
        saved = [NSDictionary dictionaryWithContentsOfFile:testPath];
        assert([saved[@"ToggleInputModeWithShift"] isEqual:@"true"] && [saved[@"DefaultInputMode"] isEqual:@"English"]);
        assert([[shift cell] cellSize].width <= NSWidth(shift.frame));
        core = [controller valueForKey:@"_inputCorePopUpButton"];
        coreStatus = [controller valueForKey:@"_inputCoreStatusTextField"];
        [controller renderInputCoreStatus:nil];
        assert(!core.enabled && coreStatus.stringValue.length > 0);
        [controller renderInputCoreStatus:@{@"supported": @NO, @"active": @"manjusri", @"requested": @NO, @"pending": @NO}];
        assert(!core.enabled && core.indexOfSelectedItem == 0);
        [controller renderInputCoreStatus:@{@"supported": @YES, @"active": @"manjusri", @"requested": @YES, @"pending": @YES}];
        assert(core.enabled && core.indexOfSelectedItem == 1);
        assert([coreStatus.stringValue containsString:@"Manjusri"] && [coreStatus.stringValue containsString:@"Guanyinma"]);
        NSString *pendingStatus = [[coreStatus.stringValue copy] autorelease];
        [controller renderInputCoreStatus:@{@"supported": @YES, @"active": @"guanyinma", @"requested": @YES, @"pending": @NO}];
        assert(core.enabled && core.indexOfSelectedItem == 1 && [coreStatus.stringValue containsString:@"Guanyinma"]);
        assert(![coreStatus.stringValue isEqualToString:pendingStatus]);
        coreReply = @{@"supported": @YES, @"active": @"manjusri", @"requested": @YES, @"pending": @YES};
        NSData *beforeCoreAction = [NSData dataWithContentsOfFile:testPath];
        NSUInteger writesBefore = coreWrites;
        [core selectItemAtIndex:1]; [controller setInputCore:core];
        assert(coreWrites == writesBefore + 1 && [lastCoreRequest boolValue]);
        assert([[NSData dataWithContentsOfFile:testPath] isEqualToData:beforeCoreAction]);
        saved = [NSDictionary dictionaryWithContentsOfFile:testPath];
        assert(!saved[@"UseGuanyinmaCore"]);
        coreReply = @{@"supported": @YES, @"active": @"manjusri", @"requested": @NO, @"pending": @NO};
        [core selectItemAtIndex:0]; [controller setInputCore:core];
        assert(coreWrites == writesBefore + 2 && ![lastCoreRequest boolValue]);
        assert([[NSData dataWithContentsOfFile:testPath] isEqualToData:beforeCoreAction]);

        [startup selectItemAtIndex:0];
        TestWindow *window = [[[TestWindow alloc] initWithContentRect:pane.bounds styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO] autorelease];
        window->testVisible = YES;
        [window setReleasedWhenClosed:NO];
        [window setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameAqua]];
        [window setContentView:pane]; [window display];
        NSBitmapImageRep *bitmap = [pane bitmapImageRepForCachingDisplayInRect:pane.bounds];
        [pane cacheDisplayInRect:pane.bounds toBitmapImageRep:bitmap];
        [[bitmap representationUsingType:NSPNGFileType properties:@{}] writeToFile:[NSString stringWithUTF8String:argv[3]] atomically:YES];
        [controller renderInputCoreStatus:@{@"supported": @YES, @"active": @"manjusri", @"requested": @YES, @"pending": @YES}];
        [window display];
        bitmap = [pane bitmapImageRepForCachingDisplayInRect:pane.bounds];
        [pane cacheDisplayInRect:pane.bounds toBitmapImageRep:bitmap];
        NSString *pendingPath = [[[NSString stringWithUTF8String:argv[3]] stringByDeletingPathExtension] stringByAppendingString:@"-pending.png"];
        [[bitmap representationUsingType:NSPNGFileType properties:@{}] writeToFile:pendingPath atomically:YES];
        // Exercise the real timer entry point with a synchronous service mock.
        // No visible app or actual DO endpoint is needed for this lifecycle.
        coreReply = @{@"supported": @YES, @"active": @"manjusri", @"requested": @YES, @"pending": @YES};
        NSTimer *probe = [NSTimer timerWithTimeInterval:1 target:controller
            selector:@selector(refreshInputCoreStatus:) userInfo:nil repeats:NO];
        NSUInteger beforePoll = coreQueries;
        for (NSUInteger i=0; i<100; ++i) [controller refreshInputCoreStatus:probe];
        assert(coreQueries > beforePoll && coreQueries - beforePoll <= 30);
        assert(![controller valueForKey:@"_inputCoreStatusTimer"]);
        NSUInteger beforeFocus = coreQueries;
        [controller refreshInputCoreStatus:[NSNotification notificationWithName:NSWindowDidBecomeKeyNotification object:window]];
        assert(coreQueries == beforeFocus + 1 && [controller valueForKey:@"_inputCoreStatusTimer"]);
        beforeFocus = coreQueries;
        [controller refreshInputCoreStatus:[NSNotification notificationWithName:NSWindowDidBecomeKeyNotification object:nil]];
        assert(coreQueries == beforeFocus);
        [pane setHidden:YES];
        [controller refreshInputCoreStatus:probe];
        assert(coreQueries == beforeFocus && ![controller valueForKey:@"_inputCoreStatusTimer"]);
        [pane setHidden:NO];
        [controller refreshInputCoreStatus:[NSNotification notificationWithName:NSWindowDidBecomeKeyNotification object:window]];
        assert([controller valueForKey:@"_inputCoreStatusTimer"]);
        window->testVisible = NO;
        beforePoll = coreQueries;
        [controller refreshInputCoreStatus:probe];
        assert(coreQueries == beforePoll && ![controller valueForKey:@"_inputCoreStatusTimer"]);
        window->testVisible = YES;
        [controller renderInputCoreStatus:@{@"supported": @NO, @"active": @"manjusri", @"requested": @YES, @"pending": @YES}];
        assert(!core.enabled && ![controller valueForKey:@"_inputCoreStatusTimer"]);
        coreReply = @{@"supported": @YES, @"active": @"manjusri", @"requested": @YES, @"pending": @YES};
        [controller refreshInputCoreStatus:[NSNotification notificationWithName:NSWindowDidBecomeKeyNotification object:window]];
        [controller setValue:@30 forKey:@"_inputCoreStatusPollCount"];
        [core selectItemAtIndex:0]; [controller setInputCore:core];
        assert([[controller valueForKey:@"_inputCoreStatusPollCount"] unsignedIntegerValue] == 0);
        assert([controller valueForKey:@"_inputCoreStatusTimer"]);
        [controller stopInputCoreService:[NSNotification notificationWithName:NSWindowWillCloseNotification object:window]];
        assert(![controller valueForKey:@"_inputCoreStatusTimer"]);
        puts("PASS: general preferences persistence, runtime core UI, isolated actions, bounded/hidden polling, focus refresh, localized layout");
    }
}
