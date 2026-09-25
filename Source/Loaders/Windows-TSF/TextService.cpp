#include "TextService.h"

#include <algorithm>
#include <array>
#include <cwchar>
#include <iterator>
#include <new>
#include <shellapi.h>
#include <utility>

#include "Diagnostics.h"
#include "FrontendSettings.h"
#include "Guids.h"
#include "LangBarButton.h"
#include "ModuleState.h"

namespace KeyKey::WindowsTsf {
namespace {

using Microsoft::WRL::ComPtr;

constexpr DWORD kShiftTapTimeoutMilliseconds = 300;

class KeyEditSession final : public ITfEditSession {
public:
    KeyEditSession(TextService* service, ITfContext* context, KeyEvent event)
        : service_(service), context_(context), event_(std::move(event)) {
        service_->AddRef();
    }

    STDMETHODIMP QueryInterface(REFIID iid, void** object) override {
        if (!object) return E_INVALIDARG;
        *object = nullptr;
        if (iid == IID_IUnknown || iid == IID_ITfEditSession) {
            *object = static_cast<ITfEditSession*>(this);
            AddRef();
            return S_OK;
        }
        return E_NOINTERFACE;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return ++references_; }
    STDMETHODIMP_(ULONG) Release() override {
        const ULONG remaining = --references_;
        if (!remaining) delete this;
        return remaining;
    }
    STDMETHODIMP DoEditSession(TfEditCookie editCookie) override {
        return service_->processKey(editCookie, context_.Get(), event_, &handled_);
    }

