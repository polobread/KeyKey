// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
import Foundation
import CGuanyinma

public struct GuanyinmaInputError: Error, LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
}

private final class GuanyinmaGlyphContext {
    let accepts: (String) -> Bool
    init(_ accepts: @escaping (String) -> Bool) { self.accepts = accepts }
}

/// The native adapter owns C handles and translates coordinates and host effects.
/// It contains no alternate walker, candidate ranking or phonetic parser.
public final class GuanyinmaInputEngine: InputEngine {
    private struct Effects: Decodable {
        let commit: String
        let handled: Bool
        let deleteBackward: Bool
        let sendReturn: Bool
    }
    private struct Segment: Decodable { let start: Int; let span: Int; let text: String }
    private struct CandidateSpan: Decodable { let start: Int; let span: Int }
    private struct Snapshot: Decodable {
        let schemaVersion: Int
        let kind: String
        let method: String
        let english: Bool
        let composition: String
        let visibleText: String
        let reading: String
        let readings: [String]
        let readingCursor: Int
        let cursor: Int
        let segments: [Segment]
        let candidateSpans: [CandidateSpan]
        let candidates: [String]
        let displayedCandidates: [String]
        let page: Int
        let pageCount: Int
        let highlight: Int?
        let effects: Effects
    }
    private enum Overlay { case none, symbols, associated }
    private var session: OpaquePointer?
    private let glyphContext: GuanyinmaGlyphContext
    private let hardwareSmartEditing: Bool
    private var snapshot: Snapshot!
    private var associatedSource: AssociatedPhraseSource?
    private var overlay: Overlay = .none
    private var overlayCandidates: [String] = []
    private var overlayPage = 0
    private var overlayHighlight = 0
    private var allowedModes = Set(BopomofoEngine.InputMode.allCases)
    private var mode = BopomofoEngine.InputMode.bopomofo
    private var shifted = false
    private var temporaryEnglish = false
    private var options: TableInputOptions
    public private(set) var lastError: Error?
    public private(set) var keyboardLayout: BopomofoKeyboardLayout
    public var chineseInputMethod: ChineseInputMethod { ChineseInputMethod(rawValue: snapshot.method) ?? .traditional }
    public var tableOptions: TableInputOptions {
        get { options }
        set {
            guard newValue != options else { return }
            guard !hasComposition else {
                lastError = GuanyinmaInputError(message: "請先完成組字後再變更字表設定。")
                return
            }
            let old = options
            options = newValue
            if chineseInputMethod.isTable {
                do { _ = try apply(["type": "set_table_options", "method": chineseInputMethod.rawValue,
                                  "options": Self.tableConfiguration(newValue)]) }
                catch { options = old; lastError = error }
            }
        }
    }
    public var spaceSelectsCandidates: Bool {
        didSet {
            guard oldValue != spaceSelectsCandidates else { return }
            _ = operate(["type": "set_smart_options", "options": smartConfiguration])
        }
    }

