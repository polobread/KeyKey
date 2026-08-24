#include <sqlite3.h>

#include <algorithm>
#include <chrono>
#include <cctype>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <map>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

#include "Mandarin.h"

namespace fs = std::filesystem;
using Formosa::Mandarin::BopomofoKeyboardLayout;

namespace {

class DatabaseError final : public std::runtime_error {
public:
    using std::runtime_error::runtime_error;
};

class Database final {
public:
    explicit Database(const fs::path& path) {
        const std::string utf8Path = path.u8string();
        if (sqlite3_open_v2(utf8Path.c_str(), &database_,
                            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nullptr) != SQLITE_OK) {
            const std::string message = database_ ? sqlite3_errmsg(database_)
                                                   : "cannot allocate SQLite connection";
            if (database_) sqlite3_close(database_);
            database_ = nullptr;
            throw DatabaseError("Cannot create " + utf8Path + ": " + message);
        }
    }

    ~Database() {
        if (database_) sqlite3_close(database_);
    }

    Database(const Database&) = delete;
    Database& operator=(const Database&) = delete;

    sqlite3* get() const { return database_; }

    void execute(const std::string& sql) const {
        char* error = nullptr;
        if (sqlite3_exec(database_, sql.c_str(), nullptr, nullptr, &error) != SQLITE_OK) {
            const std::string message = error ? error : sqlite3_errmsg(database_);
            sqlite3_free(error);
            throw DatabaseError(message);
        }
    }

private:
    sqlite3* database_ = nullptr;
};

class Statement final {
public:
    Statement(sqlite3* database, const std::string& sql) : database_(database) {
        if (sqlite3_prepare_v2(database, sql.c_str(), -1, &statement_, nullptr) != SQLITE_OK) {
            throw DatabaseError(sqlite3_errmsg(database));
        }
    }

    ~Statement() { sqlite3_finalize(statement_); }

    Statement(const Statement&) = delete;
    Statement& operator=(const Statement&) = delete;

    void bindText(int index, const std::string& value) {
        if (sqlite3_bind_text(statement_, index, value.data(),
                              static_cast<int>(value.size()), SQLITE_TRANSIENT) != SQLITE_OK) {
            throw DatabaseError(sqlite3_errmsg(database_));
        }
    }

    void bindInteger(int index, std::int64_t value) {
        if (sqlite3_bind_int64(statement_, index, value) != SQLITE_OK) {
            throw DatabaseError(sqlite3_errmsg(database_));
        }
    }

