// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
import Foundation

/// Keyboard-plane state is independent of the selected algorithm. It is moved
/// between idle backends as data, without replaying a keyboard gesture.
public struct InputEngineModeState: Equatable, Sendable {
    public let mode: BopomofoEngine.InputMode
    public let shifted: Bool
    public let temporaryEnglish: Bool
    public init(mode: BopomofoEngine.InputMode, shifted: Bool = false, temporaryEnglish: Bool = false) {
        self.mode = mode; self.shifted = shifted; self.temporaryEnglish = temporaryEnglish
    }
}

/// The frontend contract shared by the existing Swift core and Guanyinma.
/// Native events and document transactions remain in the UIKit frontend.
public protocol InputEngine: AnyObject {
    var chineseInputMethod: ChineseInputMethod { get }
    var tableOptions: TableInputOptions { get set }
    var spaceSelectsCandidates: Bool { get set }
    var keyboardLayout: BopomofoKeyboardLayout { get }
    var readingText: String { get }
    var composingText: String { get }
    var hasComposition: Bool { get }
    var completedSmartText: String { get }
    var isTouchSmartComposition: Bool { get }
    var smartCompositionCursor: Int? { get }
    var smartCompositionReadingCount: Int { get }
    var touchSmartCells: [String] { get }
    var composingCaretUTF16Offset: Int { get }
    var bopomofoCompositionMode: BopomofoCompositionMode { get }
    var isShowingSmartCandidates: Bool { get }
    var inputMode: BopomofoEngine.InputMode { get }
    var isShifted: Bool { get }
    var isTemporaryEnglish: Bool { get }
    var isShowingAssociatedPhrases: Bool { get }
    var page: Int { get }
    var pageCount: Int { get }
    var displayedCandidates: [String] { get }
    var highlightedIndex: Int { get }
    @discardableResult func restoreInputModeState(_ state: InputEngineModeState) -> Bool
    func setTableCandidateSource(_ source: TableCandidateSource)
    func setAssociatedPhraseSource(_ source: AssociatedPhraseSource?)
    @discardableResult func setChineseInputMethod(_ method: ChineseInputMethod) -> BopomofoEngine.Result
    @discardableResult func setKeyboardLayout(_ layout: BopomofoKeyboardLayout) -> BopomofoEngine.Result
    @discardableResult func setCompositionMode(_ mode: BopomofoCompositionMode) -> BopomofoEngine.Result
    func setAllowedInputModes(_ allowed: Set<BopomofoEngine.InputMode>, preferred: BopomofoEngine.InputMode, selectPreferred: Bool)
    @discardableResult func selectTouchSmartCell(_ index: Int) -> Bool
    @discardableResult func handleSoftKey(_ key: String) -> BopomofoEngine.Result
    @discardableResult func handleHardwareCharacter(_ key: Character) -> BopomofoEngine.Result
    @discardableResult func toggleHardwareLanguage() -> BopomofoEngine.Result
    @discardableResult func showHardwareSymbols() -> BopomofoEngine.Result
    @discardableResult func commitHardwarePunctuation(_ punctuation: String) -> BopomofoEngine.Result
    @discardableResult func space(fullWidth: Bool) -> BopomofoEngine.Result
    @discardableResult func openSmartCandidates() -> BopomofoEngine.Result
    @discardableResult func enter() -> BopomofoEngine.Result
    @discardableResult func backspace() -> BopomofoEngine.Result
    @discardableResult func escape() -> BopomofoEngine.Result
    @discardableResult func selectDisplayedCandidate(_ index: Int) -> BopomofoEngine.Result
    @discardableResult func selectHighlightedCandidate() -> BopomofoEngine.Result
    func moveHighlight(by delta: Int)
    func changePage(by delta: Int)
    @discardableResult func moveSmartCompositionCursor(by delta: Int) -> Bool
    func reset()
    @discardableResult func finishCompositionForInputHandoff() -> BopomofoEngine.Result
}

public extension InputEngine {
    var inputModeState: InputEngineModeState {
        InputEngineModeState(mode: inputMode, shifted: isShifted, temporaryEnglish: isTemporaryEnglish)
    }
}

extension BopomofoEngine: InputEngine {}

public enum InputCore: String, CaseIterable, Sendable {
    case swift, guanyinma
    public var displayName: String {
        self == .swift ? "Swift（原核心）" : "Guanyinma（Rust）"
    }
}
