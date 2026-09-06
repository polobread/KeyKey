import Testing

@testable import KeyKeyEngine

/// An in-memory table keyed by keystroke sequence, e.g. `"su3"`, converted to
/// the absolute-order key the engine actually looks up.
private struct TableCandidateSource: CandidateSource {
    private var table: [String: [String]] = [:]

    init(_ entries: [String: [String]]) {
        for (keys, candidates) in entries {
            table[Self.queryKey(for: keys)] = candidates
        }
    }

    static func queryKey(for keys: String) -> String {
        var reading = BopomofoReading()
        for key in keys { reading.combine(key) }
        return reading.queryKey
    }

    func candidates(for reading: BopomofoReading) -> [String] {
        reading.isEmpty ? [] : (table[reading.queryKey] ?? [])
    }
}

private struct TablePhraseSource: AssociatedPhraseSource {
    let table: [String: [String]]
    func phrases(forHeadCharacter character: String) -> [String] {
        table[character] ?? []
    }
}

/// Ported from `BopomofoEngineTest.java`. Hardware cases are used by the
/// containing App's editor; the keyboard extension itself still cannot receive
/// physical key events.
@Suite("Bopomofo engine")
struct BopomofoEngineTests {
    private func engine(
        _ entries: [String: [String]] = ["su3": ["你", "妳", "擬"]],
        phrases: [String: [String]] = [:]
    ) -> BopomofoEngine {
        BopomofoEngine(
            dictionary: TableCandidateSource(entries),
            associatedPhrases: phrases.isEmpty ? nil : TablePhraseSource(table: phrases)
        )
    }

    private func type(_ engine: BopomofoEngine, _ keys: String) -> [BopomofoEngine.Result] {
        keys.map { engine.handleSoftKey(String($0)) }
    }

    // MARK: Reading and candidates

    @Test("a tone mark opens the candidate list")
    func toneOpensCandidates() {
        let engine = engine()
        _ = type(engine, "su")
        #expect(engine.readingText == "ㄋㄧ")
        #expect(engine.displayedCandidates.isEmpty)

        let result = engine.handleSoftKey("3")
        #expect(result == .update)
        #expect(engine.readingText == "ㄋㄧˇ")
        #expect(engine.displayedCandidates == ["你", "妳", "擬"])
        #expect(engine.highlightedIndex == 0)
    }

    @Test("tapping a candidate commits it and clears the reading")
    func tapCommits() {
        let engine = engine()
        _ = type(engine, "su3")
        let result = engine.selectDisplayedCandidate(1)
        #expect(result == .commit("妳"))
        #expect(engine.readingText.isEmpty)
        #expect(engine.displayedCandidates.isEmpty)
    }

    @Test("a single candidate commits without showing a list")
    func singleCandidateAutoCommits() {
        let engine = engine(["su3": ["你"]])
        _ = type(engine, "su")
        let result = engine.handleSoftKey("3")
        #expect(result == .commit("你"))
        #expect(engine.displayedCandidates.isEmpty)
        #expect(engine.readingText.isEmpty)
    }

    @Test("space looks up a toneless reading")
    func spaceQueriesTonelessReading() {
        let engine = engine(["su": ["泥", "尼"]])
        _ = type(engine, "su")
        let result = engine.handleSoftKey("SPACE")
        #expect(result == .update)
        #expect(engine.displayedCandidates == ["泥", "尼"])
    }

    @Test("space with nothing composed types a space")
    func spaceTypesSpace() {
        #expect(engine().handleSoftKey("SPACE") == .commit(" "))
    }

    @Test("touch digits never select a visible candidate")
    func digitsDoNotSelect() {
        let engine = engine()
        _ = type(engine, "su3")
        // '2' is the ㄉ key; it must commit the first candidate and start a
        // new reading rather than picking candidate two.
        let result = engine.handleSoftKey("2")
        #expect(result == .commit("你"))
        #expect(engine.readingText == "ㄉ")
    }

    @Test("hardware number row selects ordinary candidates")
    func hardwareDigitSelectsCandidate() {
        let engine = engine(["su3": ["你", "擬"]])
        _ = type(engine, "su3")

        #expect(engine.handleHardwareCharacter("2") == .commit("擬"))
        #expect(engine.readingText.isEmpty)
    }

    @Test("a new reading over a candidate list commits the first candidate")
    func newReadingCommitsFirst() {
        let engine = engine()
        _ = type(engine, "su3")
        let result = engine.handleSoftKey("s")
        #expect(result == .commit("你"))
        #expect(engine.readingText == "ㄋ")
        #expect(engine.displayedCandidates.isEmpty)
    }

    // MARK: Backspace and escape

    @Test("backspace peels the reading before touching the document")
    func backspacePeelsReading() {
        let engine = engine()
        _ = type(engine, "su3")
        #expect(engine.handleSoftKey("BACKSPACE") == .update)
        #expect(engine.readingText == "ㄋㄧ")
        #expect(engine.displayedCandidates.isEmpty)
        #expect(engine.handleSoftKey("BACKSPACE") == .update)
        #expect(engine.handleSoftKey("BACKSPACE") == .update)
        #expect(engine.readingText.isEmpty)
        #expect(engine.handleSoftKey("BACKSPACE") == .delete)
    }

