// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
// Exercise the actual macOS adapter without starting IMK or reading a user profile.
#import <Foundation/Foundation.h>
#include "GuanyinmaMacAdapter.h"
#include "GuanyinmaMacUserData.h"
#include "guanyinma.h"
#include "PVBasicKeyValueMapImpl.h"
#include "PVCandidate.h"
#include "PVLoaderService.h"
#include "PVTextBuffer.h"
#include "PVContextSandwich.h"
#include "PVLoaderSystem.h"
#include "OVOFHanConvert.h"
#include "OVOFFullWidthCharacter.h"
#include <filesystem>
#include <iostream>
#include <memory>
#include <stdexcept>

using namespace OpenVanilla;
namespace fs = std::filesystem;
static size_t checks;
static void require(bool value, const std::string& message) {
    ++checks;
    if (!value) throw std::runtime_error(message);
}
static void expectText(const std::string& actual, const std::string& expected, const std::string& message) {
    require(actual == expected, message + ": expected [" + expected + "], got [" + actual + "]");
}
static const char* Smart = "SmartMandarin";
static const char* Traditional = "TraditionalMandarin";
static const char* Cangjie = "Generic-cj-cin";
static const char* Simplex = "Generic-simplex-cin";

class Harness {
public:
    PVBasicKeyValueMapImpl values;
    OVKeyValueMap config;
    PVLoaderService loader;
    PVCandidateService candidates;
    PVTextBuffer reading, composing;
    std::unique_ptr<OVEventHandlingContext> context;
    std::string committed;
    explicit Harness(OVEncodingService* encoding = nullptr, const std::string& locale = "zh_TW")
        : config(&values), loader(locale, nullptr, nullptr, nullptr, encoding), candidates(&loader) {
        config.setKeyStringValue("KeyboardLayout", "Standard");
        config.setKeyStringValue("CandidateSelectionKeys", "12345678");
        config.setKeyBoolValue("ShowCandidateListWithSpace", true);
        config.setKeyBoolValue("CandidateCursorAtEndOfTargetBlock", false);
        config.setKeyBoolValue("ClearComposingTextWithEsc", false);
        config.setKeyIntValue("ComposingTextBufferSize", 10);
        config.setKeyBoolValue("ComposeWhileTyping", false);
        config.setKeyBoolValue("PrefixCandidates", false);
        config.setKeyBoolValue("UseDynamicFrequency", true);
        config.setKeyBoolValue("ClearReadingBufferAtCompositionError", true);
    }
    ~Harness() { if (context) context->stopSession(&loader); }
    void open(const char* method, const fs::path& model, const fs::path& user) {
        if (context) context->stopSession(&loader);
        context.reset();
        reading.clear(); composing.clear();
        panel()->hide(); panel()->cancelEventHandler();
        std::string error;
        context.reset(GuanyinmaCreateInputContext(method, model.u8string(), user.u8string(), &config, &error));
        require(context != nullptr, std::string("open ") + method + ": " + error);
        context->startSession(&loader);
    }
    PVOneDimensionalCandidatePanel* panel() { return candidates.accessVerticalCandidatePanel(); }
    std::string visible() { return PVCombinedUTF16TextBuffer(composing, reading).composedText(); }
    void consumeCommit() {
        if (composing.isCommitted()) {
            committed += composing.composedCommittedText();
            composing.finishCommit();
        }
    }
    bool press(const OVKey& key) {
        loader.resetState();
        bool handled = true;
        auto* p = panel();
        if (p->isVisible() && p->isInControl()) {
            auto result = p->handleKeyEvent(key, &loader);
            if (result == PVCandidateState::CandidateChosen) {
                auto text = p->chosenCandidateString();
                auto index = p->chosenCandidateIndex();
                p->hide(); p->cancelEventHandler();
                handled = context->candidateSelected(&candidates, text, index, &reading, &composing, &loader);
            } else if (result == PVCandidateState::Canceled) {
                p->hide(); p->cancelEventHandler();
                context->candidateCanceled(&candidates, &reading, &composing, &loader);
            } else if (result == PVCandidateState::Ignored) {
                handled = context->candidateNonPanelKeyReceived(&candidates, &key, &reading, &composing, &loader);
            }
        } else {
            OVKey copy(key);
            handled = context->handleKey(&copy, &reading, &composing, &candidates, &loader);
        }
        consumeCommit();
        return handled;
    }
    bool key(unsigned code) { return press(loader.makeOVKey(code)); }
    void type(const std::string& keys) { for (unsigned char ch : keys) key(ch); }
    void openSmart() {
        require(reading.isEmpty(), "open candidates with completed reading");
        while (composing.cursorPosition()) key(OVKeyCode::Left);
        key(OVKeyCode::Down);
        require(panel()->isVisible(), "smart candidates visible");
    }
    size_t find(const std::string& text) {
        auto* list = panel()->candidateList();
        for (size_t i = 0; i < list->size(); ++i) if (list->candidateAtIndex(i) == text) return i;
        throw std::runtime_error("Missing candidate " + text);
    }
    void chooseIndex(size_t index) {
        auto* p = panel();
        require(p->isVisible() && index < p->candidateList()->size(), "valid selection index");
        size_t page = index / p->candidatesPerPage();
        while (p->currentPage() < page) key(OVKeyCode::PageDown);
        while (p->currentPage() > page) key(OVKeyCode::PageUp);
        press(p->candidateKeyAtIndex(index % p->candidatesPerPage()));
    }
    void choose(const std::string& text) { chooseIndex(find(text)); }
    void clear() {
        context->clear(&loader);
        reading.clear(); composing.clear();
        panel()->hide(); panel()->cancelEventHandler();
    }
};

// Use the public C ABI to prepare a user word; no arbitrary SQL or old profile.
static void addEmojiPhrase(const fs::path& model, const fs::path& user) {
    NSDictionary* configuration = @{@"method": @"smart", @"user_database": @(user.u8string().c_str())};
    NSData* json = [NSJSONSerialization dataWithJSONObject:configuration options:0 error:nil];
    GuanyinmaSession* session = nullptr;
    auto path = model.u8string();
    require(guanyinma_session_open(reinterpret_cast<const uint8_t*>(path.data()), path.size(),
                                  reinterpret_cast<const uint8_t*>(json.bytes), json.length, &session) == GUANYINMA_OK,
            "open C ABI user phrase session");
    const std::string operation = R"({"type":"add_user_phrase","qstring":"0_0_","text":"🙂事"})";
    GuanyinmaResult* result = nullptr;
    auto status = guanyinma_session_apply(session, reinterpret_cast<const uint8_t*>(operation.data()),
                                         operation.size(), &result);
    guanyinma_result_close(&result);
    guanyinma_session_close(&session);
    require(status == GUANYINMA_OK, "prepare supplementary Unicode user phrase");
}

