import Foundation
import Testing
@testable import KeyKeyEngine

@Suite("Hsu keyboard layout")
struct HsuLayoutTests {
    @Test("desktop ambiguous keys, tones and canonical dictionary queries")
    func readings() {
        let cases = [("jxl", "5j/", "ㄓㄨㄥ"), ("llf", "x/3", "ㄌㄥˇ"),
                     ("myd", "a86", "ㄇㄚˊ"), ("myf", "a83", "ㄇㄚˇ"),
                     ("myj", "a84", "ㄇㄚˋ"), ("mys", "a87", "ㄇㄚ˙"),
                     ("l", "-", "ㄦ"), ("gef", "ru3", "ㄐㄧˇ"),
                     ("guf", "rm3", "ㄐㄩˇ")]
        for (keys, standardKeys, display) in cases {
            var hsu = BopomofoReading(layout: .hsu)
            var standard = BopomofoReading()
            for key in keys {
                let accepted = hsu.combine(key)
                #expect(accepted)
            }
            for key in standardKeys { standard.combine(key) }
            #expect(hsu.displayText == display)
            #expect(hsu.queryKey == standard.queryKey)
            let saved = hsu
            let accepted = hsu.combine("#")
            #expect(!accepted)
            #expect(hsu == saved)
            hsu.clear()
            #expect(hsu.isEmpty)
            #expect(hsu.layout == .hsu)
        }
    }

    @Test("Hsu keycaps stay English while Standard retains its Bopomofo glyphs")
    func englishKeycaps() {
        for key in KeyboardLayout.bopomofoRows.flatMap({ $0 }) {
            #expect(KeyboardLayout.bopomofoGlyph(for: key, layout: .hsu) == nil)
        }
        #expect(KeyboardLayout.bopomofoGlyph(for: "j") == "ㄨ")
        #expect(KeyboardLayout.caption(for: "j", mode: .bopomofo) == "j")
        #expect(KeyboardLayout.statusText(reading: "", mode: .bopomofo, shifted: false,
                    temporaryEnglish: false, layout: .hsu) == "許氏注音")
    }

    @Test("layout defaults to Standard, persists, and follows App Group revisions")
    func preferences() {
        let localName = "hsu-local-\(UUID())", sharedName = "hsu-shared-\(UUID())"
        let local = UserDefaults(suiteName: localName)!, shared = UserDefaults(suiteName: sharedName)!
        defer { local.removePersistentDomain(forName: localName); shared.removePersistentDomain(forName: sharedName) }
        let keyboard = BopomofoKeyboardLayoutSettings(defaults: local, sharedDefaults: shared)
        let app = BopomofoKeyboardLayoutSettings(defaults: local, sharedDefaults: shared, writesShared: true)
        #expect(keyboard.layout == .standard)
        local.set("invalid", forKey: BopomofoKeyboardLayoutSettings.key)
        #expect(keyboard.layout == .standard)
        keyboard.setLayout(.hsu)
        #expect(BopomofoKeyboardLayoutSettings(defaults: local).layout == .hsu)
        app.setLayout(.standard)
        #expect(keyboard.layout == .standard)
        app.setLayout(.hsu)
        #expect(keyboard.layout == .hsu)
        keyboard.setLayout(.standard)
        #expect(keyboard.layout == .standard)
    }
}
