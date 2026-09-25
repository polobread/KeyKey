#include "keykey/linux_ime/engine.h"

#include "keykey/linux_ime/candidate_encoding.h"

#include <algorithm>
#include <cctype>
#include <stdexcept>
#include <utility>

namespace keykey::linux_ime {
namespace {

bool hasModifiers(KeyModifier modifiers) noexcept {
    return modifiers != KeyModifier::None;
}

bool isHostEditingKey(KeyCode code) noexcept {
    switch (code) {
    case KeyCode::Delete:
    case KeyCode::Tab:
    case KeyCode::Left:
    case KeyCode::Right:
    case KeyCode::Up:
    case KeyCode::Down:
    case KeyCode::Home:
    case KeyCode::End:
    case KeyCode::PageUp:
    case KeyCode::PageDown:
        return true;
    default:
        return false;
    }
}

bool isCandidateNavigationKey(KeyCode code) noexcept {
    switch (code) {
    case KeyCode::Left:
    case KeyCode::Right:
    case KeyCode::Up:
    case KeyCode::Down:
    case KeyCode::Home:
    case KeyCode::End:
    case KeyCode::PageUp:
    case KeyCode::PageDown:
        return true;
    default:
        return false;
    }
}

bool hasApplicationShortcutModifier(KeyModifier modifiers) noexcept {
    constexpr unsigned int shortcutModifiers =
        static_cast<unsigned int>(KeyModifier::Control) |
        static_cast<unsigned int>(KeyModifier::Alt) |
        static_cast<unsigned int>(KeyModifier::Super);
    return (static_cast<unsigned int>(modifiers) & shortcutModifiers) != 0U;
}

std::size_t associatedPhraseSelectionIndex(char character) noexcept {
    const std::string digits = "123456789";
    const std::string shiftedDigits = "!@#$%^&*(";
    std::size_t index = digits.find(character);
    if (index == std::string::npos) {
        index = shiftedDigits.find(character);
    }
    return index;
}

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

std::size_t utf8ByteOffset(const std::string &text,
                           std::size_t codePoints) noexcept {
    std::size_t offset = 0;
    while (codePoints-- > 0 && offset < text.size()) {
        const std::size_t length =
            utf8SequenceLength(static_cast<unsigned char>(text[offset]));
        offset += length == 0 ? 1 : length;
    }
    return std::min(offset, text.size());
}

} // namespace

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

void InputContextState::reset() noexcept {
    reading_.clear();
    tableCode_.clear();
    candidatePreedit_.clear();
    candidates_.clear();
    page_ = 0;
    highlightedIndex_ = 0;
    showingAssociatedPhrases_ = false;
    smartReadings_.clear();
    smartComposition_ = {};
    smartOverrides_.clear();
    smartCursor_ = 0;
    smartCandidateIndex_ = 0;
    showingSmartCandidates_ = false;
}

void Engine::setSmartMandarinStore(
    std::shared_ptr<const SmartMandarinStore> store) noexcept {
    smartMandarinStore_ = std::move(store);
}

void Engine::setSmartMandarinMode(bool enabled) noexcept {
    smartMandarinMode_ = enabled && smartMandarinStore_ != nullptr &&
                         inputMethod_ == InputMethod::Bopomofo;
}

Engine::Engine(std::shared_ptr<const CinDictionary> dictionary,
               InputMethod inputMethod, BopomofoLayout bopomofoLayout,
               std::shared_ptr<const CinDictionary> punctuationDictionary,
               std::shared_ptr<const CinDictionary>
                   traditionalToSimplifiedDictionary,
               std::shared_ptr<const AssociatedPhraseDictionary>
                   associatedPhraseDictionary)
    : dictionary_(std::move(dictionary)),
      punctuationDictionary_(std::move(punctuationDictionary)),
      traditionalToSimplifiedDictionary_(
          std::move(traditionalToSimplifiedDictionary)),
      associatedPhraseDictionary_(std::move(associatedPhraseDictionary)),
      inputMethod_(inputMethod),
      bopomofoLayout_(bopomofoLayout) {
    if (!dictionary_) {
        throw std::invalid_argument("Input method dictionary is required");
    }
}

void Engine::setTraditionalToSimplifiedMode(InputContextState &context,
                                            bool enabled) const noexcept {
    context.traditionalToSimplifiedMode_ = enabled;
}

void Engine::setAssociatedPhraseCollections(
    std::vector<std::string> enabledCollections) {
    enabledAssociatedPhraseCollections_ = std::move(enabledCollections);
}

void Engine::setRestrictBopomofoCandidatesToBig5(bool enabled) noexcept {
    restrictBopomofoCandidatesToBig5_ =
        inputMethod_ == InputMethod::Bopomofo && enabled;
}

EngineResult Engine::processKey(InputContextState &context,
                                const KeyEvent &event) const {
    bool updateUi = false;
    std::string pendingCommit;
    const auto includePendingCommit = [&](EngineResult result) {
        result.commit = pendingCommit + result.commit;
        return result;
    };
    const auto passThroughResult = [&]() {
        EngineResult result = snapshot(context);
        result.updateUi = updateUi;
        return result;
    };
    if (event.release) {
        return passThroughResult();
    }

    if (event.code == KeyCode::Space &&
        event.modifiers == KeyModifier::Shift) {
        if (!event.repeat) {
            context.fullWidthMode_ = !context.fullWidthMode_;
        }
        EngineResult result = snapshot(context);
        result.handled = true;
        return result;
    }

    if (smartMandarinMode_) {
        return processSmartKey(context, event);
    }

    if (context.showingAssociatedPhrases_) {
        const bool normalizedShiftedSelection =
            event.code == KeyCode::Character &&
            event.modifiers == KeyModifier::None &&
            std::string("!@#$%^&*(").find(event.character) !=
                std::string::npos;
        if (event.code == KeyCode::Character &&
            (event.modifiers == KeyModifier::Shift ||
             normalizedShiftedSelection)) {
            const std::size_t index =
                associatedPhraseSelectionIndex(event.character);
            if (index != std::string::npos) {
                const std::size_t absoluteIndex =
                    context.page_ * CandidatesPerPage + index;
                if (absoluteIndex < context.candidates_.size()) {
                    return selectAbsoluteCandidate(context, absoluteIndex);
                }
                clearCandidates(context);
                EngineResult result = snapshot(context);
                result.handled = true;
                return result;
            }
        }
        if (event.code == KeyCode::Enter || event.code == KeyCode::Escape) {
            clearCandidates(context);
            EngineResult result = snapshot(context);
            result.handled = true;
            return result;
        }
        if (event.code == KeyCode::Backspace) {
            clearCandidates(context);
            updateUi = true;
            return passThroughResult();
        }
        const bool navigatesCandidates =
            event.modifiers == KeyModifier::None &&
            (event.code == KeyCode::Space || event.code == KeyCode::Left ||
             event.code == KeyCode::Right || event.code == KeyCode::Up ||
             event.code == KeyCode::Down || event.code == KeyCode::Home ||
             event.code == KeyCode::End || event.code == KeyCode::PageUp ||
             event.code == KeyCode::PageDown);
        if (!navigatesCandidates) {
            clearCandidates(context);
            updateUi = true;
        }
    }

    const std::string punctuationKey = punctuationQueryKey(event);
    if (!punctuationKey.empty()) {
        if (!compositionEmpty(context)) {
            EngineResult result = snapshot(context);
            result.handled = true;
            return result;
        }
        return queryPunctuation(context, punctuationKey);
    }
    const bool shiftedTableSymbol =
        inputMethod_ != InputMethod::Bopomofo &&
        event.code == KeyCode::Character &&
        event.modifiers == KeyModifier::Shift &&
        std::isalpha(static_cast<unsigned char>(event.character)) == 0 &&
        acceptsCharacter(event.character);
    const bool blockHostEditingKey =
        inputMethod_ == InputMethod::Bopomofo &&
        isHostEditingKey(event.code) &&
        !hasApplicationShortcutModifier(event.modifiers) &&
        ((!compositionEmpty(context) && context.candidates_.empty()) ||
         (!context.candidates_.empty() &&
          (event.modifiers != KeyModifier::None ||
           !isCandidateNavigationKey(event.code))));
    if (blockHostEditingKey) {
        EngineResult result = snapshot(context);
        result.handled = true;
        result.beep = true;
        return result;
    }
    if (hasModifiers(event.modifiers) && !shiftedTableSymbol) {
        if (context.fullWidthMode_ &&
            event.modifiers == KeyModifier::Shift &&
            event.code == KeyCode::Character && compositionEmpty(context) &&
            context.candidates_.empty()) {
            EngineResult result = snapshot(context);
            result.handled = true;
            result.commit = outputText(context, std::string(1, event.character));
            return result;
        }
        return passThroughResult();
    }

    switch (event.code) {
    case KeyCode::Character: {
        if (!context.showingAssociatedPhrases_ &&
            !context.candidates_.empty() && event.character >= '1' &&
            event.character <= '9') {
            const auto displayedIndex =
                static_cast<std::size_t>(event.character - '1');
            return selectDisplayedCandidate(context, displayedIndex);
        }
        if (!context.candidates_.empty() && acceptsCharacter(event.character)) {
            const std::size_t absoluteIndex =
                context.page_ * CandidatesPerPage + context.highlightedIndex_;
            pendingCommit = outputText(
                context, context.candidates_.at(absoluteIndex));
            context.reset();
        }
        if (context.fullWidthMode_ && compositionEmpty(context) &&
            context.candidates_.empty() &&
            std::isupper(static_cast<unsigned char>(event.character)) != 0) {
            EngineResult result = snapshot(context);
            result.handled = true;
            result.commit = outputText(context, std::string(1, event.character));
            return includePendingCommit(std::move(result));
        }
        if (!acceptsCharacter(event.character)) {
            if (!compositionEmpty(context) || !context.candidates_.empty()) {
                EngineResult result = snapshot(context);
                result.handled = true;
                result.beep = true;
                return includePendingCommit(std::move(result));
            }
            if (context.fullWidthMode_ && compositionEmpty(context) &&
                context.candidates_.empty() && event.character >= 0x20 &&
                event.character <= 0x7E) {
                EngineResult result = snapshot(context);
                result.handled = true;
                result.commit =
                    outputText(context, std::string(1, event.character));
                return result;
            }
            return passThroughResult();
        }
        if (!combine(context, event.character)) {
            if (!pendingCommit.empty()) {
                EngineResult result = snapshot(context);
                result.handled = true;
                result.beep = true;
                return includePendingCommit(std::move(result));
            }
            if (!compositionEmpty(context) || !context.candidates_.empty()) {
                EngineResult result = snapshot(context);
                result.handled = true;
                result.beep = true;
                return result;
            }
            return passThroughResult();
        }
        clearCandidates(context);
        if (inputMethod_ == InputMethod::Bopomofo &&
            context.reading_.hasToneMarker()) {
            return includePendingCommit(query(context, true));
        }
        const bool cangjieWildcard =
            inputMethod_ == InputMethod::Cangjie &&
            context.tableCode_.size() > 1 &&
            (event.character == '?' || event.character == '*');
        if (inputMethod_ != InputMethod::Bopomofo &&
            isEndKey(event.character) && !cangjieWildcard) {
            return includePendingCommit(query(context, true));
        }
        if (inputMethod_ == InputMethod::Simplex &&
            context.tableCode_.size() == maximumCodeLength()) {
            return includePendingCommit(query(context, true));
        }
        break;
    }
    case KeyCode::Space:
        if (!context.candidates_.empty()) {
            changeCandidatePage(context, 1);
        } else if (!compositionEmpty(context)) {
            return query(context, inputMethod_ != InputMethod::Bopomofo);
        } else if (context.fullWidthMode_) {
            EngineResult result = snapshot(context);
            result.handled = true;
            result.commit = outputText(context, " ");
            return result;
        } else {
            return passThroughResult();
        }
        break;
    case KeyCode::Enter:
        if (!context.candidates_.empty()) {
            return selectDisplayedCandidate(context, context.highlightedIndex_);
        }
        if (!compositionEmpty(context)) {
            return query(context, inputMethod_ != InputMethod::Bopomofo);
        }
        return passThroughResult();
    case KeyCode::Backspace:
        if (compositionEmpty(context) && context.candidates_.empty()) {
            return passThroughResult();
        }
        clearCandidates(context);
        if (!compositionEmpty(context)) {
            backspace(context);
        }
        break;
    case KeyCode::Escape:
        if (compositionEmpty(context) && context.candidates_.empty()) {
            return passThroughResult();
        }
        context.reset();
        break;
    case KeyCode::Delete:
    case KeyCode::Tab:
        return passThroughResult();
    case KeyCode::Left:
    case KeyCode::PageUp:
        if (context.candidates_.empty()) {
            return passThroughResult();
        }
        changeCandidatePage(context, -1);
        break;
    case KeyCode::Right:
    case KeyCode::PageDown:
        if (context.candidates_.empty()) {
            return passThroughResult();
        }
        changeCandidatePage(context, 1);
        break;
    case KeyCode::Up:
        if (context.candidates_.empty()) {
            return passThroughResult();
        }
        moveCandidateHighlight(context, -1);
        break;
    case KeyCode::Down:
        if (context.candidates_.empty()) {
            return passThroughResult();
        }
        moveCandidateHighlight(context, 1);
        break;
    case KeyCode::Home:
        if (!context.candidates_.empty()) {
            context.page_ = 0;
            context.highlightedIndex_ = 0;
            break;
        }
        return passThroughResult();
    case KeyCode::End:
        if (!context.candidates_.empty()) {
            const std::size_t last = context.candidates_.size() - 1;
            context.page_ = last / CandidatesPerPage;
            context.highlightedIndex_ = last % CandidatesPerPage;
            break;
        }
        return passThroughResult();
    }

    EngineResult result = snapshot(context);
    result.handled = true;
    result.commit = std::move(pendingCommit);
    return result;
}

EngineResult Engine::selectDisplayedCandidate(InputContextState &context,
                                              std::size_t displayedIndex) const {
    if (smartMandarinMode_ && context.showingSmartCandidates_) {
        const std::size_t index =
            context.page_ * CandidatesPerPage + displayedIndex;
        if (index >= context.candidates_.size()) {
            EngineResult result = snapshot(context);
            result.handled = true;
            result.beep = true;
            return result;
        }
        const std::string chosen = context.candidates_[index];
        smartMandarinStore_->learnCandidate(
            context.smartReadings_, context.smartCandidateIndex_, chosen,
            context.smartComposition_);
        context.smartOverrides_[context.smartCandidateIndex_] = chosen;
        context.smartCursor_ = context.smartCandidateIndex_ + 1;
        rebuildSmartComposition(context);
        EngineResult result = snapshot(context);
        result.handled = true;
        return result;
    }
    const std::size_t absoluteIndex =
        context.page_ * CandidatesPerPage + displayedIndex;
    return selectAbsoluteCandidate(context, absoluteIndex);
}

EngineResult Engine::selectSmartCharacter(
    InputContextState &context, std::size_t preeditByteOffset) const {
    if (!smartMandarinMode_ || context.smartReadings_.empty() ||
        !context.reading_.empty(bopomofoLayout_)) {
        return snapshot(context);
    }
    const std::string &text = context.smartComposition_.text;
    std::size_t character = 0;
    for (std::size_t offset = 0;
         offset < std::min(preeditByteOffset, text.size()); ++character) {
        const std::size_t length = utf8SequenceLength(
            static_cast<unsigned char>(text[offset]));
        offset += length == 0 ? 1 : length;
    }
    context.smartCursor_ =
        std::min(character, context.smartReadings_.size() - 1);
    context.candidates_.clear();
    context.showingSmartCandidates_ = false;
    return processSmartKey(context, KeyEvent{KeyCode::Space});
}

void Engine::rebuildSmartComposition(InputContextState &context) const {
    context.smartComposition_ = {};
    if (!context.smartReadings_.empty()) {
        smartMandarinStore_->compose(context.smartReadings_,
                                    context.smartOverrides_,
                                    context.smartComposition_);
    }
    context.candidates_.clear();
    context.showingSmartCandidates_ = false;
    context.page_ = 0;
    context.highlightedIndex_ = 0;
}

bool Engine::finishSmartReading(InputContextState &context,
                               std::string &pendingCommit) const {
    if (context.reading_.empty(bopomofoLayout_)) {
        return false;
    }
    const std::string query = context.reading_.absoluteOrderKey();
    auto trial = context.smartReadings_;
    trial.insert(trial.begin() +
                     static_cast<std::ptrdiff_t>(context.smartCursor_), query);
    std::map<std::size_t, std::string> shiftedOverrides;
    for (const auto &entry : context.smartOverrides_) {
        shiftedOverrides[entry.first >= context.smartCursor_
                             ? entry.first + 1 : entry.first] = entry.second;
    }
    SmartComposition composition;
    if (!smartMandarinStore_->compose(trial, shiftedOverrides,
                                     composition)) {
        context.candidates_ = dictionary_->candidates(context.reading_.queryKey());
        context.showingSmartCandidates_ = false;
        context.page_ = 0;
        context.highlightedIndex_ = 0;
        return false;
    }
    context.smartReadings_ = std::move(trial);
    context.smartOverrides_ = std::move(shiftedOverrides);
    context.smartComposition_ = std::move(composition);
    ++context.smartCursor_;
    context.reading_.clear();
    context.candidates_.clear();
    context.showingSmartCandidates_ = false;
    context.page_ = 0;
    context.highlightedIndex_ = 0;
    constexpr std::size_t SmartComposingBufferSize = 10;
    if (context.smartReadings_.size() >= SmartComposingBufferSize &&
        !context.smartComposition_.segments.empty()) {
        const SmartSegment &first = context.smartComposition_.segments.front();
        pendingCommit += outputText(context, first.text);
        const std::size_t count = first.length;
        context.smartReadings_.erase(
            context.smartReadings_.begin(),
            context.smartReadings_.begin() +
                static_cast<std::ptrdiff_t>(count));
        std::map<std::size_t, std::string> shifted;
        for (const auto &entry : context.smartOverrides_) {
            if (entry.first >= count) {
                shifted[entry.first - count] = entry.second;
            }
        }
        context.smartOverrides_ = std::move(shifted);
        context.smartCursor_ = context.smartCursor_ > count
                                   ? context.smartCursor_ - count : 0;
        rebuildSmartComposition(context);
    }
    return true;
}

EngineResult Engine::processSmartKey(InputContextState &context,
                                     const KeyEvent &event) const {
    std::string pendingCommit;
    const auto resultFor = [&](bool beep = false) {
        EngineResult result = snapshot(context);
        result.handled = true;
        result.beep = beep;
        result.commit = pendingCommit;
        return result;
    };
    const bool hasReading = !context.reading_.empty(bopomofoLayout_);
    const bool hasComposition = !context.smartReadings_.empty();
    const std::string punctuationKey = punctuationQueryKey(event);
    if (!punctuationKey.empty()) {
        if (hasReading) {
            return resultFor(true);
        }
        const std::string prefix =
            hasComposition ? outputText(context, context.smartComposition_.text)
                           : std::string{};
        if (hasComposition) {
            context.reset();
        }
        EngineResult result = queryPunctuation(context, punctuationKey);
        result.commit = prefix + result.commit;
        return result;
    }
    if (hasApplicationShortcutModifier(event.modifiers)) {
        return snapshot(context);
    }
    if (event.modifiers != KeyModifier::None) {
        return snapshot(context);
    }
    if (!context.candidatePreedit_.empty() && !context.candidates_.empty()) {
        if (event.code == KeyCode::Character && event.character >= '1' &&
            event.character <= '9') {
            return selectDisplayedCandidate(
                context, static_cast<std::size_t>(event.character - '1'));
        }
        if (event.code == KeyCode::Enter) {
            return selectDisplayedCandidate(context, context.highlightedIndex_);
        }
        if (event.code == KeyCode::Escape) {
            clearCandidates(context);
            return resultFor();
        }
        if (event.code == KeyCode::Space || event.code == KeyCode::Right ||
            event.code == KeyCode::PageDown) {
            changeCandidatePage(context, 1);
            return resultFor();
        }
        if (event.code == KeyCode::Left || event.code == KeyCode::PageUp) {
            changeCandidatePage(context, -1);
            return resultFor();
        }
    }
    if (event.code == KeyCode::Character) {
        if (context.showingSmartCandidates_ && event.character >= '1' &&
            event.character <= '9') {
            return selectDisplayedCandidate(
                context, static_cast<std::size_t>(event.character - '1'));
        }
        if (acceptsCharacter(event.character)) {
            context.candidates_.clear();
            context.showingSmartCandidates_ = false;
            if (!context.reading_.combine(event.character, bopomofoLayout_)) {
                return resultFor(true);
            }
            if (context.reading_.hasToneMarker() &&
                !finishSmartReading(context, pendingCommit)) {
                return resultFor(true);
            }
            return resultFor();
        }
        if (hasReading) {
            return resultFor(true);
        }
        if (hasComposition) {
            const std::string composed = context.smartComposition_.text;
            const std::string literal =
                outputText(context, std::string(1, event.character));
            context.reset();
            EngineResult result = resultFor();
            result.commit = outputText(context, composed) + literal;
            return result;
        }
        if (context.fullWidthMode_ && event.character >= 0x20 &&
            event.character <= 0x7E) {
            EngineResult result = resultFor();
            result.commit = outputText(context, std::string(1, event.character));
            return result;
        }
        return snapshot(context);
    }
    switch (event.code) {
    case KeyCode::Space:
        if (hasReading) {
            return resultFor(!finishSmartReading(context, pendingCommit));
        }
        if (context.showingSmartCandidates_) {
            changeCandidatePage(context, 1);
            return resultFor();
        }
        if (hasComposition) {
            context.smartCandidateIndex_ =
                context.smartCursor_ == context.smartReadings_.size()
                    ? context.smartCursor_ - 1 : context.smartCursor_;
            context.candidates_ = smartMandarinStore_->candidates(
                context.smartReadings_, context.smartCandidateIndex_,
                context.smartComposition_);
            context.showingSmartCandidates_ = !context.candidates_.empty();
            return resultFor();
        }
        if (context.fullWidthMode_) {
            EngineResult result = resultFor();
            result.commit = outputText(context, " ");
            return result;
        }
        return snapshot(context);
    case KeyCode::Enter:
        if (hasReading) {
            return resultFor(!finishSmartReading(context, pendingCommit));
        }
        if (context.showingSmartCandidates_) {
            return selectDisplayedCandidate(context, context.highlightedIndex_);
        }
        if (hasComposition) {
            const std::string composed = context.smartComposition_.text;
            const std::string commit = outputText(context, composed);
            context.reset();
            EngineResult result = resultFor();
            result.commit = commit;
            return result;
        }
        return snapshot(context);
    case KeyCode::Backspace:
        if (hasReading) {
            context.reading_.backspace(bopomofoLayout_);
            context.candidates_.clear();
            return resultFor();
        }
        if (hasComposition && context.smartCursor_ > 0) {
            const std::size_t erased = --context.smartCursor_;
            context.smartReadings_.erase(
                context.smartReadings_.begin() +
                static_cast<std::ptrdiff_t>(erased));
            std::map<std::size_t, std::string> shifted;
            for (const auto &entry : context.smartOverrides_) {
                if (entry.first != erased) {
                    shifted[entry.first > erased ? entry.first - 1
                                                 : entry.first] = entry.second;
                }
            }
            context.smartOverrides_ = std::move(shifted);
            rebuildSmartComposition(context);
            return resultFor();
        }
        return hasComposition ? resultFor(true) : snapshot(context);
    case KeyCode::Delete:
        if (hasComposition && context.smartCursor_ < context.smartReadings_.size()) {
            const std::size_t erased = context.smartCursor_;
            context.smartReadings_.erase(
                context.smartReadings_.begin() +
                static_cast<std::ptrdiff_t>(erased));
            std::map<std::size_t, std::string> shifted;
            for (const auto &entry : context.smartOverrides_) {
                if (entry.first != erased) {
                    shifted[entry.first > erased ? entry.first - 1
                                                 : entry.first] = entry.second;
                }
            }
            context.smartOverrides_ = std::move(shifted);
            rebuildSmartComposition(context);
            return resultFor();
        }
        return hasReading || hasComposition ? resultFor(true)
                                            : snapshot(context);
    case KeyCode::Escape:
        if (context.showingSmartCandidates_) {
            context.candidates_.clear();
            context.showingSmartCandidates_ = false;
            return resultFor();
        }
        if (hasReading || hasComposition) {
            context.reset();
            return resultFor();
        }
        return snapshot(context);
    case KeyCode::Left:
    case KeyCode::PageUp:
        if (context.showingSmartCandidates_) {
            changeCandidatePage(context, -1);
            return resultFor();
        }
        if (event.code == KeyCode::Left && hasComposition && !hasReading &&
            context.smartCursor_ > 0) {
            --context.smartCursor_;
            return resultFor();
        }
        break;
    case KeyCode::Right:
    case KeyCode::PageDown:
        if (context.showingSmartCandidates_) {
            changeCandidatePage(context, 1);
            return resultFor();
        }
        if (event.code == KeyCode::Right && hasComposition && !hasReading &&
            context.smartCursor_ < context.smartReadings_.size()) {
            ++context.smartCursor_;
            return resultFor();
        }
        break;
    case KeyCode::Home:
        if (hasComposition && !hasReading) {
            context.smartCursor_ = 0;
            return resultFor();
        }
        break;
    case KeyCode::End:
        if (hasComposition && !hasReading) {
            context.smartCursor_ = context.smartReadings_.size();
            return resultFor();
        }
        break;
    case KeyCode::Up:
    case KeyCode::Down:
        if (context.showingSmartCandidates_) {
            moveCandidateHighlight(context,
                                   event.code == KeyCode::Down ? 1 : -1);
            return resultFor();
        }
        if (event.code == KeyCode::Down && hasComposition && !hasReading) {
            return processSmartKey(context, KeyEvent{KeyCode::Space});
        }
        break;
    default:
        break;
    }
    return hasReading || hasComposition ? resultFor(true) : snapshot(context);
}

EngineResult Engine::snapshot(const InputContextState &context) const {
    EngineResult result;
    if (smartMandarinMode_ && context.candidatePreedit_.empty()) {
        const std::string &composed = context.smartComposition_.text;
        const std::size_t cursor = utf8ByteOffset(composed,
                                                  context.smartCursor_);
        const std::string reading =
            context.reading_.displayText(bopomofoLayout_);
        result.preedit = composed.substr(0, cursor) + reading +
                         composed.substr(cursor);
        result.preeditCursorBytes = cursor + reading.size();
    } else {
        result.preedit = displayText(context);
        result.preeditCursorBytes = result.preedit.size();
    }
    result.candidatePage = context.page_;
    result.candidatePageCount =
        (context.candidates_.size() + CandidatesPerPage - 1) /
        CandidatesPerPage;
    result.highlightedIndex = context.highlightedIndex_;
    result.fullWidthMode = context.fullWidthMode_;
    result.traditionalToSimplifiedMode =
        context.traditionalToSimplifiedMode_;
    result.associatedPhrases = context.showingAssociatedPhrases_;

    const std::size_t start = context.page_ * CandidatesPerPage;
    if (start < context.candidates_.size()) {
        const std::size_t end =
            std::min(context.candidates_.size(), start + CandidatesPerPage);
        result.candidates.assign(context.candidates_.begin() +
                                     static_cast<std::ptrdiff_t>(start),
                                 context.candidates_.begin() +
                                     static_cast<std::ptrdiff_t>(end));
    }
    return result;
}

EngineResult Engine::query(InputContextState &context,
                           bool commitSingleCandidate) const {
    const std::string key = queryKey(context);
    if (inputMethod_ == InputMethod::Cangjie && key.size() > 1 &&
        key.find_first_of("?*") != std::string::npos) {
        context.candidates_ = dictionary_->candidatesMatching(key, '?', '*');
    } else {
        context.candidates_ = dictionary_->candidates(key);
    }
    if (inputMethod_ == InputMethod::Bopomofo &&
        restrictBopomofoCandidatesToBig5_) {
        context.candidates_ =
            filterBig5HkscsCandidates(context.candidates_);
    }
    context.candidatePreedit_.clear();
    context.showingAssociatedPhrases_ = false;
    context.page_ = 0;
    context.highlightedIndex_ = 0;
    if (commitSingleCandidate && context.candidates_.size() == 1) {
        return selectAbsoluteCandidate(context, 0);
    }
    if (context.candidates_.empty() &&
        inputMethod_ == InputMethod::Cangjie) {
        context.tableCode_.clear();
    }
    EngineResult result = snapshot(context);
    result.handled = true;
    result.beep = context.candidates_.empty() &&
                  inputMethod_ == InputMethod::Bopomofo;
    return result;
}

EngineResult Engine::queryPunctuation(InputContextState &context,
                                      const std::string &key) const {
    if (!punctuationDictionary_) {
        return snapshot(context);
    }
    const std::vector<std::string> &candidates =
        punctuationDictionary_->candidates(key);
    if (candidates.empty()) {
        return snapshot(context);
    }
    if (candidates.size() == 1) {
        const std::string selected = candidates.front();
        context.reset();
        EngineResult result = snapshot(context);
        result.handled = true;
        result.commit = outputText(context, selected);
        return result;
    }
    context.candidates_ = candidates;
    context.candidatePreedit_ = candidates.front();
    context.showingAssociatedPhrases_ = false;
    context.page_ = 0;
    context.highlightedIndex_ = 0;
    EngineResult result = snapshot(context);
    result.handled = true;
    return result;
}

bool Engine::acceptsCharacter(char character) const noexcept {
    if (inputMethod_ == InputMethod::Bopomofo) {
        return BopomofoReading::isBopomofoKey(character, bopomofoLayout_);
    }
    const char normalized = static_cast<char>(
        std::tolower(static_cast<unsigned char>(character)));
    return dictionary_->hasKeyName(std::string(1, normalized));
}

bool Engine::isEndKey(char character) const noexcept {
    const char normalized = static_cast<char>(
        std::tolower(static_cast<unsigned char>(character)));
    return dictionary_->isEndKey(std::string(1, normalized));
}

bool Engine::compositionEmpty(const InputContextState &context) const noexcept {
    return inputMethod_ == InputMethod::Bopomofo
               ? context.reading_.empty(bopomofoLayout_)
               : context.tableCode_.empty();
}

bool Engine::combine(InputContextState &context, char character) const {
    if (inputMethod_ == InputMethod::Bopomofo) {
        return context.reading_.combine(character, bopomofoLayout_);
    }
    if (context.tableCode_.size() < maximumCodeLength()) {
        context.tableCode_.push_back(static_cast<char>(
            std::tolower(static_cast<unsigned char>(character))));
    }
    return true;
}

void Engine::backspace(InputContextState &context) const {
    if (inputMethod_ == InputMethod::Bopomofo) {
        static_cast<void>(context.reading_.backspace(bopomofoLayout_));
    } else if (!context.tableCode_.empty()) {
        context.tableCode_.pop_back();
    }
}

void Engine::changeCandidatePage(InputContextState &context, int delta) const {
    const std::size_t pageCount =
        (context.candidates_.size() + CandidatesPerPage - 1) /
        CandidatesPerPage;
    if (pageCount == 0 || delta == 0) {
        context.page_ = 0;
        context.highlightedIndex_ = 0;
        return;
    }
    if (delta > 0) {
        context.page_ = (context.page_ + 1) % pageCount;
    } else {
        context.page_ = (context.page_ + pageCount - 1) % pageCount;
    }
    context.highlightedIndex_ = 0;
}

void Engine::moveCandidateHighlight(InputContextState &context,
                                    int delta) const {
    if (context.candidates_.empty() || delta == 0) {
        return;
    }
    const std::size_t absoluteIndex =
        context.page_ * CandidatesPerPage + context.highlightedIndex_;
    const std::size_t nextIndex =
        delta > 0 ? (absoluteIndex + 1) % context.candidates_.size()
                  : (absoluteIndex + context.candidates_.size() - 1) %
                        context.candidates_.size();
    context.page_ = nextIndex / CandidatesPerPage;
    context.highlightedIndex_ = nextIndex % CandidatesPerPage;
}

std::string Engine::queryKey(const InputContextState &context) const {
    return inputMethod_ == InputMethod::Bopomofo ? context.reading_.queryKey()
                                                 : context.tableCode_;
}

std::string Engine::displayText(const InputContextState &context) const {
    if (!context.candidatePreedit_.empty()) {
        return context.candidatePreedit_;
    }
    if (inputMethod_ == InputMethod::Bopomofo) {
        return context.reading_.displayText(bopomofoLayout_);
    }
    std::string result;
    for (const char character : context.tableCode_) {
        const std::string key(1, character);
        const std::string &name = dictionary_->keyName(key);
        result += name.empty() ? key : name;
    }
    return result;
}

std::string Engine::outputText(const InputContextState &context,
                               const std::string &text) const {
    std::string result = context.fullWidthMode_ ? toFullWidth(text) : text;
    if (context.traditionalToSimplifiedMode_ &&
        traditionalToSimplifiedDictionary_) {
        result = toSimplifiedChinese(result,
                                     *traditionalToSimplifiedDictionary_);
    }
    return result;
}

std::size_t Engine::maximumCodeLength() const noexcept {
    return inputMethod_ == InputMethod::Simplex ? 2U : 5U;
}

std::string Engine::punctuationQueryKey(const KeyEvent &event) const {
    if (inputMethod_ != InputMethod::Bopomofo || !punctuationDictionary_ ||
        event.code != KeyCode::Character) {
        return {};
    }

    std::string key;
    if (event.modifiers == KeyModifier::Control) {
        key = event.character == '0' || event.character == '1'
                  ? "_punctuation_list"
                  : "_ctrl_" + std::string(1, event.character);
    } else if (event.modifiers ==
               (KeyModifier::Control | KeyModifier::Alt)) {
        key = "_ctrl_opt_" + std::string(1, event.character);
    } else {
        return {};
    }
    return punctuationDictionary_->candidates(key).empty() ? std::string{}
                                                            : key;
}

EngineResult Engine::selectAbsoluteCandidate(InputContextState &context,
                                             std::size_t index) const {
    if (index >= context.candidates_.size()) {
        EngineResult result = snapshot(context);
        result.handled = true;
        result.beep = true;
        return result;
    }
    const bool selectedAssociatedPhrase =
        context.showingAssociatedPhrases_;
    const std::string selected = context.candidates_[index];
    context.reset();
    if (!smartMandarinMode_ && !selectedAssociatedPhrase &&
        associatedPhraseDictionary_) {
        context.candidates_ = associatedPhraseDictionary_->candidates(
            selected, enabledAssociatedPhraseCollections_);
        context.showingAssociatedPhrases_ = !context.candidates_.empty();
    }
    EngineResult result = snapshot(context);
    result.handled = true;
    result.commit = outputText(context, selected);
    return result;
}

void Engine::clearCandidates(InputContextState &context) const noexcept {
    context.candidatePreedit_.clear();
    context.candidates_.clear();
    context.page_ = 0;
    context.highlightedIndex_ = 0;
    context.showingAssociatedPhrases_ = false;
}

} // namespace keykey::linux_ime
