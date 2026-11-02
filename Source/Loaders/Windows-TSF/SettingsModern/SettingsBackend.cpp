#include <Windows.h>
#include <algorithm>
#include <cstdint>
#include <string>
#include <vector>
#include <memory>

#include "UserDataStore.h"
#include "sqlite3.h"
#include "SharedOutputState.h"
#include "StartupInputMode.h"
#include "SharedTableSettings.h"
#include "FrontendSettings.h"
#include "GuanyinmaWindowsUserData.h"

namespace {
struct Collection { std::wstring source; std::wstring display; };
std::vector<Collection> collections;
struct UserDataHandle {
    std::vector<KeyKey::WindowsTsf::UserPhrase> rows;
    std::unique_ptr<KeyKey::WindowsTsf::GuanyinmaWindowsUserData> rust;
};

void CopyTo(const std::wstring& source, wchar_t* target, int capacity) {
    if (!target || capacity <= 0) return;
    const auto length = std::min(source.size(), static_cast<size_t>(capacity - 1));
    source.copy(target, length);
    target[length] = L'\0';
}
}

extern "C" {
__declspec(dllexport) void* __cdecl KeyKeyOpenUserData(const wchar_t* model) {
    try {
        if (!model) return nullptr;
        auto handle = std::make_unique<UserDataHandle>();
        handle->rust = std::make_unique<KeyKey::WindowsTsf::GuanyinmaWindowsUserData>(model);
        return handle.release();
    } catch (...) { return nullptr; }
}
__declspec(dllexport) void __cdecl KeyKeyCloseUserData(void* handle) { delete static_cast<UserDataHandle*>(handle); }
__declspec(dllexport) int __cdecl KeyKeyUserDataLoad(void* opaque) {
    auto* handle = static_cast<UserDataHandle*>(opaque);
    if (!handle) return -1;
    try {
        handle->rows = handle->rust->load();
        return static_cast<int>(handle->rows.size());
    } catch (...) { handle->rows.clear(); return -1; }
}
__declspec(dllexport) int __cdecl KeyKeyUserDataPhraseAt(void* opaque, int index, std::int64_t* row,
    wchar_t* text, int textCapacity, wchar_t* reading, int readingCapacity) {
    const auto* handle = static_cast<UserDataHandle*>(opaque);
    if (!handle || !row || index < 0 || static_cast<size_t>(index) >= handle->rows.size()) return 0;
    const auto& phrase = handle->rows[index]; *row = phrase.rowid;
    CopyTo(phrase.text, text, textCapacity); CopyTo(phrase.reading, reading, readingCapacity); return 1;
}
// Rust row IDs resolve only in the window handle's current snapshot.
__declspec(dllexport) int __cdecl KeyKeyUserDataSave(void* opaque, std::int64_t row, const wchar_t* text, const wchar_t* reading) {
    auto* handle = static_cast<UserDataHandle*>(opaque);
    if (!handle || !text || !reading) return 0;
    try {
        return handle->rust->save({row, text, reading});
    } catch (...) { return 0; }
}
__declspec(dllexport) int __cdecl KeyKeyUserDataDelete(void* opaque, std::int64_t row) {
    auto* handle = static_cast<UserDataHandle*>(opaque); if (!handle) return 0;
    try {
        return handle->rust->remove(row);
    } catch (...) { return 0; }
}
__declspec(dllexport) int __cdecl KeyKeyUserDataReset(void* opaque) {
    auto* handle = static_cast<UserDataHandle*>(opaque); if (!handle) return 0;
    try {
        return handle->rust->resetLearning();
    } catch (...) { return 0; }
}
__declspec(dllexport) int __cdecl KeyKeyUserDataArchive(void* opaque, const wchar_t* path, int exportData) {
    auto* handle = static_cast<UserDataHandle*>(opaque); if (!handle || !path) return 0;
    try {
        return exportData ? handle->rust->exportData(path) : handle->rust->importData(path);
    } catch (...) { return 0; }
}
__declspec(dllexport) int __cdecl KeyKeyReadSimplifiedOutput() {
    Microsoft::WRL::ComPtr<ITfThreadMgrEx> manager;
    if (FAILED(CoCreateInstance(CLSID_TF_ThreadMgr, nullptr, CLSCTX_INPROC_SERVER,
            IID_PPV_ARGS(&manager)))) return -1;
    TfClientId client = TF_CLIENTID_NULL;
    if (FAILED(manager->ActivateEx(&client, TF_TMAE_NOACTIVATETIP | TF_TMAE_NOACTIVATEKEYBOARDLAYOUT))) return -1;
    KeyKey::WindowsTsf::SharedOutputState state;
    const auto connected = state.connect(manager.Get());
    const auto value = SUCCEEDED(connected) ? state.read() : std::optional<bool>{};
    state.reset();
    manager->Deactivate();
    return value.has_value() ? (*value ? 1 : 0) : -1;
}
static int PublishBooleanPreference(int enabled, REFGUID guid) {
    Microsoft::WRL::ComPtr<ITfThreadMgrEx> manager;
    if (FAILED(CoCreateInstance(CLSID_TF_ThreadMgr, nullptr, CLSCTX_INPROC_SERVER,
            IID_PPV_ARGS(&manager)))) return 0;
    TfClientId client = TF_CLIENTID_NULL;
    if (FAILED(manager->ActivateEx(&client, TF_TMAE_NOACTIVATETIP | TF_TMAE_NOACTIVATEKEYBOARDLAYOUT))) return 0;
    KeyKey::WindowsTsf::SharedOutputState state;
    const auto connected = state.connect(manager.Get(), guid);
    const auto written = SUCCEEDED(connected) ? state.write(client, enabled != 0) : connected;
    state.reset();
    manager->Deactivate();
    return SUCCEEDED(written) ? 1 : 0;
}
__declspec(dllexport) int __cdecl KeyKeyPublishSimplifiedOutput(int enabled) {
    return PublishBooleanPreference(enabled, KeyKey::WindowsTsf::OutputCompartmentGuid());
}
__declspec(dllexport) int __cdecl KeyKeyPublishDefaultChineseMode(int enabled) {
    return PublishBooleanPreference(enabled, KeyKey::WindowsTsf::StartupInputModeGuid());
}
__declspec(dllexport) int __cdecl KeyKeyPublishTablePreviewSettings(int simplex, int compose, int prefix, int clear) {
    Microsoft::WRL::ComPtr<ITfThreadMgrEx> manager;
    if (FAILED(CoCreateInstance(CLSID_TF_ThreadMgr, nullptr, CLSCTX_INPROC_SERVER,
            IID_PPV_ARGS(&manager)))) return 0;
    TfClientId client = TF_CLIENTID_NULL;
    if (FAILED(manager->ActivateEx(&client, TF_TMAE_NOACTIVATETIP | TF_TMAE_NOACTIVATEKEYBOARDLAYOUT))) return 0;
    KeyKey::WindowsTsf::SharedTableSettings state;
    const auto connected = state.connect(manager.Get(), KeyKey::WindowsTsf::TableSettingsGuid(simplex != 0));
    const auto written = SUCCEEDED(connected)
        ? state.write(client, {compose != 0, !simplex && prefix != 0, clear != 0}) : connected;
    state.reset();
    manager->Deactivate();
    return SUCCEEDED(written) ? 1 : 0;
}
__declspec(dllexport) int __cdecl KeyKeyPublishRuntimePreferences() {
    Microsoft::WRL::ComPtr<ITfThreadMgrEx> manager;
    if (FAILED(CoCreateInstance(CLSID_TF_ThreadMgr, nullptr, CLSCTX_INPROC_SERVER,
            IID_PPV_ARGS(&manager)))) return 0;
    TfClientId client = TF_CLIENTID_NULL;
    if (FAILED(manager->ActivateEx(&client, TF_TMAE_NOACTIVATETIP | TF_TMAE_NOACTIVATEKEYBOARDLAYOUT))) return 0;
    KeyKey::WindowsTsf::SharedRuntimePreferences state;
    const auto connected = state.connect(manager.Get());
    const auto snapshot = KeyKey::WindowsTsf::RuntimePreferencesSnapshot();
    const auto written = SUCCEEDED(connected) ? state.write(client, snapshot) : connected;
    state.reset();
    manager->Deactivate();
    return SUCCEEDED(written) ? 1 : 0;
}
// Each lookup owns an immutable snapshot. Caller releases it exactly once;
// buffers are caller-owned UTF-16 and capacities include the trailing NUL.
__declspec(dllexport) void* __cdecl KeyKeyLookupReadings(const wchar_t* path, const wchar_t* phrase, int* status) {
    if (!status) return nullptr;
    *status = -1;
    if (!path || !phrase) return nullptr;
    try {
        auto* result = new KeyKey::WindowsTsf::ReadingLookup(
            KeyKey::WindowsTsf::LookupPhraseReadings(path, phrase));
        *status = static_cast<int>(result->status);
        return result;
    } catch (...) { *status = -2; return nullptr; }
}
__declspec(dllexport) void __cdecl KeyKeyFreeReadings(void* handle) {
    delete static_cast<KeyKey::WindowsTsf::ReadingLookup*>(handle);
}
__declspec(dllexport) int __cdecl KeyKeyReadingCount(void* handle, int character) {
    const auto* result = static_cast<KeyKey::WindowsTsf::ReadingLookup*>(handle);
    if (!result) return -1;
    if (character == -2) return static_cast<int>(result->characters.size());
    if (character == -1) return static_cast<int>(result->wholePhraseReadings.size());
    if (character < 0 || static_cast<size_t>(character) >= result->characters.size()) return -1;
    return static_cast<int>(result->characters[character].readings.size());
}
// index -1 with a character index returns its original code point. Returns
// required capacity; writes only when the complete string fits (no truncation).
__declspec(dllexport) int __cdecl KeyKeyReadingAt(void* handle, int character, int index, wchar_t* target, int capacity) {
    const auto* result = static_cast<KeyKey::WindowsTsf::ReadingLookup*>(handle);
    if (!result) return 0;
    const std::wstring* value = nullptr;
    if (character == -1 && index >= 0 && static_cast<size_t>(index) < result->wholePhraseReadings.size())
        value = &result->wholePhraseReadings[index];
    else if (character >= 0 && static_cast<size_t>(character) < result->characters.size()) {
        const auto& item = result->characters[character];
        if (index == -1) value = &item.text;
        else if (index >= 0 && static_cast<size_t>(index) < item.readings.size()) value = &item.readings[index];
    }
    if (!value) return 0;
    const int required = static_cast<int>(value->size() + 1);
    if (target && capacity >= required) CopyTo(*value, target, capacity);
    return required;
}
__declspec(dllexport) int __cdecl KeyKeyLoadCollections(const wchar_t* path) {
    collections.clear();
    sqlite3* database = nullptr;
    if (!path || sqlite3_open16(path, &database) != SQLITE_OK) {
        if (database) sqlite3_close(database);
        return 0;
    }
    sqlite3_stmt* statement = nullptr;
    if (sqlite3_prepare_v2(database,
        "SELECT source, display FROM collection_names ORDER BY sortorder, display, rowid",
        -1, &statement, nullptr) == SQLITE_OK) {
        while (sqlite3_step(statement) == SQLITE_ROW) {
            const auto* source = reinterpret_cast<const char*>(sqlite3_column_text(statement, 0));
            const auto* display = reinterpret_cast<const char*>(sqlite3_column_text(statement, 1));
            auto decode = [](const char* utf8) {
                if (!utf8) return std::wstring{};
                const int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                                    utf8, -1, nullptr, 0);
                if (size <= 0) return std::wstring{};
                std::wstring result(static_cast<size_t>(size), L'\0');
                MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8, -1,
                                    result.data(), size);
                result.resize(static_cast<size_t>(size - 1));
                return result;
            };
            collections.push_back({decode(source), decode(display)});
        }
    }
    if (statement) sqlite3_finalize(statement);
    sqlite3_close(database);
    return static_cast<int>(collections.size());
}

__declspec(dllexport) int __cdecl KeyKeyCollectionAt(int index,
                                                     wchar_t* source, int sourceCapacity,
                                                     wchar_t* display, int displayCapacity) {
    if (index < 0 || static_cast<size_t>(index) >= collections.size()) return 0;
    CopyTo(collections[index].source, source, sourceCapacity);
    CopyTo(collections[index].display, display, displayCapacity);
    return 1;
}
}