static void testFactory(const fs::path& model, const fs::path& root) {
    for (auto method : {Smart, Traditional, Cangjie, Simplex})
        require(GuanyinmaSupportsInputMethod(method), std::string("supported ID ") + method);
    require(GuanyinmaSupportsInputMethod("OVIMSmartMandarin"), "default Smart ID alias supported");
    require(GuanyinmaSupportsInputMethod("OVIMTraditionalMandarin"), "default Traditional ID alias supported");
    require(!GuanyinmaSupportsInputMethod("OVIMUnrelated"), "unrelated input methods stay native");
    Harness h;
    std::string error;
    auto missing = root / "missing-model.db";
    std::unique_ptr<OVEventHandlingContext> result(GuanyinmaCreateInputContext(
        Smart, missing.u8string(), (root / "unused-user.db").u8string(), &h.config, &error));
    require(!result && !error.empty(), "missing model returns a diagnosed fallback");
    require(!fs::exists(missing), "opening missing model never creates it");
    const auto invalidUser = root.u8string() + "/invalid-" + std::string(1, static_cast<char>(0xff)) + ".db";
    bool threw = false;
    @try {
        result.reset(GuanyinmaCreateInputContext(Smart, model.u8string(), invalidUser, &h.config, &error));
    } @catch (NSException*) {
        threw = true;
    }
    require(!threw && !result && !error.empty(), "invalid UTF-8 user path returns diagnosed fallback without exception");
    require(!fs::exists(fs::path(invalidUser)), "invalid user path never creates a profile");
    result.reset(GuanyinmaCreateInputContext("OVIMUnrelated", model.u8string(),
                                           (root / "unrelated-user.db").u8string(), &h.config, &error));
    require(!result, "unrelated factory lookup returns no adapter");
}

// Exercise actual strings persisted by the macOS FE, Formosa's historical
// aliases, and native layout-specific selection defaults through the real ABI.
static void testNativePhoneticLayoutNames(const fs::path& model, const fs::path& root) {
    struct Case { const char* layout; const char* input; const char* keys; };
    const Case cases[] = {
        {"Standard", "5j/", "123456789"},
        {"standard", "5j/", "123456789"},
        {"ETen", ",x-", "123456789"},
        {"eTEN", ",x-", "123456789"},
        {"Hsu", "jxl", "asdfzxcv"},
        {"HSU", "jxl", "asdfzxcv"},
        {"bpmfdtnlgkhjvcjvcrzasexuyhgeiawomnklldfjs", "jxl", "asdfzxcv"},
        {"ETen26", "gxl", "asdfjkl;"},
        {"eTEN26", "gxl", "asdfjkl;"},
        {"bpmfdtnlvkhgvcgycjqwsexuaorwiqzpmntlhfjkd", "gxl", "asdfjkl;"},
        {"HanyuPinyin", "zhong", "123456789"},
        {"Hanyu Pinyin", "zhong", "123456789"},
        {"HANYU PINYIN", "zhong", "123456789"},
        {"Hanyu-Pinyin", "zhong", "123456789"},
        {"Pinyin", "zhong", "123456789"},
        {"unknown saved layout", "5j/", "123456789"},
        {"", "5j/", "123456789"},
    };
    size_t serial = 0;
    for (const char* method : {Traditional, Smart}) {
        for (const auto& item : cases) {
            Harness h;
            h.config.setKeyStringValue("KeyboardLayout", item.layout);
            h.config.setKeyStringValue("CandidateSelectionKeys", "");
            h.open(method, model, root / ("native-layout-" + std::to_string(serial++) + ".db"));
            h.type(item.input); h.key(OVKeyCode::Space);
            const bool smart = std::string(method) == Smart;
            if (smart) {
                expectText(h.visible(), "中", std::string(item.layout) + " Smart reading");
                h.openSmart();
            }
            require(h.panel()->isVisible(), std::string(item.layout) + " opens candidates");
            expectText(h.panel()->candidateList()->candidateAtIndex(0), "中",
                       std::string(item.layout) + " uses the intended native phonetic layout");
            std::string expectedKeys = item.keys;
            if (smart && expectedKeys == "123456789") expectedKeys.pop_back();
            require(h.panel()->candidatesPerPage() == expectedKeys.size(),
                    std::string(item.layout) + " empty saved selection keys use native defaults");
            for (size_t i = 0; i < expectedKeys.size(); ++i)
                require(h.panel()->candidateKeyAtIndex(i).keyCode() ==
                        static_cast<unsigned char>(expectedKeys[i]),
                        std::string(item.layout) + " panel and core share default selection keys");
            h.chooseIndex(0);
            if (smart) h.key(OVKeyCode::Return);
            expectText(h.committed, "中", std::string(item.layout) + " native selection key commits exactly once");
        }
    }
}

static void testSmart(const fs::path& model, const fs::path& root) {
    Harness h;
    h.open(Smart, model, root / "smart.db");
    h.type("su3cl3");
    expectText(h.visible(), "你好", "smart complete readings");
    require(h.reading.isEmpty(), "completed phonetics clear reading buffer");
    h.openSmart();
    auto* list = h.panel()->candidateList();
    require(list->size() > 8, "native panel receives the complete candidate list");
    expectText(list->candidateAtIndex(0), "你好", "phrase first candidate");
    h.choose("妳");
    expectText(h.visible(), "妳好", "selection changes target without committing sentence");
    require(h.committed.empty(), "smart manual choice stays in marked text");
    h.key(OVKeyCode::Return);
    expectText(h.committed, "妳好", "Return commits selected sentence once");
    expectText(h.visible(), "", "commit clears marked text");
    h.clear(); h.clear();
    h.context->stopSession(&h.loader); h.context->startSession(&h.loader);
    expectText(h.committed, "妳好", "repeated lifecycle calls cannot replay commit");
    h.type("g4");
    h.openSmart();
    require(h.panel()->candidatesPerPage() == 8, "configured eight selection keys");
    h.key(OVKeyCode::PageDown);
    require(h.panel()->currentPage() == 1, "native paging advances");
    const auto expected = h.panel()->candidateList()->candidateAtIndex(9);
    h.chooseIndex(9);
    expectText(h.visible(), expected, "absolute native selection index maps to Rust page-local index");
    h.key(OVKeyCode::Return);
    expectText(h.committed, std::string("妳好") + expected, "page selection commits exactly chosen candidate");
    h.type("su");
    require(!h.reading.isEmpty(), "unfinished reading is in native reading buffer");
    const auto pending = h.visible();
    h.clear();
    h.type("cl3");
    expectText(h.visible(), "好", "clear removes unfinished core state");
    require(!pending.empty(), "lifecycle case had visible pending text");
}

