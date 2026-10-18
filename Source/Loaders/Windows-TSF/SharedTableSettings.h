#pragma once
#include "SharedOutputState.h"

namespace KeyKey::WindowsTsf {
struct TablePreviewSettings {
    bool composeWhileTyping = false;
    bool prefixCandidates = false;
    bool clearOnError = true;

    LONG encoded() const {
        return 0x100 | (composeWhileTyping ? 1 : 0) |
            (prefixCandidates ? 2 : 0) | (clearOnError && !composeWhileTyping ? 4 : 0);
    }
};

inline GUID TableSettingsGuid(bool simplex = false) {
    GUID guid = {0xf05e73db, 0xf8ec, 0x4de7, {0xa0, 0x38, 0xd7, 0xd2, 0x82, 0x84, 0x29, 0x21}};
    if (simplex) guid.Data1 ^= 0x6921138f;
    return OutputCompartmentGuid(guid);
}

// Publish one atomic snapshot. No typed text, phrases or learning leave the
// host's profile; Search only receives these three candidate-behavior flags.
class SharedTableSettings final {
public:
    HRESULT connect(ITfThreadMgr* manager, REFGUID guid = TableSettingsGuid()) {
        reset();
        if (!manager) return E_INVALIDARG;
        Microsoft::WRL::ComPtr<ITfCompartmentMgr> global;
        const auto result = manager->GetGlobalCompartment(&global);
        return FAILED(result) ? result : global->GetCompartment(guid, &compartment_);
    }
    void reset() { compartment_.Reset(); }
    std::optional<TablePreviewSettings> read() const {
        if (!compartment_) return {};
        VARIANT value;
        VariantInit(&value);
        const auto result = compartment_->GetValue(&value);
        std::optional<TablePreviewSettings> settings;
        if (SUCCEEDED(result) && value.vt == VT_I4 &&
            (value.lVal & ~7L) == 0x100 && (value.lVal & 5) != 5) {
            settings = TablePreviewSettings{(value.lVal & 1) != 0,
                (value.lVal & 2) != 0, (value.lVal & 4) != 0};
        }
        VariantClear(&value);
        return settings;
    }
    HRESULT write(TfClientId client, const TablePreviewSettings& settings) {
        if (!compartment_) return E_UNEXPECTED;
        VARIANT value;
        VariantInit(&value);
        value.vt = VT_I4;
        value.lVal = settings.encoded();
        return compartment_->SetValue(client, &value);
    }
private:
    Microsoft::WRL::ComPtr<ITfCompartment> compartment_;
};
}
