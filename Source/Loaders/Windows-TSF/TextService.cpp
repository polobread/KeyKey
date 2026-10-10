#include "TextService.h"
#include "InputModeState.h"
#include "StartupInputMode.h"
#include "TsfHost.h"

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
#include "OutputConversion.h"

namespace KeyKey::WindowsTsf {
namespace {

using Microsoft::WRL::ComPtr;

constexpr DWORD kShiftTapTimeoutMilliseconds = 300;
constexpr UINT kPumpModeMessage = WM_APP + 71;

HRESULT RangeText(ITfRange* range, TfEditCookie cookie, std::wstring& text) {
    ComPtr<ITfRange> reader;
    if (!range) return E_INVALIDARG;
    auto result = range->Clone(&reader);
    if (FAILED(result)) return result;
    text.clear();
    wchar_t buffer[1024];
    for (;;) {
        ULONG count = 0;
        result = reader->GetText(cookie, TF_TF_MOVESTART, buffer,
                                 static_cast<ULONG>(std::size(buffer)), &count);
        if (FAILED(result)) { text.clear(); return result; }
        if (count > std::size(buffer) || count > 65536 - text.size()) {
            text.clear(); return E_FAIL;
        }
        if (!count) return S_OK;
        text.append(buffer, count);
    }
}

class TerminateEditSession final : public ITfEditSession {
public:
    explicit TerminateEditSession(ITfComposition* composition, bool simplified)
        : composition_(composition), simplified_(simplified) {}
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
        auto result = composition_->GetRange(&range);
        if (FAILED(result)) return result;
        std::wstring text;
        result = RangeText(range.Get(), editCookie, text);
        if (FAILED(result)) return result;
        text = ConvertOutput(text, simplified_);
        if (!text.empty()) result = range->SetText(editCookie, 0, text.data(), static_cast<LONG>(text.size()));
        if (FAILED(result)) return result;
        return composition_->EndComposition(editCookie);
    }

private:
    ~TerminateEditSession() = default;
    std::atomic<ULONG> references_{1};
    ComPtr<ITfComposition> composition_;
    bool simplified_;
};

class CandidateLayoutEditSession final : public ITfEditSession {
public:
    CandidateLayoutEditSession(TextService* service, ITfContext* context,
                               unsigned long long generation)
        : service_(service), context_(context), generation_(generation) { service_->AddRef(); }
    STDMETHODIMP QueryInterface(REFIID iid, void** object) override {
        if (!object) return E_INVALIDARG;
        *object = nullptr;
        if (iid != IID_IUnknown && iid != IID_ITfEditSession) return E_NOINTERFACE;
        *object = static_cast<ITfEditSession*>(this); AddRef(); return S_OK;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return ++references_; }
    STDMETHODIMP_(ULONG) Release() override {
        const auto left = --references_; if (!left) delete this; return left;
    }
    STDMETHODIMP DoEditSession(TfEditCookie cookie) override {
        executed_=true;
        return service_->refreshCandidateLayout(cookie, context_.Get(), generation_);
    }
private:
    ~CandidateLayoutEditSession() {
        if (!executed_) service_->cancelCandidateLayout(context_.Get(),generation_);
        service_->Release();
    }
    std::atomic<ULONG> references_{1};
    TextService* service_;
    ComPtr<ITfContext> context_;
    unsigned long long generation_;
    bool executed_=false;
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

struct TextService::InputOperation {
    enum class Kind { Key, Mode, Commit, Symbol };
    Kind kind=Kind::Key;
    ModeChange change=ModeChange::Chinese;
    ComPtr<ITfContext> context;
    KeyEvent event;
    std::string method;
    std::string settingsSignature;
    std::wstring text;
    unsigned long symbolGeneration=0;
    unsigned long long token=0,generation=0;
    bool enabled=false,fullWidth=false,fromConversion=false,handled=false,completed=false,accepted=false,ordered=false,processed=false;
    HRESULT result=E_PENDING;
};

class TextService::InputEditSession final : public ITfEditSession {
public:
    InputEditSession(TextService* service,std::shared_ptr<InputOperation> operation)
        : service_(service),operation_(std::move(operation)) { service_->AddRef(); }
    STDMETHODIMP QueryInterface(REFIID iid,void** object) override {
        if (!object) return E_POINTER; *object=nullptr;
        if (iid!=IID_IUnknown && iid!=IID_ITfEditSession) return E_NOINTERFACE;
        *object=static_cast<ITfEditSession*>(this); AddRef(); return S_OK;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return ++references_; }
    STDMETHODIMP_(ULONG) Release() override {
        const auto left=--references_; if (!left) delete this; return left;
    }
    STDMETHODIMP DoEditSession(TfEditCookie cookie) override {
        if (executed_) return result_;
        executed_=true;
        service_->editingInput_=true;
        result_=service_->runInput(cookie,operation_);
        service_->editingInput_=false;
        service_->completeInput(operation_,result_,false);
        return result_;
    }
private:
    ~InputEditSession() {
        if (!executed_) service_->completeInput(operation_,E_ABORT,true);
        service_->Release();
    }
    std::atomic<ULONG> references_{1};
    TextService* service_;
    std::shared_ptr<InputOperation> operation_;
    bool executed_=false;
    HRESULT result_=S_FALSE;
};

ComPtr<ITfContext> TextService::inputContext() const {
    if (!inputQueue_.empty()) return inputQueue_.back()->context;
    if (compositionContext_) return compositionContext_;
    ComPtr<ITfDocumentMgr> document; ComPtr<ITfContext> context;
    if (threadManager_ && SUCCEEDED(threadManager_->GetFocus(&document)) && document)
        document->GetTop(&context);
    return context ? context : textEditContext_;
}
bool TextService::projectedChineseMode() const {
    bool value=chineseMode_;
    for (const auto& op : inputQueue_) if (op->kind==InputOperation::Kind::Mode) {
        if (op->change==ModeChange::Chinese || op->change==ModeChange::Host) value=op->enabled;
        if (op->change==ModeChange::Method) value=op->enabled;
    }
    return value;
}
bool TextService::projectedWidthMode() const {
    bool value=fullWidthMode_;
    for (const auto& op : inputQueue_) if (op->kind==InputOperation::Kind::Mode) {
        if (op->change==ModeChange::Width) value=op->enabled;
        if (op->change==ModeChange::Host) value=op->fullWidth;
    }
    return value;
}
bool TextService::orderedPrintableKey(const KeyEvent& event) const {
    return !event.control && !event.alt && PrintableCharacter(event)!=0;
}
void TextService::cancelInput(bool resyncHost) {
    // Text operations belong to their original context; host modes belong to
    // this thread. Discard the operations but reread live modes after cleanup.
    const bool lostHostMode=restoreHostMode_ || std::any_of(inputQueue_.begin(),inputQueue_.end(),[](const auto& op) {
        return op->kind==InputOperation::Kind::Mode && op->change==ModeChange::Host;
    });
    ++inputGeneration_;
    for (auto& op : inputQueue_) { op->completed=true; op->result=E_ABORT; }
    inputQueue_.clear(); activeInput_.reset(); pendingModeCommit_=false; blockedInput_=false;
    retainedInputResult_.reset(); retainedInputContext_.Reset(); retainedCommitWritten_=false;
    retainedCommitRange_.Reset(); retainedCommitCaretSet_=false; retainedCommitNeedsEnd_=false;
    restoreHostMode_=false;
    resyncHostMode_=resyncHost && (resyncHostMode_ || lostHostMode);
    if (!resyncHost || resyncHostMode_) modeRecoveryPending_=false;
    if (resyncHostMode_) postModePump();
    if (inputLease_) { inputLease_=false; EndOrderedEngineInput(); }
}
void TextService::completeInput(const std::shared_ptr<InputOperation>& op,HRESULT result,bool cancelled) {
    if (op->completed || op->generation!=inputGeneration_ || activeInput_!=op) return;
    if (!cancelled && FAILED(result) && op->kind==InputOperation::Kind::Key && (op->accepted || op->ordered)) {
        // An already accepted key is retained in this original context. Retry
        // only on a subsequent input request; never rerun a processed engine key.
        op->result=result; activeInput_.reset(); blockedInput_=true; return;
    }
    if (!cancelled && FAILED(result) && op->kind==InputOperation::Kind::Mode && op->change==ModeChange::Host) {
        // The host may deny a write session before DoEditSession is called.
        // Reconcile to our retained composition/mode outside its notification.
        restoreHostMode_=true; postModePump();
    }
    op->completed=true; op->result=result;
    if (cancelled) {
        // TSF may cancel without DoEditSession. Do not retain a service-wide
        // pending latch or replay accepted input into a future context.
        cancelInput();
        if (resyncHostMode_) abandonComposition();
        return;
    }
    activeInput_.reset();
    if (!inputQueue_.empty() && inputQueue_.front()==op) inputQueue_.pop_front();
    pendingModeCommit_=std::any_of(inputQueue_.begin(),inputQueue_.end(),[](const auto& item) {
        return item->kind!=InputOperation::Kind::Key;
    });
    if (inputQueue_.empty() && inputLease_) { inputLease_=false; EndOrderedEngineInput(); }
    if (!pumpingInput_) pumpInput();
}
void TextService::pumpInput() {
    if (pumpingInput_ || activeInput_ || blockedInput_) return;
    pumpingInput_=true;
    if (resyncHostMode_ && !inModeNotification_ && !composition_ && !retainedInputResult_)
        resyncCancelledHostMode();
    if (modeRecoveryPending_ && !inModeNotification_) retryModeRecovery();
    if (restoreHostMode_ && !inModeNotification_) {
        restoreHostMode_=false;
        const auto chinese=publishChineseMode(chineseMode_);
        const auto width=setFullWidthMode(fullWidthMode_);
        if (FAILED(chinese) || FAILED(width)) Trace("Host mode restore failed chinese=0x%08lX width=0x%08lX",
            static_cast<unsigned long>(chinese),static_cast<unsigned long>(width));
    }
    while (!activeInput_ && !blockedInput_ && !inputQueue_.empty()) {
        auto op=inputQueue_.front();
        // A host can change mode before there is a text store. Posting to our
        // UI thread also handles that case without any write inside OnChange.
        if (!op->context && inModeNotification_ && postModePump()) break;
        activeInput_=op;
        if (!op->context) {
            const auto result=runInput(0,op); completeInput(op,result,false); continue;
        }
        auto* session=new (std::nothrow) InputEditSession(this,op);
        if (!session) { completeInput(op,E_OUTOFMEMORY,false); continue; }
        HRESULT edited=E_FAIL;
        const bool defer = inModeNotification_ ||
            (op->kind==InputOperation::Kind::Mode && op->change==ModeChange::Host);
        auto requested=op->context->RequestEditSession(clientId_,session,
            (defer ? TF_ES_ASYNC : TF_ES_SYNC)|TF_ES_READWRITE,&edited);
        if (!defer && !op->completed && (requested==TF_E_SYNCHRONOUS || requested==TF_E_LOCKED ||
            (SUCCEEDED(requested) && (edited==TF_E_SYNCHRONOUS || edited==TF_E_LOCKED)))) {
            edited=E_FAIL;
            requested=op->context->RequestEditSession(clientId_,session,TF_ES_ASYNCDONTCARE|TF_ES_READWRITE,&edited);
        }
        if (!op->completed && SUCCEEDED(requested) && SUCCEEDED(edited)) op->accepted=true;
        else if (!op->completed) completeInput(op,FAILED(requested)?requested:edited,false);
        session->Release();
    }
    pumpingInput_=false;
}
bool TextService::enqueueInput(const std::shared_ptr<InputOperation>& op) {
    // A no-context host mode can be posted just before the first field/key
    // appears. Adopt it before changing contexts rather than canceling it.
    if (op->context && !inputQueue_.empty() && !inputQueue_.front()->context &&
        !inModeNotification_) pumpInput();
    if (op->context && ((!inputQueue_.empty() && inputQueue_.front()->context.Get()!=op->context.Get()) ||
        (retainedInputContext_ && retainedInputContext_.Get()!=op->context.Get()))) {
        cancelInput(); abandonComposition();
        // The first operation in a new field must see the live host mode,
        // even if the posted resynchronization has not run yet.
        if (resyncHostMode_ && !inModeNotification_) pumpInput();
    }
    op->token=++nextInputToken_; op->generation=inputGeneration_;
    op->ordered=!inputQueue_.empty();
    if (!inputLease_) { BeginOrderedEngineInput(); inputLease_=true; }
    inputQueue_.push_back(op);
    blockedInput_=false;
    if (op->kind!=InputOperation::Kind::Key) pendingModeCommit_=true;
    pumpInput();
    return op->completed ? (op->kind==InputOperation::Kind::Key ? op->handled : SUCCEEDED(op->result))
                         : (op->accepted || op->ordered);
}
bool TextService::requestModeChange(ModeChange change,bool enabled,const std::string& method) {
    auto op=std::make_shared<InputOperation>(); op->kind=InputOperation::Kind::Mode;
    op->change=change; op->enabled=enabled; op->method=method; op->context=inputContext();
    if (change==ModeChange::Method) op->settingsSignature=EngineSettingsSignature(method);
    return enqueueInput(op);
}
bool TextService::requestKey(ITfContext* context,const KeyEvent& event) {
    if ((resyncHostMode_ || modeRecoveryPending_ || restoreHostMode_) && !inModeNotification_) pumpInput();
    if (!IsInputContextEnabled(context) || !isPotentialKey(event)) return false;
    auto op=std::make_shared<InputOperation>(); op->context=context; op->event=event;
    return enqueueInput(op);
}
bool TextService::requestSymbol(ITfContext* context,const std::wstring& text,unsigned long generation) {
    auto op=std::make_shared<InputOperation>(); op->kind=InputOperation::Kind::Symbol;
    op->context=context; op->text=text; op->symbolGeneration=generation;
    return enqueueInput(op);
}
HRESULT TextService::runInput(TfEditCookie cookie,const std::shared_ptr<InputOperation>& op) {
    if (op->completed || op->generation!=inputGeneration_ || activeInput_!=op) return S_FALSE;
    auto* context=op->context.Get();
    if (context && !IsInputContextEnabled(context) && op->kind!=InputOperation::Kind::Mode) {
        completeInput(op,E_ABORT,true);
        return S_FALSE;
    }
    if (context) {
        const auto result=retryInputResult(cookie,context);
        if (FAILED(result)) return result;
    }
    if (op->kind==InputOperation::Kind::Key) {
        const auto result=op->processed ? S_OK : processKey(cookie,context,op->event,&op->handled,&op->processed);
        if (op->processed && op->handled) return result;
        // A printable key accepted while an earlier edit was pending cannot
        // later be returned to TSF. Preserve the engine's pass-through result
        // by inserting the same character in this operation's original context.
        if (SUCCEEDED(result) && !op->handled && (op->ordered || op->accepted) &&
            !op->event.control && !op->event.alt && PrintableCharacter(op->event)) {
            auto status=commitCompositionForModeSwitch(cookie,context);
            if (FAILED(status)) return status;
            auto text=std::wstring(1,PrintableCharacter(op->event));
            if (fullWidthMode_) text=ToFullWidth(std::move(text));
            retainedInputResult_=std::make_unique<EngineResult>(); retainedInputResult_->committedText=text;
            retainedInputContext_=context; retainedCommitWritten_=false;
            op->processed=true; op->handled=true;
            return retryInputResult(cookie,context);
        }
        return result;
    }
    if (op->kind==InputOperation::Kind::Symbol)
        return insertSymbol(cookie,context,op->text,op->symbolGeneration);
    std::unique_ptr<KeyKeyEngineSession> prepared;
    if (op->kind==InputOperation::Kind::Mode && op->change==ModeChange::Method) {
        prepared=KeyKeyEngineSession::CreateControlled(op->method);
        if (!prepared || !prepared->ready()) return E_FAIL;
    }
    const auto committed=commitCompositionForModeSwitch(cookie,context);
    if (FAILED(committed)) {
        if (op->kind==InputOperation::Kind::Mode &&
            (op->change==ModeChange::Chinese || op->change==ModeChange::Width)) {
            publishChineseMode(chineseMode_); setFullWidthMode(fullWidthMode_);
        }
        return committed;
    }
    if (op->kind==InputOperation::Kind::Commit) return S_OK;
    closeSymbols();
    switch (op->change) {
        case ModeChange::Chinese: return publishChineseMode(op->enabled);
        case ModeChange::Width: return setFullWidthMode(op->enabled);
        case ModeChange::Host:
            // The host already published this state. Never echo its notification.
            chineseMode_=op->enabled; fullWidthMode_=op->fullWidth;
            shiftTogglePending_=false; shiftPressedAt_=0; refreshLangBar();
            return inModeNotification_ ? S_OK : reconcileHostMode(op->enabled,op->fromConversion);
        case ModeChange::Method: {
            // Keep the old engine and effective state until all publication
            // steps succeed. A failed TSF write must not persist a new method.
            const auto previousMethod=ObservedInputMethod();
            const bool previousChinese=chineseMode_;
            const auto restoreMode=[&] {
                const auto restored=publishChineseMode(previousChinese);
                if (FAILED(restored)) {
                    chineseMode_=previousChinese; refreshLangBar();
                    scheduleModeRecovery(previousChinese,fullWidthMode_);
                    Trace("Method switch mode rollback failed hr=0x%08lX",static_cast<unsigned long>(restored));
                }
            };
            const auto restoreSelection=[&] {
                if (!SelectInputMethod(previousMethod.c_str())) Trace("Method switch preference rollback failed");
                restoreMode();
            };
            auto result=publishChineseMode(op->enabled);
            if (FAILED(result)) return result;
            if (!SelectInputMethod(op->method.c_str())) { restoreSelection(); return E_FAIL; }
            result=threadManager_ ? sharedInputMethod_.write(clientId_,op->method.c_str()) : S_OK;
            if (FAILED(result)) {
                restoreSelection();
                return result;
            }
            engine_=std::move(prepared); effectiveInputMethod_=op->method;
            effectiveSettingsSignature_=EngineSettingsSignature(op->method); lastLocalInputMethod_=op->method;
            refreshLangBar();
            return S_OK;
        }
        case ModeChange::Simplified:
            if (FAILED(sharedOutputState_.write(clientId_,op->enabled)) && !SaveSimplifiedOutputPreference(op->enabled)) return E_FAIL;
            SaveSimplifiedOutputPreference(op->enabled);
            simplifiedOutput_=op->enabled; lastLocalSimplifiedOutput_=op->enabled; outputSettingsInitialized_=true;
            refreshLangBar(); break;
    }
    return S_OK;
}

TextService::TextService() = default;
TextService::~TextService() { if (modeWindow_) DestroyWindow(modeWindow_); }

LRESULT CALLBACK TextService::ModeWindowProc(HWND window,UINT message,WPARAM wp,LPARAM lp) {
    auto* service=reinterpret_cast<TextService*>(GetWindowLongPtrW(window,GWLP_USERDATA));
    const auto original=service ? service->modeOriginalProc_ : nullptr;
    if (service && message==kPumpModeMessage) {
        service->AddRef();
        service->modePumpPosted_=false; service->pumpInput();
        service->Release(); return 0;
    }
    if (message==WM_NCDESTROY && service) {
        service->modeWindow_=nullptr; service->modePumpPosted_=false;
        service->modeOriginalProc_=nullptr;
        SetWindowLongPtrW(window,GWLP_USERDATA,0);
    }
    return original ? CallWindowProcW(original,window,message,wp,lp) : DefWindowProcW(window,message,wp,lp);
}

bool TextService::postModePump() {
    if (modePumpPosted_) return true;
    if (!modeWindow_) {
        // Subclass the system class instead of leaving a DLL-owned window
        // class registered after a text service DLL unload/reload.
        modeWindow_=CreateWindowExW(0,L"STATIC",L"KeyKey mode dispatch",0,0,0,0,0,HWND_MESSAGE,nullptr,g_module,nullptr);
        if (modeWindow_) {
            SetWindowLongPtrW(modeWindow_,GWLP_USERDATA,reinterpret_cast<LONG_PTR>(this));
            modeOriginalProc_=reinterpret_cast<WNDPROC>(SetWindowLongPtrW(modeWindow_,GWLP_WNDPROC,
                reinterpret_cast<LONG_PTR>(ModeWindowProc)));
            if (!modeOriginalProc_) { DestroyWindow(modeWindow_); modeWindow_=nullptr; }
        }
    }
    modePumpPosted_=modeWindow_ && PostMessageW(modeWindow_,kPumpModeMessage,0,0);
    if (!modePumpPosted_) Trace("Host mode dispatch failed error=%lu",GetLastError());
    return modePumpPosted_;
}

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
    } else if (iid == IID_ITfTextLayoutSink) {
        *object = static_cast<ITfTextLayoutSink*>(this);
    } else if (iid == IID_ITfThreadMgrEventSink) {
        *object = static_cast<ITfThreadMgrEventSink*>(this);
    } else if (iid == IID_ITfThreadFocusSink) {
        *object = static_cast<ITfThreadFocusSink*>(this);
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
                                     DWORD flags) {
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
    effectiveInputMethod_=ObservedInputMethod();
    lastLocalInputMethod_=effectiveInputMethod_;
    engine_ = KeyKeyEngineSession::CreateControlled(effectiveInputMethod_);
    effectiveSettingsSignature_=EngineSettingsSignature(effectiveInputMethod_);
    for (const auto& method : kInputMethods) {
        Trace("InputMethod available method=%s available=%d", method.identifier,
              IsInputMethodAvailable(method.identifier));
    }
    immersiveMode_ = (flags & TF_TMF_IMMERSIVEMODE) != 0;
    ComPtr<ITfThreadMgrEx> extended;
    DWORD activeFlags=0;
    if (SUCCEEDED(threadManager_.As(&extended)) && SUCCEEDED(extended->GetActiveFlags(&activeFlags)))
        immersiveMode_=(activeFlags & TF_TMF_IMMERSIVEMODE)!=0;
    uiThreadFocused_=true;
    const HRESULT sharedResult = sharedInputMethod_.connect(threadManager_.Get());
    sharedOutputState_.connect(threadManager_.Get());
    Trace("SharedInputMethod connect hr=0x%08lX", static_cast<unsigned long>(sharedResult));
    syncInputMethod();
    Trace("Activate process=%ls arch=%ls client=%lu flags=0x%08lX engineReady=%d",
          CurrentProcessName().c_str(), BuildArchitecture(),
          static_cast<unsigned long>(clientId_), static_cast<unsigned long>(flags),
          engine_ && engine_->ready());
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
        applyStartupInputMode();
    }
    if (FAILED(result)) {
        closeSymbols(); cancelInput(false); clearCandidateWindow();
        if (modeWindow_) DestroyWindow(modeWindow_);
        unadviseFunctionProvider();
        unadviseSinks();
        uninitializeLangBar();
        engine_.reset();
        sharedInputMethod_.reset();
        sharedOutputState_.reset();
        lastLocalInputMethod_.clear();
        threadManager_.Reset();
        clientId_ = TF_CLIENTID_NULL;
    }
    return result;
}

