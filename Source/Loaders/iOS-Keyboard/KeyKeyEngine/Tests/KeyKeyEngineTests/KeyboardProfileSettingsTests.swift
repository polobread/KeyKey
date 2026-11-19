import Foundation
import Testing
@testable import KeyKeyEngine

@Suite("Keyboard profile settings")
struct KeyboardProfileSettingsTests {
    private func suite() -> UserDefaults {
        UserDefaults(suiteName: "keykey.profiles.\(UUID())")!
    }
    @Test func migrationSnapshotsEachSurfaceAndAppRevisionsRemainIndependent() {
        let shared = suite(), keyboard = suite(), editor = suite()
        shared.set(false, forKey: "simplifiedChineseOutput")
        shared.set("legacy-app", forKey: "simplifiedChineseOutput.appRevision")
        keyboard.set(true, forKey: "simplifiedChineseOutput")
        keyboard.set("legacy-app", forKey: "simplifiedChineseOutput.appliedAppRevision")
        editor.set(false, forKey: "simplifiedChineseOutput")
        editor.set("legacy-app", forKey: "simplifiedChineseOutput.appliedAppRevision")
        let virtual = SimplifiedChineseOutputSettings(defaults: keyboard, sharedDefaults: shared)
        let physical = SimplifiedChineseOutputSettings(defaults: editor, sharedDefaults: shared, profile: .physical)
        #expect(virtual.enabled)
        #expect(!physical.enabled)
        // Reading the App defaults must not erase an already-migrated private choice.
        let appVirtual = SimplifiedChineseOutputSettings(sharedDefaults: shared, writesShared: true)
        let appPhysical = SimplifiedChineseOutputSettings(sharedDefaults: shared, writesShared: true, profile: .physical)
        #expect(!appVirtual.enabled)
        #expect(!appPhysical.enabled)
        #expect(virtual.enabled)
        shared.set(false, forKey: "simplifiedChineseOutput")
        #expect(virtual.enabled) // legacy values are not re-read
        appPhysical.setEnabled(true)
        #expect(physical.enabled)
        #expect(virtual.enabled)
        appVirtual.setEnabled(false)
        #expect(!virtual.enabled)
        virtual.setEnabled(true)
        physical.setEnabled(false)
        KeyboardPreferenceStore.applyAppDefaults(in: shared, profile: .virtual)
        #expect(!virtual.enabled)
        #expect(!physical.enabled)
        virtual.setEnabled(true)
        KeyboardPreferenceStore.applyAppDefaults(in: shared, profile: .physical)
        #expect(physical.enabled)
        #expect(virtual.enabled)
    }
    @Test func legacyTouchOmissionDoesNotTurnOnNewHardwareFeature() {
        let shared = suite(), local = suite()
        shared.set(true, forKey: "smartOmitsTones")
        local.set(true, forKey: "smartOmitsTones")
        let touch = SmartMandarinToneOmissionSettings(defaults: local, sharedDefaults: shared)
        let hardware = SmartMandarinToneOmissionSettings(defaults: local, sharedDefaults: shared, profile: .physical)
        #expect(touch.enabled)
        #expect(!hardware.enabled)
        hardware.setEnabled(true)
        touch.setEnabled(false)
        #expect(hardware.enabled)
        #expect(!touch.enabled)
    }
    @Test func methodsLayoutsSpaceAndTablesAreIndependent() {
        let shared = suite(), local = suite()
        shared.set(true, forKey: SmartMandarinSpaceSettings.key)
        shared.set(BopomofoKeyboardLayout.eten26.rawValue, forKey: BopomofoKeyboardLayoutSettings.key)
        let virtualMethod = ChineseInputMethodSettings(defaults: local, sharedDefaults: shared)
        let physicalMethod = ChineseInputMethodSettings(defaults: local, sharedDefaults: shared, profile: .physical)
        let virtualSpace = SmartMandarinSpaceSettings(defaults: local, sharedDefaults: shared)
        let physicalSpace = SmartMandarinSpaceSettings(defaults: local, sharedDefaults: shared, profile: .physical)
        #expect(virtualSpace.enabled && physicalSpace.enabled)
        physicalSpace.setEnabled(false)
        #expect(virtualSpace.enabled && !physicalSpace.enabled)
        virtualMethod.setMethod(.cangjie)
        physicalMethod.setMethod(.simplex)
        #expect(virtualMethod.method == .cangjie && physicalMethod.method == .simplex)
        var v = virtualMethod.options(for: .simplex, virtualKeyboard: true)
        var h = physicalMethod.options(for: .simplex)
        v.composeWhileTyping = true; h.composeWhileTyping = false
        virtualMethod.setOptions(v, for: .simplex, virtualKeyboard: true)
        physicalMethod.setOptions(h, for: .simplex)
        #expect(virtualMethod.options(for: .simplex, virtualKeyboard: true).composeWhileTyping)
        #expect(!physicalMethod.options(for: .simplex).composeWhileTyping)
        let layout = BopomofoKeyboardLayoutSettings(defaults: local, sharedDefaults: shared, profile: .physical)
        layout.setLayout(.hsu)
        #expect(BopomofoKeyboardLayoutSettings(defaults: local, sharedDefaults: shared).layout == .eten26)
    }
    @Test func changingOneAppTypingOptionPreservesOtherLocalChoicesUntilApply() {
        let shared = suite(), local = suite()
        let app = KeyboardTypingSettings(sharedDefaults: shared, writesShared: true, profile: .physical)
        let editor = KeyboardTypingSettings(defaults: local, sharedDefaults: shared, profile: .physical)
        var options = editor.options
        options.selectionReturnsToEnd = true
        options.maximumCompletedSyllables = 15
        editor.setOptions(options)
        var defaults = app.options
        defaults.useBigrams = false
        app.setOptions(defaults)
        #expect(!editor.options.useBigrams)
        #expect(editor.options.selectionReturnsToEnd)
        #expect(editor.options.maximumCompletedSyllables == 15)
        KeyboardPreferenceStore.applyAppDefaults(in: shared, profile: .virtual)
        #expect(editor.options.selectionReturnsToEnd)
        #expect(editor.options.maximumCompletedSyllables == 15)
        KeyboardPreferenceStore.applyAppDefaults(in: shared, profile: .physical)
        #expect(!editor.options.selectionReturnsToEnd)
        #expect(editor.options.maximumCompletedSyllables == 10)
    }
    @Test func virtualApplyPreservesPhysicalChoicesAcrossNewReadersAndRepeatedApplies() {
        let shared = suite(), local = suite()
        let appMethod = ChineseInputMethodSettings(sharedDefaults: shared, writesShared: true, profile: .physical)
        appMethod.setMethod(.smart)
        let method = ChineseInputMethodSettings(defaults: local, sharedDefaults: shared, profile: .physical)
        method.setMethod(.simplex)
        var cangjie = method.options(for: .cangjie)
        cangjie.composeWhileTyping = false
        cangjie.clearOnError = false
        cangjie.dynamicFrequency = false
        cangjie.punctuation = 2
        method.setOptions(cangjie, for: .cangjie)
        var simplex = method.options(for: .simplex)
        simplex.composeWhileTyping = true
        simplex.dynamicFrequency = false
        method.setOptions(simplex, for: .simplex)
        BopomofoKeyboardLayoutSettings(defaults: local, sharedDefaults: shared, profile: .physical).setLayout(.eten26)
        SimplifiedChineseOutputSettings(defaults: local, sharedDefaults: shared, profile: .physical).setEnabled(true)
        SmartMandarinToneOmissionSettings(defaults: local, sharedDefaults: shared, profile: .physical).setEnabled(true)
        SmartMandarinSpaceSettings(defaults: local, sharedDefaults: shared, profile: .physical).setEnabled(true)
        let typing = KeyboardTypingSettings(defaults: local, sharedDefaults: shared, profile: .physical)
        var options = typing.options
        options.useBigrams = false
        options.candidateCursorAtEnd = true
        options.selectionReturnsToEnd = true
        options.clearComposingWithEscape = true
        options.maximumCompletedSyllables = 17
        options.ignoreCapsLockInChinese = true
        options.shiftAlwaysUppercase = true
        typing.setOptions(options)
        let virtualScript = SimplifiedChineseOutputSettings(defaults: local, sharedDefaults: shared)
        SimplifiedChineseOutputSettings(sharedDefaults: shared, writesShared: true).setEnabled(false)

        for _ in 0..<2 {
            virtualScript.setEnabled(true)
            KeyboardPreferenceStore.applyAppDefaults(in: shared, profile: .virtual)
            #expect(!virtualScript.enabled)
            // Reconstruct the App and editor readers, as when reopening either page.
            #expect(ChineseInputMethodSettings(sharedDefaults: shared, writesShared: true, profile: .physical).method == .smart)
            let reopened = ChineseInputMethodSettings(defaults: local, sharedDefaults: shared, profile: .physical)
            #expect(reopened.method == .simplex)
            #expect(reopened.options(for: .cangjie) == cangjie)
            #expect(reopened.options(for: .simplex) == simplex)
            #expect(BopomofoKeyboardLayoutSettings(defaults: local, sharedDefaults: shared, profile: .physical).layout == .eten26)
            #expect(SimplifiedChineseOutputSettings(defaults: local, sharedDefaults: shared, profile: .physical).enabled)
            #expect(SmartMandarinToneOmissionSettings(defaults: local, sharedDefaults: shared, profile: .physical).enabled)
            #expect(SmartMandarinSpaceSettings(defaults: local, sharedDefaults: shared, profile: .physical).enabled)
            #expect(KeyboardTypingSettings(defaults: local, sharedDefaults: shared, profile: .physical).options == options)
        }
    }

