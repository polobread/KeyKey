#include "../IMKShiftTap.h"
#include <cassert>
#include <iostream>

int main() {
    using Probe = IMKShiftTap;
    Probe probe;
    for (unsigned short code : {56, 60}) {
        probe.reset();
        assert(probe.flagsChanged(code, true, false, 1.0) == Probe::Pressed);
        assert(probe.flagsChanged(code, false, false, 1.2) == Probe::Tap);
    }
    // Replay the observed host pattern: down/down/up/up. Exactly one tap.
    for (unsigned short code : {56, 60}) {
        probe.reset();
        assert(probe.flagsChanged(code, true, false, 1.0) == Probe::Pressed);
        assert(probe.flagsChanged(code, true, false, 1.005) == Probe::None);
        assert(probe.flagsChanged(code, false, false, 1.1) == Probe::Tap);
        assert(probe.flagsChanged(code, false, false, 1.102) == Probe::None);
        probe.flagsChanged(code, true, false, 2.0);
        probe.flagsChanged(code, true, false, 2.4);
        assert(probe.flagsChanged(code, false, false, 2.5) == Probe::LongPress);
        probe.flagsChanged(code, true, false, 3.0);
        probe.cancel();
        probe.flagsChanged(code, true, false, 3.02);
        assert(probe.flagsChanged(code, false, false, 3.1) == Probe::Cancelled);
    }
    probe.reset();
    probe.flagsChanged(56, true, false, 0);
    assert(probe.flagsChanged(56, false, false, .300) == Probe::Tap);
    probe.flagsChanged(56, true, false, 1);
    assert(probe.flagsChanged(56, false, false, 1.301) == Probe::LongPress);
    probe.flagsChanged(56, true, false, 2);
    probe.cancel(); // Any ordinary key down, including letters and arrows.
    assert(probe.flagsChanged(56, false, false, 2.1) == Probe::Cancelled);
    probe.flagsChanged(56, true, true, 3);
    assert(probe.flagsChanged(56, false, false, 3.1) == Probe::Cancelled);
    probe.flagsChanged(56, true, false, 4);
    probe.flagsChanged(59, true, true, 4.01); // Ctrl pressed after Shift.
    probe.flagsChanged(59, true, false, 4.02); // Ctrl released first.
    assert(probe.flagsChanged(56, false, false, 4.1) == Probe::Cancelled);
    probe.flagsChanged(56, true, false, 5);
    probe.flagsChanged(60, true, false, 5.01);
    probe.flagsChanged(56, true, false, 5.02);
    assert(probe.flagsChanged(60, false, false, 5.1) == Probe::Cancelled);
    probe.flagsChanged(56, true, false, 6);
    probe.reset(); // Deactivation and activation discard incomplete gestures.
    assert(probe.flagsChanged(56, false, false, 6.1) != Probe::Tap);
    probe.flagsChanged(56, true, false, 7);
    assert(probe.flagsChanged(60, false, false, 7.1) == Probe::Cancelled);
    probe.flagsChanged(56, true, false, 8);
    assert(probe.flagsChanged(56, false, false, 7.9) == Probe::Cancelled);
    assert(probe.flagsChanged(56, false, false, 8.1) != Probe::Tap);
    std::cout << "PASS: IMK Shift tap state, timing, duplicate host events, chords, dual Shift, lifecycle, unmatched release\n";
}
