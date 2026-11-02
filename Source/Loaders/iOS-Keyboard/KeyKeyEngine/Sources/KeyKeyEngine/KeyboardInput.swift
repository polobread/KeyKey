// Copyright (c) 2026 Chui-Ping Cheng. MIT License.

/// Frontend keyboard planes, document effects and symbol palettes.
/// Input parsing, composition and learning are owned by Guanyinma.
public enum KeyboardInput {
    public static let candidatesPerPage = 9
    public static let touchSmartEditableLimit = 9
    public static let hardwareSmartEditableLimit = 10

    public enum InputMode: Sendable, Hashable, CaseIterable {
        case bopomofo, english, number
    }

    public struct Result: Equatable, Sendable {
        public let text: String
        public let deletesBackward: Bool
        public let sendsReturn: Bool

        static let update = Result(text: "", deletesBackward: false, sendsReturn: false)
        static func commit(_ text: String) -> Result {
            Result(text: text, deletesBackward: false, sendsReturn: false)
        }
        static func commitAndReturn(_ text: String) -> Result {
            Result(text: text, deletesBackward: false, sendsReturn: true)
        }
        static let delete = Result(text: "", deletesBackward: true, sendsReturn: false)
        static let returnKey = Result(text: "", deletesBackward: false, sendsReturn: true)
    }

    /// Existing frontend palettes, ten pages of nine entries each.
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
}

/// Optional frontend overlay source; model queries are supplied by Rust.
public protocol AssociatedPhraseSource {
    func phrases(forHeadCharacter character: String) -> [String]
}
