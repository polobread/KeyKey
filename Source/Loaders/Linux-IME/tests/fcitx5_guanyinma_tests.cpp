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
        std::istringstream conversion("%chardef begin\n國 国\n體 体\n%chardef end\n");
        simplified = std::make_shared<const linux_ime::CinDictionary>(linux_ime::CinDictionary::load(conversion));
        request();
    }
    ~Fixture() { std::filesystem::remove_all(scratch); }

    void request(std::string model = KEYKEY_TEST_MODEL_PATH) {
        state.requestSession(config, std::move(model), (scratch / "rust.db").string(),
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
        state.process(simplifiedOutput, false,
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
    std::shared_ptr<const linux_ime::CinDictionary> simplified;
    std::shared_ptr<const linux_ime::AssociatedPhraseDictionary> associated;
    std::vector<std::string> collections;
    fcitx5_adapter::ErrorSound sound;
    bool simplifiedOutput = false;
    bool horizontal = false;
};

void checkDefaultAndDeferredSettings() {
    KeyKeyConfig defaults;
    fcitx::RawConfig raw;
    defaults.save(raw);
    require(raw.get("InputCore") == nullptr, "Removed core selector remains in configuration");
    Fixture f;
    f.config.smartMode = false;
    f.request();
    f.character('s');
    require(f.state.usesGuanyinma() && !f.preedit().empty(), "Rust composition not active");
    f.config.traditionalSelectionKeys = "asdfghjk";
    f.request();
    f.character('u');
    require(f.state.settingsPending(), "Replaced session in an unfinished reading");
    require(f.state.commitAndReset(), "Settings handoff failed");
    const auto committed = f.allCommitted();
    f.character('s');
    require(f.state.usesGuanyinma() && !f.state.settingsPending(), "Quiet new event did not apply settings");
    require(f.allCommitted() == committed, "Settings change replayed a commit");
}

void checkCandidateOwnershipAndOneCommit() {
    Fixture f;
    f.config.smartMode = false;
    f.request();
    f.request();
    f.type("su3");
    auto candidates = f.context.inputPanel().candidateList();
    require(candidates && candidates->size() > 0 && candidates->size() <= 9, "Rust candidates not shown as one nine-key page");
    const auto selected = candidates->candidate(0).text().toString();
    f.config.traditionalSelectionKeys = "asdfghjk";
    f.request();
    require(f.state.usesGuanyinma() && f.state.settingsPending(), "Preference destroyed the old candidate session");
    f.state.select(0);
    require(f.allCommitted() == selected && f.context.commits.size() == 1, "Selected Rust candidate was not committed exactly once");
    f.character('s');
    require(f.state.usesGuanyinma() && !f.state.settingsPending(), "Next quiet event did not apply settings");
    candidates->candidate(0).select(&f.context);
    require(f.context.commits.size() == 1, "Obsolete Rust candidate selected a new backend row");
}

void checkStaleViewAndPageClick() {
    Fixture f;
    f.config.smartMode = false;
    f.request();
    f.request();
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
    f.request();
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
    f.request();
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
    f.config.traditionalSelectionKeys = "asdfghjk";
    f.request();
    f.character('b');
    require(f.state.usesGuanyinma() && f.allCommitted() == before + "ａｂ", "Settings replacement lost English/full-width mode");
}

void checkInitializationFailureAndRetryBoundary() {
    Fixture f;
    f.request((f.scratch / "missing-model.db").string());
    f.character('s');
    require(!f.state.usesGuanyinma() && f.state.coreStatus().find("無法啟用") != std::string::npos,
            "Rust initialization failure was hidden or selected a failed backend");
    require(f.preedit().empty() && f.context.commits.empty(), "Failed initialization executed a fallback or replayed the first key");
    f.state.reset();
    f.request();
    f.character('s');
    require(f.state.usesGuanyinma() && f.preedit() == "ㄋ", "Corrected model path did not permit explicit retry");
    f.state.commitAndReset();
    f.config.traditionalSelectionKeys = "asdfghjk";
    f.request((f.scratch / "missing-replacement.db").string());
    f.character('s');
    require(f.state.settingsPending() && f.state.coreStatus().find("無法啟用") != std::string::npos,
            "Replacement failure lost the pending configuration error");
    f.character('u');
    require(f.state.coreStatus().find("無法啟用") != std::string::npos,
            "A successful old-session event erased the replacement failure");
    f.state.commitAndReset();
    f.request();
    f.character('s');
    require(!f.state.settingsPending() && f.state.coreStatus().find("無法啟用") == std::string::npos,
            "Explicit corrected configuration could not retry replacement");
}

void checkTableHandoffAndIndependentContexts() {
    Fixture f;
    f.config.inputMethod = linux_ime::InputMethod::Cangjie;
    f.config.smartMode = false;
    f.request();
    f.request();
    f.character('a');
    require(!f.preedit().empty(), "Table code missing");
    f.state.commitAndReset();
    require(f.context.commits.empty() && f.preedit().empty(), "Unconfirmed table roots leaked into the document");
    Fixture other;
    other.character('s');
    require(other.state.usesGuanyinma() && other.state.chineseMode(), "Another input context inherited mode state");
}

void checkSmartClickAndUtf8Cursor() {
    Fixture f;
    f.request();
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
    f.request();
    f.addAssociatedFixture();
    f.request();
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
    f.config.traditionalSelectionKeys = "asdfghjk";
    f.request();
    require(f.state.settingsPending(), "FE overlay did not retain its backend ownership");
    f.state.select(0);
    require(f.allCommitted() == "你！", "FE raw associated text missed/doubled width conversion");
    f.character('s');
    require(f.state.usesGuanyinma() && !f.state.settingsPending(), "Completed FE overlay prevented a quiet settings update");

    Fixture sensitive;
    sensitive.config.smartMode = false;
    sensitive.request();
    sensitive.addAssociatedFixture();
    fcitx::CapabilityFlags capabilities(fcitx::CapabilityFlag::Preedit);
    capabilities |= fcitx::CapabilityFlag::Sensitive;
    sensitive.context.setCapabilityFlags(capabilities);
    sensitive.request();
    sensitive.type("su3");
    sensitive.state.select(0);
    require(sensitive.allCommitted() == "你" && !sensitive.context.inputPanel().candidateList(),
            "Sensitive field exposed FE associated phrases");
}

void checkSimplifiedOutputAndKeypad() {
    Fixture f;
    f.config.smartMode = false;
    f.request();
    f.addAssociatedFixture();
    f.simplifiedOutput = true;
    f.request();
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
    f.request();
    f.addAssociatedFixture();
    f.request();
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

void checkSavedPreferenceMapping() {
    fcitx::RawConfig raw;
    raw.setValueByPath("InputCore", "Legacy"); // An old selector cannot restore the removed backend.
    raw.setValueByPath("BopomofoMode", "Traditional");
    raw.setValueByPath("TraditionalSelectionKeys", "asdfghjk");
    raw.setValueByPath("IgnoreCapsLockInChinese", "True");
    raw.setValueByPath("LiteralKeypad", "False");
    raw.setValueByPath("AssociatedPhrases/McBopomofo", "False");
    raw.setValueByPath("AssociatedPhrases/government", "True");
    raw.setValueByPath("AssociatedPhrases/history", "True");
    raw.setValueByPath("UseUserPhrases", "False");
    raw.setValueByPath("SmartMandarin/ComposingTextBufferSize", "20");
    raw.setValueByPath("SmartMandarin/CandidateSelectionKeys", "asdfzxcv");
    raw.setValueByPath("SmartMandarin/SelectionReturnsToEnd", "True");
    raw.setValueByPath("SmartMandarin/ShiftKeyAlwaysCommitUppercaseCharacters", "True");
    raw.setValueByPath("SmartMandarin/UseBigrams", "False");
    raw.setValueByPath("SmartMandarin/LearnCandidateOverrides", "False");
    raw.setValueByPath("SmartMandarin/LearnBigrams", "False");
    raw.setValueByPath("Cangjie/ComposeWhileTyping", "True");
    raw.setValueByPath("Cangjie/ClearOnError", "True");
    raw.setValueByPath("Cangjie/UseDynamicFrequency", "True");
    raw.setValueByPath("Cangjie/PunctuationStyle", "mixed");
    raw.setValueByPath("Cangjie/MatchOneChar", "#");
    raw.setValueByPath("Simplex/MaximumRadicalLength", "1");
    raw.setValueByPath("Simplex/UseSpaceAsFirstCandidateSelectionKey", "True");
    KeyKeyConfig config;
    config.load(raw);
    fcitx::RawConfig saved;
    config.save(saved);
    require(saved.get("InputCore") == nullptr, "Old core selector survived settings save");
    KeyKeyConfig restored;
    restored.load(saved);
    require(enabledAssociatedPhraseCollections(*restored.associatedPhrases) ==
                std::vector<std::string>{"government", "history"},
            "Associated phrase checkboxes did not round-trip independently");
    auto settings = sessionSettings(restored, "chichi77-keykey-bopomofo");
    require(!settings.smartMode && settings.traditionalSelectionKeys == "asdfghjk" && settings.ignoreCapsLockInChinese &&
            !settings.literalKeypad && !settings.userPhrases, "General/traditional preferences did not round-trip into Rust settings");
    require(settings.smart.maxCompletedSyllables == 20 && settings.smart.candidateSelectionKeys == "asdfzxcv" &&
            settings.smart.selectionReturnsToEnd && settings.smart.shiftAlwaysUppercase && !settings.smart.useBigrams &&
            !settings.smart.learnBigrams && !settings.smart.learnCandidateOverrides, "Smart preferences did not map into Rust settings");
    require(settings.table.composeWhileTyping && !settings.table.clearOnError && settings.table.learnSelection &&
            settings.table.punctuation == "mixed" && settings.table.wildcardOne == "#" &&
            settings.simplex.maximumRadicalLength == 1 && settings.simplex.spaceAsFirstSelectionKey,
            "Table preferences did not remain independent or normalize realtime/error policy");
    Fixture f;
    f.config = settings;
    f.request();
    f.type("su3");
    const auto candidates = f.context.inputPanel().candidateList();
    require(candidates && candidates->label(0).toString().find('a') != std::string::npos,
            "Saved preference keys were not used by the actual Rust/Fcitx candidate view");
}

void checkSelectionKeysAndConfiguredModes() {
    Fixture f;
    f.config.smartMode = false;
    f.config.traditionalSelectionKeys = "asdfghjk";
    f.request();
    f.type("su3");
    auto candidates = f.context.inputPanel().candidateList();
    require(candidates && candidates->size() <= 8 && candidates->label(0).toString().find('a') != std::string::npos,
            "Fcitx candidate labels/page did not use configured letter keys");
    const auto selected = candidates->candidate(0).text().toString();
    f.character('a');
    require(f.allCommitted() == selected, "Configured letter key did not choose its displayed candidate");
    Fixture english;
    english.state.initializeMode(false);
    require(!english.character('a') && english.allCommitted().empty(), "Configured initial English mode did not pass through");
    fcitx::KeyEvent press(&english.context, fcitx::Key(FcitxKey_Shift_L), false, 1000);
    fcitx::KeyEvent release(&english.context, fcitx::Key(FcitxKey_Shift_L, fcitx::KeyState::Shift), true, 1100);
    english.state.processModeKey(true, press, false);
    english.state.processModeKey(true, release, false);
    require(!english.state.chineseMode() && !release.filtered(), "Disabled Shift toggle still changed language or filtered release");
}

void checkReentrantContextDestruction() {
    {
        // Delete both objects from the first actual native preedit callback.
        // Fcitx may coalesce Rust finish/reset updates with equal empty text.
        for (const bool clientUnfocus : {false, true}) {
            Fixture source;
            source.config.smartMode = false;
            source.request();
            auto context = std::make_unique<RecordingContext>(source.manager);
            auto state = std::make_unique<FcitxState>(context.get());
            state->requestSession(source.config, KEYKEY_TEST_MODEL_PATH,
                (source.scratch / "reentrant.db").string(), nullptr, source.simplified, {},
                [](const std::string &) { return true; });
            linux_ime::KeyEvent character;
            character.character = 's'; character.text = "s";
            fcitx::KeyEvent native(context.get(), fcitx::Key(FcitxKey_s));
            state->process(false, false,
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
                    "Handoff reported a live owner after reentrant reset/preedit destruction: clientUnfocus=" + std::to_string(clientUnfocus) +
                    ", updates=" + std::to_string(updates) + ", finished=" + std::to_string(finished));
        }
    }

    for (const bool destroyOnCommit : {false, true}) {
        Fixture source;
        source.config.smartMode = false;
        source.request();
        auto context = std::make_unique<RecordingContext>(source.manager);
        auto state = std::make_unique<FcitxState>(context.get());
        state->requestSession(source.config, KEYKEY_TEST_MODEL_PATH,
            (source.scratch / "reentrant-shortcut.db").string(), nullptr, source.simplified, {},
            [](const std::string &) { return true; });
        linux_ime::KeyEvent character;
        character.character = 's'; character.text = "s";
        fcitx::KeyEvent native(context.get(), fcitx::Key(FcitxKey_s));
        state->process(false, false,
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
        checkDefaultAndDeferredSettings();
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
        checkSavedPreferenceMapping();
        checkSelectionKeysAndConfiguredModes();
        checkReentrantContextDestruction();
        std::cout << "Fcitx Guanyinma settings and lifecycle, candidates, modes, cursor and one-shot host effects passed\n";
        return 0;
    } catch (const std::exception &error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
