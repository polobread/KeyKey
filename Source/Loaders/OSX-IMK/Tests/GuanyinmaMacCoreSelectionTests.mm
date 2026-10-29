// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
// Runtime selection tests use real PV buffers and the real Rust delegate.
#import <Foundation/Foundation.h>
#include "GuanyinmaMacCoreSelection.h"
#include "GuanyinmaMacAdapter.h"
#include "GuanyinmaMacUserData.h"
#include "OVIMSmartMandarin.h"
#include "PVBasicKeyValueMapImpl.h"
#include "PVLoaderService.h"
#include "PVCandidate.h"
#include "PVTextBuffer.h"
#include "PVContextSandwich.h"
#include "PVLoaderSystem.h"
#include <filesystem>
#include <iostream>
#include <memory>
#include <stdexcept>

// A memory-only preference fixture. No real preference domain is read/written.
@interface CorePreferenceDefaults : NSUserDefaults {
    id _coreValue;
    NSUInteger _writeCount;
}
- (void)useFixtureValue:(id)value;
- (NSUInteger)writeCount;
@end
@implementation CorePreferenceDefaults
- (void)useFixtureValue:(id)value { [_coreValue release]; _coreValue = [value retain]; }
- (id)objectForKey:(NSString*)key { return [key isEqualToString:@"UseGuanyinmaCore"] ? _coreValue : nil; }
- (BOOL)boolForKey:(NSString*)key { return [[self objectForKey:key] boolValue]; }
- (void)setObject:(id)value forKey:(NSString*)key { ++_writeCount; }
- (void)removeObjectForKey:(NSString*)key { ++_writeCount; }
- (NSUInteger)writeCount { return _writeCount; }
- (void)dealloc { [_coreValue release]; [super dealloc]; }
@end

