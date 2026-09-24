#include "UserDataStore.h"

#include <Windows.h>

#include <memory>
#include <string>
#include <utility>
#include <cwchar>

#include "FrontendSettings.h"
#include "Mandarin.h"
#include "OVUTF8Helper.h"
#include "sqlite3.h"

namespace KeyKey::WindowsTsf {
namespace {

using Formosa::Mandarin::BPMF;

std::string ToUtf8(const std::wstring& wide) {
    return OpenVanilla::OVUTF8::FromUTF16(wide);
}

std::wstring ToWide(const std::string& utf8) {
    return OpenVanilla::OVUTF16::FromUTF8(utf8);
}

struct Connection {
    sqlite3* db = nullptr;

    Connection() {
        const std::wstring directory = SettingsDirectory();
        if (directory.empty()) return;
        const std::wstring path = directory + L"\\SmartMandarinUserData.db";
        if (sqlite3_open16(path.c_str(), &db) != SQLITE_OK) {
            if (db) sqlite3_close(db);
            db = nullptr;
            return;
        }
        sqlite3_busy_timeout(db, 3000);
        const char* schema =
            "CREATE TABLE IF NOT EXISTS user_unigrams "
            "(qstring, current, probability, backoff);"
            "CREATE INDEX IF NOT EXISTS user_unigrams_index "
            "ON user_unigrams(qstring);"
            "CREATE TABLE IF NOT EXISTS user_bigram_cache "
            "(qstring, previous, current, probability);"
            "CREATE INDEX IF NOT EXISTS user_bigram_cache_index "
            "ON user_bigram_cache(qstring);"
            "CREATE TABLE IF NOT EXISTS user_candidate_override_cache "
            "(qstring, current);"
            "CREATE INDEX IF NOT EXISTS user_candidate_override_cache_index "
            "ON user_candidate_override_cache(qstring);";
        if (sqlite3_exec(db, schema, nullptr, nullptr, nullptr) != SQLITE_OK) {
            sqlite3_close(db);
            db = nullptr;
        }
    }