    bool handled() const { return handled_; }

private:
    ~KeyEditSession() { service_->Release(); }
    std::atomic<ULONG> references_{1};
    TextService* service_;
    ComPtr<ITfContext> context_;
    KeyEvent event_;
    bool handled_ = false;
};

class TerminateEditSession final : public ITfEditSession {
public:
    explicit TerminateEditSession(ITfComposition* composition)
        : composition_(composition) {}
    STDMETHODIMP QueryInterface(REFIID iid, void** object) override {
        if (!object) return E_INVALIDARG;
        *object = nullptr;
        if (iid == IID_IUnknown || iid == IID_ITfEditSession) {
            *object = static_cast<ITfEditSession*>(this);
            AddRef();
            return S_OK;
        }
        return E_NOINTERFACE;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return ++references_; }
    STDMETHODIMP_(ULONG) Release() override {
        const ULONG remaining = --references_;
        if (!remaining) delete this;
        return remaining;
    }
    STDMETHODIMP DoEditSession(TfEditCookie editCookie) override {
        if (!composition_) return S_OK;
        ComPtr<ITfRange> range;
        if (SUCCEEDED(composition_->GetRange(&range))) {
            range->SetText(editCookie, 0, nullptr, 0);
        }
        return composition_->EndComposition(editCookie);
    }

private:
    ~TerminateEditSession() = default;
    std::atomic<ULONG> references_{1};
    ComPtr<ITfComposition> composition_;
};

class CommitModeSwitchEditSession final : public ITfEditSession {
public:
    CommitModeSwitchEditSession(TextService* service, ITfContext* context)
        : service_(service), context_(context) {
        service_->AddRef();
    }
    STDMETHODIMP QueryInterface(REFIID iid, void** object) override {
        if (!object) return E_INVALIDARG;
        *object = nullptr;
        if (iid == IID_IUnknown || iid == IID_ITfEditSession) {
            *object = static_cast<ITfEditSession*>(this);
            AddRef();
            return S_OK;
        }
        return E_NOINTERFACE;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return ++references_; }
    STDMETHODIMP_(ULONG) Release() override {
        const ULONG remaining = --references_;
        if (!remaining) delete this;
        return remaining;
    }
    STDMETHODIMP DoEditSession(TfEditCookie editCookie) override {
        return service_->commitCompositionForModeSwitch(editCookie, context_.Get());
    }

private:
    ~CommitModeSwitchEditSession() { service_->Release(); }
    std::atomic<ULONG> references_{1};
    TextService* service_;
    ComPtr<ITfContext> context_;
};

class CompositionDisplayAttributeInfo final : public ITfDisplayAttributeInfo {
public:
    CompositionDisplayAttributeInfo() { ++g_objectCount; }
    STDMETHODIMP QueryInterface(REFIID iid, void** object) override {
        if (!object) return E_INVALIDARG;
        *object = nullptr;
        if (iid == IID_IUnknown || iid == IID_ITfDisplayAttributeInfo) {
            *object = static_cast<ITfDisplayAttributeInfo*>(this);
            AddRef();
            return S_OK;
        }
        return E_NOINTERFACE;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return ++references_; }
    STDMETHODIMP_(ULONG) Release() override {
        const ULONG remaining = --references_;
        if (!remaining) delete this;
        return remaining;
    }
    STDMETHODIMP GetGUID(GUID* guid) override {
        if (!guid) return E_INVALIDARG;
        *guid = kCompositionDisplayAttributeGuid;
        return S_OK;
    }
    STDMETHODIMP GetDescription(BSTR* description) override {
        if (!description) return E_INVALIDARG;
        *description = SysAllocString(L"琦琦輸入法組字");
        return *description ? S_OK : E_OUTOFMEMORY;
    }
    STDMETHODIMP GetAttributeInfo(TF_DISPLAYATTRIBUTE* attribute) override {
        if (!attribute) return E_INVALIDARG;
        *attribute = {};
        attribute->crText.type = TF_CT_NONE;
        attribute->crBk.type = TF_CT_NONE;
        attribute->lsStyle = TF_LS_SOLID;
        attribute->crLine.type = TF_CT_NONE;
        attribute->bAttr = TF_ATTR_INPUT;
        return S_OK;
    }
    STDMETHODIMP SetAttributeInfo(const TF_DISPLAYATTRIBUTE*) override {
        return E_NOTIMPL;
    }
    STDMETHODIMP Reset() override { return S_OK; }

private:
    ~CompositionDisplayAttributeInfo() { --g_objectCount; }
    std::atomic<ULONG> references_{1};
};

class CompositionDisplayAttributeEnum final : public IEnumTfDisplayAttributeInfo {
public:
    explicit CompositionDisplayAttributeEnum(bool consumed = false)
        : consumed_(consumed) { ++g_objectCount; }
    STDMETHODIMP QueryInterface(REFIID iid, void** object) override {
        if (!object) return E_INVALIDARG;
        *object = nullptr;
        if (iid == IID_IUnknown || iid == IID_IEnumTfDisplayAttributeInfo) {
            *object = static_cast<IEnumTfDisplayAttributeInfo*>(this);
            AddRef();
            return S_OK;
        }
        return E_NOINTERFACE;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return ++references_; }
    STDMETHODIMP_(ULONG) Release() override {
        const ULONG remaining = --references_;
        if (!remaining) delete this;
        return remaining;
    }
    STDMETHODIMP Clone(IEnumTfDisplayAttributeInfo** result) override {
        if (!result) return E_INVALIDARG;
        *result = new (std::nothrow) CompositionDisplayAttributeEnum(consumed_);
        return *result ? S_OK : E_OUTOFMEMORY;
    }
    STDMETHODIMP Next(ULONG count, ITfDisplayAttributeInfo** items,
                      ULONG* fetched) override {
        if (!items || (!fetched && count != 1)) return E_INVALIDARG;
        if (fetched) *fetched = 0;
        if (!count) return S_OK;
        if (consumed_) return S_FALSE;
        items[0] = new (std::nothrow) CompositionDisplayAttributeInfo();
        if (!items[0]) return E_OUTOFMEMORY;
        consumed_ = true;
        if (fetched) *fetched = 1;
        return count == 1 ? S_OK : S_FALSE;
    }
    STDMETHODIMP Reset() override { consumed_ = false; return S_OK; }
    STDMETHODIMP Skip(ULONG count) override {
        if (!count) return S_OK;
        if (consumed_) return S_FALSE;
        consumed_ = true;
        return count == 1 ? S_OK : S_FALSE;
    }

private:
    ~CompositionDisplayAttributeEnum() { --g_objectCount; }
    std::atomic<ULONG> references_{1};
    bool consumed_ = false;
};

bool IsKeyDown(UINT virtualKey) {
    return (GetKeyState(static_cast<int>(virtualKey)) & 0x8000) != 0;
}

bool IsShiftKey(UINT virtualKey) {
    return virtualKey == VK_SHIFT || virtualKey == VK_LSHIFT ||
           virtualKey == VK_RSHIFT;
}

bool IsHostEditingKey(UINT virtualKey) {
    switch (virtualKey) {
        case VK_BACK:
        case VK_DELETE:
        case VK_RETURN:
        case VK_TAB:
        case VK_ESCAPE:
        case VK_LEFT:
        case VK_RIGHT:
        case VK_UP:
        case VK_DOWN:
        case VK_HOME:
        case VK_END:
        case VK_PRIOR:
        case VK_NEXT:
            return true;
        default:
            return false;
    }
}

wchar_t PrintableCharacter(const KeyEvent& event) {
    if (event.text.size() == 1 && event.text.front() >= L' ' &&
        event.text.front() <= L'~') {
        return event.text.front();
    }
    if (event.virtualKey >= 'A' && event.virtualKey <= 'Z') {
        const bool uppercase = event.shift != event.capsLock;
        return static_cast<wchar_t>((uppercase ? L'A' : L'a') +
                                    event.virtualKey - 'A');
    }
    if (event.virtualKey >= '0' && event.virtualKey <= '9') {
        static constexpr wchar_t shiftedDigits[] = L")!@#$%^&*(";
        return event.shift ? shiftedDigits[event.virtualKey - '0']
                           : static_cast<wchar_t>(event.virtualKey);
    }
    switch (event.virtualKey) {
        case VK_SPACE: return L' ';
        case VK_OEM_1: return event.shift ? L':' : L';';
        case VK_OEM_PLUS: return event.shift ? L'+' : L'=';
        case VK_OEM_COMMA: return event.shift ? L'<' : L',';
        case VK_OEM_MINUS: return event.shift ? L'_' : L'-';
        case VK_OEM_PERIOD: return event.shift ? L'>' : L'.';
        case VK_OEM_2: return event.shift ? L'?' : L'/';
        case VK_OEM_3: return event.shift ? L'~' : L'`';
        case VK_OEM_4: return event.shift ? L'{' : L'[';
        case VK_OEM_5: return event.shift ? L'|' : L'\\';
        case VK_OEM_6: return event.shift ? L'}' : L']';
        case VK_OEM_7: return event.shift ? L'"' : L'\'';
        default: return 0;
    }
}

std::wstring ToFullWidth(std::wstring text) {
    for (wchar_t& character : text) {
        if (character == L' ') {
            character = L'　';
        } else if (character >= L'!' && character <= L'~') {
            character = static_cast<wchar_t>(character - L'!' + L'！');
        }
    }
    return text;
}

const wchar_t* BuildArchitecture() {
#if defined(_M_IX86)
    return L"x86";
#elif defined(_M_X64)
    return L"x64";
#elif defined(_M_ARM64)
    return L"arm64";
#else
    return L"unknown";
#endif
}

std::wstring CurrentProcessName() {
    wchar_t path[MAX_PATH]{};
    const DWORD length = GetModuleFileNameW(nullptr, path,
                                            static_cast<DWORD>(std::size(path)));
    if (!length || length >= std::size(path)) return L"unknown";
    const wchar_t* name = wcsrchr(path, L'\\');
    return name ? name + 1 : path;
}

}  // namespace

TextService::TextService() { ++g_objectCount; }
TextService::~TextService() { --g_objectCount; }

HRESULT TextService::CreateInstance(IUnknown* outer, REFIID iid, void** object) {
    if (!object) return E_INVALIDARG;
    *object = nullptr;
    if (outer) return CLASS_E_NOAGGREGATION;
    auto* service = new (std::nothrow) TextService();
    if (!service) return E_OUTOFMEMORY;
    const HRESULT result = service->QueryInterface(iid, object);
    service->Release();
    return result;
}

STDMETHODIMP TextService::QueryInterface(REFIID iid, void** object) {
    if (!object) return E_INVALIDARG;
    *object = nullptr;
    if (iid == IID_IUnknown || iid == IID_ITfTextInputProcessor ||
        iid == IID_ITfTextInputProcessorEx) {
        *object = static_cast<ITfTextInputProcessorEx*>(this);
    } else if (iid == IID_ITfKeyEventSink) {
        *object = static_cast<ITfKeyEventSink*>(this);
    } else if (iid == IID_ITfCompositionSink) {
        *object = static_cast<ITfCompositionSink*>(this);
    } else if (iid == IID_ITfTextEditSink) {
        *object = static_cast<ITfTextEditSink*>(this);
    } else if (iid == IID_ITfThreadMgrEventSink) {
        *object = static_cast<ITfThreadMgrEventSink*>(this);
    } else if (iid == IID_ITfCompartmentEventSink) {
        *object = static_cast<ITfCompartmentEventSink*>(this);
    } else if (iid == IID_ITfDisplayAttributeProvider) {
        *object = static_cast<ITfDisplayAttributeProvider*>(this);
    } else if (iid == IID_ITfFunctionProvider) {
        *object = static_cast<ITfFunctionProvider*>(this);
    } else if (iid == IID_ITfFnConfigure || iid == IID_ITfFunction) {
        *object = static_cast<ITfFnConfigure*>(this);
    } else {
        return E_NOINTERFACE;
    }
    AddRef();
    return S_OK;
}

STDMETHODIMP_(ULONG) TextService::AddRef() { return ++referenceCount_; }
STDMETHODIMP_(ULONG) TextService::Release() {
    const ULONG remaining = --referenceCount_;
    if (!remaining) delete this;
    return remaining;
}

STDMETHODIMP TextService::Activate(ITfThreadMgr* threadManager, TfClientId clientId) {
    return ActivateEx(threadManager, clientId, 0);
}

STDMETHODIMP TextService::ActivateEx(ITfThreadMgr* threadManager, TfClientId clientId,
                                     DWORD) {
    if (!threadManager || clientId == TF_CLIENTID_NULL) return E_INVALIDARG;
    if (threadManager_) return S_OK;

    threadManager_ = threadManager;
    clientId_ = clientId;
    ComPtr<ITfCategoryMgr> categoryManager;
    if (SUCCEEDED(CoCreateInstance(CLSID_TF_CategoryMgr, nullptr,
                                   CLSCTX_INPROC_SERVER,
                                   IID_PPV_ARGS(&categoryManager)))) {
        const HRESULT attributeResult = categoryManager->RegisterGUID(
            kCompositionDisplayAttributeGuid, &compositionDisplayAttributeAtom_);
        Trace("Composition display attribute hr=0x%08lX atom=%lu",
              static_cast<unsigned long>(attributeResult),
              static_cast<unsigned long>(compositionDisplayAttributeAtom_));
    }
    engine_ = KeyKeyEngineSession::Create();
    Trace("Activate process=%ls arch=%ls client=%lu engineReady=%d",
          CurrentProcessName().c_str(), BuildArchitecture(),
          static_cast<unsigned long>(clientId_), engine_ && engine_->ready());
    const HRESULT langBarResult = initializeLangBar();
    Trace("InitializeLangBar hr=0x%08lX",
          static_cast<unsigned long>(langBarResult));
    HRESULT result = adviseSinks();
    if (SUCCEEDED(result)) {
        ComPtr<ITfDocumentMgr> focused;
        ComPtr<ITfContext> context;
        if (SUCCEEDED(threadManager_->GetFocus(&focused)) && focused &&
            SUCCEEDED(focused->GetTop(&context)) && context) {
            const HRESULT textEditResult = adviseTextEditSink(context.Get());
            Trace("AdviseTextEdit hr=0x%08lX",
                  static_cast<unsigned long>(textEditResult));
        }
        const HRESULT providerResult = adviseFunctionProvider();
        Trace("AdviseFunctionProvider hr=0x%08lX",
              static_cast<unsigned long>(providerResult));
    }
    Trace("AdviseSinks hr=0x%08lX", static_cast<unsigned long>(result));
    if (SUCCEEDED(result)) {
        setChineseMode(true);
        setFullWidthMode(false);
    }
    if (FAILED(result)) {
        unadviseFunctionProvider();
        unadviseSinks();
        uninitializeLangBar();
        engine_.reset();
        threadManager_.Reset();
        clientId_ = TF_CLIENTID_NULL;
    }
    return result;
}

STDMETHODIMP TextService::Deactivate() {
    Trace("Deactivate");
    if (!requestCommitComposition()) {
        Trace("Deactivate: composition could not be committed");
    }
    unadviseFunctionProvider();
    unadviseSinks();
    uninitializeLangBar();
    engine_.reset();
    threadManager_.Reset();
    clientId_ = TF_CLIENTID_NULL;
    compositionDisplayAttributeAtom_ = TF_INVALID_GUIDATOM;
    return S_OK;
}

HRESULT TextService::adviseSinks() {
    ComPtr<ITfKeystrokeMgr> keystrokes;
    HRESULT result = threadManager_.As(&keystrokes);
    if (FAILED(result)) return result;
    result = keystrokes->AdviseKeyEventSink(clientId_, this, TRUE);
    if (FAILED(result)) return result;

    ComPtr<ITfSource> source;
    result = threadManager_.As(&source);
    if (FAILED(result)) {
        keystrokes->UnadviseKeyEventSink(clientId_);
        return result;
    }
    result = source->AdviseSink(IID_ITfThreadMgrEventSink,
                                static_cast<ITfThreadMgrEventSink*>(this),
                                &threadManagerCookie_);
    if (FAILED(result)) keystrokes->UnadviseKeyEventSink(clientId_);
    if (SUCCEEDED(result)) {
        const HRESULT modeResult = adviseInputModeSink();
        Trace("AdviseInputMode hr=0x%08lX", static_cast<unsigned long>(modeResult));
    }
    return result;
}

void TextService::unadviseSinks() {
    if (!threadManager_) return;
    unadviseTextEditSink();
    unadviseInputModeSink();
    ComPtr<ITfKeystrokeMgr> keystrokes;
    if (SUCCEEDED(threadManager_.As(&keystrokes)) && clientId_ != TF_CLIENTID_NULL) {
        keystrokes->UnadviseKeyEventSink(clientId_);
    }
    if (threadManagerCookie_ != TF_INVALID_COOKIE) {
        ComPtr<ITfSource> source;
        if (SUCCEEDED(threadManager_.As(&source))) {
            source->UnadviseSink(threadManagerCookie_);
        }
        threadManagerCookie_ = TF_INVALID_COOKIE;
    }
}

HRESULT TextService::adviseTextEditSink(ITfContext* context) {
    if (textEditContext_.Get() == context &&
        textEditCookie_ != TF_INVALID_COOKIE) {
        return S_OK;
    }
    unadviseTextEditSink();
    if (!context) return S_OK;

    ComPtr<ITfSource> source;
    HRESULT result = context->QueryInterface(IID_PPV_ARGS(&source));
    if (FAILED(result)) return result;
    result = source->AdviseSink(IID_ITfTextEditSink,
                                static_cast<ITfTextEditSink*>(this),
                                &textEditCookie_);
    if (SUCCEEDED(result)) textEditContext_ = context;
    return result;
}

void TextService::unadviseTextEditSink() {
    if (textEditContext_ && textEditCookie_ != TF_INVALID_COOKIE) {
        ComPtr<ITfSource> source;
        if (SUCCEEDED(textEditContext_.As(&source))) {
            source->UnadviseSink(textEditCookie_);
        }
    }
    textEditCookie_ = TF_INVALID_COOKIE;
    textEditContext_.Reset();
}

HRESULT TextService::adviseInputModeSink() {
    ComPtr<ITfCompartmentMgr> manager;
    HRESULT result = threadManager_.As(&manager);
    if (FAILED(result)) return result;
    ComPtr<ITfCompartment> compartment;
    result = manager->GetCompartment(GUID_COMPARTMENT_KEYBOARD_OPENCLOSE,
                                     &compartment);
    if (FAILED(result)) return result;
    ComPtr<ITfSource> source;
    result = compartment.As(&source);
    if (FAILED(result)) return result;
    result = source->AdviseSink(IID_ITfCompartmentEventSink,
                                static_cast<ITfCompartmentEventSink*>(this),
                                &inputModeCookie_);
    if (FAILED(result)) return result;

    ComPtr<ITfCompartment> conversion;
    result = manager->GetCompartment(GUID_COMPARTMENT_KEYBOARD_INPUTMODE_CONVERSION,
                                     &conversion);
    if (FAILED(result)) return S_OK;
    ComPtr<ITfSource> conversionSource;
    result = conversion.As(&conversionSource);
    if (FAILED(result)) return S_OK;
    const HRESULT conversionResult = conversionSource->AdviseSink(
        IID_ITfCompartmentEventSink, static_cast<ITfCompartmentEventSink*>(this),
        &conversionModeCookie_);
    Trace("AdviseConversionMode hr=0x%08lX",
          static_cast<unsigned long>(conversionResult));
    return S_OK;
}

void TextService::unadviseInputModeSink() {
    if (!threadManager_) return;
    ComPtr<ITfCompartmentMgr> manager;
    ComPtr<ITfCompartment> compartment;
    ComPtr<ITfSource> source;
    if (inputModeCookie_ != TF_INVALID_COOKIE &&
        SUCCEEDED(threadManager_.As(&manager)) &&
        SUCCEEDED(manager->GetCompartment(GUID_COMPARTMENT_KEYBOARD_OPENCLOSE,
                                         &compartment)) &&
        SUCCEEDED(compartment.As(&source))) {
        source->UnadviseSink(inputModeCookie_);
    }
    inputModeCookie_ = TF_INVALID_COOKIE;

    ComPtr<ITfCompartment> conversion;
    ComPtr<ITfSource> conversionSource;
    if (conversionModeCookie_ != TF_INVALID_COOKIE && manager &&
        SUCCEEDED(manager->GetCompartment(
            GUID_COMPARTMENT_KEYBOARD_INPUTMODE_CONVERSION, &conversion)) &&
        SUCCEEDED(conversion.As(&conversionSource))) {
        conversionSource->UnadviseSink(conversionModeCookie_);
    }
    conversionModeCookie_ = TF_INVALID_COOKIE;
}

HRESULT TextService::adviseFunctionProvider() {
    if (!threadManager_) return E_UNEXPECTED;
    ComPtr<ITfSourceSingle> source;
    HRESULT result = threadManager_.As(&source);
    if (FAILED(result)) return result;
    return source->AdviseSingleSink(clientId_, IID_ITfFunctionProvider,
                                    static_cast<ITfFunctionProvider*>(this));
}

void TextService::unadviseFunctionProvider() {
    if (!threadManager_ || clientId_ == TF_CLIENTID_NULL) return;
    ComPtr<ITfSourceSingle> source;
    if (SUCCEEDED(threadManager_.As(&source))) {
        source->UnadviseSingleSink(clientId_, IID_ITfFunctionProvider);
    }
}

HRESULT TextService::initializeLangBar() {
    if (!threadManager_) return E_UNEXPECTED;
    ComPtr<ITfLangBarItemMgr> manager;
    HRESULT result = threadManager_.As(&manager);
    if (FAILED(result)) return result;

    auto* modeIcon = new (std::nothrow)
        LangBarButton(this, kLangBarInputModeGuid, LangBarButton::Kind::InputMode);
    auto* switchLanguage = new (std::nothrow) LangBarButton(
        this, kLangBarSwitchLanguageGuid, LangBarButton::Kind::SwitchLanguage);
    auto* fullHalf = new (std::nothrow)
        LangBarButton(this, kLangBarFullHalfGuid, LangBarButton::Kind::FullHalf);
    auto* settings = new (std::nothrow)
        LangBarButton(this, kLangBarSettingsGuid, LangBarButton::Kind::Settings);
    {
        std::lock_guard<std::mutex> lock(langBarMutex_);
        modeIconButton_ = modeIcon;
        switchLanguageButton_ = switchLanguage;
        fullHalfButton_ = fullHalf;
        settingsButton_ = settings;
    }
    if (!modeIcon || !switchLanguage || !fullHalf || !settings) {
        uninitializeLangBar();
        return E_OUTOFMEMORY;
    }

    LangBarButton* buttons[] = {modeIcon, switchLanguage, fullHalf, settings};
    for (LangBarButton* button : buttons) {
        result = manager->AddItem(button);
        if (FAILED(result)) {
            uninitializeLangBar();
            return result;
        }
    }
    return S_OK;
}

void TextService::uninitializeLangBar() {
    ComPtr<ITfLangBarItemMgr> manager;
    if (threadManager_) threadManager_.As(&manager);
    std::array<LangBarButton*, 4> buttons{};
    {
        std::lock_guard<std::mutex> lock(langBarMutex_);
        buttons = {modeIconButton_, switchLanguageButton_, fullHalfButton_,
                   settingsButton_};
        modeIconButton_ = nullptr;
        switchLanguageButton_ = nullptr;
        fullHalfButton_ = nullptr;
        settingsButton_ = nullptr;
    }
    for (LangBarButton* button : buttons) {
        if (!button) continue;
        if (manager) manager->RemoveItem(button);
        button->Release();
    }
}

void TextService::refreshLangBar() {
    std::array<LangBarButton*, 4> buttons{};
    {
        std::lock_guard<std::mutex> lock(langBarMutex_);
        buttons = {modeIconButton_, switchLanguageButton_, fullHalfButton_,
                   settingsButton_};
        for (LangBarButton* button : buttons) {
            if (button) button->AddRef();
        }
    }
    for (LangBarButton* button : buttons) {
        if (!button) continue;
        button->update();
        button->Release();
    }
}

void TextService::setChineseMode(bool enabled) {
    // Ending a TSF composition without clearing its range commits the visible
    // text. Clearing it here used to discard the user's unfinished sentence.
    if (!enabled && !requestCommitComposition()) {
        Trace("InputMode switch deferred: composition commit unavailable");
        setChineseMode(true);
        return;
    }
    chineseMode_ = enabled;
    shiftTogglePending_ = false;
    shiftPressedAt_ = 0;

    HRESULT result = E_FAIL;
    ComPtr<ITfCompartmentMgr> manager;
    ComPtr<ITfCompartment> compartment;
    if (threadManager_ && SUCCEEDED(threadManager_.As(&manager)) &&
        SUCCEEDED(manager->GetCompartment(GUID_COMPARTMENT_KEYBOARD_OPENCLOSE,
                                         &compartment))) {
        VARIANT value;
        VariantInit(&value);
        value.vt = VT_I4;
        value.lVal = enabled ? 1 : 0;
        result = compartment->SetValue(clientId_, &value);
    }
    Trace("InputMode chinese=%d hr=0x%08lX", enabled,
          static_cast<unsigned long>(result));
    refreshLangBar();
}

void TextService::toggleChineseMode() { setChineseMode(!chineseMode_); }

void TextService::setFullWidthMode(bool enabled) {
    fullWidthMode_ = enabled;
    HRESULT result = E_FAIL;
    ComPtr<ITfCompartmentMgr> manager;
    ComPtr<ITfCompartment> compartment;
    if (threadManager_ && SUCCEEDED(threadManager_.As(&manager)) &&
        SUCCEEDED(manager->GetCompartment(
            GUID_COMPARTMENT_KEYBOARD_INPUTMODE_CONVERSION, &compartment))) {
        LONG mode = 0;
        VARIANT current;
        VariantInit(&current);
        if (SUCCEEDED(compartment->GetValue(&current)) && current.vt == VT_I4) {
            mode = current.lVal;
        }
        VariantClear(&current);
        if (enabled) {
            mode |= TF_CONVERSIONMODE_FULLSHAPE;
        } else {
            mode &= ~TF_CONVERSIONMODE_FULLSHAPE;
        }
        VARIANT value;
        VariantInit(&value);
        value.vt = VT_I4;
        value.lVal = mode;
        result = compartment->SetValue(clientId_, &value);
    }
    Trace("InputWidth full=%d hr=0x%08lX", enabled,
          static_cast<unsigned long>(result));
    refreshLangBar();
}

void TextService::toggleFullWidthMode() { setFullWidthMode(!fullWidthMode_); }

bool TextService::selectInputMethod(const char* identifier) {
    if (!IsInputMethodVisible(identifier)) return false;
    if (CurrentInputMethod() != identifier) {
        if (!requestCommitComposition()) return false;
        if (!SelectInputMethod(identifier)) return false;
    }
    if (!chineseMode_) setChineseMode(true);
    refreshLangBar();
    return true;
}

KeyEvent TextService::translateKey(WPARAM wparam, LPARAM lparam) const {
    KeyEvent event;
    event.virtualKey = static_cast<UINT>(wparam);
    event.shift = IsKeyDown(VK_SHIFT);
    event.control = IsKeyDown(VK_CONTROL);
    event.alt = IsKeyDown(VK_MENU);
    event.capsLock = (GetKeyState(VK_CAPITAL) & 1) != 0;
    event.numLock = (GetKeyState(VK_NUMLOCK) & 1) != 0;

    BYTE keyboardState[256]{};
    if (!GetKeyboardState(keyboardState)) return event;
    wchar_t characters[8]{};
    const UINT scanCode = static_cast<UINT>((lparam >> 16) & 0xff);
    const int length = ToUnicodeEx(event.virtualKey, scanCode, keyboardState,
                                   characters, static_cast<int>(std::size(characters)),
                                   4, GetKeyboardLayout(0));
    if (length > 0) event.text.assign(characters, characters + length);
    return event;
}

bool TextService::isPotentialKey(const KeyEvent& event) const {
    if (isFullWidthCharacterKey(event)) return true;
    if (!chineseMode_ || !engine_ || !engine_->ready()) return false;
    // Outside a real TSF composition, application editing/navigation keys
    // belong to the host. Returning TRUE from OnTestKeyDown alone is enough
    // for some hosts to lose the key even if OnKeyDown later returns FALSE.
    if (!composition_ && !candidateActive_ && IsHostEditingKey(event.virtualKey)) {
        return false;
    }
    if (IsInputMethodControlKey(event)) return true;
    return engine_->wantsKey(event);
}

bool TextService::isModeToggleKey(const KeyEvent& event) const {
    if (!event.control || event.alt) return false;
    if (event.virtualKey == VK_SPACE) return true;
    return event.virtualKey == VK_OEM_5 && !event.shift &&
           LoadFrontendSettings().toggleWithControlBackslash;
}

bool TextService::isWidthToggleKey(const KeyEvent& event) const {
    return event.virtualKey == VK_SPACE && event.shift && !event.control &&
           !event.alt;
}

bool TextService::isFullWidthCharacterKey(const KeyEvent& event) const {
    return fullWidthMode_ && !event.control && !event.alt &&
           PrintableCharacter(event) != 0;
}

STDMETHODIMP TextService::OnSetFocus(BOOL foreground) {
    if (!foreground) {
        shiftTogglePending_ = false;
        if (!requestCommitComposition()) {
            Trace("Input focus lost: composition could not be committed");
        }
    }
    return S_OK;
}

STDMETHODIMP TextService::OnTestKeyDown(ITfContext*, WPARAM wparam, LPARAM lparam,
                                        BOOL* eaten) {
    if (!eaten) return E_INVALIDARG;
    const KeyEvent event = translateKey(wparam, lparam);
    if (!IsShiftKey(event.virtualKey)) {
        shiftTogglePending_ = false;
        shiftPressedAt_ = 0;
    }
    if (IsShiftKey(event.virtualKey) && !event.control && !event.alt) {
        // TestKeyDown must opt in before TSF calls OnKeyDown. OnKeyDown itself
        // leaves the modifier uneaten so Shift remains available to the host.
        *eaten = TRUE;
        return S_OK;
    }
    *eaten = isModeToggleKey(event) || isWidthToggleKey(event) ||
             isPotentialKey(event);
    Trace("TestKeyDown vk=%u textLen=%zu shift=%d ctrl=%d alt=%d caps=%d mode=%d eaten=%d",
          event.virtualKey, event.text.size(), event.shift, event.control,
          event.alt, event.capsLock, chineseMode_, *eaten);
    return S_OK;
}

STDMETHODIMP TextService::OnTestKeyUp(ITfContext*, WPARAM wparam, LPARAM,
                                      BOOL* eaten) {
    if (!eaten) return E_INVALIDARG;
    *eaten = IsShiftKey(static_cast<UINT>(wparam)) && shiftTogglePending_ &&
              !IsKeyDown(VK_CONTROL) && !IsKeyDown(VK_MENU) &&
              GetTickCount() - shiftPressedAt_ <= kShiftTapTimeoutMilliseconds;
    if (IsShiftKey(static_cast<UINT>(wparam)) && !*eaten) {
        shiftTogglePending_ = false;
        shiftPressedAt_ = 0;
    }
    return S_OK;
}

STDMETHODIMP TextService::OnKeyDown(ITfContext* context, WPARAM wparam, LPARAM lparam,
                                    BOOL* eaten) {
    if (!context || !eaten) return E_INVALIDARG;
    *eaten = FALSE;
    KeyEvent event = translateKey(wparam, lparam);
    if (IsShiftKey(event.virtualKey) && !event.control && !event.alt) {
        if (!shiftTogglePending_) shiftPressedAt_ = GetTickCount();
        shiftTogglePending_ = true;
        return S_OK;
    }
    shiftTogglePending_ = false;
    if (isModeToggleKey(event)) {
        toggleChineseMode();
        *eaten = TRUE;
        return S_OK;
    }
    if (isWidthToggleKey(event)) {
        toggleFullWidthMode();
        *eaten = TRUE;
        return S_OK;
    }
    if (!isPotentialKey(event)) return S_OK;
    const UINT virtualKey = event.virtualKey;
    const size_t textLength = event.text.size();

    auto* session = new (std::nothrow) KeyEditSession(this, context, std::move(event));
    if (!session) return E_OUTOFMEMORY;
    HRESULT editResult = E_FAIL;
    HRESULT requestResult = context->RequestEditSession(
        clientId_, session, TF_ES_SYNC | TF_ES_READWRITE, &editResult);
    if (requestResult == TF_E_SYNCHRONOUS || requestResult == TF_E_LOCKED ||
        (SUCCEEDED(requestResult) && editResult == TF_E_SYNCHRONOUS)) {
        editResult = E_FAIL;
        requestResult = context->RequestEditSession(
            clientId_, session, TF_ES_ASYNCDONTCARE | TF_ES_READWRITE,
            &editResult);
        if (SUCCEEDED(requestResult) && SUCCEEDED(editResult)) {
            // The edit session may run after this callback. We already promised
            // TSF to handle this key, and KeyEditSession keeps the service alive.
            *eaten = TRUE;
        }
    } else if (SUCCEEDED(requestResult) && SUCCEEDED(editResult)) {
        *eaten = session->handled();
    }
    Trace("KeyDown vk=%u textLen=%zu request=0x%08lX edit=0x%08lX eaten=%d mode=%d",
          virtualKey, textLength, static_cast<unsigned long>(requestResult),
          static_cast<unsigned long>(editResult), *eaten, chineseMode_);
    session->Release();
    // ITfKeyEventSink callbacks must not leak a transient context-lock error
    // back to TSF. If no edit session was accepted, leave the key uneaten so
    // the application can handle it normally.
    return S_OK;
}

STDMETHODIMP TextService::OnKeyUp(ITfContext*, WPARAM wparam, LPARAM, BOOL* eaten) {
    if (!eaten) return E_INVALIDARG;
    *eaten = FALSE;
    if (IsShiftKey(static_cast<UINT>(wparam)) && shiftTogglePending_ &&
        !IsKeyDown(VK_CONTROL) && !IsKeyDown(VK_MENU) &&
        GetTickCount() - shiftPressedAt_ <= kShiftTapTimeoutMilliseconds) {
        shiftTogglePending_ = false;
        shiftPressedAt_ = 0;
        toggleChineseMode();
        *eaten = TRUE;
    } else if (IsShiftKey(static_cast<UINT>(wparam))) {
        shiftTogglePending_ = false;
        shiftPressedAt_ = 0;
    }
    return S_OK;
}

STDMETHODIMP TextService::OnPreservedKey(ITfContext*, REFGUID, BOOL* eaten) {
    if (!eaten) return E_INVALIDARG;
    *eaten = FALSE;
    return S_OK;
}

HRESULT TextService::processKey(TfEditCookie editCookie, ITfContext* context,
                                const KeyEvent& event, bool* handled) {
    if (!context || !handled) return E_INVALIDARG;
    if (composition_ && compositionContext_.Get() != context) {
        if (pendingModeCommit_) {
            *handled = false;
            return S_OK;
        }
        // A focus/context switch can happen without giving the old context a
        // writable edit cookie. Detach it before processing the new key so an
        // old composition cannot permanently block the new document.
        abandonComposition();
    }
    EngineResult result;
    if (!chineseMode_ && isFullWidthCharacterKey(event)) {
        result.handled = true;
        result.committedText = ToFullWidth(std::wstring(1, PrintableCharacter(event)));
    } else {
        if (!engine_) return E_UNEXPECTED;
        result = engine_->handleKey(event);
        if (fullWidthMode_ && !result.committedText.empty()) {
            result.committedText = ToFullWidth(std::move(result.committedText));
        }
    }
    *handled = result.handled;
    Trace("Engine vk=%u handled=%d commitLen=%zu compositionLen=%zu candidates=%zu",
          event.virtualKey, result.handled, result.committedText.size(),
          result.compositionText.size(), result.candidates.size());
    if (!result.handled) {
        // Around filters can dismiss a candidate panel while deliberately
        // passing the key through to the host (for example, an arrow key that
        // closes associated-phrase suggestions). Keep the native candidate
        // window in sync even though no composition edit is required.
        updateCandidateWindow(editCookie, context, result);
        return S_OK;
    }
    if (result.beep && LoadFrontendSettings().playSoundOnTypingError) {
        MessageBeep(MB_OK);
    }
    const HRESULT status = updateComposition(editCookie, context, result);
    Trace("UpdateComposition hr=0x%08lX", static_cast<unsigned long>(status));
    if (FAILED(status)) {
        OutputDebugStringW(L"琦琦輸入法 TSF: composition update failed; resetting state.\n");
        *handled = false;
        abandonComposition();
        return S_OK;
    }
    return S_OK;
}

HRESULT TextService::ensureComposition(TfEditCookie editCookie, ITfContext* context) {
    if (composition_) return compositionContext_.Get() == context ? S_OK : E_UNEXPECTED;

    ComPtr<ITfInsertAtSelection> insertion;
    HRESULT result = context->QueryInterface(IID_PPV_ARGS(&insertion));
    if (FAILED(result)) {
        Trace("EnsureComposition QueryInsert hr=0x%08lX",
              static_cast<unsigned long>(result));
        return result;
    }
    ComPtr<ITfRange> range;
    result = insertion->InsertTextAtSelection(editCookie, TF_IAS_QUERYONLY,
                                               nullptr, 0, &range);
    if (FAILED(result)) {
        Trace("EnsureComposition QueryRange hr=0x%08lX",
              static_cast<unsigned long>(result));
        return result;
    }

    ComPtr<ITfContextComposition> compositionContext;
    result = context->QueryInterface(IID_PPV_ARGS(&compositionContext));
    if (FAILED(result)) {
        Trace("EnsureComposition QueryComposition hr=0x%08lX",
              static_cast<unsigned long>(result));
        return result;
    }
    result = compositionContext->StartComposition(editCookie, range.Get(), this,
                                                   &composition_);
    Trace("EnsureComposition Start hr=0x%08lX composition=%d",
          static_cast<unsigned long>(result), composition_ != nullptr);
    if (SUCCEEDED(result)) compositionContext_ = context;
    return result;
}

HRESULT TextService::replaceCompositionText(TfEditCookie editCookie, ITfContext* context,
                                            const std::wstring& text, LONG cursor) {
    HRESULT result = ensureComposition(editCookie, context);
    if (FAILED(result)) return result;
    ComPtr<ITfRange> range;
    result = composition_->GetRange(&range);
    if (FAILED(result)) {
        Trace("ReplaceComposition GetRange hr=0x%08lX",
              static_cast<unsigned long>(result));
        return result;
    }
    result = range->SetText(editCookie, 0, text.data(), static_cast<LONG>(text.size()));
    if (FAILED(result)) {
        Trace("ReplaceComposition SetText hr=0x%08lX",
              static_cast<unsigned long>(result));
        return result;
    }

    if (compositionDisplayAttributeAtom_ != TF_INVALID_GUIDATOM) {
        ComPtr<ITfProperty> property;
        const HRESULT propertyResult = context->GetProperty(GUID_PROP_ATTRIBUTE,
                                                             &property);
        if (SUCCEEDED(propertyResult)) {
            VARIANT value;
            VariantInit(&value);
            value.vt = VT_I4;
            value.lVal = static_cast<LONG>(compositionDisplayAttributeAtom_);
            const HRESULT attributeResult = property->SetValue(editCookie, range.Get(),
                                                               &value);
            Trace("Composition underline hr=0x%08lX",
                  static_cast<unsigned long>(attributeResult));
        }
    }

    ComPtr<ITfRange> selection;
    result = range->Clone(&selection);
    if (FAILED(result)) {
        Trace("ReplaceComposition Clone hr=0x%08lX",
              static_cast<unsigned long>(result));
        return result;
    }
    selection->Collapse(editCookie, TF_ANCHOR_START);
    LONG shifted = 0;
    selection->ShiftEnd(editCookie,
                        std::clamp<LONG>(cursor, 0, static_cast<LONG>(text.size())),
                        &shifted, nullptr);
    selection->Collapse(editCookie, TF_ANCHOR_END);
    TF_SELECTION tfSelection{};
    tfSelection.range = selection.Get();
    tfSelection.style.ase = TF_AE_NONE;
    tfSelection.style.fInterimChar = FALSE;
    result = context->SetSelection(editCookie, 1, &tfSelection);
    Trace("ReplaceComposition textLen=%zu cursor=%ld selectionHr=0x%08lX",
          text.size(), cursor, static_cast<unsigned long>(result));
    return result;
}

HRESULT TextService::commitText(TfEditCookie editCookie, ITfContext* context,
                                const std::wstring& text) {
    if (text.empty()) return S_OK;
    if (composition_ && compositionContext_.Get() == context) {
        ComPtr<ITfRange> range;
        HRESULT result = composition_->GetRange(&range);
        if (FAILED(result)) return result;
        result = range->SetText(editCookie, 0, text.data(), static_cast<LONG>(text.size()));
        if (FAILED(result)) return result;

        // SetText does not guarantee that the host moves its selection. Keep
        // the caret explicitly at the end of the committed range before
        // ending the composition; otherwise the next composition can start
        // in front of the character just committed (for example, 囉哈).
        result = range->Collapse(editCookie, TF_ANCHOR_END);
        if (FAILED(result)) return result;
        TF_SELECTION selection{};
        selection.range = range.Get();
        selection.style.ase = TF_AE_NONE;
        selection.style.fInterimChar = FALSE;
        result = context->SetSelection(editCookie, 1, &selection);
        Trace("CommitComposition textLen=%zu selectionHr=0x%08lX", text.size(),
              static_cast<unsigned long>(result));
        if (FAILED(result)) return result;
        return endComposition(editCookie, false);
    }

    ComPtr<ITfInsertAtSelection> insertion;
    HRESULT result = context->QueryInterface(IID_PPV_ARGS(&insertion));
    if (FAILED(result)) return result;
    ComPtr<ITfRange> insertedRange;
    result = insertion->InsertTextAtSelection(editCookie, 0, text.data(),
                                              static_cast<LONG>(text.size()),
                                              &insertedRange);
    if (FAILED(result) || !insertedRange) return result;
    result = insertedRange->Collapse(editCookie, TF_ANCHOR_END);
    if (FAILED(result)) return result;
    TF_SELECTION selection{};
    selection.range = insertedRange.Get();
    selection.style.ase = TF_AE_NONE;
    selection.style.fInterimChar = FALSE;
    return context->SetSelection(editCookie, 1, &selection);
}

HRESULT TextService::endComposition(TfEditCookie editCookie, bool clearText) {
    if (!composition_) return S_OK;
    ComPtr<ITfRange> range;
    if (compositionContext_ && SUCCEEDED(composition_->GetRange(&range)) && range) {
        ComPtr<ITfProperty> property;
        if (SUCCEEDED(compositionContext_->GetProperty(GUID_PROP_ATTRIBUTE,
                                                       &property))) {
            property->Clear(editCookie, range.Get());
        }
    }
    if (clearText) {
        if (range) {
            range->SetText(editCookie, 0, nullptr, 0);
        }
    }
    endingComposition_ = true;
    ComPtr<ITfComposition> completing = composition_;
    const HRESULT result = completing->EndComposition(editCookie);
    endingComposition_ = false;
    if (SUCCEEDED(result)) {
        composition_.Reset();
        compositionContext_.Reset();
    }
    return result;
}

bool TextService::requestCommitComposition() {
    if (pendingModeCommit_) return true;
    if (!composition_) {
        candidateWindow_.hide();
        candidateActive_ = false;
        candidateAnchor_.Reset();
        if (engine_) engine_->reset();
        return true;
    }
    if (!compositionContext_ || clientId_ == TF_CLIENTID_NULL) return false;

    auto* session = new (std::nothrow)
        CommitModeSwitchEditSession(this, compositionContext_.Get());
    if (!session) return false;
    pendingModeCommit_ = true;
    HRESULT editResult = E_FAIL;
    HRESULT requestResult = compositionContext_->RequestEditSession(
        clientId_, session, TF_ES_SYNC | TF_ES_READWRITE, &editResult);
    if (requestResult == TF_E_SYNCHRONOUS || requestResult == TF_E_LOCKED ||
        (SUCCEEDED(requestResult) && editResult == TF_E_SYNCHRONOUS)) {
        editResult = E_FAIL;
        requestResult = compositionContext_->RequestEditSession(
            clientId_, session, TF_ES_ASYNCDONTCARE | TF_ES_READWRITE,
            &editResult);
    }
    const bool accepted = SUCCEEDED(requestResult) && SUCCEEDED(editResult);
    if (!accepted) pendingModeCommit_ = false;
    Trace("ModeCommit request=0x%08lX edit=0x%08lX accepted=%d",
          static_cast<unsigned long>(requestResult),
          static_cast<unsigned long>(editResult), accepted);
    session->Release();
    return accepted;
}

HRESULT TextService::commitCompositionForModeSwitch(TfEditCookie editCookie,
                                                     ITfContext* context) {
    HRESULT result = S_OK;
    if (composition_ && compositionContext_.Get() == context) {
        ComPtr<ITfRange> range;
        result = composition_->GetRange(&range);
        if (SUCCEEDED(result)) {
            ComPtr<ITfRange> caret;
            result = range->Clone(&caret);
            if (SUCCEEDED(result)) result = caret->Collapse(editCookie, TF_ANCHOR_END);
            if (SUCCEEDED(result)) {
                TF_SELECTION selection{};
                selection.range = caret.Get();
                selection.style.ase = TF_AE_NONE;
                selection.style.fInterimChar = FALSE;
                result = context->SetSelection(editCookie, 1, &selection);
            }
            if (SUCCEEDED(result)) result = endComposition(editCookie, false);
        }
    }
    if (SUCCEEDED(result)) {
        candidateWindow_.hide();
        candidateActive_ = false;
        candidateAnchor_.Reset();
        if (engine_) engine_->reset();
    }
    pendingModeCommit_ = false;
    if (FAILED(result) && !chineseMode_ && threadManager_) {
        setChineseMode(true);
    }
    Trace("ModeCommit complete hr=0x%08lX",
          static_cast<unsigned long>(result));
    return result;
}

HRESULT TextService::terminateComposition(TfEditCookie editCookie) {
    candidateWindow_.hide();
    candidateActive_ = false;
    candidateAnchor_.Reset();
    if (engine_) engine_->reset();
    return endComposition(editCookie, true);
}

void TextService::abandonComposition() {
    candidateWindow_.hide();
    candidateActive_ = false;
    candidateAnchor_.Reset();
    if (engine_) engine_->reset();

    ComPtr<ITfComposition> oldComposition = composition_;
    ComPtr<ITfContext> oldContext = compositionContext_;
    composition_.Reset();
    compositionContext_.Reset();

    if (!oldComposition || !oldContext || clientId_ == TF_CLIENTID_NULL) return;
    auto* session = new (std::nothrow) TerminateEditSession(oldComposition.Get());
    if (!session) return;
    HRESULT editResult = E_FAIL;
    oldContext->RequestEditSession(
        clientId_, session, TF_ES_ASYNCDONTCARE | TF_ES_READWRITE, &editResult);
    session->Release();
}

HRESULT TextService::updateComposition(TfEditCookie editCookie, ITfContext* context,
                                       const EngineResult& result) {
    HRESULT status = commitText(editCookie, context, result.committedText);
    if (FAILED(status)) return status;

    if (!result.compositionText.empty()) {
        status = replaceCompositionText(editCookie, context, result.compositionText,
                                        result.compositionCursor);
        if (FAILED(status)) return status;
    } else if (composition_ && result.committedText.empty()) {
        status = endComposition(editCookie, true);
        if (FAILED(status)) return status;
    }
    updateCandidateWindow(editCookie, context, result);
    return S_OK;
}

void TextService::updateCandidateWindow(TfEditCookie editCookie, ITfContext* context,
                                        const EngineResult& result) {
    if (!result.candidatesVisible || result.candidates.empty()) {
        candidateWindow_.hide();
        candidateActive_ = false;
        candidateAnchor_.Reset();
        Trace("Candidate active=0");
        return;
    }

    ComPtr<ITfRange> range;
    if (composition_) composition_->GetRange(&range);
    if (!range) {
        TF_SELECTION selection{};
        ULONG fetched = 0;
        if (FAILED(context->GetSelection(editCookie, TF_DEFAULT_SELECTION, 1,
                                         &selection, &fetched)) || !fetched) {
            candidateWindow_.hide();
            candidateActive_ = false;
            candidateAnchor_.Reset();
            return;
        }
        range.Attach(selection.range);
    }

    ComPtr<ITfContextView> view;
    if (FAILED(context->GetActiveView(&view))) {
        candidateWindow_.hide();
        candidateActive_ = false;
        candidateAnchor_.Reset();
        return;
    }
    RECT textRect{};
    BOOL clipped = FALSE;
    HWND owner = nullptr;
    if (FAILED(view->GetTextExt(editCookie, range.Get(), &textRect, &clipped)) ||
        FAILED(view->GetWnd(&owner))) {
        candidateWindow_.hide();
        candidateActive_ = false;
        candidateAnchor_.Reset();
        return;
    }
    candidateWindow_.show(owner, textRect, result.candidates,
                          result.highlightedCandidate);
    candidateActive_ = true;
    candidateAnchor_.Reset();
    if (!composition_ && SUCCEEDED(range->Clone(&candidateAnchor_))) {
        candidateAnchor_->Collapse(editCookie, TF_ANCHOR_END);
    }
    Trace("Candidate active=1 count=%zu", result.candidates.size());
}

bool TextService::selectionMatchesTrackedState(TfEditCookie editCookie,
                                               ITfContext* context) const {
    if (!context) return false;

    TF_SELECTION selection{};
    ULONG fetched = 0;
    if (FAILED(context->GetSelection(editCookie, TF_DEFAULT_SELECTION, 1,
                                     &selection, &fetched)) || !fetched) {
        return false;
    }
    ComPtr<ITfRange> selected;
    selected.Attach(selection.range);
    BOOL empty = FALSE;
    if (FAILED(selected->IsEmpty(editCookie, &empty)) || !empty) return false;

    ComPtr<ITfRange> tracked;
    bool allowsPositionInsideRange = false;
    if (composition_ && compositionContext_.Get() == context) {
        if (FAILED(composition_->GetRange(&tracked)) || !tracked) return false;
        allowsPositionInsideRange = true;
    } else if (candidateActive_ && candidateAnchor_) {
        tracked = candidateAnchor_;
    } else {
        return true;
    }

    LONG comparedWithStart = 0;
    LONG comparedWithEnd = 0;
    if (FAILED(selected->CompareStart(editCookie, tracked.Get(), TF_ANCHOR_START,
                                      &comparedWithStart)) ||
        FAILED(selected->CompareStart(editCookie, tracked.Get(), TF_ANCHOR_END,
                                      &comparedWithEnd))) {
        return false;
    }
    if (allowsPositionInsideRange) {
        return comparedWithStart >= 0 && comparedWithEnd <= 0;
    }
    return comparedWithStart == 0;
}

STDMETHODIMP TextService::OnEndEdit(ITfContext* context, TfEditCookie editCookie,
                                    ITfEditRecord* editRecord) {
    if (!context || !editRecord ||
        (!composition_ && !candidateActive_)) {
        return S_OK;
    }

    BOOL selectionChanged = FALSE;
    if (FAILED(editRecord->GetSelectionStatus(&selectionChanged)) ||
        !selectionChanged) {
        return S_OK;
    }
    if (!selectionMatchesTrackedState(editCookie, context)) {
        if (!pendingModeCommit_) {
            Trace("Selection left active input state; abandoning composition");
            abandonComposition();
        }
    }
    return S_OK;
}

STDMETHODIMP TextService::OnCompositionTerminated(TfEditCookie,
                                                   ITfComposition* composition) {
    if (composition_.Get() == composition) {
        composition_.Reset();
        compositionContext_.Reset();
        if (!endingComposition_) {
            candidateWindow_.hide();
            candidateActive_ = false;
            candidateAnchor_.Reset();
            if (engine_) engine_->reset();
        }
    }
    return S_OK;
}

STDMETHODIMP TextService::OnInitDocumentMgr(ITfDocumentMgr*) { return S_OK; }
STDMETHODIMP TextService::OnUninitDocumentMgr(ITfDocumentMgr* documentManager) {
    if (compositionContext_ && !pendingModeCommit_) {
        ComPtr<ITfDocumentMgr> owner;
        if (SUCCEEDED(compositionContext_->GetDocumentMgr(&owner)) &&
            owner.Get() == documentManager) {
            requestCommitComposition();
        }
    }
    if (textEditContext_) {
        ComPtr<ITfDocumentMgr> owner;
        if (SUCCEEDED(textEditContext_->GetDocumentMgr(&owner)) &&
            owner.Get() == documentManager) {
            if (!pendingModeCommit_) requestCommitComposition();
            unadviseTextEditSink();
        }
    }
    return S_OK;
}
STDMETHODIMP TextService::OnSetFocus(ITfDocumentMgr* focused, ITfDocumentMgr*) {
    ComPtr<ITfContext> focusedContext;
    if (focused) focused->GetTop(&focusedContext);
    if ((composition_ || candidateActive_) &&
        textEditContext_.Get() != focusedContext.Get() && !pendingModeCommit_) {
        if (!requestCommitComposition()) {
            Trace("Document focus changed: composition could not be committed");
        }
    }
    const HRESULT textEditResult = adviseTextEditSink(focusedContext.Get());
    Trace("Focus AdviseTextEdit hr=0x%08lX",
          static_cast<unsigned long>(textEditResult));
    if (!focused) {
        candidateWindow_.hide();
        candidateActive_ = false;
        candidateAnchor_.Reset();
        if (engine_) engine_->reset();
    }
    return S_OK;
}
STDMETHODIMP TextService::OnPushContext(ITfContext* context) {
    if ((composition_ || candidateActive_) && textEditContext_.Get() != context &&
        !pendingModeCommit_) {
        requestCommitComposition();
    }
    const HRESULT result = adviseTextEditSink(context);
    Trace("PushContext AdviseTextEdit hr=0x%08lX",
          static_cast<unsigned long>(result));
    // A host that does not expose ITfSource still needs the context push to
    // complete; key processing remains usable without selection tracking.
    return S_OK;
}
STDMETHODIMP TextService::OnPopContext(ITfContext* context) {
    if (compositionContext_.Get() == context) {
        if (!pendingModeCommit_) requestCommitComposition();
    } else {
        candidateWindow_.hide();
        candidateActive_ = false;
        candidateAnchor_.Reset();
        if (engine_) engine_->reset();
    }
    if (textEditContext_.Get() == context) {
        unadviseTextEditSink();
        ComPtr<ITfDocumentMgr> focused;
        ComPtr<ITfContext> top;
        if (threadManager_ && SUCCEEDED(threadManager_->GetFocus(&focused)) &&
            focused && SUCCEEDED(focused->GetTop(&top)) && top.Get() != context) {
            adviseTextEditSink(top.Get());
        }
    }
    return S_OK;
}

STDMETHODIMP TextService::OnChange(REFGUID guid) {
    if (!threadManager_) return S_OK;

    if (guid == GUID_COMPARTMENT_KEYBOARD_INPUTMODE_CONVERSION) {
        ComPtr<ITfCompartmentMgr> manager;
        ComPtr<ITfCompartment> compartment;
        VARIANT value;
        VariantInit(&value);
        if (SUCCEEDED(threadManager_.As(&manager)) &&
            SUCCEEDED(manager->GetCompartment(
                GUID_COMPARTMENT_KEYBOARD_INPUTMODE_CONVERSION, &compartment)) &&
            SUCCEEDED(compartment->GetValue(&value)) && value.vt == VT_I4) {
            fullWidthMode_ =
                (value.lVal & static_cast<LONG>(TF_CONVERSIONMODE_FULLSHAPE)) != 0;
            refreshLangBar();
            Trace("InputWidth changed full=%d", fullWidthMode_);
        }
        VariantClear(&value);
        return S_OK;
    }

    if (guid != GUID_COMPARTMENT_KEYBOARD_OPENCLOSE) return S_OK;

    ComPtr<ITfCompartmentMgr> manager;
    ComPtr<ITfCompartment> compartment;
    VARIANT value;
    VariantInit(&value);
    if (SUCCEEDED(threadManager_.As(&manager)) &&
        SUCCEEDED(manager->GetCompartment(GUID_COMPARTMENT_KEYBOARD_OPENCLOSE,
                                         &compartment)) &&
        SUCCEEDED(compartment->GetValue(&value)) && value.vt == VT_I4) {
        const bool enabled = value.lVal != 0;
        if (chineseMode_ != enabled) {
            setChineseMode(enabled);
        }
        Trace("InputMode changed chinese=%d", chineseMode_);
    }
    VariantClear(&value);
    return S_OK;
}

STDMETHODIMP TextService::EnumDisplayAttributeInfo(
    IEnumTfDisplayAttributeInfo** items) {
    if (!items) return E_INVALIDARG;
    *items = new (std::nothrow) CompositionDisplayAttributeEnum();
    return *items ? S_OK : E_OUTOFMEMORY;
}

STDMETHODIMP TextService::GetDisplayAttributeInfo(
    REFGUID guid, ITfDisplayAttributeInfo** info) {
    if (!info) return E_INVALIDARG;
    *info = nullptr;
    if (guid != kCompositionDisplayAttributeGuid) return E_INVALIDARG;
    *info = new (std::nothrow) CompositionDisplayAttributeInfo();
    return *info ? S_OK : E_OUTOFMEMORY;
}

STDMETHODIMP TextService::GetType(GUID* guid) {
    if (!guid) return E_INVALIDARG;
    *guid = kTextServiceClsid;
    return S_OK;
}

STDMETHODIMP TextService::GetDescription(BSTR* description) {
    if (!description) return E_INVALIDARG;
    *description = SysAllocString(kTextServiceDescription);
    return *description ? S_OK : E_OUTOFMEMORY;
}

STDMETHODIMP TextService::GetFunction(REFGUID guid, REFIID iid,
                                      IUnknown** object) {
    if (!object) return E_INVALIDARG;
    *object = nullptr;
    if (guid != GUID_NULL || iid != IID_ITfFnConfigure) return E_NOINTERFACE;
    return QueryInterface(iid, reinterpret_cast<void**>(object));
}

STDMETHODIMP TextService::GetDisplayName(BSTR* name) {
    if (!name) return E_INVALIDARG;
    *name = SysAllocString(L"琦琦輸入法設定");
    return *name ? S_OK : E_OUTOFMEMORY;
}

HRESULT TextService::openSettings(HWND parent) const {
    // A text host can keep an older DLL loaded after a side-by-side upgrade.
    // Resolve the active installation first so its settings app still opens.
    wchar_t installedDirectory[32768]{};
    DWORD installedDirectoryBytes = sizeof(installedDirectory);
    if (RegGetValueW(
            HKEY_LOCAL_MACHINE,
            L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\chichi77KeyKey",
            L"VersionLocation", RRF_RT_REG_SZ | RRF_SUBKEY_WOW6464KEY, nullptr,
            installedDirectory, &installedDirectoryBytes) == ERROR_SUCCESS &&
        installedDirectory[0]) {
        std::wstring installedPath = installedDirectory;
        if (installedPath.back() != L'\\' && installedPath.back() != L'/')
            installedPath += L'\\';
        installedPath += L"KeyKeySettings.exe";
        const DWORD attributes = GetFileAttributesW(installedPath.c_str());
        if (attributes != INVALID_FILE_ATTRIBUTES &&
            !(attributes & FILE_ATTRIBUTE_DIRECTORY)) {
            const HINSTANCE launched = ShellExecuteW(
                parent, L"open", installedPath.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
            const INT_PTR code = reinterpret_cast<INT_PTR>(launched);
            return code > 32 ? S_OK : HRESULT_FROM_WIN32(static_cast<DWORD>(code));
        }
    }

    // A development DLL can be registered without an installer entry.
    std::wstring modulePath(32768, L'\0');
    const DWORD length = GetModuleFileNameW(g_module, modulePath.data(),
                                            static_cast<DWORD>(modulePath.size()));
    if (!length || length >= modulePath.size()) return HRESULT_FROM_WIN32(GetLastError());
    modulePath.resize(length);
    const size_t separator = modulePath.find_last_of(L"\\/");
    if (separator == std::wstring::npos) return E_UNEXPECTED;
    modulePath.resize(separator + 1);
    modulePath += L"KeyKeySettings.exe";

    const HINSTANCE launched = ShellExecuteW(parent, L"open", modulePath.c_str(),
                                             nullptr, nullptr, SW_SHOWNORMAL);
    const INT_PTR code = reinterpret_cast<INT_PTR>(launched);
    return code > 32 ? S_OK : HRESULT_FROM_WIN32(static_cast<DWORD>(code));
}

STDMETHODIMP TextService::Show(HWND parent, LANGID language, REFGUID profile) {
    UNREFERENCED_PARAMETER(language);
    UNREFERENCED_PARAMETER(profile);
    return openSettings(parent);
}

}  // namespace KeyKey::WindowsTsf
