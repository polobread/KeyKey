#include "keykey/linux_ime/smart_mandarin_store.h"
#include "keykey/linux_ime/candidate_encoding.h"

#include <sqlite3.h>

#include <algorithm>
#include <limits>
#include <map>
#include <set>
#include <utility>

namespace keykey::linux_ime {
namespace {

struct Statement {
    sqlite3_stmt *value = nullptr;
    ~Statement() { sqlite3_finalize(value); }
};

std::string columnText(sqlite3_stmt *statement, int column) {
    const auto *value = sqlite3_column_text(statement, column);
    return value ? reinterpret_cast<const char *>(value) : "";
}

struct Path {
    double score = 0;
    double backoff = 0;
    std::vector<SmartSegment> segments;
};

std::string codepointAt(const std::string &text, std::size_t index) {
    std::size_t start = 0;
    for (std::size_t current = 0; current < index && start < text.size();
         ++current) {
        ++start;
        while (start < text.size() &&
               (static_cast<unsigned char>(text[start]) & 0xC0U) == 0x80U) {
            ++start;
        }
    }
    if (start >= text.size()) return {};
    std::size_t end = start + 1;
    while (end < text.size() &&
           (static_cast<unsigned char>(text[end]) & 0xC0U) == 0x80U) {
        ++end;
    }
    return text.substr(start, end - start);
}

} // namespace

std::shared_ptr<const SmartMandarinStore>
SmartMandarinStore::open(
    const std::string &path,
    std::shared_ptr<SmartMandarinUserData> userData) {
    sqlite3 *database = nullptr;
    if (sqlite3_open_v2(path.c_str(), &database, SQLITE_OPEN_READONLY, nullptr) !=
        SQLITE_OK) {
        sqlite3_close(database);
        return nullptr;
    }
    {
        Statement check;
        if (sqlite3_prepare_v2(database, "SELECT qstring FROM unigrams LIMIT 1",
                               -1, &check.value, nullptr) != SQLITE_OK) {
            sqlite3_close(database);
            return nullptr;
        }
    }
    return std::shared_ptr<const SmartMandarinStore>(
        new SmartMandarinStore(database, std::move(userData)));
}

SmartMandarinStore::~SmartMandarinStore() { sqlite3_close(database_); }

std::vector<SmartMandarinStore::Unigram>
SmartMandarinStore::unigrams(const std::string &query) const {
    const auto cached = unigramCache_.find(query);
    if (cached != unigramCache_.end()) {
        std::vector<Unigram> result = cached->second;
        if (userData_) {
            for (const UserUnigram &entry : userData_->unigrams(query)) {
                result.push_back({entry.text, entry.probability, entry.backoff});
            }
        }
        return result;
    }
    Statement statement;
    if (sqlite3_prepare_v2(database_,
                           "SELECT current, probability, backoff FROM unigrams "
                           "WHERE qstring = ? ORDER BY probability DESC",
                           -1, &statement.value, nullptr) != SQLITE_OK) {
        return {};
    }
    sqlite3_bind_text(statement.value, 1, query.c_str(), -1, SQLITE_TRANSIENT);
    std::vector<Unigram> result;
    while (sqlite3_step(statement.value) == SQLITE_ROW) {
        result.push_back({columnText(statement.value, 0),
                          sqlite3_column_double(statement.value, 1),
                          sqlite3_column_double(statement.value, 2)});
    }
    if (unigramCache_.size() >= 1024) {
        unigramCache_.clear();
    }
    unigramCache_.emplace(query, result);
    if (userData_) {
        for (const UserUnigram &entry : userData_->unigrams(query)) {
            result.push_back({entry.text, entry.probability, entry.backoff});
        }
    }
    return result;
}

bool SmartMandarinStore::bigram(const std::string &previousQuery,
                                const std::string &query,
                                const std::string &previous,
                                const std::string &current,
                                double &probability) const {
    if (userData_ && userData_->learnedBigram(previousQuery, query, previous,
                                              current, probability)) {
        return true;
    }
    const std::string key = previousQuery + " " + query;
    auto cached = bigramCache_.find(key);
    if (cached == bigramCache_.end()) {
        Statement statement;
        if (sqlite3_prepare_v2(database_,
                               "SELECT previous, current, probability FROM "
                               "bigrams WHERE qstring = ?",
                               -1, &statement.value, nullptr) != SQLITE_OK) {
            return false;
        }
        sqlite3_bind_text(statement.value, 1, key.c_str(), -1,
                          SQLITE_TRANSIENT);
        std::map<std::pair<std::string, std::string>, double> rows;
        while (sqlite3_step(statement.value) == SQLITE_ROW) {
            rows[{columnText(statement.value, 0),
                  columnText(statement.value, 1)}] =
                sqlite3_column_double(statement.value, 2);
        }
        if (bigramCache_.size() >= 1024) {
            bigramCache_.clear();
        }
        cached = bigramCache_.emplace(key, std::move(rows)).first;
    }
    const auto row = cached->second.find({previous, current});
    if (row == cached->second.end()) {
        return false;
    }
    probability = row->second;
    return true;
}

bool SmartMandarinStore::compose(
    const std::vector<std::string> &readings,
    const std::map<std::size_t, SmartSelection> &overrides,
    SmartComposition &result, bool restrictToBig5) const {
    result = {};
    if (readings.empty()) {
        return true;
    }
    std::vector<std::map<std::string, Path>> paths(readings.size() + 1);
    paths[0].emplace("", Path{});
    for (std::size_t start = 0; start < readings.size(); ++start) {
        if (paths[start].empty()) {
            continue;
        }
        std::string query;
        for (std::size_t length = 1;
             length <= 8 && start + length <= readings.size(); ++length) {
            query += readings[start + length - 1];
            const std::string learned =
                userData_ ? userData_->learnedCandidate(query) : std::string{};
            const auto overlapping = std::find_if(
                overrides.begin(), overrides.end(),
                [start, length](const auto &selection) {
                    return selection.first < start + length &&
                           start < selection.first + selection.second.length &&
                           !(selection.first == start &&
                             selection.second.length == length);
                });
            if (overlapping != overrides.end()) {
                continue;
            }
            for (const Unigram &entry : unigrams(query)) {
                if (restrictToBig5 && !isBig5HkscsRepresentable(entry.text)) {
                    continue;
                }
                const auto required = overrides.find(start);
                if (required != overrides.end() &&
                    required->second.text != entry.text) {
                    continue;
                }
                for (const auto &state : paths[start]) {
                    const Path &previousPath = state.second;
                    double transition;
                    const bool hasPrevious = !previousPath.segments.empty();
                    const SmartSegment *previous = hasPrevious
                                                       ? &previousPath.segments.back()
                                                       : nullptr;
                    const double fallback = hasPrevious
                                                ? previousPath.backoff + entry.probability
                                                : entry.probability;
                    if (bigram(hasPrevious ? previous->query : "!", query,
                               hasPrevious ? previous->text : "", entry.text,
                               transition)) {
                        transition = std::max(transition, fallback);
                    } else {
                        transition = fallback;
                    }
                    Path path = previousPath;
                    path.score += transition +
                                  (entry.text == learned ? 5.0 : 0.0);
                    path.backoff = entry.backoff;
                    path.segments.push_back(
                        {start, length, query, entry.text});
                    const std::string key = query + '\x1f' + entry.text;
                    auto &end = paths[start + length];
                    const auto existing = end.find(key);
                    if (existing == end.end() || path.score > existing->second.score) {
                        end[key] = std::move(path);
                    }
                }
            }
        }
    }
    double bestScore = -std::numeric_limits<double>::infinity();
    const Path *best = nullptr;
    for (const auto &state : paths.back()) {
        const Path &path = state.second;
        // Match the desktop walker's first choice for an isolated syllable.
        // The end marker must not rerank the visible candidate.
        if (readings.size() == 1) {
            if (path.score > bestScore) {
                bestScore = path.score;
                best = &path;
            }
            continue;
        }
        const SmartSegment &last = path.segments.back();
        double ending = path.backoff;
        double observed = 0;
        if (bigram(last.query, "$", last.text, "", observed)) {
            ending = std::max(observed, ending);
        }
        if (path.score + ending > bestScore) {
            bestScore = path.score + ending;
            best = &path;
        }
    }
    if (!best) {
        return false;
    }
    result.segments = best->segments;
    for (const auto &segment : result.segments) {
        result.text += segment.text;
    }
    return true;
}

std::vector<SmartCandidate> SmartMandarinStore::candidateOptions(
    const std::vector<std::string> &readings, std::size_t index,
    const SmartComposition &composition, bool restrictToBig5) const {
    if (index >= readings.size()) {
        return {};
    }
    const SmartSegment *previous = nullptr;
    for (const auto &segment : composition.segments) {
        if (segment.start + segment.length == index) {
            previous = &segment;
        }
    }
    std::vector<std::pair<SmartCandidate, double>> ranked;
    double previousBackoff = 0;
    if (previous) {
        for (const Unigram &entry : unigrams(previous->query)) {
            if (entry.text == previous->text) {
                previousBackoff = entry.backoff;
                break;
            }
        }
    }
    std::string query;
    for (std::size_t length = 1;
         length <= 8 && index + length <= readings.size(); ++length) {
        query += readings[index + length - 1];
        const std::string learned =
            userData_ ? userData_->learnedCandidate(query) : std::string{};
        for (const Unigram &entry : unigrams(query)) {
            if (restrictToBig5 && !isBig5HkscsRepresentable(entry.text)) {
                continue;
            }
            const double fallback = previousBackoff + entry.probability;
            double score = fallback;
            double observed = 0;
            if (bigram(previous ? previous->query : "!", query,
                       previous ? previous->text : "", entry.text, observed)) {
                score = std::max(observed, fallback);
            }
            ranked.push_back({{length, entry.text},
                              score + (entry.text == learned ? 5.0 : 0.0)});
        }
    }
    std::stable_sort(ranked.begin(), ranked.end(),
                     [](const auto &left, const auto &right) {
                         return left.second > right.second;
                     });
    std::set<std::pair<std::size_t, std::string>> seen;
    std::vector<SmartCandidate> result;
    for (const auto &entry : ranked) {
        if (seen.insert({entry.first.length, entry.first.text}).second) {
            result.push_back(entry.first);
        }
    }
    return result;
}

std::vector<std::string> SmartMandarinStore::candidates(
    const std::vector<std::string> &readings, std::size_t index,
    const SmartComposition &composition) const {
    std::vector<std::string> result;
    for (const SmartCandidate &candidate :
         candidateOptions(readings, index, composition)) {
        result.push_back(candidate.text);
    }
    return result;
}

bool SmartMandarinStore::learnCandidate(
    const std::vector<std::string> &readings, std::size_t index,
    const SmartCandidate &chosen, const SmartComposition &composition) const {
    if (!userData_ || chosen.length == 0 ||
        index + chosen.length > readings.size()) {
        return false;
    }
    const SmartSegment *previous = nullptr;
    for (const auto &segment : composition.segments) {
        if (segment.start + segment.length == index) {
            previous = &segment;
        }
    }
    std::string previousQuery = previous ? previous->query : std::string{};
    std::string previousText = previous ? previous->text : std::string{};
    if (!previous && index > 0) {
        for (const auto &segment : composition.segments) {
            if (segment.start <= index - 1 &&
                segment.start + segment.length > index - 1) {
                previousQuery = readings[index - 1];
                previousText = codepointAt(segment.text,
                                           index - 1 - segment.start);
                break;
            }
        }
    }
    std::string query;
    for (std::size_t offset = 0; offset < chosen.length; ++offset) {
        query += readings[index + offset];
    }
    return userData_->learn(query, chosen.text, previousQuery,
                            previousText);
}

std::size_t SmartMandarinStore::evictionLength(
    const std::vector<std::string> &readings,
    const SmartComposition &composition) const {
    if (composition.segments.empty()) {
        return 0;
    }
    const std::size_t firstLength = composition.segments.front().length;
    if (firstLength != 1) {
        return firstLength;
    }
    // Learning a single character can split a visible dictionary word into
    // one-character nodes. Keep that word together when the buffer shifts.
    std::size_t length = 0;
    std::string text;
    std::string query;
    for (const SmartSegment &segment : composition.segments) {
        if (segment.start != length || length + segment.length > readings.size()) {
            break;
        }
        for (std::size_t offset = 0; offset < segment.length; ++offset) {
            query += readings[length + offset];
        }
        length += segment.length;
        text += segment.text;
        if (length < 2) {
            continue;
        }
        if (length > 8) {
            break;
        }
        for (const Unigram &entry : unigrams(query)) {
            if (entry.text == text) {
                return length;
            }
        }
    }
    return firstLength;
}

} // namespace keykey::linux_ime
