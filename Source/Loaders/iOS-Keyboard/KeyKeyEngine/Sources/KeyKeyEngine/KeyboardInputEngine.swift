// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
import Foundation

/// One required Rust session, with frontend-owned host transaction boundaries.
/// Construction errors propagate to the caller; there is no alternate engine.
public final class KeyboardInputEngine: InputEngine {
    private let backend: GuanyinmaInputEngine
    private var phraseSource: SharedPhrasePublication?
    private var phraseRefreshPending = false
    private var pendingHostEffects = false
    private var publicationError: Error?
    public private(set) var coreError: String?

    public init(modelURL: URL, userDatabaseURL: URL, method: ChineseInputMethod = .smart,
                hardwareSmartEditing: Bool = false, keyboardLayout: BopomofoKeyboardLayout = .standard,
                tableOptions: TableInputOptions = TableInputOptions(method: .cangjie),
                spaceSelectsCandidates: Bool = false, associatedPhrases: AssociatedPhraseSource? = nil,
                candidateFilter: @escaping (String) -> Bool = { _ in true }) throws {
        backend = try GuanyinmaInputEngine(modelURL: modelURL, userDatabaseURL: userDatabaseURL,
            method: method, hardwareSmartEditing: hardwareSmartEditing, keyboardLayout: keyboardLayout,
            tableOptions: tableOptions, spaceSelectsCandidates: spaceSelectsCandidates,
            associatedPhrases: associatedPhrases, candidateFilter: candidateFilter)
    }