using namespace OpenVanilla;
namespace fs = std::filesystem;
static size_t checks;
static void require(bool value, const std::string& message) {
    ++checks; if (!value) throw std::runtime_error(message);
}
struct Counts {
    size_t made[2]{}, keys[2]{}, selected[2]{}, canceled[2]{}, nonPanel[2]{}, direct[2]{};
    size_t started[2]{}, stopped[2]{}, cleared[2]{}, destroyed[2]{}, initialized = 0, loads = 0;
};
class Delegate : public OVEventHandlingContext {
    Counts& counts;
    unsigned kind;
public:
    Delegate(Counts& value, unsigned backend) : counts(value), kind(backend) { ++counts.made[kind]; }
    ~Delegate() { ++counts.destroyed[kind]; }
    void startSession(OVLoaderService*) override { ++counts.started[kind]; }
    void stopSession(OVLoaderService*) override { ++counts.stopped[kind]; }
    void clear(OVLoaderService*) override { ++counts.cleared[kind]; }
    bool handleKey(OVKey* key, OVTextBuffer* reading, OVTextBuffer* composing,
                   OVCandidateService* candidates, OVLoaderService* service) override {
        ++counts.keys[kind];
        switch (key->keyCode()) {
            case 'x': composing->setText(kind ? "新" : "舊"); break;
            case 'r': reading->setText("ㄅ"); break;
            case 'o': {
                auto* panel = candidates->useOneDimensionalCandidatePanel();
                panel->candidateList()->setCandidates({"甲", "乙"});
                panel->setCandidateKeys("12", service); panel->setCandidatesPerPage(2);
                panel->show(); panel->yieldToCandidateEventHandler(); break;
            }
            case OVKeyCode::Return: {
                auto text = composing->composedText() + reading->composedText();
                reading->clear(); composing->clear(); composing->commitAsTextSegment(text); break;
            }
        }
        return true;
    }
    bool handleDirectText(const std::string& text, OVTextBuffer*, OVTextBuffer* composing,
                          OVCandidateService*, OVLoaderService*) override {
        ++counts.direct[kind]; composing->commitAsTextSegment(text); return true;
    }
    bool candidateSelected(OVCandidateService*, const std::string& text, size_t,
                           OVTextBuffer* reading, OVTextBuffer* composing, OVLoaderService*) override {
        ++counts.selected[kind]; reading->clear(); composing->setText(text); return true;
    }
    void candidateCanceled(OVCandidateService*, OVTextBuffer*, OVTextBuffer*, OVLoaderService*) override {
        ++counts.canceled[kind];
    }
    bool candidateNonPanelKeyReceived(OVCandidateService* candidates, const OVKey* key,
                                      OVTextBuffer* reading, OVTextBuffer* composing, OVLoaderService* service) override {
        ++counts.nonPanel[kind]; OVKey copy(*key); return handleKey(&copy, reading, composing, candidates, service);
    }
};
class Harness {
public:
    PVLoaderService loader;
    PVCandidateService candidates;
    PVTextBuffer reading, composing;
    std::unique_ptr<OVEventHandlingContext> context;
    std::string committed;
    Harness() : loader("zh_TW"), candidates(&loader) {}
    ~Harness() { if (context) context->stopSession(&loader); }
    void install(OVEventHandlingContext* value) {
        context.reset(value); require(context != nullptr, "owned runtime context");
        context->startSession(&loader);
    }
    PVOneDimensionalCandidatePanel* panel() { return candidates.accessVerticalCandidatePanel(); }
    std::string visible() { return PVCombinedUTF16TextBuffer(composing, reading).composedText(); }
    void consume() {
        if (composing.isCommitted()) { committed += composing.composedCommittedText(); composing.finishCommit(); }
    }
    bool press(unsigned code) {
        auto key = loader.makeOVKey(code);
        GuanyinmaPrepareCandidatePanelForKey(&key, &candidates);
        bool handled = true;
        auto* p = panel();
        if (p->isInControl()) {
            auto state = p->handleKeyEvent(key, &loader);
            if (state == PVCandidateState::CandidateChosen) {
                auto text = p->chosenCandidateString(); auto index = p->chosenCandidateIndex();
                p->stopControl();
                handled = context->candidateSelected(&candidates, text, index, &reading, &composing, &loader);
                p->reset();
            } else if (state == PVCandidateState::Canceled) {
                p->stopControl(); context->candidateCanceled(&candidates, &reading, &composing, &loader); p->reset();
            } else if (state == PVCandidateState::Ignored) {
                handled = context->candidateNonPanelKeyReceived(&candidates, &key, &reading, &composing, &loader);
            }
        } else handled = context->handleKey(&key, &reading, &composing, &candidates, &loader);
        consume(); return handled;
    }
    void type(const std::string& text) { for (unsigned char key : text) press(key); }
    void clear() { context->clear(&loader); candidates.resetAll(); reading.clear(); composing.clear(); }
    GuanyinmaCoreStatus status() { return GuanyinmaSwitchingContextStatus(context.get()); }
};
static GuanyinmaCoreContextFactory factory(Counts& counts) {
    return [&counts](bool requested) {
        return GuanyinmaCoreDelegate{new Delegate(counts, requested), requested, ""};
    };
}
static void testDefaultPreferenceAndExplicitLegacyChoice() {
    CorePreferenceDefaults* defaults = [[CorePreferenceDefaults alloc] init];
    require(GuanyinmaRequestedCoreFromDefaults(defaults), "missing frontend preference defaults to Rust");
    auto implicit = GuanyinmaCreateCoreSelection();
    require(GuanyinmaCoreSelectionStatus(implicit).requested, "new selector defaults to Rust");
    [defaults useFixtureValue:@NO];
    require(!GuanyinmaRequestedCoreFromDefaults(defaults), "explicit existing legacy preference remains native");
    Counts counts;
    auto selection = GuanyinmaCreateCoreSelection(GuanyinmaRequestedCoreFromDefaults(defaults));
    Harness h;
    h.install(GuanyinmaCreateSwitchingContext("SmartMandarin", selection, factory(counts)));
    require(!h.status().active && counts.made[0] == 1, "stored legacy choice creates the native delegate");
    h.press('x');
    [defaults useFixtureValue:@YES];
    GuanyinmaRequestCore(selection, GuanyinmaRequestedCoreFromDefaults(defaults));
    h.press('z');
    require(!h.status().active && h.status().pending && h.visible() == "舊",
            "explicit preference change preserves active native composition");
    h.press(OVKeyCode::Return); h.press('x');
    require(h.status().active && h.visible() == "新" && h.committed == "舊",
            "Rust preference applies after the existing host commit is consumed");
    require([defaults writeCount] == 0, "default selection never persists or overwrites user choices");
    [defaults release];
}
static void testStableBoundaries() {
    Counts counts;
    auto selection = GuanyinmaCreateCoreSelection(false);
    Harness h;
    h.install(GuanyinmaCreateSwitchingContext("SmartMandarin", selection, factory(counts)));
    require(!h.status().active && counts.made[0] == 1, "initial native context");
    h.press('x'); h.press('r');
    auto original = h.visible();
    GuanyinmaRequestCore(selection, true);
    h.context->stopSession(&h.loader); h.context->startSession(&h.loader);
    h.press('z');
    require(h.visible() == original && !h.status().active && h.status().pending,
            "unfinished reading and marked text defer switch across lifecycle callbacks");
    require(counts.made[1] == 0 && counts.keys[0] == 3, "old delegate receives pending key exactly once");
    GuanyinmaRequestCore(selection, false);
    h.press('z');
    require(h.visible() == original && counts.made[1] == 0, "reverting pending preference never opens Rust");
    GuanyinmaRequestCore(selection, true);
    h.press(OVKeyCode::Return);
    require(h.committed == "舊ㄅ" && !h.status().active, "old core finishes visible text exactly once");
    h.press('x');
    require(h.visible() == "新" && h.status().active && !h.status().pending,
            "next fresh key reaches new core after commit");
    require(counts.keys[1] == 1 && counts.destroyed[0] == 1, "switch replaces delegate without replay");
    GuanyinmaRequestCore(selection, false);
    h.clear(); h.press('x');
    require(h.visible() == "舊" && !h.status().active && counts.cleared[1] == 1, "clear is a safe boundary for next key");
    h.clear();
    GuanyinmaRequestCore(selection, true);
    require(h.context->handleDirectText("🙂", &h.reading, &h.composing, &h.candidates, &h.loader), "direct text event");
    h.consume();
    require(h.committed == "舊ㄅ🙂" && counts.direct[1] == 1, "direct text switches once at empty boundary");
}
static void testCandidateCallbacksAndNativeGuards() {
    Counts counts;
    auto selection = GuanyinmaCreateCoreSelection(false);
    Harness h;
    h.install(GuanyinmaCreateSwitchingContext("SmartMandarin", selection, factory(counts)));
    h.press('x'); h.press('o');
    GuanyinmaRequestCore(selection, true);
    h.press('2');
    require(counts.selected[0] == 1 && counts.selected[1] == 0 && h.visible() == "乙",
            "late native candidate callback belongs to old delegate");
    require(!h.status().active && h.status().pending, "selected marked text still delays switch");
    h.press(OVKeyCode::Return); h.press('x');
    require(h.committed == "乙" && h.visible() == "新", "candidate commit survives switching once");
    h.clear();
    GuanyinmaRequestCore(selection, false);
    h.press('o'); h.press(OVKeyCode::Esc);
    require(counts.canceled[0] == 1, "cancel callback reaches current native delegate");
    for (int kind = 0; kind < 3; ++kind) {
        h.clear();
        GuanyinmaRequestCore(selection, false); h.press('a');
        if (kind == 2) h.candidates.usePlainTextCandidatePanel()->show();
        else {
            auto* p = kind ? h.candidates.accessHorizontalCandidatePanel() : h.panel();
            p->candidateList()->setCandidates({"foreign"}); p->show(); p->yieldToCandidateEventHandler();
        }
        GuanyinmaRequestCore(selection, true);
        auto key = h.loader.makeOVKey('a');
        h.context->handleKey(&key, &h.reading, &h.composing, &h.candidates, &h.loader);
        require(!h.status().active, "visible native candidate panel delays delegate replacement");
        h.candidates.resetAll(); h.press('a');
        require(h.status().active, "closing native candidate panel permits next fresh key");
    }
    h.clear();
    GuanyinmaRequestCore(selection, false); h.press('a');
    h.composing.commitAsTextSegment("尚未送出");
    GuanyinmaRequestCore(selection, true);
    auto key = h.loader.makeOVKey('a');
    h.context->handleKey(&key, &h.reading, &h.composing, &h.candidates, &h.loader);
    require(!h.status().active && h.composing.composedCommittedText() == "尚未送出",
            "pending host commit cannot be discarded by a core request");
    h.consume(); h.press('a');
    require(h.status().active, "consumed host commit permits switch");
}
static void testSharedContextsAndFailure() {
    Counts counts;
    auto selection = GuanyinmaCreateCoreSelection(false);
    Harness first, second;
    first.install(GuanyinmaCreateSwitchingContext("SmartMandarin", selection, factory(counts)));
    second.install(GuanyinmaCreateSwitchingContext("Generic-cj-cin", selection, factory(counts)));
    first.press('x'); second.press('a');
    GuanyinmaRequestCore(selection, true);
    first.press('a'); second.press('a');
    auto all = GuanyinmaCoreSelectionStatus(selection);
    require(!first.status().active && second.status().active && all.nativeCount == 1 &&
            all.guanyinmaCount == 1 && all.contextCount == 2, "each live context reaches its own safe boundary");
    require(all.active && !all.pending, "latest active context status is not overridden by historical pending context");
    first.press('a');
    auto recent = GuanyinmaCoreSelectionStatus(selection);
    require(!recent.active && recent.pending, "reactivated pending context becomes the reported current backend");
    auto own = GuanyinmaCoreSelectionStatus(selection, "SmartMandarin", &first.candidates);
    require(own.contextCount == 1 && !own.active && own.pending, "status filters actual method and candidate service");
    std::uint64_t config = 1;
    size_t attempts = 0;
    Harness failing;
    auto failures = GuanyinmaCreateCoreSelection(false);
    failing.install(GuanyinmaCreateSwitchingContext("SmartMandarin", failures,
        [&](bool requested) {
            if (requested) { ++attempts; return GuanyinmaCoreDelegate{NULL, false, "unavailable core"}; }
            return GuanyinmaCoreDelegate{new Delegate(counts, 0), false, ""};
        }, [&] { return config; }));
    GuanyinmaRequestCore(failures, true);
    failing.press('a'); failing.press('a'); failing.press('a');
    require(!failing.status().active && !failing.status().error.empty() && attempts == 1,
            "failed idle replacement preserves native core without retrying every key");
    GuanyinmaRequestCore(failures, true); failing.press('a'); failing.press('a');
    require(attempts == 2, "explicit same-choice retry is attempted once");
    ++config; failing.press('a');
    require(attempts == 3, "new configuration allows one explicit retry");
}
class LegacyModule : public OVModule {
    Counts& counts;
public:
    explicit LegacyModule(Counts& value) : counts(value) {}
    const std::string identifier() const override { return "SmartMandarin"; }
    bool isInputMethod() const override { return true; }
    bool initialize(OVPathInfo*, OVLoaderService*) override { ++counts.initialized; return true; }
    OVEventHandlingContext* createContext() override { return new Delegate(counts, 0); }
};
class Package : public OVModulePackage {
    Counts& counts;
public:
    explicit Package(Counts& value) : counts(value) {}
    size_t numberOfModules(OVLoaderService*) override { return 1; }
    OVModule* moduleAtIndex(size_t index, OVLoaderService*) override {
        return index ? NULL : new LegacyModule(counts);
    }
};
static void testRealRustPackageRoundTrip(const fs::path& model, const fs::path& root) {
    Counts counts;
    auto selection = GuanyinmaCreateCoreSelection(true);
    Harness h;
    std::unique_ptr<OVModulePackage> package(GuanyinmaWrapModulePackage(
        new Package(counts), model.u8string(), (root / "runtime-user.db").u8string(), selection));
    std::unique_ptr<OVModule> module(package->moduleAtIndex(0, &h.loader));
    OVPathInfo path; path.writablePath = root.u8string();
    struct RetireContext { Harness& h; ~RetireContext() { if (h.context) { h.context->stopSession(&h.loader); h.context.reset(); } } } retire{h};
    require(module->moduleInitialize(&path, &h.loader), "runtime decorated package initializes");
    PVBasicKeyValueMapImpl values; OVKeyValueMap config(&values);
    config.setKeyStringValue("KeyboardLayout", "Standard");
    config.setKeyStringValue("CandidateSelectionKeys", "12345678");
    module->loadConfig(&config, &h.loader);
    h.install(module->createContext());
    require(h.status().active && counts.initialized == 0, "initial Rust core does not initialize native profile");
    h.type("g4"); h.press(OVKeyCode::Left); h.press(OVKeyCode::Down);
    h.press(OVKeyCode::PageDown);
    const auto chosen = h.panel()->candidateList()->candidateAtIndex(h.panel()->candidatesPerPage() + 1);
    GuanyinmaRequestCore(selection, false);
    require(h.panel()->currentPage() == 1 && h.status().active && h.status().pending,
            "runtime request preserves open candidate page and active owner");
    h.press('2');
    require(h.status().active && h.visible() == chosen, "real Rust candidate stays owned while native switch pending");
    h.press(OVKeyCode::Return); h.press('x');
    require(!h.status().active && h.visible() == "舊" && h.committed == chosen && counts.initialized == 1,
            "same native frontend reaches legacy factory after Rust commit");
    h.press(OVKeyCode::Return);
    GuanyinmaRequestCore(selection, true);
    h.type("g4");
    require(h.status().active && h.visible() == chosen && h.committed == chosen + "舊",
            "Rust preference survives native-core round trip in its separate user store");
    GuanyinmaMacUserData admin(model.u8string(), (root / "runtime-user.db").u8string());
    require([[admin.data() objectForKey:@"overrides"] count] == 1, "runtime selection never resets user learning");
    h.clear(); h.context.reset(); module->finalize(); module.reset(); package->finalize();
}
class TemporaryPolicy : public PVLoaderPolicy {
    fs::path root;
public:
    explicit TemporaryPolicy(const fs::path& value) : PVLoaderPolicy({}), root(value) {}
    const std::string propertyListPathForLoader() override { return (root / "selector-loader.plist").u8string(); }
    const std::string propertyListPathFromIdentifier(const std::string&) override {
        return (root / "selector-module.plist").u8string();
    }
};
class Pipeline : public PVLoaderContext {
public:
    Pipeline(PVLoader* loader, OVEventHandlingContext* input) : PVLoaderContext(loader) {
        m_sandwich = new PVContextSandwich;
        m_sandwich->inputMethods.push_back(input);
        m_sandwich->prepareShortcutContexts();
        m_sandwich->startAllContexts(loader->loaderService());
    }
    const void* sandwich() const { return m_sandwich; }
protected:
    bool shouldEnter(OVLoaderService*, bool = false, bool = false) override { return true; }
};
static void testActualPVDispatch(const fs::path& root) {
    Counts counts;
    auto selection = GuanyinmaCreateCoreSelection(false);
    TemporaryPolicy policy(root);
    PVLoaderService service("zh_TW");
    PVLoader loader(&policy, &service, {});
    auto* proxy = GuanyinmaCreateSwitchingContext("SmartMandarin", selection, factory(counts));
    Pipeline context(&loader, proxy);
    auto send = [&](unsigned code) {
        auto key = service.makeOVKey(code);
        GuanyinmaPrepareCandidatePanelForKey(&key, context.candidateService());
        return context.handleKeyEvent(&key);
    };
    const auto sandwich = context.sandwich();
    const auto generation = loader.generation();
    send('x'); send('o');
    auto* panel = context.candidateService()->accessVerticalCandidatePanel();
    require(panel->isInControl(), "real PV pipeline owns candidate event handler");
    GuanyinmaRequestCore(selection, true);
    send('2');
    require(counts.selected[0] == 1 && counts.made[1] == 0 &&
            context.composingText()->composedText() == "乙" && !panel->isInControl(),
            "actual PV candidateChosen forwards old core then resets candidate panel");
    send(OVKeyCode::Return);
    require(context.composingText()->composedCommittedText() == "乙", "actual PV keeps old-core commit for host");
    context.composingText()->finishCommit();
    send('x');
    require(GuanyinmaSwitchingContextStatus(proxy).active && context.composingText()->composedText() == "新",
            "same real PV context forwards next key to requested core");
    require(context.sandwich() == sandwich && loader.generation() == generation,
            "runtime core preference never invalidates or rebuilds PV sandwich");
    GuanyinmaRequestCore(selection, false);
    context.deactivate(); context.activate(); send('z');
    require(context.composingText()->composedText() == "新" && GuanyinmaSwitchingContextStatus(proxy).active,
            "actual PV activation lifecycle preserves old composition while pending");
    context.clear(); send('x');
    require(!GuanyinmaSwitchingContextStatus(proxy).active && context.composingText()->composedText() == "舊",
            "actual PV clear preserves stable proxy and permits requested native core");
}
static void testUnavailableInitialCoreAndBorrowedLifetime() {
    auto selection = GuanyinmaCreateCoreSelection(false);
    Harness unavailable;
    unavailable.install(GuanyinmaCreateSwitchingContext("SmartMandarin", selection,
        [](bool) { return GuanyinmaCoreDelegate{NULL, false, "native unavailable"}; }));
    require(!unavailable.press('a') && unavailable.visible().empty() && !unavailable.status().error.empty(),
            "initial factory failure leaves host key available without null-context crash");
    Counts counts;
    auto proxy = std::unique_ptr<OVEventHandlingContext>(
        GuanyinmaCreateSwitchingContext("SmartMandarin", selection, factory(counts)));
    {
        PVLoaderService service("zh_TW");
        PVCandidateService candidates(&service);
        PVTextBuffer reading, composing;
        proxy->startSession(&service);
        auto key = service.makeOVKey('a');
        proxy->handleKey(&key, &reading, &composing, &candidates, &service);
    }
    proxy.reset();
    require(counts.destroyed[0] == 1, "proxy destruction does not access expired borrowed frontend objects");
}

