/// The standard (Dachen) Bopomofo layout: which key contributes which
/// component. Mirrors `BopomofoKeyboardLayout::StandardLayout()` in
/// `Source/Frameworks/Formosa/Source/Mandarin.cpp` and the Java transcription
/// in `Source/Loaders/Android-IME/.../BopomofoReading.java`.
public enum StandardBopomofoLayout {
    public static let componentForKey: [Character: BopomofoSyllable.Component] = {
        var map: [Character: BopomofoSyllable.Component] = [:]
        func assign(_ keys: String, _ components: [BopomofoSyllable.Component]) {
            for (key, component) in zip(keys, components) {
                map[key] = component
            }
        }
        let s = BopomofoSyllable.self
        assign("1qaz2wsxedcrfv5tgbyhn", [
            s.b, s.p, s.m, s.f, s.d, s.t, s.n, s.l, s.g, s.k, s.h,
            s.j, s.q, s.x, s.zh, s.ch, s.sh, s.r, s.z, s.c, s.s
        ])
        assign("ujm", [s.i, s.u, s.ue])
        assign("8ik,9ol.0p;/-", [
            s.a, s.o, s.er, s.e, s.ai, s.ei, s.ao,
            s.ou, s.an, s.en, s.ang, s.eng, s.err
        ])
        assign("6347", [s.tone2, s.tone3, s.tone4, s.tone5])
        return map
    }()

    /// The Bopomofo glyph a key produces, for the dual key captions.
    public static func glyph(for key: Character) -> Character? {
        componentForKey[key].flatMap { BopomofoSyllable.glyphs[$0] }
    }

    /// True for the four tone keys (`6347`).
    public static func isToneKey(_ key: Character) -> Bool {
        guard let component = componentForKey[key] else { return false }
        return component & BopomofoSyllable.toneMask != 0
    }

    public static func isReadingKey(_ key: Character) -> Bool {
        componentForKey[Character(key.lowercased())] != nil
    }
}

/// The composition buffer for a single syllable.
public struct BopomofoReading: Equatable, Sendable {
    private var syllable = BopomofoSyllable()

    public init() {}

    public var isEmpty: Bool { syllable.isEmpty }
    public var hasToneMarker: Bool { syllable.hasToneMarker }

    /// What the user sees while composing, e.g. `ㄋㄧˇ`.
    public var displayText: String { syllable.composedString }

    /// The `Mandarin-bpmf-cin` lookup key.
    public var queryKey: String { syllable.absoluteOrderKey }

    @discardableResult
    public mutating func combine(_ rawKey: Character) -> Bool {
        let key = Character(rawKey.lowercased())
        guard let component = StandardBopomofoLayout.componentForKey[key] else { return false }
        syllable.add(component)
        return true
    }

    /// Peels one component in canonical order, matching the Java engine and the
    /// net effect of the C++ buffer chopping its key sequence.
    public mutating func backspace() {
        let order: [BopomofoSyllable.Component] = [
            BopomofoSyllable.toneMask,
            BopomofoSyllable.vowelMask,
            BopomofoSyllable.medialMask,
            BopomofoSyllable.consonantMask
        ]
        for mask in order where syllable.component(in: mask) != 0 {
            syllable.remove(mask)
            return
        }
    }

    public mutating func clear() {
        syllable = BopomofoSyllable()
    }
}
