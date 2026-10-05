#pragma once
#include "SharedInputMethod.h"

#include <Windows.h>
#include <ctffunc.h>
#include <msctf.h>
#include <wrl/client.h>

#include <atomic>
#include <memory>
#include <mutex>
#include <deque>

#include "CandidateWindow.h"
#include "KeyKeyEngine.h"
#include "SharedOutputState.h"
#include "SymbolPanel.h"

namespace KeyKey::WindowsTsf {

class LangBarButton;

class TextService final : public ITfTextInputProcessorEx,
                          public ITfKeyEventSink,
                          public ITfCompositionSink,
                          public ITfTextEditSink,
                          public ITfTextLayoutSink,
                          public ITfThreadMgrEventSink,
                          public ITfCompartmentEventSink,
                          public ITfDisplayAttributeProvider,
                          public ITfFunctionProvider,
                          public ITfFnConfigure {
public:
    static HRESULT CreateInstance(IUnknown* outer, REFIID iid, void** object);

    TextService();

    // IUnknown
    STDMETHODIMP QueryInterface(REFIID iid, void** object) override;
    STDMETHODIMP_(ULONG) AddRef() override;
    STDMETHODIMP_(ULONG) Release() override;

    // ITfTextInputProcessor / ITfTextInputProcessorEx
    STDMETHODIMP Activate(ITfThreadMgr* threadManager, TfClientId clientId) override;
    STDMETHODIMP ActivateEx(ITfThreadMgr* threadManager, TfClientId clientId, DWORD flags) override;
    STDMETHODIMP Deactivate() override;

    // ITfKeyEventSink
    STDMETHODIMP OnSetFocus(BOOL foreground) override;
    STDMETHODIMP OnTestKeyDown(ITfContext* context, WPARAM wparam, LPARAM lparam, BOOL* eaten) override;
    STDMETHODIMP OnTestKeyUp(ITfContext* context, WPARAM wparam, LPARAM lparam, BOOL* eaten) override;
    STDMETHODIMP OnKeyDown(ITfContext* context, WPARAM wparam, LPARAM lparam, BOOL* eaten) override;
    STDMETHODIMP OnKeyUp(ITfContext* context, WPARAM wparam, LPARAM lparam, BOOL* eaten) override;
    STDMETHODIMP OnPreservedKey(ITfContext* context, REFGUID guid, BOOL* eaten) override;

    // ITfCompositionSink
    STDMETHODIMP OnCompositionTerminated(TfEditCookie editCookie, ITfComposition* composition) override;

    // ITfTextEditSink
    STDMETHODIMP OnEndEdit(ITfContext* context, TfEditCookie editCookie,
                           ITfEditRecord* editRecord) override;
    STDMETHODIMP OnLayoutChange(ITfContext* context, TfLayoutCode code,
                                ITfContextView* view) override;

    // ITfThreadMgrEventSink
    STDMETHODIMP OnInitDocumentMgr(ITfDocumentMgr* documentManager) override;
    STDMETHODIMP OnUninitDocumentMgr(ITfDocumentMgr* documentManager) override;
    STDMETHODIMP OnSetFocus(ITfDocumentMgr* focused, ITfDocumentMgr* previous) override;
    STDMETHODIMP OnPushContext(ITfContext* context) override;
    STDMETHODIMP OnPopContext(ITfContext* context) override;

    // ITfCompartmentEventSink
    STDMETHODIMP OnChange(REFGUID guid) override;

    // ITfDisplayAttributeProvider
    STDMETHODIMP EnumDisplayAttributeInfo(IEnumTfDisplayAttributeInfo** items) override;
    STDMETHODIMP GetDisplayAttributeInfo(REFGUID guid,
                                          ITfDisplayAttributeInfo** info) override;

    // ITfFunctionProvider
    STDMETHODIMP GetType(GUID* guid) override;
    STDMETHODIMP GetDescription(BSTR* description) override;
    STDMETHODIMP GetFunction(REFGUID guid, REFIID iid, IUnknown** object) override;

    // ITfFunction / ITfFnConfigure
    STDMETHODIMP GetDisplayName(BSTR* name) override;
    STDMETHODIMP Show(HWND parent, LANGID language, REFGUID profile) override;

    HRESULT processKey(TfEditCookie editCookie, ITfContext* context,
                       const KeyEvent& event, bool* handled, bool* producedResult = nullptr);
    bool requestSymbol(ITfContext* context,const std::wstring& text,unsigned long generation);
    HRESULT terminateComposition(TfEditCookie editCookie);
    HRESULT refreshCandidateLayout(TfEditCookie editCookie, ITfContext* context,
                                   unsigned long long generation);
    void cancelCandidateLayout(ITfContext* context,unsigned long long generation);
    HRESULT commitCompositionForModeSwitch(TfEditCookie editCookie,
                                           ITfContext* context, ITfComposition* expected = nullptr);
    bool isChineseMode() const noexcept { return chineseMode_; }
    bool isFullWidthMode() const noexcept { return fullWidthMode_; }
    void toggleChineseMode();
    void toggleFullWidthMode();
    bool selectInputMethod(const char* identifier);
    void syncInputMethod();
    bool isSimplifiedOutput() const noexcept { return simplifiedOutput_; }
    const std::string& effectiveInputMethod() const noexcept {
        return effectiveInputMethod_.empty() && engine_ ? engine_->inputMethod() : effectiveInputMethod_;
    }
    void toggleSimplifiedOutput();
    HRESULT showSymbols();
    HRESULT insertSymbol(TfEditCookie cookie, ITfContext* context,
                         const std::wstring& text, unsigned long generation);
    HRESULT openSettings(HWND parent = nullptr) const;

private:
    friend struct TextServiceTestAccess;
    ~TextService();

    bool isPotentialKey(const KeyEvent& event) const;
    bool isModeToggleKey(const KeyEvent& event) const;
    bool isWidthToggleKey(const KeyEvent& event) const;
    bool isFullWidthCharacterKey(const KeyEvent& event) const;
    HRESULT adviseInputModeSink();
    void unadviseInputModeSink();
    HRESULT adviseTextEditSink(ITfContext* context);
    void unadviseTextEditSink();
    HRESULT adviseFunctionProvider();
    void unadviseFunctionProvider();
    HRESULT initializeLangBar();
    void uninitializeLangBar();
    void refreshLangBar();
    void syncOutputSettings();
    void closeSymbols();
    void setChineseMode(bool enabled);
    void applyStartupInputMode();
    void setFullWidthMode(bool enabled);
    KeyEvent translateKey(WPARAM wparam, LPARAM lparam) const;
    HRESULT adviseSinks();
    void unadviseSinks();
    HRESULT updateComposition(TfEditCookie editCookie, ITfContext* context,
                              const EngineResult& result);
    HRESULT ensureComposition(TfEditCookie editCookie, ITfContext* context);
    HRESULT replaceCompositionText(TfEditCookie editCookie, ITfContext* context,
                                   const std::wstring& text, LONG cursor);
    HRESULT commitText(TfEditCookie editCookie, ITfContext* context,
                       const std::wstring& text);
    HRESULT endComposition(TfEditCookie editCookie, bool clearText);
    bool requestCommitComposition();
    struct InputOperation;
    class InputEditSession;
    enum class ModeChange { Chinese, Width, Method, Simplified };
    bool enqueueInput(const std::shared_ptr<InputOperation>& operation);
    bool requestModeChange(ModeChange change, bool enabled, const std::string& method = {});
    void pumpInput();
    HRESULT runInput(TfEditCookie cookie, const std::shared_ptr<InputOperation>& operation);
    void completeInput(const std::shared_ptr<InputOperation>& operation, HRESULT result, bool cancelled);
    void cancelInput();
    Microsoft::WRL::ComPtr<ITfContext> inputContext() const;
    bool projectedChineseMode() const;
    bool projectedWidthMode() const;
    bool orderedPrintableKey(const KeyEvent& event) const;
    HRESULT retryInputResult(TfEditCookie cookie, ITfContext* context);
    void publishChineseMode(bool enabled);
    void abandonComposition();
    void updateCandidateWindow(TfEditCookie editCookie, ITfContext* context,
                               const EngineResult& result);
    void clearCandidateWindow();
    bool selectionMatchesTrackedState(TfEditCookie editCookie,
                                      ITfContext* context) const;

    std::atomic<ULONG> referenceCount_{1};
    Microsoft::WRL::ComPtr<ITfThreadMgr> threadManager_;
    TfClientId clientId_ = TF_CLIENTID_NULL;
    SharedInputMethod sharedInputMethod_;
    SharedOutputState sharedOutputState_;
    bool simplifiedOutput_ = false;
    bool compositionSimplifiedOutput_ = false;
    bool lastLocalSimplifiedOutput_ = false;
    bool outputSettingsInitialized_ = false;
    SymbolPanel symbolPanel_;
    Microsoft::WRL::ComPtr<ITfContext> symbolContext_;
    unsigned long symbolGeneration_ = 0;
    std::string lastLocalInputMethod_;
    bool immersiveMode_ = false;
    bool syncingInputMethod_ = false;
    DWORD threadManagerCookie_ = TF_INVALID_COOKIE;
    DWORD inputModeCookie_ = TF_INVALID_COOKIE;
    DWORD conversionModeCookie_ = TF_INVALID_COOKIE;
    DWORD textEditCookie_ = TF_INVALID_COOKIE;
    DWORD textLayoutCookie_ = TF_INVALID_COOKIE;
    TfGuidAtom compositionDisplayAttributeAtom_ = TF_INVALID_GUIDATOM;
    bool chineseMode_ = true;
    bool updatingModeCompartments_ = false;
    bool fullWidthMode_ = false;
    bool shiftTogglePending_ = false;
    DWORD shiftPressedAt_ = 0;
    bool candidateActive_ = false;
    bool endingComposition_ = false;
    bool pendingModeCommit_ = false;
    std::deque<std::shared_ptr<InputOperation>> inputQueue_;
    std::shared_ptr<InputOperation> activeInput_;
    unsigned long long inputGeneration_ = 0, nextInputToken_ = 0;
    bool pumpingInput_ = false;
    bool blockedInput_ = false;
    bool editingInput_ = false;
    bool requestKey(ITfContext* context,const KeyEvent& event);
    bool inputLease_ = false;
    std::string effectiveInputMethod_;
    std::string effectiveSettingsSignature_;
    std::unique_ptr<EngineResult> retainedInputResult_;
    Microsoft::WRL::ComPtr<ITfContext> retainedInputContext_;
    bool retainedCommitWritten_ = false;
    bool retainedCommitCaretSet_ = false;
    bool retainedCommitNeedsEnd_ = false;
    Microsoft::WRL::ComPtr<ITfRange> retainedCommitRange_;
    Microsoft::WRL::ComPtr<ITfComposition> composition_;
    Microsoft::WRL::ComPtr<ITfContext> compositionContext_;
    Microsoft::WRL::ComPtr<ITfContext> textEditContext_;
    Microsoft::WRL::ComPtr<ITfRange> candidateAnchor_;
    Microsoft::WRL::ComPtr<ITfContext> candidateContext_;
    std::vector<EngineCandidate> layoutCandidates_;
    size_t layoutHighlightedCandidate_ = 0;
    unsigned long long candidateGeneration_ = 0;
    unsigned long long pendingLayoutGeneration_ = 0;
    std::unique_ptr<KeyKeyEngineSession> engine_;
    CandidateWindow candidateWindow_;
    std::mutex langBarMutex_;
    LangBarButton* modeIconButton_ = nullptr;
    LangBarButton* switchLanguageButton_ = nullptr;
    LangBarButton* fullHalfButton_ = nullptr;
    LangBarButton* settingsButton_ = nullptr;
};

}  // namespace KeyKey::WindowsTsf