    /// Called only after the original host accepted the returned effects.
    public func acknowledgeHostEffects() { pendingHostEffects = false; refreshIfReady() }
    private var safeToRefresh: Bool {
        !pendingHostEffects && !backend.hasComposition && backend.displayedCandidates.isEmpty
    }
    private func refreshIfReady() {
        guard phraseRefreshPending && safeToRefresh else { return }
        do {
            try backend.refreshUserPhrases(from: phraseSource)
            phraseRefreshPending = false
            publicationError = nil
        } catch { publicationError = error }
        updateError()
    }
    private func updateError() {
        coreError = (backend.lastError ?? publicationError).map { "Guanyinma：\($0.localizedDescription)" }
    }
    @discardableResult private func perform(_ action: (GuanyinmaInputEngine) -> KeyboardInput.Result) -> KeyboardInput.Result {
        refreshIfReady()
        let result = action(backend)
        pendingHostEffects = pendingHostEffects || !result.text.isEmpty || result.deletesBackward || result.sendsReturn
        updateError()
        return result
    }
    private func performUpdate(_ action: (GuanyinmaInputEngine) -> Void) {
        refreshIfReady(); action(backend); updateError(); refreshIfReady()
    }
    @discardableResult private func performSelection(_ action: (GuanyinmaInputEngine) -> Bool) -> Bool {
        refreshIfReady(); let result = action(backend); updateError(); return result
    }
    public func refreshUserPhrases(from source: SharedPhrasePublication?) throws {
        phraseSource = source
        phraseRefreshPending = true
        if safeToRefresh {
            do {
                try backend.refreshUserPhrases(from: source)
                phraseRefreshPending = false
                publicationError = nil
                updateError()
            } catch { publicationError = error; updateError(); throw error }
        }
    }
    public func resetLearning() throws { try backend.resetLearning() }
    public var chineseInputMethod: ChineseInputMethod { backend.chineseInputMethod }
    public var tableOptions: TableInputOptions { get { backend.tableOptions } set { performUpdate { $0.tableOptions = newValue } } }
    public var spaceSelectsCandidates: Bool { get { backend.spaceSelectsCandidates } set { performUpdate { $0.spaceSelectsCandidates = newValue } } }
    public var keyboardLayout: BopomofoKeyboardLayout { backend.keyboardLayout }
    public var readingText: String { backend.readingText }
    public var composingText: String { backend.composingText }
    public var hasComposition: Bool { backend.hasComposition }
    public var completedSmartText: String { backend.completedSmartText }
    public var isTouchSmartComposition: Bool { backend.isTouchSmartComposition }
    public var smartCompositionCursor: Int? { backend.smartCompositionCursor }
    public var smartCompositionReadingCount: Int { backend.smartCompositionReadingCount }
    public var touchSmartCells: [String] { backend.touchSmartCells }
    public var composingCaretUTF16Offset: Int { backend.composingCaretUTF16Offset }
    public var bopomofoCompositionMode: BopomofoCompositionMode { backend.bopomofoCompositionMode }
    public var isShowingSmartCandidates: Bool { backend.isShowingSmartCandidates }
    public var inputMode: KeyboardInput.InputMode { backend.inputMode }
    public var isShifted: Bool { backend.isShifted }
    public var isTemporaryEnglish: Bool { backend.isTemporaryEnglish }
    public var isShowingAssociatedPhrases: Bool { backend.isShowingAssociatedPhrases }
    public var page: Int { backend.page }
    public var pageCount: Int { backend.pageCount }
    public var displayedCandidates: [String] { backend.displayedCandidates }
    public var highlightedIndex: Int { backend.highlightedIndex }
    @discardableResult public func restoreInputModeState(_ state: InputEngineModeState) -> Bool {
        performSelection { $0.restoreInputModeState(state) }
    }
    public func setAssociatedPhraseSource(_ source: AssociatedPhraseSource?) { backend.setAssociatedPhraseSource(source); updateError() }
    @discardableResult public func setChineseInputMethod(_ method: ChineseInputMethod) -> KeyboardInput.Result { perform { $0.setChineseInputMethod(method) } }
    @discardableResult public func setKeyboardLayout(_ layout: BopomofoKeyboardLayout) -> KeyboardInput.Result { perform { $0.setKeyboardLayout(layout) } }
    @discardableResult public func setCompositionMode(_ mode: BopomofoCompositionMode) -> KeyboardInput.Result { perform { $0.setCompositionMode(mode) } }
    public func setAllowedInputModes(_ allowed: Set<KeyboardInput.InputMode>, preferred: KeyboardInput.InputMode, selectPreferred: Bool = false) {
        performUpdate { $0.setAllowedInputModes(allowed, preferred: preferred, selectPreferred: selectPreferred) }
    }
    @discardableResult public func selectTouchSmartCell(_ index: Int) -> Bool { performSelection { $0.selectTouchSmartCell(index) } }
    @discardableResult public func handleSoftKey(_ key: String) -> KeyboardInput.Result { perform { $0.handleSoftKey(key) } }
    @discardableResult public func handleHardwareCharacter(_ key: Character) -> KeyboardInput.Result { perform { $0.handleHardwareCharacter(key) } }
    @discardableResult public func toggleHardwareLanguage() -> KeyboardInput.Result { perform { $0.toggleHardwareLanguage() } }
    @discardableResult public func showHardwareSymbols() -> KeyboardInput.Result { perform { $0.showHardwareSymbols() } }
    @discardableResult public func commitHardwarePunctuation(_ punctuation: String) -> KeyboardInput.Result { perform { $0.commitHardwarePunctuation(punctuation) } }
    @discardableResult public func space(fullWidth: Bool = false) -> KeyboardInput.Result { perform { $0.space(fullWidth: fullWidth) } }
    @discardableResult public func openSmartCandidates() -> KeyboardInput.Result { perform { $0.openSmartCandidates() } }
    @discardableResult public func enter() -> KeyboardInput.Result { perform { $0.enter() } }
    @discardableResult public func backspace() -> KeyboardInput.Result { perform { $0.backspace() } }
    @discardableResult public func escape() -> KeyboardInput.Result { perform { $0.escape() } }
    @discardableResult public func selectDisplayedCandidate(_ index: Int) -> KeyboardInput.Result { perform { $0.selectDisplayedCandidate(index) } }
    @discardableResult public func selectHighlightedCandidate() -> KeyboardInput.Result { perform { $0.selectHighlightedCandidate() } }
    public func moveHighlight(by delta: Int) { performUpdate { $0.moveHighlight(by: delta) } }
    public func changePage(by delta: Int) { performUpdate { $0.changePage(by: delta) } }
    @discardableResult public func moveSmartCompositionCursor(by delta: Int) -> Bool { performSelection { $0.moveSmartCompositionCursor(by: delta) } }
    public func reset() { performUpdate { $0.reset() } }
    @discardableResult public func finishCompositionForInputHandoff() -> KeyboardInput.Result { perform { $0.finishCompositionForInputHandoff() } }
}
