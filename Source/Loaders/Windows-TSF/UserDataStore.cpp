#include "UserDataStore.h"

#include <Windows.h>

#include <memory>
#include <string>
#include <utility>
#include <cwchar>
#include <algorithm>
#include <map>

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

ReadingLookup LookupPhraseReadings(const std::wstring& databasePath, const std::wstring& phrase) {
    ReadingLookup result;
    if (phrase.empty() || phrase.size() > 128) return result;
    // Reject malformed UTF-16 rather than silently dropping a surrogate.
    for (size_t i = 0; i < phrase.size(); ++i) {
        const auto c = static_cast<unsigned>(phrase[i]);
        if (c >= 0xD800 && c <= 0xDBFF) {
            if (++i >= phrase.size() || phrase[i] < 0xDC00 || phrase[i] > 0xDFFF) return result;
        } else if (c >= 0xDC00 && c <= 0xDFFF) return result;
    }
    const auto points = OpenVanilla::OVUTF8Helper::SplitStringByCodePoint(ToUtf8(phrase));
    if (points.empty() || points.size() > 64) return result;
    for (const auto& point : points) result.characters.push_back({ToWide(point), {}});
    sqlite3* db = nullptr;
    const auto path = ToUtf8(databasePath);
    if (sqlite3_open_v2(path.c_str(), &db, SQLITE_OPEN_READONLY, nullptr) != SQLITE_OK) {
        if (db) sqlite3_close(db);
        result.status = ReadingLookupStatus::DatabaseError;
        return result;
    }
    const std::unique_ptr<sqlite3, decltype(&sqlite3_close)> database(db, sqlite3_close);
    bool good = true;
    {
        Statement query(db, "SELECT DISTINCT qstring FROM unigrams WHERE current = ? "
                            "ORDER BY probability DESC, qstring LIMIT 256");
        good = query.value != nullptr;
        auto lookup = [&](const std::string& text, size_t syllables) {
            std::vector<std::wstring> readings;
            if (!query.value) return readings;
            sqlite3_reset(query.value);
            sqlite3_clear_bindings(query.value);
            sqlite3_bind_text(query.value, 1, text.c_str(), -1, SQLITE_TRANSIENT);
            int step = SQLITE_DONE;
            while ((step = sqlite3_step(query.value)) == SQLITE_ROW) {
                const char* raw = reinterpret_cast<const char*>(sqlite3_column_text(query.value, 0));
                if (!raw) continue;
                const std::string encoded(raw);
                if (encoded.size() != syllables * 2) continue;
                const auto reading = DecodeReading(encoded);
                size_t decodedCount = 0;
                if (reading.empty() || EncodeReading(reading, decodedCount) != encoded || decodedCount != syllables) continue;
                if (std::find(readings.begin(), readings.end(), reading) == readings.end()) readings.push_back(reading);
                if (readings.size() == 32) break;
            }
            if (step != SQLITE_ROW && step != SQLITE_DONE) good = false;
            return readings;
        };
        result.wholePhraseReadings = lookup(ToUtf8(phrase), points.size());
        for (const auto& combination : result.wholePhraseReadings) {
            size_t start = 0;
            for (auto& character : result.characters) {
                const auto end = combination.find(L',', start);
                const auto reading = combination.substr(start, end - start);
                if (std::find(character.readings.begin(), character.readings.end(), reading) == character.readings.end())
                    character.readings.push_back(reading);
                start = end == std::wstring::npos ? combination.size() : end + 1;
            }
        }
        std::map<std::string, std::vector<std::wstring>> characterCache;
        for (size_t i = 0; i < points.size(); ++i) {
            auto found = characterCache.find(points[i]);
            if (found == characterCache.end()) found = characterCache.emplace(points[i], lookup(points[i], 1)).first;
            for (const auto& reading : found->second) {
                auto& choices = result.characters[i].readings;
                if (choices.size() < 32 && std::find(choices.begin(), choices.end(), reading) == choices.end()) choices.push_back(reading);
            }
        }
    }
    bool any = !result.wholePhraseReadings.empty();
    for (const auto& character : result.characters) any = any || !character.readings.empty();
    result.status = !good ? ReadingLookupStatus::DatabaseError :
        any ? ReadingLookupStatus::Success : ReadingLookupStatus::NoReadings;
    return result;
}

}  // namespace KeyKey::WindowsTsf