    @Test func virtualApplyBeforeFirstPhysicalReadPreservesAcknowledgedLegacyEditorChoice() {
        let shared = suite(), local = suite()
        shared.set("legacy-apply", forKey: "keyboardAppDefaultsRevision")
        shared.set(false, forKey: "simplifiedChineseOutput")
        shared.set("legacy-setting", forKey: "simplifiedChineseOutput.appRevision")
        local.set(true, forKey: "simplifiedChineseOutput")
        local.set("legacy-setting", forKey: "simplifiedChineseOutput.appliedAppRevision")
        local.set("legacy-apply", forKey: "simplifiedChineseOutput.appliedAppDefaultsRevision")
        let appVirtual = SimplifiedChineseOutputSettings(sharedDefaults: shared, writesShared: true)
        #expect(!appVirtual.enabled)
        KeyboardPreferenceStore.applyAppDefaults(in: shared, profile: .virtual)
        let physical = SimplifiedChineseOutputSettings(defaults: local, sharedDefaults: shared, profile: .physical)
        #expect(physical.enabled)
        let appPhysical = SimplifiedChineseOutputSettings(sharedDefaults: shared, writesShared: true, profile: .physical)
        #expect(!appPhysical.enabled)
        #expect(physical.enabled)
        #expect(!SimplifiedChineseOutputSettings(defaults: local, sharedDefaults: shared).enabled)
        KeyboardPreferenceStore.applyAppDefaults(in: shared, profile: .virtual)
        #expect(SimplifiedChineseOutputSettings(defaults: local, sharedDefaults: shared, profile: .physical).enabled)
        // Real changes to a physical App default still replace that setting alone.
        appPhysical.setEnabled(false)
        #expect(!physical.enabled)
        #expect(shared.string(forKey: "keyboardAppDefaultsRevision") == "legacy-apply")
    }

