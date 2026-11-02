// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
// Standalone Rust package/FE contracts; no installed IMK or preference domain.
#import <Foundation/Foundation.h>
#include "GuanyinmaMacAdapter.h"
#include "PVBasicKeyValueMapImpl.h"
#include "PVCandidate.h"
#include "PVLoaderService.h"
#include "PVTextBuffer.h"
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
class Harness {
public:
    PVLoaderService loader;
    PVCandidateService candidates;
    PVTextBuffer reading, composing;
    std::unique_ptr<OVEventHandlingContext> context;
    std::string committed;
    Harness() : loader("zh_TW"), candidates(&loader) {}
    ~Harness() { if (context) context->stopSession(&loader); }
    void install(OVModule* module) {
        context.reset(module->createContext());
        require(context != nullptr, "package always supplies a success or explicit error context");
        context->startSession(&loader);
    }
    bool press(unsigned code, bool consume = true) {
        auto key = loader.makeOVKey(code);
        bool handled = context->handleKey(&key, &reading, &composing, &candidates, &loader);
        if (consume) finishCommit();
        return handled;
    }
    void type(const std::string& text) { for (unsigned char key : text) press(key); }
    void finishCommit() {
        if (composing.isCommitted()) {
            committed += composing.composedCommittedText();
            composing.finishCommit();
        }
    }
    void choose(const std::string& text) {
        auto* panel = candidates.accessVerticalCandidatePanel();
        auto* list = panel->candidateList();
        for (size_t i = 0; i < list->size(); ++i) {
            if (list->candidateAtIndex(i) != text) continue;
            panel->hide(); panel->cancelEventHandler();
            require(context->candidateSelected(&candidates, text, i, &reading, &composing, &loader),
                    "native selected text/index reaches the Rust session");
            finishCommit();
            return;
        }
        throw std::runtime_error("expected package candidate: " + text);
    }
};
static std::unique_ptr<OVModule> input(OVModulePackage* package, size_t index, Harness& h,
    OVKeyValueMap* config = nullptr) {
    std::unique_ptr<OVModule> module(package->moduleAtIndex(index, &h.loader));
    OVPathInfo path;
    require(module && module->moduleInitialize(&path, &h.loader), "standalone module initializes without native DB services");
    PVBasicKeyValueMapImpl values;
    OVKeyValueMap defaults(&values);
    module->loadConfig(config ? config : &defaults, &h.loader);
    return module;
}
static void testPackage(const fs::path& model, const fs::path& root) {
    std::unique_ptr<OVModulePackage> package(GuanyinmaCreateModulePackage(
        model.u8string(), (root / "package-users.db").u8string()));
    Harness service;
    OVPathInfo path;
    require(package->initialize(&path, &service.loader), "standalone package initializes");
    require(package->numberOfModules(&service.loader) == 5, "exactly four input methods and one associated FE");
    const char* ids[] = {"TraditionalMandarin", "SmartMandarin", "Generic-cj-cin", "Generic-simplex-cin"};
    const char* tc[] = {"傳統注音", "智慧注音", "倉頡（大字集）", "簡易（大字集）"};
    const char* english[] = {"Traditional Mandarin (Bopomofo)", "Smart Mandarin", "CangJie (Large Character Set)", "Simplex (Large Character Set)"};
    for (size_t i = 0; i < 4; ++i) {
        Harness h;
        auto module = input(package.get(), i, h);
        require(module->identifier() == ids[i] && module->isInputMethod(), "existing formal input identifier is retained");
        require(module->localizedName("zh_TW") == tc[i] && module->localizedName("zh-Hant") == tc[i], "existing Traditional Chinese module name is retained");
        require(module->localizedName("en") == english[i], "existing English module name is retained");
        h.install(module.get());
        if (i == 1) {
            h.type("su3cl3"); h.press(OVKeyCode::Return);
            require(h.committed == "你好", "standalone Smart module sends one exact native commit");
        } else if (i == 0) {
            h.type("su3");
            require(h.candidates.accessVerticalCandidatePanel()->candidatesPerPage() == 9, "absent Traditional selection keys use the desktop default");
            h.choose("你");
            require(h.committed == "你", "standalone Traditional module sends selected Chinese");
        } else {
            h.type("a"); h.press(OVKeyCode::Space);
            if (h.committed.empty()) h.choose("日");
            require(h.committed == "日", "standalone table module uses the shared model and sends selected Chinese");
        }
        h.press(OVKeyCode::Return);
        const std::string expected = i == 1 ? "你好" : i == 0 ? "你" : "日";
        require(h.committed == expected, "native commit is not replayed by the next event");
        h.context.reset();
        module->finalize();
    }
    require(package->moduleAtIndex(5, &service.loader) == nullptr &&
            package->moduleAtIndex(static_cast<size_t>(-1), &service.loader) == nullptr,
            "module bounds reject all indices beyond the fixed package");
    auto associated = input(package.get(), 4, service);
    require(associated->isAroundFilter() && associated->identifier() == "OVAFAssociatedPhrase",
            "associated phrase stays a native around-filter FE without a native SQL service");
    PVBasicKeyValueMapImpl values;
    OVKeyValueMap config(&values);
    config.setKeyStringValue("UseGuanyinmaCore", "false");
    config.setKeyStringValue("UnrelatedPreference", "retained");
    auto smart = input(package.get(), 1, service, &config);
    smart->saveConfig(&config, &service.loader);
    require(config.stringValueForKey("UnrelatedPreference") == "retained" &&
            !config.hasKey("ComposingTextBufferSize"), "module does not rewrite FE preferences or persist missing defaults");
    service.install(smart.get()); service.type("su3cl3"); service.press(OVKeyCode::Return);
    require(service.committed == "你好", "obsolete core choice cannot select another engine");
    service.context.reset();
    package->finalize(); package->finalize();
    require(package->numberOfModules(&service.loader) == 0 && package->moduleAtIndex(0, &service.loader) == nullptr,
            "repeated package finalization is safe");
}
static void testFailure(const fs::path& model, const fs::path& root) {
    const fs::path missing = root / "missing-model.db";
    std::unique_ptr<OVModulePackage> broken(GuanyinmaCreateModulePackage(missing.u8string(),
        (root / "unavailable-users.db").u8string()));
    for (size_t i = 0; i < 4; ++i) {
        Harness h;
        auto module = input(broken.get(), i, h);
        h.install(module.get());
        require(h.loader.shouldBeep() && !h.loader.notifyMessage().empty(), "missing model reports an explicit native service error");
        h.type("a"); h.press(OVKeyCode::Return);
        require(h.committed.empty() && h.reading.isEmpty() && h.composing.isEmpty(), "failed Rust initialization never substitutes another engine or literal input");
    }
    require(!fs::exists(missing) && !fs::exists(root / "unavailable-users.db"), "failed input initialization never creates a replacement model or legacy profile");
    Harness h;
    std::unique_ptr<OVModulePackage> package(GuanyinmaCreateModulePackage(model.u8string(),
        (root / "invalid-config-users.db").u8string()));
    PVBasicKeyValueMapImpl values;
    OVKeyValueMap config(&values);
    config.setKeyIntValue("ComposingTextBufferSize", 9);
    auto module = input(package.get(), 1, h, &config);
    h.install(module.get());
    require(h.loader.notifyMessage().size() == 1 && h.loader.notifyMessage()[0].find("10 and 20") != std::string::npos,
            "unsupported configuration is reported with its actual cause");
    h.context.reset();
    config.setKeyIntValue("ComposingTextBufferSize", 10); module->loadConfig(&config, &h.loader);
    h.loader.resetState(); h.install(module.get()); h.type("su3cl3"); h.press(OVKeyCode::Return);
    require(h.committed == "你好" && h.loader.notifyMessage().empty(), "corrected configuration creates a Rust session without fallback state");
}
static void testPendingHostCommit(const fs::path& model, const fs::path& root) {
    Harness h;
    std::unique_ptr<OVModulePackage> package(GuanyinmaCreateModulePackage(model.u8string(),
        (root / "pending-commit-users.db").u8string()));
    PVBasicKeyValueMapImpl values;
    OVKeyValueMap config(&values);
    auto module = input(package.get(), 1, h, &config);
    h.install(module.get()); h.type("su3cl3"); h.press(OVKeyCode::Return, false);
    require(h.composing.isCommitted() && h.composing.composedCommittedText() == "你好",
            "native host still owns an unconsumed commit");
    config.setKeyIntValue("ComposingTextBufferSize", 9); module->loadConfig(&config, &h.loader);
    h.loader.resetState(); h.context->stopSession(&h.loader); h.context->startSession(&h.loader);
    require(!h.loader.shouldBeep(), "lifecycle activation does not change configuration before the host boundary");
    h.press(OVKeyCode::Esc, false);
    require(!h.loader.shouldBeep() && h.composing.composedCommittedText() == "你好",
            "pending native commit defers changed configuration without replaying text");
    h.finishCommit(); h.press(OVKeyCode::Esc);
    require(h.loader.shouldBeep() && h.committed == "你好",
            "next empty native boundary reports rejected configuration and preserves one exact host commit");
    h.loader.resetState(); h.press(OVKeyCode::Esc);
    require(!h.loader.shouldBeep(), "rejected preference generation is reported once");
}
int main(int argc, char** argv) {
    @autoreleasepool {
        try {
            if (argc != 3) throw std::runtime_error("expected model and scratch paths");
            testPackage(argv[1], argv[2]);
            testFailure(argv[1], argv[2]);
            testPendingHostCommit(argv[1], argv[2]);
            std::cout << "Guanyinma macOS package: " << checks << " checks passed.\n";
            return 0;
        } catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
    }
}
