#pragma once
// Isolated TSF contract model: writing a compartment in its own OnChange is
// rejected, just as in the separately verified Windows compartment API.
#include <Windows.h>
#include <msctf.h>
#include <ocidl.h>
#include <wrl/client.h>
#include <cstring>
#include <map>
#include <deque>

namespace KeyKey::WindowsTsf::Test {
using Microsoft::WRL::ComPtr;
class Compartment final : public ITfCompartment, public ITfSource {
public:
    explicit Compartment(REFGUID id) : guid(id) {}
    STDMETHODIMP QueryInterface(REFIID iid,void** object) override {
        if (!object) return E_POINTER; *object=nullptr;
        if (iid==IID_IUnknown || iid==IID_ITfCompartment) *object=static_cast<ITfCompartment*>(this);
        else if (iid==IID_ITfSource) *object=static_cast<ITfSource*>(this);
        else return E_NOINTERFACE;
        AddRef(); return S_OK;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return ++references; }
    STDMETHODIMP_(ULONG) Release() override { auto left=--references; if (!left) delete this; return left; }
    STDMETHODIMP GetValue(VARIANT* result) override {
        if (!result) return E_POINTER;
        VariantInit(result);
        if (FAILED(readResult)) return readResult;
        result->vt=type; result->lVal=value; return S_OK;
    }
    STDMETHODIMP SetValue(TfClientId,const VARIANT* next) override {
        ++attempts;
        if (notifying) { ++reentrantWrites; return E_UNEXPECTED; }
        auto result=writeResult;
        if (!writeResults.empty()) { result=writeResults.front(); writeResults.pop_front(); }
        if (FAILED(result)) return result;
        if (!next || next->vt!=VT_I4) return E_INVALIDARG;
        ++writes; type=VT_I4; value=next->lVal;
        notifying=true;
        if (sink) sink->OnChange(guid);
        notifying=false; return S_OK;
    }
    STDMETHODIMP AdviseSink(REFIID iid,IUnknown* object,DWORD* cookie) override {
        if (iid!=IID_ITfCompartmentEventSink) return E_NOINTERFACE;
        if (sink) return E_FAIL;
        const auto result=object->QueryInterface(IID_PPV_ARGS(&sink));
        if (SUCCEEDED(result)) *cookie=1; return result;
    }
    STDMETHODIMP UnadviseSink(DWORD) override { sink.Reset(); return S_OK; }
    GUID guid;
    VARTYPE type=VT_EMPTY;
    LONG value=0;
    HRESULT writeResult=S_OK;
    HRESULT readResult=S_OK;
    std::deque<HRESULT> writeResults;
    int writes=0, reentrantWrites=0, attempts=0;
    bool notifying=false;
    ComPtr<ITfCompartmentEventSink> sink;
private: ULONG references=1;
};
struct GuidLess { bool operator()(const GUID& a,const GUID& b) const { return std::memcmp(&a,&b,sizeof(GUID))<0; } };
class Compartments final : public ITfCompartmentMgr {
public:
    STDMETHODIMP QueryInterface(REFIID iid,void** object) override {
        if (!object) return E_POINTER; *object=nullptr;
        if (iid!=IID_IUnknown && iid!=IID_ITfCompartmentMgr) return E_NOINTERFACE;
        *object=static_cast<ITfCompartmentMgr*>(this); AddRef(); return S_OK;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return ++references; }
    STDMETHODIMP_(ULONG) Release() override { auto left=--references; if (!left) delete this; return left; }
    Compartment* get(REFGUID guid) {
        auto& result=values[guid]; if (!result) result.Attach(new Compartment(guid)); return result.Get();
    }
    STDMETHODIMP GetCompartment(REFGUID guid,ITfCompartment** object) override {
        if (!object) return E_POINTER; *object=get(guid); (*object)->AddRef(); return S_OK;
    }
    STDMETHODIMP ClearCompartment(TfClientId,REFGUID guid) override { values.erase(guid); return S_OK; }
    STDMETHODIMP EnumCompartments(IEnumGUID**) override { return E_NOTIMPL; }
private:
    ULONG references=1;
    std::map<GUID,ComPtr<Compartment>,GuidLess> values;
};
} // namespace KeyKey::WindowsTsf::Test