    @Test("escape clears reading and candidates")
    func escapeClears() {
        let engine = engine()
        _ = type(engine, "su3")
        #expect(engine.handleSoftKey("ESCAPE") == .update)
        #expect(engine.readingText.isEmpty)
        #expect(engine.displayedCandidates.isEmpty)
    }

    @Test("enter with nothing composed sends a return")
    func enterSendsReturn() {
        #expect(engine().handleSoftKey("ENTER") == .returnKey)
    }

    @Test("enter selects the highlighted candidate")
    func enterSelectsHighlight() {
        let engine = engine()
        _ = type(engine, "su3")
        engine.moveHighlight(by: 2)
        #expect(engine.handleSoftKey("ENTER") == .commit("擬"))
    }

    // MARK: Paging

    @Test("paging is cyclic and resets the highlight")
    func cyclicPaging() {
        let many = (1...21).map(String.init)
        let engine = engine(["su3": many])
        _ = type(engine, "su3")
        #expect(engine.pageCount == 3)
        #expect(engine.displayedCandidates.count == 9)

        engine.changePage(by: -1)
        #expect(engine.page == 2)
        #expect(engine.displayedCandidates == ["19", "20", "21"])
        #expect(engine.highlightedIndex == 0)

        engine.changePage(by: 1)
        #expect(engine.page == 0)
        #expect(engine.displayedCandidates.first == "1")
    }

    @Test("space pages through an open candidate list")
    func spacePages() {
        let engine = engine(["su3": (1...21).map(String.init)])
        _ = type(engine, "su3")
        #expect(engine.handleSoftKey("SPACE") == .update)
        #expect(engine.page == 1)
    }

    @Test("highlight movement wraps across pages and the whole list")
    func highlightWraps() {
        let engine = engine(["su3": (1...21).map(String.init)])
        _ = type(engine, "su3")
        engine.moveHighlight(by: -1)
        #expect(engine.page == 2)
        #expect(engine.highlightedIndex == 2)  // the 21st candidate
        engine.moveHighlight(by: 1)
        #expect(engine.page == 0)
        #expect(engine.highlightedIndex == 0)
    }

    // MARK: Modes

    @Test("the mode key cycles Bopomofo, English, number")
    func modeCycles() {
        let engine = engine()
        #expect(engine.inputMode == .bopomofo)
        _ = engine.handleSoftKey("MODE")
        #expect(engine.inputMode == .english)
        _ = engine.handleSoftKey("MODE")
        #expect(engine.inputMode == .number)
        _ = engine.handleSoftKey("MODE")
        #expect(engine.inputMode == .bopomofo)
    }

    @Test("a restricted mode cycle skips Bopomofo")
    func restrictedModeCycle() {
        let engine = engine()
        engine.setAllowedInputModes([.english, .number], preferred: .english,
                                    selectPreferred: true)
        #expect(engine.inputMode == .english)
        _ = engine.handleSoftKey("MODE")
        #expect(engine.inputMode == .number)
        _ = engine.handleSoftKey("MODE")
        #expect(engine.inputMode == .english)
    }

    @Test("hardware language shortcut alternates Bopomofo and English")
    func hardwareLanguageShortcut() {
        let engine = engine()

        _ = engine.toggleHardwareLanguage()
        #expect(engine.inputMode == .english)
        #expect(engine.handleHardwareCharacter("A") == .commit("A"))
        _ = engine.toggleHardwareLanguage()
        #expect(engine.inputMode == .bopomofo)
    }

    @Test("shift on the Bopomofo plane is a one-shot lower-case English")
    func oneShotEnglish() {
        let engine = engine()
        _ = engine.handleSoftKey("SHIFT")
        #expect(engine.inputMode == .english)
        #expect(engine.isTemporaryEnglish)

        #expect(engine.handleSoftKey("a") == .commit("a"))
        #expect(engine.inputMode == .bopomofo)
        #expect(!engine.isTemporaryEnglish)
    }

    @Test("shift latches in English mode and uppercases letters")
    func englishShiftLatches() {
        let engine = engine()
        _ = engine.handleSoftKey("MODE")
        #expect(engine.handleSoftKey("a") == .commit("a"))
        _ = engine.handleSoftKey("SHIFT")
        #expect(engine.isShifted)
        #expect(engine.handleSoftKey("a") == .commit("A"))
        #expect(engine.isShifted, "English shift must not clear after one letter")
    }

    @Test("shift in number mode stays in number mode")
    func numberShiftStays() {
        let engine = engine()
        _ = engine.handleSoftKey("MODE")
        _ = engine.handleSoftKey("MODE")
        #expect(engine.inputMode == .number)
        _ = engine.handleSoftKey("SHIFT")
        #expect(engine.inputMode == .number)
        #expect(engine.isShifted)
    }

