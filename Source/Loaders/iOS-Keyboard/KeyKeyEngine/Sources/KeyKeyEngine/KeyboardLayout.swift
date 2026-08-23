/// The touch key planes and captions, copied from
/// `Source/Loaders/Android-IME/.../BopomofoKeyboardView.java` so muscle memory
/// carries across platforms.
///
/// Every plane is four rows of exactly eleven keys. Rows two to four end in a
/// function key (`@`, Emoji, Shift) rather than a twelfth letter, which is what
/// keeps the columns aligned.
public enum KeyboardLayout {
    public static let bopomofoRows: [[String]] = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-"],
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "@"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l", ";", "EMOJI"],
        ["z", "x", "c", "v", "b", "n", "m", ",", ".", "/", "SHIFT"]
    ]

    public static let shiftedEnglishRows: [[String]] = [
        ["!", "@", "#", "$", "%", "^", "&", "*", "(", ")", "_"],
        ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "@"],
        ["A", "S", "D", "F", "G", "H", "J", "K", "L", ";", "EMOJI"],
        ["Z", "X", "C", "V", "B", "N", "M", ",", ".", "/", "SHIFT"]
    ]

    public static let numberRows: [[String]] = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-"],
        ["!", "@", "#", "$", "%", "^", "&", "*", "(", ")", "_"],
        ["+", "=", "[", "]", "{", "}", "<", ">", "/", "\\", "|"],
        ["~", "`", "\"", "'", ":", ";", "?", ",", ".", "…", "SHIFT"]
    ]

    public static let shiftedNumberRows: [[String]] = [
        ["$", "€", "£", "¥", "₩", "₹", "₽", "¢", "₫", "₱", "฿"],
        ["＋", "－", "×", "÷", "=", "≠", "≈", "±", "<", ">", "∞"],
        ["←", "→", "↑", "↓", "↔", "↕", "↖", "↗", "↘", "↙", "⇒"],
        ["★", "☆", "●", "○", "■", "□", "▲", "△", "▼", "▽", "SHIFT"]
    ]

    /// The long space bar is the only deliberately wide key.
    public static let functionRow: [String] = [
        "MODE", "SYMBOL", "SETTINGS", "，", "SPACE", "。", "BACKSPACE", "ENTER"
    ]

    /// The globe key. iPhone gets one from the system in its own row below the
    /// input view, so the keyboard must not draw a second; iPad gets no such
    /// row, and without this key there is no way out of the keyboard. Which
    /// case applies is `UIInputViewController.needsInputModeSwitchKey`.
    public static let inputModeSwitchKey = "NEXT_KEYBOARD"

    public static func functionRow(withInputModeSwitch: Bool) -> [String] {
        withInputModeSwitch ? [inputModeSwitchKey] + functionRow : functionRow
    }

    public static func rows(
        mode: BopomofoEngine.InputMode, shifted: Bool
    ) -> [[String]] {
        switch mode {
        case .bopomofo: return bopomofoRows
        case .english: return shifted ? shiftedEnglishRows : bopomofoRows
        case .number: return shifted ? shiftedNumberRows : numberRows
        }
    }

    public static func weight(for key: String) -> Double {
        switch key {
        case "MODE": return 1.65
        case "SPACE": return 3.8
        case "BACKSPACE", "ENTER": return 1.4
        default: return 1
        }
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
        for key: String, mode: BopomofoEngine.InputMode
    ) -> String {
        switch key {
        case "MODE":
            switch mode {
            case .bopomofo: return "英/數"
            case .english: return "數/中"
            case .number: return "中/英"
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
    public static func bopomofoGlyph(for key: String) -> String? {
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
    /// keyboard's only state readout, and on iOS it is also where the reading
    /// lives, because an extension has no marked-text channel.
    public static func statusText(
        reading: String,
        mode: BopomofoEngine.InputMode,
        shifted: Bool,
        temporaryEnglish: Bool
    ) -> String {
        if !reading.isEmpty { return "\(reading)\u{3000}按空白選字" }
        if temporaryEnglish { return "暫時英文小寫" }
        switch mode {
        case .english: return shifted ? "英文大寫" : "英文小寫"
        case .number: return shifted ? "數字與符號（二）" : "數字與符號（一）"
        case .bopomofo: return "標準注音"
        }
    }
}
