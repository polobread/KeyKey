#pragma once

#include <Windows.h>
#include <msctf.h>
#include <wrl/client.h>
#include "InputMethods.h"

namespace KeyKey::WindowsTsf {

// Session-wide TSF state, accessible to desktop and AppContainer hosts. Only
// the selected method is shared; preferences and learning remain private.
inline constexpr GUID kSelectedInputMethodCompartment =
    {0x87207fa3, 0xf010, 0x45da, {0x90, 0x46, 0x26, 0x55, 0xd9, 0xe1, 0x31, 0x91}};

class SharedInputMethod final {
public:
    HRESULT connect(ITfThreadMgr* manager, REFGUID guid = kSelectedInputMethodCompartment) {
        compartment_.Reset();
        if (!manager) return E_INVALIDARG;
        Microsoft::WRL::ComPtr<ITfCompartmentMgr> global;
        HRESULT result = manager->GetGlobalCompartment(&global);
        return FAILED(result) ? result : global->GetCompartment(guid, &compartment_);
    }
    void reset() { compartment_.Reset(); }
    const InputMethodDefinition* read() const {
        if (!compartment_) return nullptr;
        VARIANT value;
        VariantInit(&value);
        const HRESULT result = compartment_->GetValue(&value);
        const InputMethodDefinition* method = nullptr;
        if (SUCCEEDED(result) && value.vt == VT_I4) {
            for (const auto& candidate : kInputMethods) {
                if (value.lVal == static_cast<LONG>(candidate.menuId)) method = &candidate;
            }
        }
        VariantClear(&value);
        return method;
    }
    HRESULT write(TfClientId client, const char* identifier) {
        const auto* method = identifier ? FindInputMethod(identifier) : nullptr;
        if (!method) return E_INVALIDARG;
        if (!compartment_) return E_UNEXPECTED;
        VARIANT value;
        VariantInit(&value);
        value.vt = VT_I4;
        value.lVal = static_cast<LONG>(method->menuId);
        return compartment_->SetValue(client, &value);
    }
private:
    Microsoft::WRL::ComPtr<ITfCompartment> compartment_;
};

} // namespace KeyKey::WindowsTsf
