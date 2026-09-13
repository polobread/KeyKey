#pragma once

#include <cstddef>
#include <istream>
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
    const std::string &keyName(const std::string &key) const;
    bool hasKeyName(const std::string &key) const noexcept;
    bool isEndKey(const std::string &key) const noexcept;
    std::vector<std::string> keys() const;
    std::size_t keyCount() const noexcept;
    std::size_t entryCount() const noexcept;

private:
    std::unordered_map<std::string, std::vector<std::string>> entries_;
    std::unordered_map<std::string, std::string> keyNames_;
    std::unordered_set<std::string> endKeys_;
    std::size_t entryCount_ = 0;
};

} // namespace keykey::linux_ime
