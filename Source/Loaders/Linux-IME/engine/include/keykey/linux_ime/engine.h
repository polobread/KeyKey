#pragma once

#include "keykey/linux_ime/associated_phrase_dictionary.h"
#include "keykey/linux_ime/bopomofo_reading.h"
#include "keykey/linux_ime/cin_dictionary.h"

#include <cstddef>
#include <memory>
#include <string>
#include <vector>

namespace keykey::linux_ime {

std::string toFullWidth(const std::string &text);
std::string toSimplifiedChinese(const std::string &text,
                                const CinDictionary &dictionary);

enum class KeyCode {
    Character,
    Space,
    Enter,
    Backspace,
    Escape,
    Left,
    Right,
    Up,
    Down,
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
};

struct EngineResult {
    bool handled = false;
    bool updateUi = false;
    std::string preedit;
    std::size_t preeditCursorBytes = 0;
    std::vector<std::string> candidates;
    std::size_t candidatePage = 0;
    std::size_t candidatePageCount = 0;
    std::size_t highlightedIndex = 0;
    bool fullWidthMode = false;
    bool traditionalToSimplifiedMode = false;
    bool associatedPhrases = false;
    std::string commit;
};

enum class InputMethod { Bopomofo, Cangjie, Simplex };

class InputContextState {
public:
    void reset() noexcept;

private:
    friend class Engine;
    BopomofoReading reading_;
    std::string tableCode_;
    std::string candidatePreedit_;
    std::vector<std::string> candidates_;
    std::size_t page_ = 0;
    std::size_t highlightedIndex_ = 0;
    bool fullWidthMode_ = false;
    bool traditionalToSimplifiedMode_ = false;
    bool showingAssociatedPhrases_ = false;
};

class Engine {
public:
    static constexpr std::size_t CandidatesPerPage = 9;

    explicit Engine(std::shared_ptr<const CinDictionary> dictionary,
                    InputMethod inputMethod = InputMethod::Bopomofo,
                    BopomofoLayout bopomofoLayout =
                        BopomofoLayout::Standard,
                    std::shared_ptr<const CinDictionary> punctuationDictionary =
                        nullptr,
                    std::shared_ptr<const CinDictionary>
                        traditionalToSimplifiedDictionary = nullptr,
                    std::shared_ptr<const AssociatedPhraseDictionary>
                        associatedPhraseDictionary = nullptr);

    EngineResult processKey(InputContextState &context,
                            const KeyEvent &event) const;
    void setTraditionalToSimplifiedMode(InputContextState &context,
                                        bool enabled) const noexcept;
    void setAssociatedPhraseCollections(
        std::vector<std::string> enabledCollections);
    EngineResult selectDisplayedCandidate(InputContextState &context,
                                          std::size_t displayedIndex) const;
    EngineResult snapshot(const InputContextState &context) const;

private:
    EngineResult query(InputContextState &context) const;
    EngineResult queryPunctuation(InputContextState &context,
                                  const std::string &key) const;
    EngineResult selectAbsoluteCandidate(InputContextState &context,
                                         std::size_t index) const;
    void clearCandidates(InputContextState &context) const noexcept;
    bool acceptsCharacter(char character) const noexcept;
    bool compositionEmpty(const InputContextState &context) const noexcept;
    bool combine(InputContextState &context, char character) const;
    void backspace(InputContextState &context) const;
    void changeCandidatePage(InputContextState &context, int delta) const;
    void moveCandidateHighlight(InputContextState &context, int delta) const;
    std::string queryKey(const InputContextState &context) const;
    std::string displayText(const InputContextState &context) const;
    std::string outputText(const InputContextState &context,
                           const std::string &text) const;
    std::size_t maximumCodeLength() const noexcept;
    std::string punctuationQueryKey(const KeyEvent &event) const;

    std::shared_ptr<const CinDictionary> dictionary_;
    std::shared_ptr<const CinDictionary> punctuationDictionary_;
    std::shared_ptr<const CinDictionary> traditionalToSimplifiedDictionary_;
    std::shared_ptr<const AssociatedPhraseDictionary>
        associatedPhraseDictionary_;
    std::vector<std::string> enabledAssociatedPhraseCollections_{
        "McBopomofo"};
    InputMethod inputMethod_;
    BopomofoLayout bopomofoLayout_;
};

} // namespace keykey::linux_ime
