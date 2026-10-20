// Standalone state machine for the opt-in IMK event-delivery experiment.
#pragma once

struct IMKShiftTapProbe {
    enum Result { None, Pressed, Cancelled, Tap, LongPress };
    bool shiftDown = false;
    bool pending = false;
    unsigned short keyCode = 0;
    double startedAt = 0;
    double elapsed = 0;

    void reset() { *this = IMKShiftTapProbe(); }

    Result flagsChanged(unsigned short code, bool shift, bool otherModifiers, double time) {
        const bool wasDown = shiftDown;
        shiftDown = shift;
        if (code != 56 && code != 60) {
            return cancel();
        }
        if (shift && !wasDown) {
            keyCode = code;
            startedAt = time;
            pending = !otherModifiers;
            return pending ? Pressed : Cancelled;
        }
        if (!shift && wasDown) {
            const bool valid = pending && !otherModifiers && code == keyCode;
            pending = false;
            elapsed = time - startedAt;
            if (!valid || elapsed < 0) return Cancelled;
            return elapsed <= 0.300 ? Tap : LongPress;
        }
        // Some hosts deliver each flagsChanged transition twice. Preserve the
        // original press time and cancelled state; a duplicate must not re-arm
        // a gesture or turn a long press into a tap. The other Shift still cancels.
        if (shift && wasDown && code == keyCode && !otherModifiers)
            return None;
        return cancel();
    }

    Result cancel() {
        const bool hadPending = pending;
        pending = false;
        return hadPending ? Cancelled : None;
    }
};
