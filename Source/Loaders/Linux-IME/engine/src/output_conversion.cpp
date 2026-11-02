#include "keykey/linux_ime/input_types.h"
#include <tuple>

namespace keykey::linux_ime {
namespace {
void appendUtf8(std::string &output, char32_t codePoint) {
    if (codePoint <= 0x7FU) {
        output.push_back(static_cast<char>(codePoint));
    } else if (codePoint <= 0x7FFU) {
        output.push_back(static_cast<char>(0xC0U | (codePoint >> 6U)));
        output.push_back(static_cast<char>(0x80U | (codePoint & 0x3FU)));
    } else {
        output.push_back(static_cast<char>(0xE0U | (codePoint >> 12U)));
        output.push_back(
            static_cast<char>(0x80U | ((codePoint >> 6U) & 0x3FU)));
        output.push_back(static_cast<char>(0x80U | (codePoint & 0x3FU)));
    }
}

std::size_t utf8SequenceLength(unsigned char lead) noexcept {
    if (lead < 0x80U) {
        return 1;
    }
    if ((lead & 0xE0U) == 0xC0U) {
        return 2;
    }
    if ((lead & 0xF0U) == 0xE0U) {
        return 3;
    }
    if ((lead & 0xF8U) == 0xF0U) {
        return 4;
    }
    return 0;
}

bool isValidUtf8Sequence(const std::string &text, std::size_t offset,
                         std::size_t length) noexcept {
    if (length == 0 || offset + length > text.size()) {
        return false;
    }
    for (std::size_t index = 1; index < length; ++index) {
        const auto continuation =
            static_cast<unsigned char>(text[offset + index]);
        if ((continuation & 0xC0U) != 0x80U) {
            return false;
        }
    }
    return true;
}

}

std::string toFullWidth(const std::string &text) {
    std::string result;
    result.reserve(text.size());
    for (const char rawCharacter : text) {
        const auto character = static_cast<unsigned char>(rawCharacter);
        if (character == 0x20U) {
            appendUtf8(result, 0x3000U);
        } else if (character >= 0x21U && character <= 0x7EU) {
            appendUtf8(result, 0xFF01U + character - 0x21U);
        } else {
            result.push_back(static_cast<char>(character));
        }
    }
    return result;
}

std::string toSimplifiedChinese(const std::string &text,
                                const CinDictionary &dictionary) {
    std::string result;
    result.reserve(text.size());
    for (std::size_t offset = 0; offset < text.size();) {
        const auto lead = static_cast<unsigned char>(text[offset]);
        const std::size_t length = utf8SequenceLength(lead);
        if (!isValidUtf8Sequence(text, offset, length)) {
            result.push_back(text[offset]);
            ++offset;
            continue;
        }

        const std::string character = text.substr(offset, length);
        const std::vector<std::string> &mapped =
            dictionary.candidates(character);
        result += mapped.empty() ? character : mapped.front();
        offset += length;
    }
    return result;
}


bool SmartMandarinPreferences::operator==(const SmartMandarinPreferences &o) const noexcept {
    return std::tie(showCandidateListWithSpace, candidateCursorAtEndOfTargetBlock,
                    clearComposingTextWithEsc, maxCompletedSyllables,
                    candidateSelectionKeys, selectionReturnsToEnd, shiftAlwaysUppercase,
                    useBigrams, learnCandidateOverrides, learnBigrams) ==
           std::tie(o.showCandidateListWithSpace, o.candidateCursorAtEndOfTargetBlock,
                    o.clearComposingTextWithEsc, o.maxCompletedSyllables,
                    o.candidateSelectionKeys, o.selectionReturnsToEnd, o.shiftAlwaysUppercase,
                    o.useBigrams, o.learnCandidateOverrides, o.learnBigrams);
}
TablePreferences TablePreferences::simplex() {
    TablePreferences result;
    result.clearOnError = false;
    result.queryAtMaximum = true;
    result.maximumRadicalLength = 2;
    result.spaceCommitsFirstOnSinglePage = false;
    result.wildcardOne.clear();
    result.wildcardMany.clear();
    return result;
}
bool TablePreferences::operator==(const TablePreferences &o) const noexcept {
    return std::tie(composeWhileTyping, prefixCandidates, clearOnError, queryAtMaximum,
                    learnSelection, candidateSelectionKeys, punctuation, maximumRadicalLength,
                    spaceAsFirstSelectionKey, spaceCommitsFirstOnSinglePage,
                    wildcardOne, wildcardMany) ==
           std::tie(o.composeWhileTyping, o.prefixCandidates, o.clearOnError, o.queryAtMaximum,
                    o.learnSelection, o.candidateSelectionKeys, o.punctuation, o.maximumRadicalLength,
                    o.spaceAsFirstSelectionKey, o.spaceCommitsFirstOnSinglePage,
                    o.wildcardOne, o.wildcardMany);
}
} // namespace keykey::linux_ime
