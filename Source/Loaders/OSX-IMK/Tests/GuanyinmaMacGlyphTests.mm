// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
// Rust adapter/system-font FE contract; never starts installed IMK or reads a profile.
#import <Cocoa/Cocoa.h>
#include "GuanyinmaMacAdapter.h"
#include "CVEncodingService.h"
#include "PVBasicKeyValueMapImpl.h"
#include "PVLoaderService.h"
#include "PVCandidate.h"
#include "PVTextBuffer.h"
#include <algorithm>
#include <filesystem>
#include <iostream>
#include <memory>
#include <set>
#include <stdexcept>

using namespace OpenVanilla;
namespace fs = std::filesystem;
static size_t checks;
static const char* Cangjie = "Generic-cj-cin";
static void require(bool ok, const std::string& message) {
    ++checks;
    if (!ok) throw std::runtime_error(message);
}
static void expectText(const std::string& actual, const std::string& expected, const std::string& label) {
    require(actual == expected, label + ": expected [" + expected + "], got [" + actual + "]");
}

class FontPolicy : public PVDefaultEncodingService {
public:
    std::set<std::string> rejected = {"𥫜", "\U000fd952", "𠆥"};
    size_t systemCalls = 0, encodingCalls = 0;
    bool codepointSupportedBySystem(const std::string& text) override {
        ++systemCalls;
        return !rejected.count(text);
    }
    bool codepointSupportedByEncoding(const std::string& text, const std::string& encoding) override {
        ++encodingCalls;
        if (encoding == "UTF-8") return true;
        // A distinct policy demonstrates the explicit encoding route.
        return !rejected.count(text) && (encoding != "BIG-5" || text != "昋");
    }
    bool isEncodingSupported(const std::string& value) override {
        return value == "UTF-8" || value == "BIG-5";
    }
};

class Harness {
public:
    PVBasicKeyValueMapImpl values;
    OVKeyValueMap config;
    PVLoaderService loader;
    PVCandidateService candidates;
    PVTextBuffer reading, composing;
    std::unique_ptr<OVEventHandlingContext> context;
    std::string committed;
    Harness(OVEncodingService* policy, const fs::path& model,
            const fs::path& scratch, const std::string& encoding = "", bool prefix = true)
        : config(&values), loader("zh_TW", nullptr, nullptr, nullptr, policy), candidates(&loader) {
        config.setKeyBoolValue("ComposeWhileTyping", true);
        config.setKeyBoolValue("PrefixCandidates", prefix);
        config.setKeyBoolValue("UseDynamicFrequency", false);
        config.setKeyBoolValue("ClearReadingBufferAtCompositionError", false);
        config.setKeyStringValue("UseCharactersSupportedByEncoding", encoding);
        std::string error;
        context.reset(GuanyinmaCreateInputContext(Cangjie, model.u8string(),
            (scratch / "rust-users.db").u8string(), &config, &error));
        require(context != nullptr, "Rust context: " + error);
        context->startSession(&loader);
    }
    ~Harness() {
        if (context) context->stopSession(&loader);
        context.reset();
    }
    PVOneDimensionalCandidatePanel* panel() { return candidates.accessVerticalCandidatePanel(); }
    std::vector<std::string> list() {
        std::vector<std::string> result;
        if (!panel()->isVisible()) return result;
        auto* source = panel()->candidateList();
        for (size_t i = 0; i < source->size(); ++i) result.push_back(source->candidateAtIndex(i));
        return result;
    }
    bool press(const OVKey& key) {
        loader.resetState();
        bool handled = true;
        auto* p = panel();
        if (p->isVisible() && p->isInControl()) {
            const auto state = p->handleKeyEvent(key, &loader);
            if (state == PVCandidateState::CandidateChosen) {
                const auto text = p->chosenCandidateString();
                const auto index = p->chosenCandidateIndex();
                p->hide(); p->cancelEventHandler();
                handled = context->candidateSelected(&candidates, text, index, &reading, &composing, &loader);
            } else if (state == PVCandidateState::Canceled) {
                p->hide(); p->cancelEventHandler();
                context->candidateCanceled(&candidates, &reading, &composing, &loader);
            } else if (state == PVCandidateState::Ignored) {
                handled = context->candidateNonPanelKeyReceived(&candidates, &key, &reading, &composing, &loader);
            }
        } else {
            auto copy = key;
            handled = context->handleKey(&copy, &reading, &composing, &candidates, &loader);
        }
        if (composing.isCommitted()) {
            committed += composing.composedCommittedText();
            composing.finishCommit();
        }
        return handled;
    }
    void key(unsigned code) { require(press(loader.makeOVKey(code)), "input key handled"); }
    void type(const std::string& value) { for (unsigned char c : value) key(c); }
    void choose(size_t index) {
        require(index < list().size(), "selection index exists");
        const auto page = index / panel()->candidatesPerPage();
        while (panel()->currentPage() < page) key(OVKeyCode::PageDown);
        while (panel()->currentPage() > page) key(OVKeyCode::PageUp);
        const auto selection = panel()->candidateKeyAtIndex(index % panel()->candidatesPerPage());
        require(press(selection), "candidate selection handled");
    }
};

