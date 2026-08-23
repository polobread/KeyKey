/// One Bopomofo syllable packed into a bit field, ported from
/// `Source/Frameworks/Formosa/Headers/Mandarin.h`.
///
/// The packing matters beyond memory: `absoluteOrderKey` is the key the cooked
/// `KeyKey.db` is indexed by. Both desktop cookers run every `.cin` keystroke
/// sequence through this encoding before inserting, so a lookup built from raw
/// keystrokes finds nothing.
public struct BopomofoSyllable: Equatable, Sendable {
    public typealias Component = UInt16

    public static let consonantMask: Component = 0x001f  // 21 consonants
    public static let medialMask: Component = 0x0060     // 3 medial vowels
    public static let vowelMask: Component = 0x0780      // 13 vowels
    public static let toneMask: Component = 0x3800       // 4 marks; tone 1 is 0

    private static let classMasks = [consonantMask, medialMask, vowelMask, toneMask]

    public static let b: Component = 0x0001, p: Component = 0x0002
    public static let m: Component = 0x0003, f: Component = 0x0004
    public static let d: Component = 0x0005, t: Component = 0x0006
    public static let n: Component = 0x0007, l: Component = 0x0008
    public static let g: Component = 0x0009, k: Component = 0x000a
    public static let h: Component = 0x000b, j: Component = 0x000c
    public static let q: Component = 0x000d, x: Component = 0x000e
    public static let zh: Component = 0x000f, ch: Component = 0x0010
    public static let sh: Component = 0x0011, r: Component = 0x0012
    public static let z: Component = 0x0013, c: Component = 0x0014
    public static let s: Component = 0x0015

    public static let i: Component = 0x0020, u: Component = 0x0040
    public static let ue: Component = 0x0060

    public static let a: Component = 0x0080, o: Component = 0x0100
    public static let er: Component = 0x0180, e: Component = 0x0200
    public static let ai: Component = 0x0280, ei: Component = 0x0300
    public static let ao: Component = 0x0380, ou: Component = 0x0400
    public static let an: Component = 0x0480, en: Component = 0x0500
    public static let ang: Component = 0x0580, eng: Component = 0x0600
    public static let err: Component = 0x0680

    public static let tone1: Component = 0x0000, tone2: Component = 0x0800
    public static let tone3: Component = 0x1000, tone4: Component = 0x1800
    public static let tone5: Component = 0x2000

    public private(set) var value: Component

    public init(_ value: Component = 0) {
        self.value = value
    }

    public var isEmpty: Bool { value == 0 }

    /// Tone 1 shares the zero bit pattern with "no tone", matching the C++
    /// model and the toneless rows in `bpmf-ext.cin`.
    public var hasToneMarker: Bool { value & Self.toneMask != 0 }

    public func component(in mask: Component) -> Component { value & mask }

    /// A later component of the same class replaces the earlier one, so typing
    /// ㄅ then ㄆ leaves only ㄆ.
    public mutating func add(_ component: Component) {
        for mask in Self.classMasks where component & mask != 0 {
            value = (value & ~mask) | (component & mask)
        }
    }

    public mutating func remove(_ mask: Component) {
        value &= ~mask
    }

    /// The syllable as a number in a 22 x 4 x 14 x 5 space.
    public var absoluteOrder: Int {
        Int(value & Self.consonantMask)
            + Int((value & Self.medialMask) >> 5) * 22
            + Int((value & Self.vowelMask) >> 7) * 22 * 4
            + Int((value & Self.toneMask) >> 11) * 22 * 4 * 14
    }

    /// The 6160 possible syllables encoded as two printable ASCII bytes, low
    /// digit first. This is the `Mandarin-bpmf-cin` key.
    public var absoluteOrderKey: String {
        let order = absoluteOrder
        let low = UnicodeScalar(48 + UInt8(order % 79))
        let high = UnicodeScalar(48 + UInt8(order / 79))
        return String(Character(low)) + String(Character(high))
    }

    public init(absoluteOrder order: Int) {
        let consonant = Component(order % 22)
        let medial = Component((order / 22) % 4) << 5
        let vowel = Component((order / (22 * 4)) % 14) << 7
        let tone = Component((order / (22 * 4 * 14)) % 5) << 11
        self.init(consonant | medial | vowel | tone)
    }

    public init?(absoluteOrderKey key: String) {
        let bytes = Array(key.utf8)
        guard bytes.count == 2 else { return nil }
        self.init(absoluteOrder: Int(bytes[1] - 48) * 79 + Int(bytes[0] - 48))
    }

    /// The display form, e.g. `ㄋㄧˇ`. Components always come out in canonical
    /// order regardless of the order they were typed in.
    public var composedString: String {
        var result = ""
        for mask in Self.classMasks {
            let component = value & mask
            if component != 0, let glyph = Self.glyphs[component] {
                result.append(glyph)
            }
        }
        return result
    }

    static let glyphs: [Component: Character] = [
        b: "ㄅ", p: "ㄆ", m: "ㄇ", f: "ㄈ", d: "ㄉ", t: "ㄊ", n: "ㄋ", l: "ㄌ",
        g: "ㄍ", k: "ㄎ", h: "ㄏ", j: "ㄐ", q: "ㄑ", x: "ㄒ",
        zh: "ㄓ", ch: "ㄔ", sh: "ㄕ", r: "ㄖ", z: "ㄗ", c: "ㄘ", s: "ㄙ",
        i: "ㄧ", u: "ㄨ", ue: "ㄩ",
        a: "ㄚ", o: "ㄛ", er: "ㄜ", e: "ㄝ", ai: "ㄞ", ei: "ㄟ", ao: "ㄠ",
        ou: "ㄡ", an: "ㄢ", en: "ㄣ", ang: "ㄤ", eng: "ㄥ", err: "ㄦ",
        tone2: "ˊ", tone3: "ˇ", tone4: "ˋ", tone5: "˙"
    ]
}
