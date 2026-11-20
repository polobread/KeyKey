// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
// The runner injects production candidate targets, guards and native actions.
// No IMK server, NSApplication, real window, TIS selection or global key posting.
#import <Cocoa/Cocoa.h>
#include "PVCandidate.h"
#include "PVLoaderService.h"
#include "PVTextBuffer.h"
#include <functional>
#include <stdexcept>
using namespace OpenVanilla;
static NSUInteger scenarios;
static void Require(bool value, const char *message) {
    if (!value) throw std::runtime_error(message);
}
struct CandidateContext {
    PVLoaderService loader;
    PVCandidateService service;
    NSUInteger keysReceived = 0;
    size_t selectedIndex = (size_t)-1;
    std::string received, chosen;
    CandidateContext() : service(&loader) {}
    PVCandidateService *candidateService() { return &service; }
    bool handleKeyEvent(OVKey *key) {
        ++keysReceived;
        received = key->receivedString();
        auto *panel = dynamic_cast<PVOneDimensionalCandidatePanel*>(service.lastUsedPanel());
        Require(panel != nullptr, "selection must use a real one-dimensional panel");
        Require(panel->handleKeyEvent(*key, &loader) == PVCandidateState::CandidateChosen,
            "bound key must actually select the clicked native panel row");
        selectedIndex = panel->chosenCandidateIndex();
        chosen = panel->chosenCandidateString();
        panel->hide(); panel->cancelEventHandler();
        return true;
    }
};
@protocol CandidateView
- (void)hide;
- (IBAction)gotoNextPage:(id)sender;
- (IBAction)gotoPreviousPage:(id)sender;
@end
@class OpenVanillaController;
static OpenVanillaController *OVCActiveContext;
static id OVCActiveContextSender;
static NSUInteger OVCActiveContextGeneration;
// ACTUAL_TARGET_CLASS

@interface CandidateHost : NSObject {
@public
    NSUInteger flushes;
    NSString *visible;
}
@end
@implementation CandidateHost
- (void)dealloc { [visible release]; [super dealloc]; }
@end

@interface OpenVanillaController : NSObject {
@public
    CandidateContext *_context;
    NSMutableIndexSet *_handledKeyCodes;
    NSUInteger flushes;
    id flushedClient;
    id<CandidateView> hideDuringFlush;
}
+ (void)setActiveContext:(OpenVanillaController*)context sender:(id)sender;
+ (id)candidateSelectionTargetForPanel:(PVOneDimensionalCandidatePanel*)panel;
+ (void)invalidateCandidateSelectionTarget:(id)target;
+ (BOOL)candidateSelectionTargetIsCurrent:(id)target;
+ (BOOL)selectCandidateAtIndex:(NSUInteger)index target:(id)target;
- (void)_flushKeyEffectsToClient:(id)sender;
@end
@implementation OpenVanillaController
- (id)init {
    if ((self = [super init])) {
        _context = new CandidateContext;
        _handledKeyCodes = [[NSMutableIndexSet alloc] init];
        [_handledKeyCodes addIndex:7]; [_handledKeyCodes addIndex:39];
    }
    return self;
}
- (void)dealloc {
    if (OVCActiveContext == self) [OpenVanillaController setActiveContext:nil sender:nil];
    delete _context; [_handledKeyCodes release]; [super dealloc];
}
- (void)_flushKeyEffectsToClient:(id)sender {
    ++flushes; flushedClient = sender;
    CandidateHost *host = sender;
    ++host->flushes;
    [host->visible release];
    host->visible = [[NSString stringWithUTF8String:_context->chosen.c_str()] copy];
    // A real render may synchronously hide the window/release its selection token.
    if (hideDuringFlush) [hideDuringFlush hide];
}
// ACTUAL_CONTROLLER_METHODS
@end

@interface RowControl : NSObject {
@public NSInteger row; BOOL clickable;
}
- (NSInteger)selectedRow;
- (NSInteger)clickedIndex;
- (void)setClickable:(BOOL)value;
@end
@implementation RowControl
- (NSInteger)selectedRow { return row; }
- (NSInteger)clickedIndex { return row; }
- (void)setClickable:(BOOL)value { clickable = value; }
@end
@interface InertWindow : NSObject {
@public NSUInteger hides;
}
- (void)orderOut:(id)sender;
- (NSRect)frame;
@end
@implementation InertWindow
- (void)orderOut:(id)sender { ++hides; }
- (NSRect)frame { return NSMakeRect(0, 0, 100, 100); }
@end

