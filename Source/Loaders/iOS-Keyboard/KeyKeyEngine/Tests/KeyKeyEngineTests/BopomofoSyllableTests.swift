import Testing

@testable import KeyKeyEngine

@Suite("Bopomofo syllable encoding")
struct BopomofoSyllableTests {
    /// The values on the right come from querying the cooked KeyKey.db, so this
    /// pins the Swift encoder to what the desktop cookers actually wrote.
    @Test(
        "absolute order key matches the cooked database",
        arguments: [
            // ㄋㄧˇ -> 你妳擬
            ([BopomofoSyllable.n, BopomofoSyllable.i, BopomofoSyllable.tone3], 2493, "\\O"),
            // ㄋㄧˋ -> 逆溺匿
            ([BopomofoSyllable.n, BopomofoSyllable.i, BopomofoSyllable.tone4], 3725, "<_"),
            // ㄕˋ -> 市是事
            ([BopomofoSyllable.sh, BopomofoSyllable.tone4], 3713, "0_"),
            // ㄨㄛˇ -> 我
            ([BopomofoSyllable.u, BopomofoSyllable.o, BopomofoSyllable.tone3], 2684, "}Q"),
            // ㄅ alone
            ([BopomofoSyllable.b], 1, "10")
        ]
    )
    func absoluteOrderKey(
        components: [BopomofoSyllable.Component], order: Int, key: String
    ) {
        var syllable = BopomofoSyllable()
        for component in components { syllable.add(component) }
        #expect(syllable.absoluteOrder == order)
        #expect(syllable.absoluteOrderKey == key)
    }

    @Test("absolute order round-trips")
    func roundTrip() {
        for order in 0..<(22 * 4 * 14 * 5) {
            let syllable = BopomofoSyllable(absoluteOrder: order)
            #expect(syllable.absoluteOrder == order)
            let decoded = BopomofoSyllable(absoluteOrderKey: syllable.absoluteOrderKey)
            #expect(decoded == syllable)
        }
    }

    @Test("the key is always two printable ASCII bytes")
    func keyIsPrintableAscii() {
        for order in 0..<(22 * 4 * 14 * 5) {
            let bytes = Array(BopomofoSyllable(absoluteOrder: order).absoluteOrderKey.utf8)
            #expect(bytes.count == 2)
            for byte in bytes { #expect(byte >= 48 && byte <= 126) }
        }
    }

    @Test("a later component of the same class replaces the earlier one")
    func sameClassReplaces() {
        var syllable = BopomofoSyllable()
        syllable.add(BopomofoSyllable.b)
        syllable.add(BopomofoSyllable.p)
        #expect(syllable.composedString == "ㄆ")
    }

    @Test("components compose in canonical order")
    func canonicalOrder() {
        var syllable = BopomofoSyllable()
        syllable.add(BopomofoSyllable.tone3)
        syllable.add(BopomofoSyllable.i)
        syllable.add(BopomofoSyllable.n)
        #expect(syllable.composedString == "ㄋㄧˇ")
    }

    @Test("tone 1 is not a tone marker")
    func toneOneIsBlank() {
        var syllable = BopomofoSyllable()
        syllable.add(BopomofoSyllable.n)
        #expect(!syllable.hasToneMarker)
        syllable.add(BopomofoSyllable.tone1)
        #expect(!syllable.hasToneMarker)
        syllable.add(BopomofoSyllable.tone3)
        #expect(syllable.hasToneMarker)
    }
}