    @Test func pendingLegacyGlobalApplyStillTakesEffectWhenProfilesMigrate() {
        let shared = suite(), local = suite()
        shared.set("new-legacy-apply", forKey: "keyboardAppDefaultsRevision")
        shared.set(false, forKey: "simplifiedChineseOutput")
        local.set(true, forKey: "simplifiedChineseOutput")
        local.set("old-legacy-apply", forKey: "simplifiedChineseOutput.appliedAppDefaultsRevision")
        for profile in KeyboardSettingsProfile.allCases {
            let app = SimplifiedChineseOutputSettings(sharedDefaults: shared, writesShared: true, profile: profile)
            let reader = SimplifiedChineseOutputSettings(defaults: local, sharedDefaults: shared, profile: profile)
            #expect(!app.enabled)
            #expect(!reader.enabled)
            reader.setEnabled(true)
            #expect(SimplifiedChineseOutputSettings(defaults: local, sharedDefaults: shared, profile: profile).enabled)
        }
    }

    @Test func completeCoreConfigurationKeepsTouchAndPhysicalBoundaries() {
        var options = KeyboardTypingOptions()
        options.useBigrams = false
        options.maximumCompletedSyllables = 20
        options.candidateCursorAtEnd = true
        options.selectionReturnsToEnd = true
        options.clearComposingWithEscape = true
        options.shiftAlwaysUppercase = true
        let physical = GuanyinmaInputEngine.smartConfiguration(hardware: true, space: false,
            omitsTones: true, options: options)
        #expect(physical["max_completed_syllables"] as? Int == 20)
        for key in ["omit_tone", "candidate_cursor_at_end", "selection_returns_to_end",
                    "clear_composing_with_escape", "shift_always_uppercase"] {
            #expect(physical[key] as? Bool == true)
        }
        #expect(physical["use_bigrams"] as? Bool == false)
        #expect(physical["shift_at_limit"] as? Bool == false)
        let touch = GuanyinmaInputEngine.smartConfiguration(hardware: false, space: true,
            phoneticGrid: true, omitsTones: true, options: options)
        #expect(touch["max_completed_syllables"] as? Int == 12)
        #expect(touch["omit_tone"] as? Bool == false)
        #expect(touch["candidate_cursor_at_end"] as? Bool == false)
        #expect(touch["shift_at_limit"] as? Bool == true)
    }
}