static void testSmartLearningAndLimit(const fs::path& model, const fs::path& root) {
    Harness h;
    const auto user = root / "smart-learning.db";
    h.open(Smart, model, user);
    h.type("g4"); h.openSmart(); h.choose("事");
    h.key(OVKeyCode::Return);
    h.open(Smart, model, user);
    h.type("g4");
    expectText(h.visible(), "事", "explicit smart candidate preference survives context recreation");
    h.openSmart();
    expectText(h.panel()->candidateList()->candidateAtIndex(0), "事", "learned candidate leads native list");
    h.chooseIndex(0);
    h.key(OVKeyCode::Return);
    h.open(Smart, model, user);
    h.type("g4");
    expectText(h.visible(), "是", "choosing current first candidate clears learned preference");
    h.clear();
    Harness roomy;
    roomy.config.setKeyIntValue("ComposingTextBufferSize", 20);
    roomy.open(Smart, model, root / "limit20.db");
    for (size_t i = 0; i < 12; ++i) roomy.type("g4");
    require(roomy.committed.empty() && roomy.composing.codePointCount() == 12,
            "FE composition limit 20 is passed to core");
    Harness physical;
    physical.open(Smart, model, root / "limit10.db");
    for (size_t i = 0; i < 10; ++i) physical.type("g4");
    require(physical.committed.empty() && physical.composing.codePointCount() == 10,
            "physical default retains ten completed syllables");
    physical.type("g4");
    require(!physical.committed.empty(), "eleventh completed syllable shifts a complete phrase");
}

static void testMethodsAndLearning(const fs::path& model, const fs::path& root) {
    Harness h;
    const auto user = root / "tables.db";
    h.open(Traditional, model, user);
    h.type("su3");
    require(h.panel()->isVisible(), "traditional syllable opens candidates");
    h.choose("妳");
    expectText(h.committed, "妳", "traditional selection commits");
    h.type("su3"); h.key(OVKeyCode::Esc);
    require(!h.panel()->isVisible(), "traditional cancellation closes candidates");
    expectText(h.committed, "妳", "cancellation never commits");
    h.clear();
    h.open(Cangjie, model, user);
    h.type("a"); h.key(OVKeyCode::Space);
    expectText(h.panel()->candidateList()->candidateAtIndex(0), "日", "fresh Cangjie order");
    h.choose("曰");
    expectText(h.committed, "妳曰", "Cangjie native candidate commits");
    h.open(Cangjie, model, user);
    h.type("a"); h.key(OVKeyCode::Space);
    expectText(h.panel()->candidateList()->candidateAtIndex(0), "曰", "selection learning survives context recreation");
    h.clear();
    h.open(Simplex, model, user);
    h.type("ab");
    if (!h.panel()->isVisible()) h.key(OVKeyCode::Space);
    require(h.panel()->isVisible(), "Simplex maximum code queries candidates");
    require(h.find("明") < h.panel()->candidateList()->size(), "Simplex common candidate");
    h.choose("明");
    expectText(h.committed, "妳曰明", "switching methods retains previous host text");
    h.open(Cangjie, model, root / "learning-off.db");
    h.config.setKeyBoolValue("UseDynamicFrequency", false);
    h.open(Cangjie, model, root / "learning-off.db");
    h.type("a"); h.key(OVKeyCode::Space); h.choose("曰");
    h.open(Cangjie, model, root / "learning-off.db");
    h.type("a"); h.key(OVKeyCode::Space);
    expectText(h.panel()->candidateList()->candidateAtIndex(0), "日", "disabled learning preserves model order");
}

static void testKeyNormalization(const fs::path& model, const fs::path& root) {
    Harness h;
    h.open(Smart, model, root / "keys.db");
    h.type("su3");
    // OVKey's legacy NumLock flag is populated by the controller only for real keypad virtual codes.
    h.press(h.loader.makeOVKey('2', false, false, false, false, false, false, true));
    expectText(h.committed, "你2", "real keypad commits composition then literal digit");
    expectText(h.visible(), "", "keypad does not begin another phonetic reading");
    h.type("su3");
    h.openSmart();
    auto expected = h.panel()->candidateList()->candidateAtIndex(1);
    h.key('2');
    expectText(h.visible(), expected, "main keyboard digit remains a candidate selection key");
    h.clear();
    h.press(h.loader.makeOVKey("🙂"));
    expectText(h.committed, "你2🙂", "translated supplementary Unicode scalar reaches host intact");
    h.press(OVKey(new PVKeyImpl("Ａ", 'a', OVKeyMask::DirectText)));
    expectText(h.committed, "你2🙂Ａ", "direct fullwidth text is not interpreted as a letter code");
    h.type("su3");
    auto before = h.visible();
    require(h.press(h.loader.makeOVKey('a', false, false, false, false, true)) && h.loader.shouldBeep(),
            "Command shortcut with marked text follows Manjusri protected-composition behavior");
    expectText(h.visible(), before, "host shortcut preserves current composition");
    h.clear();
    require(!h.press(h.loader.makeOVKey('a', false, false, false, false, true)),
            "Command shortcut with no marked text remains available to host");
}

