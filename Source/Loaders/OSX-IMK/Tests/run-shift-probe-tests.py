#!/usr/bin/env python3
"""Test the real IMK probe observer in isolation; never connect to installed IMK."""
from pathlib import Path
import subprocess
import tempfile

loader = Path(__file__).resolve().parents[1]
source = (loader / "OpenVanillaController.mm").read_text()

def method(signature):
    start = source.index(signature)
    opening = source.index("{", start)
    level = 1
    end = opening + 1
    while level:
        if source[end] == "{":
            level += 1
        elif source[end] == "}":
            level -= 1
        end += 1
    return source[start:end]

observer = method("- (void)_observeShiftProbeEvent:")
assert "[self _observeShiftProbeEvent:event];" in method("- (BOOL)handleEvent:")
assert "_shiftProbe.reset();" in method("- (void)activateServer:")
assert "_shiftProbe.reset();" in method("- (void)deactivateServer:")
assert "_shiftProbeEnabled = NO;" in method("- (void)deactivateServer:")
fixture = r'''#import <Cocoa/Cocoa.h>
#import "IMKShiftTapProbe.h"
#include <cassert>
#include <initializer_list>
static NSUInteger notices;
@interface CVNotifyController : NSObject
+ (void)notify:(NSString*)message;
@end
@implementation CVNotifyController
+ (void)notify:(NSString*)message { assert([message containsString:@"Shift 單按"]); ++notices; }
@end
@interface ProbeEvent : NSObject
@property NSEventType type;
@property unsigned short keyCode;
@property NSEventModifierFlags modifierFlags;
@property NSTimeInterval timestamp;
@end
@implementation ProbeEvent
@end
@interface ProbeController : NSObject {
@public
    IMKShiftTapProbe _shiftProbe;
    BOOL _shiftProbeEnabled;
}
- (void)_observeShiftProbeEvent:(NSEvent*)event;
@end
@implementation ProbeController
OBSERVER
@end
static void send(ProbeController *controller, NSEventType type, unsigned short code, NSEventModifierFlags flags, double time) {
    ProbeEvent *event = [ProbeEvent new];
    event.type = type; event.keyCode = code; event.modifierFlags = flags; event.timestamp = time;
    [controller _observeShiftProbeEvent:(NSEvent*)event];
}
int main() { @autoreleasepool {
    ProbeController *controller = [ProbeController new];
    send(controller, NSFlagsChanged, 56, NSShiftKeyMask, 1);
    send(controller, NSFlagsChanged, 56, 0, 1.1);
    assert(notices == 0); // Disabled is inert.
    controller->_shiftProbeEnabled = YES;
    for (unsigned short code : {56, 60}) {
        send(controller, NSFlagsChanged, code, NSShiftKeyMask, 2);
        send(controller, NSFlagsChanged, code, 0, 2.1);
    }
    assert(notices == 2);
    // Duplicate transitions observed in the installed IMK logs.
    send(controller, NSFlagsChanged, 56, NSShiftKeyMask, 2.2);
    send(controller, NSFlagsChanged, 56, NSShiftKeyMask, 2.205);
    send(controller, NSFlagsChanged, 56, 0, 2.3);
    send(controller, NSFlagsChanged, 56, 0, 2.302);
    assert(notices == 3);
    send(controller, NSFlagsChanged, 56, NSShiftKeyMask, 3);
    send(controller, NSKeyDown, 0, NSShiftKeyMask, 3.01);
    send(controller, NSFlagsChanged, 56, 0, 3.1);
    send(controller, NSFlagsChanged, 56, NSShiftKeyMask, 4);
    send(controller, NSFlagsChanged, 56, 0, 4.5);
    assert(notices == 3); // Chord and long press do not notify.
    puts("PASS: actual IMK observer, disabled gate, left/right tap, duplicate events, chord, long press");
} }
'''.replace("OBSERVER", observer)
with tempfile.TemporaryDirectory(prefix="keykey-imk-shift-tests-") as scratch:
    tmp = Path(scratch)
    common = ["xcrun", "clang++", "-std=c++17", "-I", str(loader)]
    subprocess.run([*common, str(loader / "Tests/IMKShiftTapProbeTests.cpp"), "-o", str(tmp / "state")], check=True)
    subprocess.run([str(tmp / "state")], check=True)
    (tmp / "observer.mm").write_text(fixture)
    subprocess.run([*common, "-fobjc-arc", "-Wno-deprecated-declarations", "-framework", "Cocoa",
                    str(tmp / "observer.mm"), "-o", str(tmp / "observer")], check=True)
    subprocess.run([str(tmp / "observer")], check=True)
