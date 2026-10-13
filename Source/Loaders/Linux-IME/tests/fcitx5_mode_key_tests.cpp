// Include the implementation to test the actual private FcitxState, not a
// second model of its behavior. No engine addon or desktop session is started.
#include "../adapters/fcitx5/fcitx5_engine.cpp"

#include <iostream>
#include <stdexcept>

namespace {

class TestInputContext final : public fcitx::InputContext {
public:
    explicit TestInputContext(fcitx::InputContextManager &manager)
        : fcitx::InputContext(manager, "keykey-mode-key-test") {
        created();
        focusIn();
    }
    ~TestInputContext() override { destroy(); }
    const char *frontend() const override { return "keykey-test"; }

protected:
    void commitStringImpl(const std::string &) override {}
    void deleteSurroundingTextImpl(int, unsigned int) override {}
    void forwardKeyImpl(const fcitx::ForwardKeyEvent &) override {}
    void updatePreeditImpl() override {}
};

void require(bool condition, const char *message) {
    if (!condition) {
        throw std::runtime_error(message);
    }
}

void checkShift(fcitx::KeySym symbol, bool longHold) {
    fcitx::InputContextManager manager;
    TestInputContext context(manager);
    FcitxState state(&context);
    bool clientShiftHeld = false;
    for (int tap = 0; tap < 2; ++tap) {
        const bool before = state.chineseMode();
        fcitx::KeyEvent press(&context, fcitx::Key(symbol), false, 1000);
        require(!state.processModeKey(true, press), "Shift press was filtered");
        require(!press.accepted(), "Shift press was swallowed");
        clientShiftHeld = true;
        require(state.chineseMode() == before, "Shift toggled before release");

        // Shift is still in the event's modifier mask at release. Acceptance,
        // not this mask, determines whether the frontend delivers it to App.
        fcitx::KeyEvent release(
            &context, fcitx::Key(symbol, fcitx::KeyState::Shift), true,
            longHold ? 1500 : 1100);
        require(state.processModeKey(true, release), "Tracked release not filtered");
        require(release.filtered(), "Shift release can trigger another IM handler");
        if (!release.accepted()) {
            clientShiftHeld = false;
        }
        require(!clientShiftHeld, "Client Shift stayed held after physical release");
        require(state.chineseMode() == (longHold ? before : !before),
                "Shift tap/hold toggled mode incorrectly");

        fcitx::KeyEvent duplicate(&context, fcitx::Key(symbol), true, 1600);
        require(!state.processModeKey(true, duplicate), "Untracked release was owned");
        require(!duplicate.accepted(), "Untracked release was swallowed");
        require(state.chineseMode() == (longHold ? before : !before),
                "Duplicate release toggled mode");
    }
}

void checkCancelledShift(bool reset) {
    fcitx::InputContextManager manager;
    TestInputContext context(manager);
    FcitxState state(&context);
    fcitx::KeyEvent press(&context, fcitx::Key(FcitxKey_Shift_L), false, 1000);
    state.processModeKey(true, press);
    if (reset) {
        state.reset(); // Focus/input-method changes clear a pending tap.
    } else {
        fcitx::KeyEvent letter(
            &context, fcitx::Key(FcitxKey_A, fcitx::KeyState::Shift), false, 1050);
        state.processModeKey(true, letter);
    }
    fcitx::KeyEvent release(
        &context, fcitx::Key(FcitxKey_Shift_L, fcitx::KeyState::Shift), true, 1100);
    state.processModeKey(true, release);
    require(!release.accepted(), "Cancelled Shift release was swallowed");
    require(state.chineseMode(), "Cancelled Shift tap changed mode");
}

void checkOtherShortcuts() {
    fcitx::InputContextManager manager;
    TestInputContext context(manager);
    FcitxState state(&context);
    for (bool release : {false, true}) {
        fcitx::KeyEvent space(
            &context, fcitx::Key(FcitxKey_space, fcitx::KeyState::Ctrl), release, 1000);
        require(!state.processModeKey(true, space), "Ctrl+Space was intercepted");
        require(!space.filtered() && !space.accepted(), "Ctrl+Space no longer reaches Fcitx");
    }
    fcitx::KeyEvent press(
        &context, fcitx::Key(FcitxKey_backslash, fcitx::KeyState::Ctrl), false, 1000);
    state.processModeKey(true, press);
    require(press.accepted() && !state.chineseMode(), "Ctrl+backslash no longer switches mode");
    fcitx::KeyEvent release(&context, fcitx::Key(FcitxKey_backslash), true, 1100);
    state.processModeKey(true, release);
    require(release.accepted() && !state.chineseMode(), "Owned shortcut release changed mode");
}

} // namespace

int main() {
    try {
        for (auto symbol : {FcitxKey_Shift_L, FcitxKey_Shift_R}) {
            checkShift(symbol, false);
            checkShift(symbol, true);
        }
        checkCancelledShift(false);
        checkCancelledShift(true);
        checkOtherShortcuts();
        std::cout << "Shift tap/hold releases reach client; mode and shortcuts preserved\n";
        return 0;
    } catch (const std::exception &error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
