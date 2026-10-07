// Isolated COM behavioral tests; these do not activate/install the input method.
#include "TextService.h"
#include "ModuleState.h"
#include <textstor.h>
#include <algorithm>
#include <iostream>
#include <memory>
#include <filesystem>
#include <fstream>
#include <stdexcept>
#include <vector>
#include <deque>
#include "InputMethods.h"
#include "FrontendSettings.h"
#include "Mandarin.h"
#include "sqlite3.h"
namespace KeyKey::WindowsTsf {
HMODULE g_module = nullptr;
std::atomic<long> g_objectCount{0}, g_serverLocks{0};
struct TextServiceTestAccess {
    static void fresh(TextService& s) { s.composition_.Reset(); s.compositionContext_.Reset(); }
    static size_t queued(TextService& s) { return s.inputQueue_.size(); }
    static void manager(TextService& s,ITfThreadMgr* manager) { s.threadManager_=manager; }
    static bool symbol(TextService& s,ITfContext* context,const std::wstring& text) {
        s.symbolContext_=context; return s.requestSymbol(context,text,s.symbolGeneration_);
    }
    static void start(TextService& s,const std::string& method,bool chinese=true,bool full=false) {
        s.clientId_=1; s.effectiveInputMethod_=method; s.effectiveSettingsSignature_=EngineSettingsSignature(method);
        s.lastLocalInputMethod_=method;
        s.engine_=KeyKeyEngineSession::CreateControlled(method); s.chineseMode_=chinese; s.fullWidthMode_=full;
    }
    static bool key(TextService& s,ITfContext* c,const KeyEvent& event) { return s.requestKey(c,event); }
    static bool wants(TextService& s,const KeyEvent& event) { return s.isPotentialKey(event); }
    static bool engineComposition(TextService& s) { return s.engine_ && s.engine_->hasComposition(); }
    static bool pending(TextService& s) { return s.pendingModeCommit_; }
    static bool retained(TextService& s) { return bool(s.retainedInputResult_); }
    static void cancel(TextService& s) { s.cancelInput(); }
    static void state(TextService& s, ITfContext* c, ITfComposition* composition,
                      bool snapshot, bool next = true) {
        s.composition_ = composition; s.compositionContext_ = c;
        s.compositionSimplifiedOutput_ = snapshot; s.simplifiedOutput_ = next;
        s.clientId_ = 1; s.fullWidthMode_ = true;
    }
    static HRESULT commit(TextService& s, ITfContext* c, const std::wstring& text) {
        return s.commitText(1,c,text);
    }
    static HRESULT update(TextService& s, ITfContext* c, const EngineResult& r) {
        return s.updateComposition(1,c,r);
    }
    static bool request(TextService& s) { return s.requestCommitComposition(); }
    static void abandon(TextService& s) { s.abandonComposition(); }
    static ITfComposition* composition(TextService& s) { return s.composition_.Get(); }
    static void candidates(TextService& s, ITfContext* c, const EngineResult& r) {
        s.updateCandidateWindow(1,c,r);
    }
    static bool candidateActive(TextService& s) { return s.candidateActive_; }
    static bool candidateVisible(TextService& s) {
        return s.candidateWindow_.window_ && IsWindowVisible(s.candidateWindow_.window_);
    }
    static HRESULT track(TextService& s, ITfContext* c) { return s.adviseTextEditSink(c); }
    static void untrack(TextService& s) { s.unadviseTextEditSink(); }
};
}
using namespace KeyKey::WindowsTsf;
using Microsoft::WRL::ComPtr;
void Check(bool value, const char* message) { if (!value) throw std::runtime_error(message); }
void Success(HRESULT value, const char* message) { Check(SUCCEEDED(value),message); }
struct Document {
    std::wstring text;
    LONG caret = 0;
    std::vector<std::wstring> writes, insertions;
    bool failWrite = false;
    bool failSelection = false;
    int failReadAfter = -1, reads = 0;
};
class Range final : public ITfRange {
public:
    Range(std::shared_ptr<Document> d, LONG first, LONG last) : document(std::move(d)), start(first), end(last) {}
    STDMETHODIMP QueryInterface(REFIID iid, void** result) override {
        if (!result) return E_POINTER; *result = nullptr;
        if (iid != IID_IUnknown && iid != IID_ITfRange) return E_NOINTERFACE;
        *result = static_cast<ITfRange*>(this); AddRef(); return S_OK;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return ++references; }
    STDMETHODIMP_(ULONG) Release() override { auto count = --references; if (!count) delete this; return count; }
    STDMETHODIMP GetText(TfEditCookie, DWORD flags, WCHAR* buffer, ULONG capacity, ULONG* count) override {
        if (document->reads++ == document->failReadAfter) { *count=0; return E_FAIL; }
        *count = std::min<ULONG>(capacity, static_cast<ULONG>(end-start));
        std::copy_n(document->text.data()+start,*count,buffer);
        if (flags & TF_TF_MOVESTART) start += *count;
        return S_OK;
    }
    STDMETHODIMP SetText(TfEditCookie, DWORD, const WCHAR* text, LONG count) override {
        if (document->failWrite) return E_FAIL;
        std::wstring replacement = text ? std::wstring(text,count) : L"";
        document->text.replace(start,end-start,replacement); end = start+count;
        document->writes.push_back(replacement); return S_OK;
    }
    STDMETHODIMP Clone(ITfRange** copy) override { *copy = new Range(document,start,end); return S_OK; }
    STDMETHODIMP Collapse(TfEditCookie, TfAnchor anchor) override {
        if (anchor == TF_ANCHOR_END) start = end; else end = start; return S_OK;
    }
    STDMETHODIMP ShiftStart(TfEditCookie, LONG requested, LONG* shifted, const TF_HALTCOND*) override {
        LONG next = std::clamp<LONG>(start+requested,0,end); *shifted = next-start; start = next; return S_OK;
    }
    STDMETHODIMP ShiftEnd(TfEditCookie, LONG requested, LONG* shifted, const TF_HALTCOND*) override {
        LONG next = std::clamp<LONG>(end+requested,start,static_cast<LONG>(document->text.size()));
        *shifted = next-end; end = next; return S_OK;
    }
    STDMETHODIMP GetFormattedText(TfEditCookie,IDataObject**) override { return E_NOTIMPL; }
    STDMETHODIMP GetEmbedded(TfEditCookie,REFGUID,REFIID,IUnknown**) override { return E_NOTIMPL; }
    STDMETHODIMP InsertEmbedded(TfEditCookie,DWORD,IDataObject*) override { return E_NOTIMPL; }
    STDMETHODIMP ShiftStartToRange(TfEditCookie,ITfRange*,TfAnchor) override { return E_NOTIMPL; }
    STDMETHODIMP ShiftEndToRange(TfEditCookie,ITfRange*,TfAnchor) override { return E_NOTIMPL; }
    STDMETHODIMP ShiftStartRegion(TfEditCookie,TfShiftDir,BOOL*) override { return E_NOTIMPL; }
    STDMETHODIMP ShiftEndRegion(TfEditCookie,TfShiftDir,BOOL*) override { return E_NOTIMPL; }
    STDMETHODIMP IsEmpty(TfEditCookie,BOOL* empty) override { *empty = start == end; return S_OK; }
    STDMETHODIMP IsEqualStart(TfEditCookie,ITfRange*,TfAnchor,BOOL*) override { return E_NOTIMPL; }
    STDMETHODIMP IsEqualEnd(TfEditCookie,ITfRange*,TfAnchor,BOOL*) override { return E_NOTIMPL; }
    STDMETHODIMP CompareStart(TfEditCookie,ITfRange* other,TfAnchor anchor,LONG* result) override {
        auto* range=static_cast<Range*>(other); *result=start-(anchor==TF_ANCHOR_START ? range->start : range->end); return S_OK;
    }
    STDMETHODIMP CompareEnd(TfEditCookie,ITfRange* other,TfAnchor anchor,LONG* result) override {
        auto* range=static_cast<Range*>(other); *result=end-(anchor==TF_ANCHOR_START ? range->start : range->end); return S_OK;
    }
    STDMETHODIMP AdjustForInsert(TfEditCookie,ULONG,BOOL*) override { return E_NOTIMPL; }
    STDMETHODIMP GetGravity(TfGravity*,TfGravity*) override { return E_NOTIMPL; }
    STDMETHODIMP SetGravity(TfEditCookie,TfGravity,TfGravity) override { return E_NOTIMPL; }
    STDMETHODIMP GetContext(ITfContext**) override { return E_NOTIMPL; }
    std::shared_ptr<Document> document;
    LONG start, end;
private: ULONG references = 1;
};
class Composition final : public ITfComposition {
public:
    Composition(ITfRange* range, ITfCompositionSink* sink) : range_(range), sink_(sink) {}
    STDMETHODIMP QueryInterface(REFIID iid, void** result) override {
        if (!result) return E_POINTER; *result = nullptr;
        if (iid != IID_IUnknown && iid != IID_ITfComposition) return E_NOINTERFACE;
        *result = static_cast<ITfComposition*>(this); AddRef(); return S_OK;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return ++references; }
    STDMETHODIMP_(ULONG) Release() override { auto count = --references; if (!count) delete this; return count; }
    STDMETHODIMP GetRange(ITfRange** range) override { *range=range_.Get(); (*range)->AddRef(); return S_OK; }
    STDMETHODIMP ShiftStart(TfEditCookie,ITfRange*) override { return E_NOTIMPL; }
    STDMETHODIMP ShiftEnd(TfEditCookie,ITfRange*) override { return E_NOTIMPL; }
    STDMETHODIMP EndComposition(TfEditCookie cookie) override {
        ++ends; if (sink_) sink_->OnCompositionTerminated(cookie,this); return S_OK;
    }
    int ends = 0;
private:
    ULONG references = 1;
    ComPtr<ITfRange> range_;
    ITfCompositionSink* sink_; // Test owner outlives every mock/session.
};
class LayoutView final : public ITfContextView {
public:
    STDMETHODIMP QueryInterface(REFIID iid, void** result) override {
        if (!result) return E_POINTER; *result = nullptr;
        if (iid != IID_IUnknown && iid != IID_ITfContextView) return E_NOINTERFACE;
        *result = static_cast<ITfContextView*>(this); AddRef(); return S_OK;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return ++references; }
    STDMETHODIMP_(ULONG) Release() override { auto count=--references; if (!count) delete this; return count; }
    STDMETHODIMP GetRangeFromPoint(TfEditCookie,const POINT*,DWORD,ITfRange**) override { return E_NOTIMPL; }
    STDMETHODIMP GetTextExt(TfEditCookie,ITfRange*,RECT* rect,BOOL* clipped) override {
        ++queries; *rect=bounds; *clipped=FALSE; return layoutResult;
    }
    STDMETHODIMP GetScreenExt(RECT*) override { return E_NOTIMPL; }
    STDMETHODIMP GetWnd(HWND* window) override { *window=nullptr; return S_OK; }
    HRESULT layoutResult = TS_E_NOLAYOUT;
    RECT bounds{100,100,120,120};
    int queries = 0;
private: ULONG references=1;
};
class Context final : public ITfContext, public ITfInsertAtSelection, public ITfContextComposition,
                      public ITfSource {
public:
    explicit Context(std::shared_ptr<Document> d) : document(std::move(d)) {}
    STDMETHODIMP QueryInterface(REFIID iid, void** result) override {
        if (!result) return E_POINTER; *result = nullptr;
        if (iid == IID_IUnknown || iid == IID_ITfContext) *result = static_cast<ITfContext*>(this);
        else if (iid == IID_ITfInsertAtSelection) *result = static_cast<ITfInsertAtSelection*>(this);
        else if (iid == IID_ITfContextComposition) *result = static_cast<ITfContextComposition*>(this);
        else if (iid == IID_ITfSource) *result = static_cast<ITfSource*>(this);
        else return E_NOINTERFACE;
        AddRef(); return S_OK;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return ++references; }
    STDMETHODIMP_(ULONG) Release() override { auto count = --references; if (!count) delete this; return count; }
    STDMETHODIMP RequestEditSession(TfClientId,ITfEditSession* session,DWORD flags,HRESULT* result) override {
        ++requests; lastFlags=flags;
        if (rejectRequest) { *result=E_FAIL; return E_FAIL; }
        if (rejectSync && (flags & TF_ES_SYNC)) { *result=TF_E_SYNCHRONOUS; return TF_E_SYNCHRONOUS; }
        if (queue && !(flags & TF_ES_SYNC)) {
            if (!pending) pending=session; else queued.emplace_back(session);
            *result = TF_S_ASYNC;
        }
        else *result = session->DoEditSession(1);
        return S_OK;
    }
    HRESULT drain() {
        auto session=pending; pending.Reset();
        if (!queued.empty()) { pending=queued.front(); queued.pop_front(); }
        return session ? session->DoEditSession(1) : S_FALSE;
    }
    void drainAll() { for (int i=0;pending && i<500;++i) drain(); Check(!pending,"Mock sessions failed to drain"); }
    STDMETHODIMP SetSelection(TfEditCookie,ULONG count,const TF_SELECTION* selections) override {
        if (document->failSelection) return E_FAIL;
        if (count != 1) return E_INVALIDARG;
        document->caret = static_cast<Range*>(selections[0].range)->end; return S_OK;
    }
    STDMETHODIMP InsertTextAtSelection(TfEditCookie,DWORD flags,const WCHAR* text,LONG count,ITfRange** range) override {
        LONG start = document->caret;
        if (!(flags & TF_IAS_QUERYONLY)) {
            std::wstring insertion = text ? std::wstring(text,count) : L"";
            document->text.insert(start,insertion); document->insertions.push_back(insertion);
        }
        *range = new Range(document,start,start+count); return S_OK;
    }
    STDMETHODIMP StartComposition(TfEditCookie,ITfRange* range,ITfCompositionSink* sink,ITfComposition** composition) override {
        if (rejectComposition) { *composition=nullptr; return S_OK; }
        *composition = new Composition(range,sink); return S_OK;
    }
    STDMETHODIMP GetProperty(REFGUID,ITfProperty** property) override { *property=nullptr; return E_NOINTERFACE; }
    STDMETHODIMP InWriteSession(TfClientId,BOOL*) override { return E_NOTIMPL; }
    STDMETHODIMP GetSelection(TfEditCookie,ULONG,ULONG,TF_SELECTION* selection,ULONG* fetched) override {
        selection->range=new Range(document,document->caret,document->caret); *fetched=1; return S_OK;
    }
    STDMETHODIMP GetStart(TfEditCookie,ITfRange**) override { return E_NOTIMPL; }
    STDMETHODIMP GetEnd(TfEditCookie,ITfRange**) override { return E_NOTIMPL; }
    STDMETHODIMP GetActiveView(ITfContextView** result) override {
        *result=view.Get(); if (!*result) return E_NOTIMPL; (*result)->AddRef(); return S_OK;
    }
    STDMETHODIMP AdviseSink(REFIID iid,IUnknown* sink,DWORD* cookie) override {
        if (iid == IID_ITfTextLayoutSink) {
            const auto hr=sink->QueryInterface(IID_PPV_ARGS(&layoutSink)); *cookie=2; return hr;
        }
        if (iid == IID_ITfTextEditSink) { *cookie=1; return S_OK; }
        return E_NOINTERFACE;
    }
    STDMETHODIMP UnadviseSink(DWORD cookie) override {
        if (cookie==2) layoutSink.Reset(); return S_OK;
    }
    STDMETHODIMP EnumViews(IEnumTfContextViews**) override { return E_NOTIMPL; }
    STDMETHODIMP GetStatus(TF_STATUS*) override { return E_NOTIMPL; }
    STDMETHODIMP GetAppProperty(REFGUID,ITfReadOnlyProperty**) override { return E_NOTIMPL; }
    STDMETHODIMP TrackProperties(const GUID**,ULONG,const GUID**,ULONG,ITfReadOnlyProperty**) override { return E_NOTIMPL; }
    STDMETHODIMP EnumProperties(IEnumTfProperties**) override { return E_NOTIMPL; }
    STDMETHODIMP GetDocumentMgr(ITfDocumentMgr**) override { return E_NOTIMPL; }
    STDMETHODIMP CreateRangeBackup(TfEditCookie,ITfRange*,ITfRangeBackup**) override { return E_NOTIMPL; }
    STDMETHODIMP InsertEmbeddedAtSelection(TfEditCookie,DWORD,IDataObject*,ITfRange**) override { return E_NOTIMPL; }
    STDMETHODIMP EnumCompositions(IEnumITfCompositionView**) override { return E_NOTIMPL; }
    STDMETHODIMP FindComposition(TfEditCookie,ITfRange*,IEnumITfCompositionView**) override { return E_NOTIMPL; }
    STDMETHODIMP TakeOwnership(TfEditCookie,ITfCompositionView*,ITfCompositionSink*,ITfComposition**) override { return E_NOTIMPL; }
    std::shared_ptr<Document> document;
    bool queue = false;
    bool rejectSync = false;
    bool rejectRequest = false;
    bool rejectComposition = false;
    int requests = 0;
    DWORD lastFlags = 0;
    ComPtr<LayoutView> view;
    ComPtr<ITfTextLayoutSink> layoutSink;
    ComPtr<ITfEditSession> pending;
    std::deque<ComPtr<ITfEditSession>> queued;
private: ULONG references = 1;
};
struct Fixture {
    ComPtr<TextService> service;
    std::shared_ptr<Document> document = std::make_shared<Document>();
    ComPtr<Context> context;
    ComPtr<Composition> composition;
    ~Fixture() {
        TextServiceTestAccess::cancel(*service.Get()); TextServiceTestAccess::untrack(*service.Get());
        context->pending.Reset(); context->queued.clear();
    }
    Fixture(const std::wstring& text, bool snapshot = true, bool next = true) {
        service.Attach(new TextService); document->text = text;
        context.Attach(new Context(document));
        ComPtr<Range> range; range.Attach(new Range(document,0,static_cast<LONG>(text.size())));
        composition.Attach(new Composition(range.Get(),service.Get()));
        TextServiceTestAccess::state(*service.Get(),context.Get(),composition.Get(),snapshot,next);
    }
};
void TestCandidateLayout() {
    const auto profile=std::filesystem::current_path()/"LayoutTestProfiles"/std::to_string(GetCurrentProcessId());
    std::filesystem::create_directories(profile);
    SetEnvironmentVariableW(L"KEYKEY_TSF_TEST_PROFILE_DIR",profile.c_str());
    EngineResult candidates;
    candidates.candidatesVisible=true;
    candidates.candidates={{L"1",L"\x66F8"},{L"2",L"\x8F38"}};
    { Fixture f(L"\x66F8",false,false);
      f.context->view.Attach(new LayoutView); f.context->queue=true;
      Success(TextServiceTestAccess::track(*f.service.Get(),f.context.Get()),"Track layout sink");
      Check(bool(f.context->layoutSink),"Layout sink subscribed");
      TextServiceTestAccess::candidates(*f.service.Get(),f.context.Get(),candidates);
      Check(TextServiceTestAccess::candidateActive(*f.service.Get()) &&
            !TextServiceTestAccess::candidateVisible(*f.service.Get()),"No layout retains pending candidates");
      f.context->view->layoutResult=S_OK;
      Success(f.context->layoutSink->OnLayoutChange(f.context.Get(),TF_LC_CHANGE,f.context->view.Get()),"Layout ready");
      Success(f.context->layoutSink->OnLayoutChange(f.context.Get(),TF_LC_CHANGE,f.context->view.Get()),"Duplicate layout notification");
      Check(f.context->requests==1 && f.context->lastFlags==(TF_ES_ASYNC|TF_ES_READ),"One read-only async refresh");
      Success(f.context->drain(),"Refresh without another keystroke");
      Check(TextServiceTestAccess::candidateVisible(*f.service.Get()),"First character candidates shown after layout");
      Check(f.document->writes.empty() && f.document->text==L"\x66F8" && f.composition->ends==0,
            "Layout refresh never edits or commits text");
      f.context->view->bounds={0,0,0,0};
      f.context->layoutSink->OnLayoutChange(f.context.Get(),TF_LC_CHANGE,f.context->view.Get());
      f.context->drain();
      Check(!TextServiceTestAccess::candidateVisible(*f.service.Get()),"Invisible text hides candidates");
      f.context->view->bounds={100,100,100,120};
      f.context->layoutSink->OnLayoutChange(f.context.Get(),TF_LC_CHANGE,f.context->view.Get());
      f.context->drain();
      Check(TextServiceTestAccess::candidateVisible(*f.service.Get()),"Zero-width caret remains a valid anchor");
      TextServiceTestAccess::untrack(*f.service.Get());
      Check(!f.context->layoutSink && !TextServiceTestAccess::candidateVisible(*f.service.Get()),"Unsubscribe hides candidates"); }
    { Fixture f(L"\x66F8",false,false);
      f.context->view.Attach(new LayoutView); f.context->queue=true;
      TextServiceTestAccess::candidates(*f.service.Get(),f.context.Get(),candidates);
      f.service->OnLayoutChange(f.context.Get(),TF_LC_CHANGE,f.context->view.Get());
      Check(f.context->pending && f.context->requests==1,"Layout cancellation initial request");
      f.context->pending.Reset(); f.context->view->layoutResult=S_OK;
      f.service->OnLayoutChange(f.context.Get(),TF_LC_CHANGE,f.context->view.Get());
      Check(f.context->pending && f.context->requests==2,"Cancelled layout session suppressed valid same-generation retry");
      f.context->drainAll(); Check(TextServiceTestAccess::candidateVisible(*f.service.Get()),"Cancelled layout session could not recover"); }
    for (int cancel=0;cancel<4;++cancel) {
      Fixture f(L"\x66F8",false,false);
      f.context->view.Attach(new LayoutView); f.context->queue=true;
      TextServiceTestAccess::candidates(*f.service.Get(),f.context.Get(),candidates);
      f.service->OnLayoutChange(f.context.Get(),TF_LC_CHANGE,f.context->view.Get());
      Check(bool(f.context->pending),"Layout refresh queued");
      ComPtr<ITfEditSession> stale=f.context->pending; f.context->pending.Reset();
      if (cancel==0) TextServiceTestAccess::candidates(*f.service.Get(),f.context.Get(),EngineResult{});
      if (cancel==1) { f.context->rejectSync=true; f.service->OnSetFocus(FALSE); }
      if (cancel==2) f.service->OnCompositionTerminated(1,f.composition.Get());
      if (cancel==3) TextServiceTestAccess::untrack(*f.service.Get());
      f.context->view->layoutResult=S_OK;
      const auto queries=f.context->view->queries;
      Success(stale->DoEditSession(1),"Stale callback after cancellation");
      Check(!TextServiceTestAccess::candidateVisible(*f.service.Get()) && f.context->view->queries==queries,
            "Cancelled candidates are never resurrected");
      // Focus loss may also have queued a mode commit. Drain any surviving session.
      f.context->drain();
    }
    { Fixture f(L"\x66F8",false,false);
      f.context->view.Attach(new LayoutView); f.context->queue=true;
      TextServiceTestAccess::candidates(*f.service.Get(),f.context.Get(),candidates);
      f.context->rejectRequest=true;
      f.service->OnLayoutChange(f.context.Get(),TF_LC_CHANGE,f.context->view.Get());
      f.context->rejectRequest=false;
      f.service->OnLayoutChange(f.context.Get(),TF_LC_CHANGE,f.context->view.Get());
      Check(f.context->requests==2 && f.context->pending,"Failed request allows next layout retry");
      ComPtr<ITfEditSession> old=f.context->pending; f.context->pending.Reset();
      candidates.candidates={{L"1",L"\x6CD5"}};
      TextServiceTestAccess::candidates(*f.service.Get(),f.context.Get(),candidates);
      f.context->view->layoutResult=S_OK;
      const auto queries=f.context->view->queries;
      old->DoEditSession(1);
      Check(f.context->view->queries==queries,"Old page callback cannot update new candidates");
      f.service->OnLayoutChange(f.context.Get(),TF_LC_CHANGE,f.context->view.Get());
      f.context->drain();
      Check(TextServiceTestAccess::candidateVisible(*f.service.Get()),"Latest candidates recover independently"); }
    { Fixture f(L"\x66F8",false,false);
      f.context->view.Attach(new LayoutView); f.context->queue=true;
      // Associated phrases have no live composition; preserve their caret anchor.
      Success(TextServiceTestAccess::commit(*f.service.Get(),f.context.Get(),L"\x66F8"),"Commit before associated candidates");
      TextServiceTestAccess::candidates(*f.service.Get(),f.context.Get(),candidates);
      ComPtr<Context> other; other.Attach(new Context(f.document));
      f.service->OnLayoutChange(other.Get(),TF_LC_CHANGE,nullptr);
      Check(f.context->requests==0,"Other document cannot refresh pending candidates");
      f.service->OnLayoutChange(f.context.Get(),TF_LC_CHANGE,f.context->view.Get());
      f.context->drain();
      Check(!f.context->pending && !TextServiceTestAccess::candidateVisible(*f.service.Get()),
            "Persistent no-layout waits for another notification without polling");
      f.context->view->layoutResult=S_OK;
      f.service->OnLayoutChange(f.context.Get(),TF_LC_CHANGE,f.context->view.Get());
      f.context->drain();
      Check(TextServiceTestAccess::candidateVisible(*f.service.Get()),"Associated candidates recover after layout"); }
    SetEnvironmentVariableW(L"KEYKEY_TSF_TEST_PROFILE_DIR",nullptr);
}