    @Test("number mode commits the key as given")
    func numberModeCommits() {
        let engine = engine()
        _ = engine.handleSoftKey("MODE")
        _ = engine.handleSoftKey("MODE")
        #expect(engine.handleSoftKey("7") == .commit("7"))
        #expect(engine.handleSoftKey("＄") == .commit("＄"))
    }

    // MARK: Symbol and emoji panels

    @Test(
        "the symbol and emoji panels are ten pages of nine",
        arguments: ["SYMBOL", "EMOJI"]
    )
    func panels(key: String) {
        let engine = engine()
        #expect(engine.handleSoftKey(key) == .update)
        #expect(engine.pageCount == 10)
        #expect(engine.displayedCandidates.count == 9)
        engine.changePage(by: -1)
        #expect(engine.page == 9)
    }

    @Test("hardware symbol and punctuation shortcuts preserve an active reading")
    func hardwareShortcutsPreserveReading() {
        let engine = engine()
        _ = engine.handleHardwareCharacter("s")

        #expect(engine.commitHardwarePunctuation("，") == .update)
        #expect(engine.showHardwareSymbols() == .update)
        #expect(engine.readingText == "ㄋ")
        #expect(engine.displayedCandidates.isEmpty)
    }

    /// Selecting a symbol does go on to ask for associated phrases, exactly as
    /// the Android engine does. Nothing comes back because the cooked
    /// dictionary only contains words whose first character is Han -- the
    /// invariant lives in the data, not here, so do not "fix" the engine to
    /// gate on the panel kind.
    @Test("a symbol commits and the dictionary offers no phrases for it")
    func symbolCommits() {
        let engine = engine(phrases: ["你": ["好"]])
        _ = engine.handleSoftKey("SYMBOL")
        #expect(engine.selectDisplayedCandidate(0) == .commit("，"))
        #expect(!engine.isShowingAssociatedPhrases)
        #expect(engine.displayedCandidates.isEmpty)
    }

    // MARK: Associated phrases

    @Test("associated phrases open after committing a character")
    func associatedPhrasesOpen() {
        let engine = engine(phrases: ["你": ["好", "們", "的"]])
        _ = type(engine, "su3")
        #expect(engine.selectDisplayedCandidate(0) == .commit("你"))
        #expect(engine.isShowingAssociatedPhrases)
        #expect(engine.displayedCandidates == ["好", "們", "的"])
    }

    @Test("selecting an associated phrase commits only the suffix and stops")
    func associatedPhraseCommitsSuffix() {
        let engine = engine(phrases: ["你": ["好"], "好": ["嗎"]])
        _ = type(engine, "su3")
        _ = engine.selectDisplayedCandidate(0)
        #expect(engine.selectDisplayedCandidate(0) == .commit("好"))
        #expect(!engine.isShowingAssociatedPhrases, "must not chain another round")
        #expect(engine.displayedCandidates.isEmpty)
    }

    @Test("enter dismisses associated phrases and sends return")
    func enterDismissesAssociatedPhrasesAndSendsReturn() {
        let engine = engine(phrases: ["你": ["好", "們"]])
        _ = type(engine, "su3")
        _ = engine.selectDisplayedCandidate(0)
        engine.moveHighlight(by: 1)

        #expect(engine.handleSoftKey("ENTER") == .returnKey)
        #expect(!engine.isShowingAssociatedPhrases)
        #expect(engine.displayedCandidates.isEmpty)
        #expect(engine.readingText.isEmpty)
    }

    @Test("a new reading dismisses associated phrases without committing one")
    func newReadingDismissesPhrases() {
        let engine = engine(phrases: ["你": ["好", "們"]])
        _ = type(engine, "su3")
        _ = engine.selectDisplayedCandidate(0)
        #expect(engine.isShowingAssociatedPhrases)

        let result = engine.handleSoftKey("s")
        #expect(result == .update, "must not commit a phrase")
        #expect(engine.readingText == "ㄋ")
        #expect(!engine.isShowingAssociatedPhrases)
    }

    @Test("an unshifted hardware number starts a reading over associated phrases")
    func hardwareDigitDoesNotSelectAssociatedPhrase() {
        let engine = engine(phrases: ["你": ["好", "們"]])
        _ = type(engine, "su3")
        _ = engine.selectDisplayedCandidate(0)

        #expect(engine.handleHardwareCharacter("2") == .update)
        #expect(engine.readingText == "ㄉ")
        #expect(engine.displayedCandidates.isEmpty)
    }

    @Test("associated phrases need a source")
    func noPhraseSource() {
        let engine = engine()
        _ = type(engine, "su3")
        #expect(engine.selectDisplayedCandidate(0) == .commit("你"))
        #expect(!engine.isShowingAssociatedPhrases)
    }

    @Test("reset returns to Bopomofo from temporary English")
    func resetLeavesTemporaryEnglish() {
        let engine = engine()
        _ = engine.handleSoftKey("SHIFT")
        engine.reset()
        #expect(engine.inputMode == .bopomofo)
        #expect(!engine.isTemporaryEnglish)
    }
}
