#pragma once
#include <Windows.h>
#include <msctf.h>
#include <wrl/client.h>
#include <optional>

namespace KeyKey::WindowsTsf {
inline constexpr GUID kSimplifiedOutputCompartment =
    {0xe9f8731a, 0xc194, 0x4557, {0x8d, 0x6b, 0x12, 0x20, 0xac, 0x44, 0x23, 0x7a}};

inline GUID OutputCompartmentGuid(GUID guid = kSimplifiedOutputCompartment) {
    wchar_t profile[32768];
    const auto length = GetEnvironmentVariableW(L"KEYKEY_TSF_TEST_PROFILE_DIR", profile, 32768);
    if (length && length < 32768) {
        unsigned long long hash = 14695981039346656037ull;
        for (DWORD i = 0; i < length; ++i) { hash ^= profile[i]; hash *= 1099511628211ull; }
        guid.Data1 ^= static_cast<unsigned long>(hash);
        for (int i = 0; i < 8; ++i) guid.Data4[i] ^= static_cast<unsigned char>(hash >> (i * 8));
    }
    return guid;
}

class SharedOutputState final {
public:
    HRESULT connect(ITfThreadMgr* manager, REFGUID guid = OutputCompartmentGuid()) {
        reset();
        if (!manager) return E_INVALIDARG;
        Microsoft::WRL::ComPtr<ITfCompartmentMgr> global;
        auto result = manager->GetGlobalCompartment(&global);
        return FAILED(result) ? result : global->GetCompartment(guid, &compartment_);
    }
    void reset() { compartment_.Reset(); }
    std::optional<bool> read() const {
        if (!compartment_) return {};
        VARIANT value;
        VariantInit(&value);
        const auto result = compartment_->GetValue(&value);
        std::optional<bool> enabled;
        if (SUCCEEDED(result) && value.vt == VT_I4 && (value.lVal == 1 || value.lVal == 2))
            enabled = value.lVal == 2;
        VariantClear(&value);
        return enabled;
    }
    HRESULT write(TfClientId client, bool enabled) {
        if (!compartment_) return E_UNEXPECTED;
        VARIANT value;
        VariantInit(&value);
        value.vt = VT_I4;
        value.lVal = enabled ? 2 : 1;
        return compartment_->SetValue(client, &value);
    }
private:
    Microsoft::WRL::ComPtr<ITfCompartment> compartment_;
};
}
