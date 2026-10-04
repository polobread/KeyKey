// Isolated COM behavioral tests; these do not activate/install the input method.
#include "TextService.h"
#include "ModuleState.h"
#include <algorithm>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <vector>
namespace KeyKey::WindowsTsf {
HMODULE g_module = nullptr;
std::atomic<long> g_objectCount{0}, g_serverLocks{0};
struct TextServiceTestAccess {
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
    STDMETHODIMP CompareStart(TfEditCookie,ITfRange*,TfAnchor,LONG*) override { return E_NOTIMPL; }
    STDMETHODIMP CompareEnd(TfEditCookie,ITfRange*,TfAnchor,LONG*) override { return E_NOTIMPL; }
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
class Context final : public ITfContext, public ITfInsertAtSelection, public ITfContextComposition {
public:
    explicit Context(std::shared_ptr<Document> d) : document(std::move(d)) {}
    STDMETHODIMP QueryInterface(REFIID iid, void** result) override {
        if (!result) return E_POINTER; *result = nullptr;
        if (iid == IID_IUnknown || iid == IID_ITfContext) *result = static_cast<ITfContext*>(this);
        else if (iid == IID_ITfInsertAtSelection) *result = static_cast<ITfInsertAtSelection*>(this);
        else if (iid == IID_ITfContextComposition) *result = static_cast<ITfContextComposition*>(this);
        else return E_NOINTERFACE;
        AddRef(); return S_OK;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return ++references; }
    STDMETHODIMP_(ULONG) Release() override { auto count = --references; if (!count) delete this; return count; }
    STDMETHODIMP RequestEditSession(TfClientId,ITfEditSession* session,DWORD flags,HRESULT* result) override {
        if (rejectSync && (flags & TF_ES_SYNC)) { *result=TF_E_SYNCHRONOUS; return TF_E_SYNCHRONOUS; }
        if (queue && !(flags & TF_ES_SYNC)) { pending = session; *result = S_OK; }
        else *result = session->DoEditSession(1);
        return S_OK;
    }
    HRESULT drain() { auto session = pending; pending.Reset(); return session ? session->DoEditSession(1) : S_FALSE; }
    STDMETHODIMP SetSelection(TfEditCookie,ULONG count,const TF_SELECTION* selections) override {
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
        *composition = new Composition(range,sink); return S_OK;
    }
    STDMETHODIMP GetProperty(REFGUID,ITfProperty** property) override { *property=nullptr; return E_NOINTERFACE; }
    STDMETHODIMP InWriteSession(TfClientId,BOOL*) override { return E_NOTIMPL; }
    STDMETHODIMP GetSelection(TfEditCookie,ULONG,ULONG,TF_SELECTION*,ULONG*) override { return E_NOTIMPL; }
    STDMETHODIMP GetStart(TfEditCookie,ITfRange**) override { return E_NOTIMPL; }
    STDMETHODIMP GetEnd(TfEditCookie,ITfRange**) override { return E_NOTIMPL; }
    STDMETHODIMP GetActiveView(ITfContextView**) override { return E_NOTIMPL; }
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
    ComPtr<ITfEditSession> pending;
private: ULONG references = 1;
};
struct Fixture {
    ComPtr<TextService> service;
    std::shared_ptr<Document> document = std::make_shared<Document>();
    ComPtr<Context> context;
    ComPtr<Composition> composition;
    Fixture(const std::wstring& text, bool snapshot = true, bool next = true) {
        service.Attach(new TextService); document->text = text;
        context.Attach(new Context(document));
        ComPtr<Range> range; range.Attach(new Range(document,0,static_cast<LONG>(text.size())));
        composition.Attach(new Composition(range.Get(),service.Get()));
        TextServiceTestAccess::state(*service.Get(),context.Get(),composition.Get(),snapshot,next);
    }
};
int main() {
    try {
        g_module = GetModuleHandleW(nullptr);
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
        std::cout << "TSF output snapshots, commit/preedit, focus, symbols, and stale callbacks passed\n";
        return 0;
    } catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
}
