/// Where character candidates come from. The keyboard uses the SQLite-backed
/// `CandidateStore`; tests use an in-memory table.
public protocol CandidateSource {
    func candidates(for reading: BopomofoReading) -> [String]
}

/// Where associated phrases come from, keyed by the committed head character.
public protocol AssociatedPhraseSource {
    func phrases(forHeadCharacter character: String) -> [String]
}

/// The input state machine, ported from
/// `Source/Loaders/Android-IME/.../BopomofoEngine.java` so the two touch
/// keyboards behave identically.
///
/// The state machine remains platform-neutral. The iOS loader mirrors
/// `readingText` into the host's marked-text range and applies `Result.text` as
/// the committed replacement.
public final class BopomofoEngine {
    public static let candidatesPerPage = 9

    public enum InputMode: Sendable, Hashable, CaseIterable {
        case bopomofo, english, number
    }

    /// What the caller must do to the document. Everything else is display
    /// state read back off the engine.
    public struct Result: Equatable, Sendable {
        public let text: String
        public let deletesBackward: Bool
        public let sendsReturn: Bool

        static let update = Result(text: "", deletesBackward: false, sendsReturn: false)
        static func commit(_ text: String) -> Result {
            Result(text: text, deletesBackward: false, sendsReturn: false)
        }
        static let delete = Result(text: "", deletesBackward: true, sendsReturn: false)
        static let returnKey = Result(text: "", deletesBackward: false, sendsReturn: true)
    }

    /// The 90 punctuation and symbol entries the 「符」 key offers, and the 90
    /// emoji the third row offers. Both are ten pages of nine. These are the
    /// Android arrays verbatim, not the database's 217-row `_punctuation_list`.
    public static let symbols: [String] = [
        "，", "。", "、", "？", "！", "：", "；", "「", "」",
        "『", "』", "（", "）", "【", "】", "〔", "〕", "…",
        "—", "～", "·", "‧", "‥", "※", "＊", "＃", "＠",
        "＆", "％", "＋", "－", "×", "÷", "＝", "≠", "±",
        "＜", "＞", "≤", "≥", "≈", "∞", "√", "∑", "∫",
        "°", "℃", "℉", "㎜", "㎝", "㎞", "㎎", "㎏", "㎡",
        "＄", "￠", "￡", "￥", "€", "₩", "₹", "₽", "¢",
        "←", "→", "↑", "↓", "↔", "↕", "↖", "↗", "↘",
        "↙", "⇒", "⇔", "✓", "✔", "✕", "✖", "★", "☆",
        "●", "○", "■", "□", "▲", "△", "▼", "▽", "◆"
    ]

    public static let emojis: [String] = [
        "😀", "😃", "😄", "😁", "😆", "😅", "😂", "😊", "😍",
        "🥰", "😘", "😎", "🤩", "🥳", "🙂", "😉", "😋", "🤔",
        "😭", "😢", "😡", "😱", "😴", "🤢", "🤮", "🥺", "🤣",
        "👍", "👎", "👌", "✌️", "🤞", "👏", "🙏", "💪", "👋",
        "❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "💯", "🎉",
        "🍎", "🍊", "🍋", "🍌", "🍉", "🍇", "🍓", "🫐", "🍒",
        "🍔", "🍟", "🍕", "🌭", "🍿", "🍩", "🍪", "🎂", "☕",
        "🐶", "🐱", "🐭", "🐹", "🐰", "🦊", "🐻", "🐼", "🐨",
        "🌞", "🌙", "⭐", "🌈", "🔥", "💧", "🌸", "🌹", "🍀",
        "🚗", "🚌", "🚆", "✈️", "🚀", "🏠", "🎁", "🎈", "🔔"
    ]

    private let dictionary: CandidateSource
    private var associatedPhrases: AssociatedPhraseSource?
    private let smartSource: SmartMandarinSource?
    private let hardwareSmartEditing: Bool

