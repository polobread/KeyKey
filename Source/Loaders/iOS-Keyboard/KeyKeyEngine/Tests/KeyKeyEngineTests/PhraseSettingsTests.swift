import Foundation
import Testing

@testable import KeyKeyEngine

@Suite("Phrase settings")
struct PhraseSettingsTests {
    private func settings() -> (PhraseSettings, UserDefaults) {
        // A private suite keeps each test independent of the real defaults.
        let name = "tw.chichi77.keykey.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return (PhraseSettings(defaults: defaults), defaults)
    }

    @Test("a first run enables the base collection")
    func firstRun() {
        let (settings, _) = settings()
        #expect(settings.enabledCollections == ["McBopomofo"])
    }

    @Test("an explicitly empty selection is kept, not reset to the default")
    func emptyIsHonoured() {
        let (settings, _) = settings()
        settings.setEnabledCollections([])
        #expect(settings.enabledCollections.isEmpty)
    }

    @Test("clearing the stored selection returns to the first-run default")
    func clearing() {
        let (settings, _) = settings()
        settings.setEnabledCollections([])
        settings.clearStoredSelection()
        #expect(settings.enabledCollections == ["McBopomofo"])
    }

    @Test("individual collections toggle independently")
    func toggling() {
        let (settings, _) = settings()
        settings.setCollection("medicine", enabled: true)
        #expect(settings.enabledCollections == ["McBopomofo", "medicine"])
        settings.setCollection("McBopomofo", enabled: false)
        #expect(settings.enabledCollections == ["medicine"])
        settings.setCollection("medicine", enabled: false)
        #expect(settings.enabledCollections.isEmpty)
    }

    @Test("the selection survives a new reader over the same store")
    func persistence() {
        let (settings, defaults) = settings()
        settings.setEnabledCollections(["chinese", "general"])
        #expect(PhraseSettings(defaults: defaults).enabledCollections
            == ["chinese", "general"])
    }
}
