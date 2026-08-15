#include "TextService.h"

#include <algorithm>
#include <iterator>
#include <new>
#include <shellapi.h>
#include <utility>

#include "Diagnostics.h"
#include "Guids.h"
#include "LangBarButton.h"
#include "ModuleState.h"

namespace KeyKey::WindowsTsf {
namespace {

using Microsoft::WRL::ComPtr;

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

bool IsKeyDown(UINT virtualKey) {
    return (GetKeyState(static_cast<int>(virtualKey)) & 0x8000) != 0;
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
    } else if (iid == IID_ITfThreadMgrEventSink) {
        *object = static_cast<ITfThreadMgrEventSink*>(this);
    } else if (iid == IID_ITfCompartmentEventSink) {
        *object = static_cast<ITfCompartmentEventSink*>(this);
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
    engine_ = KeyKeyEngineSession::Create();
    Trace("Activate client=%lu engineReady=%d", static_cast<unsigned long>(clientId_),
          engine_ && engine_->ready());
    const HRESULT langBarResult = initializeLangBar();
    Trace("InitializeLangBar hr=0x%08lX",
          static_cast<unsigned long>(langBarResult));
    HRESULT result = adviseSinks();
    if (SUCCEEDED(result)) {
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
    abandonComposition();
    unadviseFunctionProvider();
    unadviseSinks();
    uninitializeLangBar();
    engine_.reset();
    threadManager_.Reset();
    clientId_ = TF_CLIENTID_NULL;
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

    modeIconButton_ = new (std::nothrow)
        LangBarButton(this, kLangBarInputModeGuid, LangBarButton::Kind::InputMode);
    switchLanguageButton_ = new (std::nothrow) LangBarButton(
        this, kLangBarSwitchLanguageGuid, LangBarButton::Kind::SwitchLanguage);
    fullHalfButton_ = new (std::nothrow)
        LangBarButton(this, kLangBarFullHalfGuid, LangBarButton::Kind::FullHalf);
    settingsButton_ = new (std::nothrow)
        LangBarButton(this, kLangBarSettingsGuid, LangBarButton::Kind::Settings);
    if (!modeIconButton_ || !switchLanguageButton_ || !fullHalfButton_ ||
        !settingsButton_) {
        uninitializeLangBar();
        return E_OUTOFMEMORY;
    }

    LangBarButton* buttons[] = {modeIconButton_, switchLanguageButton_,
                                fullHalfButton_, settingsButton_};
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
    LangBarButton** buttons[] = {&modeIconButton_, &switchLanguageButton_,
                                 &fullHalfButton_, &settingsButton_};
    for (LangBarButton** button : buttons) {
        if (!*button) continue;
        if (manager) manager->RemoveItem(*button);
        (*button)->Release();
        *button = nullptr;
    }
}

void TextService::refreshLangBar() {
    if (modeIconButton_) modeIconButton_->update();
    if (switchLanguageButton_) switchLanguageButton_->update();
    if (fullHalfButton_) fullHalfButton_->update();
    if (settingsButton_) settingsButton_->update();
}

void TextService::setChineseMode(bool enabled) {
    chineseMode_ = enabled;
    shiftTogglePending_ = false;
    if (!enabled) abandonComposition();

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
    return engine_->wantsKey(event);
}

bool TextService::isModeToggleKey(const KeyEvent& event) const {
    return event.virtualKey == VK_SPACE && event.control && !event.alt;
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
        abandonComposition();
    }
    return S_OK;
}

STDMETHODIMP TextService::OnTestKeyDown(ITfContext*, WPARAM wparam, LPARAM lparam,
                                        BOOL* eaten) {
    if (!eaten) return E_INVALIDARG;
    const KeyEvent event = translateKey(wparam, lparam);
    *eaten = isModeToggleKey(event) || isWidthToggleKey(event) ||
             isPotentialKey(event);
    Trace("TestKeyDown vk=%u textLen=%zu shift=%d ctrl=%d alt=%d caps=%d mode=%d eaten=%d",
          event.virtualKey, event.text.size(), event.shift, event.control,
          event.alt, event.capsLock, chineseMode_, *eaten);
    return S_OK;
}

STDMETHODIMP TextService::OnTestKeyUp(ITfContext*, WPARAM, LPARAM, BOOL* eaten) {
    if (!eaten) return E_INVALIDARG;
    *eaten = FALSE;
    return S_OK;
}

STDMETHODIMP TextService::OnKeyDown(ITfContext* context, WPARAM wparam, LPARAM lparam,
                                    BOOL* eaten) {
    if (!context || !eaten) return E_INVALIDARG;
    *eaten = FALSE;
    KeyEvent event = translateKey(wparam, lparam);
    if ((event.virtualKey == VK_SHIFT || event.virtualKey == VK_LSHIFT ||
         event.virtualKey == VK_RSHIFT) &&
        !event.control && !event.alt) {
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
    if ((wparam == VK_SHIFT || wparam == VK_LSHIFT || wparam == VK_RSHIFT) &&
        shiftTogglePending_ && !IsKeyDown(VK_CONTROL) && !IsKeyDown(VK_MENU)) {
        shiftTogglePending_ = false;
        toggleChineseMode();
        *eaten = TRUE;
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
    if (!result.handled) return S_OK;
    if (result.beep) MessageBeep(MB_OK);
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
    if (clearText) {
        ComPtr<ITfRange> range;
        if (SUCCEEDED(composition_->GetRange(&range))) {
            range->SetText(editCookie, 0, nullptr, 0);
        }
    }
    endingComposition_ = true;
    const HRESULT result = composition_->EndComposition(editCookie);
    endingComposition_ = false;
    composition_.Reset();
    compositionContext_.Reset();
    return result;
}

HRESULT TextService::terminateComposition(TfEditCookie editCookie) {
    candidateWindow_.hide();
    candidateActive_ = false;
    if (engine_) engine_->reset();
    return endComposition(editCookie, true);
}

void TextService::abandonComposition() {
    candidateWindow_.hide();
    candidateActive_ = false;
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
            return;
        }
        range.Attach(selection.range);
    }

    ComPtr<ITfContextView> view;
    if (FAILED(context->GetActiveView(&view))) {
        candidateWindow_.hide();
        candidateActive_ = false;
        return;
    }
    RECT textRect{};
    BOOL clipped = FALSE;
    HWND owner = nullptr;
    if (FAILED(view->GetTextExt(editCookie, range.Get(), &textRect, &clipped)) ||
        FAILED(view->GetWnd(&owner))) {
        candidateWindow_.hide();
        candidateActive_ = false;
        return;
    }
    candidateWindow_.show(owner, textRect, result.candidates,
                          result.highlightedCandidate);
    candidateActive_ = true;
    Trace("Candidate active=1 count=%zu", result.candidates.size());
}

STDMETHODIMP TextService::OnCompositionTerminated(TfEditCookie,
                                                   ITfComposition* composition) {
    if (composition_.Get() == composition) {
        composition_.Reset();
        compositionContext_.Reset();
        if (!endingComposition_) {
            candidateWindow_.hide();
            candidateActive_ = false;
            if (engine_) engine_->reset();
        }
    }
    return S_OK;
}

STDMETHODIMP TextService::OnInitDocumentMgr(ITfDocumentMgr*) { return S_OK; }
STDMETHODIMP TextService::OnUninitDocumentMgr(ITfDocumentMgr* documentManager) {
    if (compositionContext_) {
        ComPtr<ITfDocumentMgr> owner;
        if (SUCCEEDED(compositionContext_->GetDocumentMgr(&owner)) &&
            owner.Get() == documentManager) {
            abandonComposition();
        }
    }
    return S_OK;
}
STDMETHODIMP TextService::OnSetFocus(ITfDocumentMgr* focused, ITfDocumentMgr*) {
    ComPtr<ITfContext> focusedContext;
    if (focused) focused->GetTop(&focusedContext);
    if (composition_ && compositionContext_.Get() != focusedContext.Get()) {
        abandonComposition();
    } else if (!focused) {
        candidateWindow_.hide();
        candidateActive_ = false;
        if (engine_) engine_->reset();
    }
    return S_OK;
}
STDMETHODIMP TextService::OnPushContext(ITfContext*) { return S_OK; }
STDMETHODIMP TextService::OnPopContext(ITfContext* context) {
    if (compositionContext_.Get() == context) {
        abandonComposition();
    } else {
        candidateWindow_.hide();
        candidateActive_ = false;
        if (engine_) engine_->reset();
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
            chineseMode_ = enabled;
            shiftTogglePending_ = false;
            if (!enabled) abandonComposition();
            refreshLangBar();
        }
        Trace("InputMode changed chinese=%d", chineseMode_);
    }
    VariantClear(&value);
    return S_OK;
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
    *name = SysAllocString(L"琦琦輸入法詞庫設定");
    return *name ? S_OK : E_OUTOFMEMORY;
}

HRESULT TextService::openSettings(HWND parent) const {
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