    private var reading = BopomofoReading()
    private var candidates: [String] = []
    private var pageIndex = 0
    private var highlight = 0
    private var mode = InputMode.bopomofo
    private var shifted = false
    private var temporaryEnglish = false
    private var showingAssociatedPhrases = false
    private var allowedInputModes = Set(InputMode.allCases)
    private var compositionMode: BopomofoCompositionMode
    private var smartReadings: [String] = []
    private var smartComposition: SmartMandarinComposition?
    private var smartOverrides: [Int: SmartMandarinSelection] = [:]
    private var smartCursor = 0
    private var smartCandidateStart = 0
    private var smartCandidateOptions: [SmartMandarinCandidate] = []
    private var showingSmartCandidates = false

    public init(
        dictionary: CandidateSource,
        associatedPhrases: AssociatedPhraseSource? = nil,
        smartSource: SmartMandarinSource? = nil,
        compositionMode: BopomofoCompositionMode = .traditional,
        hardwareSmartEditing: Bool = false
    ) {
        self.dictionary = dictionary
        self.associatedPhrases = associatedPhrases
        self.smartSource = smartSource
        self.hardwareSmartEditing = hardwareSmartEditing
        self.compositionMode = smartSource == nil ? .traditional : compositionMode
    }

    public func setAssociatedPhraseSource(_ source: AssociatedPhraseSource?) {
        associatedPhrases = source
        if showingAssociatedPhrases { clearComposition() }
    }

    @discardableResult
    public func setCompositionMode(_ mode: BopomofoCompositionMode) -> Result {
        guard mode != compositionMode else { return .update }
        let result = finishCompositionForModeSwitch()
        compositionMode = mode == .smart && smartSource == nil ? .traditional : mode
        return result
    }

    public func setAllowedInputModes(
        _ allowed: Set<InputMode>, preferred: InputMode, selectPreferred: Bool = false
    ) {
        allowedInputModes = allowed.isEmpty ? Set(InputMode.allCases) : allowed
        if temporaryEnglish && !allowedInputModes.contains(.bopomofo) {
            temporaryEnglish = false
        }
        if selectPreferred || !allowedInputModes.contains(mode) {
            clearComposition()
            mode = allowedInputModes.contains(preferred)
                ? preferred : allowedInputModes.sorted(by: modeOrder).first!
            shifted = false
            temporaryEnglish = false
        }
    }

    // MARK: - Display state

    public var readingText: String { reading.displayText }
    public var composingText: String {
        guard compositionMode == .smart else { return reading.displayText }
        return (smartComposition?.text ?? "") + reading.displayText
    }
    public var hasComposition: Bool { !composingText.isEmpty }
    public var smartCompositionCursor: Int? {
        hardwareSmartEditing && compositionMode == .smart && !smartReadings.isEmpty
            ? smartCursor : nil
    }
    public var smartCompositionReadingCount: Int { smartReadings.count }
    public var composingCaretUTF16Offset: Int {
        guard let composition = smartComposition, let cursor = smartCompositionCursor,
              reading.isEmpty else { return composingText.utf16.count }
        var prefix = ""
        for segment in composition.segments {
            if cursor >= segment.start + segment.length {
                prefix += segment.text
            } else if cursor > segment.start {
                // Most segments have one character per reading. Keep the caret
                // inside a longer phrase if its display length differs.
                let characters = Array(segment.text)
                let count = (cursor - segment.start) * characters.count / segment.length
                prefix += String(characters.prefix(count))
                break
            } else {
                break
            }
        }
        return prefix.utf16.count
    }
    public var bopomofoCompositionMode: BopomofoCompositionMode { compositionMode }
    public var isShowingSmartCandidates: Bool { showingSmartCandidates }
    public var inputMode: InputMode { mode }
    public var isShifted: Bool { shifted }
    public var isTemporaryEnglish: Bool { temporaryEnglish }
    public var isShowingAssociatedPhrases: Bool { showingAssociatedPhrases }
    public var page: Int { pageIndex }

    public var pageCount: Int {
        (candidates.count + Self.candidatesPerPage - 1) / Self.candidatesPerPage
    }

    public var displayedCandidates: [String] {
        let start = pageIndex * Self.candidatesPerPage
        guard start < candidates.count else { return [] }
        return Array(candidates[start..<min(candidates.count, start + Self.candidatesPerPage)])
    }