// Renderer seams only bind the exact production selection token. The Python
// runner separately checks the production renderers' invalidate/capture wiring.
@interface CVVerticalCandidateController : NSObject <CandidateView> {
@public
    RowControl *_tableView;
    PVVerticalCandidatePanel *_panel;
    id _selectionTarget;
    BOOL _allowClick;
    NSArray *_displayedCandidateTexts;
    size_t _displayedPage, _displayedHighlightIndex;
    BOOL _displayedInControl;
    InertWindow *_window;
}
- (id)window;
- (void)updateDisplay:(PVVerticalCandidatePanel*)panel atPoint:(NSPoint)point;
- (void)hide;
- (IBAction)sendKey:(id)sender;
- (IBAction)gotoNextPage:(id)sender;
- (IBAction)gotoPreviousPage:(id)sender;
@end
@implementation CVVerticalCandidateController
- (id)init {
    if ((self = [super init])) { _tableView = [RowControl new]; _window = [InertWindow new]; }
    return self;
}
- (void)dealloc { [_selectionTarget release]; [_tableView release]; [_window release]; [super dealloc]; }
- (id)window { return _window; }
- (void)updateDisplay:(PVVerticalCandidatePanel*)panel atPoint:(NSPoint)point {
    [OpenVanillaController invalidateCandidateSelectionTarget:_selectionTarget];
    [_selectionTarget release]; _panel = panel; _allowClick = YES;
    _selectionTarget = [[OpenVanillaController candidateSelectionTargetForPanel:panel] retain];
}
// ACTUAL_VERTICAL_METHODS
@end
@interface CVHorizontalCandidateController : NSObject <CandidateView> {
@public
    RowControl *_candidateControl;
    PVHorizontalCandidatePanel *_panel;
    id _selectionTarget;
    InertWindow *_window;
}
- (id)window;
- (void)updateDisplay:(PVHorizontalCandidatePanel*)panel atPoint:(NSPoint)point;
- (void)hide;
- (IBAction)sendKey:(id)sender;
- (IBAction)gotoNextPage:(id)sender;
- (IBAction)gotoPreviousPage:(id)sender;
@end
@implementation CVHorizontalCandidateController
- (id)init {
    if ((self = [super init])) { _candidateControl = [RowControl new]; _window = [InertWindow new]; }
    return self;
}
- (void)dealloc { [_selectionTarget release]; [_candidateControl release]; [_window release]; [super dealloc]; }
- (id)window { return _window; }
- (void)updateDisplay:(PVHorizontalCandidatePanel*)panel atPoint:(NSPoint)point {
    [OpenVanillaController invalidateCandidateSelectionTarget:_selectionTarget];
    [_selectionTarget release]; _panel = panel;
    _selectionTarget = [[OpenVanillaController candidateSelectionTargetForPanel:panel] retain];
}
// ACTUAL_HORIZONTAL_METHODS
@end