static void testUnicodeCoordinates(const fs::path& model, const fs::path& root) {
    const auto user = root / "Unicode 使用者.db";
    addEmojiPhrase(model, user);
    Harness h;
    h.open(Smart, model, user);
    h.type("g4g4");
    expectText(h.visible(), "🙂事", "adapter reads prepared user phrase");
    PVCombinedUTF16TextBuffer end(h.composing, h.reading);
    require(end.cursorPosition() == 2 && end.wideCursorPosition() == 3,
            "native text separates scalar and UTF-16 cursor coordinates");
    h.key(OVKeyCode::Left);
    PVCombinedUTF16TextBuffer middle(h.composing, h.reading);
    require(middle.cursorPosition() == 1 && middle.wideCursorPosition() == 2,
            "cursor steps over supplementary character as one scalar");
    h.type("s");
    PVCombinedUTF16TextBuffer partial(h.composing, h.reading);
    expectText(partial.composedText(), "🙂ㄋ事", "unfinished reading inserts at native caret");
    require(partial.cursorPosition() == 2 && partial.wideCursorPosition() == 3,
            "reading caret maps to UTF-16 after supplementary character");
    require(h.context->handleDirectText("Ａ", &h.reading, &h.composing, &h.candidates, &h.loader),
            "direct text finishes the visible marked text");
    h.consumeCommit();
    expectText(h.visible(), "是Ａ是", "native direct text discards unfinished reading and re-walks the split phrase");
    expectText(h.committed, "", "direct text keeps an existing smart graph editable");
    h.key(OVKeyCode::Return);
    expectText(h.committed, "是Ａ是", "direct text and existing graph commit exactly once");
}

static void testUserDataAdministration(const fs::path& model, const fs::path& root) {
    const auto user = root / "admin 使用者.db";
    GuanyinmaMacUserData admin(model.u8string(), user.u8string());
    require(admin.valid(), "explicit Guanyinma administration store opens");
    require([admin.phrases() count] == 0, "fresh administration store has no custom words");
    Harness h;
    h.open(Smart, model, user);
    require(admin.apply(@{@"type": @"add_user_phrase", @"qstring": @"0_0_", @"text": @"士事"}),
            "administration adds custom word through C ABI");
    require([admin.phrases() count] == 1, "administration reads added custom word");
    h.type("g4g4");
    expectText(h.visible(), "士事", "active native session observes administration addition");
    h.clear();
    require(admin.apply(@{@"type": @"update_user_phrase", @"qstring": @"0_0_", @"text": @"士事",
                          @"new_qstring": @"0_0_", @"new_text": @"事士"}),
            "administration edits word atomically");
    require(!admin.apply(@{@"type": @"update_user_phrase", @"qstring": @"0_0_", @"text": @"事士",
                           @"new_qstring": @"invalid", @"new_text": @"失敗"}),
            "invalid administration edit is rejected");
    require([[[admin.phrases() objectAtIndex:0] objectForKey:@"current"] isEqualToString:@"事士"],
            "failed edit retains previous custom word");
    h.type("g4g4");
    expectText(h.visible(), "事士", "active native session observes edited custom word");
    h.clear();
    h.type("g4"); h.openSmart(); h.choose("事"); h.key(OVKeyCode::Return);
    require([[admin.data() objectForKey:@"overrides"] count] == 1,
            "administration reads selection learned by existing native session");
    require(admin.apply(@{@"type": @"reset_learning"}), "administration resets learning");
    require([admin.phrases() count] == 1 && [[admin.data() objectForKey:@"overrides"] count] == 0,
            "learning reset preserves custom words");
    h.type("g4");
    expectText(h.visible(), "是", "active native session observes reset without reviving old preference");
    h.clear();
    require(admin.apply(@{@"type": @"remove_user_phrase", @"qstring": @"0_0_", @"text": @"事士"}),
            "administration removes custom word");
    require([admin.phrases() count] == 0, "removed word disappears from administration snapshot");
    GuanyinmaMacUserData invalid(model.u8string(), model.u8string());
    require(!invalid.valid() && !invalid.apply(@{@"type": @"reset_learning"}),
            "administration refuses model as writable user store");
}

class TemporaryLoaderPolicy : public PVLoaderPolicy {
    fs::path root;
public:
    explicit TemporaryLoaderPolicy(const fs::path& directory) : PVLoaderPolicy({}), root(directory) {}
    const std::string propertyListPathForLoader() override { return (root / "loader.plist").u8string(); }
    const std::string propertyListPathFromIdentifier(const std::string&) override {
        return (root / "module.plist").u8string();
    }
    const OVPathInfo modulePackagePathInfoFromPath(const std::string&) override {
        OVPathInfo result; result.loadedPath = result.resourcePath = result.writablePath = root.u8string();
        return result;
    }
};
// Inject only the isolated sandwich, retaining the real PV key/candidate/filter implementation.
class IsolatedPipelineContext : public PVLoaderContext {
public:
    IsolatedPipelineContext(PVLoader* loader, OVEventHandlingContext* input, bool filters = true) : PVLoaderContext(loader) {
        m_sandwich = new PVContextSandwich;
        m_sandwich->inputMethods.push_back(input);
        if (filters) {
            m_sandwich->outputFilters.push_back(new OVOFTC2SCContext);
            m_sandwich->outputFilters.push_back(new OVOFFullWidthCharacterContext);
        }
        m_sandwich->prepareShortcutContexts();
        m_sandwich->startAllContexts(loader->loaderService());
    }
    bool dispatch(OVKey* key) {
        GuanyinmaPrepareCandidatePanelForKey(key, candidateService());
        return handleKeyEvent(key);
    }
protected:
    bool shouldEnter(OVLoaderService*, bool = false, bool = false) override { return true; }
};
static void testOwnedNativePreferences(const fs::path& model, const fs::path& root) {
    Harness h;
    std::unique_ptr<OVModulePackage> package(GuanyinmaCreateModulePackage(
        model.u8string(), (root / "owned-settings.db").u8string()));
    std::unique_ptr<OVModule> module(package->moduleAtIndex(1, &h.loader));
    OVPathInfo paths; paths.writablePath = root.u8string();
    require(module->moduleInitialize(&paths, &h.loader), "owned preference module initializes");
    auto loadDetached = [&](int limit, const std::string& encoding) {
        std::unique_ptr<PVPlistValue> dictionary(new PVPlistValue(PVPlistValue::Dictionary));
        dictionary->setKeyValue("KeyboardLayout", "Standard");
        dictionary->setKeyValue("ComposingTextBufferSize", std::to_string(limit));
        dictionary->setKeyValue("CandidateSelectionKeys", "12345678");
        dictionary->setKeyValue("UseCharactersSupportedByEncoding", encoding);
        auto borrowed = dictionary->readOnlyKeyValueMap();
        module->loadConfig(&borrowed, &h.loader);
        dictionary.reset(); // Native plist reload destroys this backing storage.
    };
    loadDetached(20, "");
    h.context.reset(module->createContext());
    require(h.context != nullptr, "copied native settings create Rust context");
    h.context->startSession(&h.loader);
    for (size_t i = 0; i < 12; ++i) h.type("g4");
    require(h.committed.empty() && h.composing.codePointCount() == 12,
            "owned plist snapshot survives original dictionary destruction");
    loadDetached(10, "");
    h.clear();
    for (size_t i = 0; i < 11; ++i) h.type("g4");
    require(!h.committed.empty(), "existing context refreshes replaced owned plist after clear");
    h.clear();
    loadDetached(9, "");
    h.type("s");
    require(h.loader.shouldBeep(), "unsupported pending setting is reported once");
    h.type("u");
    require(!h.loader.shouldBeep(), "unsupported pending setting is not a repeated keystroke error");
    h.clear();
    h.context.reset();
    std::unique_ptr<OVEventHandlingContext> rejected(module->createContext());
    h.loader.resetState();
    rejected->startSession(&h.loader);
    require(h.loader.shouldBeep() && !h.loader.notifyMessage().empty(),
            "unsupported setting explicitly reports Rust context initialization failure");
    auto key = h.loader.makeOVKey('s');
    require(rejected->handleKey(&key, &h.reading, &h.composing, &h.candidates, &h.loader) &&
            h.visible().empty() && !h.composing.isCommitted(),
            "failed context never substitutes literal text or another input core");
    rejected.reset();
    loadDetached(10, "");
    h.context.reset(module->createContext());
    require(h.context != nullptr, "supported configuration creates a fresh Rust context");
    h.context.reset();
    module->finalize();
    module.reset();
    package->finalize();
    package->finalize();
    require(package->numberOfModules(&h.loader) == 0, "repeated package finalize is safe and retires the standalone package");
}

