#include "keykey/linux_ime/cin_dictionary.h"

#include <algorithm>
#include <cctype>
#include <fstream>
#include <sstream>
#include <stdexcept>

namespace keykey::linux_ime {
namespace {

std::string trim(std::string value) {
    if (value.size() >= 3 &&
        static_cast<unsigned char>(value[0]) == 0xEFU &&
        static_cast<unsigned char>(value[1]) == 0xBBU &&
        static_cast<unsigned char>(value[2]) == 0xBFU) {
        value.erase(0, 3);
    }
    const auto isSpace = [](unsigned char character) {
        return std::isspace(character) != 0;
    };
    const auto first = std::find_if_not(value.begin(), value.end(), isSpace);
    const auto last = std::find_if_not(value.rbegin(), value.rend(), isSpace).base();
    if (first >= last) {
        return {};
    }
    return std::string(first, last);
}

std::string lowercase(std::string value) {
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char character) {
        return static_cast<char>(std::tolower(character));
    });
    return value;
}

} // namespace

CinDictionary CinDictionary::loadFile(const std::string &path) {
    std::ifstream input(path, std::ios::binary);
    if (!input) {
        throw std::runtime_error("Cannot open CIN data: " + path);
    }
    return load(input);
}

CinDictionary CinDictionary::load(std::istream &input) {
    CinDictionary dictionary;
    bool inKeyNames = false;
    bool inCharacterDefinitions = false;
    bool sawCharacterDefinitions = false;
    std::size_t lineNumber = 0;
    std::string line;
    while (std::getline(input, line)) {
        ++lineNumber;
        const std::string cleaned = trim(std::move(line));
        if (cleaned.empty()) {
            continue;
        }

        const std::string lowered = lowercase(cleaned);
        if (lowered.rfind("%keyname", 0) == 0) {
            std::istringstream directive(lowered);
            std::string name;
            std::string action;
            directive >> name >> action;
            if (action == "begin") {
                if (inKeyNames) {
                    throw std::runtime_error(
                        "Nested %keyname begin at line " +
                        std::to_string(lineNumber));
                }
                inKeyNames = true;
            } else if (action == "end") {
                if (!inKeyNames) {
                    throw std::runtime_error(
                        "%keyname end without begin at line " +
                        std::to_string(lineNumber));
                }
                inKeyNames = false;
            }
            continue;
        }
        if (lowered.rfind("%chardef", 0) == 0) {
            std::istringstream directive(lowered);
            std::string name;
            std::string action;
            directive >> name >> action;
            if (action == "begin") {
                if (inCharacterDefinitions) {
                    throw std::runtime_error(
                        "Nested %chardef begin at line " +
                        std::to_string(lineNumber));
                }
                inCharacterDefinitions = true;
                sawCharacterDefinitions = true;
            } else if (action == "end") {
                if (!inCharacterDefinitions) {
                    throw std::runtime_error(
                        "%chardef end without begin at line " +
                        std::to_string(lineNumber));
                }
                inCharacterDefinitions = false;
            }
            continue;
        }
        if (inKeyNames) {
            const auto separator = cleaned.find_first_of(" \t");
            if (separator != std::string::npos) {
                const std::string key = cleaned.substr(0, separator);
                const std::string value = trim(cleaned.substr(separator + 1));
                if (!key.empty() && !value.empty()) {
                    dictionary.keyNames_.insert_or_assign(key, value);
                }
            }
            continue;
        }
        if (!inCharacterDefinitions) {
            continue;
        }

        const auto separator = cleaned.find_first_of(" \t");
        if (separator == std::string::npos) {
            continue;
        }
        const std::string key = cleaned.substr(0, separator);
        const std::string value = trim(cleaned.substr(separator + 1));
        if (key.empty() || value.empty()) {
            continue;
        }
        dictionary.entries_[key].push_back(value);
        ++dictionary.entryCount_;
    }
    if (!input.eof() && input.fail()) {
        throw std::runtime_error("Failed while reading CIN data");
    }
    if (!sawCharacterDefinitions) {
        throw std::runtime_error("CIN data has no %chardef section");
    }
    if (inKeyNames) {
        throw std::runtime_error("CIN data has an unterminated %keyname section");
    }
    if (inCharacterDefinitions) {
        throw std::runtime_error("CIN data has an unterminated %chardef section");
    }
    return dictionary;
}

const std::vector<std::string> &
CinDictionary::candidates(const std::string &key) const {
    static const std::vector<std::string> empty;
    const auto found = entries_.find(key);
    return found == entries_.end() ? empty : found->second;
}

const std::string &CinDictionary::keyName(const std::string &key) const {
    static const std::string empty;
    const auto found = keyNames_.find(key);
    return found == keyNames_.end() ? empty : found->second;
}

std::vector<std::string> CinDictionary::keys() const {
    std::vector<std::string> result;
    result.reserve(entries_.size());
    for (const auto &entry : entries_) {
        result.push_back(entry.first);
    }
    std::sort(result.begin(), result.end());
    return result;
}

std::size_t CinDictionary::keyCount() const noexcept { return entries_.size(); }

std::size_t CinDictionary::entryCount() const noexcept { return entryCount_; }

} // namespace keykey::linux_ime