struct Fixture {
    bool vertical;
    OpenVanillaController *owner, *other;
    CandidateHost *host, *otherHost;
    CVVerticalCandidateController *v = nil;
    CVHorizontalCandidateController *h = nil;
    PVOneDimensionalCandidatePanel *panel;
    id target;
    NSIndexSet *handled;
    explicit Fixture(bool orientation, const std::string& keys = "12345678", size_t page = 0)
        : vertical(orientation) {
        owner = [OpenVanillaController new]; other = [OpenVanillaController new];
        host = [CandidateHost new]; otherHost = [CandidateHost new];
        [OpenVanillaController setActiveContext:owner sender:host];
        auto *service = owner->_context->candidateService();
        panel = static_cast<PVOneDimensionalCandidatePanel*>(vertical
            ? service->useVerticalCandidatePanel() : service->useHorizontalCandidatePanel());
        std::vector<std::string> texts;
        for (size_t i = 0; i < 11; ++i) texts.push_back("candidate-" + std::to_string(i));
        panel->candidateList()->setCandidates(texts);
        static_cast<OVOneDimensionalCandidatePanel*>(panel)->setCandidateKeys(keys, &owner->_context->loader);
        panel->setCandidatesPerPage(8); panel->show(); panel->yieldToCandidateEventHandler(); panel->goToPage(page);
        if (vertical) { v = [CVVerticalCandidateController new]; [v updateDisplay:static_cast<PVVerticalCandidatePanel*>(panel) atPoint:NSZeroPoint]; }
        else { h = [CVHorizontalCandidateController new]; [h updateDisplay:static_cast<PVHorizontalCandidatePanel*>(panel) atPoint:NSZeroPoint]; }
        target = [token() retain];
        handled = [owner->_handledKeyCodes copy];
        Require([OpenVanillaController candidateSelectionTargetIsCurrent:target], "fixture must capture a valid production token");
    }
    ~Fixture() {
        [OpenVanillaController setActiveContext:nil sender:nil];
        [v release]; [h release]; [target release]; [handled release];
        [owner release]; [other release]; [host release]; [otherHost release];
    }
    id token() { return vertical ? v->_selectionTarget : h->_selectionTarget; }
    id<CandidateView> view() { return vertical ? (id<CandidateView>)v : (id<CandidateView>)h; }
    void click(NSInteger row) {
        if (vertical) { v->_tableView->row = row; [v sendKey:nil]; }
        else { h->_candidateControl->row = row; [h sendKey:nil]; }
    }
    void unchangedKeyUps() {
        Require([handled isEqualToIndexSet:owner->_handledKeyCodes], "mouse selection must not reserve/suppress a real hardware key-up");
    }
    void noEffects() {
        Require(owner->_context->keysReceived == 0 && other->_context->keysReceived == 0,
            "stale view must not dispatch to either engine");
        Require(host->flushes == 0 && otherHost->flushes == 0 && owner->flushes == 0 && other->flushes == 0,
            "stale view must not insert/render in either client");
        unchangedKeyUps();
    }
};

static void Positive(bool vertical, bool customPaged, bool hideDuringFlush) {
    NSAutoreleasePool *capturePool = [[NSAutoreleasePool alloc] init];
    Fixture f(vertical, customPaged ? "asdfghjk" : "12345678", customPaged ? 1 : 0);
    [capturePool drain];
    if (hideDuringFlush) {
        // The view is now the token's only external owner. Hiding it during
        // flush really releases that last reference, exercising the production
        // dispatcher's temporary retain rather than an incidental test retain.
        [f.target release]; f.target = nil;
    }
    f.owner->hideDuringFlush = hideDuringFlush ? f.view() : nil;
    f.click(1); f.click(1);
    const size_t expected = customPaged ? 9 : 1;
    Require(f.owner->_context->keysReceived == 1 && f.owner->flushes == 1 && f.host->flushes == 1,
        "one click must select/flush once; repeated old view cannot select twice");
    Require(f.owner->_context->selectedIndex == expected && f.owner->_context->chosen == "candidate-" + std::to_string(expected),
        "page-local click must select the exact native absolute candidate");
    Require(f.owner->_context->received == (customPaged ? "s" : "2"), "native custom selection key must be preserved");
    Require(f.owner->flushedClient == f.host && f.otherHost->flushes == 0 && f.other->_context->keysReceived == 0,
        "selection must flush to its bound client only");
    f.unchangedKeyUps(); ++scenarios;
}

static void Reject(bool vertical, const char *name, const std::function<void(Fixture&)>& mutate) {
    Fixture f(vertical);
    mutate(f); f.click(1); f.noEffects();
    Require(![OpenVanillaController candidateSelectionTargetIsCurrent:f.target], name);
    ++scenarios;
}

