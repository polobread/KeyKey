// Copyright (c) 2007-2012, Yahoo! Inc. All rights reserved.
// Copyrights licensed under the New BSD License. See the accompanying LICENSE.
// Frontend Hsu key classification derived from Formosa/Mandarin.h and Mandarin.cpp.

public enum BopomofoKeyboardLayout: String, CaseIterable, Sendable {
    case standard = "Standard"
    case hsu = "Hsu"

    public var displayName: String { self == .hsu ? "許氏鍵盤" : "標準" }

    public func isReadingKey(_ key: Character) -> Bool {
        let key = Character(key.lowercased())
        return self == .hsu ? Self.hsuKeys.contains(key)
            : StandardBopomofoLayout.isReadingKey(key)
    }

    public func punctuation(for key: Character) -> String? {
        guard self == .hsu else { return nil }
        return [",": "，", ".": "。", "<": "〈", ">": "〉", ":": "：",
                ";": "；", "'": "、", "\"": "”", "-": "─", "_": "＿"][String(key)]
    }

    // Frontend key classification only; Hsu parsing is owned by Rust.
    private static let hsuKeys = Set("bpmfdtnlgkhjvcrzasexuy iwo".filter { !$0.isWhitespace })
}