static std::vector<std::string> candidatesForPolicy(OVEncodingService* policy, const fs::path& model,
        const fs::path& root, const std::string& code, const std::string& encoding = "",
        bool prefix = true) {
    Harness rust(policy, model, root, encoding, prefix);
    rust.type(code);
    const auto actual = rust.list();
    require(!actual.empty(), "filtered candidate list is available for " + code + "/" + encoding);
    require(rust.panel()->candidatesPerPage() == std::min<size_t>(9, actual.size()),
            "native FE keeps nine selection keys and shortens a smaller list");
    require(rust.panel()->pageCount() == (actual.size() + 8) / 9,
            "FE page count uses the already filtered candidate list");
    for (const auto& text : actual)
        require(encoding.empty() ? policy->stringSupportedBySystem(text) :
            policy->stringSupportedByEncoding(text, encoding), "candidate accepted by frontend");
    if (actual.size() > rust.panel()->candidatesPerPage()) {
        rust.key(OVKeyCode::PageDown);
        require(rust.panel()->currentPage() == 1, "page-down reaches filtered second page");
        rust.key(OVKeyCode::PageUp);
        require(rust.panel()->currentPage() == 0, "page-up returns to first page");
        const auto selected = rust.panel()->candidatesPerPage() + 1;
        require(selected < actual.size(), "second-page target exists");
        rust.choose(selected);
        expectText(rust.committed, actual[selected], "filtered second-page selection identity");
    }
    return actual;
}

static void deterministic(const fs::path& model, const fs::path& root) {
    FontPolicy policy;
    for (const auto& code : {"hk", "hkr", "hkrb", "hkrbr", "hk?", "hk*"}) candidatesForPolicy(&policy, model, root, code);
    {
        Harness rust(&policy, model, root);
        rust.type("hk");
        expectText(rust.reading.composedText(), "竹大", "Cangjie roots reach native reading buffer");
        const auto view = rust.list();
        require(view.size() == 37, "one supported exact result plus 36 prefix results");
        expectText(view[0], "夭", "supported exact result first");
        expectText(view[1], "喬", "喬 is second after unsupported exact results are removed");
        rust.key('2');
        expectText(rust.committed, "喬", "Rust number 2 selects 喬");
    }
    require(policy.systemCalls > 0, "empty encoding invokes frontend system-font check");
    policy.rejected.insert("喬"); policy.rejected.insert("昋"); policy.rejected.insert("簝");
    const auto refill = candidatesForPolicy(&policy, model, root, "hk");
    require(refill.size() == 37, "prefix fills all 36 slots after popular prefix results are rejected");
    require(std::find(refill.begin(), refill.end(), "喬") == refill.end(), "rejected prefix is absent");
    FontPolicy encoding;
    const auto raw = candidatesForPolicy(&encoding, model, root, "hk", "UTF-8");
    require(raw.size() == 40, "UTF-8 policy preserves all original four exact plus 36 prefix results");
    expectText(raw[4], "喬", "UTF-8 explicit policy permits original rare exact candidates");
    const auto big5 = candidatesForPolicy(&encoding, model, root, "hk", "BIG-5");
    expectText(big5[1], "喬", "explicit encoding policy removes unsupported exact results");
    require(std::find(big5.begin(), big5.end(), "昋") == big5.end(), "encoding-specific rejection applied");
    require(encoding.encodingCalls > 0, "explicit encoding invokes encoding service");
    candidatesForPolicy(&policy, model, root, "hk", "", false);
}

static void actualFonts(const fs::path& model, const fs::path& root) {
    // Font queries need AppKit initialized first, in this isolated process.
    // No windows/text controls, TIS calls, installed IMK or real profile are used.
    [NSApplication sharedApplication];
    CVEncodingService policy;
    require(policy.stringSupportedBySystem("夭喬中文"), "system font coverage is usable for basic Chinese");
    const auto values = candidatesForPolicy(&policy, model, root, "hk");
    require(values.size() >= 2, "real system-font hk results are available");
    expectText(values[0], "夭", "real system-font exact result");
    // Installed font coverage may differ across machines; deterministic policy
    // fixtures above keep the missing-glyph ordering regression stable.
    const auto qiao = std::find(values.begin(), values.end(), "喬");
    require(qiao != values.end(), "real system-font prefix retains 喬");
    std::cout << "Actual CVEncodingService hk (喬 index "
              << std::distance(values.begin(), qiao) << "): ";
    for (size_t i = 0; i < std::min<size_t>(9, values.size()); ++i) std::cout << values[i] << " ";
    std::cout << "\n";
}

int main(int argc, char** argv) {
    @autoreleasepool {
        try {
            require(argc == 3 || (argc == 4 && std::string(argv[3]) == "--system-fonts"),
                    "usage: GuanyinmaMacGlyphTests MODEL TEMP_PROFILES [--system-fonts]");
            const fs::path model = argv[1], root = argv[2];
            require(fs::is_regular_file(model) && fs::is_directory(root), "existing model and isolated profile directory");
            deterministic(model, root);
            if (argc == 4) actualFonts(model, root);
            std::cout << "Guanyinma macOS glyph FE contract: " << checks << " checks passed.\n";
            return 0;
        } catch (const std::exception& error) {
            std::cerr << error.what() << "\n";
            return 1;
        }
    }
}
