// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
#pragma once
#include "keykey/linux_ime/cin_dictionary.h"
#include <cstddef>
#include <string>
#include <vector>

namespace keykey::linux_ime {

enum class BopomofoLayout { Standard, ETen, ETen26, Hsu, HanyuPinyin };
std::string toFullWidth(const std::string &text);
std::string toSimplifiedChinese(const std::string &text, const CinDictionary &dictionary);

enum class KeyCode {
    Character,
    Space,
    Enter,
    Backspace,
    Delete,
    Tab,
    Escape,
    Left,
    Right,
    Up,
    Down,
    Home,
    End,
    PageUp,
    PageDown,
};

enum class KeyModifier : unsigned int {
    None = 0,
    Shift = 1U << 0U,
    Control = 1U << 1U,
    Alt = 1U << 2U,
    Super = 1U << 3U,
};

constexpr KeyModifier operator|(KeyModifier left, KeyModifier right) noexcept {
    return static_cast<KeyModifier>(static_cast<unsigned int>(left) |
                                    static_cast<unsigned int>(right));
}

struct KeyEvent {
    KeyCode code = KeyCode::Character;
    char character = '\0';
    KeyModifier modifiers = KeyModifier::None;
    bool release = false;
    bool repeat = false;
    bool capsLock = false;
    // Native text and physical flags are forwarded to the shared Rust core.
    std::string text{};
    bool rawShift = false;
    bool keypad = false;
    bool numLock = false;
};

struct EngineResult {
    bool handled = false;
    bool updateUi = false;
    bool beep = false;
    std::string preedit;
    std::size_t preeditCursorBytes = 0;
    std::vector<std::string> candidates;
    std::size_t candidatePage = 0;
    std::size_t candidatePageCount = 0;
    std::size_t highlightedIndex = 0;
    std::string candidateSelectionKeys;
    std::size_t candidatePageSize = 9;
    bool fullWidthMode = false;
    bool traditionalToSimplifiedMode = false;
    bool associatedPhrases = false;
    std::string commit;
    bool deleteBackward = false;
    bool sendReturn = false;
    bool discardComposition = false;
    std::string phraseFeedback;
    bool phraseAdded = false;
    bool hasMarkedPhrase = false;
    std::size_t markedPreeditStartBytes = 0;
    std::size_t markedPreeditLengthBytes = 0;
};

enum class InputMethod { Bopomofo, Cangjie, Simplex };

struct SmartMandarinPreferences {
    bool showCandidateListWithSpace = false;
    bool candidateCursorAtEndOfTargetBlock = false;
    bool clearComposingTextWithEsc = false;
    std::size_t maxCompletedSyllables = 10;
    std::string candidateSelectionKeys = "123456789";
    bool selectionReturnsToEnd = false;
    bool shiftAlwaysUppercase = false;
    bool useBigrams = true;
    bool learnCandidateOverrides = true;
    bool learnBigrams = true;

    bool operator==(const SmartMandarinPreferences &other) const noexcept;
};

struct TablePreferences {
    bool composeWhileTyping = false;
    bool prefixCandidates = false;
    bool clearOnError = true;
    bool queryAtMaximum = false;
    bool learnSelection = false;
    std::string candidateSelectionKeys = "123456789";
    std::string punctuation = "original";
    std::size_t maximumRadicalLength = 5;
    bool spaceAsFirstSelectionKey = false;
    bool spaceCommitsFirstOnSinglePage = true;
    std::string wildcardOne = "?";
    std::string wildcardMany = "*";

    static TablePreferences simplex();
    bool operator==(const TablePreferences &other) const noexcept;
};

} // namespace keykey::linux_ime
