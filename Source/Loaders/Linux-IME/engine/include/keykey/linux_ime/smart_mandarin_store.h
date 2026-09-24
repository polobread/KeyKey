#pragma once

#include <cstddef>
#include <map>
#include <memory>
#include <string>
#include <vector>

#include "keykey/linux_ime/smart_mandarin_user_data.h"

struct sqlite3;

namespace keykey::linux_ime {

struct SmartSegment {
    std::size_t start = 0;
    std::size_t length = 0;
    std::string query;
    std::string text;
};

struct SmartComposition {
    std::string text;
    std::vector<SmartSegment> segments;
};

class SmartMandarinStore {
public:
    static std::shared_ptr<const SmartMandarinStore> open(
        const std::string &path,
        std::shared_ptr<SmartMandarinUserData> userData = nullptr);
    ~SmartMandarinStore();
    SmartMandarinStore(const SmartMandarinStore &) = delete;
    SmartMandarinStore &operator=(const SmartMandarinStore &) = delete;

    bool compose(const std::vector<std::string> &readings,
                 const std::map<std::size_t, std::string> &overrides,
                 SmartComposition &result) const;
    std::vector<std::string> candidates(
        const std::vector<std::string> &readings, std::size_t index,
        const SmartComposition &composition) const;
    bool learnCandidate(const std::vector<std::string> &readings,
                        std::size_t index, const std::string &chosen,
                        const SmartComposition &composition) const;

private:
    struct Unigram {
        std::string text;
        double probability = 0;
        double backoff = 0;
    };
    SmartMandarinStore(sqlite3 *database,
                       std::shared_ptr<SmartMandarinUserData> userData)
        : database_(database), userData_(std::move(userData)) {}
    std::vector<Unigram> unigrams(const std::string &query) const;
    bool bigram(const std::string &previousQuery, const std::string &query,
                const std::string &previous, const std::string &current,
                double &probability) const;

    sqlite3 *database_;
    std::shared_ptr<SmartMandarinUserData> userData_;
    mutable std::map<std::string, std::vector<Unigram>> unigramCache_;
    mutable std::map<std::string,
                     std::map<std::pair<std::string, std::string>, double>>
        bigramCache_;
};

} // namespace keykey::linux_ime
