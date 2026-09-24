#include "keykey/linux_ime/smart_mandarin_user_data.h"

#include <sqlite3.h>

#include <array>
#include <cstdlib>
#include <filesystem>
#include <sstream>
#include <sys/stat.h>
#include <utility>

namespace keykey::linux_ime {
namespace {

struct Statement {
    sqlite3_stmt *value = nullptr;
    ~Statement() { sqlite3_finalize(value); }
};

const std::array<const char *, 21> initials = {
    "ㄅ", "ㄆ", "ㄇ", "ㄈ", "ㄉ", "ㄊ", "ㄋ", "ㄌ", "ㄍ", "ㄎ", "ㄏ",
    "ㄐ", "ㄑ", "ㄒ", "ㄓ", "ㄔ", "ㄕ", "ㄖ", "ㄗ", "ㄘ", "ㄙ"};
const std::array<const char *, 3> medials = {"ㄧ", "ㄨ", "ㄩ"};
const std::array<const char *, 13> finals = {
    "ㄚ", "ㄛ", "ㄜ", "ㄝ", "ㄞ", "ㄟ", "ㄠ", "ㄡ", "ㄢ", "ㄣ", "ㄤ", "ㄥ", "ㄦ"};
const std::array<const char *, 4> tones = {"ˊ", "ˇ", "ˋ", "˙"};

std::string columnText(sqlite3_stmt *statement, int column) {
    const auto *value = sqlite3_column_text(statement, column);
    return value ? reinterpret_cast<const char *>(value) : "";
}

bool execute(sqlite3 *database, const char *sql) {
    return sqlite3_exec(database, sql, nullptr, nullptr, nullptr) == SQLITE_OK;
}

bool prepare(sqlite3 *database, Statement &statement, const char *sql) {
    return sqlite3_prepare_v2(database, sql, -1, &statement.value, nullptr) ==
           SQLITE_OK;
}

void bind(sqlite3_stmt *statement, int column, const std::string &text) {
    sqlite3_bind_text(statement, column, text.c_str(), -1, SQLITE_TRANSIENT);
}

std::size_t codepointCount(const std::string &text) {
    std::size_t count = 0;
    for (const unsigned char byte : text) {
        if ((byte & 0xC0U) != 0x80U) {
            ++count;
        }
    }
    return count;
}

} // namespace

std::string SmartMandarinUserData::defaultPath() {
    const char *overridePath = std::getenv("CHICHI77_KEYKEY_USER_DB");
    if (overridePath && *overridePath) {
        return overridePath;
    }
    const char *xdg = std::getenv("XDG_DATA_HOME");
    if (xdg && *xdg) {
        return std::string(xdg) + "/chichi77-keykey/smart-mandarin-user.db";
    }
    const char *home = std::getenv("HOME");
    return home && *home
               ? std::string(home) + "/.local/share/chichi77-keykey/smart-mandarin-user.db"
               : std::string{};
}

std::shared_ptr<SmartMandarinUserData>
SmartMandarinUserData::open(const std::string &path) {
    if (path.empty()) {
        return nullptr;
    }
    const std::filesystem::path directory =
        std::filesystem::path(path).parent_path();
    if (!directory.empty()) {
        std::error_code error;
        std::filesystem::create_directories(directory, error);
        if (error) {
            return nullptr;
        }
        chmod(directory.c_str(), 0700);
    }
    sqlite3 *database = nullptr;
    if (sqlite3_open_v2(path.c_str(), &database,
                        SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nullptr) !=
        SQLITE_OK) {
        sqlite3_close(database);
        return nullptr;
    }
    chmod(path.c_str(), 0600);
    sqlite3_busy_timeout(database, 1000);
    if (!execute(database,
                 "CREATE TABLE IF NOT EXISTS user_unigrams ("
                 "qstring TEXT NOT NULL, current TEXT NOT NULL, "
                 "probability REAL NOT NULL, backoff REAL NOT NULL);"
                 "CREATE INDEX IF NOT EXISTS user_unigrams_index "
                 "ON user_unigrams(qstring);"
                 "CREATE TABLE IF NOT EXISTS user_bigram_cache ("
                 "qstring TEXT NOT NULL, previous TEXT NOT NULL, "
                 "current TEXT NOT NULL, probability REAL NOT NULL);"
                 "CREATE INDEX IF NOT EXISTS user_bigram_cache_index "
                 "ON user_bigram_cache(qstring);"
                 "CREATE TABLE IF NOT EXISTS user_candidate_override_cache ("
                 "qstring TEXT NOT NULL, current TEXT NOT NULL);"
                 "CREATE INDEX IF NOT EXISTS user_candidate_override_cache_index "
                 "ON user_candidate_override_cache(qstring);")) {
        sqlite3_close(database);
        return nullptr;
    }
    return std::shared_ptr<SmartMandarinUserData>(
        new SmartMandarinUserData(database));
}

SmartMandarinUserData::~SmartMandarinUserData() { sqlite3_close(database_); }

std::vector<UserUnigram>
SmartMandarinUserData::unigrams(const std::string &query) const {
    Statement statement;
    if (!prepare(database_, statement,
                 "SELECT current, probability, backoff FROM user_unigrams "
                 "WHERE qstring = ? ORDER BY probability DESC, rowid")) {
        return {};
    }
    bind(statement.value, 1, query);
    std::vector<UserUnigram> result;
    while (sqlite3_step(statement.value) == SQLITE_ROW) {
        result.push_back({columnText(statement.value, 0),
                          sqlite3_column_double(statement.value, 1),
                          sqlite3_column_double(statement.value, 2)});
    }
    return result;
}

std::string SmartMandarinUserData::learnedCandidate(
    const std::string &query) const {
    Statement statement;
    if (!prepare(database_, statement,
                 "SELECT current FROM user_candidate_override_cache "
                 "WHERE qstring = ? ORDER BY rowid DESC LIMIT 1")) {
        return {};
    }
    bind(statement.value, 1, query);
    return sqlite3_step(statement.value) == SQLITE_ROW
               ? columnText(statement.value, 0) : std::string{};
}

bool SmartMandarinUserData::learnedBigram(
    const std::string &previousQuery, const std::string &query,
    const std::string &previous, const std::string &current,
    double &score) const {
    Statement statement;
    if (!prepare(database_, statement,
                 "SELECT probability FROM user_bigram_cache WHERE "
                 "qstring = ? AND previous = ? AND current = ? "
                 "ORDER BY rowid DESC LIMIT 1")) {
        return false;
    }
    bind(statement.value, 1, previousQuery + " " + query);
    bind(statement.value, 2, previous);
    bind(statement.value, 3, current);
    if (sqlite3_step(statement.value) != SQLITE_ROW) {
        return false;
    }
    score = sqlite3_column_double(statement.value, 0);
    return true;
}

bool SmartMandarinUserData::learn(
    const std::string &query, const std::string &current,
    const std::string &previousQuery, const std::string &previous) const {
    if (query.empty() || current.empty() || !execute(database_, "BEGIN IMMEDIATE")) {
        return false;
    }
    bool ok = false;
    {
        Statement remove, insert, removeBigram, insertBigram;
        ok = prepare(database_, remove,
                     "DELETE FROM user_candidate_override_cache WHERE qstring = ?") &&
             prepare(database_, insert,
                     "INSERT INTO user_candidate_override_cache VALUES (?, ?)");
        if (ok) {
            bind(remove.value, 1, query);
            ok = sqlite3_step(remove.value) == SQLITE_DONE;
        }
        if (ok) {
            bind(insert.value, 1, query);
            bind(insert.value, 2, current);
            ok = sqlite3_step(insert.value) == SQLITE_DONE;
        }
        if (ok && !previousQuery.empty()) {
            ok = prepare(database_, removeBigram,
                         "DELETE FROM user_bigram_cache WHERE qstring = ?") &&
                 prepare(database_, insertBigram,
                         "INSERT INTO user_bigram_cache VALUES (?, ?, ?, 0)");
            const std::string pair = previousQuery + " " + query;
            if (ok) {
                bind(removeBigram.value, 1, pair);
                ok = sqlite3_step(removeBigram.value) == SQLITE_DONE;
            }
            if (ok) {
                bind(insertBigram.value, 1, pair);
                bind(insertBigram.value, 2, previous);
                bind(insertBigram.value, 3, current);
                ok = sqlite3_step(insertBigram.value) == SQLITE_DONE;
            }
        }
    }
    if (ok && execute(database_, "COMMIT")) {
        return true;
    }
    execute(database_, "ROLLBACK");
    return false;
}

std::string SmartMandarinUserData::readingToQuery(
    const std::string &reading) {
    std::istringstream stream(reading);
    std::string syllable;
    std::string result;
    while (stream >> syllable) {
        unsigned int initial = 0, medial = 0, final = 0, tone = 0;
        for (std::size_t offset = 0; offset < syllable.size();) {
            bool found = false;
            const auto match = [&](const auto &symbols, unsigned int &slot) {
                for (std::size_t index = 0; index < symbols.size(); ++index) {
                    const std::string symbol = symbols[index];
                    if (syllable.compare(offset, symbol.size(), symbol) == 0) {
                        if (slot != 0) return false;
                        slot = static_cast<unsigned int>(index + 1);
                        offset += symbol.size();
                        return true;
                    }
                }
                return false;
            };
            found = match(initials, initial) || match(medials, medial) ||
                    match(finals, final) || match(tones, tone);
            if (!found) return {};
        }
        if (initial == 0 && medial == 0 && final == 0) return {};
        const unsigned int order = initial + medial * 22U + final * 88U +
                                   tone * 1232U;
        result.push_back(static_cast<char>(48U + order % 79U));
        result.push_back(static_cast<char>(48U + order / 79U));
    }
    return result;
}

std::string SmartMandarinUserData::queryToReading(
    const std::string &query) {
    if (query.size() % 2 != 0) return {};
    std::string result;
    for (std::size_t offset = 0; offset < query.size(); offset += 2) {
        const int order = (query[offset] - 48) + (query[offset + 1] - 48) * 79;
        if (order < 0 || order >= 6160) return {};
        const int initial = order % 22;
        const int medial = (order / 22) % 4;
        const int final = (order / 88) % 14;
        const int tone = order / 1232;
        if (tone > 4) return {};
        if (!result.empty()) result += " ";
        if (initial) result += initials[static_cast<std::size_t>(initial - 1)];
        if (medial) result += medials[static_cast<std::size_t>(medial - 1)];
        if (final) result += finals[static_cast<std::size_t>(final - 1)];
        if (tone) result += tones[static_cast<std::size_t>(tone - 1)];
    }
    return result;
}

bool SmartMandarinUserData::addPhrase(const std::string &text,
                                      const std::string &reading) const {
    const std::string query = readingToQuery(reading);
    if (text.empty() || query.empty() || codepointCount(text) != query.size() / 2 ||
        query.size() > 16) return false;
    Statement exists, insert;
    if (!prepare(database_, exists,
                 "SELECT 1 FROM user_unigrams WHERE qstring = ? AND current = ?") ||
        !prepare(database_, insert,
                 "INSERT INTO user_unigrams VALUES (?, ?, -0.0000001, 0)")) return false;
    bind(exists.value, 1, query);
    bind(exists.value, 2, text);
    if (sqlite3_step(exists.value) == SQLITE_ROW) return false;
    bind(insert.value, 1, query);
    bind(insert.value, 2, text);
    return sqlite3_step(insert.value) == SQLITE_DONE;
}

bool SmartMandarinUserData::removePhrase(const std::string &text,
                                         const std::string &reading) const {
    const std::string query = readingToQuery(reading);
    if (text.empty() || query.empty()) return false;
    Statement statement;
    if (!prepare(database_, statement,
                 "DELETE FROM user_unigrams WHERE qstring = ? AND current = ?"))
        return false;
    bind(statement.value, 1, query);
    bind(statement.value, 2, text);
    return sqlite3_step(statement.value) == SQLITE_DONE &&
           sqlite3_changes(database_) > 0;
}

std::vector<std::pair<std::string, std::string>>
SmartMandarinUserData::phrases() const {
    Statement statement;
    if (!prepare(database_, statement,
                 "SELECT current, qstring FROM user_unigrams ORDER BY rowid"))
        return {};
    std::vector<std::pair<std::string, std::string>> result;
    while (sqlite3_step(statement.value) == SQLITE_ROW) {
        result.emplace_back(columnText(statement.value, 0),
                            queryToReading(columnText(statement.value, 1)));
    }
    return result;
}

bool SmartMandarinUserData::resetLearning() const {
    if (!execute(database_, "BEGIN IMMEDIATE")) return false;
    const bool cleared = execute(database_, "DELETE FROM user_bigram_cache") &&
                         execute(database_, "DELETE FROM user_candidate_override_cache");
    if (cleared && execute(database_, "COMMIT")) return true;
    execute(database_, "ROLLBACK");
    return false;
}

} // namespace keykey::linux_ime