class ReadOnlyModel : public OVSQLiteConnection {
    ReadOnlyModel(sqlite3* value, const std::string& path) : OVSQLiteConnection(value, path) {}
public:
    static std::unique_ptr<OVSQLiteConnection> open(const fs::path& model) {
        auto path = fs::absolute(model).u8string();
        NSString* url = [[[NSURL fileURLWithPath:[NSString stringWithUTF8String:path.c_str()]]
            absoluteString] stringByAppendingString:@"?mode=ro"];
        sqlite3* handle = NULL;
        require(sqlite3_open_v2([url UTF8String], &handle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_URI, NULL) == SQLITE_OK,
            "open readonly native model with writable attached user database");
        require(sqlite3_db_readonly(handle, "main") == 1, "native main model is readonly");
        return std::unique_ptr<OVSQLiteConnection>(new ReadOnlyModel(handle, path));
    }
};
class RealSmartContext : public OVIMSmartMandarinContext {
    Counts& counts;
public:
    RealSmartContext(OVIMSmartMandarin* module, Counts& value) : OVIMSmartMandarinContext(module), counts(value) {}
    void stopSession(OVLoaderService* service) override {
        ++counts.stopped[0]; OVIMSmartMandarinContext::stopSession(service);
    }
    bool handleKey(OVKey* key, OVTextBuffer* reading, OVTextBuffer* composing,
                   OVCandidateService* candidates, OVLoaderService* service) override {
        ++counts.keys[0]; return OVIMSmartMandarinContext::handleKey(key, reading, composing, candidates, service);
    }
};
class RealSmart : public OVIMSmartMandarin {
    Counts& counts;
public:
    explicit RealSmart(Counts& value) : counts(value) {}
    bool initialize(OVPathInfo* path, OVLoaderService* service) override {
        ++counts.initialized; return OVIMSmartMandarin::initialize(path, service);
    }
    void loadConfig(OVKeyValueMap* config, OVLoaderService* service) override {
        ++counts.loads; OVIMSmartMandarin::loadConfig(config, service);
    }
    OVEventHandlingContext* createContext() override { return new RealSmartContext(this, counts); }
};
class RealPackage : public OVModulePackage {
    Counts& counts;
public:
    explicit RealPackage(Counts& value) : counts(value) {}
    size_t numberOfModules(OVLoaderService*) override { return 1; }
    OVModule* moduleAtIndex(size_t index, OVLoaderService*) override { return index ? NULL : new RealSmart(counts); }
};
static void testRealManjusriLearning(const fs::path& model, const fs::path& root) {
    const auto nativeProfile = root / "actual-native";
    fs::create_directory(nativeProfile);
    const auto rustParent = root / "initially-missing";
    const auto rustUser = rustParent / "GuanyinmaUserData.db";
    auto connection = ReadOnlyModel::open(model);
    std::unique_ptr<OVSQLiteDatabaseService> database(
        OVSQLiteDatabaseService::ServiceWithExistingConnection(connection.get()));
    Counts counts;
    auto selection = GuanyinmaCreateCoreSelection(false);
    Harness h;
    h.loader.setSQLiteDatabaseService(database.get());
    std::unique_ptr<OVModulePackage> package(GuanyinmaWrapModulePackage(
        new RealPackage(counts), model.u8string(), rustUser.u8string(), selection));
    std::unique_ptr<OVModule> module(package->moduleAtIndex(0, &h.loader));
    OVPathInfo path; path.writablePath = nativeProfile.u8string();
    struct RetireContext { Harness& h; ~RetireContext() { if (h.context) { h.context->stopSession(&h.loader); h.context.reset(); } } } retire{h};
    require(module->moduleInitialize(&path, &h.loader), "actual native module metadata initializes");
    PVBasicKeyValueMapImpl values; OVKeyValueMap config(&values);
    config.setKeyStringValue("KeyboardLayout", "Standard");
    config.setKeyStringValue("CandidateSelectionKeys", "12345678");
    config.setKeyBoolValue("CandidateCursorAtEndOfTargetBlock", false);
    config.setKeyBoolValue("ShowCandidateListWithSpace", true);
    config.setKeyIntValue("ComposingTextBufferSize", 10);
    module->loadConfig(&config, &h.loader);
    h.install(module->createContext());
    require(!h.status().active && counts.loads == 1 && !fs::exists(rustUser),
            "native selection uses only its native profile");
    require(sqlite3_db_readonly(connection->connection(), "userdb") == 0, "native learning uses separate writable attachment");
    h.type("g4"); h.press(OVKeyCode::Left); h.press(OVKeyCode::Down); h.press('2');
    require(h.visible() == "事", "actual Manjusri learns selected candidate");
    h.press(OVKeyCode::Return);
    const auto stops = counts.stopped[0], keys = counts.keys[0], loads = counts.loads;
    GuanyinmaRequestCore(selection, true);
    h.type("g4");
    require(!h.status().active && !h.status().error.empty() && h.visible() == "事",
            "failed Rust activation preserves native in-memory candidate learning");
    require(counts.loads == loads && counts.stopped[0] == stops + 1 && counts.keys[0] == keys + 2,
            "same-config fallback avoids cache reload and forwards each native key once");
    h.clear();
    GuanyinmaRequestCore(selection, false); h.press(OVKeyCode::Esc);
    fs::create_directory(rustParent);
    GuanyinmaRequestCore(selection, true);
    h.type("g4");
    require(h.status().active && h.visible() == "是", "fresh Rust profile does not import native learning");
    h.press(OVKeyCode::Left); h.press(OVKeyCode::Down); h.press('3');
    require(h.visible() == "市", "real Rust core learns independent candidate");
    h.press(OVKeyCode::Return);
    GuanyinmaRequestCore(selection, false); h.type("g4");
    require(!h.status().active && h.visible() == "事" && counts.loads == loads,
            "native learning survives successful Rust roundtrip without reloading its cache");
    h.press(OVKeyCode::Return);
    GuanyinmaRequestCore(selection, true); h.type("g4");
    require(h.status().active && h.visible() == "市", "Rust learning survives actual Manjusri roundtrip independently");
    require(fs::exists(nativeProfile / "SmartMandarinUserData.db") && fs::exists(rustUser),
            "both real cores retain separate user database files");
    h.clear(); h.context->stopSession(&h.loader); h.context.reset();
    module->finalize(); module.reset(); package->finalize();
}