// Changing a native font/encoding choice installs a fresh policy only after
// old composition is preserved/cleared. Its old callback context must remain
// alive through the old session close and the new graph/cache must not leak it.
class PreferenceEncodingService : public PVDefaultEncodingService {
public:
    size_t systemCalls = 0, encodingCalls = 0;
    bool codepointSupportedBySystem(const std::string& value) override {
        ++systemCalls;
        return value != "事";
    }
    bool codepointSupportedByEncoding(const std::string& value, const std::string& encoding) override {
        ++encodingCalls;
        return encoding == "UTF-8" || value != "士";
    }
};

static void testNativeFilterPreferenceRefresh(const fs::path& model, const fs::path& root) {
    PreferenceEncodingService encoding;
    Harness h(&encoding);
    std::unique_ptr<OVModulePackage> package(GuanyinmaCreateModulePackage(
        model.u8string(), (root / "filter-preferences.db").u8string()));
    std::unique_ptr<OVModule> module(package->moduleAtIndex(1, &h.loader));
    OVPathInfo paths; paths.writablePath = root.u8string();
    require(module->moduleInitialize(&paths, &h.loader), "filter preference module initializes");
    module->loadConfig(&h.config, &h.loader);
    h.context.reset(module->createContext());
    require(h.context != nullptr, "filter preference begins in Rust");
    h.context->startSession(&h.loader);
    auto contains = [&](const std::string& text) {
        auto* list = h.panel()->candidateList();
        for (size_t i = 0; i < list->size(); ++i)
            if (list->candidateAtIndex(i) == text) return true;
        return false;
    };
    h.type("g4"); h.openSmart();
    require(encoding.systemCalls > 0 && !contains("事") && contains("士"),
            "empty native encoding delegates to system font service");
    h.config.setKeyStringValue("UseCharactersSupportedByEncoding", "UTF-8");
    module->loadConfig(&h.config, &h.loader);
    h.key(OVKeyCode::Esc);
    h.type("g4");
    require(h.visible().find("事") == std::string::npos && encoding.encodingCalls == 0,
            "new encoding is deferred while old composition and graph remain");
    h.clear();
    h.type("g4"); h.openSmart();
    require(encoding.encodingCalls > 0 && contains("事") && contains("士"),
            "safe empty boundary installs UTF-8 callback with a new graph cache");
    h.config.setKeyStringValue("UseCharactersSupportedByEncoding", "BIG-5");
    module->loadConfig(&h.config, &h.loader);
    h.clear();
    h.type("g4"); h.openSmart();
    require(contains("事") && !contains("士"),
            "valid BIG-5 policy is supported directly by Rust native adapter");
    h.config.setKeyStringValue("UseCharactersSupportedByEncoding", "");
    module->loadConfig(&h.config, &h.loader);
    h.clear();
    h.type("g4"); h.openSmart();
    require(!contains("事") && contains("士"),
            "returning to system policy releases old encoding policy and cache");
    h.clear();
    h.context.reset();
    module->finalize();
    module.reset();
    package->finalize();
}

static void testNormalizedNativeEncodings(const fs::path& model, const fs::path& root) {
    size_t serial = 0;
    for (const char* value : {"false", "BIG5", "unknown encoding"}) {
        for (const char* method : {Traditional, Smart}) {
            PreferenceEncodingService encoding;
            Harness h(&encoding);
            h.config.setKeyStringValue("UseCharactersSupportedByEncoding", value);
            h.open(method, model, root / ("normalized-encoding-" + std::to_string(serial++) + ".db"));
            h.type("g4");
            if (std::string(method) == Smart) h.openSmart();
            require(encoding.systemCalls > 0 && encoding.encodingCalls == 0,
                    "unknown native encoding uses system font policy");
            require(h.panel()->isVisible(), "normalizing a native encoding keeps a working Rust context");
            auto* list = h.panel()->candidateList();
            for (size_t i = 0; i < list->size(); ++i)
                require(list->candidateAtIndex(i) != "事", "normalized font policy filters candidates");
        }
    }
}

