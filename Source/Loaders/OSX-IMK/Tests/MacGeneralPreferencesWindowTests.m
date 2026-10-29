// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
// Load the localized production NIB and real preference window controllers.
// Native profile, TIS, sounds, and distributed services stay isolated.
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "../../../PreferenceApplications/OSX/TakaoGlobal.h"
#import "../../../PreferenceApplications/OSX/TakaoPreference.h"
#import "../../../PreferenceApplications/OSX/TakaoHelper.h"
#import "../../../PreferenceApplications/OSX/TakaoAbout.h"

static NSString *profilePath;
static BOOL serviceThrows;
static NSMutableArray *failures;
static NSUInteger checks;
static void Require(BOOL pass, NSString *message) {
    ++checks;
    if (!pass) [failures addObject:message];
}
@implementation TakaoHelper
+ (NSString *)plistFilePath:(NSString *)filename { return profilePath; }
+ (NSString *)cacheFolder { return [profilePath stringByDeletingLastPathComponent]; }
@end

@interface NSConnection (WindowTestIsolation)
+ (id)layout_rootProxyForConnectionWithRegisteredName:(NSString *)name host:(NSString *)host;
@end
@implementation NSConnection (WindowTestIsolation)
+ (id)layout_rootProxyForConnectionWithRegisteredName:(NSString *)name host:(NSString *)host {
    if (serviceThrows) [NSException raise:@"LayoutIsolatedServiceFailure" format:@"isolated service failure"];
    return nil;
}
@end

@interface WindowTestGlobal : TakaoGlobal @end
@implementation WindowTestGlobal
- (void)setKeyboardLayoutUI {
    NSPopUpButton *popup = [self valueForKey:@"_keyboardLayoutPopUpButton"];
    [popup removeAllItems]; [popup addItemWithTitle:@"US"];
}
- (void)setSoundUI {
    NSPopUpButton *popup = [self valueForKey:@"_soundListPopUpButton"];
    [popup removeAllItems]; [popup addItemWithTitle:@"Default"];
}
- (void)requestUpdateConsent:(NSNumber *)enabled {}
@end

@interface QuietController : NSObject @end
@implementation QuietController
- (void)setValue:(id)value forUndefinedKey:(NSString *)key {}
- (id)valueForUndefinedKey:(NSString *)key { return nil; }
- (NSInteger)numberOfRowsInTableView:(NSTableView *)table { return 0; }
- (id)tableView:(NSTableView *)table objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row { return nil; }
- (void)awakeFromNib {}
@end

@implementation TakaoAbout
- (id)initWithModuleInfo:(NSArray *)modules {
    if ((self = [super initWithNibName:nil bundle:nil]))
        [self setView:[[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 480, 430)] autorelease]];
    return self;
}
- (void)refresh {}
@end

@interface WindowTestPreference : TakaoPreference @end
@implementation WindowTestPreference @end

static void Snapshot(NSWindow *window, NSString *directory, NSString *suffix) {
    [window display];
    NSView *frame = [[window contentView] superview];
    [frame layoutSubtreeIfNeeded];
    NSBitmapImageRep *rep = [frame bitmapImageRepForCachingDisplayInRect:frame.bounds];
    [frame cacheDisplayInRect:frame.bounds toBitmapImageRep:rep];
    NSString *path = [directory stringByAppendingPathComponent:
        [NSString stringWithFormat:@"general-window-%@.png", suffix]];
    Require([[rep representationUsingType:NSPNGFileType properties:@{}] writeToFile:path atomically:YES],
        @"write full native window snapshot");
}

