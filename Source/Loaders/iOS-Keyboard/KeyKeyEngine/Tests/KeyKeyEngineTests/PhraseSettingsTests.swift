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

@Suite("Apply App keyboard defaults")
struct ApplyAppKeyboardDefaultsTests {
    @Test func virtualApplyKeepsEditorCollectionChoiceWhileAppCollectionChangesRemainShared() {
        let shared = UserDefaults(suiteName: "keykey.phrase-apply.shared.\(UUID())")!
        let keyboardDefaults = UserDefaults(suiteName: "keykey.phrase-apply.keyboard.\(UUID())")!
        let editorDefaults = UserDefaults(suiteName: "keykey.phrase-apply.editor.\(UUID())")!
        let app = PhraseSettings(sharedDefaults: shared, writesShared: true)
        let keyboard = PhraseSettings(defaults: keyboardDefaults, sharedDefaults: shared)
        let editor = PhraseSettings(defaults: editorDefaults, sharedDefaults: shared, applyDefaultsProfile: .physical)
        app.setEnabledCollections(["taiwan"])
        keyboard.setEnabledCollections([PhraseSettings.baseCollection])
        editor.setEnabledCollections(["china"])
        KeyboardPreferenceStore.applyAppDefaults(in: shared, profile: .virtual)
        #expect(keyboard.enabledCollections == ["taiwan"])
        #expect(editor.enabledCollections == ["china"])
        #expect(PhraseSettings(defaults: editorDefaults, sharedDefaults: shared,
                               applyDefaultsProfile: .physical).enabledCollections == ["china"])
        // A direct change to the common App source still propagates to both.
        app.setEnabledCollections(["hongkong-macao"])
        #expect(keyboard.enabledCollections == ["hongkong-macao"])
        #expect(editor.enabledCollections == ["hongkong-macao"])
        editor.setEnabledCollections([])
        KeyboardPreferenceStore.applyAppDefaults(in: shared, profile: .virtual)
        #expect(keyboard.enabledCollections == ["hongkong-macao"])
        #expect(editor.enabledCollections.isEmpty)
    }

    @Test func replacesKeyboardChoicesWithAppValuesAndBuiltInDefaults() throws {
        let localName = "keykey.keyboard-defaults.local.\(UUID())"
        let sharedName = "keykey.keyboard-defaults.shared.\(UUID())"
        let local = try #require(UserDefaults(suiteName: localName))
        let shared = try #require(UserDefaults(suiteName: sharedName))
        defer {
            local.removePersistentDomain(forName: localName)
            shared.removePersistentDomain(forName: sharedName)
        }

        let appMethod = ChineseInputMethodSettings(sharedDefaults: shared, writesShared: true)
        let appScript = SimplifiedChineseOutputSettings(sharedDefaults: shared, writesShared: true)
        let appLayout = BopomofoKeyboardLayoutSettings(sharedDefaults: shared, writesShared: true)
        let appProfile = KeyboardLayoutProfileSettings(sharedDefaults: shared, writesShared: true)
        let appPhrases = PhraseSettings(sharedDefaults: shared, writesShared: true)
        let sharedSpace = SmartMandarinSpaceSettings(sharedDefaults: shared, writesShared: true)
        appMethod.setMethod(.simplex)
        appScript.setEnabled(true)
        appLayout.setLayout(.hsu)
        appProfile.setProfile(.alignedSplit)
        appProfile.setKeycapArea(.medium)
        appProfile.setDeleteShiftPosition(.leftOfEnter)
        appPhrases.setEnabledCollections([])
        sharedSpace.setEnabled(true)

        var virtualCangjie = appMethod.options(for: .cangjie, virtualKeyboard: true)
        virtualCangjie.queryAtMaximum = true
        virtualCangjie.punctuation = 1
        appMethod.setOptions(virtualCangjie, for: .cangjie, virtualKeyboard: true)
        var physicalCangjie = appMethod.options(for: .cangjie)
        physicalCangjie.clearOnError = false
        appMethod.setOptions(physicalCangjie, for: .cangjie)
        var simplex = appMethod.options(for: .simplex)
        simplex.composeWhileTyping = true
        appMethod.setOptions(simplex, for: .simplex)

        let method = ChineseInputMethodSettings(defaults: local, sharedDefaults: shared)
        let script = SimplifiedChineseOutputSettings(defaults: local, sharedDefaults: shared)
        let toneOmission = SmartMandarinToneOmissionSettings(defaults: local, sharedDefaults: shared)
        let layout = BopomofoKeyboardLayoutSettings(defaults: local, sharedDefaults: shared)
        let profile = KeyboardLayoutProfileSettings(defaults: local, sharedDefaults: shared)
        let color = CandidateColorSettings(defaults: local, sharedDefaults: shared)
        let click = KeyboardClickSettings(defaults: local, sharedDefaults: shared)
        let phrases = PhraseSettings(defaults: local, sharedDefaults: shared)
        let height = KeyboardHeightSettings(defaults: local)
        let learningReset = KeyboardLearningResetRequest(localDefaults: local, sharedDefaults: shared)
        let taller = KeyboardEdgeGeometry(top: 1.25)

        method.setMethod(.traditional)
        method.setOptions(TableInputOptions(method: .cangjie), for: .cangjie, virtualKeyboard: true)
        method.setOptions(TableInputOptions(method: .cangjie), for: .cangjie)
        method.setOptions(TableInputOptions(method: .simplex), for: .simplex)
        script.setEnabled(false)
        toneOmission.setEnabled(true)
        layout.setLayout(.hanyuPinyin)
        profile.setProfile(.aligned)
        profile.setKeycapArea(.large)
        profile.setFontSize(.extraLarge)
        profile.setDeleteShiftPosition(.aboveEnter)
        color.setColor(.red)
        click.setEnabled(false)
        phrases.setEnabledCollections([PhraseSettings.baseCollection])
        height.setGeometry(taller, for: .portrait)

        #expect(method.method == .traditional)
        #expect(toneOmission.enabled)
        #expect(!phrases.enabledCollections.isEmpty)
        KeyboardPreferenceStore.applyAppDefaults(in: shared, profile: .virtual)

        #expect(method.method == .simplex)
        #expect(method.options(for: .cangjie, virtualKeyboard: true) == virtualCangjie)
        #expect(method.options(for: .cangjie) == physicalCangjie)
        #expect(method.options(for: .simplex) == simplex)
        #expect(script.enabled)
        #expect(!toneOmission.enabled)
        #expect(sharedSpace.enabled)
        #expect(layout.layout == .hsu)
        #expect(profile.profile.id == KeyboardLayoutProfile.alignedSplit.id)
        #expect(profile.keycapArea == .medium)
        #expect(profile.fontSize == .normal)
        #expect(profile.deleteShiftPosition == .leftOfEnter)
        #expect(color.color == .purple)
        #expect(click.enabled)
        #expect(phrases.enabledCollections.isEmpty)
        #expect(height.geometry(for: .portrait) == taller)
        #expect(!learningReset.applyIfNeeded { Issue.record("Applying defaults requested a reset") })

        script.setEnabled(false)
        toneOmission.setEnabled(true)
        #expect(!SimplifiedChineseOutputSettings(defaults: local, sharedDefaults: shared).enabled)
        #expect(toneOmission.enabled)
        KeyboardPreferenceStore.applyAppDefaults(in: shared, profile: .virtual)
        #expect(script.enabled)
        #expect(!toneOmission.enabled)
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

    @Test("Rust reset requests are once-only, retried on failure, and ignore legacy requests")
    func sharedLearningReset() throws {
        let localName = "keykey.reset-local.\(UUID())", sharedName = "keykey.reset-shared.\(UUID())"
        let local = try #require(UserDefaults(suiteName: localName))
        let shared = try #require(UserDefaults(suiteName: sharedName))
        defer { local.removePersistentDomain(forName: localName); shared.removePersistentDomain(forName: sharedName) }
        let request = KeyboardLearningResetRequest(localDefaults: local, sharedDefaults: shared)
        var calls = 0
        shared.set(UUID().uuidString, forKey: "smartMandarinLearningResetRequest")
        #expect(!request.applyIfNeeded { calls += 1 })
        request.request()
        #expect(!request.applyIfNeeded { throw CocoaError(.fileWriteNoPermission) })
        #expect(request.applyIfNeeded { calls += 1 })
        #expect(!request.applyIfNeeded { calls += 1 })
        #expect(calls == 1)
    }
}
