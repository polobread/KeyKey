// Copyright (c) 2007-2012, Yahoo! Inc. All rights reserved.
// Copyrights licensed under the New BSD License. See the accompanying LICENSE.
// Frontend Hsu key classification derived from Formosa/Mandarin.h and Mandarin.cpp.

public enum BopomofoKeyboardLayout: String, CaseIterable, Sendable {
    case standard = "Standard"
    case hsu = "Hsu"
    case hanyuPinyin = "HanyuPinyin"
    case eten = "ETen"
    case eten26 = "ETen26"

    public static let settingsHelp = """
        好打與傳統注音共用配置。標準與倚天顯示注音鍵帽，許氏、倚天 26 鍵與漢語拼音使用英文字母鍵帽。拼音一聲按空白，二至四聲按 2～4，輕聲按 5。拼音寫作 ü（注音「ㄩ」）時按 v。例如綠（lǜ）輸入 lv4。
        """

    public var displayName: String {
        switch self {
        case .standard: return "標準"
        case .hsu: return "許氏鍵盤"
        case .hanyuPinyin: return "漢語拼音"
        case .eten: return "倚天"
        case .eten26: return "倚天 26 鍵"
        }
    }

    public func isReadingKey(_ key: Character) -> Bool {
        guard key.isASCII else { return false }
        let lowercased = Character(key.lowercased())
        switch self {
        case .standard: return StandardBopomofoLayout.isReadingKey(lowercased)
        case .hsu: return Self.hsuKeys.contains(lowercased)
        case .hanyuPinyin: return lowercased.isLetter || ("2"..."5").contains(lowercased)
        case .eten: return Self.etenGlyphs[lowercased] != nil
        case .eten26: return lowercased.isLetter
        }
    }

    func glyph(for key: Character) -> Character? {
        switch self {
        case .standard: return StandardBopomofoLayout.glyph(for: key)
        case .eten: return Self.etenGlyphs[key]
        case .hsu, .hanyuPinyin, .eten26: return nil
        }
    }

    public func punctuation(for key: Character) -> String? {
        guard self == .hsu else { return nil }
        return [",": "，", ".": "。", "<": "〈", ">": "〉", ":": "：",
                ";": "；", "'": "、", "\"": "”", "-": "─", "_": "＿"][String(key)]
    }

    // Positional mapping for keycaps and reading-key events, ordered as Guanyinma's ETEN_KEYS.
    private static let etenGlyphs = Dictionary(uniqueKeysWithValues: zip(
        "bpmfdtnlvkhg7c,./j;'sexuaorwiqzy890-=2341",
        StandardBopomofoLayout.glyphs
    ))

    // Frontend key classification only; Hsu parsing is owned by Rust.
    private static let hsuKeys = Set("bpmfdtnlgkhjvcrzasexuy iwo".filter { !$0.isWhitespace })
}