int main() { @autoreleasepool {
    try {
        for (bool vertical : {true, false}) {
            Positive(vertical, false, false);
            Positive(vertical, true, false);
            Positive(vertical, false, true);
            Reject(vertical, "owner switch must invalidate", [](Fixture& f) { [OpenVanillaController setActiveContext:f.other sender:f.otherHost]; });
            Reject(vertical, "same owner/new client must invalidate", [](Fixture& f) { [OpenVanillaController setActiveContext:f.owner sender:f.otherHost]; });
            Reject(vertical, "reactivated same owner/client needs a new generation", [](Fixture& f) { [OpenVanillaController setActiveContext:f.owner sender:f.host]; });
            Reject(vertical, "deactivation must invalidate", [](Fixture&) { [OpenVanillaController setActiveContext:nil sender:nil]; });
            Reject(vertical, "page change must invalidate", [](Fixture& f) { f.panel->goToPage(1); });
            Reject(vertical, "page size change must invalidate", [](Fixture& f) { f.panel->setCandidatesPerPage(7); });
            Reject(vertical, "visible text change must invalidate", [](Fixture& f) { f.panel->candidateList()->setCandidate(0, "changed"); });
            Reject(vertical, "candidate count change must invalidate", [](Fixture& f) { f.panel->candidateList()->setCandidates({"one", "two"}); });
            Reject(vertical, "selection key change must invalidate", [](Fixture& f) {
                static_cast<OVOneDimensionalCandidatePanel*>(f.panel)->setCandidateKeys("asdfghjk", &f.owner->_context->loader);
            });
            Reject(vertical, "hidden panel must invalidate", [](Fixture& f) { f.panel->hide(); });
            Reject(vertical, "noncontrolling panel must invalidate", [](Fixture& f) { f.panel->cancelEventHandler(); });
            Reject(vertical, "another active panel must invalidate", [](Fixture& f) {
                if (f.vertical) f.owner->_context->service.useHorizontalCandidatePanel();
                else f.owner->_context->service.useVerticalCandidatePanel();
            });
            Reject(vertical, "native hide action must invalidate its retained token", [](Fixture& f) { [f.view() hide]; });
            Reject(vertical, "explicit target invalidation must be terminal", [](Fixture& f) { [OpenVanillaController invalidateCandidateSelectionTarget:f.target]; });
            { Fixture f(vertical, "12345678", 1); f.click(-1); f.click(3); f.noEffects();
              Require([OpenVanillaController candidateSelectionTargetIsCurrent:f.target], "invalid row must not consume a valid target");
              f.click(2); Require(f.owner->_context->selectedIndex == 10 && f.host->flushes == 1, "last partial page valid row remains usable");
              f.unchangedKeyUps(); ++scenarios; }
            { Fixture f(vertical); [f.view() gotoNextPage:nil];
              Require(f.panel->currentPage() == 1, "native next-page action must update the bound panel");
              Require(![OpenVanillaController selectCandidateAtIndex:1 target:f.target], "redisplay must invalidate the original page token");
              f.click(1); Require(f.owner->_context->selectedIndex == 9 && f.host->flushes == 1, "new page action must bind its visible page");
              f.unchangedKeyUps(); ++scenarios; }
            { Fixture f(vertical, "12345678", 1); [f.view() gotoPreviousPage:nil];
              Require(f.panel->currentPage() == 0, "native previous-page action must update the bound panel");
              f.click(1); Require(f.owner->_context->selectedIndex == 1, "previous page must bind its own local keys");
              f.unchangedKeyUps(); ++scenarios; }
            { Fixture f(vertical); [OpenVanillaController setActiveContext:f.other sender:f.otherHost];
              [f.view() gotoNextPage:nil]; Require(f.panel->currentPage() == 0, "stale page action must not mutate the old panel");
              f.noEffects(); ++scenarios; }
        }
        Require(![OpenVanillaController candidateSelectionTargetForPanel:nullptr], "no active owner/panel must fail closed");
        Require(![OpenVanillaController selectCandidateAtIndex:0 target:nil], "nil target must fail closed");
        Require(![OpenVanillaController candidateSelectionTargetIsCurrent:@"not a token"], "foreign object must fail closed");
        printf("PASS: %lu focused candidate scenarios; real vertical/horizontal actions, bound dispatch, custom keys, pagination, invalidations, reentrant hide, and unchanged hardware key-up state; no IMK/windows/global events.\n", (unsigned long)scenarios);
    } catch (const std::exception& error) {
        fprintf(stderr, "FAIL: %s\n", error.what()); return 1;
    }
} return 0; }
