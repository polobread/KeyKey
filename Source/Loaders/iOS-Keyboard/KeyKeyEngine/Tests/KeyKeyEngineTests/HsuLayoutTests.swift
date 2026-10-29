import Foundation
import Testing
@testable import KeyKeyEngine

@Suite("Hsu keyboard layout")
struct HsuLayoutTests {
    @Test("Hsu keycaps stay English while Standard retains its Bopomofo glyphs")
    func englishKeycaps() {
        for key in KeyboardLayout.bopomofoRows.flatMap({ $0 }) {
            #expect(KeyboardLayout.bopomofoGlyph(for: key, layout: .hsu) == nil)
        }
        #expect(KeyboardLayout.bopomofoGlyph(for: "j") == "ㄨ")
        #expect(KeyboardLayout.caption(for: "j", mode: .bopomofo) == "j")
        #expect(KeyboardLayout.statusText(reading: "", mode: .bopomofo, shifted: false,
                    temporaryEnglish: false, layout: .hsu) == "許氏鍵盤")
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
