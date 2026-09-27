#include "keykey/linux_ime/associated_phrase_dictionary.h"

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <map>
#include <stdexcept>
#include <utility>

namespace keykey::linux_ime {
namespace {

namespace fs = std::filesystem;

struct PhraseRow {
    std::string word;
    std::uint64_t count = 0;
    std::size_t firstCodePointLength = 0;
};

std::string trimAscii(const std::string &value) {
    const std::size_t first = value.find_first_not_of(" \t\r\n");
    if (first == std::string::npos) {
        return {};
    }
    const std::size_t last = value.find_last_not_of(" \t\r\n");
    return value.substr(first, last - first + 1);
}

std::string cleanLine(std::string line) {
    if (!line.empty() && line.back() == '\r') {
        line.pop_back();
    }
    if (line.size() >= 3 &&
        static_cast<unsigned char>(line[0]) == 0xEFU &&
        static_cast<unsigned char>(line[1]) == 0xBBU &&
        static_cast<unsigned char>(line[2]) == 0xBFU) {
        line.erase(0, 3);
    }
    return line;
}

std::vector<std::string> split(const std::string &line, char delimiter) {
    std::vector<std::string> fields;
    std::size_t start = 0;
    while (start <= line.size()) {
        const std::size_t end = line.find(delimiter, start);
        fields.push_back(line.substr(
            start, end == std::string::npos ? std::string::npos : end - start));
        if (end == std::string::npos) {
            break;
        }
        start = end + 1;
    }
    return fields;
}

std::vector<std::string> splitWhitespace(const std::string &line) {
    std::vector<std::string> fields;
    fields.reserve(4);
    std::size_t offset = 0;
    while (offset < line.size()) {
        while (offset < line.size() &&
               std::isspace(static_cast<unsigned char>(line[offset])) != 0) {
            ++offset;
        }
        const std::size_t start = offset;
        while (offset < line.size() &&
               std::isspace(static_cast<unsigned char>(line[offset])) == 0) {
            ++offset;
        }
        if (start < offset) {
            fields.push_back(line.substr(start, offset - start));
        }
    }
    return fields;
}

std::uint64_t parseCount(const std::string &field) {
    const std::string value = trimAscii(field);
    if (value.empty() ||
        !std::all_of(value.begin(), value.end(), [](unsigned char character) {
            return std::isdigit(character) != 0;
        })) {
        return 0;
    }
    try {
        return std::stoull(value);
    } catch (const std::exception &) {
        return 0;
    }
}

std::size_t decodeUtf8(const std::string &text, std::size_t offset,
                       char32_t &codePoint) noexcept {
    if (offset >= text.size()) {
        return 0;
    }
    const auto first = static_cast<unsigned char>(text[offset]);
    std::size_t length = 0;
    char32_t value = 0;
    if (first <= 0x7FU) {
        length = 1;
        value = first;
    } else if (first >= 0xC2U && first <= 0xDFU) {
        length = 2;
        value = static_cast<char32_t>(first & 0x1FU);
    } else if (first >= 0xE0U && first <= 0xEFU) {
        length = 3;
        value = static_cast<char32_t>(first & 0x0FU);
    } else if (first >= 0xF0U && first <= 0xF4U) {
        length = 4;
        value = static_cast<char32_t>(first & 0x07U);
    } else {
        return 0;
    }
    if (offset + length > text.size()) {
        return 0;
    }
    for (std::size_t index = 1; index < length; ++index) {
        const auto continuation =
            static_cast<unsigned char>(text[offset + index]);
        if ((continuation & 0xC0U) != 0x80U) {
            return 0;
        }
        value = static_cast<char32_t>((value << 6U) |
                                      (continuation & 0x3FU));
    }
    if ((length == 3 && value < 0x800U) ||
        (length == 4 && value < 0x10000U) ||
        (value >= 0xD800U && value <= 0xDFFFU) || value > 0x10FFFFU) {
        return 0;
    }
    codePoint = value;
    return length;
}

bool isHan(char32_t codePoint) noexcept {
    return codePoint == 0x3007U ||
           (codePoint >= 0x3400U && codePoint <= 0x4DBFU) ||
           (codePoint >= 0x4E00U && codePoint <= 0x9FFFU) ||
           (codePoint >= 0xF900U && codePoint <= 0xFAFFU) ||
           (codePoint >= 0x20000U && codePoint <= 0x323AFU);
}

std::size_t codePointCount(const std::string &text) noexcept {
    std::size_t count = 0;
    for (std::size_t offset = 0; offset < text.size();) {
        char32_t codePoint = 0;
        const std::size_t length = decodeUtf8(text, offset, codePoint);
        if (length == 0) {
            return 0;
        }
        offset += length;
        ++count;
    }
    return count;
}

bool beginsWithHan(const std::string &text,
                   std::size_t &firstCodePointLength) noexcept {
    char32_t codePoint = 0;
    firstCodePointLength = decodeUtf8(text, 0, codePoint);
    return firstCodePointLength != 0 && isHan(codePoint);
}

std::unordered_map<std::string, std::string>
loadDisplayNames(const fs::path &path) {
    std::ifstream input(path, std::ios::binary);
    if (!input) {
        throw std::runtime_error("Cannot open associated-phrase display names: " +
                                 path.string());
    }
    std::unordered_map<std::string, std::string> names;
    std::string line;
    while (std::getline(input, line)) {
        const std::vector<std::string> fields = split(cleanLine(line), '\t');
        if (fields.size() < 2) {
            continue;
        }
        const std::string source = trimAscii(fields[0]);
        const std::string displayName = trimAscii(fields[1]);
        if (!source.empty() && source != "source" && !displayName.empty()) {
            names[source] = displayName;
        }
    }
    if (names.empty()) {
        throw std::runtime_error("Associated-phrase display names are empty: " +
                                 path.string());
    }
    return names;
}

std::string displayNameFromCollection(const fs::path &path) {
    std::ifstream input(path, std::ios::binary);
    if (!input) {
        throw std::runtime_error("Cannot open associated-phrase collection: " +
                                 path.string());
    }
    std::string line;
    while (std::getline(input, line)) {
        const std::vector<std::string> fields = split(cleanLine(line), '\t');
        if (fields.size() < 4) {
            continue;
        }
        const std::string value = trimAscii(fields[3]);
        if (!value.empty() && value != "分類") {
            return value;
        }
    }
    return {};
}

std::unordered_set<std::string>
loadBaseExclusions(const std::vector<fs::path> &categoryPaths) {
    std::unordered_set<std::string> exclusions;
    for (const fs::path &path : categoryPaths) {
        const std::string name = path.filename().string();
        if (name.rfind("phrase.people-", 0) != 0) {
            continue;
        }
        std::ifstream input(path, std::ios::binary);
        if (!input) {
            throw std::runtime_error(
                "Cannot open associated-phrase exclusion source: " +
                path.string());
        }
        std::string line;
        while (std::getline(input, line)) {
            const std::vector<std::string> fields = split(cleanLine(line), '\t');
            if (fields.empty()) {
                continue;
            }
            const std::string word = trimAscii(fields[0]);
            if (!word.empty() && word != "詞") {
                exclusions.insert(word);
            }
        }
    }
    return exclusions;
}

std::size_t phraseCount(
    const AssociatedPhraseDictionary::CandidateMap &entries) noexcept {
    std::size_t count = 0;
    for (const auto &entry : entries) {
        count += entry.second.size();
    }
    return count;
}

} // namespace

AssociatedPhraseDictionary::CandidateMap
AssociatedPhraseDictionary::parseCollection(
    std::istream &input,
    const std::unordered_set<std::string> &exclusions) {
    std::vector<PhraseRow> rows;
    std::unordered_map<std::string, std::size_t> rowIndexes;
    std::string line;
    while (std::getline(input, line)) {
        line = cleanLine(std::move(line));
        const std::vector<std::string> fields =
            line.find('\t') == std::string::npos ? splitWhitespace(line)
                                                  : split(line, '\t');
        if (fields.size() < 2) {
            continue;
        }
        const std::string word = trimAscii(fields[0]);
        const std::uint64_t count = parseCount(fields[1]);
        if (count == 0 || exclusions.find(word) != exclusions.end()) {
            continue;
        }
        std::size_t firstCodePointLength = 0;
        if (!beginsWithHan(word, firstCodePointLength)) {
            continue;
        }
        const std::size_t length = codePointCount(word);
        if (length < 2 || length > 20) {
            continue;
        }

        const auto previous = rowIndexes.find(word);
        if (previous == rowIndexes.end()) {
            rowIndexes.emplace(word, rows.size());
            rows.push_back(PhraseRow{word, count, firstCodePointLength});
        } else {
            PhraseRow &row = rows[previous->second];
            row.count = std::max(row.count, count);
        }
    }

    std::uint64_t total = 0;
    for (const PhraseRow &row : rows) {
        total += row.count;
    }
    if (total == 0) {
        return {};
    }

    std::map<std::string, std::vector<PhraseRow>> grouped;
    for (const PhraseRow &row : rows) {
        if (static_cast<long double>(row.count) * 1000000.0L <= total ||
            row.word.find("媽的") != std::string::npos) {
            continue;
        }
        grouped[row.word.substr(0, row.firstCodePointLength)].push_back(row);
    }

    CandidateMap result;
    for (auto &entry : grouped) {
        std::vector<PhraseRow> &phrases = entry.second;
        std::stable_sort(phrases.begin(), phrases.end(),
                         [](const PhraseRow &left, const PhraseRow &right) {
                             return left.count > right.count;
                         });
        std::vector<std::string> suffixes;
        suffixes.reserve(phrases.size());
        for (const PhraseRow &phrase : phrases) {
            suffixes.push_back(
                phrase.word.substr(phrase.firstCodePointLength));
        }
        result.emplace(entry.first, std::move(suffixes));
    }
    return result;
}

AssociatedPhraseDictionary AssociatedPhraseDictionary::loadDirectory(
    const std::string &directoryPath) {
    const fs::path directory = fs::u8path(directoryPath);
    if (!fs::is_directory(directory)) {
        throw std::runtime_error("Associated-phrase data directory is missing: " +
                                 directory.string());
    }

    const auto displayNames =
        loadDisplayNames(directory / "display-names.tsv");
    std::vector<fs::path> categoryPaths;
    for (const fs::directory_entry &entry : fs::directory_iterator(directory)) {
        if (!entry.is_regular_file()) {
            continue;
        }
        const std::string name = entry.path().filename().string();
        if (name.rfind("phrase.", 0) == 0 &&
            entry.path().extension() == ".tsv") {
            categoryPaths.push_back(entry.path());
        }
    }
    std::sort(categoryPaths.begin(), categoryPaths.end());
    const auto exclusions = loadBaseExclusions(categoryPaths);

    AssociatedPhraseDictionary dictionary;
    const auto addCollection = [&](const std::string &source,
                                   const std::string &displayName,
                                   const fs::path &path,
                                   const std::unordered_set<std::string>
                                       &collectionExclusions) {
        std::ifstream input(path, std::ios::binary);
        if (!input) {
            throw std::runtime_error("Cannot open associated-phrase collection: " +
                                     path.string());
        }
        CandidateMap entries =
            parseCollection(input, collectionExclusions);
        const std::size_t count = phraseCount(entries);
        if (count == 0) {
            throw std::runtime_error("No usable associated phrases in: " +
                                     path.string());
        }
        if (dictionary.collectionIndexes_.find(source) !=
            dictionary.collectionIndexes_.end()) {
            throw std::runtime_error("Duplicate associated-phrase source: " +
                                     source);
        }
        Collection info{source, displayName.empty() ? source : displayName,
                        count};
        dictionary.collectionIndexes_.emplace(
            source, dictionary.collectionData_.size());
        dictionary.entryCount_ += count;
        dictionary.collections_.push_back(info);
        dictionary.collectionData_.push_back(CollectionData{std::move(entries)});
    };

    const auto baseName = displayNames.find("McBopomofo");
    addCollection("McBopomofo",
                  baseName == displayNames.end() ? "McBopomofo"
                                                 : baseName->second,
                  directory / "McBopomofo.occ", exclusions);

    for (const fs::path &path : categoryPaths) {
        const std::string fileName = path.filename().string();
        const std::size_t prefixLength = std::string("phrase.").size();
        const std::size_t suffixLength = std::string(".tsv").size();
        const std::string source = fileName.substr(
            prefixLength, fileName.size() - prefixLength - suffixLength);
        const auto overrideName = displayNames.find(source);
        const std::string displayName =
            overrideName == displayNames.end()
                ? displayNameFromCollection(path)
                : overrideName->second;
        addCollection(source, displayName, path, {});
    }
    return dictionary;
}

std::vector<std::string> AssociatedPhraseDictionary::candidates(
    const std::string &headCharacter,
    const std::vector<std::string> &enabledSources) const {
    std::vector<std::string> result;
    std::unordered_set<std::string> seen;
    for (const std::string &source : enabledSources) {
        const auto collection = collectionIndexes_.find(source);
        if (collection == collectionIndexes_.end()) {
            continue;
        }
        const CandidateMap &entries =
            collectionData_[collection->second].entries;
        const auto phrases = entries.find(headCharacter);
        if (phrases == entries.end()) {
            continue;
        }
        for (const std::string &suffix : phrases->second) {
            if (seen.insert(suffix).second) {
                result.push_back(suffix);
            }
        }
    }
    return result;
}

const std::vector<AssociatedPhraseDictionary::Collection> &
AssociatedPhraseDictionary::collections() const noexcept {
    return collections_;
}

std::size_t AssociatedPhraseDictionary::entryCount() const noexcept {
    return entryCount_;
}

} // namespace keykey::linux_ime
