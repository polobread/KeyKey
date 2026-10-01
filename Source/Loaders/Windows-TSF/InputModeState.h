#pragma once

#include <Windows.h>
#include <msctf.h>
#include <wrl/client.h>

namespace KeyKey::WindowsTsf {

// Windows hosts can use either compartment to represent the IME's mode.
// Set both, retaining width and the other conversion flags owned by the host.
inline HRESULT WriteChineseMode(ITfCompartmentMgr* manager, TfClientId client,
                                bool enabled) {
    if (!manager) return E_INVALIDARG;
    Microsoft::WRL::ComPtr<ITfCompartment> openClose;
    HRESULT result = manager->GetCompartment(GUID_COMPARTMENT_KEYBOARD_OPENCLOSE, &openClose);
    if (FAILED(result)) return result;
    VARIANT value;
    VariantInit(&value);
    value.vt = VT_I4;
    value.lVal = enabled ? 1 : 0;
    const HRESULT openResult = openClose->SetValue(client, &value);

    Microsoft::WRL::ComPtr<ITfCompartment> conversion;
    result = manager->GetCompartment(GUID_COMPARTMENT_KEYBOARD_INPUTMODE_CONVERSION, &conversion);
    if (FAILED(result)) return FAILED(openResult) ? openResult : result;
    VARIANT current;
    VariantInit(&current);
    LONG mode = 0;
    if (SUCCEEDED(conversion->GetValue(&current)) && current.vt == VT_I4) mode = current.lVal;
    VariantClear(&current);
    value.lVal = enabled ? mode | TF_CONVERSIONMODE_NATIVE
                        : mode & ~static_cast<LONG>(TF_CONVERSIONMODE_NATIVE);
    result = conversion->SetValue(client, &value);
    return FAILED(openResult) ? openResult : result;
}

}  // namespace KeyKey::WindowsTsf
