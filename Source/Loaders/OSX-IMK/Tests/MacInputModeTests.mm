#import <Cocoa/Cocoa.h>
#import "IMKShiftTap.h"
#import "IMKInputMode.h"
#include "PVTextBuffer.h"
#include <cassert>
using namespace OpenVanilla;
#define LFLSTR(x) (x)
static IMKInputMode OVCInputMode;
static NSUInteger notices;
static id OVCActiveContextSender;
static NSString *kIMKCommandClientName = @"IMKCommandClient";
struct FakeLoader {
    std::string primary = "SmartMandarin";
    void setPrimaryInputMethod(const std::string& method) { primary = method; }
    void syncSandwichConfig() {}
};
static FakeLoader loader;
@interface OpenVanillaLoader : NSObject
+ (FakeLoader*)sharedLoader;
@end
@implementation OpenVanillaLoader
+ (FakeLoader*)sharedLoader { return &loader; }
@end
@interface CVNotifyController : NSObject
+ (void)notify:(NSString*)message;
@end
@implementation CVNotifyController
+ (void)notify:(NSString*)message { ++notices; }
@end
struct FakeContext {
    PVTextBuffer composing, reading;
    bool simplify = false;
    bool candidateVisible = true;
    int clears = 0;
    PVTextBuffer *composingText() { return &composing; }
    PVTextBuffer *readingText() { return &reading; }
    std::string residueComposingTextBeforeDeactivation() {
        std::string result = composing.composedText();
        composing.commit();
        if (simplify) {
            auto pos = result.find("臺");
            if (pos != std::string::npos) result.replace(pos, std::string("臺").size(), "台");
        }
        return result;
    }
    void clear() { ++clears; composing.clear(); reading.clear(); candidateVisible = false; }
    void deactivate() {}
    void activate() {}
};
@interface ModeController : NSObject {
@public
    IMKShiftTap _shiftTap;
    BOOL _shiftTapEnabled;
    BOOL _modeSwitchInProgress;
    FakeContext *_context;
    NSMutableString *_composingBuffer;
}
- (BOOL)_finishCompositionForModeSwitch:(id)sender;
- (BOOL)_setEnglishMode:(BOOL)english client:(id)sender;
- (void)_handleShiftTap:(NSEvent*)event client:(id)sender;
- (void)_resetUI;
- (void)switchInputMethodAction:(id)sender;
- (void)englishInputModeAction:(id)sender;
@end
@implementation ModeController
- (id)init { if ((self = [super init])) { _context = new FakeContext; _composingBuffer = [NSMutableString new]; } return self; }
- (void)dealloc { delete _context; }
- (void)_resetUI {}
// ACTUAL_METHODS
@end
@interface Host : NSObject
@property NSMutableString *inserted;
@property BOOL reject;
@property ModeController *controller;
- (void)insertText:(NSString*)text replacementRange:(NSRange)range;
@end
@implementation Host
- (void)insertText:(NSString*)text replacementRange:(NSRange)range {
    assert(![self.controller _finishCompositionForModeSwitch:self]); // Reentrant host callback is inert.
    if (self.reject) @throw [NSException exceptionWithName:@"Rejected" reason:nil userInfo:nil];
    [self.inserted appendString:text];
}
@end
@interface InputEvent : NSObject
@property NSEventType type;
@property unsigned short keyCode;
@property NSEventModifierFlags modifierFlags;
@property NSTimeInterval timestamp;
@end
@implementation InputEvent
@end
static void Send(ModeController *controller, Host *host, NSEventType type, unsigned short code, NSEventModifierFlags flags, double time) {
    InputEvent *event = [InputEvent new]; event.type = type; event.keyCode = code; event.modifierFlags = flags; event.timestamp = time;
    [controller _handleShiftTap:(NSEvent*)event client:host];
}
int main() { @autoreleasepool {
    IMKInputMode startup;
    startup.initialize(false); assert(!startup.english);
    startup.english = true; startup.initialize(false); assert(startup.english);
    IMKInputMode englishStartup; englishStartup.initialize(true); assert(englishStartup.english);
    englishStartup.initialize(false); assert(englishStartup.english);
    ModeController *controller = [ModeController new];
    Host *host = [Host new]; host.inserted = [NSMutableString new]; host.controller = controller;
    Send(controller, host, NSFlagsChanged, 56, NSShiftKeyMask, 0);
    Send(controller, host, NSFlagsChanged, 56, 0, .1);
    assert(!OVCInputMode.english && notices == 0);
    controller->_shiftTapEnabled = YES;
    controller->_context->composing.setText("甲乙"); controller->_context->composing.setCursorPosition(1);
    controller->_context->reading.setText("ㄅ");
    [controller->_composingBuffer setString:@"甲ㄅ乙"];
    Send(controller, host, NSFlagsChanged, 56, NSShiftKeyMask, 1);
    Send(controller, host, NSFlagsChanged, 56, NSShiftKeyMask, 1.005);
    Send(controller, host, NSFlagsChanged, 56, 0, 1.1);
    Send(controller, host, NSFlagsChanged, 56, 0, 1.102);
    assert(OVCInputMode.english && notices == 1);
    assert([host.inserted isEqualToString:@"甲ㄅ乙"]);
    assert(controller->_context->composing.isEmpty() && controller->_context->reading.isEmpty());
    assert(!controller->_context->candidateVisible && controller->_context->clears == 1);
    Send(controller, host, NSFlagsChanged, 60, NSShiftKeyMask, 2);
    Send(controller, host, NSFlagsChanged, 60, 0, 2.1);
    assert(!OVCInputMode.english && notices == 2);
    Send(controller, host, NSFlagsChanged, 56, NSShiftKeyMask, 3);
    Send(controller, host, NSKeyDown, 0, NSShiftKeyMask, 3.01);
    Send(controller, host, NSFlagsChanged, 56, 0, 3.1);
    Send(controller, host, NSFlagsChanged, 56, NSShiftKeyMask, 4);
    Send(controller, host, NSFlagsChanged, 56, 0, 4.5);
    assert(!OVCInputMode.english && notices == 2);
    controller->_context->composing.setText("臺灣"); controller->_context->composing.setCursorPosition(1);
    controller->_context->reading.setText("ㄅ"); controller->_context->simplify = true;
    host.reject = YES;
    assert(![controller _setEnglishMode:YES client:host]);
    assert(!OVCInputMode.english && notices == 2 && !controller->_modeSwitchInProgress);
    assert(controller->_context->composing.composedText() == "臺灣");
    assert(!controller->_context->composing.isCommitted());
    assert(controller->_context->reading.composedText() == "ㄅ");
    host.reject = NO; controller->_shiftTapEnabled = NO;
    assert([controller _setEnglishMode:YES client:host]); // Menu remains available with Shift disabled.
    assert(OVCInputMode.english && [host.inserted isEqualToString:@"甲ㄅ乙台ㄅ灣"]);
    assert([controller _setEnglishMode:YES client:host] && notices == 3); // Same mode is inert.
    assert(![controller _setEnglishMode:NO client:nil] && OVCInputMode.english);
    NSUInteger sequence = 0;
    for (NSString *method in @[@"SmartMandarin", @"TraditionalMandarin", @"Generic-cj-cin", @"Generic-simplex-cin"]) {
        NSMenuItem *item = [NSMenuItem new]; item.title = method; item.representedObject = method;
        NSDictionary *command = @{@"IMKCommandClient":host, @"IMKCommandMenuItem":item};
        [controller switchInputMethodAction:command];
        assert(!OVCInputMode.english && loader.primary == [method UTF8String]);
        [controller englishInputModeAction:command];
        assert(OVCInputMode.english && loader.primary == [method UTF8String]);
        controller->_shiftTapEnabled = YES;
        Send(controller, host, NSFlagsChanged, 56, NSShiftKeyMask, 10 + sequence);
        Send(controller, host, NSFlagsChanged, 56, 0, 10.1 + sequence);
        assert(!OVCInputMode.english && loader.primary == [method UTF8String]);
        ++sequence;
    }
    puts("PASS: four Chinese method menu selections retain their identities across independent English mode");
    puts("PASS: real mode-switch methods, startup preference, duplicate events, reading at caret, filtering, failure, reentrancy, disabled Shift");
} }
