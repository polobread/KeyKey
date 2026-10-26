// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
// Exercise the actual Fcitx adapter without starting a desktop or an addon.
#include "../adapters/fcitx5/fcitx5_engine.cpp"

#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <unistd.h>

namespace {

void require(bool condition, const std::string &message) {
    if (!condition) throw std::runtime_error(message);
}

class RecordingContext final : public fcitx::InputContext {
public:
    explicit RecordingContext(fcitx::InputContextManager &manager)
        : fcitx::InputContext(manager, "keykey-guanyinma-test") {
        created();
        setCapabilityFlags(fcitx::CapabilityFlag::Preedit);
        focusIn();
    }
    ~RecordingContext() override { destroy(); }
    const char *frontend() const override { return "keykey-test"; }
    std::vector<std::string> commits;
    std::vector<fcitx::KeySym> forwarded;
    std::function<void()> onCommit;
    std::function<void()> onPreedit;
protected:
    void commitStringImpl(const std::string &text) override {
        commits.push_back(text);
        const auto callback = onCommit;
        if (callback) callback();
    }
    void deleteSurroundingTextImpl(int, unsigned int) override {}
    void forwardKeyImpl(const fcitx::ForwardKeyEvent &event) override {
        if (!event.isRelease()) forwarded.push_back(event.rawKey().sym());
    }
    void updatePreeditImpl() override {
        const auto callback = onPreedit;
        if (callback) callback();
    }
};

class Fixture {
public:
    Fixture() : context(manager), state(&context) {
        char pattern[] = "/tmp/keykey-fcitx-guanyinma-XXXXXX";
        const auto directory = mkdtemp(pattern);
        require(directory != nullptr, "Cannot create private test directory");
        scratch = directory;
        dictionary = std::make_shared<const linux_ime::CinDictionary>(
            linux_ime::CinDictionary::loadFile(std::string(KEYKEY_TEST_SOURCE_DATA_DIR) + "/bpmf-ext.cin"));
        std::istringstream conversion("%chardef begin\n國 国\n體 体\n%chardef end\n");
        simplified = std::make_shared<const linux_ime::CinDictionary>(linux_ime::CinDictionary::load(conversion));
        rebuildEngine();
    }
    ~Fixture() { std::filesystem::remove_all(scratch); }

    void rebuildEngine() {
        const std::string table = config.inputMethod == linux_ime::InputMethod::Cangjie ? "cj-ext.cin"
            : config.inputMethod == linux_ime::InputMethod::Simplex ? "simplex-ext.cin" : "bpmf-ext.cin";
        auto source = std::make_shared<const linux_ime::CinDictionary>(linux_ime::CinDictionary::loadFile(
            std::string(KEYKEY_TEST_SOURCE_DATA_DIR) + "/" + table));
        engine = std::make_unique<linux_ime::Engine>(source, config.inputMethod, config.layout);
        engine->setSmartMandarinStore(linux_ime::SmartMandarinStore::open(KEYKEY_TEST_MODEL_PATH));
        engine->setSmartMandarinMode(config.smartMode);
    }

    void request(bool rust, std::string model = KEYKEY_TEST_MODEL_PATH) {
        state.requestCore(rust, config, std::move(model), (scratch / "rust.db").string(),
                          associated, simplified, collections,
                          [](const std::string &) { return true; });
    }

    void addAssociatedFixture() {
        const auto directory = scratch / "associated";
        std::filesystem::create_directory(directory);
        std::ofstream(directory / "display-names.tsv") << "McBopomofo\t測試\n";
        std::ofstream(directory / "McBopomofo.occ") << "你! 10\n你國 5\n";
        associated = std::make_shared<const linux_ime::AssociatedPhraseDictionary>(
            linux_ime::AssociatedPhraseDictionary::loadDirectory(directory.string()));
        collections = {"McBopomofo"};
    }

    bool send(linux_ime::KeyEvent key) {
        fcitx::KeySym sym = key.code == linux_ime::KeyCode::Space ? FcitxKey_space
            : key.code == linux_ime::KeyCode::Enter ? FcitxKey_Return
            : key.code == linux_ime::KeyCode::Backspace ? FcitxKey_BackSpace
            : key.code == linux_ime::KeyCode::Down ? FcitxKey_Down
            : key.code == linux_ime::KeyCode::Escape ? FcitxKey_Escape
            : static_cast<fcitx::KeySym>(static_cast<unsigned char>(key.character));
        fcitx::KeyEvent native(&context, fcitx::Key(sym), key.release);
        state.process(*engine, config.smartMode, simplifiedOutput, false,
                      horizontal ? fcitx::CandidateLayoutHint::Horizontal : fcitx::CandidateLayoutHint::Vertical,
                      sound, key, native);
        return native.accepted();
    }

