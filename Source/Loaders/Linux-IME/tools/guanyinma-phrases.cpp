// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
#include "keykey/linux_ime/guanyinma_session.h"
#include "keykey/linux_ime/phrase_reading.h"
#include <sqlite3.h>
#include <json-c/json.h>
#include <unistd.h>
#include <cerrno>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <vector>
#include <algorithm>
#include <set>

namespace {
using keykey::linux_ime::GuanyinmaSession;
using keykey::linux_ime::readingToQuery;
using keykey::linux_ime::queryToReading;
namespace fs = std::filesystem;
using Json = std::unique_ptr<json_object, decltype(&json_object_put)>;
constexpr std::size_t ArchiveLimit = 64U * 1024U * 1024U;

Json parse(const std::string &text) {
    if (text.size() > ArchiveLimit) throw std::runtime_error("JSON 超過 64 MiB");
    auto *tokener = json_tokener_new();
    if (!tokener) throw std::bad_alloc();
    auto *value = json_tokener_parse_ex(tokener, text.data(), static_cast<int>(text.size()));
    const auto error = json_tokener_get_error(tokener);
    const auto end = json_tokener_get_parse_end(tokener);
    json_tokener_free(tokener);
    Json result(value, &json_object_put);
    if (error != json_tokener_success || !value ||
        text.find_first_not_of(" \r\n\t", end) != std::string::npos)
        throw std::runtime_error("無效 JSON");
    return result;
}
json_object *field(json_object *value, const char *name, json_type type) {
    json_object *child = nullptr;
    if (!json_object_object_get_ex(value, name, &child) || !json_object_is_type(child, type))
        throw std::runtime_error(std::string("無效核心資料欄位：") + name);
    return child;
}
void put(json_object *object, const char *key, const std::string &text) {
    json_object_object_add(object, key,
        json_object_new_string_len(text.data(), static_cast<int>(text.size())));
}
std::string query(const std::string &reading) {
    const auto encoded = readingToQuery(reading);
    if (encoded.empty()) throw std::runtime_error("無效注音讀音");
    return encoded;
}
std::string modelPath() {
    const char *directory = std::getenv("CHICHI77_KEYKEY_DATA_DIR");
    return std::string(directory && *directory ? directory : KEYKEY_LINUX_DATA_DIR) +
           "/smart-mandarin.db";
}
bool sameFile(const fs::path &first, const fs::path &second) {
    std::error_code a, b;
    const auto left = fs::weakly_canonical(first, a);
    const auto right = fs::weakly_canonical(second, b);
    if (!a && !b && left == right) return true;
    std::error_code error;
    return fs::equivalent(first, second, error) && !error;
}
void protectBackup(const fs::path &destination, const std::string &model) {
    if (destination.empty() || fs::is_symlink(destination))
        throw std::runtime_error("備份目的地不可為空或符號連結");
    std::vector<std::string> protectedPaths{model,
        GuanyinmaSession::defaultUserDatabasePath(),
        std::string(KEYKEY_LINUX_DATA_DIR) + "/smart-mandarin.db"};
    // Overrides select this invocation's store; they do not make the normal
    // profile files safe backup destinations.
    for (const char *variable : {"XDG_DATA_HOME", "HOME"}) {
        const auto *base = std::getenv(variable);
        if (!base || !*base) continue;
        const auto directory = fs::path(base) /
            (std::string(variable) == "HOME" ? ".local/share/chichi77-keykey" : "chichi77-keykey");
        for (const char *name : {"guanyinma-user.db"})
            protectedPaths.push_back((directory / name).string());
    }
    for (const auto &path : protectedPaths) {
        if (path.empty()) continue;
        for (const char *suffix : {"", "-wal", "-shm", "-journal"})
            if (sameFile(destination, path + suffix))
                throw std::runtime_error("備份不可覆蓋模型、使用者資料庫或其別名");
    }
}
void atomicWrite(const fs::path &destination, const std::string &content, const std::string &model) {
    protectBackup(destination, model);
    auto parent = destination.parent_path();
    if (parent.empty()) parent = ".";
    const auto temporary = (parent / ".keykey-backup-XXXXXX").string();
    std::vector<char> name(temporary.begin(), temporary.end());
    name.push_back('\0');
    int descriptor = mkstemp(name.data());
    if (descriptor < 0) throw std::runtime_error("無法建立私有備份暫存檔");
    try {
        std::size_t position = 0;
        while (position < content.size()) {
            const auto count = write(descriptor, content.data() + position, content.size() - position);
            if (count < 0 && errno == EINTR) continue;
            if (count <= 0) throw std::runtime_error("備份寫入失敗");
            position += static_cast<std::size_t>(count);
        }
        if (fsync(descriptor) != 0) throw std::runtime_error("備份同步失敗");
        const int closed = close(descriptor);
        descriptor = -1;
        if (closed != 0) throw std::runtime_error("備份關閉失敗");
        protectBackup(destination, model);
        fs::rename(name.data(), destination);
    } catch (...) {
        if (descriptor >= 0) close(descriptor);
        unlink(name.data());
        throw;
    }
}
std::string readArchive(const fs::path &path) {
    const auto size = fs::file_size(path);
    if (size > ArchiveLimit) throw std::runtime_error("備份檔超過 64 MiB");
    std::ifstream input(path, std::ios::binary);
    if (!input) throw std::runtime_error("無法讀取備份");
    std::string content(static_cast<std::size_t>(size), '\0');
    input.read(content.data(), static_cast<std::streamsize>(content.size()));
    if (!input || input.peek() != std::char_traits<char>::eof())
        throw std::runtime_error("備份讀取失敗或讀取期間有變更");
    return content;
}
std::vector<std::string> scalars(const std::string &text) {
    std::vector<std::string> result;
    for (std::size_t offset = 0; offset < text.size();) {
        const auto lead = static_cast<unsigned char>(text[offset]);
        const std::size_t width = lead < 0x80 ? 1 : lead >= 0xc2 && lead <= 0xdf ? 2 :
            lead >= 0xe0 && lead <= 0xef ? 3 : lead >= 0xf0 && lead <= 0xf4 ? 4 : 0;
        if (!width || offset + width > text.size()) throw std::runtime_error("詞語不是有效 UTF-8");
        for (std::size_t i = 1; i < width; ++i)
            if ((static_cast<unsigned char>(text[offset + i]) & 0xc0) != 0x80)
                throw std::runtime_error("詞語不是有效 UTF-8");
        if (width >= 3) {
            const auto second = static_cast<unsigned char>(text[offset + 1]);
            if ((lead == 0xe0 && second < 0xa0) || (lead == 0xed && second >= 0xa0) ||
                (lead == 0xf0 && second < 0x90) || (lead == 0xf4 && second >= 0x90))
                throw std::runtime_error("詞語不是有效 UTF-8");
        }
        result.push_back(text.substr(offset, width));
        offset += width;
    }
    return result;
}
Json phraseReadings(const std::string &text, const std::string &model, json_object *userRows) {
    Json result(json_object_new_array(), &json_object_put);
    const auto characters = scalars(text);
    if (characters.empty() || characters.size() > 8) return result;
    std::unique_ptr<sqlite3, decltype(&sqlite3_close)> database(nullptr, sqlite3_close);
    sqlite3 *opened = nullptr;
    const int openedStatus = sqlite3_open_v2(model.c_str(), &opened, SQLITE_OPEN_READONLY, nullptr);
    database.reset(opened);
    if (openedStatus != SQLITE_OK) throw std::runtime_error("無法唯讀查詢共用詞庫");
    const auto modelQueries = [&](const std::string &word) {
        sqlite3_stmt *raw = nullptr;
        if (sqlite3_prepare_v2(database.get(),
            "SELECT DISTINCT qstring FROM unigrams WHERE current=? ORDER BY probability DESC,rowid LIMIT 64",
            -1, &raw, nullptr) != SQLITE_OK) throw std::runtime_error("無法查詢詞語讀音");
        std::unique_ptr<sqlite3_stmt, decltype(&sqlite3_finalize)> statement(raw, sqlite3_finalize);
        sqlite3_bind_text(raw, 1, word.c_str(), -1, SQLITE_TRANSIENT);
        std::vector<std::string> queries;
        int status = SQLITE_ROW;
        while ((status = sqlite3_step(raw)) == SQLITE_ROW) {
            const auto *value = sqlite3_column_text(raw, 0);
            if (value) queries.emplace_back(reinterpret_cast<const char *>(value));
        }
        if (status != SQLITE_DONE) throw std::runtime_error("詞語讀音查詢失敗");
        return queries;
    };
    std::set<std::string> seen;
    const auto append = [&](const std::string &q) {
        if (q.size() != characters.size() * 2 || seen.size() >= 64) return;
        const auto reading = queryToReading(q);
        if (!reading.empty() && seen.insert(reading).second)
            json_object_array_add(result.get(), json_object_new_string_len(reading.data(), static_cast<int>(reading.size())));
    };
    for (std::size_t i = 0; i < json_object_array_length(userRows); ++i) {
        auto *row = json_object_array_get_idx(userRows, i);
        if (text == json_object_get_string(field(row, "current", json_type_string)))
            append(json_object_get_string(field(row, "qstring", json_type_string)));
    }
    for (const auto &q : modelQueries(text)) append(q);
    if (seen.empty()) {
        std::vector<std::string> combinations{std::string{}};
        for (const auto &character : characters) {
            auto alternatives = modelQueries(character);
            std::vector<std::string> next;
            for (const auto &prefix : combinations) {
                for (const auto &q : alternatives) {
                    if (q.size() != 2 || queryToReading(q).empty()) continue;
                    if (next.size() < 64) next.push_back(prefix + q);
                }
                if (next.size() == 64) break;
            }
            combinations = std::move(next);
            if (combinations.empty()) break;
        }
        for (const auto &q : combinations) append(q);
    }
    return result;
}
} // namespace

