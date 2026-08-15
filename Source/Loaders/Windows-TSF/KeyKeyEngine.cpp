#include "KeyKeyEngine.h"

#include <mutex>
#include <utility>

#include "ModuleState.h"

#include "OpenVanilla.h"
#include "PlainVanilla.h"
#include "OVAFAssociatedPhrase.h"
#include "OVIMTraditionalMandarin.h"

namespace KeyKey::WindowsTsf {
namespace {

using namespace OpenVanilla;

constexpr char kPrimaryInputMethod[] = OVIMTRADITIONALMANDARIN_IDENTIFIER;
constexpr char kAssociatedPhraseFilter[] = OVAFASSOCIATEDPHRASE_IDENTIFIER;

class WindowsLoaderPolicy final : public PVLoaderPolicy {
public:
    WindowsLoaderPolicy() : PVLoaderPolicy(std::vector<std::string>()) {}

    const std::string defaultDatabaseFileName() override { return "KeyKey.db"; }
    const std::string loaderIdentifier() override {
        return "org.openvanilla.chichi77-keykey.windows";
    }
    const std::string loaderName() override { return "chichi77 KeyKey"; }
    const std::vector<std::string> modulePackageFilePatterns() override { return {}; }
};

// Smart Mandarin depends on a corpus that is not part of this repository. Keep
// the database-backed Traditional Mandarin and associated-phrase modules in the
// first Windows milestone.
class WindowsMandarinPackage final : public OVModulePackage {
public:
    bool initialize(OVPathInfo*, OVLoaderService*) override {
        m_moduleVector.push_back(new OVModuleClassWrapper<OVIMTraditionalMandarin>);
        m_moduleVector.push_back(new OVModuleClassWrapper<OVAFAssociatedPhrase>);
        return true;
    }
};

std::wstring ModuleDirectory() {
    std::wstring path(32768, L'\0');
    const DWORD length = GetModuleFileNameW(g_module, path.data(),
                                            static_cast<DWORD>(path.size()));
    if (!length || length >= path.size()) return {};
    path.resize(length);
    const size_t separator = path.find_last_of(L"\\/");
    return separator == std::wstring::npos ? std::wstring() : path.substr(0, separator);
}

std::string FindDatabase() {
    const std::wstring root = ModuleDirectory();
    if (root.empty()) return {};

    const std::wstring candidates[] = {
        root + L"\\Databases\\KeyKey.db",
        root + L"\\KeyKey.db",
    };
    for (const auto& candidate : candidates) {
        const DWORD attributes = GetFileAttributesW(candidate.c_str());
        if (attributes != INVALID_FILE_ATTRIBUTES &&
            !(attributes & FILE_ATTRIBUTE_DIRECTORY)) {
            return OVUTF8::FromUTF16(candidate);
        }
    }
    return {};
}

class EngineRuntime final {
public:
    EngineRuntime() {
        const std::string databasePath = FindDatabase();
        if (databasePath.empty()) {
            OutputDebugStringW(L"chichi77 KeyKey TSF: Databases\\KeyKey.db was not found.\n");
            return;
        }

        database_.reset(OVSQLiteDatabaseService::Create(databasePath));
        if (!database_) {
            OutputDebugStringW(L"chichi77 KeyKey TSF: unable to open KeyKey.db.\n");
            return;
        }

        const std::string resourcePath = OVUTF8::FromUTF16(ModuleDirectory());
        OVPathInfo pathInfo;
        pathInfo.loadedPath = resourcePath;
        pathInfo.resourcePath = resourcePath;
        pathInfo.writablePath =
            OVDirectoryHelper::UserApplicationSupportDataDirectory("chichi77 KeyKey");
        OVDirectoryHelper::CheckDirectory(pathInfo.writablePath);

        policy_ = std::make_unique<WindowsLoaderPolicy>();
        service_ = std::make_unique<PVLoaderService>("zh_TW", nullptr, database_.get());
        packages_ = std::make_unique<PVStaticModulePackageLoadingSystem>(pathInfo, true);

        auto* mandarin = new WindowsMandarinPackage();
        if (!mandarin->initialize(&pathInfo, service_.get()) ||
            !packages_->addInitializedPackage("OVIMMandarin", mandarin)) {
            mandarin->finalize();
            delete mandarin;
            return;
        }

        std::vector<PVModulePackageLoadingSystem*> systems{packages_.get()};
        loader_ = std::make_unique<PVLoader>(policy_.get(), service_.get(), systems);
        loader_->setPrimaryInputMethod(kPrimaryInputMethod);
        if (!loader_->isAroundFilterActivated(kAssociatedPhraseFilter)) {
            loader_->toggleAroundFilter(kAssociatedPhraseFilter);
        }
        loader_->syncSandwichConfig();
        ready_ = loader_->primaryInputMethod() == kPrimaryInputMethod;
    }

