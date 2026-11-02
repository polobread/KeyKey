// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
// Manual migration source oracle, independent of frozen baseline files.
#import <Foundation/Foundation.h>
#include "GuanyinmaMacAdapter.h"
#include "GuanyinmaMacUserData.h"
#include "OVIMSmartMandarin.h"
#include "OVIMTraditionalMandarin.h"
#include "OVIMGeneric.h"
#include "PVBasicKeyValueMapImpl.h"
#include "PVLoaderService.h"
#include "PVCandidate.h"
#include "PVTextBuffer.h"
#include <filesystem>
#include <functional>
#include <iostream>
#include <memory>
#include <stdexcept>
using namespace OpenVanilla;
namespace fs = std::filesystem;
static size_t checks, serial;
static void require(bool value, const std::string& message) {
    ++checks; if (!value) throw std::runtime_error(message);
}
static const char* Smart = "SmartMandarin";
static const char* Traditional = "TraditionalMandarin";
static const char* Cangjie = "Generic-cj-cin";
static const char* Simplex = "Generic-simplex-cin";
class ReadOnlyModel : public OVSQLiteConnection {
    ReadOnlyModel(sqlite3* value, const std::string& path) : OVSQLiteConnection(value, path) {}
public:
    static std::unique_ptr<OVSQLiteConnection> open(const fs::path& model) {
        auto path = fs::absolute(model).u8string();
        NSString* uri = [[[NSURL fileURLWithPath:[NSString stringWithUTF8String:path.c_str()]]
            absoluteString] stringByAppendingString:@"?mode=ro"];
        sqlite3* handle = nullptr;
        require(sqlite3_open_v2(uri.UTF8String, &handle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_URI, nullptr) == SQLITE_OK,
            "native read-only model / writable separate attachment");
        require(sqlite3_db_readonly(handle, "main") == 1, "native main is read-only");
        return std::unique_ptr<OVSQLiteConnection>(new ReadOnlyModel(handle, path));
    }
};
class PreparedSmart : public OVIMSmartMandarin {
public:
    bool addPhrase(const std::string& query, const std::string& text) {
        return m_LM->addUserUnigram(query, text);
    }
};
using Configure = std::function<void(OVKeyValueMap&)>;
class Harness {
    std::unique_ptr<OVSQLiteConnection> connection;
    std::unique_ptr<OVSQLiteDatabaseService> database;
    std::unique_ptr<OVModule> module;
public:
    PVBasicKeyValueMapImpl values;
    OVKeyValueMap config;
    PVLoaderService loader;
    PVCandidateService candidates;
    PVTextBuffer reading, composing;
    std::unique_ptr<OVEventHandlingContext> context;
    std::string committed;
    bool rust;
    fs::path modelPath, userPath;
    Harness(bool useRust, const char* method, const fs::path& model, const fs::path& root,
            const Configure& configure = {})
        : connection(ReadOnlyModel::open(model)),
          database(OVSQLiteDatabaseService::ServiceWithExistingConnection(connection.get(), false)),
          config(&values), loader("zh_TW", nullptr, database.get()), candidates(&loader), rust(useRust) {
        const auto profile = root / ("native-oracle-" + std::to_string(serial++));
        fs::create_directory(profile);
        modelPath = model; userPath = profile / "GuanyinmaUserData.db";
        config.setKeyStringValue("KeyboardLayout", "Standard");
        config.setKeyStringValue("CandidateSelectionKeys", "");
        config.setKeyStringValue("UseCharactersSupportedByEncoding", "");
        config.setKeyBoolValue("UseDynamicFrequency", false);
        config.setKeyBoolValue("ComposeWhileTyping", false);
        config.setKeyBoolValue("PrefixCandidates", false);
        config.setKeyBoolValue("ClearReadingBufferAtCompositionError", true);
        config.setKeyBoolValue("ShowCandidateListWithSpace", true);
        config.setKeyBoolValue("ClearComposingTextWithEsc", false);
        config.setKeyIntValue("ComposingTextBufferSize", 10);
        if (configure) configure(config);
        if (rust) {
            std::string error;
            context.reset(GuanyinmaCreateInputContext(method, model.u8string(),
                (profile / "GuanyinmaUserData.db").u8string(), &config, &error));
            require(context != nullptr, "Rust oracle context: " + error);
        } else {
            if (std::string(method) == Smart) module.reset(new PreparedSmart);
            else if (std::string(method) == Traditional) module.reset(new OVIMTraditionalMandarin);
            else module.reset(new OVIMGeneric(method, database.get()));
            OVPathInfo path; path.writablePath = profile.u8string();
            require(module->moduleInitialize(&path, &loader), "actual native module initialization");
            module->loadConfig(&config, &loader);
            context.reset(module->createContext());
        }
        context->startSession(&loader);
    }
    ~Harness() {
        if (context) { context->stopSession(&loader); context.reset(); }
        if (module) { module->finalize(); module.reset(); }
    }
    void addPhrase(const std::string& query, const std::string& text) {
        if (rust) {
            GuanyinmaMacUserData data(modelPath.u8string(), userPath.u8string());
            require(data.valid() && data.apply(@{@"type":@"add_user_phrase",
                @"qstring":[NSString stringWithUTF8String:query.c_str()],
                @"text":[NSString stringWithUTF8String:text.c_str()]}), "seed isolated Rust phrase");
        } else {
            auto* smart = dynamic_cast<PreparedSmart*>(module.get());
            require(smart && smart->addPhrase(query, text), "seed isolated native phrase through LM API");
        }
    }
    PVOneDimensionalCandidatePanel* panel() { return candidates.accessVerticalCandidatePanel(); }
    std::string visible() { return PVCombinedUTF16TextBuffer(composing, reading).composedText(); }
    bool press(const OVKey& key) {
        loader.resetState();
        if (rust) GuanyinmaPrepareCandidatePanelForKey(&key, &candidates);
        auto* p = panel();
        bool handled = false;
        if (p->isInControl()) {
            const auto state = p->handleKeyEvent(key, &loader);
            if (state == PVCandidateState::CandidateChosen) {
                const auto text = p->chosenCandidateString();
                const auto index = p->chosenCandidateIndex();
                p->stopControl();
                context->candidateSelected(&candidates, text, index, &reading, &composing, &loader);
                p->reset(); handled = true;
            } else if (state == PVCandidateState::Canceled) {
                p->stopControl();
                context->candidateCanceled(&candidates, &reading, &composing, &loader);
                p->reset(); handled = true;
            } else if (state == PVCandidateState::Ignored) {
                if (!context->candidateNonPanelKeyReceived(&candidates, &key, &reading, &composing, &loader))
                    loader.beep();
                if (!p->isInControl()) p->reset();
                handled = true;
            } else {
                if (state == PVCandidateState::ReachedPageBoundary ||
                    state == PVCandidateState::InvalidCandidateKey) loader.beep();
                handled = true;
            }
        } else {
            OVKey copy(key);
            handled = context->handleKey(&copy, &reading, &composing, &candidates, &loader);
        }
        if (composing.isCommitted()) {
            committed += composing.composedCommittedText();
            composing.finishCommit();
        }
        return handled;
    }
};
class Trace {
    Harness native, rust;
    std::string label;
public:
    Trace(const char* method, const fs::path& model, const fs::path& root,
          const std::string& name, const Configure& config = {})
        : native(false, method, model, root, config), rust(true, method, model, root, config),
          label(std::string(method) + " " + name) {}
    void addPhrase(const std::string& query, const std::string& text) {
        native.addPhrase(query, text); rust.addPhrase(query, text);
    }
    void event(unsigned code, unsigned flags = 0, const std::string& text = "") {
        const OVKey key = text.empty() ? OVKey(new PVKeyImpl(code, flags)) :
            OVKey(new PVKeyImpl(text, code, flags));
        const bool lhs = native.press(key), rhs = rust.press(key);
        const std::string at = label + " key=" + std::to_string(code) + " flags=" + std::to_string(flags);
        require(lhs == rhs, at + " handled differs");
        require(native.visible() == rust.visible(), at + " visible native=[" + native.visible() + "] Rust=[" + rust.visible() + "]");
        require(native.committed == rust.committed, at + " commit native=[" + native.committed + "] Rust=[" + rust.committed + "]");
        require(native.loader.shouldBeep() == rust.loader.shouldBeep(), at + " beep differs");
        require(PVCombinedUTF16TextBuffer(native.composing, native.reading).cursorPosition() ==
                PVCombinedUTF16TextBuffer(rust.composing, rust.reading).cursorPosition(),
                at + " visible scalar caret differs");
        auto* a = native.panel(); auto* b = rust.panel();
        require(a->isVisible() == b->isVisible() && a->isInControl() == b->isInControl(), at + " panel state differs");
        if (a->isVisible()) {
            require(a->candidateList()->size() == b->candidateList()->size(), at + " candidate count differs");
            for (size_t i = 0; i < a->candidateList()->size(); ++i)
                require(a->candidateList()->candidateAtIndex(i) == b->candidateList()->candidateAtIndex(i),
                        at + " complete candidate order differs at " + std::to_string(i));
            require(a->candidatesPerPage() == b->candidatesPerPage(), at + " page size differs");
            require(a->currentPage() == b->currentPage(), at + " page differs");
            require(a->currentHightlightIndexInCandidateList() == b->currentHightlightIndexInCandidateList(), at + " highlight differs");
        }
    }
    void type(const std::string& keys) { for (unsigned char ch : keys) event(ch); }
};
static void cases(const fs::path& model, const fs::path& root) {
    for (const char* method : {Traditional, Smart, Cangjie, Simplex}) {
        Trace trace(method, model, root, "native literal case");
        trace.event('A', OVKeyMask::Shift);
        trace.event('A', OVKeyMask::CapsLock);
        trace.event('A', OVKeyMask::CapsLock | OVKeyMask::Shift);
        // Standard macOS [NSEvent characters] delivers uppercase with Shift.
        // Synthetic lowercase+Shift represents a caller-prepared text contract,
        // and is deliberately not a physical-event equivalence claim.
        trace.event('1', OVKeyMask::CapsLock);
        trace.event('A');
        trace.event(0, OVKeyMask::Shift, "Ａ");
        trace.event(0, OVKeyMask::CapsLock, "字");
        trace.event(OVKeyCode::Space, OVKeyMask::Shift);
        trace.event('1');
    }
    Trace force(Smart, model, root, "force uppercase", [](OVKeyValueMap& config) {
        config.setKeyBoolValue("ShiftKeyAlwaysCommitUppercaseCharacters", true);
    });
    force.event('A', OVKeyMask::Shift);
}
static void layouts(const fs::path& model, const fs::path& root) {
    struct Layout { const char* name; const char* keys; };
    const Layout names[] = {
        {"Standard","5j/"}, {"standard","5j/"}, {"ETen",",x-"}, {"eTEN",",x-"},
        {"Hsu","jxl"}, {"bpmfdtnlgkhjvcjvcrzasexuyhgeiawomnklldfjs","jxl"},
        {"ETen26","gxl"}, {"bpmfdtnlvkhgvcgycjqwsexuaorwiqzpmntlhfjkd","gxl"},
        {"HanyuPinyin","zhong"}, {"Hanyu Pinyin","zhong"}, {"Hanyu-Pinyin","zhong"},
        {"pinyin","zhong"}, {"HANYU PINYIN","zhong"}, {"unknown-layout","5j/"},
    };
    for (const char* method : {Traditional, Smart}) {
        for (const auto& layout : names) {
            Trace trace(method, model, root, layout.name, [&](OVKeyValueMap& config) {
                config.setKeyStringValue("KeyboardLayout", layout.name);
            });
            trace.type(layout.keys);
            trace.event(OVKeyCode::Space, OVKeyMask::Shift);
            if (std::string(method) == Traditional) {
                trace.event(OVKeyCode::PageDown);
                trace.event(OVKeyCode::PageUp);
                trace.event(OVKeyCode::End);
                trace.event(OVKeyCode::Home);
                trace.event(OVKeyCode::Return);
            } else {
                trace.event(OVKeyCode::Left);
                trace.event(OVKeyCode::Down);
                trace.event(OVKeyCode::PageDown);
                trace.event(OVKeyCode::PageUp);
                trace.event(OVKeyCode::Return);
                trace.event(OVKeyCode::Return);
            }
        }
    }
}
static void edits(const fs::path& model, const fs::path& root) {
    for (const char* method : {Traditional, Smart, Cangjie, Simplex}) {
        Trace trace(method, model, root, "unfinished / DirectText");
        trace.type(std::string(method) == Cangjie || std::string(method) == Simplex ? "h" : "s");
        trace.event('a', OVKeyMask::DirectText, "字");
        trace.event(OVKeyCode::Return);
        trace.event(OVKeyCode::Backspace);
        trace.event(OVKeyCode::Esc);
    }
    for (const char* method : {Traditional, Smart}) {
        Trace trace(method, model, root, "composition editing");
        trace.type("su3");
        if (std::string(method) == Smart) { trace.event(OVKeyCode::Left); trace.event(OVKeyCode::Down); }
        trace.event('a', OVKeyMask::DirectText, "字");
        trace.event(OVKeyCode::Backspace);
        trace.event(OVKeyCode::Esc);
        trace.event(OVKeyCode::Return);
    }
    for (const char* method : {Traditional, Cangjie, Simplex}) {
        Trace candidate(method, model, root, "candidate literal modifiers");
        candidate.type(std::string(method) == Traditional ? "su3" : "a ");
        candidate.event('A', OVKeyMask::Shift);
        candidate.event('A', OVKeyMask::CapsLock);
        candidate.event(OVKeyCode::Space, OVKeyMask::Shift);
        candidate.event(OVKeyCode::Esc);
    }
    for (const char* keys : {"ni3", "ni "}) {
        Trace pinyin(Traditional, model, root, "Pinyin candidate continuation", [](OVKeyValueMap& config) {
            config.setKeyStringValue("KeyboardLayout", "Hanyu Pinyin");
        });
        pinyin.type(keys); pinyin.event('a'); pinyin.event(OVKeyCode::Esc);
    }
    Trace pinyinUpper(Traditional, model, root, "Pinyin modified continuation", [](OVKeyValueMap& config) {
        config.setKeyStringValue("KeyboardLayout", "Hanyu Pinyin");
    });
    pinyinUpper.type("ni "); pinyinUpper.event('A', OVKeyMask::Shift);
    for (const char* method : {Traditional, Cangjie, Simplex}) {
        Trace capsSpace(method, model, root, "Caps Lock Space supersedes unfinished input");
        capsSpace.type(std::string(method) == Traditional ? "s" : "h");
        capsSpace.event(OVKeyCode::Space, OVKeyMask::CapsLock);
    }
    for (const char* method : {Traditional, Cangjie, Simplex}) {
        for (unsigned flags : {0u, static_cast<unsigned>(OVKeyMask::Shift)}) {
            for (char angle : {'<', '>'}) {
                Trace brackets(method, model, root, "candidate angle key");
                brackets.type(std::string(method) == Traditional ? "su3" : "a ");
                brackets.event(angle, flags);
            }
        }
    }
    Trace unicode(Smart, model, root, "split supplementary user phrase");
    unicode.addPhrase("0_0_", "🙂事");
    unicode.type("g4g4"); unicode.event(OVKeyCode::Left); unicode.type("s");
    unicode.event('a', OVKeyMask::DirectText, "Ａ"); unicode.event(OVKeyCode::Return);
    Trace shortcuts(Traditional, model, root, "unfinished Ctrl punctuation");
    shortcuts.type("s");
    shortcuts.event(',', OVKeyMask::Ctrl);
    shortcuts.event('a', OVKeyMask::Ctrl | OVKeyMask::Alt);
}
static void capsSpecials(const fs::path& model, const fs::path& root) {
    bool failed = false;
    for (const char* method : {Cangjie, Simplex, Traditional}) {
        for (unsigned key : {OVKeyCode::Backspace, OVKeyCode::Return, OVKeyCode::Esc,
                             OVKeyCode::Left, OVKeyCode::Right}) {
            try {
                Trace trace(method, model, root, "Caps Lock special", [](OVKeyValueMap& config) {
                    config.setKeyBoolValue("ShouldCommitAtMaximumRadicalLength", false);
                });
                trace.event(key, OVKeyMask::CapsLock);
                trace.type(std::string(method) == Traditional ? "su" : "hk");
                trace.event(key, OVKeyMask::CapsLock);
            } catch (const std::exception& error) {
                std::cerr << "Caps special diagnostic: " << error.what() << "\n";
                failed = true;
            }
        }
    }
    if (failed) throw std::runtime_error("Caps Lock native special-key differences remain");
}
static void controls(const fs::path& model, const fs::path& root) {
    Trace caps(Smart, model, root, "CapsLock control punctuation");
    caps.event('1', OVKeyMask::Ctrl | OVKeyMask::CapsLock);
    caps.type("s");
    caps.event(',', OVKeyMask::Ctrl | OVKeyMask::CapsLock);
    for (bool atEnd : {false, true}) {
        for (bool middle : {false, true}) {
            Trace trace(Smart, model, root, "Ctrl punctuation target", [&](OVKeyValueMap& config) {
                config.setKeyBoolValue("CandidateCursorAtEndOfTargetBlock", atEnd);
            });
            trace.type("su3cl3");
            if (middle) trace.event(OVKeyCode::Left);
            trace.event('1', OVKeyMask::Ctrl);
            trace.event(OVKeyCode::Esc);
            trace.event(OVKeyCode::Return);
        }
        Trace single(Smart, model, root, "Ctrl single punctuation", [&](OVKeyValueMap& config) {
            config.setKeyBoolValue("CandidateCursorAtEndOfTargetBlock", atEnd);
        });
        single.type("su3cl3"); single.event(OVKeyCode::Left);
        single.event(',', OVKeyMask::Ctrl);
        single.event(OVKeyCode::Return);
    }
}
static void tables(const fs::path& model, const fs::path& root) {
    for (const char* method : {Cangjie, Simplex}) {
        for (bool leading : {false, true}) {
            Trace trace(method, model, root, leading ? "leading Space" : "one-page Space", [&](OVKeyValueMap& config) {
                config.setKeyBoolValue("UseSpaceAsFirstCandidateSelectionKey", leading);
                config.setKeyBoolValue("SendFirstCandidateWithSpaceWithOnePageList", true);
            });
            trace.type("a"); trace.event(OVKeyCode::Space);
            trace.event(OVKeyCode::Space);
            trace.event(OVKeyCode::Esc);
        }
        Trace maximum(method, model, root, "custom maximum", [](OVKeyValueMap& config) {
            config.setKeyIntValue("MaximumRadicalLength", 2);
            config.setKeyBoolValue("ShouldCommitAtMaximumRadicalLength", true);
        });
        maximum.type("hk"); maximum.event(OVKeyCode::Return);
        for (const char* overrideName : {"Punctuations-cj-mixedwidth-cin","Punctuations-cj-halfwidth-cin"}) {
            Trace punctuation(method, model, root, overrideName, [&](OVKeyValueMap& config) {
                config.setKeyStringValue("UseOverrideTable", overrideName);
            });
            punctuation.type(","); punctuation.event(OVKeyCode::Space);
            punctuation.event(OVKeyCode::Return);
        }
    }
    Trace legacyDefault(Cangjie, model, root, "actual preference default override", [](OVKeyValueMap& config) {
        config.setKeyStringValue("UseOverrideTable", "Punctuations-punctuations-cin");
    });
    legacyDefault.type(","); legacyDefault.event(OVKeyCode::Space); legacyDefault.event(OVKeyCode::Return);
    Trace wildcard(Cangjie, model, root, "custom wildcard", [](OVKeyValueMap& config) {
        config.setKeyStringValue("MatchOneChar", "!");
        config.setKeyStringValue("MatchZeroOrMoreChar", "%");
    });
    wildcard.type("hk!"); wildcard.event(OVKeyCode::Space);
    wildcard.event(OVKeyCode::PageDown); wildcard.event(OVKeyCode::Return);
    Trace angleWildcard(Cangjie, model, root, "plain angle wildcard", [](OVKeyValueMap& config) {
        config.setKeyStringValue("MatchOneChar", ">");
    });
    angleWildcard.type("hk "); angleWildcard.event('>');
    Trace prefix(Cangjie, model, root, "prefix", [](OVKeyValueMap& config) {
        config.setKeyBoolValue("ComposeWhileTyping", true);
        config.setKeyBoolValue("PrefixCandidates", true);
    });
    prefix.type("hk"); prefix.event('2'); prefix.type("hkrbr"); prefix.event(OVKeyCode::Space);
}
int main(int argc, char** argv) {
    @autoreleasepool {
        try {
            require(argc >= 3, "usage: oracle MODEL TEMP_ROOT [case|layouts|edits|controls|tables|caps|all]");
            const fs::path model=argv[1], root=argv[2];
            const std::string group = argc > 3 ? argv[3] : "all";
            bool failed = false;
            auto run = [&](const char* name, const auto& action) {
                if (group != "all" && group != name) return;
                try { action(model, root); }
                catch (const std::exception& error) {
                    std::cerr << "Native behavior mismatch [" << name << "]: " << error.what() << "\n";
                    failed = true;
                }
            };
            run("case", cases); run("layouts", layouts); run("edits", edits); run("controls", controls); run("tables", tables); run("caps", capsSpecials);
            std::cout << "Four macOS native input methods: " << checks << " checks, "
                      << (failed ? "FAILED" : "passed") << ".\n";
            return failed ? 1 : 0;
        } catch (const std::exception& error) {
            std::cerr << "Native behavior mismatch: " << error.what() << "\n";
            return 1;
        }
    }
}
