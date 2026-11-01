// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
// A test-owned UTF-16 document. Contexts, ranges, compositions and edit sessions
// are supplied by Windows TSF, rather than COM mocks.
#pragma once
#include <Windows.h>
#include <olectl.h>
#include <textstor.h>
#include <wrl/client.h>
#include <algorithm>
#include <string>

class DesktopTextStore final : public ITextStoreACP {
public:
    std::wstring text;
    TS_SELECTION_ACP selection{0, 0, {TS_AE_END, FALSE}};
    unsigned locks = 0, writes = 0;
    STDMETHODIMP QueryInterface(REFIID iid, void** out) override {
        if (!out) return E_POINTER;
        *out = nullptr;
        if (iid != IID_IUnknown && iid != IID_ITextStoreACP) return E_NOINTERFACE;
        *out = static_cast<ITextStoreACP*>(this); AddRef(); return S_OK;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return ++references_; }
    STDMETHODIMP_(ULONG) Release() override { auto n = --references_; if (!n) delete this; return n; }
    STDMETHODIMP AdviseSink(REFIID iid, IUnknown* object, DWORD) override {
        if (iid != IID_ITextStoreACPSink) return E_INVALIDARG;
        if (sink_) return CONNECT_E_ADVISELIMIT;
        return object->QueryInterface(IID_PPV_ARGS(&sink_));
    }
    STDMETHODIMP UnadviseSink(IUnknown*) override { sink_.Reset(); return S_OK; }
    STDMETHODIMP RequestLock(DWORD flags, HRESULT* result) override {
        if (!result || !sink_) return E_UNEXPECTED;
        if (lock_) {
            if (flags & TS_LF_SYNC) { *result = TS_E_SYNCHRONOUS; return S_OK; }
            pending_ = flags; *result = TS_S_ASYNC; return S_OK;
        }
        lock_ = flags; ++locks;
        *result = sink_->OnLockGranted(flags);
        lock_ = 0;
        while (pending_) {
            auto next = pending_; pending_ = 0;
            HRESULT ignored; RequestLock(next, &ignored);
        }
        return S_OK;
    }
    STDMETHODIMP GetStatus(TS_STATUS* value) override { *value = {0, TS_SS_NOHIDDENTEXT}; return S_OK; }
    STDMETHODIMP QueryInsert(LONG first, LONG last, ULONG, LONG* a, LONG* b) override {
        if (!valid(first, last)) return TS_E_INVALIDPOS;
        *a = first; *b = last; return S_OK;
    }
    STDMETHODIMP GetSelection(ULONG index, ULONG count, TS_SELECTION_ACP* value, ULONG* fetched) override {
        if (!lock_) return TS_E_NOLOCK;
        *fetched = 0;
        if ((index != TS_DEFAULT_SELECTION && index != 0) || !count) return E_INVALIDARG;
        *value = selection; *fetched = 1; return S_OK;
    }
    STDMETHODIMP SetSelection(ULONG count, const TS_SELECTION_ACP* value) override {
        if ((lock_ & TS_LF_READWRITE) != TS_LF_READWRITE) return TS_E_NOLOCK;
        if (count != 1 || !valid(value->acpStart, value->acpEnd)) return TS_E_INVALIDPOS;
        selection = *value; return S_OK;
    }
    STDMETHODIMP GetText(LONG first, LONG last, WCHAR* buffer, ULONG capacity, ULONG* copied,
                        TS_RUNINFO* runs, ULONG runCapacity, ULONG* runCount, LONG* next) override {
        if (!lock_) return TS_E_NOLOCK;
        if (last == -1) last = static_cast<LONG>(text.size());
        if (!valid(first, last)) return TS_E_INVALIDPOS;
        const auto n = std::min<ULONG>(last - first, capacity ? capacity : (runCapacity ? last - first : 0));
        *copied = capacity ? n : 0; *runCount = runCapacity && n ? 1 : 0; *next = first + n;
        if (*copied) std::copy_n(text.data() + first, n, buffer);
        if (*runCount) runs[0] = {n, TS_RT_PLAIN};
        return S_OK;
    }
    STDMETHODIMP SetText(DWORD, LONG first, LONG last, const WCHAR* value, ULONG count, TS_TEXTCHANGE* change) override {
        if ((lock_ & TS_LF_READWRITE) != TS_LF_READWRITE) return TS_E_NOLOCK;
        if (!valid(first, last)) return TS_E_INVALIDPOS;
        replace(first, last, value, count, change); return S_OK;
    }
    STDMETHODIMP InsertTextAtSelection(DWORD flags, const WCHAR* value, ULONG count, LONG* first,
                                      LONG* last, TS_TEXTCHANGE* change) override {
        if (!lock_) return TS_E_NOLOCK;
        const auto start = selection.acpStart, end = selection.acpEnd;
        if (flags & TS_IAS_QUERYONLY) {
            if (first) *first = start; if (last) *last = end; return S_OK;
        }
        if ((lock_ & TS_LF_READWRITE) != TS_LF_READWRITE) return TS_E_NOLOCK;
        replace(start, end, value, count, change);
        if (first) *first = start; if (last) *last = start + count;
        return S_OK;
    }
    // The application handles keys which TSF leaves uneaten and notifies TSF
    // only after changing its store outside an edit-session lock.
    void insert(const std::wstring& value) {
        TS_TEXTCHANGE change{};
        replace(selection.acpStart, selection.acpEnd, value.data(), static_cast<ULONG>(value.size()), &change);
        if (sink_) { sink_->OnTextChange(0, &change); sink_->OnSelectionChange(); }
    }
    STDMETHODIMP GetFormattedText(LONG, LONG, IDataObject**) override { return E_NOTIMPL; }
    STDMETHODIMP GetEmbedded(LONG, REFGUID, REFIID, IUnknown**) override { return E_NOTIMPL; }
    STDMETHODIMP QueryInsertEmbedded(const GUID*, const FORMATETC*, BOOL* ok) override { *ok = FALSE; return S_OK; }
    STDMETHODIMP InsertEmbedded(DWORD, LONG, LONG, IDataObject*, TS_TEXTCHANGE*) override { return E_NOTIMPL; }
    STDMETHODIMP InsertEmbeddedAtSelection(DWORD, IDataObject*, LONG*, LONG*, TS_TEXTCHANGE*) override { return E_NOTIMPL; }
    STDMETHODIMP RequestSupportedAttrs(DWORD, ULONG, const TS_ATTRID*) override { return S_OK; }
    STDMETHODIMP RequestAttrsAtPosition(LONG, ULONG, const TS_ATTRID*, DWORD) override { return S_OK; }
    STDMETHODIMP RequestAttrsTransitioningAtPosition(LONG, ULONG, const TS_ATTRID*, DWORD) override { return S_OK; }
    STDMETHODIMP FindNextAttrTransition(LONG, LONG halt, ULONG, const TS_ATTRID*, DWORD, LONG* next, BOOL* found, LONG* offset) override {
        *next = halt; *found = FALSE; *offset = 0; return S_OK;
    }
    STDMETHODIMP RetrieveRequestedAttrs(ULONG, TS_ATTRVAL*, ULONG* count) override { *count = 0; return S_OK; }
    STDMETHODIMP GetEndACP(LONG* end) override { if (!lock_) return TS_E_NOLOCK; *end = static_cast<LONG>(text.size()); return S_OK; }
    STDMETHODIMP GetActiveView(TsViewCookie* view) override { *view = 1; return S_OK; }
    STDMETHODIMP GetACPFromPoint(TsViewCookie, const POINT*, DWORD, LONG*) override { return TS_E_NOLAYOUT; }
    STDMETHODIMP GetTextExt(TsViewCookie, LONG, LONG, RECT*, BOOL*) override { return TS_E_NOLAYOUT; }
    STDMETHODIMP GetScreenExt(TsViewCookie, RECT* bounds) override { *bounds = {}; return S_OK; }
    STDMETHODIMP GetWnd(TsViewCookie, HWND* window) override { *window = nullptr; return S_OK; }
private:
    ULONG references_ = 1;
    DWORD lock_ = 0, pending_ = 0;
    Microsoft::WRL::ComPtr<ITextStoreACPSink> sink_;
    bool valid(LONG first, LONG last) const { return first >= 0 && first <= last && static_cast<size_t>(last) <= text.size(); }
    void replace(LONG first, LONG last, const WCHAR* value, ULONG count, TS_TEXTCHANGE* change) {
        text.replace(first, last - first, value ? std::wstring(value, count) : L"");
        selection.acpStart = selection.acpEnd = first + count;
        if (change) *change = {first, last, first + static_cast<LONG>(count)};
        ++writes;
    }
};
