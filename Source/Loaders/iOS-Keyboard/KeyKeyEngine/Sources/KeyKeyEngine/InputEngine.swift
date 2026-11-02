// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
import Foundation

/// Keyboard-plane state is frontend data; restoring it does not replay a key.
public struct InputEngineModeState: Equatable, Sendable {
    public let mode: KeyboardInput.InputMode
    public let shifted: Bool
    public let temporaryEnglish: Bool
    public init(mode: KeyboardInput.InputMode, shifted: Bool = false, temporaryEnglish: Bool = false) {
        self.mode = mode; self.shifted = shifted; self.temporaryEnglish = temporaryEnglish
    }
}

/// The frontend contract implemented by the required Guanyinma adapter.
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
    var inputMode: KeyboardInput.InputMode { get }
    var isShifted: Bool { get }
    var isTemporaryEnglish: Bool { get }
    var isShowingAssociatedPhrases: Bool { get }
    var page: Int { get }
    var pageCount: Int { get }
    var displayedCandidates: [String] { get }
    var highlightedIndex: Int { get }
    @discardableResult func restoreInputModeState(_ state: InputEngineModeState) -> Bool
    func setAssociatedPhraseSource(_ source: AssociatedPhraseSource?)
    @discardableResult func setChineseInputMethod(_ method: ChineseInputMethod) -> KeyboardInput.Result
    @discardableResult func setKeyboardLayout(_ layout: BopomofoKeyboardLayout) -> KeyboardInput.Result
    @discardableResult func setCompositionMode(_ mode: BopomofoCompositionMode) -> KeyboardInput.Result
    func setAllowedInputModes(_ allowed: Set<KeyboardInput.InputMode>, preferred: KeyboardInput.InputMode, selectPreferred: Bool)
    @discardableResult func selectTouchSmartCell(_ index: Int) -> Bool
    @discardableResult func handleSoftKey(_ key: String) -> KeyboardInput.Result
    @discardableResult func handleHardwareCharacter(_ key: Character) -> KeyboardInput.Result
    @discardableResult func toggleHardwareLanguage() -> KeyboardInput.Result
    @discardableResult func showHardwareSymbols() -> KeyboardInput.Result
    @discardableResult func commitHardwarePunctuation(_ punctuation: String) -> KeyboardInput.Result
    @discardableResult func space(fullWidth: Bool) -> KeyboardInput.Result
    @discardableResult func openSmartCandidates() -> KeyboardInput.Result
    @discardableResult func enter() -> KeyboardInput.Result
    @discardableResult func backspace() -> KeyboardInput.Result
    @discardableResult func escape() -> KeyboardInput.Result
    @discardableResult func selectDisplayedCandidate(_ index: Int) -> KeyboardInput.Result
    @discardableResult func selectHighlightedCandidate() -> KeyboardInput.Result
    func moveHighlight(by delta: Int)
    func changePage(by delta: Int)
    @discardableResult func moveSmartCompositionCursor(by delta: Int) -> Bool
    func reset()
    @discardableResult func finishCompositionForInputHandoff() -> KeyboardInput.Result
}

public extension InputEngine {
    var inputModeState: InputEngineModeState {
        InputEngineModeState(mode: inputMode, shifted: isShifted, temporaryEnglish: isTemporaryEnglish)
    }
}
