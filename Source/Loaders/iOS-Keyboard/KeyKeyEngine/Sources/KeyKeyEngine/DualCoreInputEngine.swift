// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
import Foundation

/// One frontend and two independent backends. A backend changes only after
/// composition, candidate interaction and the previous host transaction finish.
public final class DualCoreInputEngine: InputEngine {
    private let legacy: BopomofoEngine
    private var rust: GuanyinmaInputEngine?
    private let modelURL: URL
    private let userDatabaseURL: URL
    private let hardwareSmartEditing: Bool
    private let candidateFilter: (String) -> Bool
    private var associatedSource: AssociatedPhraseSource?
    private var phraseSource: SmartMandarinUserData?
    private var phraseRefreshPending = false
    private var pendingHostEffects = false
    private var allowedModes = Set(BopomofoEngine.InputMode.allCases)
    public private(set) var activeCore: InputCore = .swift
    public private(set) var requestedCore: InputCore
    public private(set) var coreError: String?
    private var backend: any InputEngine { activeCore == .swift ? legacy : rust! }

    public init(legacy: BopomofoEngine, modelURL: URL, userDatabaseURL: URL,
                preferredCore: InputCore = .swift, hardwareSmartEditing: Bool = false,
                associatedPhrases: AssociatedPhraseSource? = nil,
                candidateFilter: @escaping (String) -> Bool = { _ in true }) {
        self.legacy = legacy
        self.modelURL = modelURL
        self.userDatabaseURL = userDatabaseURL
        self.requestedCore = preferredCore
        self.hardwareSmartEditing = hardwareSmartEditing
        self.associatedSource = associatedPhrases
        self.candidateFilter = candidateFilter
        switchIfReady()
    }

    public func requestCore(_ core: InputCore) {
        requestedCore = core
        if core == .swift && activeCore == .swift { coreError = nil }
        switchIfReady()
    }

    /// The frontend calls this after applying the returned text/delete/return
    /// to the original host. No input event or host effect is replayed.
    public func acknowledgeHostEffects() { pendingHostEffects = false; switchIfReady() }