    /// -1 when there is nothing to highlight.
    public var highlightedIndex: Int {
        let count = displayedCandidates.count
        return count == 0 ? -1 : min(highlight, count - 1)
    }

    // MARK: - Key entry points

    /// A press on the on-screen keyboard. Named keys are the function row;
    /// anything else is a single character from one of the key planes.
    @discardableResult
    public func handleSoftKey(_ key: String) -> Result {
        // Temporary English lasts exactly one typed character.
        let restoreBopomofo = temporaryEnglish && key != "SHIFT" && key != "MODE"
        let result: Result
        switch key {
        case "MODE": result = cycleInputMode()
        case "SHIFT": result = touchShift()
        case "BACKSPACE": result = backspace()
        case "SPACE": result = space()
        case "ENTER": result = enter()
        case "ESCAPE": result = escape()
        case "SYMBOL": result = showSymbols()
        case "EMOJI": result = showEmojis()
        default:
            result = key.count == 1 ? character(key.first!, fromTouch: true) : .update
        }
        if restoreBopomofo { endTemporaryEnglish() }
        return result
    }

    /// A character from a physical keyboard. This mirrors Android's hardware
    /// path: Shift changes the character supplied by UIKit, number-row keys can
    /// select ordinary candidates, and a new reading dismisses associated
    /// phrases without committing one.
    @discardableResult
    public func handleHardwareCharacter(_ key: Character) -> Result {
        prepareForHardwareInput()
        return character(key, fromTouch: false)
    }

    /// Ctrl+Space alternates only between Bopomofo and English, matching the
    /// desktop and Android physical-keyboard shortcut.
    @discardableResult
    public func toggleHardwareLanguage() -> Result {
        prepareForHardwareInput()
        let result = finishCompositionForModeSwitch()
        mode = mode == .bopomofo ? .english : .bopomofo
        shifted = false
        return result
    }

    @discardableResult
    public func showHardwareSymbols() -> Result {
        prepareForHardwareInput()
        guard reading.isEmpty || compositionMode == .smart else { return .update }
        return showSymbols()
    }

    @discardableResult
    public func commitHardwarePunctuation(_ punctuation: String) -> Result {
        prepareForHardwareInput()
        guard reading.isEmpty || compositionMode == .smart else { return .update }
        return .commit(finishCompositionForModeSwitch().text + punctuation)
    }

    @discardableResult
    public func space() -> Result {
        if compositionMode == .smart, mode == .bopomofo {
            if !reading.isEmpty { return finishSmartReading() }
            if !smartReadings.isEmpty {
                if hardwareSmartEditing && !showingSmartCandidates {
                    showHardwareSmartCandidates()
                } else {
                    changePage(by: 1)
                }
                return .update
            }
        }
        if !candidates.isEmpty {
            changePage(by: 1)
            return .update
        }
        guard mode == .bopomofo, !reading.isEmpty else { return .commit(" ") }
        return query()
    }

    @discardableResult
    public func enter() -> Result {
        if showingAssociatedPhrases {
            clearComposition()
            return .returnKey
        }
        if compositionMode == .smart, mode == .bopomofo, hasComposition {
            if hardwareSmartEditing && showingSmartCandidates {
                return selectHighlightedCandidate()
            }
            if !reading.isEmpty {
                let result = finishSmartReading()
                guard reading.isEmpty else { return result }
            }
            return commitSmartComposition()
        }
        if !candidates.isEmpty { return selectHighlightedCandidate() }
        if !reading.isEmpty { return query() }
        return .returnKey
    }

    /// While a reading is being composed the backspace peels it inside the
    /// keyboard; only an empty reading reaches the document.
    @discardableResult
    public func backspace() -> Result {
        if compositionMode == .smart, mode == .bopomofo {
            if !reading.isEmpty {
                reading.backspace()
                candidates = []
                showingSmartCandidates = false
                pageIndex = 0
                return .update
            }
            if !smartReadings.isEmpty {
                guard smartCursor > 0 else { return .update }
                let deleted = smartCursor - 1
                smartReadings.remove(at: deleted)
                smartCursor = deleted
                shiftSmartOverrides(afterRemoving: deleted)
                rebuildSmartComposition()
                return .update
            }
        }
        if !candidates.isEmpty {
            candidates = []
            showingAssociatedPhrases = false
            highlight = 0
        }
        if !reading.isEmpty {
            reading.backspace()
            pageIndex = 0
            return .update
        }
        return .delete
    }

