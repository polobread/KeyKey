#include <Windows.h>
#include <algorithm>
#include <cstdint>
#include <string>
#include <vector>

#include "UserDataStore.h"
#include "sqlite3.h"
#include "SharedOutputState.h"

namespace {
struct Collection { std::wstring source; std::wstring display; };
std::vector<KeyKey::WindowsTsf::UserPhrase> phrases;
std::vector<Collection> collections;

void CopyTo(const std::wstring& source, wchar_t* target, int capacity) {
    if (!target || capacity <= 0) return;
    const auto length = std::min(source.size(), static_cast<size_t>(capacity - 1));
    source.copy(target, length);
    target[length] = L'\0';
}
}

extern "C" {
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
__declspec(dllexport) int __cdecl KeyKeyPublishSimplifiedOutput(int enabled) {
    Microsoft::WRL::ComPtr<ITfThreadMgrEx> manager;
    if (FAILED(CoCreateInstance(CLSID_TF_ThreadMgr, nullptr, CLSCTX_INPROC_SERVER,
            IID_PPV_ARGS(&manager)))) return 0;
    TfClientId client = TF_CLIENTID_NULL;
    if (FAILED(manager->ActivateEx(&client, TF_TMAE_NOACTIVATETIP | TF_TMAE_NOACTIVATEKEYBOARDLAYOUT))) return 0;
    KeyKey::WindowsTsf::SharedOutputState state;
    const auto connected = state.connect(manager.Get());
    const auto written = SUCCEEDED(connected) ? state.write(client, enabled != 0) : connected;
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
__declspec(dllexport) int __cdecl KeyKeyLoadPhrases() {
    phrases = KeyKey::WindowsTsf::LoadUserPhrases();
    return static_cast<int>(phrases.size());
}

__declspec(dllexport) int __cdecl KeyKeyPhraseAt(int index, std::int64_t* rowid,
                                                wchar_t* text, int textCapacity,
                                                wchar_t* reading, int readingCapacity) {
    if (index < 0 || static_cast<size_t>(index) >= phrases.size() || !rowid) return 0;
    const auto& phrase = phrases[index];
    *rowid = phrase.rowid;
    CopyTo(phrase.text, text, textCapacity);
    CopyTo(phrase.reading, reading, readingCapacity);
    return 1;
}

__declspec(dllexport) int __cdecl KeyKeySavePhrase(std::int64_t rowid,
                                                   const wchar_t* text,
                                                   const wchar_t* reading) {
    if (!text || !reading) return 0;
    return KeyKey::WindowsTsf::SaveUserPhrase({rowid, text, reading}) ? 1 : 0;
}

__declspec(dllexport) int __cdecl KeyKeyDeletePhrase(std::int64_t rowid) {
    return KeyKey::WindowsTsf::DeleteUserPhrase(rowid) ? 1 : 0;
}

__declspec(dllexport) int __cdecl KeyKeyResetLearning() {
    return KeyKey::WindowsTsf::ResetUserLearning() ? 1 : 0;
}

__declspec(dllexport) int __cdecl KeyKeyImportUserData(const wchar_t* path) {
    return path && KeyKey::WindowsTsf::ImportUserData(path) ? 1 : 0;
}

__declspec(dllexport) int __cdecl KeyKeyExportUserData(const wchar_t* path) {
    return path && KeyKey::WindowsTsf::ExportUserData(path) ? 1 : 0;
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