    bool character(char value) {
        linux_ime::KeyEvent key;
        key.character = value;
        key.text.assign(1, value);
        return send(key);
    }
    bool key(linux_ime::KeyCode code) {
        linux_ime::KeyEvent event;
        event.code = code;
        return send(event);
    }
    void type(const std::string &text) { for (const auto c : text) character(c); }
    std::string preedit() const { return context.inputPanel().clientPreedit().toString(); }
    std::string allCommitted() const {
        std::string result;
        for (const auto &text : context.commits) result += text;
        return result;
    }

    fcitx::InputContextManager manager;
    RecordingContext context;
    FcitxState state;
    linux_ime::GuanyinmaConfig config;
    std::filesystem::path scratch;
    std::shared_ptr<const linux_ime::CinDictionary> dictionary;
    std::shared_ptr<const linux_ime::CinDictionary> simplified;
    std::shared_ptr<const linux_ime::AssociatedPhraseDictionary> associated;
    std::vector<std::string> collections;
    std::unique_ptr<linux_ime::Engine> engine;
    fcitx5_adapter::ErrorSound sound;
    bool simplifiedOutput = false;
    bool horizontal = false;
};

void checkDefaultAndDeferredLegacySwitch() {
    KeyKeyConfig defaults;
    require(*defaults.inputCore == "Legacy", "C++ is not the saved default core");
    Fixture f;
    f.config.smartMode = false;
    f.rebuildEngine();
    f.character('s');
    require(!f.state.usesGuanyinma() && !f.preedit().empty(), "Legacy composition not active");
    f.request(true);
    f.character('u');
    require(!f.state.usesGuanyinma() && f.state.corePending(), "Switched in an unfinished legacy reading");
    require(f.state.commitAndReset(), "Legacy handoff failed");
    const auto committed = f.allCommitted();
    f.character('s');
    require(f.state.usesGuanyinma() && !f.state.corePending(), "Quiet new event did not select Rust");
    require(f.allCommitted() == committed, "Core switch replayed a legacy commit");
}

void checkCandidateOwnershipAndOneCommit() {
    Fixture f;
    f.config.smartMode = false;
    f.rebuildEngine();
    f.request(true);
    f.type("su3");
    auto candidates = f.context.inputPanel().candidateList();
    require(candidates && candidates->size() > 0 && candidates->size() <= 9, "Rust candidates not shown as one nine-key page");
    const auto selected = candidates->candidate(0).text().toString();
    f.request(false);
    require(f.state.usesGuanyinma() && f.state.corePending(), "Preference destroyed the old candidate session");
    f.state.select(0);
    require(f.allCommitted() == selected && f.context.commits.size() == 1, "Selected Rust candidate was not committed exactly once");
    f.character('s');
    require(!f.state.usesGuanyinma(), "Next quiet event did not return to C++");
    candidates->candidate(0).select(&f.context);
    require(f.context.commits.size() == 1, "Obsolete Rust candidate selected a new backend row");
}

void checkStaleViewAndPageClick() {
    Fixture f;
    f.config.smartMode = false;
    f.rebuildEngine();
    f.request(true);
    f.type("su3");
    auto old = f.context.inputPanel().candidateList();
    require(old && old->size() > 0, "No old candidate list");
    f.key(linux_ime::KeyCode::PageDown);
    auto next = f.context.inputPanel().candidateList();
    require(next && next->size() > 0, "No next-page candidate list");
    old->candidate(0).select(&f.context);
    require(f.context.commits.empty(), "Old page callback committed a different page");
    const auto selected = next->candidate(0).text().toString();
    next->candidate(0).select(&f.context);
    require(f.allCommitted() == selected, "Page-local mouse index selected the wrong text");
}

void checkClientUnfocusCommitAndRepeatedReset() {
    Fixture f;
    f.request(true);
    f.type("su3");
    require(!f.preedit().empty(), "No client preedit before focus-out");
    fcitx::CapabilityFlags capabilities(fcitx::CapabilityFlag::Preedit);
    capabilities |= fcitx::CapabilityFlag::ClientUnfocusCommit;
    f.context.setCapabilityFlags(capabilities);
    f.context.focusOut();
    f.state.commitAndReset(true);
    f.state.reset();
    f.state.commitAndReset(true);
    require(f.context.commits.empty(), "Client-unfocus preedit was committed a second time");
    f.context.focusIn();
    f.character('s');
    require(f.preedit() == "ㄋ", "Old composition revived after a new host boundary");
}

void checkModeWidthAndEnglishPassThrough() {
    Fixture f;
    f.request(true);
    f.character('s');
    require(f.state.commitAndReset(), "Cannot clear initial reading");
    fcitx::KeyEvent press(&f.context, fcitx::Key(FcitxKey_Shift_L), false, 1000);
    fcitx::KeyEvent release(&f.context, fcitx::Key(FcitxKey_Shift_L, fcitx::KeyState::Shift), true, 1100);
    f.state.processModeKey(true, press);
    f.state.processModeKey(true, release);
    require(!f.state.chineseMode() && release.filtered() && !release.accepted(), "Shift mode/release contract changed");
    const auto before = f.allCommitted();
    require(!f.character('a') && f.allCommitted() == before, "English half-width stopped passing through");
    linux_ime::KeyEvent width;
    width.code = linux_ime::KeyCode::Space;
    width.rawShift = true;
    width.modifiers = linux_ime::KeyModifier::Shift;
    f.send(width);
    f.character('a');
    require(f.allCommitted() == before + "ａ", "Rust full-width English was not committed once");
    f.request(false);
    f.character('b');
    require(!f.state.usesGuanyinma() && f.allCommitted() == before + "ａｂ", "Core switch lost English/full-width mode");
}

void checkInitializationFailureAndRetryBoundary() {
    Fixture f;
    f.request(true, (f.scratch / "missing-model.db").string());
    f.character('s');
    require(!f.state.usesGuanyinma() && f.state.coreStatus().find("無法啟用") != std::string::npos,
            "Rust initialization failure was hidden or selected a failed backend");
    require(f.preedit() == "ㄋ", "Initial fallback lost or replayed the first key");
    f.state.reset();
    f.request(true);
    f.character('s');
    require(f.state.usesGuanyinma() && f.preedit() == "ㄋ", "Corrected model path did not permit explicit retry");
}

void checkTableHandoffAndIndependentContexts() {
    Fixture f;
    f.config.inputMethod = linux_ime::InputMethod::Cangjie;
    f.config.smartMode = false;
    f.rebuildEngine();
    f.request(true);
    f.character('a');
    require(!f.preedit().empty(), "Table code missing");
    f.state.commitAndReset();
    require(f.context.commits.empty() && f.preedit().empty(), "Unconfirmed table roots leaked into the document");
    Fixture other;
    other.character('s');
    require(!other.state.usesGuanyinma() && other.state.chineseMode(), "Another input context inherited Rust/core mode");
}

void checkSmartClickAndUtf8Cursor() {
    Fixture f;
    f.request(true);
    f.type("su3cl3");
    const auto preedit = f.preedit();
    require(!preedit.empty() && f.context.inputPanel().clientPreedit().cursor() == static_cast<int>(preedit.size()),
            "Rust Unicode scalar cursor was not mapped to UTF-8 bytes");
    require(f.state.selectSmartCharacter(0), "Smart preedit click did not target a completed reading");
    auto candidates = f.context.inputPanel().candidateList();
    require(candidates && candidates->size() > 0, "Smart click did not open candidates");
    f.state.select(0);
    require(f.context.commits.empty(), "Smart candidate click committed the whole sentence");
    f.key(linux_ime::KeyCode::Enter);
    require(f.context.commits.size() == 1 && !f.allCommitted().empty(), "Smart Enter did not produce a single host commit");
}

void checkAssociatedWidthAndSensitiveFields() {
    Fixture f;
    f.config.smartMode = false;
    f.rebuildEngine();
    f.addAssociatedFixture();
    f.request(true);
    f.type("su3");
    f.state.select(0);
    auto candidates = f.context.inputPanel().candidateList();
    require(f.allCommitted() == "你" && candidates && candidates->size() == 2,
            "Shared FE associated-phrase fixture was not offered after Rust selection");
    linux_ime::KeyEvent width;
    width.code = linux_ime::KeyCode::Space;
    width.rawShift = true;
    width.modifiers = linux_ime::KeyModifier::Shift;
    f.send(width);
    f.request(false);
    require(f.state.corePending(), "FE overlay did not retain its backend ownership");
    f.state.select(0);
    require(f.allCommitted() == "你！", "FE raw associated text missed/doubled width conversion");
    f.character('s');
    require(!f.state.usesGuanyinma(), "Completed FE overlay prevented a quiet core switch");

    Fixture sensitive;
    sensitive.config.smartMode = false;
    sensitive.rebuildEngine();
    sensitive.addAssociatedFixture();
    fcitx::CapabilityFlags capabilities(fcitx::CapabilityFlag::Preedit);
    capabilities |= fcitx::CapabilityFlag::Sensitive;
    sensitive.context.setCapabilityFlags(capabilities);
    sensitive.request(true);
    sensitive.type("su3");
    sensitive.state.select(0);
    require(sensitive.allCommitted() == "你" && !sensitive.context.inputPanel().candidateList(),
            "Sensitive field exposed FE associated phrases");
}

void checkSimplifiedOutputAndKeypad() {
    Fixture f;
    f.config.smartMode = false;
    f.rebuildEngine();
    f.addAssociatedFixture();
    f.simplifiedOutput = true;
    f.request(true);
    f.type("su3");
    f.state.select(0);
    f.state.select(1);
    require(f.allCommitted() == "你国", "FE associated commit did not use the shared output conversion");
    f.type("su3");
    linux_ime::KeyEvent keypad;
    keypad.character = '1';
    keypad.text = "1";
    keypad.keypad = true;
    keypad.numLock = true;
    f.send(keypad);
    require(!f.allCommitted().empty() && f.allCommitted().back() == '1',
            "Actual keypad digit was consumed as a candidate selection");
}

void checkAssociatedShortcutDoesNotSelect() {
    Fixture f;
    f.config.smartMode = false;
    f.rebuildEngine();
    f.addAssociatedFixture();
    f.request(true);
    f.type("su3");
    f.state.select(0);
    require(f.context.inputPanel().candidateList() != nullptr, "No associated overlay before shortcut");
    linux_ime::KeyEvent shortcut;
    shortcut.character = '!';
    shortcut.text = "!";
    shortcut.rawShift = true;
    shortcut.modifiers = linux_ime::KeyModifier::Control | linux_ime::KeyModifier::Shift;
    require(!f.send(shortcut) && f.allCommitted() == "你",
            "Ctrl+Shift+1 selected an associated phrase instead of passing through");
}

void checkLegacyNativeOnlyEventsPassThrough() {
    Fixture f;
    f.config.smartMode = false;
    f.rebuildEngine();
    f.type("su3");
    const auto before = f.preedit();
    auto candidates = f.context.inputPanel().candidateList();
    require(candidates && candidates->size() > 0, "Legacy candidate fixture missing");
    const auto selected = candidates->candidate(0).text().toString();
    const auto check = [&](fcitx::Key key, linux_ime::KeyEvent translated) {
        fcitx::KeyEvent native(&f.context, key);
        require(!legacyInputKey(native), "Native-only fixture unexpectedly belongs to the original translator");
        f.state.process(*f.engine, false, false, false,
            fcitx::CandidateLayoutHint::Vertical, f.sound, translated, native);
        require(!native.accepted() && f.context.commits.empty() && f.preedit() == before,
                "Expanded native event was dispatched to the legacy candidate engine");
        auto current = f.context.inputPanel().candidateList();
        require(current && current->candidate(0).text().toString() == selected,
                "Expanded native event changed a legacy candidate view");
    };
    linux_ime::KeyEvent keypad;
    keypad.character = '1'; keypad.text = "1"; keypad.keypad = true; keypad.numLock = true;
    check(fcitx::Key(FcitxKey_KP_1, fcitx::KeyState::NumLock), keypad);
    linux_ime::KeyEvent unicode;
    unicode.text = "中";
    check(fcitx::Key(fcitx::Key::keySymFromUnicode(0x4e2dU)), unicode);
    linux_ime::KeyEvent navigation;
    navigation.code = linux_ime::KeyCode::Left; navigation.keypad = true;
    check(fcitx::Key(FcitxKey_KP_Left), navigation);
}

void checkReentrantContextDestruction() {
    for (const bool rust : {false, true}) {
        // Delete both objects from the first actual native preedit callback.
        // Fcitx may coalesce Rust finish/reset updates with equal empty text.
        for (const bool clientUnfocus : {false, true}) {
            Fixture source;
            source.config.smartMode = false;
            source.rebuildEngine();
            auto context = std::make_unique<RecordingContext>(source.manager);
            auto state = std::make_unique<FcitxState>(context.get());
            state->requestCore(rust, source.config, KEYKEY_TEST_MODEL_PATH,
                (source.scratch / "reentrant.db").string(), nullptr, source.simplified, {},
                [](const std::string &) { return true; });
            linux_ime::KeyEvent character;
            character.character = 's'; character.text = "s";
            fcitx::KeyEvent native(context.get(), fcitx::Key(FcitxKey_s));
            state->process(*source.engine, false, false, false,
                fcitx::CandidateLayoutHint::Vertical, source.sound, character, native);
            if (clientUnfocus) {
                fcitx::CapabilityFlags flags(fcitx::CapabilityFlag::Preedit);
                flags |= fcitx::CapabilityFlag::ClientUnfocusCommit;
                context->setCapabilityFlags(flags);
                context->focusOut();
            }
            const auto original = context->watch();
            int updates = 0;
            context->onPreedit = [&] {
                ++updates;
                state.reset();
                context.reset();
            };
            auto *const active = state.get();
            const bool finished = active->commitAndReset();
            require(!original.isValid() && !finished && !state && !context,
                    "Handoff reported a live owner after reentrant reset/preedit destruction: rust=" +
                    std::to_string(rust) + ", clientUnfocus=" + std::to_string(clientUnfocus) +
                    ", updates=" + std::to_string(updates) + ", finished=" + std::to_string(finished));
        }
    }

    for (const bool destroyOnCommit : {false, true}) {
        Fixture source;
        source.config.smartMode = false;
        source.rebuildEngine();
        auto context = std::make_unique<RecordingContext>(source.manager);
        auto state = std::make_unique<FcitxState>(context.get());
        linux_ime::KeyEvent character;
        character.character = 's'; character.text = "s";
        fcitx::KeyEvent native(context.get(), fcitx::Key(FcitxKey_s));
        state->process(*source.engine, false, false, false,
            fcitx::CandidateLayoutHint::Vertical, source.sound, character, native);
        const auto original = context->watch();
        const auto destroy = [&] { state.reset(); context.reset(); };
        if (destroyOnCommit) context->onCommit = destroy;
        else context->onPreedit = destroy;
        fcitx::KeyEvent shortcut(context.get(),
            fcitx::Key(FcitxKey_backslash, fcitx::KeyState::Ctrl), false, 1000);
        auto *const active = state.get();
        require(active->processModeKey(true, shortcut), "Owned shortcut was not consumed after owner destruction");
        require(!original.isValid() && !state && !context && shortcut.accepted(),
                "Ctrl+backslash continued through a destroyed host/state: commit=" +
                std::to_string(destroyOnCommit) + ", owner=" + std::to_string(original.isValid()) +
                ", state=" + std::to_string(bool(state)) + ", accepted=" + std::to_string(shortcut.accepted()));
    }
}

} // namespace

int main() {
    try {
        checkDefaultAndDeferredLegacySwitch();
        checkCandidateOwnershipAndOneCommit();
        checkStaleViewAndPageClick();
        checkClientUnfocusCommitAndRepeatedReset();
        checkModeWidthAndEnglishPassThrough();
        checkInitializationFailureAndRetryBoundary();
        checkTableHandoffAndIndependentContexts();
        checkSmartClickAndUtf8Cursor();
        checkAssociatedWidthAndSensitiveFields();
        checkSimplifiedOutputAndKeypad();
        checkAssociatedShortcutDoesNotSelect();
        checkLegacyNativeOnlyEventsPassThrough();
        checkReentrantContextDestruction();
        std::cout << "Fcitx dual-core lifecycle, candidates, modes, cursor and one-shot host effects passed\n";
        return 0;
    } catch (const std::exception &error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
