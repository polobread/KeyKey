// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
// Headless smoke for the Unix reading codec's behavior options and C ABI wiring.
#include "keykey/linux_ime/phrase_reading.h"

#include <iostream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace {
unsigned checks = 0;
void require(bool condition, const char *message) {
    ++checks;
    if (!condition) throw std::runtime_error(message);
}
} // namespace

int main() {
    using keykey::linux_ime::queryToReading;
    using keykey::linux_ime::readingToQuery;
    try {
        require(readingToQuery("ㄋㄧˇ ㄏㄠˇ") == "\\O:W", "encode spaced readings");
        require(queryToReading("\\O:W") == "ㄋㄧˇ ㄏㄠˇ", "decode escaped query bytes");
        require(readingToQuery(" \tㄋㄧˇ\r\nㄏㄠˇ\v\f ") == "\\O:W", "classic ASCII whitespace");
        require(readingToQuery("ㄧㄋˇ") == "\\O", "component order remains permissive");
        require(readingToQuery("").empty(), "empty reading");
        require(queryToReading("").empty(), "empty query");
        require(queryToReading("00\\O") == "ㄋㄧˇ", "omit only leading empty syllables");
        require(queryToReading("\\O00:W") == "ㄋㄧˇ  ㄏㄠˇ", "retain interior empty syllables");
        require(queryToReading("\\O00") == "ㄋㄧˇ ", "retain trailing empty syllables");
        for (const auto &reading : std::vector<std::string>{
                "ㄅㄆ", "ㄧㄨ", "ㄚㄛ", "ㄋㄧˇˊ", "ˇ", "ㄋㄧˇ,ㄏㄠˇ",
                "ㄋㄧˇ　ㄏㄠˇ", "ㄋㄧˇ\xc2\xa0ㄏㄠˇ", "unknown", "🐱", std::string("ㄋ\0ㄧ", 7)}) {
            require(readingToQuery(reading).empty(), "invalid reading must not yield a partial query");
        }
        for (const auto &query : std::vector<std::string>{
                "0", "\\O0", "~~", "/0", std::string("\x7f" "0", 2),
                std::string("\xff" "0", 2), std::string("\0" "0", 2)}) {
            require(queryToReading(query).empty(), "invalid query must not yield a partial reading");
        }
        std::cout << "Unix reading codec bridge: " << checks << " checks passed\n";
        return 0;
    } catch (const std::exception &error) {
        std::cerr << "Unix reading codec bridge failed: " << error.what() << '\n';
        return 1;
    }
}