static void CheckVisible(NSView *view, NSWindow *window, NSString *name) {
    NSRect rect = [view convertRect:view.bounds toView:nil];
    NSRect usable = window.contentLayoutRect;
    Require(NSContainsRect(usable, rect), [NSString stringWithFormat:
        @"%@ inside actual window contentLayoutRect (view %@, usable %@)", name,
        NSStringFromRect(rect), NSStringFromRect(usable)]);
    NSRect visible = view.visibleRect;
    Require(NSWidth(visible) + 0.5 >= NSWidth(view.bounds) &&
            NSHeight(visible) + 0.5 >= NSHeight(view.bounds),
        [NSString stringWithFormat:@"%@ not clipped by ancestors: %@ vs %@", name,
            NSStringFromRect(visible), NSStringFromRect(view.bounds)]);
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 5) return 2;
        failures = [NSMutableArray array];
        profilePath = [NSString stringWithUTF8String:argv[1]];
        NSString *output = [NSString stringWithUTF8String:argv[2]];
        NSString *caseName = [NSString stringWithUTF8String:argv[3]];
        serviceThrows = strcmp(argv[4], "throw") == 0;
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
        method_exchangeImplementations(
            class_getClassMethod([NSConnection class], @selector(rootProxyForConnectionWithRegisteredName:host:)),
            class_getClassMethod([NSConnection class], @selector(layout_rootProxyForConnectionWithRegisteredName:host:)));
        NSArray *objects = nil;
        NSNib *nib = [[[NSNib alloc] initWithNibNamed:@"LayoutMain" bundle:[NSBundle mainBundle]] autorelease];
        Require(nib != nil && [nib instantiateWithOwner:NSApp topLevelObjects:&objects], @"instantiate real localized MainMenu NIB");
        WindowTestPreference *preference = nil;
        WindowTestGlobal *global = nil;
        for (id object in objects) {
            if ([object isKindOfClass:[WindowTestPreference class]]) preference = object;
            if ([object isKindOfClass:[WindowTestGlobal class]]) global = object;
        }
        Require(preference != nil && global != nil, @"find production preference/global controllers");
        if (!preference || !global) return 1;
        NSWindow *window = [preference valueForKey:@"window"];
        [window setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameAqua]];
        NSView *pane = [preference valueForKey:@"_generalView"];
        NSPopUpButton *reference = [global valueForKey:@"_highlightColorPopUpButton"];
        NSPopUpButton *startup = [global valueForKey:@"_defaultInputModePopUpButton"];
        Require(startup != nil, @"startup input mode control instantiated");
        Require(![global respondsToSelector:NSSelectorFromString(@"setInputCore:")], @"single-core preferences expose no core switch action");
        Snapshot(window, output, [caseName stringByAppendingString:@"-initial"]);
        Require(window.toolbar != nil && window.toolbar.items.count >= 7, @"real toolbar attached");
        Require([pane superview] == window.contentView, @"active general pane in real content view");
        Require(NSWidth(window.contentLayoutRect) + 0.5 >= NSWidth(pane.frame) &&
                NSHeight(window.contentLayoutRect) + 0.5 >= NSHeight(pane.frame),
            [NSString stringWithFormat:@"window usable rect %@ contains whole pane %@",
                NSStringFromRect(window.contentLayoutRect), NSStringFromRect(pane.frame)]);
        Require(fabs(NSMinX(startup.frame) - NSMinX(reference.frame)) <= 0.5,
            @"startup popup aligned with existing control column");
        for (NSView *child in pane.subviews) {
            if (child.hidden) continue;
            Require(NSContainsRect(pane.bounds, child.frame), [NSString stringWithFormat:
                @"pane contains child %@ %@", [child class], NSStringFromRect(child.frame)]);
            CheckVisible(child, window, [NSString stringWithFormat:@"%@", [child class]]);
        }
        NSString *scaleTitle = [[NSBundle mainBundle] localizedStringForKey:
            @"Candidate window scale:" value:nil table:nil];
        for (NSView *child in pane.subviews) {
            if (![child isKindOfClass:[NSTextField class]]) continue;
            NSTextField *label = (NSTextField *)child;
            BOOL isStartupLabel = NSMaxX(label.frame) <= NSMinX(startup.frame) &&
                fabs(NSMidY(label.frame) - NSMidY(startup.frame)) < 8.0;
            BOOL isScaleLabel = [label.stringValue isEqualToString:scaleTitle];
            if (isStartupLabel || isScaleLabel) {
                Require([[label cell] cellSize].width <= NSWidth(label.frame) + 0.5,
                    [NSString stringWithFormat:@"localized label fits: %@", label.stringValue]);
                Require(!NSIntersectsRect(label.frame, startup.frame),
                    @"localized dynamic label does not overlap popup column");
            }
        }
        NSButton *shift = [global valueForKey:@"_useShiftToggleInputMode"];
        Require([[shift cell] cellSize].width <= NSWidth(shift.frame) + 0.5,
            @"localized Shift checkbox fits");
        for (NSPopUpButton *popup in @[startup])
            for (NSMenuItem *item in popup.itemArray)
                Require([item.title sizeWithAttributes:@{NSFontAttributeName: popup.font}].width
                        <= NSWidth(popup.frame) - 25.0,
                    @"localized popup item title fits");
        NSView *sound = [global valueForKey:@"_soundListPopUpButton"];
        Require(!NSIntersectsRect(startup.frame, sound.frame), @"startup input mode and sound rows do not intersect");
        NSRect originalPane = pane.frame;
        NSRect originalWindow = window.frame;
        NSView *other = [preference valueForKey:@"_phoneticView"];
        for (NSUInteger n = 0; n < 4; ++n) {
            [preference setActiveView:other animate:NO];
            [preference setActiveView:pane animate:NO];
            Require(NSEqualSizes(pane.frame.size, originalPane.size), @"tab switch keeps pane size");
            Require(NSEqualSizes(window.frame.size, originalWindow.size), @"tab switch keeps native window size");
            CheckVisible(sound, window, @"sound popup after tab switch");
            CheckVisible(startup, window, @"startup input mode after tab switch");
        }
        // Exercise the actual toolbar action, which requests animated resizing.
        NSToolbarItem *phoneticItem = nil, *generalItem = nil;
        for (NSToolbarItem *item in window.toolbar.items) {
            if ([item.itemIdentifier isEqualToString:PhoneticToolbarItemIdentifier]) phoneticItem = item;
            if ([item.itemIdentifier isEqualToString:GeneralToolbarItemIdentifier]) generalItem = item;
        }
        Require(phoneticItem && generalItem, @"actual toolbar has both pane actions");
        for (NSToolbarItem *item in @[phoneticItem, generalItem]) {
            [window.toolbar setSelectedItemIdentifier:item.itemIdentifier];
            Require([NSApp sendAction:item.action to:item.target from:item], @"native toolbar dispatches pane action");
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.15]];
        }
        Require(NSEqualSizes(pane.frame.size, originalPane.size), @"animated toolbar keeps pane size");
        Require(NSEqualSizes(window.frame.size, originalWindow.size), @"animated toolbar keeps native window size");
        for (NSView *child in pane.subviews)
            if (!child.hidden) CheckVisible(child, window, @"control after animated toolbar return");
        Snapshot(window, output, [caseName stringByAppendingString:@"-return"]);
        [window orderOut:nil];
        for (NSString *failure in failures) fprintf(stderr, "FAIL: %s\n", failure.UTF8String);
        printf("General preferences real NIB/window (%s): %lu checks, %lu failures.\n",
            caseName.UTF8String, (unsigned long)checks, (unsigned long)failures.count);
        return failures.count ? 1 : 0;
    }
}
