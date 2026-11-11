// Copyright (c) 2007-2012, Yahoo! Inc. All rights reserved.
// Copyrights licensed under the New BSD License. See the accompanying LICENSE.
// Frontend Hsu key classification derived from Formosa/Mandarin.h and Mandarin.cpp.

public enum BopomofoKeyboardLayout: String, CaseIterable, Sendable {
    case standard = "Standard"
    case hsu = "Hsu"
    case hanyuPinyin = "HanyuPinyin"

    public static let settingsHelp = """
        好打與傳統注音共用配置。許氏與漢語拼音使用英文字母鍵帽。拼音一聲按空白，二至四聲按 2～4，輕聲按 5。拼音寫作 ü（注音「ㄩ」）時按 v。例如綠（lǜ）輸入 lv4。
        """

    public var displayName: String {
        switch self {
        case .standard: return "標準"
        case .hsu: return "許氏鍵盤"
        case .hanyuPinyin: return "漢語拼音"
        }
    }

    public func isReadingKey(_ key: Character) -> Bool {
        guard key.isASCII else { return false }
        let lowercased = Character(key.lowercased())
        switch self {
        case .standard: return StandardBopomofoLayout.isReadingKey(lowercased)
        case .hsu: return Self.hsuKeys.contains(lowercased)
        case .hanyuPinyin: return lowercased.isLetter || ("2"..."5").contains(lowercased)
        }
    }

    public func punctuation(for key: Character) -> String? {
        guard self == .hsu else { return nil }
        return [",": "，", ".": "。", "<": "〈", ">": "〉", ":": "：",
                ";": "；", "'": "、", "\"": "”", "-": "─", "_": "＿"][String(key)]
    }

    // Frontend key classification only; Hsu parsing is owned by Rust.
    private static let hsuKeys = Set("bpmfdtnlgkhjvcrzasexuy iwo".filter { !$0.isWhitespace })
}
