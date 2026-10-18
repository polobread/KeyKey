#pragma once

#include <cstddef>
#include <istream>
#include <functional>
#include <map>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace keykey::linux_ime {

class CinDictionary {
public:
    static CinDictionary loadFile(const std::string &path);
    static CinDictionary load(std::istream &input);

    const std::vector<std::string> &candidates(const std::string &key) const;
    std::vector<std::string>
    candidatesMatching(const std::string &pattern, char matchOne,
                       char matchZeroOrMore) const;
    void forEachPrefixValue(const std::string &prefix,
                            const std::function<void(const std::string &)> &visitor) const;
    const std::string &keyName(const std::string &key) const;
    bool hasKeyName(const std::string &key) const noexcept;
    bool isEndKey(const std::string &key) const noexcept;
    std::vector<std::string> keys() const;
    std::size_t keyCount() const noexcept;
    std::size_t entryCount() const noexcept;

private:
    struct Entry {
        std::vector<std::string> values;
        std::vector<std::size_t> rows;
    };
    std::map<std::string, Entry> entries_;
    std::unordered_map<std::string, std::string> keyNames_;
    std::unordered_set<std::string> endKeys_;
    std::size_t entryCount_ = 0;
};

} // namespace keykey::linux_ime
