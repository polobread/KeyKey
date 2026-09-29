#pragma once

#include <memory>
#include <string>
#include <utility>
#include <vector>

struct sqlite3;

namespace keykey::linux_ime {

struct UserUnigram {
    std::string text;
    double probability = 0;
    double backoff = 0;
};

class SmartMandarinUserData {
public:
    static std::string defaultPath();
    static std::shared_ptr<SmartMandarinUserData> open(const std::string &path);
    ~SmartMandarinUserData();
    SmartMandarinUserData(const SmartMandarinUserData &) = delete;
    SmartMandarinUserData &operator=(const SmartMandarinUserData &) = delete;

    std::vector<UserUnigram> unigrams(const std::string &query) const;
    std::string learnedCandidate(const std::string &query) const;
    bool learnedBigram(const std::string &previousQuery,
                       const std::string &query, const std::string &previous,
                       const std::string &current, double &score) const;
    bool learn(const std::string &query, const std::string &current,
               const std::string &previousQuery,
               const std::string &previous) const;
    bool addPhrase(const std::string &text, const std::string &reading) const;
    bool removePhrase(const std::string &text, const std::string &reading) const;
    std::vector<std::pair<std::string, std::string>> phrases() const;
    bool resetLearning() const;
    static std::string readingToQuery(const std::string &reading);
    static std::string queryToReading(const std::string &query);

private:
    explicit SmartMandarinUserData(sqlite3 *database) : database_(database) {}
    sqlite3 *database_;
};

} // namespace keykey::linux_ime