static void testEmptyCandidateOwnership(const fs::path& model, const fs::path& root) {
    // Empty dictionary values are legal. Use a closed disposable model copy to
    // exercise a punctuation panel whose first preview has no native text.
    const auto emptyPreview = root / "empty-preview-model.db";
    fs::copy_file(model, emptyPreview);
    sqlite3* writer = NULL;
    require(sqlite3_open(emptyPreview.u8string().c_str(), &writer) == SQLITE_OK, "open disposable empty-preview fixture");
    require(sqlite3_exec(writer, "UPDATE \"Mandarin-bpmf-cin\" SET value='' WHERE rowid=(SELECT rowid FROM \"Mandarin-bpmf-cin\" WHERE key='_punctuation_list' ORDER BY rowid LIMIT 1)",
                         NULL, NULL, NULL) == SQLITE_OK && sqlite3_changes(writer) == 1, "prepare legal empty punctuation preview");
    sqlite3_close(writer);
    Counts counts;
    auto selection = GuanyinmaCreateCoreSelection(true);
    Harness h;
    h.install(GuanyinmaCreateSwitchingContext("TraditionalMandarin", selection,
        [&](bool requested) {
            if (!requested) return GuanyinmaCoreDelegate{new Delegate(counts, 0), false, ""};
            std::string error;
            auto* input = GuanyinmaCreateInputContext("TraditionalMandarin", emptyPreview.u8string(),
                (root / "punctuation-user.db").u8string(), NULL, &error);
            return GuanyinmaCoreDelegate{input, input != NULL, error};
        }));
    auto punctuation = h.loader.makeOVKey('1', false, false, true);
    require(h.context->handleKey(&punctuation, &h.reading, &h.composing, &h.candidates, &h.loader),
            "real Rust Traditional control punctuation opens candidates");
    require(h.visible().empty() && h.panel()->isInControl() && h.panel()->isVisible(),
            "punctuation candidates can own an empty native composition");
    GuanyinmaRequestCore(selection, false);
    auto keypad = h.loader.makeOVKey('1', false, false, false, false, false, false, true);
    require(GuanyinmaPrepareCandidatePanelForKey(&keypad, &h.candidates), "keypad prehook releases Rust punctuation panel");
    GuanyinmaPreserveCoreForCandidateEvent(selection, &h.candidates);
    require(h.context->handleKey(&keypad, &h.reading, &h.composing, &h.candidates, &h.loader),
            "released candidate event reaches original Rust delegate");
    h.consume();
    require(h.status().active && counts.made[0] == 0 && h.committed == "1",
            "empty candidate keypad event preserves Rust ownership exactly once");
    h.press('a');
    require(!h.status().active && counts.keys[0] == 1, "following quiet event can switch to native delegate");
}

int main(int argc, char** argv) {
    @autoreleasepool {
        try {
            require(argc == 3, "usage: GuanyinmaMacCoreSelectionTests MODEL TEMP_PROFILE_DIRECTORY");
            testDefaultPreferenceAndExplicitLegacyChoice();
            testStableBoundaries();
            testCandidateCallbacksAndNativeGuards();
            testSharedContextsAndFailure();
            testRealRustPackageRoundTrip(argv[1], argv[2]);
            testActualPVDispatch(argv[2]);
            testUnavailableInitialCoreAndBorrowedLifetime();
            testRealManjusriLearning(argv[1], argv[2]);
            testEmptyCandidateOwnership(argv[1], argv[2]);
            std::cout << "Guanyinma macOS core selection: " << checks << " checks passed.\n";
            return 0;
        } catch (const std::exception& error) {
            std::cerr << "Guanyinma macOS core selection test failed: " << error.what() << '\n';
            return 1;
        }
    }
}