static void testNativeShiftAndDirectText(const fs::path& model, const fs::path& root) {
    size_t serial = 0;
    for (const char* method : {Traditional, Smart, Cangjie, Simplex}) {
        const unsigned modifierCases[] = {OVKeyMask::Shift, OVKeyMask::CapsLock,
                                          OVKeyMask::CapsLock | OVKeyMask::Shift};
        for (unsigned modifiers : modifierCases) {
            Harness h;
            h.open(method, model, root / ("native-case-" + std::to_string(serial++) + ".db"));
            h.press(OVKey(new PVKeyImpl('A', modifiers)));
            expectText(h.committed, modifiers == (OVKeyMask::CapsLock | OVKeyMask::Shift) ? "A" : "a",
                       "macOS translates native Caps/Shift text before the core");
        }
        Harness h;
        h.open(method, model, root / ("native-shift-space-" + std::to_string(serial++) + ".db"));
        const bool spaceHandled = h.press(h.loader.makeOVKey(OVKeyCode::Space, false, false, false, true));
        const std::string prefix = std::string(method) == Smart ? "" : " ";
        require(spaceHandled == (std::string(method) != Smart),
                "macOS Shift+Space preserves native empty-Space ownership");
        expectText(h.committed, prefix, "macOS Shift+Space remains a Space event");
        h.press(OVKey(new PVKeyImpl("Ａ", 'a', OVKeyMask::DirectText)));
        expectText(h.committed, prefix + "Ａ", "a direct-text key keeps the literal width unchanged");
        h.type(std::string(method) == Cangjie || std::string(method) == Simplex ? "h" : "s");
        require(!h.visible().empty(), "unfinished input exists before direct text");
        h.press(OVKey(new PVKeyImpl("字", 'a', OVKeyMask::DirectText)));
        expectText(h.committed, prefix + "Ａ字", "direct text replaces unfinished phonetic/code input without leaking it");
        expectText(h.visible(), "", "direct text clears replaced unfinished input");
    }
    Harness uppercase;
    uppercase.config.setKeyBoolValue("ShiftKeyAlwaysCommitUppercaseCharacters", true);
    uppercase.open(Smart, model, root / "native-force-uppercase.db");
    uppercase.press(OVKey(new PVKeyImpl('A', OVKeyMask::Shift)));
    expectText(uppercase.committed, "A", "native Smart Shift-uppercase setting reaches the core");
    Harness caps;
    caps.open(Smart, model, root / "native-caps-control.db");
    require(!caps.press(OVKey(new PVKeyImpl('1', OVKeyMask::Ctrl | OVKeyMask::CapsLock))) &&
            !caps.loader.shouldBeep(), "Caps Lock Ctrl punctuation stays with the host on empty Smart input");
    caps.type("s");
    const auto before = caps.visible();
    require(caps.press(OVKey(new PVKeyImpl(',', OVKeyMask::Ctrl | OVKeyMask::CapsLock))) &&
            caps.loader.shouldBeep(), "Caps Lock Ctrl punctuation protects existing Smart input");
    expectText(caps.visible(), before, "rejected Caps Lock chord preserves the unfinished reading");
}

static void testNativePhraseMarking(const fs::path& model, const fs::path& root) {
    size_t serial = 0;
    for (const char* locale : {"zh_TW", "zh_CN", "en"}) {
        Harness h(nullptr, locale);
        const auto user = root / ("native-mark-" + std::to_string(serial++) + ".db");
        h.open(Smart, model, user);
        h.type("g4"); h.openSmart(); h.choose("示"); h.key(OVKeyCode::End);
        h.type("g4"); h.key(OVKeyCode::Left); h.key(OVKeyCode::Down); h.choose("士");
        expectText(h.visible(), "示士", "marking begins with explicitly chosen text");
        h.key(OVKeyCode::End);
        h.press(h.loader.makeOVKey(OVKeyCode::Home, false, false, false, true));
        require(h.composing.highlightMark() == OVTextBuffer::RangePair(0, 2),
                "native mark uses scalar text coordinates");
        require(h.composing.toolTipText().find("示士") != std::string::npos &&
                h.composing.toolTipText().find("ENTER") != std::string::npos,
                "marked phrase has localized native tooltip");
        h.key(OVKeyCode::Return);
        expectText(h.visible(), "示士", "adding marked phrase preserves editable composition");
        require(h.committed.empty() && h.composing.highlightMark().second == 0,
                "adding a marked phrase neither commits nor leaves stale highlight");
        const std::string success = std::string(locale) == "zh_TW" ? "加入新詞" :
            std::string(locale) == "zh_CN" ? "加入新词" : "New phrase";
        require(h.composing.toolTipText().find(success) != std::string::npos,
                "phrase-added result is shown in the frontend locale");
        GuanyinmaMacUserData data(model.u8string(), user.u8string());
        require([data.phrases() count] == 1, "marked phrase is saved through Guanyinma user-data transaction");
        h.key(OVKeyCode::End);
        h.press(h.loader.makeOVKey(OVKeyCode::Home, false, false, false, true));
        h.key(OVKeyCode::Return);
        const std::string duplicate = std::string(locale) == "zh_TW" ? "無法加入" :
            std::string(locale) == "zh_CN" ? "无法加入" : "Cannot add";
        require(h.composing.toolTipText().find(duplicate) != std::string::npos &&
                [data.phrases() count] == 1, "duplicate marking has feedback without duplicate rows");
    }
}

static void testNativeCapsSpecialClassification(const fs::path& model, const fs::path& root) {
    size_t serial = 0;
    for (const char* method : {Traditional, Cangjie, Simplex}) {
        for (unsigned key : {OVKeyCode::Backspace, OVKeyCode::Return, OVKeyCode::Esc,
                             OVKeyCode::Left, OVKeyCode::Right}) {
            Harness h;
            h.config.setKeyBoolValue("ShouldCommitAtMaximumRadicalLength", false);
            h.open(method, model, root / ("native-caps-special-" + std::to_string(serial++) + ".db"));
            require(!h.press(OVKey(new PVKeyImpl(key, OVKeyMask::CapsLock))),
                    "empty Caps special remains unhandled for the host");
            h.type(std::string(method) == Traditional ? "su" : "hk");
            require(h.press(OVKey(new PVKeyImpl(key, OVKeyMask::CapsLock))),
                    "occupied Caps special is classified by the native frontend");
            expectText(h.visible(), "", "native Caps special clears the unfinished sequence");
            expectText(h.committed, std::string(method) == Traditional ?
                std::string(1, static_cast<char>(key)) : std::string(),
                "Traditional raw key-byte compatibility stays in FE; table methods only reset");
        }
    }
}

