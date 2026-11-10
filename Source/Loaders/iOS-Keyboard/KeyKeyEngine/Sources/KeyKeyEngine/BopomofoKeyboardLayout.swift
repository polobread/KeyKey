// Copyright (c) 2007-2012, Yahoo! Inc. All rights reserved.
// Copyrights licensed under the New BSD License. See the accompanying LICENSE.
// Frontend Hsu key classification derived from Formosa/Mandarin.h and Mandarin.cpp.

public enum BopomofoKeyboardLayout: String, CaseIterable, Sendable {
    case standard = "Standard"
    case hsu = "Hsu"
    case hanyuPinyin = "HanyuPinyin"

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
