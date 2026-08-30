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
/// Unlike Android there is no marked-text channel on iOS, so the caller shows
/// `readingText` inside the keyboard and only ever inserts `Result.text`.
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

    private var reading = BopomofoReading()
    private var candidates: [String] = []
    private var pageIndex = 0
    private var highlight = 0
    private var mode = InputMode.bopomofo
    private var shifted = false
    private var temporaryEnglish = false
    private var showingAssociatedPhrases = false
    private var allowedInputModes = Set(InputMode.allCases)

    public init(dictionary: CandidateSource, associatedPhrases: AssociatedPhraseSource? = nil) {
        self.dictionary = dictionary
        self.associatedPhrases = associatedPhrases
    }

    public func setAssociatedPhraseSource(_ source: AssociatedPhraseSource?) {
        associatedPhrases = source
        if showingAssociatedPhrases { clearComposition() }
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
            result = key.count == 1 ? character(key.first!) : .update
        }
        if restoreBopomofo { endTemporaryEnglish() }
        return result
    }

    @discardableResult
    public func space() -> Result {
        if !candidates.isEmpty {
            changePage(by: 1)
            return .update
        }
        guard mode == .bopomofo, !reading.isEmpty else { return .commit(" ") }
        return query()
    }

    @discardableResult
    public func enter() -> Result {
        if !candidates.isEmpty { return selectHighlightedCandidate() }
        if !reading.isEmpty { return query() }
        return .returnKey
    }

    /// While a reading is being composed the backspace peels it inside the
    /// keyboard; only an empty reading reaches the document.
    @discardableResult
    public func backspace() -> Result {
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
        clearComposition()
        return .update
    }

    // MARK: - Candidates

    @discardableResult
    public func selectDisplayedCandidate(_ displayedIndex: Int) -> Result {
        let absolute = pageIndex * Self.candidatesPerPage + displayedIndex
        guard absolute >= 0, absolute < candidates.count else { return .update }
        let selected = candidates[absolute]
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

    /// Every character arrives from the on-screen keyboard, so unlike the
    /// Android engine there is no hardware branch: digits never select a
    /// candidate, and the four Bopomofo rows stay Bopomofo even with a
    /// candidate list open. Candidates are chosen by tapping them.
    private func character(_ rawKey: Character) -> Result {
        if mode == .english {
            let output = shifted && rawKey.isLetter
                ? Character(rawKey.uppercased()) : rawKey
            return .commit(String(output))
        }
        if mode == .number { return .commit(String(rawKey)) }

        let key = Character(rawKey.lowercased())
        if StandardBopomofoLayout.isReadingKey(key) {
            let prefix = commitFirstCandidateIfNeeded()
            reading.combine(key)
            let result = reading.hasToneMarker ? query() : Result.update
            if !prefix.isEmpty {
                return .commit(prefix + result.text)
            }
            return result
        }

        if !reading.isEmpty { return .update }
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
        clearComposition()
        if temporaryEnglish {
            temporaryEnglish = false
            shifted = false
            return .update
        }
        repeat {
            switch mode {
            case .bopomofo: mode = .english
            case .english: mode = .number
            case .number: mode = .bopomofo
            }
        } while !allowedInputModes.contains(mode)
        shifted = false
        return .update
    }

    /// Shift on the Bopomofo plane is a one-shot hop to lower-case English; on
    /// the English and number planes it latches.
    private func touchShift() -> Result {
        clearComposition()
        if temporaryEnglish {
            endTemporaryEnglish()
        } else if mode == .bopomofo, allowedInputModes.contains(.english) {
            mode = .english
            temporaryEnglish = true
            shifted = false
        } else {
            shifted = !shifted
        }
        return .update
    }

    private func endTemporaryEnglish() {
        mode = allowedInputModes.contains(.bopomofo)
            ? .bopomofo : allowedInputModes.sorted(by: modeOrder).first!
        temporaryEnglish = false
        shifted = false
    }

    private func showSymbols() -> Result {
        clearComposition()
        candidates = Self.symbols
        return .update
    }

    private func showEmojis() -> Result {
        clearComposition()
        candidates = Self.emojis
        return .update
    }

    private func clearComposition() {
        reading.clear()
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