    @discardableResult
    public func escape() -> Result {
        if hardwareSmartEditing, compositionMode == .smart {
            if showingSmartCandidates {
                candidates = []
                showingSmartCandidates = false
                pageIndex = 0
                highlight = 0
            } else if !reading.isEmpty {
                reading.clear()
            }
            return .update
        }
        clearComposition()
        return .update
    }

    // MARK: - Candidates

    @discardableResult
    public func selectDisplayedCandidate(_ displayedIndex: Int) -> Result {
        let absolute = pageIndex * Self.candidatesPerPage + displayedIndex
        guard absolute >= 0, absolute < candidates.count else { return .update }
        let selected = candidates[absolute]
        if compositionMode == .smart, showingSmartCandidates, !smartReadings.isEmpty {
            guard smartCandidateOptions.indices.contains(absolute) else { return .update }
            let option = smartCandidateOptions[absolute]
            smartSource?.learnSelection(
                readings: smartReadings, at: smartCandidateStart,
                candidate: option, composition: smartComposition
            )
            let end = smartCandidateStart + option.length
            smartOverrides = smartOverrides.filter { start, selection in
                start >= end || start + selection.length <= smartCandidateStart
            }
            smartOverrides[smartCandidateStart] = SmartMandarinSelection(
                length: option.length, text: option.text
            )
            smartCursor = end
            rebuildSmartComposition()
            return .update
        }
        if showingAssociatedPhrases {
            // Only the suffix is committed, and it does not chain another round.
            clearComposition()
            return .commit(selected)
        }
        return commitPrimaryCandidate(selected, offeringAssociatedPhrases: true)
    }

    @discardableResult
    public func selectHighlightedCandidate() -> Result {
        selectDisplayedCandidate(highlight)
    }

    /// Highlight movement wraps across the whole candidate list, not just the
    /// visible page.
    public func moveHighlight(by delta: Int) {
        guard !candidates.isEmpty, delta != 0 else { return }
        let absolute = pageIndex * Self.candidatesPerPage + highlight
        let next = floorMod(absolute + delta, candidates.count)
        pageIndex = next / Self.candidatesPerPage
        highlight = next % Self.candidatesPerPage
    }

    /// Paging is cyclic: the page before the first is the last.
    public func changePage(by delta: Int) {
        let pages = pageCount
        guard pages > 0 else {
            pageIndex = 0
            highlight = 0
            return
        }
        pageIndex = floorMod(pageIndex + delta, pages)
        highlight = 0
    }

    /// Moves between reading boundaries in an uncommitted hardware composition.
    /// The candidate panel closes so the next Space queries the new position.
    @discardableResult
    public func moveSmartCompositionCursor(by delta: Int) -> Bool {
        guard smartCompositionCursor != nil, reading.isEmpty else { return false }
        smartCursor = min(max(smartCursor + delta, 0), smartReadings.count)
        candidates = []
        smartCandidateOptions = []
        showingSmartCandidates = false
        pageIndex = 0
        highlight = 0
        return true
    }

    public func reset() {
        clearComposition()
        if temporaryEnglish {
            mode = allowedInputModes.contains(.bopomofo)
                ? .bopomofo : allowedInputModes.sorted(by: modeOrder).first!
        }
        temporaryEnglish = false
        shifted = false
    }

    // MARK: - Internals

