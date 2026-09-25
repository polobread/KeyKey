#include <Windows.h>
#include <algorithm>
#include <cstdint>
#include <string>
#include <vector>

#include "UserDataStore.h"
#include "sqlite3.h"

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
