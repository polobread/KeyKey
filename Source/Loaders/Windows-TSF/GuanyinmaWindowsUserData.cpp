// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
#include "GuanyinmaWindowsUserData.h"
#include "GuanyinmaJson.h"
#include "FrontendSettings.h"
#include "SharedFileAccess.h"
#include "Mandarin.h"
#include "OVUTF8Helper.h"
#include <map>
#include <filesystem>

namespace KeyKey::WindowsTsf {
using namespace Guanyinma;
using namespace OpenVanilla;
using Formosa::Mandarin::BPMF;
namespace {
std::string Encode(const std::wstring& reading) {
    const auto utf8 = OVUTF8::FromUTF16(reading);
    std::string result;
    for (size_t pos = 0; pos <= utf8.size();) {
        const auto end = utf8.find(',', pos);
        auto part = utf8.substr(pos, end - pos);
        const auto first = part.find_first_not_of(" \t\r\n");
        const auto last = part.find_last_not_of(" \t\r\n");
        if (first == std::string::npos) return {};
        const auto syllable = BPMF::FromComposedString(part.substr(first, last - first + 1));
        if (syllable.isEmpty()) return {};
        result += syllable.absoluteOrderString();
        if (end == std::string::npos) break;
        pos = end + 1;
    }
    return result;
}
std::wstring Decode(const std::string& qstring) {
    std::string text;
    for (size_t i = 0; i + 1 < qstring.size(); i += 2) {
        if (i) text += ',';
        text += BPMF::FromAbsoluteOrderString(qstring.substr(i, 2)).composedString();
    }
    return OVUTF16::FromUTF8(text);
}
bool SameFile(const std::wstring& first, const std::wstring& second) {
    if (_wcsicmp(SettingsLockPath(first).c_str(), SettingsLockPath(second).c_str()) == 0) return true;
    HANDLE a = CreateFileW(first.c_str(), FILE_READ_ATTRIBUTES, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        nullptr, OPEN_EXISTING, 0, nullptr);
    HANDLE b = CreateFileW(second.c_str(), FILE_READ_ATTRIBUTES, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        nullptr, OPEN_EXISTING, 0, nullptr);
    BY_HANDLE_FILE_INFORMATION x{}, y{};
    const bool same = a != INVALID_HANDLE_VALUE && b != INVALID_HANDLE_VALUE &&
        GetFileInformationByHandle(a, &x) && GetFileInformationByHandle(b, &y) &&
        x.dwVolumeSerialNumber == y.dwVolumeSerialNumber && x.nFileIndexHigh == y.nFileIndexHigh && x.nFileIndexLow == y.nFileIndexLow;
    if (a != INVALID_HANDLE_VALUE) CloseHandle(a);
    if (b != INVALID_HANDLE_VALUE) CloseHandle(b);
    return same;
}
}
struct GuanyinmaWindowsUserData::Impl {
    GuanyinmaSession* session = nullptr;
    std::wstring model;
    std::map<std::int64_t, std::pair<std::string, std::string>> rows;
    std::int64_t nextRow = 0;
    ~Impl() { guanyinma_session_close(&session); }
    Json data() {
        GuanyinmaResult* result = nullptr;
        if (guanyinma_session_user_data(session, &result) != GUANYINMA_OK) throw std::runtime_error(LastError());
        return ReadResult(result).GetNamedObject(L"data");
    }
};
GuanyinmaWindowsUserData::GuanyinmaWindowsUserData(const std::wstring& model) : impl_(std::make_unique<Impl>()) {
    Apartment apartment;
    impl_->model = model;
    const auto directory = SettingsDirectory();
    if (directory.empty()) throw std::runtime_error("no Guanyinma profile");
    Json config; Set(config, L"method", "smart");
    Set(config, L"user_database", OVUTF8::FromUTF16(directory + L"\\GuanyinmaUserData.db"));
    const auto path = OVUTF8::FromUTF16(model), json = winrt::to_string(config.Stringify());
    if (guanyinma_session_open(reinterpret_cast<const uint8_t*>(path.data()), path.size(),
        reinterpret_cast<const uint8_t*>(json.data()), json.size(), &impl_->session) != GUANYINMA_OK) throw std::runtime_error(LastError());
}
GuanyinmaWindowsUserData::~GuanyinmaWindowsUserData() = default;
std::vector<UserPhrase> GuanyinmaWindowsUserData::load() {
    Apartment apartment;
    const auto data = impl_->data();
    impl_->rows.clear();
    std::vector<UserPhrase> rows;
    for (auto const& value : data.GetNamedArray(L"phrases")) {
        const auto phrase = value.GetObject();
        const auto qstring = String(phrase, L"qstring"), text = String(phrase, L"current");
        const auto id = ++impl_->nextRow;
        impl_->rows.emplace(id, std::make_pair(qstring, text));
        rows.push_back({id, OVUTF16::FromUTF8(text), Decode(qstring)});
    }
    return rows;
}
bool GuanyinmaWindowsUserData::save(const UserPhrase& phrase) {
    Apartment apartment;
    const auto qstring = Encode(phrase.reading), text = OVUTF8::FromUTF16(phrase.text);
    if (qstring.empty() || text.empty() || qstring.size() / 2 != OVUTF8Helper::SplitStringByCodePoint(text).size()) return false;
    auto op = Operation(phrase.rowid ? "update_user_phrase" : "add_user_phrase");
    if (phrase.rowid) {
        const auto found = impl_->rows.find(phrase.rowid);
        if (found == impl_->rows.end()) return false;
        Set(op, L"qstring", found->second.first); Set(op, L"text", found->second.second);
        Set(op, L"new_qstring", qstring); Set(op, L"new_text", text);
    } else { Set(op, L"qstring", qstring); Set(op, L"text", text); }
    Apply(impl_->session, op); return true;
}
bool GuanyinmaWindowsUserData::remove(std::int64_t row) {
    Apartment apartment;
    const auto found = impl_->rows.find(row);
    if (found == impl_->rows.end()) return false;
    auto op = Operation("remove_user_phrase");
    Set(op, L"qstring", found->second.first); Set(op, L"text", found->second.second);
    Apply(impl_->session, op); impl_->rows.erase(found); return true;
}
bool GuanyinmaWindowsUserData::resetLearning() {
    Apartment apartment;
    auto op = Operation("reset_method_learning"); Set(op, L"method", "smart");
    Apply(impl_->session, op); return true;
}
bool GuanyinmaWindowsUserData::importData(const std::wstring& path) {
    Apartment apartment;
    std::string content;
    if (!ReadSharedSettingsFile(path, content)) return false;
    Json op;
    if (content.compare(0, 16, std::string("SQLite format 3\0", 16)) == 0) {
        op = Operation("import_legacy_user_data"); Set(op, L"path", OVUTF8::FromUTF16(path));
    } else {
        if (guanyinma_user_archive_validate(reinterpret_cast<const uint8_t*>(content.data()), content.size()) != GUANYINMA_OK) return false;
        op = Operation("import_user_data"); op.SetNamedValue(L"archive", Json::Parse(winrt::to_hstring(content)));
    }
    Apply(impl_->session, op); return true;
}
bool GuanyinmaWindowsUserData::exportData(const std::wstring& path) {
    Apartment apartment;
    if (path.empty()) return false;
    const auto directory = SettingsDirectory();
    std::vector<std::wstring> protectedPaths{impl_->model};
    for (const auto* file : {L"GuanyinmaUserData.db", L"SmartMandarinUserData.db", L"Generic-cj-cin-DynamicCandidateOrder.sqlite3", L"Generic-simplex-cin-DynamicCandidateOrder.sqlite3"})
        for (const auto* suffix : {L"", L"-wal", L"-shm", L"-journal"}) protectedPaths.push_back(directory + L"\\" + file + suffix);
    SettingsFileLock lock(path);
    if (!lock) return false;
    for (const auto& protectedPath : protectedPaths) if (SameFile(path, protectedPath)) return false;
    const auto data = impl_->data();
    Json archive; Set(archive, L"format", "guanyinma_user_data"); Set(archive, L"schema_version", 1);
    archive.SetNamedValue(L"phrases", data.GetNamedArray(L"phrases"));
    Json smart; smart.SetNamedValue(L"overrides", data.GetNamedArray(L"overrides")); smart.SetNamedValue(L"bigrams", data.GetNamedArray(L"bigrams"));
    archive.SetNamedValue(L"smart", smart); archive.SetNamedValue(L"table", data.GetNamedArray(L"table"));
    const auto text = winrt::to_string(archive.Stringify());
    if (guanyinma_user_archive_validate(reinterpret_cast<const uint8_t*>(text.data()), text.size()) != GUANYINMA_OK) return false;
    return WriteSharedSettingsFile(path, text);
}
}