    void run() {
        if (sqlite3_step(statement_) != SQLITE_DONE) {
            throw DatabaseError(sqlite3_errmsg(database_));
        }
        sqlite3_reset(statement_);
        sqlite3_clear_bindings(statement_);
    }

private:
    sqlite3* database_ = nullptr;
    sqlite3_stmt* statement_ = nullptr;
};

std::string ReadFile(const fs::path& path) {
    std::ifstream input(path, std::ios::binary);
    if (!input) throw std::runtime_error("Cannot open " + path.u8string());
    std::ostringstream stream;
    stream << input.rdbuf();
    return stream.str();
}

std::string TrimLine(std::string line) {
    if (!line.empty() && line.back() == '\r') line.pop_back();
    if (line.size() >= 3 && static_cast<unsigned char>(line[0]) == 0xef &&
        static_cast<unsigned char>(line[1]) == 0xbb &&
        static_cast<unsigned char>(line[2]) == 0xbf) {
        line.erase(0, 3);
    }
    return line;
}

bool StartsWithAsciiCaseInsensitive(const std::string& text, const char* prefix) {
    for (size_t index = 0; prefix[index]; ++index) {
        if (index >= text.size()) return false;
        if (std::tolower(static_cast<unsigned char>(text[index])) !=
            std::tolower(static_cast<unsigned char>(prefix[index]))) {
            return false;
        }
    }
    return true;
}

std::pair<std::string, std::string> SplitKeyValue(const std::string& line) {
    size_t keyStart = line.find_first_not_of(" \t");
    if (keyStart == std::string::npos) return {};
    size_t keyEnd = line.find_first_of(" \t", keyStart);
    if (keyEnd == std::string::npos) return {line.substr(keyStart), std::string()};
    size_t valueStart = line.find_first_not_of(" \t", keyEnd);
    return {line.substr(keyStart, keyEnd - keyStart),
            valueStart == std::string::npos ? std::string() : line.substr(valueStart)};
}

std::vector<std::string> Split(const std::string& line, char delimiter) {
    std::vector<std::string> result;
    size_t start = 0;
    while (start <= line.size()) {
        const size_t end = line.find(delimiter, start);
        result.push_back(line.substr(start, end == std::string::npos
                                               ? std::string::npos
                                               : end - start));
        if (end == std::string::npos) break;
        start = end + 1;
    }
    return result;
}

std::vector<std::string> SplitWhitespace(const std::string& line) {
    std::istringstream stream(line);
    std::vector<std::string> result;
    std::string value;
    while (stream >> value) result.push_back(value);
    return result;
}

std::string TrimAscii(const std::string& value) {
    const size_t first = value.find_first_not_of(" \t\r\n");
    if (first == std::string::npos) return {};
    const size_t last = value.find_last_not_of(" \t\r\n");
    return value.substr(first, last - first + 1);
}

size_t DecodeUtf8(const std::string& text, size_t offset, std::uint32_t& codePoint) {
    if (offset >= text.size()) return 0;
    const auto first = static_cast<unsigned char>(text[offset]);
    size_t length = 1;
    if ((first & 0xe0) == 0xc0) length = 2;
    else if ((first & 0xf0) == 0xe0) length = 3;
    else if ((first & 0xf8) == 0xf0) length = 4;
    if (offset + length > text.size()) return 0;

    if (length == 1) {
        codePoint = first;
        return 1;
    }
    codePoint = first & ((1u << (7 - length)) - 1u);
    for (size_t index = 1; index < length; ++index) {
        const auto continuation = static_cast<unsigned char>(text[offset + index]);
        if ((continuation & 0xc0) != 0x80) return 0;
        codePoint = (codePoint << 6) | (continuation & 0x3f);
    }
    return length;
}

bool IsHan(std::uint32_t codePoint) {
    return codePoint == 0x3007 ||
           (codePoint >= 0x3400 && codePoint <= 0x4dbf) ||
           (codePoint >= 0x4e00 && codePoint <= 0x9fff) ||
           (codePoint >= 0xf900 && codePoint <= 0xfaff) ||
           (codePoint >= 0x20000 && codePoint <= 0x323af);
}

size_t Utf8CodePointCount(const std::string& text) {
    size_t count = 0;
    for (size_t offset = 0; offset < text.size();) {
        std::uint32_t codePoint = 0;
        const size_t length = DecodeUtf8(text, offset, codePoint);
        if (!length) return 0;
        offset += length;
        ++count;
    }
    return count;
}

bool LeadsWithHan(const std::string& text, size_t& firstLength) {
    std::uint32_t codePoint = 0;
    firstLength = DecodeUtf8(text, 0, codePoint);
    return firstLength != 0 && IsHan(codePoint);
}

void InsertPair(Statement& statement, const std::string& key,
                const std::string& value) {
    statement.bindText(1, key);
    statement.bindText(2, value);
    statement.run();
}

std::size_t ImportCin(Database& database, const fs::path& path,
                      const std::string& table, bool characterDefinitionsOnly,
                      bool convertBopomofo) {
    std::ifstream input(path, std::ios::binary);
    if (!input) throw std::runtime_error("Cannot open " + path.u8string());

    Statement insert(database.get(), "INSERT INTO \"" + table + "\" VALUES(?, ?)");
    database.execute("BEGIN");
    bool inCharacterDefinitions = false;
    bool inKeyNames = false;
    std::size_t inserted = 0;
    std::string line;
    try {
        while (std::getline(input, line)) {
            line = TrimLine(std::move(line));
            if (StartsWithAsciiCaseInsensitive(line, "%chardef")) {
                inCharacterDefinitions = line.find("begin") != std::string::npos;
                continue;
            }
            if (StartsWithAsciiCaseInsensitive(line, "%keyname")) {
                inKeyNames = line.find("begin") != std::string::npos;
                continue;
            }

            if (inCharacterDefinitions) {
                auto [key, value] = SplitKeyValue(line);
                if (key.empty() || value.empty()) continue;
                if (convertBopomofo) {
                    key = BopomofoKeyboardLayout::StandardLayout()
                              ->syllableFromKeySequence(key)
                              .absoluteOrderString();
                }
                InsertPair(insert, key, value);
                ++inserted;
            } else if (!characterDefinitionsOnly && inKeyNames) {
                auto [key, value] = SplitKeyValue(line);
                if (!key.empty()) {
                    InsertPair(insert, "__property_keyname-" + key, value);
                    ++inserted;
                }
            } else if (!characterDefinitionsOnly && !line.empty() && line[0] == '%') {
                auto [key, value] = SplitKeyValue(line.substr(1));
                if (!key.empty()) {
                    InsertPair(insert, "__property_" + key, value);
                    ++inserted;
                }
            }
        }
        database.execute("COMMIT");
    } catch (...) {
        database.execute("ROLLBACK");
        throw;
    }
    std::cout << "Imported " << inserted << " rows from " << path.filename().u8string()
              << " into " << table << "\n";
    return inserted;
}

void InsertFile(Database& database, const std::string& key, const fs::path& path) {
    Statement insert(database.get(),
                     "INSERT INTO prepopulated_service_data (key, value) VALUES(?, ?)");
    InsertPair(insert, key, ReadFile(path));
    const auto now = std::chrono::system_clock::to_time_t(std::chrono::system_clock::now());
    InsertPair(insert, key + "_timestamp", std::to_string(now));
}

std::set<std::string> LoadExclusions(const fs::path& collectionDirectory) {
    std::set<std::string> result;
    if (!fs::exists(collectionDirectory)) return result;
    for (const auto& entry : fs::directory_iterator(collectionDirectory)) {
        if (!entry.is_regular_file()) continue;
        const std::string filename = entry.path().filename().u8string();
        if (filename.rfind("phrase.people-", 0) != 0 ||
            entry.path().extension() != ".tsv") {
            continue;
        }
        std::ifstream input(entry.path(), std::ios::binary);
        std::string line;
        bool header = true;
        while (std::getline(input, line)) {
            line = TrimLine(std::move(line));
            if (header) {
                header = false;
                continue;
            }
            const auto fields = Split(line, '\t');
            if (!fields.empty()) {
                const std::string word = TrimAscii(fields[0]);
                if (!word.empty()) result.insert(word);
            }
        }
    }
    return result;
}

struct PhraseRow {
    std::string word;
    std::uint64_t count = 0;
    size_t firstCodePointLength = 0;
};

std::uint64_t ParseCount(const std::string& text) {
    const std::string value = TrimAscii(text);
    if (value.empty() ||
        !std::all_of(value.begin(), value.end(), [](unsigned char c) { return std::isdigit(c); })) {
        return 0;
    }
    try {
        return std::stoull(value);
    } catch (...) {
        return 0;
    }
}

std::string CollectionName(const fs::path& path, bool isMcBopomofo) {
    if (isMcBopomofo) return "McBopomofo";
    std::string name = path.stem().u8string();
    constexpr char prefix[] = "phrase.";
    if (name.rfind(prefix, 0) == 0) name.erase(0, sizeof(prefix) - 1);
    return name;
}

std::map<std::string, std::string> LoadCollectionDisplayNames(const fs::path& path) {
    std::ifstream input(path, std::ios::binary);
    if (!input) throw std::runtime_error("Cannot open " + path.u8string());

    std::map<std::string, std::string> names;
    std::string line;
    bool header = true;
    while (std::getline(input, line)) {
        line = TrimLine(std::move(line));
        if (header) {
            header = false;
            continue;
        }
        const auto fields = Split(line, '\t');
        if (fields.size() < 2) continue;
        const std::string source = TrimAscii(fields[0]);
        const std::string display = TrimAscii(fields[1]);
        if (!source.empty() && !display.empty()) names[source] = display;
    }
    if (names.empty()) {
        throw std::runtime_error("No collection display names in " + path.u8string());
    }
    return names;
}

std::string CollectionDisplayName(
    const fs::path& path, bool isMcBopomofo,
    const std::map<std::string, std::string>& displayNames) {
    const std::string collection = CollectionName(path, isMcBopomofo);
    const auto override = displayNames.find(collection);
    if (override != displayNames.end()) return override->second;
    if (isMcBopomofo) return collection;
    std::ifstream input(path, std::ios::binary);
    std::string line;
    bool header = true;
    while (std::getline(input, line)) {
        line = TrimLine(std::move(line));
        if (header) {
            header = false;
            continue;
        }
        const auto fields = Split(line, '\t');
        if (fields.size() >= 4) {
            const std::string display = TrimAscii(fields[3]);
            if (!display.empty()) return display;
        }
    }
    return collection;
}

std::size_t ImportCollection(Database& database, const fs::path& path,
                             bool isMcBopomofo,
                             const std::set<std::string>& exclusions,
                             const std::map<std::string, std::string>& displayNames) {
    std::ifstream input(path, std::ios::binary);
    if (!input) throw std::runtime_error("Cannot open " + path.u8string());

    std::vector<PhraseRow> rows;
    std::unordered_map<std::string, size_t> seen;
    std::string line;
    while (std::getline(input, line)) {
        line = TrimLine(std::move(line));
        const auto fields = line.find('\t') != std::string::npos
                                ? Split(line, '\t')
                                : SplitWhitespace(line);
        if (fields.size() < 2) continue;
        const std::string word = TrimAscii(fields[0]);
        const std::uint64_t count = ParseCount(fields[1]);
        if (!count || exclusions.find(word) != exclusions.end()) continue;
        size_t firstLength = 0;
        if (!LeadsWithHan(word, firstLength)) continue;
        const size_t length = Utf8CodePointCount(word);
        if (length < 2 || length > 20) continue;

        auto found = seen.find(word);
        if (found != seen.end()) {
            rows[found->second].count = std::max(rows[found->second].count, count);
        } else {
            seen.emplace(word, rows.size());
            rows.push_back(PhraseRow{word, count, firstLength});
        }
    }

    std::uint64_t total = 0;
    for (const auto& row : rows) total += row.count;
    if (!total) throw std::runtime_error("No usable phrases in " + path.u8string());

    std::map<std::string, std::vector<PhraseRow>> grouped;
    for (const auto& row : rows) {
        // Equivalent to AssociatedPhraseCooker's log10 probability > -6.0.
        if (static_cast<long double>(row.count) * 1000000.0L <= total) continue;
        if (row.word.find("媽的") != std::string::npos) continue;
        grouped[row.word.substr(0, row.firstCodePointLength)].push_back(row);
    }

    const std::string collection = CollectionName(path, isMcBopomofo);
    Statement insertPhrase(database.get(),
                           "INSERT INTO associated_phrases (headchar, data, source) "
                           "VALUES(?, ?, ?)");
    Statement insertName(database.get(),
                         "INSERT INTO collection_names (source, display, sortorder) "
                         "VALUES(?, ?, ?)");
    database.execute("BEGIN");
    std::size_t phraseCount = 0;
    try {
        for (auto& [head, phrases] : grouped) {
            std::stable_sort(phrases.begin(), phrases.end(),
                             [](const PhraseRow& left, const PhraseRow& right) {
                                 return left.count > right.count;
                             });
            std::string data;
            for (const auto& phrase : phrases) {
                if (!data.empty()) data += ',';
                data += phrase.word.substr(phrase.firstCodePointLength);
            }
            insertPhrase.bindText(1, head);
            insertPhrase.bindText(2, data);
            insertPhrase.bindText(3, collection);
            insertPhrase.run();
            phraseCount += phrases.size();
        }

        insertName.bindText(1, collection);
        insertName.bindText(2, CollectionDisplayName(path, isMcBopomofo, displayNames));
        insertName.bindInteger(3, isMcBopomofo ? 0 : 1);
        insertName.run();
        database.execute("COMMIT");
    } catch (...) {
        database.execute("ROLLBACK");
        throw;
    }
    std::cout << "Imported " << phraseCount << " associated phrases from "
              << path.filename().u8string() << " as " << collection << "\n";
    return phraseCount;
}

std::int64_t ScalarInteger(sqlite3* database, const char* sql) {
    sqlite3_stmt* statement = nullptr;
    if (sqlite3_prepare_v2(database, sql, -1, &statement, nullptr) != SQLITE_OK) {
        throw DatabaseError(sqlite3_errmsg(database));
    }
    const int step = sqlite3_step(statement);
    if (step != SQLITE_ROW) {
        const std::string message = sqlite3_errmsg(database);
        sqlite3_finalize(statement);
        throw DatabaseError(message);
    }
    const std::int64_t value = sqlite3_column_int64(statement, 0);
    sqlite3_finalize(statement);
    return value;
}

void VerifyCollectionDisplayNames(
    sqlite3* database, const std::map<std::string, std::string>& displayNames) {
    sqlite3_stmt* statement = nullptr;
    const char* sql = "SELECT display FROM collection_names WHERE source = ?";
    if (sqlite3_prepare_v2(database, sql, -1, &statement, nullptr) != SQLITE_OK) {
        throw DatabaseError(sqlite3_errmsg(database));
    }
    try {
        for (const auto& [source, expected] : displayNames) {
            sqlite3_bind_text(statement, 1, source.data(), static_cast<int>(source.size()),
                              SQLITE_TRANSIENT);
            const int step = sqlite3_step(statement);
            if (step == SQLITE_ROW) {
                const unsigned char* value = sqlite3_column_text(statement, 0);
                if (!value || reinterpret_cast<const char*>(value) != expected) {
                    throw DatabaseError("Incorrect collection display name for " + source);
                }
            } else if (step != SQLITE_DONE) {
                throw DatabaseError(sqlite3_errmsg(database));
            }
            sqlite3_reset(statement);
            sqlite3_clear_bindings(statement);
        }
    } catch (...) {
        sqlite3_finalize(statement);
        throw;
    }
    sqlite3_finalize(statement);
}

void Verify(Database& database,
            const std::map<std::string, std::string>& displayNames) {
    sqlite3_stmt* statement = nullptr;
    if (sqlite3_prepare_v2(database.get(), "PRAGMA integrity_check", -1,
                           &statement, nullptr) != SQLITE_OK ||
        sqlite3_step(statement) != SQLITE_ROW ||
        std::string(reinterpret_cast<const char*>(sqlite3_column_text(statement, 0))) != "ok") {
        if (statement) sqlite3_finalize(statement);
        throw DatabaseError("SQLite integrity_check failed");
    }
    sqlite3_finalize(statement);

    const auto mandarin = ScalarInteger(database.get(),
                                        "SELECT count(*) FROM 'Mandarin-bpmf-cin'");
    const auto associated = ScalarInteger(database.get(),
                                          "SELECT count(*) FROM associated_phrases");
    const auto collections = ScalarInteger(database.get(),
                                           "SELECT count(*) FROM collection_names");
    if (mandarin < 90000 || associated == 0 || collections == 0) {
        throw DatabaseError("Generated database is missing required data");
    }
    VerifyCollectionDisplayNames(database.get(), displayNames);
    std::cout << "Verified database: " << mandarin << " Mandarin rows, "
              << associated << " associated-phrase heads, " << collections
              << " collections\n";
}

std::vector<fs::path> CollectionPaths(const fs::path& dataRoot,
                                      const fs::path& categorizedCollectionRoot) {
    std::vector<fs::path> paths;
    paths.push_back(dataRoot / "McBopomofo" / "phrase.occ");
    if (fs::is_directory(categorizedCollectionRoot)) {
        for (const auto& entry : fs::directory_iterator(categorizedCollectionRoot)) {
            if (!entry.is_regular_file()) continue;
            const std::string filename = entry.path().filename().u8string();
            if (filename.rfind("phrase.", 0) == 0 && entry.path().extension() == ".tsv") {
                paths.push_back(entry.path());
            }
        }
    }
    std::sort(paths.begin() + 1, paths.end());
    return paths;
}

void Cook(const fs::path& sourceRoot, const fs::path& dataRoot,
          const fs::path& categorizedCollectionRoot,
          const fs::path& outputPath) {
    fs::create_directories(outputPath.parent_path());
    std::error_code removeError;
    fs::remove(outputPath, removeError);
    if (removeError) {
        throw std::runtime_error("Cannot replace " + outputPath.u8string() + ": " +
                                 removeError.message());
    }

    Database database(outputPath);
    database.execute(ReadFile(sourceRoot / "Distributions" / "Takao" /
                              "DatabaseCooker" / "Schema.sql"));

    const fs::path tables = sourceRoot / "DataTables";
    ImportCin(database, tables / "bpmf-ext.cin", "Mandarin-bpmf-cin", false, true);
    ImportCin(database, tables / "bpmf-punctuations.cin", "Mandarin-bpmf-cin",
              true, false);
    ImportCin(database, tables / "cj-ext.cin", "Generic-cj-cin", false, false);
    ImportCin(database, tables / "simplex-ext.cin", "Generic-simplex-cin", false,
              false);
    ImportCin(database, tables / "cj-punctuations-halfwidth.cin",
              "Punctuations-cj-halfwidth-cin", false, false);
    ImportCin(database, tables / "cj-punctuations-mixedwidth.cin",
              "Punctuations-cj-mixedwidth-cin", false, false);
    ImportCin(database, tables / "bopomofo-correction.cin",
              "BopomofoCorrection-bopomofo-correction-cin", false, false);

    const fs::path online = sourceRoot / "Distributions" / "Takao" / "OnlineData";
    InsertFile(database, "onekey_services", online / "OneKey.plist");
    InsertFile(database, "canned_messages", online / "CannedMessages.plist");

    const auto displayNames = LoadCollectionDisplayNames(
        dataRoot / "AssociatedPhraseCollectionNames.tsv");
    const std::set<std::string> exclusions = LoadExclusions(categorizedCollectionRoot);
    for (const fs::path& collection : CollectionPaths(dataRoot, categorizedCollectionRoot)) {
        const bool isMcBopomofo = collection.parent_path().filename() == "McBopomofo";
        ImportCollection(database, collection, isMcBopomofo,
                         isMcBopomofo ? exclusions : std::set<std::string>(),
                         displayNames);
    }

    database.execute("ANALYZE");
    Verify(database, displayNames);
}

}  // namespace

int main(int argc, char* argv[]) {
    if (argc != 5) {
        std::cerr << "Usage: KeyKeyDatabaseCooker <Source directory> "
                     "<DataSource directory> <categorized collection directory> "
                     "<output KeyKey.db>\n";
        return 2;
    }
    try {
        Cook(fs::u8path(argv[1]), fs::u8path(argv[2]), fs::u8path(argv[3]),
             fs::u8path(argv[4]));
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "KeyKeyDatabaseCooker: " << error.what() << '\n';
        return 1;
    }
}
