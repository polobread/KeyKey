#pragma once

#include <Windows.h>
#include <msctf.h>
#include <wrl/client.h>
#include <initializer_list>

namespace KeyKey::WindowsTsf {

inline bool IsInputContextEnabled(ITfContext* context) {
    if (!context) return false;
    Microsoft::WRL::ComPtr<ITfCompartmentMgr> compartments;
    if (SUCCEEDED(context->QueryInterface(IID_PPV_ARGS(&compartments)))) {
        for (const auto& guid : {GUID_COMPARTMENT_KEYBOARD_DISABLED, GUID_COMPARTMENT_EMPTYCONTEXT}) {
            Microsoft::WRL::ComPtr<ITfCompartment> compartment;
            VARIANT value{};
            const bool disabled = SUCCEEDED(compartments->GetCompartment(guid, &compartment)) &&
                SUCCEEDED(compartment->GetValue(&value)) && value.vt == VT_I4 && value.lVal != 0;
            VariantClear(&value);
            if (disabled) return false;
        }
    }
    TF_STATUS status{};
    return FAILED(context->GetStatus(&status)) || !(status.dwDynamicFlags & TF_SD_READONLY);
}

inline bool IsPopupOwner(HWND owner) {
    DWORD process = 0;
    return owner && IsWindow(owner) && GetWindowThreadProcessId(owner, &process) &&
        process == GetCurrentProcessId();
}

inline HWND ResolvePopupOwner(ITfContext* context) {
    Microsoft::WRL::ComPtr<ITfContextView> view;
    HWND owner = nullptr;
    if (!context || FAILED(context->GetActiveView(&view)) || !view ||
        FAILED(view->GetWnd(&owner)) || !owner) owner = GetFocus();
    return IsPopupOwner(owner) ? owner : nullptr;
}

} // namespace KeyKey::WindowsTsf