int guanyinmaPhrases(int argc, char **argv) {
    try {
        if (argc < 2) throw std::runtime_error("缺少指令：list/readings/add/remove/update/reset-learning/export/import");
        const std::string command = argv[1];
        // Reject removed/unknown commands before opening any user database.
        if (command != "list" && command != "readings" && command != "add" &&
            command != "remove" && command != "update" && command != "reset-learning" &&
            command != "export" && command != "import")
            throw std::runtime_error("無效指令；可用 list/readings/add/remove/update/reset-learning/export/import");
        const auto model = modelPath();
        keykey::linux_ime::GuanyinmaConfig config;
        GuanyinmaSession session(model, GuanyinmaSession::defaultUserDatabasePath(),
                                config, [](const std::string &) { return true; });
        Json operation(json_object_new_object(), &json_object_put);
        if ((argc == 2 && command == "list") ||
            (argc == 3 && command == "list" && std::string(argv[2]) == "--json") ||
            (argc == 3 && command == "readings")) {
            auto result = parse(session.userDataJson());
            auto *rows = field(field(result.get(), "data", json_type_object), "phrases", json_type_array);
            if (command == "readings") {
                auto readings = phraseReadings(argv[2], model, rows);
                std::cout << json_object_to_json_string_ext(readings.get(), JSON_C_TO_STRING_PLAIN) << '\n';
                return 0;
            }
            Json jsonRows(json_object_new_array(), &json_object_put);
            for (std::size_t i = 0; i < json_object_array_length(rows); ++i) {
                auto *row = json_object_array_get_idx(rows, i);
                const std::string text = json_object_get_string(field(row, "current", json_type_string));
                const std::string qstring = json_object_get_string(field(row, "qstring", json_type_string));
                const auto reading = queryToReading(qstring);
                if (argc == 2) std::cout << text << '\t' << reading << '\n';
                else {
                    auto *entry = json_object_new_object();
                    put(entry, "text", text); put(entry, "reading", reading); put(entry, "qstring", qstring);
                    json_object_array_add(jsonRows.get(), entry);
                }
            }
            if (argc == 3) std::cout << json_object_to_json_string_ext(jsonRows.get(), JSON_C_TO_STRING_PLAIN) << '\n';
            return 0;
        }
        if (argc == 2 && command == "reset-learning") {
            put(operation.get(), "type", "reset_method_learning");
            put(operation.get(), "method", "smart");
        } else if (argc == 4 && (command == "add" || command == "remove")) {
            put(operation.get(), "type", command == "add" ? "add_user_phrase" : "remove_user_phrase");
            put(operation.get(), "text", argv[2]);
            put(operation.get(), "qstring", query(argv[3]));
        } else if (argc == 6 && command == "update") {
            put(operation.get(), "type", "update_user_phrase");
            put(operation.get(), "text", argv[2]);
            put(operation.get(), "qstring", query(argv[3]));
            put(operation.get(), "new_text", argv[4]);
            put(operation.get(), "new_qstring", query(argv[5]));
        } else if (argc == 3 && command == "import") {
            const auto content = readArchive(argv[2]);
            GuanyinmaSession::validateArchive(content);
            auto archive = parse(content);
            put(operation.get(), "type", "import_user_data");
            json_object_object_add(operation.get(), "archive", archive.release());
        } else if (argc == 3 && command == "export") {
            auto result = parse(session.userDataJson());
            auto *data = field(result.get(), "data", json_type_object);
            Json archive(json_object_new_object(), &json_object_put);
            put(archive.get(), "format", "guanyinma_user_data");
            json_object_object_add(archive.get(), "schema_version", json_object_new_int(1));
            json_object_object_add(archive.get(), "phrases", json_object_get(field(data, "phrases", json_type_array)));
            auto *smart = json_object_new_object();
            json_object_object_add(smart, "overrides", json_object_get(field(data, "overrides", json_type_array)));
            json_object_object_add(smart, "bigrams", json_object_get(field(data, "bigrams", json_type_array)));
            json_object_object_add(archive.get(), "smart", smart);
            json_object_object_add(archive.get(), "table", json_object_get(field(data, "table", json_type_array)));
            const std::string content = json_object_to_json_string_ext(archive.get(), JSON_C_TO_STRING_PRETTY);
            GuanyinmaSession::validateArchive(content);
            atomicWrite(argv[2], content + "\n", model);
            std::cout << "已匯出完整 Guanyinma 備份。\n";
            return 0;
        } else throw std::runtime_error("無效指令或參數；可用 list/readings/add/remove/update/reset-learning/export/import");
        const bool phraseEdit = command == "add" || command == "remove" || command == "update";
        std::string previousPhrases;
        if (phraseEdit) {
            auto data = parse(session.userDataJson());
            previousPhrases = json_object_to_json_string_ext(
                field(field(data.get(), "data", json_type_object), "phrases", json_type_array), JSON_C_TO_STRING_PLAIN);
        }
        session.applyJson(json_object_to_json_string_ext(operation.get(), JSON_C_TO_STRING_PLAIN));
        if (phraseEdit) {
            auto data = parse(session.userDataJson());
            const std::string currentPhrases = json_object_to_json_string_ext(
                field(field(data.get(), "data", json_type_object), "phrases", json_type_array), JSON_C_TO_STRING_PLAIN);
            if (previousPhrases == currentPhrases)
                throw std::runtime_error(command == "add" ? "相同詞語與讀音已存在於內建或自訂詞庫。" :
                    command == "remove" ? "找不到指定的自訂詞。" : "詞語與讀音沒有變更。");
        }
        std::cout << "已更新 Guanyinma 使用者資料。\n";
        return 0;
    } catch (const std::exception &error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