    private func character(_ rawKey: Character, fromTouch: Bool) -> Result {
        if mode == .english {
            let output = fromTouch && shifted && rawKey.isLetter
                ? Character(rawKey.uppercased()) : rawKey
            return .commit(String(output))
        }
        if mode == .number { return .commit(String(rawKey)) }

        let key = Character(rawKey.lowercased())
        if !fromTouch, !showingAssociatedPhrases, !candidates.isEmpty,
           let number = key.wholeNumberValue, (1...9).contains(number) {
            return selectDisplayedCandidate(number - 1)
        }
        if StandardBopomofoLayout.isReadingKey(key) {
            if compositionMode == .smart {
                candidates = []
                showingAssociatedPhrases = false
                showingSmartCandidates = false
                reading.combine(key)
                return reading.hasToneMarker ? finishSmartReading() : .update
            }
            let prefix = commitFirstCandidateIfNeeded()
            reading.combine(key)
            let result = reading.hasToneMarker ? query() : Result.update
            if !prefix.isEmpty {
                return .commit(prefix + result.text)
            }
            return result
        }

        if !reading.isEmpty {
            if compositionMode == .smart {
                return .commit(finishCompositionForModeSwitch().text + String(rawKey))
            }
            return .update
        }
        if compositionMode == .smart, !smartReadings.isEmpty {
            return .commit(finishCompositionForModeSwitch().text + String(rawKey))
        }
        if !candidates.isEmpty {
            let prefix = commitFirstCandidateIfNeeded()
            return .commit(prefix + String(rawKey))
        }
        return .commit(String(rawKey))
    }

    private func query() -> Result {
        candidates = dictionary.candidates(for: reading)
        showingAssociatedPhrases = false
        pageIndex = 0
        highlight = 0
        if candidates.count == 1 {
            return commitPrimaryCandidate(candidates[0], offeringAssociatedPhrases: true)
        }
        return .update
    }

    private func finishSmartReading() -> Result {
        guard let smartSource, !reading.isEmpty else { return .update }
        let query = reading.queryKey
        var trialReadings = smartReadings
        trialReadings.insert(query, at: smartCursor)
        let shiftedOverrides = shiftedSmartOverrides(afterInserting: smartCursor)
        guard smartSource.compose(readings: trialReadings, selections: shiftedOverrides) != nil else {
            candidates = dictionary.candidates(for: reading)
            showingSmartCandidates = false
            pageIndex = 0
            highlight = 0
            return .update
        }
        smartReadings = trialReadings
        smartOverrides = shiftedOverrides
        smartCursor += 1
        reading.clear()
        rebuildSmartComposition()
        return .update
    }

    private func rebuildSmartComposition() {
        guard let smartSource else { return }
        smartComposition = smartSource.compose(
            readings: smartReadings, selections: smartOverrides
        )
        if smartReadings.isEmpty || smartComposition == nil || hardwareSmartEditing {
            candidates = []
            smartCandidateOptions = []
            showingSmartCandidates = false
        } else {
            smartCandidateStart = smartReadings.count - 1
            smartCandidateOptions = smartSource.candidateOptions(
                for: smartReadings,
                at: smartCandidateStart,
                composition: smartComposition
            )
            candidates = smartCandidateOptions.map(\.text)
            showingSmartCandidates = !candidates.isEmpty
        }
        showingAssociatedPhrases = false
        pageIndex = 0
        highlight = 0
    }

    private func showHardwareSmartCandidates() {
        guard let smartSource, !smartReadings.isEmpty else { return }
        smartCandidateStart = min(smartCursor, smartReadings.count - 1)
        smartCandidateOptions = smartSource.candidateOptions(
            for: smartReadings,
            at: smartCandidateStart,
            composition: smartComposition
        )
        candidates = smartCandidateOptions.map(\.text)
        showingSmartCandidates = !candidates.isEmpty
        pageIndex = 0
        highlight = 0
    }

    private func shiftedSmartOverrides(afterInserting index: Int) -> [Int: SmartMandarinSelection] {
        var shifted: [Int: SmartMandarinSelection] = [:]
        for (start, selection) in smartOverrides {
            if start >= index {
                shifted[start + 1] = selection
            } else if start + selection.length <= index {
                shifted[start] = selection
            }
        }
        return shifted
    }

    private func shiftSmartOverrides(afterRemoving index: Int) {
        var shifted: [Int: SmartMandarinSelection] = [:]
        for (start, selection) in smartOverrides {
            if start > index {
                shifted[start - 1] = selection
            } else if start + selection.length <= index {
                shifted[start] = selection
            }
        }
        smartOverrides = shifted
    }