static void testNativeCangjiePreferenceDefault(const fs::path& model, const fs::path& root) {
    Harness h;
    h.config.setKeyStringValue("UseOverrideTable", "Punctuations-punctuations-cin");
    std::string error;
    require(GuanyinmaCanUseInputMethod(Cangjie, &h.config, &error) && error.empty(),
            "the actual Cangjie UI default is accepted by Rust");
    h.open(Cangjie, model, root / "native-cangjie-ui-default.db");
    h.type("a"); h.key(OVKeyCode::Space); h.choose("日");
    expectText(h.committed, "日", "known missing legacy override uses the original Cangjie table");
}

static void testFrontendModeSynchronization(const fs::path& model, const fs::path& root) {
    size_t serial = 0;
    for (const char* method : {Traditional, Smart, Cangjie, Simplex}) {
        Harness h;
        h.open(method, model, root / ("native-mode-" + std::to_string(serial++) + ".db"));
        h.type("s");
        const auto visible = h.visible();
        require(!visible.empty(), "mode synchronization test owns unfinished input");
        std::string error;
        require(GuanyinmaSetEnglishModeForService(&h.candidates, false, &error) && error.empty(),
                "reasserting current Chinese mode preserves unfinished input");
        require(!GuanyinmaSetEnglishModeForService(&h.candidates, true, &error) && !error.empty(),
                "mode helper refuses nonempty state before FE preservation");
        expectText(h.visible(), visible, "failed mode synchronization preserves visible input");
        require(h.committed.empty(), "failed mode synchronization produces no host commit");
        h.clear();
        require(GuanyinmaSetEnglishModeForService(&h.candidates, true, &error) && error.empty(),
                "FE mode decision reaches empty owning session after clear");
        require(GuanyinmaSetEnglishModeForService(&h.candidates, true, &error),
                "repeating set-English is idempotent");
        require(h.committed.empty(), "mode helper never replays preserved text");
        h.type("s");
        expectText(h.committed, "s", "owning core session now follows English behavior");
        require(GuanyinmaSetEnglishModeForService(&h.candidates, false, &error),
                "FE can explicitly restore Chinese without a toggle race");
        h.type("s");
        require(!h.visible().empty(), "Chinese input resumes after semantic set");
        PVCandidateService foreign(&h.loader);
        require(GuanyinmaSetEnglishModeForService(&foreign, true, &error),
                "foreign/native candidate service is a successful no-op");
        h.clear();
        h.context->stopSession(&h.loader);
        require(GuanyinmaSetEnglishModeForService(&h.candidates, true, &error),
                "inactive session is not changed through a reused native service");
        h.context->startSession(&h.loader);
        h.type("s");
        require(!h.visible().empty(), "inactive-context no-op retains its Chinese state");
        h.clear();
    }
}

static void testNativePipeline(const fs::path& model, const fs::path& root) {
    const auto isolated = root / "native-pipeline";
    fs::create_directory(isolated);
    TemporaryLoaderPolicy policy(isolated);
    Harness factory;
    PVLoader loader(&policy, &factory.loader, {});
    std::string error;
    auto* adapter = GuanyinmaCreateInputContext(Traditional, model.u8string(),
        (isolated / "users.db").u8string(), &factory.config, &error);
    require(adapter != nullptr, "native pipeline adapter opens: " + error);
    IsolatedPipelineContext context(&loader, adapter);
    auto send = [&](unsigned code) {
        auto key = factory.loader.makeOVKey(code);
        return context.dispatch(&key);
    };
    for (char ch : std::string("su3")) require(send(ch), "PV pipeline handles traditional phonetic key");
    auto* panel = context.candidateService()->accessVerticalCandidatePanel();
    require(panel->isInControl() && panel->isVisible(), "real PV pipeline grants candidate focus");
    size_t index = 0;
    while (index < panel->candidateList()->size() &&
           panel->candidateList()->candidateAtIndex(index) != "擬") ++index;
    require(index < panel->candidatesPerPage(), "pipeline selection target on current page");
    auto selection = panel->candidateKeyAtIndex(index);
    require(context.dispatch(&selection), "PV pipeline dispatches actual candidateChosen callback");
    require(!panel->isInControl() && !panel->isVisible() && panel->candidateList()->size() == 0,
            "PV candidateChosen path resets native panel after adapter callback");
    require(context.composingText()->isCommitted(), "candidateChosen keeps commit available to native host");
    expectText(context.composingText()->composedCommittedText(), "拟",
               "real traditional-to-simplified output filter runs on adapter candidate commit");
    context.composingText()->finishCommit();
    auto direct = factory.loader.makeOVKey("A");
    require(context.dispatch(&direct), "PV pipeline handles literal text");
    expectText(context.composingText()->composedCommittedText(), "Ａ",
               "real fullwidth output filter runs after adapter literal commit");
    context.composingText()->finishCommit();
    context.clear();
    require(context.composingText()->isEmpty() && context.readingText()->isEmpty() &&
            !context.composingText()->isCommitted(), "real PV clear removes native/core transaction state");
}

