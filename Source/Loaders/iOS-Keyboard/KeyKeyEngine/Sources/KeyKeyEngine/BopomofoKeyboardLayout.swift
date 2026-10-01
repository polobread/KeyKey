// Copyright (c) 2007-2012, Yahoo! Inc. All rights reserved.
// Copyrights licensed under the New BSD License. See the accompanying LICENSE.
// Hsu mapping and disambiguation ported from Formosa/Mandarin.h and Mandarin.cpp.

public enum BopomofoKeyboardLayout: String, CaseIterable, Sendable {
    case standard = "Standard"
    case hsu = "Hsu"

    public var displayName: String { self == .hsu ? "許氏鍵盤" : "標準" }

    public func isReadingKey(_ key: Character) -> Bool {
        let key = Character(key.lowercased())
        return self == .hsu ? Self.hsuComponents[key] != nil
            : StandardBopomofoLayout.isReadingKey(key)
    }

    public func punctuation(for key: Character) -> String? {
        guard self == .hsu else { return nil }
        return [",": "，", ".": "。", "<": "〈", ">": "〉", ":": "：",
                ";": "；", "'": "、", "\"": "”", "-": "─", "_": "＿"][String(key)]
    }

    // Values are Standard-layout keys for the components in desktop priority order.
    private static let hsuKeys: [Character: String] = [
        "b": "1", "p": "q", "m": "a0", "f": "z3", "d": "26", "t": "w",
        "n": "sp", "l": "x/-", "g": "ek", "k": "d;", "h": "ci",
        "j": "r54", "v": "ft", "c": "vg", "r": "b", "z": "y",
        "a": "ho", "s": "n7", "e": "u,", "x": "j", "u": "m",
        "y": "8", "i": "9", "w": "l", "o": "."
    ]
    private static let hsuComponents = hsuKeys.mapValues {
        $0.map { StandardBopomofoLayout.componentForKey[$0]! }
    }
    private static let hsuComponentKeys: [BopomofoSyllable.Component: Character] = {
        var result: [BopomofoSyllable.Component: Character] = [:]
        for (key, components) in hsuComponents {
            for component in components { result[component] = key }
        }
        return result
    }()
    private static let masks = [BopomofoSyllable.consonantMask,
        BopomofoSyllable.medialMask, BopomofoSyllable.vowelMask, BopomofoSyllable.toneMask]

    static func hsuSequence(for syllable: BopomofoSyllable) -> String {
        String(masks.compactMap { hsuComponentKeys[syllable.component(in: $0)] })
    }

    /// Match the desktop buffer: re-encode the current syllable before appending
    /// or removing a key. Keeping raw keystroke history changes ambiguous edits.
    static func parseHsu(_ sequence: String) -> BopomofoSyllable {
        typealias S = BopomofoSyllable
        let keys = Array(sequence)
        var syllable = S()
        func mask(_ value: S.Component) -> S.Component {
            masks.reduce(0) { $0 | (value & $1 == 0 ? 0 : $1) }
        }
        func jqx(_ value: S.Component) -> Bool { [S.j, S.q, S.x].contains(value) }
        func zcsr(_ value: S.Component) -> Bool { value >= S.zh && value <= S.s }
        func endOrTone(_ index: Int) -> Bool {
            index == keys.count || "dfjs".contains(keys[index])
        }
        for index in keys.indices {
            guard let components = hsuComponents[keys[index]] else { continue }
            if components.count == 1 { syllable.add(components[0]); continue }
            let head = components[0], follow = components[1]
            let ending = components.last!
            let beforeHasIorUE = keys[..<index].contains { $0 == "e" || $0 == "u" }
            let aheadHasIorUE = keys[(index + 1)...].contains { $0 == "e" || $0 == "u" }
            if head == S.e || follow == S.e {
                syllable.add(beforeHasIorUE ? S.e : (head == S.e ? follow : head))
            } else if jqx(head) != jqx(follow) {
                if !syllable.isEmpty {
                    if ending != follow { syllable.add(ending) }
                } else {
                    syllable.add(aheadHasIorUE == jqx(head) ? head : follow)
                }
            } else if keys.count == 1 {
                if head & S.vowelMask != 0 || follow & S.toneMask != 0 || zcsr(head) {
                    syllable.add(head)
                } else {
                    syllable.add(follow & S.vowelMask != 0 || ending & S.toneMask != 0
                        ? follow : ending)
                }
            } else if mask(syllable.value) & mask(head) == 0 && !endOrTone(index + 1) {
                syllable.add(head)
            } else if endOrTone(index + 1) && zcsr(head) && syllable.isEmpty {
                syllable.add(head)
            } else {
                syllable.add(mask(syllable.value) < mask(follow) ? follow : ending)
            }
        }
        if syllable.component(in: S.vowelMask) == S.eng,
           syllable.component(in: S.consonantMask) == 0,
           syllable.component(in: S.medialMask) == 0 {
            syllable.add(S.err)
        } else if syllable.component(in: S.consonantMask) == S.g,
                  [S.i, S.ue].contains(syllable.component(in: S.medialMask)) {
            syllable.add(S.j)
        }
        return syllable
    }
}