    ~Connection() { if (db) sqlite3_close(db); }
    Connection(const Connection&) = delete;
    Connection& operator=(const Connection&) = delete;
};

struct Statement {
    sqlite3_stmt* value = nullptr;
    Statement(sqlite3* db, const char* sql) {
        if (db) sqlite3_prepare_v2(db, sql, -1, &value, nullptr);
    }
    ~Statement() { if (value) sqlite3_finalize(value); }
};

std::string EncodeReading(const std::wstring& reading, size_t& syllables) {
    std::string encoded;
    syllables = 0;
    const std::string utf8 = ToUtf8(reading);
    size_t start = 0;
    while (start <= utf8.size()) {
        const size_t end = utf8.find(',', start);
        std::string part = utf8.substr(start, end - start);
        const size_t first = part.find_first_not_of(" \t\r\n");
        const size_t last = part.find_last_not_of(" \t\r\n");
        if (first == std::string::npos) return {};
        part = part.substr(first, last - first + 1);
        const BPMF syllable = BPMF::FromComposedString(part);
        if (syllable.isEmpty()) return {};
        encoded += syllable.absoluteOrderString();
        ++syllables;
        if (end == std::string::npos) break;
        start = end + 1;
    }
    return encoded;
}

std::wstring DecodeReading(const std::string& qstring) {
    if (qstring.empty() || qstring.size() % 2) return {};
    std::string reading;
    for (size_t offset = 0; offset < qstring.size(); offset += 2) {
        if (!reading.empty()) reading += ',';
        reading += BPMF::FromAbsoluteOrderString(qstring.substr(offset, 2))
                       .composedString();
    }
    return ToWide(reading);
}

}  // namespace

std::vector<UserPhrase> LoadUserPhrases() {
    std::vector<UserPhrase> rows;
    Connection connection;
    Statement query(connection.db,
        "SELECT rowid, qstring, current FROM user_unigrams ORDER BY rowid");
    if (!query.value) return rows;
    while (sqlite3_step(query.value) == SQLITE_ROW) {
        const char* qstring = reinterpret_cast<const char*>(
            sqlite3_column_text(query.value, 1));
        const char* current = reinterpret_cast<const char*>(
            sqlite3_column_text(query.value, 2));
        if (!qstring || !current) continue;
        UserPhrase row;
        row.rowid = sqlite3_column_int64(query.value, 0);
        row.text = ToWide(current);
        row.reading = DecodeReading(qstring);
        if (!row.text.empty() && !row.reading.empty()) rows.push_back(std::move(row));
    }
    return rows;
}

bool SaveUserPhrase(const UserPhrase& phrase) {
    if (phrase.text.empty() || phrase.reading.empty()) return false;
    const std::string text = ToUtf8(phrase.text);
    const size_t characters =
        OpenVanilla::OVUTF8Helper::SplitStringByCodePoint(text).size();
    size_t syllables = 0;
    const std::string qstring = EncodeReading(phrase.reading, syllables);
    if (qstring.empty() || characters != syllables) return false;

    Connection connection;
    if (!connection.db) return false;
    {
        Statement duplicate(connection.db,
            "SELECT rowid FROM user_unigrams WHERE qstring = ? AND current = ? "
            "AND rowid != ? "
            "ORDER BY rowid LIMIT 1");
        if (!duplicate.value) return false;
        sqlite3_bind_text(duplicate.value, 1, qstring.c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(duplicate.value, 2, text.c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_int64(duplicate.value, 3, phrase.rowid);
        const int found = sqlite3_step(duplicate.value);
        if (found == SQLITE_ROW) return false;
        if (found != SQLITE_ROW && found != SQLITE_DONE) return false;
    }

    Statement write(connection.db, phrase.rowid
        ? "UPDATE user_unigrams SET qstring = ?, current = ? WHERE rowid = ?"
        : "INSERT INTO user_unigrams (qstring, current, probability, backoff) "
          "VALUES (?, ?, -0.0000001, 0.0)");
    if (!write.value) return false;
    sqlite3_bind_text(write.value, 1, qstring.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(write.value, 2, text.c_str(), -1, SQLITE_TRANSIENT);
    if (phrase.rowid) sqlite3_bind_int64(write.value, 3, phrase.rowid);
    return sqlite3_step(write.value) == SQLITE_DONE &&
           (!phrase.rowid || sqlite3_changes(connection.db) == 1);
}

bool DeleteUserPhrase(std::int64_t rowid) {
    if (rowid <= 0) return false;
    Connection connection;
    Statement remove(connection.db,
        "DELETE FROM user_unigrams WHERE rowid = ?");
    if (!remove.value) return false;
    sqlite3_bind_int64(remove.value, 1, rowid);
    return sqlite3_step(remove.value) == SQLITE_DONE &&
           sqlite3_changes(connection.db) == 1;
}

bool ResetUserLearning() {
    Connection connection;
    if (!connection.db) return false;
    if (sqlite3_exec(connection.db, "BEGIN IMMEDIATE", nullptr, nullptr, nullptr) != SQLITE_OK)
        return false;
    const bool cleared =
        sqlite3_exec(connection.db, "DELETE FROM user_bigram_cache;"
                    "DELETE FROM user_candidate_override_cache;",
                    nullptr, nullptr, nullptr) == SQLITE_OK;
    if (!cleared || sqlite3_exec(connection.db, "COMMIT", nullptr, nullptr, nullptr) != SQLITE_OK) {
        sqlite3_exec(connection.db, "ROLLBACK", nullptr, nullptr, nullptr);
        return false;
    }
    return true;
}

bool ImportUserData(const std::wstring& databasePath) {
    if (databasePath.empty() ||
        GetFileAttributesW(databasePath.c_str()) == INVALID_FILE_ATTRIBUTES) return false;
    const std::wstring directory = SettingsDirectory();
    if (directory.empty()) return false;
    const std::wstring currentPath = directory + L"\\SmartMandarinUserData.db";
    if (_wcsicmp(databasePath.c_str(), currentPath.c_str()) == 0) return false;
    Connection connection;
    if (!connection.db) return false;
    Statement attach(connection.db, "ATTACH DATABASE ? AS imported");
    if (!attach.value) return false;
    const std::string path = ToUtf8(databasePath);
    sqlite3_bind_text(attach.value, 1, path.c_str(), -1, SQLITE_TRANSIENT);
    if (sqlite3_step(attach.value) != SQLITE_DONE) return false;
    sqlite3_finalize(attach.value);
    attach.value = nullptr;

    const char* copySql =
        "BEGIN;"
        "INSERT INTO main.user_unigrams (qstring, current, probability, backoff) "
        "SELECT src.qstring, src.current, src.probability, src.backoff "
        "FROM imported.user_unigrams AS src "
        "WHERE NOT EXISTS (SELECT 1 FROM main.user_unigrams AS dst "
        "WHERE dst.qstring = src.qstring AND dst.current = src.current) "
        "ORDER BY src.rowid;"
        "DELETE FROM main.user_bigram_cache;"
        "INSERT INTO main.user_bigram_cache "
        "(qstring, previous, current, probability) "
        "SELECT qstring, previous, current, probability "
        "FROM imported.user_bigram_cache ORDER BY rowid;"
        "DELETE FROM main.user_candidate_override_cache;"
        "INSERT INTO main.user_candidate_override_cache (qstring, current) "
        "SELECT qstring, current FROM imported.user_candidate_override_cache "
        "ORDER BY rowid;"
        "COMMIT;";
    const bool copied = sqlite3_exec(connection.db, copySql, nullptr, nullptr, nullptr) == SQLITE_OK;
    if (!copied) sqlite3_exec(connection.db, "ROLLBACK", nullptr, nullptr, nullptr);
    sqlite3_exec(connection.db, "DETACH DATABASE imported", nullptr, nullptr, nullptr);
    return copied;
}

bool ExportUserData(const std::wstring& databasePath) {
    if (databasePath.empty()) return false;
    const std::wstring directory = SettingsDirectory();
    if (directory.empty()) return false;
    const std::wstring sourcePath = directory + L"\\SmartMandarinUserData.db";
    if (_wcsicmp(databasePath.c_str(), sourcePath.c_str()) == 0) return false;
    Connection connection;
    if (!connection.db) return false;
    sqlite3* output = nullptr;
    if (sqlite3_open16(databasePath.c_str(), &output) != SQLITE_OK) {
        if (output) sqlite3_close(output);
        return false;
    }
    sqlite3_busy_timeout(output, 3000);
    sqlite3_backup* backup = sqlite3_backup_init(output, "main", connection.db, "main");
    if (!backup) {
        sqlite3_close(output);
        return false;
    }
    const int result = sqlite3_backup_step(backup, -1);
    const int finish = sqlite3_backup_finish(backup);
    const int close = sqlite3_close(output);
    return result == SQLITE_DONE && finish == SQLITE_OK && close == SQLITE_OK;
}

}  // namespace KeyKey::WindowsTsf
