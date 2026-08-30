import Testing

@testable import KeyKeyEngine

@Suite("Keyboard layout")
struct KeyboardLayoutTests {
    @Test(
        "every plane is four rows of eleven",
        arguments: [
            KeyboardLayout.bopomofoRows,
            KeyboardLayout.shiftedEnglishRows,
            KeyboardLayout.numberRows,
            KeyboardLayout.shiftedNumberRows
        ]
    )
    func planeShape(rows: [[String]]) {
        #expect(rows.count == 4)
        for row in rows { #expect(row.count == 11) }
    }

    @Test("rows two to four end in a function key")
    func rowEndings() {
        let rows = KeyboardLayout.bopomofoRows
        #expect(KeyboardLayout.bopomofoGlyph(for: rows[0][10]) == "ㄦ")
        #expect(rows[1][10] == "@")
        #expect(rows[2][10] == "EMOJI")
        #expect(rows[3][10] == "SHIFT")
    }

    @Test("the Bopomofo plane covers all 41 reading keys")
    func readingCoverage() {
        let keys = KeyboardLayout.bopomofoRows.flatMap { $0 }
            .filter { KeyboardLayout.bopomofoGlyph(for: $0) != nil }
        #expect(keys.count == 41)
        #expect(Set(keys).count == 41, "no key appears twice")
    }

    @Test("the function row weights leave the space bar widest")
    func functionRowWeights() {
        let weights = KeyboardLayout.functionRow.map(KeyboardLayout.weight(for:))
        #expect(weights == [1.65, 1, 1, 1, 3.8, 1, 1.4, 1.4])
        #expect(weights.reduce(0, +) == 12.25)
        #expect(KeyboardLayout.weight(for: "SPACE") == weights.max())
    }

    @Test("the mode key advertises the next two modes")
    func modeCaption() {
        #expect(KeyboardLayout.caption(for: "MODE", mode: .bopomofo) == "英/數")
        #expect(KeyboardLayout.caption(for: "MODE", mode: .english) == "數/ㄅ")
        #expect(KeyboardLayout.caption(for: "MODE", mode: .number) == "ㄅ/英")
    }

    @Test("shift only swaps the plane where it should")
    func planeSelection() {
        // The Bopomofo plane ignores shift: shift there is a one-shot hop to
        // English, handled by the engine rather than the layout.
        #expect(KeyboardLayout.rows(mode: .bopomofo, shifted: true)
            == KeyboardLayout.bopomofoRows)
        #expect(KeyboardLayout.rows(mode: .english, shifted: false)
            == KeyboardLayout.bopomofoRows)
        #expect(KeyboardLayout.rows(mode: .english, shifted: true)
            == KeyboardLayout.shiftedEnglishRows)
        #expect(KeyboardLayout.rows(mode: .number, shifted: false)
            == KeyboardLayout.numberRows)
        #expect(KeyboardLayout.rows(mode: .number, shifted: true)
            == KeyboardLayout.shiftedNumberRows)
    }

    @Test("the status line doubles as the reading display")
    func statusText() {
        #expect(KeyboardLayout.statusText(
            reading: "ㄋㄧ", mode: .bopomofo, shifted: false, temporaryEnglish: false)
            == "ㄋㄧ\u{3000}按空白選字")
        #expect(KeyboardLayout.statusText(
            reading: "", mode: .bopomofo, shifted: false, temporaryEnglish: false)
            == "標準注音")
        #expect(KeyboardLayout.statusText(
            reading: "", mode: .english, shifted: false, temporaryEnglish: true)
            == "暫時英文小寫")
        #expect(KeyboardLayout.statusText(
            reading: "", mode: .english, shifted: true, temporaryEnglish: false)
            == "英文大寫")
        #expect(KeyboardLayout.statusText(
            reading: "", mode: .number, shifted: true, temporaryEnglish: false)
            == "數字與符號（二）")
    }

    @Test("symbol and emoji panels are exactly ninety entries")
    func panelSizes() {
        #expect(BopomofoEngine.symbols.count == 90)
        #expect(BopomofoEngine.emojis.count == 90)
        #expect(Set(BopomofoEngine.symbols).count == 90, "no duplicates")
        #expect(Set(BopomofoEngine.emojis).count == 90, "no duplicates")
    }

    @Test func toneKeysAreDrawnLarger() {
        // 6347 are the tone keys; everything else keeps the plain size.
        for key in ["6", "3", "4", "7"] {
            #expect(KeyboardLayout.glyphPointScale(for: key) > 1)
        }
        for key in ["1", "5", "8", "u", "SPACE", ""] {
            #expect(KeyboardLayout.glyphPointScale(for: key) == 1)
        }
    }
}