STDMETHODIMP TextService::Deactivate() {
    Trace("Deactivate");
    closeSymbols();
    cancelInput(false); abandonComposition();
    if (modeWindow_) DestroyWindow(modeWindow_);
    unadviseFunctionProvider();
    unadviseSinks();
    uninitializeLangBar();
    engine_.reset();
    sharedInputMethod_.reset();
    sharedOutputState_.reset();
    outputSettingsInitialized_ = false;
    lastLocalInputMethod_.clear();
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
    if (SUCCEEDED(result)) result=source->AdviseSink(IID_ITfThreadFocusSink,
        static_cast<ITfThreadFocusSink*>(this), &threadFocusCookie_);
    if (FAILED(result)) {
        if (threadManagerCookie_!=TF_INVALID_COOKIE) {
            source->UnadviseSink(threadManagerCookie_); threadManagerCookie_=TF_INVALID_COOKIE;
        }
        keystrokes->UnadviseKeyEventSink(clientId_);
    }
    if (SUCCEEDED(result)) {
        const HRESULT modeResult = adviseInputModeSink();
        Trace("AdviseInputMode hr=0x%08lX", static_cast<unsigned long>(modeResult));
        if (FAILED(modeResult)) result=modeResult;
    }
    return result;
}

void TextService::unadviseSinks() {
    if (!threadManager_) return;
    unadviseTextEditSink();
    unadviseInputModeSink();
    if (threadFocusCookie_!=TF_INVALID_COOKIE) {
        ComPtr<ITfSource> source;
        if (SUCCEEDED(threadManager_.As(&source))) source->UnadviseSink(threadFocusCookie_);
        threadFocusCookie_=TF_INVALID_COOKIE;
    }
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
        (textEditCookie_ != TF_INVALID_COOKIE || textLayoutCookie_ != TF_INVALID_COOKIE)) {
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
    const HRESULT layoutResult = source->AdviseSink(IID_ITfTextLayoutSink,
        static_cast<ITfTextLayoutSink*>(this), &textLayoutCookie_);
    if (SUCCEEDED(result) || SUCCEEDED(layoutResult)) textEditContext_ = context;
    Trace("AdviseTextLayout hr=0x%08lX", static_cast<unsigned long>(layoutResult));
    return result;
}

