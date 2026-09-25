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

@Suite("Bopomofo composition mode settings")
struct BopomofoCompositionModeSettingsTests {
    private func settings() -> (BopomofoCompositionModeSettings, UserDefaults) {
        let name = "tw.chichi77.keykey.mode-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return (BopomofoCompositionModeSettings(defaults: defaults), defaults)
    }

    @Test("first run defaults to Smart Bopomofo")
    func defaultMode() {
        let (settings, _) = settings()
        #expect(settings.mode == .smart)
    }

    @Test("traditional mode persists")
    func persistence() {
        let (settings, defaults) = settings()
        settings.setMode(.traditional)
        #expect(BopomofoCompositionModeSettings(defaults: defaults).mode == .traditional)
    }

    @Test("app changes reach the keyboard without overriding newer keyboard-local changes")
    func sharedSettings() {
        let local = UserDefaults(suiteName: "keykey.local.\(UUID().uuidString)")!
        let shared = UserDefaults(suiteName: "keykey.shared.\(UUID().uuidString)")!
        let keyboardMode = BopomofoCompositionModeSettings(
            defaults: local, sharedDefaults: shared
        )
        let appMode = BopomofoCompositionModeSettings(
            defaults: local, sharedDefaults: shared, writesShared: true
        )
        let appColor = CandidateColorSettings(
            defaults: local, sharedDefaults: shared, writesShared: true
        )

        keyboardMode.setMode(.traditional)
        appMode.setMode(.smart)
        #expect(keyboardMode.mode == .smart)
        keyboardMode.setMode(.traditional)
        appColor.setColor(.green)
        #expect(keyboardMode.mode == .traditional)
        appMode.setMode(.smart)
        #expect(keyboardMode.mode == .smart)
    }

    @Test("an app reset request clears private keyboard learning once")
    func sharedLearningReset() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let local = UserDefaults(suiteName: "keykey.reset-local.\(UUID().uuidString)")!
        let shared = UserDefaults(suiteName: "keykey.reset-shared.\(UUID().uuidString)")!
        let keyboard = try SmartMandarinUserData(
            phrasesURL: directory.appendingPathComponent("group/UserPhrase.db"),
            learningURL: directory.appendingPathComponent("keyboard/learning.db"),
            writablePhrases: false
        )
        keyboard.learnCandidate(query: "AB", current: "妳")
        #expect(keyboard.learnedCandidate(for: "AB") == "妳")

        let request = KeyboardLearningResetRequest(localDefaults: local, sharedDefaults: shared)
        request.request()
        #expect(request.applyIfNeeded(to: keyboard))
        #expect(keyboard.learnedCandidate(for: "AB") == nil)
        keyboard.learnCandidate(query: "AB", current: "你")
        #expect(!request.applyIfNeeded(to: keyboard))
        #expect(keyboard.learnedCandidate(for: "AB") == "你")
    }
}