KeyEvent Character(wchar_t character) {
    KeyEvent event; event.text=std::wstring(1,character);
    event.virtualKey=character>=L'a' && character<=L'z' ? character-L'a'+'A' : character;
    return event;
}
KeyEvent Special(UINT key) { KeyEvent event; event.virtualKey=key; return event; }
void Type(Fixture& f,const wchar_t* keys) {
    for (;*keys;++keys) Check(TextServiceTestAccess::key(*f.service.Get(),f.context.Get(),Character(*keys)),"Real engine did not handle sample key");
}
void Fresh(Fixture& f,const std::string& method="SmartMandarin",bool chinese=true,bool full=false) {
    TextServiceTestAccess::fresh(*f.service.Get());
    TextServiceTestAccess::start(*f.service.Get(),method,chinese,full);
    Success(TextServiceTestAccess::track(*f.service.Get(),f.context.Get()),"Track ordered context");
}
class SelectionEdit final : public ITfEditRecord {
public:
    STDMETHODIMP QueryInterface(REFIID iid,void** result) override {
        if (!result) return E_POINTER; *result=nullptr;
        if (iid!=IID_IUnknown && iid!=IID_ITfEditRecord) return E_NOINTERFACE;
        *result=static_cast<ITfEditRecord*>(this); AddRef(); return S_OK;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return ++references_; }
    STDMETHODIMP_(ULONG) Release() override { return --references_; }
    STDMETHODIMP GetSelectionStatus(BOOL* changed) override { *changed=TRUE; return S_OK; }
    STDMETHODIMP GetTextAndPropertyUpdates(DWORD,const GUID**,ULONG,IEnumTfRanges**) override { return E_NOTIMPL; }
private: ULONG references_=1;
};
class FocusManager final : public ITfThreadMgr,public ITfDocumentMgr {
public:
    explicit FocusManager(ITfContext* context) : context_(context) {}
    STDMETHODIMP QueryInterface(REFIID iid,void** result) override {
        if (!result) return E_POINTER; *result=nullptr;
        if (iid==IID_IUnknown || iid==IID_ITfThreadMgr) *result=static_cast<ITfThreadMgr*>(this);
        else if (iid==IID_ITfDocumentMgr) *result=static_cast<ITfDocumentMgr*>(this);
        else return E_NOINTERFACE;
        AddRef(); return S_OK;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return ++references_; }
    STDMETHODIMP_(ULONG) Release() override { auto left=--references_; if (!left) delete this; return left; }
    STDMETHODIMP Activate(TfClientId* client) override { *client=1; return S_OK; }
    STDMETHODIMP Deactivate() override { return S_OK; }
    STDMETHODIMP CreateDocumentMgr(ITfDocumentMgr**) override { return E_NOTIMPL; }
    STDMETHODIMP EnumDocumentMgrs(IEnumTfDocumentMgrs**) override { return E_NOTIMPL; }
    STDMETHODIMP GetFocus(ITfDocumentMgr** document) override { *document=static_cast<ITfDocumentMgr*>(this); AddRef(); return S_OK; }
    STDMETHODIMP SetFocus(ITfDocumentMgr*) override { return E_NOTIMPL; }
    STDMETHODIMP AssociateFocus(HWND,ITfDocumentMgr*,ITfDocumentMgr**) override { return E_NOTIMPL; }
    STDMETHODIMP IsThreadFocus(BOOL* focus) override { *focus=TRUE; return S_OK; }
    STDMETHODIMP GetFunctionProvider(REFCLSID,ITfFunctionProvider**) override { return E_NOTIMPL; }
    STDMETHODIMP EnumFunctionProviders(IEnumTfFunctionProviders**) override { return E_NOTIMPL; }
    STDMETHODIMP GetGlobalCompartment(ITfCompartmentMgr**) override { return E_NOINTERFACE; }
    STDMETHODIMP CreateContext(TfClientId,DWORD,IUnknown*,ITfContext**,TfEditCookie*) override { return E_NOTIMPL; }
    STDMETHODIMP Push(ITfContext*) override { return E_NOTIMPL; }
    STDMETHODIMP Pop(DWORD) override { return E_NOTIMPL; }
    STDMETHODIMP GetTop(ITfContext** context) override { *context=context_.Get(); (*context)->AddRef(); return S_OK; }
    STDMETHODIMP GetBase(ITfContext** context) override { return GetTop(context); }
    STDMETHODIMP EnumContexts(IEnumTfContexts**) override { return E_NOTIMPL; }
private: ULONG references_=1; ComPtr<ITfContext> context_;
};
void TestControlledBoundaries() {
    const auto settings=SmartMandarinPreferencesPath();
    std::ifstream before(settings,std::ios::binary);
    const std::string original{std::istreambuf_iterator<char>(before),std::istreambuf_iterator<char>()};
    before.close();
    Check(SelectInputMethod("Generic-cj-cin"),"Select non-Smart global method");
    {
        std::ofstream file(settings,std::ios::binary);
        file<<"<plist><dict><key>KeyboardLayout</key><string>Hsu</string>"
              "<key>ShowCandidateListWithSpace</key><string>true</string></dict></plist>";
    }
    auto controlled=KeyKeyEngineSession::CreateControlled("SmartMandarin");
    Check(controlled && controlled->ready(),"Controlled non-primary creation");
    const auto* layout=Formosa::Mandarin::BopomofoKeyboardLayout::LayoutForName("Hsu");
    const auto reading=Formosa::Mandarin::BopomofoSyllable::FromComposedString("ㄋㄧˇ");
    for (char key : layout->keySequenceFromSyllable(reading))
        Check(controlled->handleKey(Character(key)).handled,"Controlled new method adopted stale keyboard layout");
    const auto choices=controlled->handleKey(Character(L' '));
    Check(choices.candidatesVisible && choices.candidates.size()==8 && choices.candidates[0].selectionKey==L"a" &&
          ObservedInputMethod()=="Generic-cj-cin","Named method config not loaded before activate");
    controlled.reset();
    { std::ofstream restore(settings,std::ios::binary); restore<<original; }

    Check(SelectInputMethod("SmartMandarin"),"Same-timestamp primary method");
    { std::ofstream file(settings,std::ios::binary);
      file<<"<plist><dict><key>KeyboardLayout</key><string>Standard</string>"
            "<key>ShowCandidateListWithSpace</key><string>true</string></dict></plist>"; }
    controlled=KeyKeyEngineSession::CreateControlled("SmartMandarin");
    Check(controlled && controlled->ready(),"Load same-timestamp baseline"); controlled.reset();
    const auto timestamp=std::filesystem::last_write_time(settings);
    { std::ofstream file(settings,std::ios::binary);
      file<<"<plist><dict><key>KeyboardLayout</key><string>Hsu</string>"
            "<key>ShowCandidateListWithSpace</key><string>true</string></dict></plist>"; }
    std::filesystem::last_write_time(settings,timestamp);
    Check(std::filesystem::last_write_time(settings)==timestamp,"Same-timestamp test precondition");
    controlled=KeyKeyEngineSession::CreateControlled("SmartMandarin");
    Check(controlled && controlled->ready(),"Same-timestamp controlled creation");
    for (char key : layout->keySequenceFromSyllable(reading))
        Check(controlled->handleKey(Character(key)).handled,"Same-timestamp layout reading");
    const auto sameTimestampChoices=controlled->handleKey(Character(L' '));
    Check(sameTimestampChoices.candidatesVisible && sameTimestampChoices.candidates.size()==8 &&
          sameTimestampChoices.candidates[0].selectionKey==L"a","Changed setting content was acknowledged without load");
    controlled.reset();
    { std::ofstream restore(settings,std::ios::binary); restore<<original; }

    sqlite3* database=nullptr;
    Check(sqlite3_open16((SettingsDirectory()+L"\\SmartMandarinUserData.db").c_str(),&database)==SQLITE_OK,"Open isolated learning DB");
    auto sql=[&](const char* command) { Check(sqlite3_exec(database,command,nullptr,nullptr,nullptr)==SQLITE_OK,"External learning SQL"); };
    auto count=[&] {
        sqlite3_stmt* statement=nullptr;
        Check(sqlite3_prepare_v2(database,"SELECT count(*) FROM user_candidate_override_cache WHERE qstring='ordered-reset-sentinel'",-1,&statement,nullptr)==SQLITE_OK,"Learning count prepare");
        Check(sqlite3_step(statement)==SQLITE_ROW,"Learning count row");
        const int value=sqlite3_column_int(statement,0); sqlite3_finalize(statement); return value;
    };
    sql("INSERT INTO user_candidate_override_cache VALUES('ordered-reset-sentinel','復活');");
    controlled=KeyKeyEngineSession::CreateControlled("SmartMandarin");
    Check(controlled && controlled->ready(),"Learning baseline controlled create");
    controlled.reset();
    Check(count()==1,"Positive control did not load/save the learning sentinel");
    controlled=KeyKeyEngineSession::CreateControlled("SmartMandarin");
    Check(SelectInputMethod("Generic-cj-cin"),"Retire Smart while non-primary");
    BeginOrderedEngineInput();
    sql("DELETE FROM user_candidate_override_cache; DELETE FROM user_bigram_cache;");
    controlled.reset(); EndOrderedEngineInput();
    Check(count()==0,"Controlled non-primary retirement resurrected externally reset learning");
    sqlite3_close(database);
    std::cout<<"Controlled named config before activation, same-timestamp content reload and non-primary learning-reset retirement passed\n";
}
void TestOrderedInput() {
    const auto profile=std::filesystem::current_path()/"LayoutTestProfiles"/std::to_string(GetCurrentProcessId());
    SetEnvironmentVariableW(L"KEYKEY_TSF_TEST_PROFILE_DIR",profile.c_str());
    { Fixture f(L"",false,false); Fresh(f);
      f.context->rejectComposition=true;
      Check(!TextServiceTestAccess::key(*f.service.Get(),f.context.Get(),Character(L'1')),"Refused StartComposition must leave sync key uneaten");
      Check(f.document->text.empty() && !TextServiceTestAccess::engineComposition(*f.service.Get()) &&
            !TextServiceTestAccess::composition(*f.service.Get()),"S_OK/null composition must not mutate engine or crash");
      f.context->rejectComposition=false; Type(f,L"1");
      Check(f.document->text==L"\x3105","First accepted reading was duplicated/lost after refusal"); }
    { Fixture f(L"",false,false); Fresh(f,"SmartMandarin",false,true);
      f.context->queue=true; f.context->rejectSync=true;
      Check(TextServiceTestAccess::key(*f.service.Get(),f.context.Get(),Character(L'1')),"Queue first fullwidth key");
      f.context->rejectSync=false;
      Check(TextServiceTestAccess::key(*f.service.Get(),f.context.Get(),Character(L'2')),"Queue next key behind async");
      Check(f.document->text.empty() && f.context->requests==2,"Second sync key overtook queued first key");
      f.context->drainAll(); Check(f.document->text==L"\xFF11\xFF12","Fullwidth keys must commit in arrival order"); }
    { Fixture f(L"",false,false); Fresh(f);
      f.context->queue=true; f.context->rejectSync=true;
      Type(f,L"1"); f.service->toggleChineseMode();
      Check(f.service->isChineseMode(),"Queued switch changed mode before commit");
      Check(TextServiceTestAccess::wants(*f.service.Get(),Character(L'a')),"Pending halfwidth English must reserve printable input");
      Type(f,L"ab");
      Check(!TextServiceTestAccess::wants(*f.service.Get(),Special(VK_LEFT)),"Pending navigation must remain with host");
      auto shortcut=Character(L'c'); shortcut.control=true;
      Check(!TextServiceTestAccess::wants(*f.service.Get(),shortcut),"Pending shortcut swallowed");
      f.context->drainAll();
      Check(f.document->text==L"\x3105" L"ab" && !f.service->isChineseMode() && !TextServiceTestAccess::engineComposition(*f.service.Get()),
            "Pending key/switch/halfwidth English keys lost text or order"); }
    { Fixture f(L"",false,false); Fresh(f,"SmartMandarin",false,true);
      f.context->queue=true; f.context->rejectSync=true; Type(f,L"1");
      Check(f.service->selectInputMethod("TraditionalMandarin"),"Queue English to Chinese");
      Type(f,L"1"); f.context->drainAll();
      Check(f.document->text==L"\xFF11\x3105" && f.service->isChineseMode() && f.service->effectiveInputMethod()=="TraditionalMandarin",
            "English to Chinese first key used previous mode"); }
    { Fixture f(L"",false,false); Fresh(f,"SmartMandarin",false,true);
      f.document->failSelection=true;
      Check(TextServiceTestAccess::key(*f.service.Get(),f.context.Get(),Character(L'1')),"Written sync key must stay consumed");
      Check(f.document->text==L"\xFF11" && TextServiceTestAccess::retained(*f.service.Get()),"Failed post-write caret must retain stage");
      f.document->failSelection=false; Type(f,L"2");
      Check(f.document->text==L"\xFF11\xFF12" && f.document->insertions.size()==2,"Caret retry inserted the first key twice"); }
    { Fixture f(L"",false,false); Fresh(f); Type(f,L"1");
      const auto original=f.document->text;
      f.document->failWrite=true;
      Check(!f.service->selectInputMethod("TraditionalMandarin"),"Rejected mode commit should report failure");
      Check(f.service->effectiveInputMethod()=="SmartMandarin" && f.service->isChineseMode() &&
            TextServiceTestAccess::engineComposition(*f.service.Get()) && f.document->text==original,"Failed switch discarded original mode/text/engine");
      f.document->failWrite=false; Check(f.service->selectInputMethod("TraditionalMandarin"),"Retry mode switch");
      Check(f.document->text==original && !TextServiceTestAccess::engineComposition(*f.service.Get()),"Successful retry lost or duplicated old reading"); }
    { Fixture f(L"",false,false); Fresh(f); Type(f,L"1");
      f.context->queue=true; f.context->rejectSync=true;
      Check(f.service->selectInputMethod("TraditionalMandarin") && TextServiceTestAccess::pending(*f.service.Get()),"Mode commit pending token");
      f.context->pending.Reset();
      Check(!TextServiceTestAccess::pending(*f.service.Get()) && TextServiceTestAccess::queued(*f.service.Get())==0 &&
            f.service->effectiveInputMethod()=="SmartMandarin" && f.document->text==L"\x3105","Cancelled session latched mode or discarded visible input");
      auto otherDoc=std::make_shared<Document>(); ComPtr<Context> other; other.Attach(new Context(otherDoc));
      Check(TextServiceTestAccess::key(*f.service.Get(),other.Get(),Character(L'1')),"Cancelled mode commit blocked new context");
      Check(otherDoc->text==L"\x3105","Old reading was replayed into new context"); f.context->drainAll(); }
    { Fixture f(L"",false,false); Fresh(f,"SmartMandarin",false,true);
      f.context->queue=true; f.context->rejectSync=true; Type(f,L"1");
      auto stale=f.context->pending; f.context->pending.Reset(); TextServiceTestAccess::cancel(*f.service.Get());
      Type(f,L"2"); const auto count=TextServiceTestAccess::queued(*f.service.Get());
      Success(stale->DoEditSession(1),"Stale edit callback");
      Check(TextServiceTestAccess::queued(*f.service.Get())==count && f.document->text.empty(),"Stale callback affected new token");
      f.context->drainAll(); Check(f.document->text==L"\xFF12","New token failed after stale completion");
      Success(stale->DoEditSession(1),"Duplicate stale callback"); Check(f.document->text==L"\xFF12","Duplicate callback wrote old input"); }
    { Fixture f(L"",false,false); Fresh(f,"SmartMandarin",false,true);
      f.context->queue=true; f.context->rejectSync=true; Type(f,L"1");
      SelectionEdit record; f.document->caret=0;
      Success(f.service->OnEndEdit(f.context.Get(),1,&record),"Host selection change"); f.context->drainAll();
      Check(f.document->text.empty() && TextServiceTestAccess::queued(*f.service.Get())==0,"Deferred key followed host caret movement"); }
    { Fixture f(L"",false,false); Fresh(f); f.context->queue=true; f.context->rejectSync=true;
      Type(f,L"1"); Check(f.service->selectInputMethod("Generic-cj-cin"),"Fast switch A to B");
      f.service->toggleChineseMode(); Type(f,L"a"); f.context->drainAll();
      Check(f.document->text==L"\x3105" L"a" && !f.service->isChineseMode() && f.service->effectiveInputMethod()=="Generic-cj-cin",
            "Fast A/B/English switch took snapshot before preceding key"); }
    { Check(SelectInputMethod("SmartMandarin"),"Seed observed method");
      Fixture f(L"",false,false); Fresh(f);
      ComPtr<FocusManager> manager; manager.Attach(new FocusManager(f.context.Get()));
      TextServiceTestAccess::manager(*f.service.Get(),manager.Get());
      f.context->queue=true; f.context->rejectSync=true; Type(f,L"1");
      Check(f.service->selectInputMethod("Generic-cj-cin"),"Queue explicit method before observation");
      f.service->syncInputMethod(); f.service->syncInputMethod();
      Check(TextServiceTestAccess::queued(*f.service.Get())==2,"Focus/key observation undid pending explicit method");
      f.context->drainAll();
      Check(f.service->effectiveInputMethod()=="Generic-cj-cin" && f.document->text==L"\x3105",
            "Observed old profile reverted queued method or lost original reading"); }
    { Check(SelectInputMethod("SmartMandarin"),"Seed English method");
      Fixture f(L"",false,false); Fresh(f,"SmartMandarin",false);
      ComPtr<FocusManager> manager; manager.Attach(new FocusManager(f.context.Get()));
      TextServiceTestAccess::manager(*f.service.Get(),manager.Get());
      Success(f.service->OnSetFocus(TRUE),"Observe idle English focus");
      Check(!f.service->isChineseMode(),"Observation switched live English mode to Chinese"); }
    { Fixture f(L"",false,false); Fresh(f); f.context->queue=true; f.context->rejectSync=true; Type(f,L"1");
      Check(SelectInputMethod("Generic-cj-cin"),"Other service changes method");
      f.context->drainAll(); Check(f.document->text==L"\x3105","Pending method-pinned key adopted global table method"); }
    { Fixture f(L"",false,false); Fresh(f); f.context->queue=true; f.context->rejectSync=true;
      f.context->rejectComposition=true; Type(f,L"1"); f.context->drain();
      Check(f.document->text.empty() && !TextServiceTestAccess::engineComposition(*f.service.Get()) &&
            TextServiceTestAccess::queued(*f.service.Get())==1,"Async host refusal lost accepted key or mutated engine");
      f.context->rejectComposition=false; Type(f,L"j"); f.context->drainAll();
      Check(f.document->text==L"\x3105\x3128","Retried async refusal duplicated/lost reading keys"); }
    { Fixture f(L"",false,false); Fresh(f,"SmartMandarin",false,true);
      ComPtr<FocusManager> manager; manager.Attach(new FocusManager(f.context.Get()));
      TextServiceTestAccess::manager(*f.service.Get(),manager.Get());
      f.context->queue=true; f.context->rejectSync=true; Type(f,L"1");
      Check(TextServiceTestAccess::symbol(*f.service.Get(),f.context.Get(),L"\x2764\xFE0F"),"Queue symbol behind key");
      Type(f,L"2"); f.context->drainAll();
      Check(f.document->text==L"\xFF11\x2764\xFE0F\xFF12","Symbol commit overtook or lost neighboring keys"); }

    size_t switches=0;
    for (int source=0;source<5;++source) for (int target=0;target<5;++target) if (source!=target) {
        for (int state=0;state<(source==4 ? 1 : 4);++state) {
            const std::string method=source==4 ? "SmartMandarin" : kInputMethods[source].identifier;
            Fixture f(L"",false,false); Fresh(f,method,source!=4);
            if (state==1) Type(f,IsTableInputMethod(method)?L"a":L"1");
            if (state==2) {
                if (method=="SmartMandarin") Type(f,L"su3cl3");
                else { Type(f,IsTableInputMethod(method)?L"ab ":L"1j4"); Type(f,L"1"); }
                Check(!f.document->text.empty(),"Existing Chinese text sample empty");
                Type(f,IsTableInputMethod(method)?L"a":L"1");
            }
            if (state==3) {
                Type(f,IsTableInputMethod(method)?L"ab ":L"1u3");
                if (method=="SmartMandarin") Check(TextServiceTestAccess::key(*f.service.Get(),f.context.Get(),Special(VK_DOWN)),"Open Smart candidates");
                Check(TextServiceTestAccess::candidateActive(*f.service.Get()),"Source candidates not open");
            }
            const auto original=f.document->text;
            if (target==4) f.service->toggleChineseMode();
            else Check(f.service->selectInputMethod(kInputMethods[target].identifier),"Directed switch rejected");
            Check(f.document->text==original && !TextServiceTestAccess::engineComposition(*f.service.Get()) &&
                  !TextServiceTestAccess::candidateActive(*f.service.Get()) && f.service->isChineseMode()==(target!=4),
                  "Directed switch discarded/duplicated source text or left input state");
            if (target!=4) Check(f.service->effectiveInputMethod()==kInputMethods[target].identifier,"Directed switch wrong effective method");
            ++switches;
        }
    }
    Check(switches==68,"Applicable directed switching matrix coverage changed");
    { Fixture f(L"",false,false); Fresh(f); Type(f,L"su3cl3");
      Check(TextServiceTestAccess::key(*f.service.Get(),f.context.Get(),Special(VK_LEFT)),"Sentence cursor left");
      Check(TextServiceTestAccess::key(*f.service.Get(),f.context.Get(),Special(VK_DOWN)),"Sentence candidates"); Type(f,L"2");
      const auto selected=f.document->text; f.service->toggleChineseMode();
      Check(f.document->text==selected && !f.service->isChineseMode(),"Selected candidate/mid-sentence switch lost visible text"); }
    std::cout << "Ordered TSF input: 20 directed mode pairs / 68 applicable states plus refusal, cancellation, FIFO, caret retry and stale callbacks passed\n";
    TestControlledBoundaries();
    SetEnvironmentVariableW(L"KEYKEY_TSF_TEST_PROFILE_DIR",nullptr);
}

