import Foundation
import Testing
@testable import KeyKeyEngine

struct InputMethodSettingsTests {
    @Test("method settings migrate and keep app-group revision semantics")
    func settings() throws {
        let localName = "TableLocal." + UUID().uuidString, sharedName = "TableShared." + UUID().uuidString
        let local = try #require(UserDefaults(suiteName: localName)), shared = try #require(UserDefaults(suiteName: sharedName))
        defer { local.removePersistentDomain(forName: localName); shared.removePersistentDomain(forName: sharedName) }
        local.set("traditional", forKey: BopomofoCompositionModeSettings.key)
        let keyboard = ChineseInputMethodSettings(defaults: local, sharedDefaults: shared)
        #expect(keyboard.method == .traditional)
        let app = ChineseInputMethodSettings(defaults: local, sharedDefaults: shared, writesShared: true)
        app.setMethod(.cangjie)
        #expect(keyboard.method == .cangjie)
        keyboard.setMethod(.simplex)
        #expect(keyboard.method == .simplex)
        app.setMethod(.smart)
        #expect(keyboard.method == .smart)
    }
}
