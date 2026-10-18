#pragma once
#include "SharedOutputState.h"
#include <algorithm>
#include <string>

namespace KeyKey::WindowsTsf {
inline GUID RuntimePreferencesGuid() {
    return OutputCompartmentGuid(
        {0xd86315ad, 0x670a, 0x440b, {0x9a, 0x90, 0xe3, 0x5e, 0x47, 0x11, 0x92, 0x43}});
}

// Global integer slots carry a compact UTF-8 snapshot. One revision marks the
// complete publication; readers cache it until the revision changes.
class SharedRuntimePreferences final {
public:
    static constexpr UINT maximumLength = 32768;
    HRESULT connect(ITfThreadMgr* manager, REFGUID guid = RuntimePreferencesGuid()) {
        reset();
        if (!manager) return E_INVALIDARG;
        guid_ = guid;
        const auto result = manager->GetGlobalCompartment(&global_);
        return FAILED(result) ? result : global_->GetCompartment(guid_, &revision_);
    }
    void reset() {
        revision_.Reset(); global_.Reset(); applied_.clear(); cached_.clear();
        cachedRevision_ = 0; slotsUsed_ = 0;
    }
    bool alreadyApplied(const std::wstring& snapshot) const { return applied_ == snapshot; }
    void applied(const std::wstring& snapshot) { applied_ = snapshot; }
    std::optional<std::wstring> read() const {
        const auto first = readInteger(revision_.Get());
        if (!first || *first <= 0 || (*first & 1)) return {};
        if (*first == cachedRevision_ && !cached_.empty()) return cached_;
        const auto length = readSlot(1);
        if (!length || *length <= 0 || *length > static_cast<LONG>(maximumLength)) return {};
        std::string bytes(static_cast<size_t>(*length), '\0');
        const size_t count = (bytes.size() + 3) / 4;
        slotsUsed_ = std::max(slotsUsed_, count);
        for (size_t i = 0; i < count; ++i) {
            const auto slot = readSlot(static_cast<ULONG>(i + 2));
            if (!slot) return {};
            const auto value = static_cast<ULONG>(*slot);
            for (size_t j = 0; j < 4 && i * 4 + j < bytes.size(); ++j)
                bytes[i * 4 + j] = static_cast<char>(value >> (j * 8));
        }
        if (readInteger(revision_.Get()) != first) return {};
        const int lengthWide = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
            bytes.data(), static_cast<int>(bytes.size()), nullptr, 0);
        if (lengthWide <= 0) return {};
        std::wstring result(static_cast<size_t>(lengthWide), L'\0');
        if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, bytes.data(),
            static_cast<int>(bytes.size()), result.data(), lengthWide)) return {};
        cachedRevision_ = *first; cached_ = result;
        return result;
    }
    HRESULT write(TfClientId client, const std::wstring& snapshot) {
        if (!revision_) return E_UNEXPECTED;
        if (snapshot.empty() || snapshot.size() > maximumLength) return E_INVALIDARG;
        const int size = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS,
            snapshot.data(), static_cast<int>(snapshot.size()), nullptr, 0, nullptr, nullptr);
        if (size <= 0 || size > static_cast<int>(maximumLength)) return E_INVALIDARG;
        std::string bytes(static_cast<size_t>(size), '\0');
        if (!WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, snapshot.data(),
            static_cast<int>(snapshot.size()), bytes.data(), size, nullptr, nullptr)) return E_INVALIDARG;
        // Serialize desktop publishers. Private-profile readers need no mutex
        // access or changes to AppContainer/file permissions.
        wchar_t guidText[40]{};
        if (!StringFromGUID2(guid_, guidText, 40)) return E_FAIL;
        const auto name = std::wstring(L"Local\\chichi77.KeyKey.Preferences.") + guidText;
        struct Lease {
            HANDLE handle = nullptr;
            bool locked = false;
            ~Lease() { if (locked) ReleaseMutex(handle); if (handle) CloseHandle(handle); }
        } lease;
        lease.handle = CreateMutexW(nullptr, FALSE, name.c_str());
        if (!lease.handle) return HRESULT_FROM_WIN32(GetLastError());
        const DWORD wait = WaitForSingleObject(lease.handle, 250);
        lease.locked = wait == WAIT_OBJECT_0 || wait == WAIT_ABANDONED;
        if (!lease.locked) return HRESULT_FROM_WIN32(wait == WAIT_TIMEOUT ? ERROR_TIMEOUT : GetLastError());
        const auto previous = readInteger(revision_.Get()).value_or(0);
        const LONG next = previous > 0 && previous < 0x7ffffffc ? (previous & ~1L) + 2 : 2;
        auto result = writeInteger(revision_.Get(), client, next - 1);
        if (result != S_OK) return FAILED(result) ? result : E_FAIL;
        result = writeSlot(1, client, size);
        const size_t count = (bytes.size() + 3) / 4;
        slotsUsed_ = std::max(slotsUsed_, count);
        for (size_t i = 0; result == S_OK && i < count; ++i) {
            ULONG value = 0;
            for (size_t j = 0; j < 4 && i * 4 + j < bytes.size(); ++j)
                value |= static_cast<ULONG>(static_cast<unsigned char>(bytes[i * 4 + j])) << (j * 8);
            result = writeSlot(static_cast<ULONG>(i + 2), client, static_cast<LONG>(value));
        }
        if (result == S_OK) result = writeInteger(revision_.Get(), client, next);
        cachedRevision_ = 0; cached_.clear();
        return result == S_OK ? S_OK : FAILED(result) ? result : E_FAIL;
    }
    HRESULT clear(TfClientId client) {
        if (!global_) return E_UNEXPECTED;
        HRESULT result = S_OK;
        for (size_t i = 0; i < slotsUsed_ + 2; ++i) {
            const auto status = global_->ClearCompartment(client, slotGuid(static_cast<ULONG>(i)));
            if (FAILED(status)) result = status;
        }
        reset();
        return result;
    }