    public init(modelURL: URL, userDatabaseURL: URL, method: ChineseInputMethod = .smart,
                hardwareSmartEditing: Bool = false, keyboardLayout: BopomofoKeyboardLayout = .standard,
                tableOptions: TableInputOptions = TableInputOptions(method: .cangjie),
                spaceSelectsCandidates: Bool = false, associatedPhrases: AssociatedPhraseSource? = nil,
                candidateFilter: @escaping (String) -> Bool = { _ in true }) throws {
        self.hardwareSmartEditing = hardwareSmartEditing
        self.keyboardLayout = keyboardLayout
        self.options = tableOptions
        self.spaceSelectsCandidates = spaceSelectsCandidates
        self.associatedSource = associatedPhrases
        glyphContext = GuanyinmaGlyphContext(candidateFilter)
        try FileManager.default.createDirectory(at: userDatabaseURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let smart: [String: Any] = Self.smartConfiguration(hardware: hardwareSmartEditing, space: spaceSelectsCandidates)
        let configuration: [String: Any] = [
            "method": method.rawValue, "profile": hardwareSmartEditing ? "desktop" : "touch",
            "layout": Self.layoutName(keyboardLayout), "user_database": userDatabaseURL.path,
            "traditional_selection_keys": "123456789", "table_selection_keys": "123456789",
            "smart": smart,
            "learning": ["user_phrases": true, "candidate_overrides": true, "bigrams": true, "table_learning": true],
            "cangjie": Self.tableConfiguration(method == .cangjie ? tableOptions : TableInputOptions(method: .cangjie)),
            "simplex": Self.tableConfiguration(method == .simplex ? tableOptions : TableInputOptions(method: .simplex))
        ]
        let model = Array(modelURL.path.utf8)
        let data = try JSONSerialization.data(withJSONObject: configuration)
        var handle: OpaquePointer?
        let context = Unmanaged.passUnretained(glyphContext).toOpaque()
        let status = model.withUnsafeBufferPointer { path in
            data.withUnsafeBytes { bytes in
                guanyinma_session_open_with_candidate_filter(path.baseAddress, path.count,
                    bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count,
                    { context, text, count in
                        guard let context, let text else { return 0 }
                        let box = Unmanaged<GuanyinmaGlyphContext>.fromOpaque(context).takeUnretainedValue()
                        guard let value = String(bytes: UnsafeBufferPointer(start: text, count: count), encoding: .utf8) else { return 0 }
                        return box.accepts(value) ? 1 : 0
                    }, context, &handle)
            }
        }
        guard status == 0, let opened = handle else { throw Self.failure(status) }
        session = opened
        do {
            var result: OpaquePointer?
            let code = guanyinma_session_snapshot(opened, &result)
            guard code == 0 else { throw Self.failure(code) }
            snapshot = try Self.decode(&result)
        } catch {
            guanyinma_session_close(&handle)
            session = nil
            throw error
        }
    }

    deinit { guanyinma_session_close(&session) }

    private static func layoutName(_ layout: BopomofoKeyboardLayout) -> String { layout == .hsu ? "hsu" : "standard" }
    private static func smartConfiguration(hardware: Bool, space: Bool) -> [String: Any] {
        ["max_completed_syllables": 10, "shift_at_limit": !hardware,
         "selection_returns_to_end": !hardware, "candidate_cursor_at_end": hardware,
         "space_opens_candidates": space, "candidate_selection_keys": "123456789"]
    }
    private var smartConfiguration: [String: Any] {
        Self.smartConfiguration(hardware: hardwareSmartEditing, space: spaceSelectsCandidates)
    }
    private static func tableConfiguration(_ options: TableInputOptions) -> [String: Any] {
        ["realtime": options.composeWhileTyping, "prefix": options.prefixCandidates,
         "clear_on_error": options.clearOnError, "query_at_maximum": options.queryAtMaximum,
         "learn_selection": options.dynamicFrequency,
         "punctuation": options.punctuation == 1 ? "mixed" : options.punctuation == 2 ? "half" : "original"]
    }
    private static func failure(_ code: Int32) -> GuanyinmaInputError {
        var count = 0
        _ = guanyinma_last_error(nil, 0, &count)
        var bytes = [UInt8](repeating: 0, count: max(count, 1))
        let capacity = bytes.count
        _ = guanyinma_last_error(&bytes, capacity, &count)
        let message = String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        return GuanyinmaInputError(message: message.isEmpty ? "Guanyinma 錯誤 \(code)" : message)
    }
    private static func decode(_ result: inout OpaquePointer?) throws -> Snapshot {
        defer { guanyinma_result_close(&result) }
        var required = 0
        let probe = guanyinma_result_json(result, nil, 0, &required)
        guard probe == 5, required > 0, required <= 32 * 1024 * 1024 else { throw failure(probe) }
        var bytes = [UInt8](repeating: 0, count: required)
        let capacity = bytes.count
        let status = guanyinma_result_json(result, &bytes, capacity, &required)
        guard status == 0, required == bytes.count, bytes.last == 0 else { throw failure(status) }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let snapshot = try decoder.decode(Snapshot.self, from: Data(bytes.dropLast()))
        guard snapshot.schemaVersion == 1, snapshot.kind == "session" else {
            throw GuanyinmaInputError(message: "不支援的 Guanyinma session 快照。")
        }
        return snapshot
    }
    private func apply(_ operation: [String: Any]) throws -> BopomofoEngine.Result {
        let data = try JSONSerialization.data(withJSONObject: operation)
        var result: OpaquePointer?
        let code = data.withUnsafeBytes { bytes in
            guanyinma_session_apply(session, bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count, &result)
        }
        guard code == 0 else { throw Self.failure(code) }
        snapshot = try Self.decode(&result)
        lastError = nil
        return BopomofoEngine.Result(text: snapshot.effects.commit,
                                    deletesBackward: snapshot.effects.deleteBackward,
                                    sendsReturn: snapshot.effects.sendReturn)
    }
    @discardableResult private func operate(_ operation: [String: Any]) -> BopomofoEngine.Result {
        do { return try apply(operation) }
        catch { lastError = error; return .update }
    }
    private func key(_ name: String) -> BopomofoEngine.Result { operate(["type": "key", "key": name]) }
    private func clearOverlay() { overlay = .none; overlayCandidates = []; overlayPage = 0; overlayHighlight = 0 }
    private func offeringAssociated(_ result: BopomofoEngine.Result) -> BopomofoEngine.Result {
        guard result.text.count == 1, !hasComposition,
              let source = associatedSource else { return result }
        let values = source.phrases(forHeadCharacter: result.text).filter(glyphContext.accepts)
        if !values.isEmpty { overlay = .associated; overlayCandidates = values; overlayPage = 0; overlayHighlight = 0 }
        return result
    }
    private func direct(_ text: String) -> BopomofoEngine.Result {
        let finished = finishCompositionForInputHandoff()
        guard lastError == nil else { return finished }
        let literal = operate(["type": "direct_text", "text": text])
        return BopomofoEngine.Result(text: finished.text + literal.text,
                                    deletesBackward: literal.deletesBackward, sendsReturn: literal.sendsReturn)
    }

    public var readingText: String { snapshot.reading }
    public var composingText: String { snapshot.visibleText }
    public var hasComposition: Bool { !snapshot.visibleText.isEmpty }
    public var completedSmartText: String { chineseInputMethod == .smart ? snapshot.composition : "" }
    public var isTouchSmartComposition: Bool { chineseInputMethod == .smart && mode == .bopomofo && !hardwareSmartEditing }
    public var smartCompositionCursor: Int? { hardwareSmartEditing && chineseInputMethod == .smart && !snapshot.readings.isEmpty ? snapshot.readingCursor : nil }
    public var smartCompositionReadingCount: Int { snapshot.readings.count }
    public var touchSmartCells: [String] {
        guard isTouchSmartComposition else { return [] }
        var cells = snapshot.segments.flatMap { segment -> [String] in
            let chars = Array(segment.text)
            guard segment.span > 0 else { return [] }
            return (0..<segment.span).map { offset in
                String(chars[(offset * chars.count / segment.span)..<((offset + 1) * chars.count / segment.span)])
            }
        }
        for symbol in snapshot.reading.map(String.init) {
            if cells.count < 11 { cells.append(symbol) } else { cells[10] += symbol }
        }
        return cells
    }
    public var composingCaretUTF16Offset: Int {
        let scalars = snapshot.visibleText.unicodeScalars
        return String(scalars.prefix(snapshot.cursor)).utf16.count
    }
    public var bopomofoCompositionMode: BopomofoCompositionMode { chineseInputMethod == .smart ? .smart : .traditional }
    public var isShowingSmartCandidates: Bool { chineseInputMethod == .smart && overlay == .none && !snapshot.candidates.isEmpty }
    public var inputMode: BopomofoEngine.InputMode { mode }
    public var isShifted: Bool { shifted }
    public var isTemporaryEnglish: Bool { temporaryEnglish }
    public var isShowingAssociatedPhrases: Bool { overlay == .associated }
    public var page: Int { overlay == .none ? snapshot.page : overlayPage }
    public var pageCount: Int { overlay == .none ? snapshot.pageCount : (overlayCandidates.count + 8) / 9 }
    public var displayedCandidates: [String] {
        if overlay == .none { return snapshot.displayedCandidates }
        return Array(overlayCandidates.dropFirst(overlayPage * 9).prefix(9))
    }
    public var highlightedIndex: Int { displayedCandidates.isEmpty ? -1 : overlay == .none ? (snapshot.highlight ?? 0) : overlayHighlight }
    public func setTableCandidateSource(_ source: TableCandidateSource) {}
    public func setAssociatedPhraseSource(_ source: AssociatedPhraseSource?) { associatedSource = source; if overlay == .associated { clearOverlay() } }
    @discardableResult public func setChineseInputMethod(_ method: ChineseInputMethod) -> BopomofoEngine.Result {
        guard method != chineseInputMethod else { return .update }
        clearOverlay()
        let result = operate(["type": "set_method", "method": method.rawValue])
        options = TableInputOptions(method: method)
        return result
    }
    @discardableResult public func setKeyboardLayout(_ layout: BopomofoKeyboardLayout) -> BopomofoEngine.Result {
        guard layout != keyboardLayout else { return .update }
        clearOverlay()
        let result = operate(["type": "set_layout", "layout": Self.layoutName(layout)])
        if lastError == nil { keyboardLayout = layout }
        return result
    }
    @discardableResult public func setCompositionMode(_ mode: BopomofoCompositionMode) -> BopomofoEngine.Result { setChineseInputMethod(mode == .smart ? .smart : .traditional) }
    public func setAllowedInputModes(_ allowed: Set<BopomofoEngine.InputMode>, preferred: BopomofoEngine.InputMode, selectPreferred: Bool = false) {
        allowedModes = allowed.isEmpty ? Set(BopomofoEngine.InputMode.allCases) : allowed
        if selectPreferred || !allowedModes.contains(mode) {
            reset()
            mode = allowedModes.contains(preferred) ? preferred : BopomofoEngine.InputMode.allCases.first(where: allowedModes.contains)!
            _ = operate(["type": "set_english", "enabled": mode != .bopomofo])
        }
    }
    @discardableResult public func restoreInputModeState(_ state: InputEngineModeState) -> Bool {
        guard !hasComposition, displayedCandidates.isEmpty else { return false }
        let target = allowedModes.contains(state.mode)
            ? state.mode : BopomofoEngine.InputMode.allCases.first(where: allowedModes.contains)!
        _ = operate(["type": "set_english", "enabled": target != .bopomofo])
        guard lastError == nil else { return false }
        mode = target
        temporaryEnglish = state.temporaryEnglish && target == .english && allowedModes.contains(.bopomofo)
        shifted = state.shifted && !temporaryEnglish
        return true
    }
    @discardableResult public func selectTouchSmartCell(_ index: Int) -> Bool {
        guard isTouchSmartComposition, snapshot.readings.indices.contains(index) else { return false }
        if snapshot.candidateSpans.first?.start == index, !snapshot.candidates.isEmpty { _ = operate(["type": "close_candidates"]) }
        else { _ = operate(["type": "open_candidates", "index": index]) }
        return lastError == nil
    }
    private func setMode(_ value: BopomofoEngine.InputMode) -> BopomofoEngine.Result {
        clearOverlay(); mode = value
        return operate(["type": "set_english", "enabled": value != .bopomofo])
    }
    private func endTemporaryEnglish() {
        temporaryEnglish = false; shifted = false
        _ = setMode(allowedModes.contains(.bopomofo) ? .bopomofo : BopomofoEngine.InputMode.allCases.first(where: allowedModes.contains)!)
    }
    @discardableResult public func handleSoftKey(_ value: String) -> BopomofoEngine.Result {
        let restore = temporaryEnglish && value != "SHIFT" && value != "MODE"
        let result: BopomofoEngine.Result
        switch value {
        case "MODE":
            if temporaryEnglish {
                temporaryEnglish = false; shifted = false; result = .update
            } else {
                let all = BopomofoEngine.InputMode.allCases
                let start = all.firstIndex(of: mode) ?? 0
                let next = (1...all.count).map { all[(start + $0) % all.count] }.first(where: allowedModes.contains)!
                result = setMode(next); shifted = false
            }
        case "SHIFT":
            if temporaryEnglish { endTemporaryEnglish(); result = .update }
            else if mode == .bopomofo, allowedModes.contains(.english) {
                result = setMode(.english); temporaryEnglish = true; shifted = false
            } else { shifted.toggle(); result = .update }
        case "BACKSPACE": result = backspace()
        case "SPACE": result = space()
        case "ENTER": result = enter()
        case "ESCAPE": result = escape()
        case "SYMBOL": result = showOverlay(BopomofoEngine.symbols)
        case "EMOJI": result = showOverlay(BopomofoEngine.emojis)
        default:
            if value.count == 1 { result = character(value, touch: true) } else { result = .update }
        }
        if restore { endTemporaryEnglish() }
        return result
    }
    private func character(_ raw: String, touch: Bool) -> BopomofoEngine.Result {
        clearOverlay()
        if mode != .bopomofo { return direct(touch && shifted ? raw.uppercased() : raw) }
        if touch, raw == "，" || raw == "。" { return direct(raw) }
        if !touch, let character = raw.first, character.isASCII && character.isUppercase { return direct(raw) }
        guard raw.unicodeScalars.count == 1 else { return direct(raw) }
        return offeringAssociated(operate(["type": "character", "text": raw.lowercased()]))
    }
    @discardableResult public func handleHardwareCharacter(_ key: Character) -> BopomofoEngine.Result {
        if temporaryEnglish { endTemporaryEnglish() }
        if overlay == .symbols, let number = key.wholeNumberValue, (1...9).contains(number) {
            return selectDisplayedCandidate(number - 1)
        }
        if chineseInputMethod.isTable, !displayedCandidates.isEmpty, key == "<" || key == ">" {
            changePage(by: key == "<" ? -1 : 1); return .update
        }
        return character(String(key), touch: false)
    }
    @discardableResult public func toggleHardwareLanguage() -> BopomofoEngine.Result {
        temporaryEnglish = false; shifted = false
        return setMode(mode == .bopomofo ? .english : .bopomofo)
    }
    private func showOverlay(_ values: [String]) -> BopomofoEngine.Result {
        let result = finishCompositionForInputHandoff()
        guard lastError == nil else { return result }
        overlay = .symbols; overlayCandidates = values.filter(glyphContext.accepts); overlayPage = 0; overlayHighlight = 0
        return result
    }
    @discardableResult public func showHardwareSymbols() -> BopomofoEngine.Result {
        if temporaryEnglish { endTemporaryEnglish() }
        guard readingText.isEmpty || chineseInputMethod == .smart else { return .update }
        return showOverlay(BopomofoEngine.symbols)
    }
    @discardableResult public func commitHardwarePunctuation(_ punctuation: String) -> BopomofoEngine.Result {
        guard readingText.isEmpty || chineseInputMethod == .smart else { return .update }
        return direct(punctuation)
    }
    @discardableResult public func space(fullWidth: Bool = false) -> BopomofoEngine.Result {
        if overlay != .none { changePage(by: 1); return .update }
        if !hasComposition { return .commit(fullWidth ? "　" : " ") }
        if fullWidth, chineseInputMethod == .smart, snapshot.reading.isEmpty,
           !spaceSelectsCandidates, snapshot.candidates.isEmpty {
            return operate(["type": "direct_text", "text": "　"])
        }
        return offeringAssociated(key("space"))
    }
    @discardableResult public func openSmartCandidates() -> BopomofoEngine.Result {
        guard chineseInputMethod == .smart, mode == .bopomofo else { return .update }
        if !snapshot.reading.isEmpty { return key("space") }
        if !snapshot.candidates.isEmpty { changePage(by: 1); return .update }
        guard !snapshot.readings.isEmpty else { return .update }
        let index = hardwareSmartEditing ? max(0, snapshot.readingCursor - 1) : snapshot.readings.count - 1
        return operate(["type": "open_candidates", "index": index])
    }
    @discardableResult public func enter() -> BopomofoEngine.Result {
        if overlay == .associated { clearOverlay(); return .returnKey }
        if overlay != .none { return selectHighlightedCandidate() }
        if isTouchSmartComposition, hasComposition {
            let result = finishCompositionForInputHandoff()
            return BopomofoEngine.Result(text: result.text, deletesBackward: result.deletesBackward, sendsReturn: lastError == nil)
        }
        if !hasComposition && displayedCandidates.isEmpty { return .returnKey }
        return offeringAssociated(key("return"))
    }
    @discardableResult public func backspace() -> BopomofoEngine.Result {
        if overlay != .none { clearOverlay() }
        if !hasComposition { return .delete }
        return key("backspace")
    }
    @discardableResult public func escape() -> BopomofoEngine.Result {
        if overlay != .none { clearOverlay(); return .update }
        if !hardwareSmartEditing { reset(); return .update }
        return key("escape")
    }
    @discardableResult public func selectDisplayedCandidate(_ index: Int) -> BopomofoEngine.Result {
        guard displayedCandidates.indices.contains(index) else { return .update }
        if overlay != .none {
            let value = displayedCandidates[index]
            return direct(value)
        }
        return offeringAssociated(operate(["type": "select", "index": index]))
    }
    @discardableResult public func selectHighlightedCandidate() -> BopomofoEngine.Result { selectDisplayedCandidate(highlightedIndex) }
    public func moveHighlight(by delta: Int) {
        if overlay == .none {
            guard !snapshot.candidates.isEmpty else { return }
            let current = snapshot.page * 9 + (snapshot.highlight ?? 0)
            let target = floorMod(current + delta, snapshot.candidates.count)
            _ = operate(["type": "move_highlight", "delta": target - current]); return
        }
        guard !overlayCandidates.isEmpty else { return }
        let index = floorMod(overlayPage * 9 + overlayHighlight + delta, overlayCandidates.count)
        overlayPage = index / 9; overlayHighlight = index % 9
    }
    public func changePage(by delta: Int) {
        if overlay == .none { _ = operate(["type": "page", "delta": delta]); return }
        guard pageCount > 0 else { return }
        overlayPage = floorMod(overlayPage + delta, pageCount); overlayHighlight = 0
    }
    @discardableResult public func moveSmartCompositionCursor(by delta: Int) -> Bool {
        guard smartCompositionCursor != nil, snapshot.reading.isEmpty else { return false }
        _ = operate(["type": "close_candidates"])
        _ = operate(["type": "set_cursor", "index": min(max(snapshot.readingCursor + delta, 0), snapshot.readings.count)])
        return lastError == nil
    }
    public func reset() {
        clearOverlay(); _ = operate(["type": "reset"])
        if temporaryEnglish { endTemporaryEnglish() }
        shifted = false
    }
    @discardableResult public func finishCompositionForInputHandoff() -> BopomofoEngine.Result {
        clearOverlay()
        guard hasComposition else { return .update }
        if chineseInputMethod != .smart, !snapshot.candidates.isEmpty {
            let result = operate(["type": "select", "index": snapshot.highlight ?? 0])
            guard lastError == nil else { return result }
            _ = operate(["type": "reset"])
            return result
        }
        return operate(["type": "finish"])
    }
    private func floorMod(_ value: Int, _ size: Int) -> Int { ((value % size) + size) % size }

    /// Replace the FE-published phrase snapshot atomically without importing
    /// another core's learning or giving an extension shared-container writes.
    public func refreshUserPhrases(from source: SmartMandarinUserData?) throws {
        guard let source else { return }
        guard let rows = try source.guanyinmaPhraseRows() else { return }
        _ = try apply(["type": "replace_user_phrases", "phrases": rows])
    }
    public func resetLearning() throws { _ = try apply(["type": "reset_method_learning", "method": "smart"]) }
    public static func resetLearning(modelURL: URL, userDatabaseURL: URL) throws {
        let engine = try GuanyinmaInputEngine(modelURL: modelURL, userDatabaseURL: userDatabaseURL)
        try engine.resetLearning()
    }
}
