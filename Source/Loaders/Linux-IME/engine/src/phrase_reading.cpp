// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
#include "keykey/linux_ime/phrase_reading.h"
#include <array>
#include <sstream>
namespace keykey::linux_ime {
namespace {
const std::array<const char *, 21> initials = {
    "ㄅ", "ㄆ", "ㄇ", "ㄈ", "ㄉ", "ㄊ", "ㄋ", "ㄌ", "ㄍ", "ㄎ", "ㄏ",
    "ㄐ", "ㄑ", "ㄒ", "ㄓ", "ㄔ", "ㄕ", "ㄖ", "ㄗ", "ㄘ", "ㄙ"};
const std::array<const char *, 3> medials = {"ㄧ", "ㄨ", "ㄩ"};
const std::array<const char *, 13> finals = {
    "ㄚ", "ㄛ", "ㄜ", "ㄝ", "ㄞ", "ㄟ", "ㄠ", "ㄡ", "ㄢ", "ㄣ", "ㄤ", "ㄥ", "ㄦ"};
const std::array<const char *, 4> tones = {"ˊ", "ˇ", "ˋ", "˙"};

}
std::string readingToQuery(
    const std::string &reading) {
    std::istringstream stream(reading);
    std::string syllable;
    std::string result;
    while (stream >> syllable) {
        unsigned int initial = 0, medial = 0, final = 0, tone = 0;
        for (std::size_t offset = 0; offset < syllable.size();) {
            bool found = false;
            const auto match = [&](const auto &symbols, unsigned int &slot) {
                for (std::size_t index = 0; index < symbols.size(); ++index) {
                    const std::string symbol = symbols[index];
                    if (syllable.compare(offset, symbol.size(), symbol) == 0) {
                        if (slot != 0) return false;
                        slot = static_cast<unsigned int>(index + 1);
                        offset += symbol.size();
                        return true;
                    }
                }
                return false;
            };
            found = match(initials, initial) || match(medials, medial) ||
                    match(finals, final) || match(tones, tone);
            if (!found) return {};
        }
        if (initial == 0 && medial == 0 && final == 0) return {};
        const unsigned int order = initial + medial * 22U + final * 88U +
                                   tone * 1232U;
        result.push_back(static_cast<char>(48U + order % 79U));
        result.push_back(static_cast<char>(48U + order / 79U));
    }
    return result;
}

std::string queryToReading(
    const std::string &query) {
    if (query.size() % 2 != 0) return {};
    std::string result;
    for (std::size_t offset = 0; offset < query.size(); offset += 2) {
        const auto low = static_cast<unsigned char>(query[offset]);
        const auto high = static_cast<unsigned char>(query[offset + 1]);
        if (low < 48 || low > 126 || high < 48 || high > 126) return {};
        const int order = (low - 48) + (high - 48) * 79;
        if (order < 0 || order >= 6160) return {};
        const int initial = order % 22;
        const int medial = (order / 22) % 4;
        const int final = (order / 88) % 14;
        const int tone = order / 1232;
        if (tone > 4) return {};
        if (!result.empty()) result += " ";
        if (initial) result += initials[static_cast<std::size_t>(initial - 1)];
        if (medial) result += medials[static_cast<std::size_t>(medial - 1)];
        if (final) result += finals[static_cast<std::size_t>(final - 1)];
        if (tone) result += tones[static_cast<std::size_t>(tone - 1)];
    }
    return result;
}

}
