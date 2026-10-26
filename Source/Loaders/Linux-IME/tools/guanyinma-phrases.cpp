// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
#include "keykey/linux_ime/guanyinma_session.h"
#include "keykey/linux_ime/smart_mandarin_user_data.h"
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

namespace {
using keykey::linux_ime::GuanyinmaSession;
using keykey::linux_ime::SmartMandarinUserData;
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
    const auto encoded = SmartMandarinUserData::readingToQuery(reading);
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
    std::vector<std::string> protectedPaths{model, SmartMandarinUserData::defaultPath(),
        GuanyinmaSession::defaultUserDatabasePath(),
        std::string(KEYKEY_LINUX_DATA_DIR) + "/smart-mandarin.db"};
    // Overrides select this invocation's store; they do not make the normal
    // profile files safe backup destinations.
    for (const char *variable : {"XDG_DATA_HOME", "HOME"}) {
        const auto *base = std::getenv(variable);
        if (!base || !*base) continue;
        const auto directory = fs::path(base) /
            (std::string(variable) == "HOME" ? ".local/share/chichi77-keykey" : "chichi77-keykey");
        for (const char *name : {"smart-mandarin-user.db", "guanyinma-user.db"})
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
} // namespace

int guanyinmaPhrases(int argc, char **argv) {
    try {
        if (argc < 2) throw std::runtime_error("缺少指令：list/add/remove/update/reset-learning/export/import/import-legacy");
        const std::string command = argv[1];
        const auto model = modelPath();
        keykey::linux_ime::GuanyinmaConfig config;
        GuanyinmaSession session(model, GuanyinmaSession::defaultUserDatabasePath(),
                                config, [](const std::string &) { return true; });
        Json operation(json_object_new_object(), &json_object_put);
        if (argc == 2 && command == "list") {
            auto result = parse(session.userDataJson());
            auto *rows = field(field(result.get(), "data", json_type_object), "phrases", json_type_array);
            for (std::size_t i = 0; i < json_object_array_length(rows); ++i) {
                auto *row = json_object_array_get_idx(rows, i);
                std::cout << json_object_get_string(field(row, "current", json_type_string)) << '\t'
                          << SmartMandarinUserData::queryToReading(
                                 json_object_get_string(field(row, "qstring", json_type_string))) << '\n';
            }
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
        } else if (argc == 3 && command == "import-legacy") {
            put(operation.get(), "type", "import_legacy_user_data");
            put(operation.get(), "path", fs::absolute(argv[2]).string());
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
        } else throw std::runtime_error("無效指令或參數；可用 list/add/remove/update/reset-learning/export/import/import-legacy");
        session.applyJson(json_object_to_json_string_ext(operation.get(), JSON_C_TO_STRING_PLAIN));
        std::cout << "已更新 Guanyinma 使用者資料；C++ 原核心資料未變。\n";
        return 0;
    } catch (const std::exception &error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
