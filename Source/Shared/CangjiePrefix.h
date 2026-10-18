// Shared bounded Cangjie prefix selection. Source glyphs are kept for display.
#ifndef KEYKEY_CANGJIE_PREFIX_H
#define KEYKEY_CANGJIE_PREFIX_H
#include "CangjieRankingData.h"
#include "CangjieUnicodeData.h"
#include <algorithm>
#include <climits>
#include <map>
#include <set>
#include <string>
#include <vector>

namespace KeyKeyCangjie {
inline bool isCode(const std::string& code) {
    if (code.empty() || code.size() > 5) return false;
    for (size_t i = 0; i < code.size(); ++i)
        if (code[i] < 'a' || code[i] > 'z') return false;
    return true;
}
inline unsigned scalar(const std::string& text, size_t& offset) {
    if (offset >= text.size()) return 0;
    unsigned c = static_cast<unsigned char>(text[offset++]);
    if (c < 128) return c;
    unsigned count = c < 0xE0 ? 1 : c < 0xF0 ? 2 : 3;
    c &= count == 1 ? 0x1F : count == 2 ? 0x0F : 0x07;
    while (count-- && offset < text.size())
        c = (c << 6) | (static_cast<unsigned char>(text[offset++]) & 0x3F);
    return c;
}
inline std::string utf8(unsigned c) {
    std::string text;
    if (c < 0x80) text += static_cast<char>(c);
    else {
        if (c >= 0x10000) text += static_cast<char>(0xF0 | (c >> 18));
        if (c >= 0x800) text += static_cast<char>((c >= 0x10000 ? 0x80 : 0xE0) | ((c >> 12) & 0x3F));
        text += static_cast<char>((c >= 0x800 ? 0x80 : 0xC0) | ((c >> 6) & 0x3F));
        text += static_cast<char>(0x80 | (c & 0x3F));
    }
    return text;
}
inline std::string identity(const std::string& text) {
    size_t offset = 0;
    const unsigned cp = scalar(text, offset);
    if (offset != text.size() || !((cp >= 0xF900 && cp < 0xFB00) ||
                                   (cp >= 0x2F800 && cp < 0x2FA20))) return text;
    for (size_t i = 0; i < sizeof(CanonicalCjk) / sizeof(*CanonicalCjk); ++i)
        if (CanonicalCjk[i].first == cp) return utf8(CanonicalCjk[i].second);
    return text;
}
inline bool excluded(const std::string& text) {
    if (text.empty()) return true;
    size_t offset = 0;
    const unsigned cp = scalar(text, offset);
    for (size_t i = 0; i < sizeof(ExcludedRanges) / sizeof(*ExcludedRanges); ++i) {
        if (cp < ExcludedRanges[i].first) return false;
        if (cp <= ExcludedRanges[i].second) return true;
    }
    return false;
}
inline std::map<std::string, int> makeRanks() {
    std::map<std::string, int> result;
    {
        const std::string characters(RankedCharacters);
        size_t offset = 0;
        int rank = 1;
        while (offset < characters.size()) {
            const size_t begin = offset;
            scalar(characters, offset);
            result[characters.substr(begin, offset - begin)] = rank++;
        }
    }
    return result;
}
inline const std::map<std::string, int>& ranks() {
    static const std::map<std::string, int> result = makeRanks();
    return result;
}
inline int rank(const std::string& text) {
    const std::map<std::string, int>& table = ranks();
    std::map<std::string, int>::const_iterator found = table.find(identity(text));
    return found == table.end() ? INT_MAX : found->second;
}
inline std::vector<std::string> unique(const std::vector<std::string>& values) {
    std::vector<std::string> result;
    std::set<std::string> seen;
    for (size_t i = 0; i < values.size(); ++i)
        if (seen.insert(identity(values[i])).second) result.push_back(values[i]);
    return result;
}
class Selection {
    struct Item {
        std::string text;
        int rank;
        Item(const std::string& t, int r) : text(t), rank(r) {}
    };
    std::set<std::string> seen_;
    std::vector<Item> best_;
public:
    enum { Limit = 36 };
    explicit Selection(const std::vector<std::string>& exact) {
        for (size_t i = 0; i < exact.size(); ++i) seen_.insert(identity(exact[i]));
    }
    template<class Filter> void consider(const std::string& value, const Filter& filter) {
        const std::string id = identity(value);
        if (excluded(value) || seen_.count(id)) return;
        const int frequency = rank(id);
        if (best_.size() == Limit && frequency >= best_.back().rank) return;
        if (!filter(value)) return;
        seen_.insert(id);
        size_t i = 0;
        while (i < best_.size() && best_[i].rank <= frequency) ++i;
        best_.insert(best_.begin() + i, Item(value, frequency));
        if (best_.size() > Limit) best_.pop_back();
    }
    std::vector<std::string> values() const {
        std::vector<std::string> result;
        for (size_t i = 0; i < best_.size(); ++i) result.push_back(best_[i].text);
        return result;
    }
};
}
#endif
