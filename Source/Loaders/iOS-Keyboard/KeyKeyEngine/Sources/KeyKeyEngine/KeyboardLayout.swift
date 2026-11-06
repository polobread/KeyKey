/// The touch key planes and captions, copied from
/// `Source/Loaders/Android-IME/.../BopomofoKeyboardView.java` so muscle memory
/// carries across platforms.
///
/// The original full profile has four rows of eleven keys. Rows two to four end in a
/// function key (`@`, Emoji, Shift) rather than a twelfth letter, which is what
/// keeps the columns aligned.
public enum KeyboardLayout {
    // Compatibility helpers describe the original full profile, not every visual style.
    public static var bopomofoRows: [[String]] { KeyboardLayoutProfile.aligned.portrait.bopomofo.rows }
    public static var shiftedEnglishRows: [[String]] { KeyboardLayoutProfile.aligned.portrait.english.shiftedRows }
    public static var numberRows: [[String]] { KeyboardLayoutProfile.aligned.portrait.numberSymbols.rows }
    public static var shiftedNumberRows: [[String]] { KeyboardLayoutProfile.aligned.portrait.numberSymbols.shiftedRows }
    public static var functionRow: [String] { KeyboardLayoutProfile.aligned.functionKeys }

    /// The globe key. iPhone gets one from the system in its own row below the
    /// input view, so the keyboard must not draw a second; iPad gets no such
    /// row, and without this key there is no way out of the keyboard. Which
    /// case applies is `UIInputViewController.needsInputModeSwitchKey`.
    public static let inputModeSwitchKey = "NEXT_KEYBOARD"

    public static func functionRow(withInputModeSwitch: Bool) -> [String] {
        withInputModeSwitch ? [inputModeSwitchKey] + functionRow : functionRow
    }

    public static func rows(
        mode: KeyboardInput.InputMode, shifted: Bool
    ) -> [[String]] {
        KeyboardLayoutProfile.aligned.rows(orientation: .portrait, inputMethod: .smart, mode: mode, shifted: shifted)
    }

    public static func weight(for key: String) -> Double {
        KeyboardLayoutProfile.aligned.functionWeight(for: key)
    }

    /// Keys drawn in the darker fill.
    public static func isSpecial(_ key: String) -> Bool {
        switch key {
        case inputModeSwitchKey,
             "MODE", "SYMBOL", "SETTINGS", "SPACE", "BACKSPACE", "ENTER",
             "SHIFT", "EMOJI", "，", "。":
            return true
        default:
            return false
        }
    }

    /// The mode key advertises the *next two* modes, not the current one.
    public static func caption(
        for key: String, mode: KeyboardInput.InputMode
    ) -> String {
        switch key {
        case "MODE":
            switch mode {
            case .bopomofo: return "英/數"
            case .english: return "數/ㄅ"
            case .number: return "ㄅ/英"
            }
        case "SYMBOL": return "符"
        case "SETTINGS": return "設"
        case "SPACE": return "空白"
        case "BACKSPACE": return "⌫"
        case "ENTER": return "↵"
        case "SHIFT": return "⇧"
        case "EMOJI": return "☺"
        default: return key
        }
    }

    /// The Bopomofo glyph for a reading key, or nil for anything else. Keys
    /// carry both labels so the physical key position stays visible.
    public static func bopomofoGlyph(
        for key: String, layout: BopomofoKeyboardLayout = .standard
    ) -> String? {
        guard layout == .standard else { return nil }
        guard key.count == 1, let character = key.first else { return nil }
        return StandardBopomofoLayout.glyph(for: character).map(String.init)
    }

    /// How much bigger the glyph is drawn than the rest of the caption. The
    /// tone marks (ˊ ˇ ˋ ˙) are spacing modifier letters, drawn small and high
    /// in the em box, so at the size that suits ㄅ they are barely readable.
    /// The key position underneath keeps the normal hint size.
    public static func glyphPointScale(for key: String) -> Double {
        guard key.count == 1, let character = key.first else { return 1 }
        return StandardBopomofoLayout.isToneKey(character) ? 1.8 : 1
    }

    /// What the candidate strip shows when there are no candidates. This is the
    /// keyboard's state readout and a fallback visual cue while the iOS loader
    /// also mirrors the reading into the host's marked-text range.
    public static func statusText(
        reading: String,
        mode: KeyboardInput.InputMode,
        shifted: Bool,
        temporaryEnglish: Bool,
        layout: BopomofoKeyboardLayout = .standard
    ) -> String {
        if !reading.isEmpty { return "\(reading)\u{3000}按空白選字" }
        if temporaryEnglish { return "暫時英文小寫" }
        switch mode {
        case .english: return shifted ? "英文大寫" : "英文小寫"
        case .number: return shifted ? "數字與符號（二）" : "數字與符號（一）"
        case .bopomofo: return layout == .hsu ? "許氏鍵盤" : "標準注音"
        }
    }
}