static void testNativeCandidateKeypad(const fs::path& model, const fs::path& root) {
    for (auto method : {Smart, Traditional, Cangjie, Simplex}) {
        const auto isolated = root / (std::string("keypad-") + method);
        fs::create_directory(isolated);
        const auto user = isolated / "users.db";
        TemporaryLoaderPolicy policy(isolated);
        Harness factory;
        PVLoader loader(&policy, &factory.loader, {});
        std::string error;
        auto* adapter = GuanyinmaCreateInputContext(method, model.u8string(), user.u8string(),
                                                    &factory.config, &error);
        require(adapter != nullptr, std::string("keypad pipeline opens ") + method + ": " + error);
        IsolatedPipelineContext context(&loader, adapter, false);
        auto send = [&](unsigned code) {
            auto key = factory.loader.makeOVKey(code);
            return context.dispatch(&key);
        };
        auto open = [&] {
            std::string code = (method == Smart ? "g4" :
                method == Traditional ? "su3" : method == Cangjie ? "a" : "ab");
            for (char ch : code) send(ch);
            if (method == Smart) { send(OVKeyCode::Left); send(OVKeyCode::Down); }
            if (method == Cangjie) send(OVKeyCode::Space);
            auto* panel = context.candidateService()->accessVerticalCandidatePanel();
            require(panel->isVisible() && panel->isInControl(), std::string(method) + " opens native panel");
            return panel;
        };
        auto* panel = open();
        const auto visible = PVCombinedUTF16TextBuffer(*context.composingText(), *context.readingText()).composedText();
        auto keypad = factory.loader.makeOVKey('1', false, false, false, false, false, false, true);
        require(GuanyinmaPrepareCandidatePanelForKey(&keypad, context.candidateService()),
                std::string(method) + " releases owned candidate handler for real keypad");
        require(context.handleKeyEvent(&keypad), std::string(method) + " dispatches literal keypad through real PV");
        expectText(context.composingText()->composedCommittedText(), visible + "1",
                   std::string(method) + " keypad commits exact visible text plus literal digit");
        require(!panel->isVisible() && !panel->isInControl(), "keypad leaves native candidate control");
        GuanyinmaMacUserData admin(model.u8string(), user.u8string());
        auto data = admin.data();
        require([[data objectForKey:@"overrides"] count] == 0 &&
                [[data objectForKey:@"bigrams"] count] == 0 && [[data objectForKey:@"table"] count] == 0,
                std::string(method) + " keypad creates no selection learning");
        context.composingText()->finishCommit();
        context.clear();
        panel = open();
        const auto chosen = panel->candidateList()->candidateAtIndex(0);
        auto main = factory.loader.makeOVKey('1');
        require(!GuanyinmaPrepareCandidatePanelForKey(&main, context.candidateService()) &&
                panel->isInControl(), "main keyboard selection key keeps native handler");
        require(context.dispatch(&main), "real PV dispatches main keyboard selection");
        if (method == Smart) {
            expectText(context.composingText()->composedText(), chosen, "smart main key chooses candidate");
            send(OVKeyCode::Return);
        }
        expectText(context.composingText()->composedCommittedText(), chosen,
                   std::string(method) + " main keyboard commits selected candidate");
        context.composingText()->finishCommit();
        context.clear();
    }

    // The same service can later show associated-phrase/around-filter panels.
    const auto isolated = root / "keypad-owner";
    fs::create_directory(isolated);
    TemporaryLoaderPolicy policy(isolated);
    Harness factory;
    PVLoader loader(&policy, &factory.loader, {});
    std::string error;
    auto* adapter = GuanyinmaCreateInputContext(Smart, model.u8string(),
        (isolated / "users.db").u8string(), &factory.config, &error);
    require(adapter != nullptr, "panel ownership adapter opens");
    IsolatedPipelineContext context(&loader, adapter, false);
    auto send = [&](unsigned code) {
        auto key = factory.loader.makeOVKey(code); return context.dispatch(&key);
    };
    send('g'); send('4'); send(OVKeyCode::Left); send(OVKeyCode::Down);
    auto* service = context.candidateService();
    auto* own = service->accessVerticalCandidatePanel();
    require(own->isInControl() && own->isVisible(), "ownership test has Rust panel");
    const auto ownCount = own->candidateList()->size();
    for (unsigned modifier : {OVKeyMask::Ctrl, OVKeyMask::Alt, OVKeyMask::Opt, OVKeyMask::Command}) {
        OVKey modified(new PVKeyImpl('1', OVKeyMask::NumLock | modifier));
        require(!GuanyinmaPrepareCandidatePanelForKey(&modified, service) &&
                own->isVisible() && own->isInControl() && own->candidateList()->size() == ownCount,
                "modified keypad shortcut does not release Rust candidate control");
    }
    auto keypad = factory.loader.makeOVKey('1', false, false, false, false, false, false, true);
    PVCandidateService unrelated(&factory.loader);
    unrelated.useVerticalCandidatePanel();
    auto* external = unrelated.accessVerticalCandidatePanel();
    external->candidateList()->setCandidates({"foreign"});
    external->show(); external->yieldToCandidateEventHandler();
    require(!GuanyinmaPrepareCandidatePanelForKey(&keypad, &unrelated) &&
            external->isVisible() && external->isInControl() &&
            external->candidateList()->candidateAtIndex(0) == "foreign",
            "non-Rust service candidate panel is unaffected");
    service->useHorizontalCandidatePanel();
    auto* other = service->accessHorizontalCandidatePanel();
    other->candidateList()->setCandidates({"around-filter"});
    other->show(); other->yieldToCandidateEventHandler();
    require(!GuanyinmaPrepareCandidatePanelForKey(&keypad, service) &&
            service->lastUsedPanel() == other && own->isVisible() && own->isInControl() &&
            other->isVisible() && other->isInControl(),
            "another active panel retains its owner and Rust panel state");
    service->useVerticalCandidatePanel();
    own->candidateList()->setCandidates({"replacement"});
    require(!GuanyinmaPrepareCandidatePanelForKey(&keypad, service) &&
            own->isVisible() && own->isInControl() && own->candidateList()->candidateAtIndex(0) == "replacement",
            "foreign candidate list on shared native panel is unaffected");
    context.clear();
}

int main(int argc, char** argv) {
    @autoreleasepool {
        try {
            require(argc == 3, "usage: GuanyinmaMacAdapterTests MODEL TEMP_PROFILE_DIRECTORY");
            const fs::path model = argv[1], root = argv[2];
            require(fs::is_directory(root), "test profile directory must exist");
            testFactory(model, root);
            testNativePhoneticLayoutNames(model, root);
            testSmart(model, root);
            testSmartLearningAndLimit(model, root);
            testMethodsAndLearning(model, root);
            testKeyNormalization(model, root);
            testUnicodeCoordinates(model, root);
            testUserDataAdministration(model, root);
            testNativePipeline(model, root);
            testOwnedNativePreferences(model, root);
            testNativeFilterPreferenceRefresh(model, root);
            testNormalizedNativeEncodings(model, root);
            testNativeShiftAndDirectText(model, root);
            testNativePhraseMarking(model, root);
            testFrontendModeSynchronization(model, root);
            testNativeCangjiePreferenceDefault(model, root);
            testNativeCapsSpecialClassification(model, root);
            testNativeCandidateKeypad(model, root);
            std::cout << "Guanyinma macOS adapter: " << checks << " checks passed.\n";
            return 0;
        } catch (const std::exception& error) {
            std::cerr << "Guanyinma macOS adapter test failed: " << error.what() << '\n';
            return 1;
        }
    }
}