    private var safeToSwitch: Bool {
        !pendingHostEffects && !backend.hasComposition && backend.displayedCandidates.isEmpty
    }
    private func switchIfReady() {
        guard safeToSwitch else { return }
        do {
            if requestedCore == .guanyinma {
                if rust == nil {
                    rust = try GuanyinmaInputEngine(modelURL: modelURL, userDatabaseURL: userDatabaseURL,
                        method: legacy.chineseInputMethod, hardwareSmartEditing: hardwareSmartEditing,
                        keyboardLayout: legacy.keyboardLayout, tableOptions: legacy.tableOptions,
                        spaceSelectsCandidates: legacy.spaceSelectsCandidates,
                        associatedPhrases: associatedSource, candidateFilter: candidateFilter)
                }
                if phraseRefreshPending { try rust?.refreshUserPhrases(from: phraseSource); phraseRefreshPending = false }
            }
            guard requestedCore != activeCore else { return }
            let method = backend.chineseInputMethod
            let layout = backend.keyboardLayout
            let table = backend.tableOptions
            let space = backend.spaceSelectsCandidates
            let modeState = backend.inputModeState
            let previousCore = activeCore
            activeCore = requestedCore
            _ = backend.setChineseInputMethod(method)
            _ = backend.setKeyboardLayout(layout)
            backend.tableOptions = table
            backend.spaceSelectsCandidates = space
            backend.setAssociatedPhraseSource(associatedSource)
            backend.setAllowedInputModes(allowedModes, preferred: modeState.mode, selectPreferred: true)
            guard backend.restoreInputModeState(modeState) else {
                activeCore = previousCore
                throw GuanyinmaInputError(message: "無法在安全邊界還原鍵盤模式。")
            }
            coreError = nil
        } catch {
            // Opening/synchronizing a new backend can fall back before any
            // event reaches it; a live session never silently changes cores.
            coreError = "Guanyinma 無法啟用：\(error.localizedDescription)"
        }
    }
    private func updateError() {
        if activeCore == .guanyinma { coreError = rust?.lastError.map { "Guanyinma：\($0.localizedDescription)" } }
    }
    @discardableResult private func perform(_ action: (any InputEngine) -> BopomofoEngine.Result) -> BopomofoEngine.Result {
        switchIfReady()
        let result = action(backend)
        pendingHostEffects = pendingHostEffects || !result.text.isEmpty || result.deletesBackward || result.sendsReturn
        updateError()
        return result
    }
    private func performUpdate(_ action: (any InputEngine) -> Void) { switchIfReady(); action(backend); updateError(); switchIfReady() }
    @discardableResult private func performSelection(_ action: (any InputEngine) -> Bool) -> Bool {
        switchIfReady(); let result = action(backend); updateError(); return result
    }
    public func refreshUserPhrases(from source: SmartMandarinUserData?) throws {
        phraseSource = source
        phraseRefreshPending = true
        if safeToSwitch, let rust {
            try rust.refreshUserPhrases(from: source)
            phraseRefreshPending = false
        }
    }
    public func resetActiveCoreLearning() throws {
        if activeCore == .guanyinma { try rust?.resetLearning() }
    }
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
    public var inputMode: BopomofoEngine.InputMode { backend.inputMode }
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
    public func setTableCandidateSource(_ source: TableCandidateSource) { legacy.setTableCandidateSource(source) }
    public func setAssociatedPhraseSource(_ source: AssociatedPhraseSource?) { associatedSource = source; legacy.setAssociatedPhraseSource(source); rust?.setAssociatedPhraseSource(source) }
    @discardableResult public func setChineseInputMethod(_ method: ChineseInputMethod) -> BopomofoEngine.Result { perform { $0.setChineseInputMethod(method) } }
    @discardableResult public func setKeyboardLayout(_ layout: BopomofoKeyboardLayout) -> BopomofoEngine.Result { perform { $0.setKeyboardLayout(layout) } }
    @discardableResult public func setCompositionMode(_ mode: BopomofoCompositionMode) -> BopomofoEngine.Result { perform { $0.setCompositionMode(mode) } }
    public func setAllowedInputModes(_ allowed: Set<BopomofoEngine.InputMode>, preferred: BopomofoEngine.InputMode, selectPreferred: Bool = false) {
        allowedModes = allowed.isEmpty ? Set(BopomofoEngine.InputMode.allCases) : allowed
        performUpdate { $0.setAllowedInputModes(allowed, preferred: preferred, selectPreferred: selectPreferred) }
    }
    @discardableResult public func selectTouchSmartCell(_ index: Int) -> Bool { performSelection { $0.selectTouchSmartCell(index) } }
    @discardableResult public func handleSoftKey(_ key: String) -> BopomofoEngine.Result { perform { $0.handleSoftKey(key) } }
    @discardableResult public func handleHardwareCharacter(_ key: Character) -> BopomofoEngine.Result { perform { $0.handleHardwareCharacter(key) } }
    @discardableResult public func toggleHardwareLanguage() -> BopomofoEngine.Result { perform { $0.toggleHardwareLanguage() } }
    @discardableResult public func showHardwareSymbols() -> BopomofoEngine.Result { perform { $0.showHardwareSymbols() } }
    @discardableResult public func commitHardwarePunctuation(_ punctuation: String) -> BopomofoEngine.Result { perform { $0.commitHardwarePunctuation(punctuation) } }
    @discardableResult public func space(fullWidth: Bool = false) -> BopomofoEngine.Result { perform { $0.space(fullWidth: fullWidth) } }
    @discardableResult public func openSmartCandidates() -> BopomofoEngine.Result { perform { $0.openSmartCandidates() } }
    @discardableResult public func enter() -> BopomofoEngine.Result { perform { $0.enter() } }
    @discardableResult public func backspace() -> BopomofoEngine.Result { perform { $0.backspace() } }
    @discardableResult public func escape() -> BopomofoEngine.Result { perform { $0.escape() } }
    @discardableResult public func selectDisplayedCandidate(_ index: Int) -> BopomofoEngine.Result { perform { $0.selectDisplayedCandidate(index) } }
    @discardableResult public func selectHighlightedCandidate() -> BopomofoEngine.Result { perform { $0.selectHighlightedCandidate() } }
    public func moveHighlight(by delta: Int) { performUpdate { $0.moveHighlight(by: delta) } }
    public func changePage(by delta: Int) { performUpdate { $0.changePage(by: delta) } }
    @discardableResult public func moveSmartCompositionCursor(by delta: Int) -> Bool { performSelection { $0.moveSmartCompositionCursor(by: delta) } }
    public func reset() { performUpdate { $0.reset() } }
    @discardableResult public func finishCompositionForInputHandoff() -> BopomofoEngine.Result { perform { $0.finishCompositionForInputHandoff() } }
}