    private func commitSmartComposition() -> Result {
        let text = smartComposition?.text ?? ""
        if let smartComposition, !text.isEmpty {
            smartSource?.learnConfirmedComposition(smartComposition)
        }
        clearComposition()
        return text.isEmpty ? .update : .commit(text)
    }

    private func finishCompositionForModeSwitch() -> Result {
        guard compositionMode == .smart, mode == .bopomofo, hasComposition else {
            clearComposition()
            return .update
        }
        if !reading.isEmpty { _ = finishSmartReading() }
        if reading.isEmpty { return commitSmartComposition() }

        // An unfinished syllable may have no language-model match. Keep the
        // visible reading after the converted text instead of losing it.
        let text = (smartComposition?.text ?? "") + reading.displayText
        if let smartComposition {
            smartSource?.learnConfirmedComposition(smartComposition)
        }
        clearComposition()
        return .commit(text)
    }

    /// Associated phrases only appear after a single Chinese character is
    /// committed from the dictionary -- never after a symbol, emoji or letter.
    private func commitPrimaryCandidate(
        _ selected: String, offeringAssociatedPhrases offering: Bool
    ) -> Result {
        clearComposition()
        if offering, let source = associatedPhrases {
            candidates = source.phrases(forHeadCharacter: selected)
            showingAssociatedPhrases = !candidates.isEmpty
        }
        return .commit(selected)
    }

    /// Typing a new reading over a candidate list commits the first candidate
    /// first; over an associated-phrase list it commits nothing.
    private func commitFirstCandidateIfNeeded() -> String {
        guard !candidates.isEmpty else { return "" }
        if showingAssociatedPhrases {
            clearComposition()
            return ""
        }
        let first = candidates[pageIndex * Self.candidatesPerPage]
        clearComposition()
        return first
    }

    private func cycleInputMode() -> Result {
        let result = finishCompositionForModeSwitch()
        if temporaryEnglish {
            temporaryEnglish = false
            shifted = false
            return result
        }
        repeat {
            switch mode {
            case .bopomofo: mode = .english
            case .english: mode = .number
            case .number: mode = .bopomofo
            }
        } while !allowedInputModes.contains(mode)
        shifted = false
        return result
    }

    /// Shift on the Bopomofo plane is a one-shot hop to lower-case English; on
    /// the English and number planes it latches.
    private func touchShift() -> Result {
        let result = finishCompositionForModeSwitch()
        if temporaryEnglish {
            endTemporaryEnglish()
        } else if mode == .bopomofo, allowedInputModes.contains(.english) {
            mode = .english
            temporaryEnglish = true
            shifted = false
        } else {
            shifted = !shifted
        }
        return result
    }

    private func endTemporaryEnglish() {
        mode = allowedInputModes.contains(.bopomofo)
            ? .bopomofo : allowedInputModes.sorted(by: modeOrder).first!
        temporaryEnglish = false
        shifted = false
    }

    private func prepareForHardwareInput() {
        if temporaryEnglish { endTemporaryEnglish() }
    }

    private func showSymbols() -> Result {
        let result = finishCompositionForModeSwitch()
        candidates = Self.symbols
        return result
    }

    private func showEmojis() -> Result {
        let result = finishCompositionForModeSwitch()
        candidates = Self.emojis
        return result
    }

    private func clearComposition() {
        reading.clear()
        smartReadings = []
        smartComposition = nil
        smartOverrides = [:]
        smartCursor = 0
        smartCandidateStart = 0
        smartCandidateOptions = []
        showingSmartCandidates = false
        candidates = []
        pageIndex = 0
        highlight = 0
        showingAssociatedPhrases = false
    }

    private func floorMod(_ value: Int, _ modulus: Int) -> Int {
        let remainder = value % modulus
        return remainder < 0 ? remainder + modulus : remainder
    }

    private func modeOrder(_ left: InputMode, _ right: InputMode) -> Bool {
        InputMode.allCases.firstIndex(of: left)! < InputMode.allCases.firstIndex(of: right)!
    }
}

extension CandidateStore: CandidateSource {}
extension AssociatedPhraseStore: AssociatedPhraseSource {}
