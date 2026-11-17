import Foundation
import Testing

@testable import KeyKeyEngine

@Suite("倚天鍵盤")
struct ETenLayoutTests {
    @Test func fullETenExposesEveryReadingKeyInAllProfilesAndOrientations() {
        let desktopKeys = Set("bpmfdtnlvkhg7c,./j;'sexuaorwiqzy890-=2341")
        for profile in KeyboardLayoutProfile.available {
            for orientation in KeyboardLayoutProfile.Orientation.allCases {
                for position in KeyboardDeleteShiftPosition.allCases {
                    let rows = profile.resolvedRows(orientation: orientation, plane: .bopomofo,
                        shifted: false, deleteShiftPosition: position, keyboardLayout: .eten)
                    let keys = rows.joined().compactMap { $0.count == 1 ? $0.first : nil }
                    let readings = keys.filter(BopomofoKeyboardLayout.eten.isReadingKey)
                    #expect(rows.map(\.count) == [11, 11, 11, 11])
                    #expect(readings.count == 41)
                    #expect(Set(readings) == desktopKeys)
                    #expect(rows[0].last == "EMOJI")
                    #expect(rows[1].last == "@")
                    #expect(rows[2].suffix(2) == [";", "'"])

                    for index in rows.indices {
                        let geometry = profile.keyRowGeometry(for: rows, plane: .bopomofo, rowIndex: index)
                        let frames = geometry.frames(width: 390, height: 44, spacing: profile.keySpacing)
                        #expect(frames.count == (profile.splitGeometry == nil ? 11 : 12))
                        #expect(frames.allSatisfy { $0.width > 0 })
                    }
                }
            }
        }
    }

    @Test func etenCaptionsAndToneSizesFollowTheDesktopReadingPositions() {
        #expect(KeyboardLayout.bopomofoGlyph(for: "=", layout: .eten) == "ㄦ")
        #expect(KeyboardLayout.bopomofoGlyph(for: "'", layout: .eten) == "ㄘ")
        #expect(KeyboardLayout.bopomofoGlyph(for: "3", layout: .eten) == "ˇ")
        #expect(KeyboardLayout.bopomofoGlyph(for: "7", layout: .eten) == "ㄑ")
        #expect(KeyboardLayout.bopomofoGlyph(for: "3") == "ˇ")
        #expect(KeyboardLayout.glyphPointScale(for: "1", layout: .eten) == 1.8)
        #expect(KeyboardLayout.glyphPointScale(for: "1") == 1)
        #expect(KeyboardLayout.glyphPointScale(for: "7", layout: .eten) == 1)
        #expect(KeyboardLayout.glyphPointScale(for: "7") == 1.8)
        #expect(KeyboardLayout.bopomofoGlyph(for: "n", layout: .eten26) == nil)
    }

    @Test func eten26KeepsAllLatinPositionsAndOtherInputPlanesKeepTheirKeys() {
        let profile = KeyboardLayoutProfile.aligned
        let keys = profile.resolvedRows(orientation: .portrait, plane: .bopomofo, shifted: false,
            deleteShiftPosition: .leftOfEnter, keyboardLayout: .eten26)
            .joined().compactMap { $0.count == 1 ? $0.first : nil }
        #expect(Set(keys.filter(BopomofoKeyboardLayout.eten26.isReadingKey)) == Set("abcdefghijklmnopqrstuvwxyz"))
        #expect(BopomofoKeyboardLayout.eten26.isReadingKey("J"))
        #expect(!BopomofoKeyboardLayout.eten26.isReadingKey("3"))
        #expect(!BopomofoKeyboardLayout.eten26.isReadingKey("'"))

        for plane in [KeyboardLayoutProfile.Plane.english, .numberSymbols, .cangjie, .simplex] {
            let standard = profile.resolvedRows(orientation: .portrait, plane: plane, shifted: false,
                deleteShiftPosition: .leftOfEnter)
            for layout in [BopomofoKeyboardLayout.eten, .eten26] {
                #expect(profile.resolvedRows(orientation: .portrait, plane: plane, shifted: false,
                    deleteShiftPosition: .leftOfEnter, keyboardLayout: layout) == standard)
            }
        }
    }

    @Test func bothEtenLayoutsRoundTripThroughExistingKeyboardPreferences() throws {
        let suite = "ETenLayoutTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = BopomofoKeyboardLayoutSettings(defaults: defaults)
        let omission = SmartMandarinToneOmissionSettings(defaults: defaults)
        #expect(!omission.enabled)
        omission.setEnabled(true)
        for layout in [BopomofoKeyboardLayout.eten, .eten26, .standard] {
            settings.setLayout(layout)
            #expect(BopomofoKeyboardLayoutSettings(defaults: defaults).layout == layout)
            #expect(omission.enabled)
        }
    }
}