void TextService::unadviseTextEditSink() {
    if (textEditContext_) {
        ComPtr<ITfSource> source;
        if (SUCCEEDED(textEditContext_.As(&source))) {
            if (textEditCookie_ != TF_INVALID_COOKIE) source->UnadviseSink(textEditCookie_);
            if (textLayoutCookie_ != TF_INVALID_COOKIE) source->UnadviseSink(textLayoutCookie_);
        }
    }
    textEditCookie_ = TF_INVALID_COOKIE;
    textLayoutCookie_ = TF_INVALID_COOKIE;
    clearCandidateWindow();
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

    auto* modeIcon = LangBarButton::CreateInputMode(this);
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

void TextService::applyStartupInputMode() {
    setChineseMode(ResolveStartupChineseMode(threadManager_.Get(), clientId_, immersiveMode_,
                                            LoadFrontendSettings().defaultChineseMode));
    setFullWidthMode(false);
}

void TextService::setChineseMode(bool enabled) {
    requestModeChange(ModeChange::Chinese,enabled);
}
HRESULT TextService::publishChineseMode(bool enabled) {
    HRESULT result=S_OK;
    ChineseModeWriteStatus status;
    ComPtr<ITfCompartmentMgr> manager;
    if (threadManager_) {
        result=threadManager_.As(&manager);
        if (FAILED(result)) { scheduleModeRecovery(chineseMode_,fullWidthMode_); return result; }
        updatingModeCompartments_=true;
        result=WriteChineseMode(manager.Get(),clientId_,enabled,&status);
        updatingModeCompartments_=false;
    }
    if (FAILED(result)) {
        scheduleModeRecovery(chineseMode_,fullWidthMode_);
        Trace("InputMode write failed hr=0x%08lX partial=%d rollback=0x%08lX",static_cast<unsigned long>(result),
              status.partiallyWritten,static_cast<unsigned long>(status.rollback));
        return result;
    }
    chineseMode_=enabled; shiftTogglePending_=false; shiftPressedAt_=0;
    if (modeRecoveryPending_ && !modeRecoveryRunning_) {
        recoveryChinese_=chineseMode_; recoveryFullWidth_=fullWidthMode_;
    }
    refreshLangBar();
    return S_OK;
}
void TextService::toggleChineseMode() { setChineseMode(!projectedChineseMode()); }

void TextService::scheduleModeRecovery(bool chinese,bool fullWidth) {
    if (!threadManager_) return;
    const bool first=!modeRecoveryPending_;
    modeRecoveryPending_=true;
    if (!modeRecoveryRunning_) { recoveryChinese_=chinese; recoveryFullWidth_=fullWidth; }
    // One deferred attempt per failure episode. Persistent denial is retried
    // only on later focus/input activity, never by reposting an endless loop.
    if (first && !modeRecoveryRunning_) postModePump();
}

void TextService::retryModeRecovery() {
    if (!modeRecoveryPending_ || modeRecoveryRunning_ || inModeNotification_ || !threadManager_) return;
    modeRecoveryRunning_=true;
    const bool chinese=recoveryChinese_,width=recoveryFullWidth_;
    const auto chineseResult=publishChineseMode(chinese);
    const auto widthResult=setFullWidthMode(width);
    modeRecoveryPending_=FAILED(chineseResult) || FAILED(widthResult);
    modeRecoveryRunning_=false;
    if (modeRecoveryPending_) Trace("Mode recovery pending chinese=0x%08lX width=0x%08lX",
        static_cast<unsigned long>(chineseResult),static_cast<unsigned long>(widthResult));
}

HRESULT TextService::setFullWidthMode(bool enabled) {
    HRESULT result = S_OK;
    ComPtr<ITfCompartmentMgr> manager;
    ComPtr<ITfCompartment> compartment;
    if (threadManager_) {
        result=threadManager_.As(&manager);
        if (FAILED(result)) { scheduleModeRecovery(chineseMode_,fullWidthMode_); return result; }
        result=manager->GetCompartment(GUID_COMPARTMENT_KEYBOARD_INPUTMODE_CONVERSION, &compartment);
        if (FAILED(result)) { scheduleModeRecovery(chineseMode_,fullWidthMode_); return result; }
        LONG mode = 0;
        VARIANT current;
        VariantInit(&current);
        result=compartment->GetValue(&current);
        const bool valid=current.vt==VT_I4;
        const LONG previous=valid ? current.lVal : 0;
        if (SUCCEEDED(result) && current.vt == VT_I4) {
            mode = current.lVal;
        }
        if (SUCCEEDED(result) && !valid && current.vt!=VT_EMPTY) result=E_INVALIDARG;
        VariantClear(&current);
        if (FAILED(result)) { scheduleModeRecovery(chineseMode_,fullWidthMode_); return result; }
        if (enabled) {
            mode |= TF_CONVERSIONMODE_FULLSHAPE;
        } else {
            mode &= ~TF_CONVERSIONMODE_FULLSHAPE;
        }
        VARIANT value;
        VariantInit(&value);
        value.vt = VT_I4;
        value.lVal = mode;
        updatingModeCompartments_=true;
        result = valid && previous==mode ? S_OK : compartment->SetValue(clientId_, &value);
        updatingModeCompartments_=false;
    }
    Trace("InputWidth full=%d hr=0x%08lX", enabled,
          static_cast<unsigned long>(result));
    if (FAILED(result)) { scheduleModeRecovery(chineseMode_,fullWidthMode_); return result; }
    fullWidthMode_ = enabled;
    if (modeRecoveryPending_ && !modeRecoveryRunning_) {
        recoveryChinese_=chineseMode_; recoveryFullWidth_=fullWidthMode_;
    }
    refreshLangBar();
    return S_OK;
}

void TextService::toggleFullWidthMode() { requestModeChange(ModeChange::Width,!projectedWidthMode()); }

bool TextService::selectInputMethod(const char* identifier) {
    if (!IsInputMethodVisible(identifier) || !IsInputMethodAvailable(identifier)) return false;
    return requestModeChange(ModeChange::Method,true,identifier);
}

void TextService::syncInputMethod() {
    if (!threadManager_ || syncingInputMethod_) return;
    if ((resyncHostMode_ || modeRecoveryPending_ || restoreHostMode_) && !inModeNotification_) pumpInput();
    syncingInputMethod_=true;
    syncOutputSettings();
    const auto local=ObservedInputMethod();
    const auto* shared=sharedInputMethod_.read();
    std::string desired=local;
    if (shared && (immersiveMode_ || lastLocalInputMethod_.empty() || local==lastLocalInputMethod_)) desired=shared->identifier;
    std::string projected=effectiveInputMethod_;
    auto projectedSignature=effectiveSettingsSignature_;
    for (const auto& op : inputQueue_)
        if (op->kind==InputOperation::Kind::Mode && op->change==ModeChange::Method) {
            projected=op->method; projectedSignature=op->settingsSignature;
        }
    // An explicit queued choice has not yet been published to the profile or
    // shared compartment. Observing those unchanged values must not undo it.
    if (projected!=effectiveInputMethod_ && desired==effectiveInputMethod_ &&
        local==lastLocalInputMethod_) desired=projected;
    const auto signature=EngineSettingsSignature(desired);
    if (IsInputMethodAvailable(desired.c_str()) &&
        (desired!=projected || signature!=projectedSignature))
        requestModeChange(ModeChange::Method,projectedChineseMode(),desired);
    lastLocalInputMethod_=local;
    syncingInputMethod_=false;
}

void TextService::syncOutputSettings() {
    const bool local = LoadFrontendSettings().simplifiedChineseOutput;
    const auto shared = sharedOutputState_.read();
    bool next = local;
    if ((!immersiveMode_ && outputSettingsInitialized_ && local != lastLocalSimplifiedOutput_) ||
        (!shared && !immersiveMode_)) {
        sharedOutputState_.write(clientId_, local);
    } else if (shared) {
        next = *shared;
        if (!immersiveMode_ && next != local) SaveSimplifiedOutputPreference(next);
    }
    if (!outputSettingsInitialized_) {
        simplifiedOutput_=next;
    } else {
        bool projected=simplifiedOutput_;
        for (const auto& op : inputQueue_) if (op->kind==InputOperation::Kind::Mode && op->change==ModeChange::Simplified) projected=op->enabled;
        if (projected!=simplifiedOutput_ && next==simplifiedOutput_ &&
            local==lastLocalSimplifiedOutput_) next=projected;
        if (next!=projected) requestModeChange(ModeChange::Simplified,next);
    }
    lastLocalSimplifiedOutput_ = LoadFrontendSettings().simplifiedChineseOutput;
    outputSettingsInitialized_ = true;
}

void TextService::toggleSimplifiedOutput() {
    syncOutputSettings();
    bool next=!simplifiedOutput_;
    for (const auto& op : inputQueue_) if (op->kind==InputOperation::Kind::Mode && op->change==ModeChange::Simplified) next=!op->enabled;
    requestModeChange(ModeChange::Simplified,next);
}

void TextService::closeSymbols() {
    symbolPanel_.hide();
    symbolContext_.Reset();
    ++symbolGeneration_;
}

HRESULT TextService::showSymbols() {
    closeSymbols();
    if (!threadManager_ || clientId_ == TF_CLIENTID_NULL) return E_UNEXPECTED;
    ComPtr<ITfDocumentMgr> document;
    if (FAILED(threadManager_->GetFocus(&document)) || !document) return E_UNEXPECTED;
    ComPtr<ITfContext> context;
    if (FAILED(document->GetTop(&context)) || !context) return E_UNEXPECTED;
    if (!isFocusedContext(context.Get()) || !IsInputContextEnabled(context.Get())) return E_UNEXPECTED;
    const HWND owner = ResolvePopupOwner(context.Get());
    if (!owner) return E_UNEXPECTED;
    POINT point; GetCursorPos(&point);
    RECT anchor{point.x, point.y, point.x, point.y};
    symbolContext_ = context;
    const auto generation = symbolGeneration_;
    if (!symbolPanel_.show(owner, anchor, [this, context, generation](const std::wstring& text) {
        if (!threadManager_ || generation != symbolGeneration_ || symbolContext_.Get() != context.Get()) return;
        requestSymbol(context.Get(),text,generation);
    })) { closeSymbols(); return E_FAIL; }
    return S_OK;
}

HRESULT TextService::insertSymbol(TfEditCookie cookie, ITfContext* context,
                                  const std::wstring& text, unsigned long generation) {
    if (!threadManager_ || generation != symbolGeneration_ || symbolContext_.Get() != context) return S_FALSE;
    if (!isFocusedContext(context) || !IsInputContextEnabled(context)) { closeSymbols(); return S_FALSE; }
    ComPtr<ITfDocumentMgr> document;
    ComPtr<ITfContext> focused;
    if (FAILED(threadManager_->GetFocus(&document)) || !document ||
        FAILED(document->GetTop(&focused)) || focused.Get() != context) { closeSymbols(); return S_FALSE; }
    closeSymbols(); // Invalidate before a queued second selection can run.
    auto result = commitCompositionForModeSwitch(cookie, context);
    if (FAILED(result)) return result;
    // Symbols bypass width conversion and learning; commitText applies only Han conversion.
    retainedInputResult_=std::make_unique<EngineResult>(); retainedInputResult_->committedText=text;
    retainedInputContext_=context; retainedCommitWritten_=false;
    return retryInputResult(cookie,context);
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
    if (!inputQueue_.empty()) return orderedPrintableKey(event);
    if (isFullWidthCharacterKey(event)) return true;
    if (!chineseMode_ || !engine_ || !engine_->ready()) return false;
    // Outside a real TSF composition, application editing/navigation keys
    // belong to the host. Returning TRUE from OnTestKeyDown alone is enough
    // for some hosts to lose the key even if OnKeyDown later returns FALSE.
    if (!composition_ && !candidateActive_ && IsHostEditingKey(event.virtualKey)) {
        return false;
    }
    if (IsInputMethodControlKey(event,effectiveInputMethod_)) return true;
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
    if (foreground) syncInputMethod();
    if (!foreground) {
        closeSymbols();
        clearCandidateWindow();
        shiftTogglePending_ = false;
        cancelInput(); abandonComposition();
    }
    return S_OK;
}

bool TextService::isFocusedContext(ITfContext* context) const {
    if (!uiThreadFocused_ || !threadManager_ || !context) return false;
    BOOL focused=FALSE;
    ComPtr<ITfDocumentMgr> document;
    ComPtr<ITfContext> top;
    return SUCCEEDED(threadManager_->IsThreadFocus(&focused)) && focused &&
        SUCCEEDED(threadManager_->GetFocus(&document)) && document &&
        SUCCEEDED(document->GetTop(&top)) && top.Get()==context;
}

STDMETHODIMP TextService::OnKillThreadFocus() {
    uiThreadFocused_=false;
    closeSymbols(); hideCandidateUi();
    shiftTogglePending_=false; shiftPressedAt_=0;
    // UI focus loss is not destruction of the host's composition. Keep text
    // and engine state; document/context/TIP changes already cancel input.
    return S_OK;
}

STDMETHODIMP TextService::OnSetThreadFocus() {
    uiThreadFocused_=true;
    if (resyncHostMode_ || modeRecoveryPending_ || restoreHostMode_) pumpInput();
    if (candidateActive_ && isFocusedContext(candidateContext_.Get()))
        OnLayoutChange(candidateContext_.Get(),TF_LC_CHANGE,nullptr);
    return S_OK;
}

STDMETHODIMP TextService::OnTestKeyDown(ITfContext* context, WPARAM wparam, LPARAM lparam,
                                        BOOL* eaten) {
    if (!eaten) return E_INVALIDARG;
    *eaten=FALSE;
    if (!IsInputContextEnabled(context)) { shiftTogglePending_=false; return S_OK; }
    syncInputMethod();
    const KeyEvent event = translateKey(wparam, lparam);
    if (symbolPanel_.visible() && event.virtualKey == VK_ESCAPE) { *eaten = TRUE; return S_OK; }
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

STDMETHODIMP TextService::OnTestKeyUp(ITfContext* context, WPARAM wparam, LPARAM,
                                      BOOL* eaten) {
    if (!eaten) return E_INVALIDARG;
    *eaten=FALSE;
    if (!IsInputContextEnabled(context)) { shiftTogglePending_=false; return S_OK; }
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
    *eaten=FALSE;
    if (!IsInputContextEnabled(context)) { closeSymbols(); hideCandidateUi(); shiftTogglePending_=false; return S_OK; }
    syncInputMethod();
    *eaten = FALSE;
    KeyEvent event = translateKey(wparam, lparam);
    if (symbolPanel_.visible() && event.virtualKey == VK_ESCAPE) { closeSymbols(); *eaten = TRUE; return S_OK; }
    if (symbolPanel_.visible()) closeSymbols();
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

    *eaten=requestKey(context,event);
    Trace("KeyDown vk=%u textLen=%zu eaten=%d mode=%d",virtualKey,textLength,*eaten,chineseMode_);
    // ITfKeyEventSink callbacks must not leak a transient context-lock error
    // back to TSF. If no edit session was accepted, leave the key uneaten so
    // the application can handle it normally.
    return S_OK;
}

STDMETHODIMP TextService::OnKeyUp(ITfContext* context, WPARAM wparam, LPARAM, BOOL* eaten) {
    if (!eaten) return E_INVALIDARG;
    *eaten = FALSE;
    if (!IsInputContextEnabled(context)) { shiftTogglePending_=false; return S_OK; }
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
                                const KeyEvent& event, bool* handled, bool* producedResult) {
    if (!context || !handled) return E_INVALIDARG;
    *handled=false;
    if (producedResult) *producedResult=false;
    if (composition_ && compositionContext_.Get() != context) {
        // A focus/context switch can happen without giving the old context a
        // writable edit cookie. Detach it before processing the new key so an
        // old composition cannot permanently block the new document.
        abandonComposition();
    }
    if (composition_ && compositionSimplifiedOutput_ != simplifiedOutput_) {
        const auto status = commitCompositionForModeSwitch(editCookie, context);
        if (FAILED(status)) return status;
    }
    EngineResult result;
    if (!chineseMode_) {
        if (event.control || event.alt || !PrintableCharacter(event)) return S_OK;
        result.handled = true;
        result.committedText = std::wstring(1, PrintableCharacter(event));
        if (fullWidthMode_) result.committedText=ToFullWidth(std::move(result.committedText));
    } else {
        if (!engine_) return E_UNEXPECTED;
        // Ask the host before mutating the engine. StartComposition is allowed
        // to succeed with a null result when the host refuses a composition.
        const bool numpad=event.virtualKey>=VK_NUMPAD0 && event.virtualKey<=VK_DIVIDE;
        if (!composition_ && chineseMode_ && !numpad &&
            (engine_->wantsKey(event) || IsInputMethodControlKey(event,effectiveInputMethod_))) {
            const auto status=ensureComposition(editCookie,context);
            if (FAILED(status)) return status;
        }
        result = engine_->handleKey(event);
        if (fullWidthMode_ && !result.committedText.empty()) {
            result.committedText = ToFullWidth(std::move(result.committedText));
        }
    }
    *handled = result.handled;
    Trace("Engine vk=%u handled=%d commitLen=%zu compositionLen=%zu candidates=%zu",
          event.virtualKey, result.handled, result.committedText.size(),
          result.compositionText.size(), result.candidates.size());
    if (!result.handled && result.committedText.empty()) {
        // Around filters can dismiss a candidate panel while deliberately
        // passing the key through to the host (for example, an arrow key that
        // closes associated-phrase suggestions). Keep the native candidate
        // window in sync even though no composition edit is required.
        updateCandidateWindow(editCookie, context, result);
        if (composition_ && result.compositionText.empty()) endComposition(editCookie,false);
        return S_OK;
    }
    if (result.beep && LoadFrontendSettings().playSoundOnTypingError) {
        MessageBeep(MB_OK);
    }
    retainedInputResult_=std::make_unique<EngineResult>(std::move(result));
    if (producedResult) *producedResult=true;
    retainedInputContext_=context; retainedCommitWritten_=false;
    const HRESULT status = retryInputResult(editCookie,context);
    Trace("UpdateComposition hr=0x%08lX", static_cast<unsigned long>(status));
    if (FAILED(status)) {
        // Retain the result and its write stage; Snapshot may already have
        // consumed committedText. Retrying must not handle/learn this key twice.
        return status;
    }
    return S_OK;
}

HRESULT TextService::ensureComposition(TfEditCookie editCookie, ITfContext* context) {
    if (composition_) return compositionContext_.Get() == context ? S_OK : E_UNEXPECTED;
    compositionSimplifiedOutput_ = simplifiedOutput_;

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
    if (SUCCEEDED(result) && !composition_) return E_ACCESSDENIED;
    if (SUCCEEDED(result)) compositionContext_ = context;
    return result;
}

HRESULT TextService::replaceCompositionText(TfEditCookie editCookie, ITfContext* context,
                                            const std::wstring& text, LONG cursor) {
    HRESULT result = ensureComposition(editCookie, context);
    if (FAILED(result) || !composition_) return FAILED(result) ? result : E_ACCESSDENIED;
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
                                const std::wstring& originalText) {
    const auto text = ConvertOutput(originalText, composition_ && compositionContext_.Get() == context
        ? compositionSimplifiedOutput_ : simplifiedOutput_);
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
        ComPtr<ITfRange> caret;
        result=range->Clone(&caret);
        if (FAILED(result)) return result;
        result = caret->Collapse(editCookie, TF_ANCHOR_END);
        if (FAILED(result)) return result;
        TF_SELECTION selection{};
        selection.range = caret.Get();
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
    if (!composition_ && inputQueue_.empty()) {
        clearCandidateWindow(); if (engine_) engine_->reset(); return true;
    }
    auto op=std::make_shared<InputOperation>(); op->kind=InputOperation::Kind::Commit;
    op->context=inputContext();
    if (!op->context || clientId_==TF_CLIENTID_NULL) return false;
    return enqueueInput(op);
}

HRESULT TextService::commitCompositionForModeSwitch(TfEditCookie editCookie,
                                                     ITfContext* context, ITfComposition* expected) {
    if (expected && composition_.Get() != expected) return S_OK;
    HRESULT result = S_OK;
    if (composition_ && compositionContext_.Get() == context) {
        ComPtr<ITfRange> range;
        result = composition_->GetRange(&range);
        if (SUCCEEDED(result)) {
            std::wstring text;
            result = RangeText(range.Get(), editCookie, text);
            if (SUCCEEDED(result)) {
                text = ConvertOutput(text, compositionSimplifiedOutput_);
                if (!text.empty()) result = range->SetText(editCookie, 0, text.data(), static_cast<LONG>(text.size()));
            }
            ComPtr<ITfRange> caret;
            if (SUCCEEDED(result)) result = range->Clone(&caret);
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
        clearCandidateWindow();
        if (engine_) engine_->reset();
    }
    Trace("ModeCommit complete hr=0x%08lX",
          static_cast<unsigned long>(result));
    return result;
}

HRESULT TextService::terminateComposition(TfEditCookie editCookie) {
    clearCandidateWindow();
    if (engine_) engine_->reset();
    return endComposition(editCookie, true);
}

void TextService::abandonComposition() {
    clearCandidateWindow();
    if (engine_) engine_->reset();

    ComPtr<ITfComposition> oldComposition = composition_;
    ComPtr<ITfContext> oldContext = compositionContext_;
    composition_.Reset();
    compositionContext_.Reset();

    if (!oldComposition || !oldContext || clientId_ == TF_CLIENTID_NULL) return;
    auto* session = new (std::nothrow) TerminateEditSession(oldComposition.Get(), compositionSimplifiedOutput_);
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

HRESULT TextService::retryInputResult(TfEditCookie cookie,ITfContext* context) {
    if (!retainedInputResult_) return S_OK;
    if (retainedInputContext_.Get()!=context) return E_ABORT;
    const auto& result=*retainedInputResult_;
    HRESULT status=S_OK;
    if (!retainedCommitWritten_) {
        retainedCommitNeedsEnd_=composition_ && compositionContext_.Get()==context && !result.committedText.empty();
        if (!result.committedText.empty()) {
            const auto text=ConvertOutput(result.committedText,retainedCommitNeedsEnd_ ? compositionSimplifiedOutput_ : simplifiedOutput_);
            if (retainedCommitNeedsEnd_) {
                status=composition_->GetRange(&retainedCommitRange_);
                if (SUCCEEDED(status)) status=retainedCommitRange_->SetText(cookie,0,text.data(),static_cast<LONG>(text.size()));
            } else {
                ComPtr<ITfInsertAtSelection> insertion;
                status=context->QueryInterface(IID_PPV_ARGS(&insertion));
                if (SUCCEEDED(status)) status=insertion->InsertTextAtSelection(cookie,0,text.data(),static_cast<LONG>(text.size()),&retainedCommitRange_);
            }
            if (FAILED(status)) return status;
        }
        // Persist immediately after the write, before Clone/Collapse/selection.
        // A host may accept insertion yet reject the following caret operation.
        retainedCommitWritten_=true;
    }
    if (!result.committedText.empty()) {
        if (!retainedCommitCaretSet_) {
            if (!retainedCommitRange_) return E_UNEXPECTED;
            ComPtr<ITfRange> caret; status=retainedCommitRange_->Clone(&caret);
            if (SUCCEEDED(status)) status=caret->Collapse(cookie,TF_ANCHOR_END);
            if (SUCCEEDED(status)) {
                TF_SELECTION selection{}; selection.range=caret.Get(); selection.style.ase=TF_AE_NONE;
                status=context->SetSelection(cookie,1,&selection);
            }
            if (FAILED(status)) return status;
            retainedCommitCaretSet_=true;
        }
        if (retainedCommitNeedsEnd_) {
            status=endComposition(cookie,false); if (FAILED(status)) return status;
            retainedCommitNeedsEnd_=false;
        }
    }
    if (!result.compositionText.empty()) {
        status=replaceCompositionText(cookie,context,result.compositionText,result.compositionCursor);
    } else if (composition_ && result.committedText.empty()) status=endComposition(cookie,true);
    if (FAILED(status)) return status;
    updateCandidateWindow(cookie,context,result);
    retainedInputResult_.reset(); retainedInputContext_.Reset(); retainedCommitWritten_=false;
    retainedCommitRange_.Reset(); retainedCommitCaretSet_=false; retainedCommitNeedsEnd_=false;
    return S_OK;
}

void TextService::hideCandidateUi() {
    ++candidateGeneration_;
    pendingLayoutGeneration_ = 0;
    candidateWindow_.hide();
}
void TextService::clearCandidateWindow() {
    hideCandidateUi();
    candidateActive_ = false;
    candidateAnchor_.Reset();
    candidateContext_.Reset();
    layoutCandidates_.clear();
}
void TextService::cancelCandidateLayout(ITfContext* context,unsigned long long generation) {
    if (pendingLayoutGeneration_==generation && candidateGeneration_==generation && candidateContext_.Get()==context)
        pendingLayoutGeneration_=0;
}

void TextService::updateCandidateWindow(TfEditCookie editCookie, ITfContext* context,
                                        const EngineResult& result) {
    if (!result.candidatesVisible || result.candidates.empty()) {
        clearCandidateWindow();
        return;
    }
    ++candidateGeneration_;
    pendingLayoutGeneration_ = 0;
    candidateAnchor_.Reset();

    candidateContext_ = context;
    layoutCandidates_ = result.candidates;
    layoutHighlightedCandidate_ = result.highlightedCandidate;
    // Candidate activity is an engine state, even while the host has no layout.
    candidateActive_ = true;
    if (!composition_) {
        TF_SELECTION selection{};
        ULONG fetched = 0;
        if (FAILED(context->GetSelection(editCookie, TF_DEFAULT_SELECTION, 1,
                                         &selection, &fetched)) || !fetched) {
            clearCandidateWindow();
            return;
        }
        candidateAnchor_.Attach(selection.range);
        candidateAnchor_->Collapse(editCookie, TF_ANCHOR_END);
    }
    refreshCandidateLayout(editCookie, context, candidateGeneration_);
}

HRESULT TextService::refreshCandidateLayout(TfEditCookie editCookie, ITfContext* context,
                                             unsigned long long generation) {
    // A queued layout callback must not resurrect candidates after Esc, a new
    // key, focus loss, a mode switch, or deactivation.
    if (generation != candidateGeneration_ || candidateContext_.Get() != context ||
        !candidateActive_) return S_OK;
    if (pendingLayoutGeneration_ == generation) pendingLayoutGeneration_ = 0;
    if (!isFocusedContext(context) || !IsInputContextEnabled(context)) {
        candidateWindow_.hide(); return S_OK;
    }
    ComPtr<ITfRange> range;
    if (composition_ && compositionContext_.Get() == context) composition_->GetRange(&range);
    if (!range) range = candidateAnchor_;
    if (!range) return S_OK;

    ComPtr<ITfContextView> view;
    HRESULT status = context->GetActiveView(&view);
    RECT textRect{};
    BOOL clipped = FALSE;
    HWND owner = nullptr;
    if (SUCCEEDED(status)) status = view->GetTextExt(editCookie, range.Get(), &textRect, &clipped);
    if (SUCCEEDED(status)) owner = ResolvePopupOwner(context);
    if (FAILED(status) || !owner || textRect.bottom <= textRect.top || textRect.right < textRect.left) {
        // TS_E_NOLAYOUT is transient. Keep the candidates and wait for the
        // host's ITfTextLayoutSink notification instead of requiring a key.
        candidateWindow_.hide();
        Trace("Candidate layout deferred hr=0x%08lX generation=%llu",
              static_cast<unsigned long>(status), generation);
        return S_OK;
    }
    candidateWindow_.show(owner, textRect, layoutCandidates_, layoutHighlightedCandidate_);
    Trace("Candidate active=1 count=%zu generation=%llu", layoutCandidates_.size(), generation);
    return S_OK;
}

STDMETHODIMP TextService::OnLayoutChange(ITfContext* context, TfLayoutCode code,
                                         ITfContextView*) {
    if (code == TF_LC_DESTROY && context == candidateContext_.Get()) { hideCandidateUi(); return S_OK; }
    if (code != TF_LC_CHANGE || !context || context != candidateContext_.Get() ||
        !isFocusedContext(context) || !IsInputContextEnabled(context) ||
        !candidateActive_ || clientId_ == TF_CLIENTID_NULL ||
        pendingLayoutGeneration_ == candidateGeneration_) return S_OK;
    const auto generation = candidateGeneration_;
    auto* session = new (std::nothrow) CandidateLayoutEditSession(this, context, generation);
    if (!session) return E_OUTOFMEMORY;
    pendingLayoutGeneration_ = generation;
    HRESULT editResult = E_FAIL;
    const HRESULT request = context->RequestEditSession(
        clientId_, session, TF_ES_ASYNC | TF_ES_READ, &editResult);
    session->Release();
    if ((FAILED(request) || FAILED(editResult)) && pendingLayoutGeneration_ == generation)
        pendingLayoutGeneration_ = 0;
    Trace("Candidate layout request=0x%08lX edit=0x%08lX generation=%llu",
          static_cast<unsigned long>(request), static_cast<unsigned long>(editResult), generation);
    return S_OK;
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
    if (!context || !editRecord || editingInput_ ||
        (!composition_ && !candidateActive_ && inputQueue_.empty())) {
        return S_OK;
    }

    BOOL selectionChanged = FALSE;
    if (FAILED(editRecord->GetSelectionStatus(&selectionChanged)) ||
        !selectionChanged) {
        return S_OK;
    }
    if (!composition_ && !candidateActive_ && !inputQueue_.empty()) {
        // Before the first deferred composition exists, a host caret move is
        // still a different insertion target even within the same context.
        cancelInput(); return S_OK;
    }
    if (!selectionMatchesTrackedState(editCookie, context)) {
        Trace("Selection left active input state; abandoning composition");
        cancelInput(); abandonComposition();
    }
    return S_OK;
}

STDMETHODIMP TextService::OnCompositionTerminated(TfEditCookie editCookie,
                                                   ITfComposition* composition) {
    if (composition_.Get() == composition) {
        if (!endingComposition_ && compositionSimplifiedOutput_) {
            ComPtr<ITfRange> range;
            if (SUCCEEDED(composition->GetRange(&range))) {
                std::wstring text;
                if (SUCCEEDED(RangeText(range.Get(), editCookie, text))) {
                    text = ConvertOutput(text, true);
                    if (!text.empty()) range->SetText(editCookie, 0, text.data(), static_cast<LONG>(text.size()));
                }
            }
        }
        composition_.Reset();
        compositionContext_.Reset();
        if (!endingComposition_) {
            cancelInput();
            clearCandidateWindow();
            if (engine_) engine_->reset();
        }
    }
    return S_OK;
}

STDMETHODIMP TextService::OnInitDocumentMgr(ITfDocumentMgr*) { return S_OK; }
STDMETHODIMP TextService::OnUninitDocumentMgr(ITfDocumentMgr* documentManager) {
    closeSymbols();
    auto context=inputContext(); ComPtr<ITfDocumentMgr> owner;
    if (context && SUCCEEDED(context->GetDocumentMgr(&owner)) && owner.Get()==documentManager) {
        cancelInput(); abandonComposition(); unadviseTextEditSink();
    }
    return S_OK;
}
STDMETHODIMP TextService::OnSetFocus(ITfDocumentMgr* focused,ITfDocumentMgr*) {
    closeSymbols(); ComPtr<ITfContext> context;
    if (focused) focused->GetTop(&context);
    auto previous=inputContext();
    if (previous && previous.Get()!=context.Get()) { cancelInput(); abandonComposition(); }
    adviseTextEditSink(context.Get());
    if (focused) syncInputMethod();
    return S_OK;
}
STDMETHODIMP TextService::OnPushContext(ITfContext* context) {
    closeSymbols(); auto previous=inputContext();
    if (previous && previous.Get()!=context) { cancelInput(); abandonComposition(); }
    adviseTextEditSink(context); return S_OK;
}
STDMETHODIMP TextService::OnPopContext(ITfContext* context) {
    closeSymbols();
    if (inputContext().Get()==context) { cancelInput(); abandonComposition(); }
    if (textEditContext_.Get()==context) {
        unadviseTextEditSink(); ComPtr<ITfDocumentMgr> focused; ComPtr<ITfContext> top;
        if (threadManager_ && SUCCEEDED(threadManager_->GetFocus(&focused)) && focused &&
            SUCCEEDED(focused->GetTop(&top)) && top.Get()!=context) adviseTextEditSink(top.Get());
    }
    return S_OK;
}

HRESULT TextService::reconcileHostMode(bool chinese,bool fromConversion) {
    const auto checked=[&](HRESULT result) {
        if (FAILED(result)) scheduleModeRecovery(chinese,fullWidthMode_);
        return result;
    };
    ComPtr<ITfCompartmentMgr> manager;
    ComPtr<ITfCompartment> other;
    auto result=threadManager_.As(&manager);
    if (FAILED(result)) return checked(result);
    result=manager->GetCompartment(fromConversion ? GUID_COMPARTMENT_KEYBOARD_OPENCLOSE :
        GUID_COMPARTMENT_KEYBOARD_INPUTMODE_CONVERSION,&other);
    if (FAILED(result)) return checked(result);
    VARIANT value{};
    result=other->GetValue(&value);
    if (FAILED(result)) { VariantClear(&value); return checked(result); }
    if (value.vt!=VT_I4 && value.vt!=VT_EMPTY) { VariantClear(&value); return checked(E_INVALIDARG); }
    const bool valid=value.vt==VT_I4;
    LONG previous=valid ? value.lVal : 0;
    VariantClear(&value);
    const LONG next=fromConversion ? (chinese ? 1 : 0) :
        (chinese ? previous|TF_CONVERSIONMODE_NATIVE : previous&~static_cast<LONG>(TF_CONVERSIONMODE_NATIVE));
    if (valid && previous==next) return S_OK;
    value.vt=VT_I4; value.lVal=next;
    updatingModeCompartments_=true;
    result=other->SetValue(clientId_,&value);
    updatingModeCompartments_=false;
    if (FAILED(result)) Trace("Host mode reconcile failed hr=0x%08lX",static_cast<unsigned long>(result));
    return checked(result);
}

void TextService::observeInputMode(bool chinese,bool fullWidth,bool fromConversion) {
    // A new external notification supersedes our retained recovery target,
    // including when its logical mode already matches the local engine.
    const bool recovering=modeRecoveryPending_ || restoreHostMode_;
    modeRecoveryPending_=false; restoreHostMode_=false;
    lastHostModeFromConversion_=fromConversion;
    if (!recovering && projectedChineseMode()==chinese && projectedWidthMode()==fullWidth) return;
    auto op=std::make_shared<InputOperation>(); op->kind=InputOperation::Kind::Mode;
    op->change=ModeChange::Host; op->enabled=chinese; op->fullWidth=fullWidth;
    op->fromConversion=fromConversion;
    op->context=inputContext();
    if (!composition_ && !retainedInputResult_ && inputQueue_.empty()) op->context.Reset();
    enqueueInput(op);
}

HRESULT TextService::resyncCancelledHostMode() {
    ComPtr<ITfCompartmentMgr> manager;
    auto result=threadManager_.As(&manager);
    if (FAILED(result)) return result;
    ComPtr<ITfCompartment> open,conversion;
    result=manager->GetCompartment(GUID_COMPARTMENT_KEYBOARD_OPENCLOSE,&open);
    if (FAILED(result)) return result;
    result=manager->GetCompartment(GUID_COMPARTMENT_KEYBOARD_INPUTMODE_CONVERSION,&conversion);
    if (FAILED(result)) return result;
    VARIANT openValue{},conversionValue{};
    result=open->GetValue(&openValue);
    if (SUCCEEDED(result)) result=conversion->GetValue(&conversionValue);
    const bool hasOpen=openValue.vt==VT_I4,hasConversion=conversionValue.vt==VT_I4;
    const bool fromConversion=hasConversion && (lastHostModeFromConversion_ || !hasOpen);
    const bool chinese=fromConversion ? (conversionValue.lVal & TF_CONVERSIONMODE_NATIVE)!=0 : openValue.lVal!=0;
    const bool width=hasConversion ? (conversionValue.lVal & TF_CONVERSIONMODE_FULLSHAPE)!=0 : fullWidthMode_;
    VariantClear(&openValue); VariantClear(&conversionValue);
    // Leave the latch set on a read failure; the next focus/key can retry.
    if (FAILED(result)) { Trace("Canceled host mode read failed hr=0x%08lX",static_cast<unsigned long>(result)); return result; }
    resyncHostMode_=false;
    if (!hasOpen && !hasConversion) return S_FALSE;
    chineseMode_=chinese; fullWidthMode_=width;
    shiftTogglePending_=false; shiftPressedAt_=0; refreshLangBar();
    return reconcileHostMode(chinese,fromConversion);
}

STDMETHODIMP TextService::OnChange(REFGUID guid) {
    if (!threadManager_) return S_OK;
    // The two synchronous writes represent one mode change. Don't let the
    // first notification read the second compartment's previous value.
    if (updatingModeCompartments_) return S_OK;

    const bool previousNotification=inModeNotification_;
    inModeNotification_=true;
    if (guid == GUID_COMPARTMENT_KEYBOARD_INPUTMODE_CONVERSION) {
        ComPtr<ITfCompartmentMgr> manager;
        ComPtr<ITfCompartment> compartment;
        VARIANT value;
        VariantInit(&value);
        if (SUCCEEDED(threadManager_.As(&manager)) &&
            SUCCEEDED(manager->GetCompartment(
                GUID_COMPARTMENT_KEYBOARD_INPUTMODE_CONVERSION, &compartment)) &&
            SUCCEEDED(compartment->GetValue(&value)) && value.vt == VT_I4) {
            const bool full=(value.lVal & static_cast<LONG>(TF_CONVERSIONMODE_FULLSHAPE))!=0;
            const bool enabled = (value.lVal & static_cast<LONG>(TF_CONVERSIONMODE_NATIVE)) != 0;
            observeInputMode(enabled,full,true);
            Trace("InputWidth changed full=%d", fullWidthMode_);
        }
        VariantClear(&value);
        inModeNotification_=previousNotification;
        return S_OK;
    }

    if (guid != GUID_COMPARTMENT_KEYBOARD_OPENCLOSE) { inModeNotification_=previousNotification; return S_OK; }

    ComPtr<ITfCompartmentMgr> manager;
    ComPtr<ITfCompartment> compartment;
    VARIANT value;
    VariantInit(&value);
    if (SUCCEEDED(threadManager_.As(&manager)) &&
        SUCCEEDED(manager->GetCompartment(GUID_COMPARTMENT_KEYBOARD_OPENCLOSE,
                                         &compartment)) &&
        SUCCEEDED(compartment->GetValue(&value)) && value.vt == VT_I4) {
        const bool enabled = value.lVal != 0;
        observeInputMode(enabled,projectedWidthMode(),false);
        Trace("InputMode changed chinese=%d", chineseMode_);
    }
    VariantClear(&value);
    inModeNotification_=previousNotification;
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
