#import "../../../PreferenceApplications/OSX/TakaoGlobal.h"
#import "../../../PreferenceApplications/OSX/TakaoHelper.h"
#include <assert.h>
static NSString *testPath;
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
        NSView *pane;
        TestGlobal *controller = Make(layout, &pane);
        NSButton *shift = [controller valueForKey:@"_useShiftToggleInputMode"];
        NSPopUpButton *startup = [controller valueForKey:@"_defaultInputModePopUpButton"];
        NSButton *ctrl = [controller valueForKey:@"_useCtrlBackSlashToggleInputMethod"];
        assert(shift.intValue == 1 && startup.indexOfSelectedItem == 0);
        assert(shift.target == controller && shift.action == @selector(writePreference:));
        assert(startup.target == controller && startup.action == @selector(writePreference:));
        assert(pane.frame.size.height == Frame(layout).size.height + 52);
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
        [startup selectItemAtIndex:0];
        NSWindow *window = [[[NSWindow alloc] initWithContentRect:pane.bounds styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO] autorelease];
        [window setReleasedWhenClosed:NO];
        [window setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameAqua]];
        [window setContentView:pane]; [window display];
        NSBitmapImageRep *bitmap = [pane bitmapImageRepForCachingDisplayInRect:pane.bounds];
        [pane cacheDisplayInRect:pane.bounds toBitmapImageRep:bitmap];
        [[bitmap representationUsingType:NSPNGFileType properties:@{}] writeToFile:[NSString stringWithUTF8String:argv[3]] atomically:YES];
        puts("PASS: general preferences default Chinese/Shift on, persistence, independent startup choice, action wiring, nonoverlapping layout");
    }
}
