import Testing

@testable import KeyKeyEngine

/// Ported from `BopomofoReadingTest.java`.
@Suite("Bopomofo reading buffer")
struct BopomofoReadingTests {
    @Test("out-of-order entry canonicalises")
    func outOfOrderEntry() {
        var reading = BopomofoReading()
        for key in "3us" { reading.combine(key) }
        #expect(reading.displayText == "ㄋㄧˇ")
        #expect(reading.hasToneMarker)
    }

    @Test("same-class components replace")
    func sameClassReplaces() {
        var reading = BopomofoReading()
        for key in "1q89" { reading.combine(key) }
        #expect(reading.displayText == "ㄆㄞ")
    }

    @Test("backspace peels tone, vowel, medial, consonant")
    func backspaceOrder() {
        var reading = BopomofoReading()
        for key in "su3" { reading.combine(key) }
        #expect(reading.displayText == "ㄋㄧˇ")
        reading.backspace()
        #expect(reading.displayText == "ㄋㄧ")
        #expect(!reading.hasToneMarker)
        reading.backspace()
        #expect(reading.displayText == "ㄋ")
        reading.backspace()
        #expect(reading.isEmpty)
        reading.backspace()
        #expect(reading.isEmpty)
    }

    @Test("non-reading keys are rejected and leave the buffer alone")
    func rejectsOtherKeys() {
        var reading = BopomofoReading()
        let accepted = reading.combine("1")
        let rejected = reading.combine("@")
        #expect(accepted)
        #expect(!rejected)
        #expect(reading.displayText == "ㄅ")
    }

    @Test("uppercase keys are accepted")
    func uppercaseAccepted() {
        var reading = BopomofoReading()
        for key in "SU3" { reading.combine(key) }
        #expect(reading.displayText == "ㄋㄧˇ")
    }

    @Test("every standard layout key maps to a glyph")
    func layoutCoverage() {
        let keys = "1qaz2wsxedcrfv5tgbyhn" + "ujm" + "8ik,9ol.0p;/-" + "6347"
        #expect(keys.count == 41)
        for key in keys {
            #expect(StandardBopomofoLayout.glyph(for: key) != nil, "no glyph for \(key)")
        }
        // A digit that is not part of the layout stays unmapped.
        #expect(StandardBopomofoLayout.glyph(for: "2") != nil)
        #expect(StandardBopomofoLayout.glyph(for: "@") == nil)
    }
}