    PVLoaderContext* createContext() {
        std::lock_guard<std::recursive_mutex> lock(mutex_);
        return ready_ ? loader_->createContext() : nullptr;
    }

    PVLoaderService* service() const { return service_.get(); }
    void syncSettings() {
        if (loader_) loader_->syncSandwichConfig();
    }
    std::recursive_mutex& mutex() { return mutex_; }

private:
    std::recursive_mutex mutex_;
    std::unique_ptr<OVSQLiteDatabaseService> database_;
    std::unique_ptr<WindowsLoaderPolicy> policy_;
    std::unique_ptr<PVLoaderService> service_;
    std::unique_ptr<PVStaticModulePackageLoadingSystem> packages_;
    std::unique_ptr<PVLoader> loader_;
    bool ready_ = false;
};

EngineRuntime& Runtime() {
    // Avoid running the legacy core's destructor graph while Windows owns the
    // loader lock during process shutdown.
    static EngineRuntime* runtime = new EngineRuntime();
    return *runtime;
}

unsigned int Modifiers(const KeyEvent& event) {
    unsigned int result = 0;
    if (event.alt) result |= OVKeyMask::Alt;
    if (event.control) result |= OVKeyMask::Ctrl;
    if (event.shift) result |= OVKeyMask::Shift;
    if (event.capsLock) result |= OVKeyMask::CapsLock;
    // The legacy OpenVanilla module treats NumLock as a property of a numpad
    // key, not as a global keyboard toggle. Windows reports the toggle for
    // every key; propagating it for the main keyboard makes Mandarin reject
    // all ordinary Bopomofo keys while Num Lock is on.
    if (event.numLock && event.virtualKey >= VK_NUMPAD0 &&
        event.virtualKey <= VK_DIVIDE) {
        result |= OVKeyMask::NumLock;
    }
    return result;
}

unsigned int SpecialKeyCode(UINT virtualKey) {
    switch (virtualKey) {
        case VK_BACK: return OVKeyCode::Backspace;
        case VK_DELETE: return OVKeyCode::Delete;
        case VK_UP: return OVKeyCode::Up;
        case VK_DOWN: return OVKeyCode::Down;
        case VK_LEFT: return OVKeyCode::Left;
        case VK_RIGHT: return OVKeyCode::Right;
        case VK_HOME: return OVKeyCode::Home;
        case VK_END: return OVKeyCode::End;
        case VK_PRIOR: return OVKeyCode::PageUp;
        case VK_NEXT: return OVKeyCode::PageDown;
        case VK_TAB: return OVKeyCode::Tab;
        case VK_ESCAPE: return OVKeyCode::Esc;
        case VK_SPACE: return OVKeyCode::Space;
        case VK_RETURN: return OVKeyCode::Return;
        case VK_F1: return OVKeyCode::F1;
        case VK_F2: return OVKeyCode::F2;
        case VK_F3: return OVKeyCode::F3;
        case VK_F4: return OVKeyCode::F4;
        case VK_F5: return OVKeyCode::F5;
        case VK_F6: return OVKeyCode::F6;
        case VK_F7: return OVKeyCode::F7;
        case VK_F8: return OVKeyCode::F8;
        case VK_F9: return OVKeyCode::F9;
        case VK_F10: return OVKeyCode::F10;
        default: return 0;
    }
}

char PrintableAsciiFromVirtualKey(const KeyEvent& event) {
    if (event.virtualKey >= 'A' && event.virtualKey <= 'Z') {
        const bool upper = event.shift != event.capsLock;
        return static_cast<char>((upper ? 'A' : 'a') + event.virtualKey - 'A');
    }
    if (event.virtualKey >= '0' && event.virtualKey <= '9') {
        static constexpr char shiftedDigits[] = ")!@#$%^&*(";
        return event.shift ? shiftedDigits[event.virtualKey - '0']
                           : static_cast<char>(event.virtualKey);
    }
    if (event.virtualKey >= VK_NUMPAD0 && event.virtualKey <= VK_NUMPAD9 &&
        event.numLock) {
        return static_cast<char>('0' + event.virtualKey - VK_NUMPAD0);
    }
    switch (event.virtualKey) {
        case VK_SPACE: return ' ';
        case VK_OEM_1: return event.shift ? ':' : ';';
        case VK_OEM_PLUS: return event.shift ? '+' : '=';
        case VK_OEM_COMMA: return event.shift ? '<' : ',';
        case VK_OEM_MINUS: return event.shift ? '_' : '-';
        case VK_OEM_PERIOD: return event.shift ? '>' : '.';
        case VK_OEM_2: return event.shift ? '?' : '/';
        case VK_OEM_3: return event.shift ? '~' : '`';
        case VK_OEM_4: return event.shift ? '{' : '[';
        case VK_OEM_5: return event.shift ? '|' : '\\';
        case VK_OEM_6: return event.shift ? '}' : ']';
        case VK_OEM_7: return event.shift ? '"' : '\'';
        default: return 0;
    }
}

PVKeyImpl MakeKey(const KeyEvent& event) {
    const unsigned int modifiers = Modifiers(event);
    unsigned int keyCode = SpecialKeyCode(event.virtualKey);
    std::string received;

    if (event.control && event.virtualKey >= 'A' && event.virtualKey <= 'Z') {
        keyCode = static_cast<unsigned int>('a' + event.virtualKey - 'A');
        received.assign(1, static_cast<char>(keyCode));
    } else if (const char character = PrintableAsciiFromVirtualKey(event)) {
        // Bopomofo is a key-position based layout. Prefer the Windows virtual
        // key over ToUnicodeEx, which can report an uppercase or localized
        // character while a Chinese TIP is active.
        keyCode = static_cast<unsigned char>(character);
        received.assign(1, character);
    } else if (!event.text.empty() && event.text.size() == 1 &&
               event.text.front() >= 32 && event.text.front() < 127) {
        keyCode = static_cast<unsigned char>(event.text.front());
        received.assign(1, static_cast<char>(keyCode));
    } else if (!event.text.empty()) {
        received = OVUTF8::FromUTF16(event.text);
    }

    return received.empty() ? PVKeyImpl(keyCode, modifiers)
                            : PVKeyImpl(received, keyCode, modifiers);
}

bool IsNavigationOrEditingKey(UINT key) {
    switch (key) {
        case VK_BACK:
        case VK_DELETE:
        case VK_UP:
        case VK_DOWN:
        case VK_LEFT:
        case VK_RIGHT:
        case VK_HOME:
        case VK_END:
        case VK_PRIOR:
        case VK_NEXT:
        case VK_TAB:
        case VK_ESCAPE:
        case VK_SPACE:
        case VK_RETURN:
            return true;
        default:
            return false;
    }
}

void Snapshot(PVLoaderContext* context, EngineResult& result) {
    PVTextBuffer* composing = context->composingText();
    PVTextBuffer* reading = context->readingText();

    if (composing->isCommitted()) {
        result.committedText = OVUTF16::FromUTF8(composing->composedCommittedText());
        composing->finishCommit();
    }

    PVCombinedUTF16TextBuffer combined(*composing, *reading);
    result.compositionText = combined.wideComposedText();
    result.compositionCursor = static_cast<LONG>(combined.wideCursorPosition());

    auto* panel = dynamic_cast<PVOneDimensionalCandidatePanel*>(
        context->candidateService()->lastUsedPanel());
    if (panel && panel->isVisible()) {
        result.candidatesVisible = true;
        result.highlightedCandidate = panel->currentHightlightIndex();
        const size_t first = panel->currentPage() * panel->candidatesPerPage();
        const size_t count = panel->currentPageCandidateCount();
        OVCandidateList* list = panel->candidateList();
        result.candidates.reserve(count);
        for (size_t index = 0; index < count; ++index) {
            EngineCandidate candidate;
            candidate.selectionKey =
                OVUTF16::FromUTF8(panel->candidateKeyAtIndex(index).receivedString());
            candidate.text = OVUTF16::FromUTF8(list->candidateAtIndex(first + index));
            result.candidates.push_back(std::move(candidate));
        }
        panel->finishUpdate();
    }

    if (composing->shouldUpdate()) composing->finishUpdate();
    if (reading->shouldUpdate()) reading->finishUpdate();
}

}  // namespace

std::unique_ptr<KeyKeyEngineSession> KeyKeyEngineSession::Create() {
    return std::unique_ptr<KeyKeyEngineSession>(
        new KeyKeyEngineSession(Runtime().createContext()));
}

KeyKeyEngineSession::KeyKeyEngineSession(PVLoaderContext* context) : context_(context) {
    if (context_) {
        std::lock_guard<std::recursive_mutex> lock(Runtime().mutex());
        context_->activate();
    }
}

KeyKeyEngineSession::~KeyKeyEngineSession() {
    if (!context_) return;
    std::lock_guard<std::recursive_mutex> lock(Runtime().mutex());
    context_->deactivate();
    delete context_;
}

bool KeyKeyEngineSession::ready() const noexcept { return context_ != nullptr; }

bool KeyKeyEngineSession::hasComposition() const {
    if (!context_) return false;
    std::lock_guard<std::recursive_mutex> lock(Runtime().mutex());
    OVCandidatePanel* panel = context_->candidateService()->lastUsedPanel();
    return !context_->composingText()->isEmpty() || !context_->readingText()->isEmpty() ||
           (panel && panel->isVisible());
}

bool KeyKeyEngineSession::wantsKey(const KeyEvent& event) const {
    if (!context_) return false;
    if (hasComposition()) {
        return IsNavigationOrEditingKey(event.virtualKey) ||
               PrintableAsciiFromVirtualKey(event) != 0 || !event.text.empty();
    }
    if (event.control || event.alt) return false;
    // Like production TSF implementations, accept ordinary virtual keys even
    // when ToUnicodeEx returns no character for the active keyboard layout.
    // Otherwise TSF skips OnKeyDown and sends the raw key to the application.
    return PrintableAsciiFromVirtualKey(event) != 0 || !event.text.empty();
}

EngineResult KeyKeyEngineSession::handleKey(const KeyEvent& event) {
    EngineResult result;
    if (!context_) return result;

    std::lock_guard<std::recursive_mutex> lock(Runtime().mutex());
    Runtime().syncSettings();
    PVKeyImpl keyImplementation = MakeKey(event);
    OVKey key(keyImplementation.copy());
    Runtime().service()->resetState();
    result.handled = context_->handleKeyEvent(&key);
    result.beep = Runtime().service()->shouldBeep();
    Snapshot(context_, result);
    return result;
}

void KeyKeyEngineSession::reset() {
    if (!context_) return;
    std::lock_guard<std::recursive_mutex> lock(Runtime().mutex());
    context_->clear();
    Runtime().service()->resetState();
}

}  // namespace KeyKey::WindowsTsf