int main() {
    try {
        g_module = GetModuleHandleW(nullptr);
        TestCandidateLayout();
        TestOrderedInput();
        const std::wstring traditional=L"\x81FA\x7063", simplified=L"\x53F0\x6E7E";
        { Fixture f(traditional);
          Success(TextServiceTestAccess::commit(*f.service.Get(),f.context.Get(),traditional),"Commit");
          Check(f.document->text == simplified && f.document->writes.size()==1 && f.composition->ends==1,
                "Standard commit converts once and ends once"); }
        { Fixture f(traditional,false,true);
          Success(f.service->commitCompositionForModeSwitch(1,f.context.Get()),"Mode switch old snapshot");
          Check(f.document->text==traditional,"Changing state preserves old traditional snapshot");
          Success(TextServiceTestAccess::commit(*f.service.Get(),f.context.Get(),traditional),"Next commit");
          Check(f.document->text==traditional+simplified,"New state applies to subsequent commit"); }
        { Fixture f(traditional,true,false);
          Success(f.service->OnSetFocus(FALSE),"Focus loss");
          Check(f.document->text==simplified && f.composition->ends==1,"Focus loss converts captured old state"); }
        { Fixture f(traditional,true,false);
          f.context->queue=true; f.context->rejectSync=true;
          Check(TextServiceTestAccess::request(*f.service.Get()) && f.context->pending,"Locked sync request schedules async preserving commit");
          Check(f.document->text==traditional && f.composition->ends==0,"Queued mode switch does not prematurely replace text");
          Success(f.context->drain(),"Deferred mode switch");
          Check(f.document->text==simplified && f.composition->ends==1,"Deferred mode switch uses captured old output state"); }
        { Fixture f(traditional);
          EngineResult result; result.committedText=traditional; result.compositionText=traditional;
          result.compositionCursor=static_cast<LONG>(traditional.size());
          Success(TextServiceTestAccess::update(*f.service.Get(),f.context.Get(),result),"Long push");
          Check(f.document->text==simplified+traditional,"Long push converts committed prefix and keeps preedit traditional");
          Check(f.document->writes.size()==2,"Prefix and preedit each written once"); }
        { Fixture f(traditional);
          Success(f.service->commitCompositionForModeSwitch(1,f.context.Get()),"Finish before symbol");
          const std::wstring symbol=L"v(\xFFE3\xFE36\xFFE3)y \x81FA\x7063 ABC";
          Success(TextServiceTestAccess::commit(*f.service.Get(),f.context.Get(),symbol),"Symbol commit policy");
          Check(f.document->text==simplified+L"v(\xFFE3\xFE36\xFFE3)y \x53F0\x6E7E ABC",
                "Explicit symbols preserve ASCII/fullwidth forms and convert Han once"); }
        { Fixture f(traditional);
          f.document->failWrite=true;
          Check(FAILED(f.service->commitCompositionForModeSwitch(1,f.context.Get())),"Conversion write failure propagates");
          Check(f.composition->ends==0 && TextServiceTestAccess::composition(*f.service.Get())==f.composition.Get(),
                "Failed write preserves composition"); }
        { Fixture f(traditional);
          Success(f.service->OnCompositionTerminated(1,f.composition.Get()),"Host termination");
          Check(f.document->text==simplified && f.document->writes.size()==1,"Host termination converts once");
          Success(f.service->OnCompositionTerminated(1,f.composition.Get()),"Duplicate termination");
          Check(f.document->writes.size()==1,"Repeated host termination does not reconvert"); }
        { Fixture f(traditional);
          f.context->queue=true;
          TextServiceTestAccess::abandon(*f.service.Get());
          Check(f.context->pending && !TextServiceTestAccess::composition(*f.service.Get()),"Abandon queues preserving edit");
          ComPtr<Range> nextRange; nextRange.Attach(new Range(f.document,0,2));
          ComPtr<Composition> next; next.Attach(new Composition(nextRange.Get(),f.service.Get()));
          TextServiceTestAccess::state(*f.service.Get(),f.context.Get(),next.Get(),false,false);
          Success(f.context->drain(),"Queued abandon");
          Check(f.document->text==simplified && f.composition->ends==1,"Abandon preserves and converts old text");
          Check(TextServiceTestAccess::composition(*f.service.Get())==next.Get(),"Stale termination does not reset new composition");
          auto writes=f.document->writes.size();
          Success(f.service->commitCompositionForModeSwitch(1,f.context.Get(),f.composition.Get()),"Stale mode callback");
          Check(f.document->writes.size()==writes && next->ends==0,"Expected-composition mismatch ignores stale callback"); }
        for (int failedRead : {0,1}) {
          const std::wstring longText(2200,L'\x81FA');
          Fixture f(longText); f.document->failReadAfter=failedRead;
          Check(FAILED(f.service->commitCompositionForModeSwitch(1,f.context.Get())),"Failed range read propagates");
          Check(f.document->text==longText && f.document->writes.empty() && f.composition->ends==0,
                "Failed first/partial read does not truncate or terminate composition");
        }
        for (int failedRead : {0,1}) {
          const std::wstring longText(2200,L'\x81FA');
          Fixture f(longText); f.document->failReadAfter=failedRead; f.context->queue=true;
          TextServiceTestAccess::abandon(*f.service.Get());
          Check(FAILED(f.context->drain()),"Abandon range read failure propagates");
          Check(f.document->text==longText && f.document->writes.empty() && f.composition->ends==0,
                "Abandon failed first/partial read keeps original complete text");
        }
        for (int failedRead : {0,1}) {
          const std::wstring longText(2200,L'\x81FA');
          Fixture f(longText); f.document->failReadAfter=failedRead;
          Success(f.service->OnCompositionTerminated(1,f.composition.Get()),"Host termination with failed read");
          Check(f.document->text==longText && f.document->writes.empty(),"Host termination failed read never writes partial text");
        }
        { Fixture f(traditional); f.document->failWrite=true; f.context->queue=true;
          TextServiceTestAccess::abandon(*f.service.Get());
          Check(FAILED(f.context->drain()),"Abandon SetText failure propagates");
          Check(f.document->text==traditional && f.composition->ends==0,"Abandon failed write keeps text and does not end"); }
        { Fixture f(std::wstring(66000,L'\x81FA'));
          const auto original=f.document->text;
          Check(FAILED(f.service->commitCompositionForModeSwitch(1,f.context.Get())),"Oversized range rejected");
          Check(f.document->text==original && f.document->writes.empty() && f.composition->ends==0,
                "Read size bound cannot commit truncated text"); }
        Check(g_objectCount==0,"TextService object cleanup");
        std::cout << "TSF candidate layout recovery, output snapshots, commit/preedit, focus, symbols, and stale callbacks passed\n";
        return 0;
    } catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
}