private:
    GUID slotGuid(ULONG index) const {
        GUID result = guid_;
        result.Data1 ^= 0x9e3779b9u * index;
        result.Data3 ^= static_cast<USHORT>(index);
        return result;
    }
    static std::optional<LONG> readInteger(ITfCompartment* state) {
        if (!state) return {};
        VARIANT value; VariantInit(&value);
        const auto result = state->GetValue(&value);
        std::optional<LONG> number;
        if (result == S_OK && value.vt == VT_I4) number = value.lVal;
        VariantClear(&value);
        return number;
    }
    static HRESULT writeInteger(ITfCompartment* state, TfClientId client, LONG number) {
        if (!state) return E_UNEXPECTED;
        VARIANT value; VariantInit(&value); value.vt = VT_I4; value.lVal = number;
        return state->SetValue(client, &value);
    }
    std::optional<LONG> readSlot(ULONG index) const {
        Microsoft::WRL::ComPtr<ITfCompartment> state;
        return global_ && SUCCEEDED(global_->GetCompartment(slotGuid(index), &state))
            ? readInteger(state.Get()) : std::optional<LONG>{};
    }
    HRESULT writeSlot(ULONG index, TfClientId client, LONG number) {
        Microsoft::WRL::ComPtr<ITfCompartment> state;
        const auto result = global_->GetCompartment(slotGuid(index), &state);
        return FAILED(result) ? result : writeInteger(state.Get(), client, number);
    }
    GUID guid_{};
    Microsoft::WRL::ComPtr<ITfCompartmentMgr> global_;
    Microsoft::WRL::ComPtr<ITfCompartment> revision_;
    std::wstring applied_;
    mutable std::wstring cached_;
    mutable LONG cachedRevision_ = 0;
    mutable size_t slotsUsed_ = 0;
};
}
