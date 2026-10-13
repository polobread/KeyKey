#pragma once

#include <Windows.h>
#include <msctf.h>
#include <wrl/client.h>

namespace KeyKey::WindowsTsf {

struct ChineseModeWriteStatus {
    bool partiallyWritten = false;
    HRESULT rollback = S_OK;
};

// Windows hosts can use either compartment to represent the IME's mode.
// Set both, retaining width and the other conversion flags owned by the host.
inline HRESULT WriteChineseMode(ITfCompartmentMgr* manager, TfClientId client,
                                bool enabled, ChineseModeWriteStatus* status = nullptr) {
    if (status) *status={};
    if (!manager) return E_INVALIDARG;
    Microsoft::WRL::ComPtr<ITfCompartment> openClose;
    HRESULT result = manager->GetCompartment(GUID_COMPARTMENT_KEYBOARD_OPENCLOSE, &openClose);
    if (FAILED(result)) return result;
    Microsoft::WRL::ComPtr<ITfCompartment> conversion;
    result = manager->GetCompartment(GUID_COMPARTMENT_KEYBOARD_INPUTMODE_CONVERSION, &conversion);
    if (FAILED(result)) return result;
    VARIANT current;
    VariantInit(&current);
    LONG mode = 0;
    result=conversion->GetValue(&current);
    const bool validConversion=current.vt==VT_I4;
    if (SUCCEEDED(result) && validConversion) mode = current.lVal;
    if (SUCCEEDED(result) && !validConversion && current.vt!=VT_EMPTY) result=E_INVALIDARG;
    VariantClear(&current);
    if (FAILED(result)) return result;
    VARIANT previous{};
    result=openClose->GetValue(&previous);
    if (FAILED(result)) { VariantClear(&previous); return result; }
    if (previous.vt!=VT_I4 && previous.vt!=VT_EMPTY) { VariantClear(&previous); return E_INVALIDARG; }
    VARIANT value{};
    value.vt=VT_I4; value.lVal=enabled ? 1 : 0;
    const bool changedOpen=previous.vt!=VT_I4 || previous.lVal!=value.lVal;
    result=changedOpen ? openClose->SetValue(client,&value) : S_OK;
    if (FAILED(result)) { VariantClear(&previous); return result; }
    value.lVal = enabled ? mode | TF_CONVERSIONMODE_NATIVE
                        : mode & ~static_cast<LONG>(TF_CONVERSIONMODE_NATIVE);
    result = validConversion && mode==value.lVal ? S_OK : conversion->SetValue(client, &value);
    if (FAILED(result) && changedOpen) {
        // Never clear a predefined compartment to restore VT_EMPTY: that can
        // invalidate the host's compartment and event subscriptions. Report it
        // for deferred recovery to the retained logical mode instead.
        const auto rollback=previous.vt==VT_I4 ? openClose->SetValue(client,&previous) : E_UNEXPECTED;
        if (status) { status->partiallyWritten=true; status->rollback=rollback; }
    }
    VariantClear(&previous);
    return result;
}

}  // namespace KeyKey::WindowsTsf
