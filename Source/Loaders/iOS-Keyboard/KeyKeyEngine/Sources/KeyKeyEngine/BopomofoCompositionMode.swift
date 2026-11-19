import Foundation

/// The containing app may write App Group preferences without Full Access.
/// The keyboard reads those values, while its own changes stay in its sandbox.
/// Changes in the App supersede older keyboard choices for the same setting.
/// The App can also explicitly reapply a profile with its own shared revision.
public enum KeyboardSettingsProfile: String, CaseIterable, Sendable {
    case virtual, physical
    public var title: String {
        self == .virtual ? "虛擬鍵盤調整設定" : "實體鍵盤調整設定（App 編輯器）"
    }
}

public struct KeyboardPreferenceStore {
    public static let appGroupIdentifier = "group.io.github.polobread.inputmethod.chichi77.ios"
    // Older builds used one revision for every surface. Keep it as a frozen
    // fallback so upgrading does not discard acknowledged private choices.
    private static let legacyApplyDefaultsRevisionKey = "keyboardAppDefaultsRevision"

    private static func applyDefaultsRevisionKey(for profile: KeyboardSettingsProfile) -> String {
        "keyboardProfile." + profile.rawValue + ".appDefaultsRevision"
    }

    private var defaultsRevision: String? {
        sharedDefaults?.string(forKey: Self.applyDefaultsRevisionKey(for: applyDefaultsProfile))
            ?? sharedDefaults?.string(forKey: Self.legacyApplyDefaultsRevisionKey)
    }

    private let defaults: UserDefaults
    private let sharedDefaults: UserDefaults?
    private let writesShared: Bool
    private let profile: KeyboardSettingsProfile?
    private let applyDefaultsProfile: KeyboardSettingsProfile

    public init(
        defaults: UserDefaults = .standard, sharedDefaults: UserDefaults? = nil,
        writesShared: Bool = false, profile: KeyboardSettingsProfile? = nil,
        applyDefaultsProfile: KeyboardSettingsProfile? = nil
    ) {
        self.defaults = defaults
        self.sharedDefaults = sharedDefaults
        self.writesShared = writesShared
        self.profile = profile
        // Shared collection keys stay common while each surface acknowledges its
        // own reapply revision. Appearance preferences default to the virtual one.
        self.applyDefaultsProfile = applyDefaultsProfile ?? profile ?? .virtual
    }

    private func resolvedKey(_ key: String) -> String {
        guard let profile else { return key }
        let scoped = "keyboardProfile." + profile.rawValue + "." + key
        let target = writesShared ? sharedDefaults : defaults
        let marker = scoped + ".migrated"
        if target?.bool(forKey: marker) != true {
            // Snapshot the old effective value once. Never keep following legacy keys.
            // A virtual-only apply may happen before the physical profile is
            // first opened. Resolve this snapshot against the old global revision,
            // so that new virtual revisions cannot erase a legacy editor choice.
            let legacyRevision = sharedDefaults?.string(forKey: Self.legacyApplyDefaultsRevisionKey)
            if !(profile == .physical && key == "smartOmitsTones"),
               target?.object(forKey: scoped) == nil,
               let value = value(forKey: key, defaultsRevision: legacyRevision) {
                target?.set(value, forKey: scoped)
            }
            if writesShared {
                if let revision = sharedDefaults?.string(forKey: revisionKey(key)) {
                    target?.set(revision, forKey: revisionKey(scoped))
                }
            } else {
                // Carry the legacy revision, rather than acknowledging a newer App choice.
                target?.set(sharedDefaults?.string(forKey: revisionKey(key)),
                            forKey: appliedRevisionKey(scoped))
                target?.set(legacyRevision, forKey: appliedDefaultsRevisionKey(scoped))
            }
            target?.set(true, forKey: marker)
        }
        return scoped
    }

    public func object(forKey originalKey: String) -> Any? {
        value(forKey: resolvedKey(originalKey), defaultsRevision: defaultsRevision)
    }

    private func value(forKey key: String, defaultsRevision: String?) -> Any? {
        if writesShared { return sharedDefaults?.object(forKey: key) }
        let sharedValue = sharedDefaults?.object(forKey: key)
        let revision = sharedDefaults?.string(forKey: revisionKey(key))
        if defaults.string(forKey: appliedDefaultsRevisionKey(key)) == defaultsRevision,
           sharedValue == nil || defaults.string(forKey: appliedRevisionKey(key)) == revision {
            return defaults.object(forKey: key) ?? sharedValue
        }
        return sharedValue
    }

    /// Reapply one profile, including built-in defaults for unset preferences.
    /// Virtual application also includes appearance and the keyboard's phrase choice.
    public static func applyAppDefaults(in sharedDefaults: UserDefaults, profile: KeyboardSettingsProfile) {
        sharedDefaults.set(UUID().uuidString, forKey: applyDefaultsRevisionKey(for: profile))
    }

    public func set(_ value: Any, forKey originalKey: String) {
        let key = resolvedKey(originalKey)
        if writesShared {
            sharedDefaults?.set(value, forKey: key)
            sharedDefaults?.set(UUID().uuidString, forKey: revisionKey(key))
        } else {
            let revision = sharedDefaults?.string(forKey: revisionKey(key))
            let defaultsRevision = self.defaultsRevision
            defaults.set(value, forKey: key)
            defaults.set(revision, forKey: appliedRevisionKey(key))
            defaults.set(defaultsRevision, forKey: appliedDefaultsRevisionKey(key))
        }
    }

    public func removeObject(forKey originalKey: String) {
        let key = resolvedKey(originalKey)
        if writesShared {
            sharedDefaults?.removeObject(forKey: key)
            sharedDefaults?.set(UUID().uuidString, forKey: revisionKey(key))
        } else {
            defaults.removeObject(forKey: key)
            defaults.removeObject(forKey: appliedRevisionKey(key))
            defaults.removeObject(forKey: appliedDefaultsRevisionKey(key))
        }
    }

    private func revisionKey(_ key: String) -> String { key + ".appRevision" }
    private func appliedRevisionKey(_ key: String) -> String { key + ".appliedAppRevision" }
    private func appliedDefaultsRevisionKey(_ key: String) -> String { key + ".appliedAppDefaultsRevision" }
}

public enum BopomofoCompositionMode: String, CaseIterable, Sendable {
    case smart
    case traditional

    public var displayName: String {
        switch self {
        case .smart: "好打注音"
        case .traditional: "傳統注音"
        }
    }
}

/// Keyboard and editor changes remain private; an App Group setting from the
/// containing app can override either on the next opening.
public final class BopomofoCompositionModeSettings {
    public static let key = "bopomofoCompositionMode"

    private let store: KeyboardPreferenceStore

    public init(
        defaults: UserDefaults = .standard, sharedDefaults: UserDefaults? = nil,
        writesShared: Bool = false, profile: KeyboardSettingsProfile = .virtual
    ) {
        store = KeyboardPreferenceStore(
            defaults: defaults, sharedDefaults: sharedDefaults, writesShared: writesShared, profile: profile
        )
    }

    public var mode: BopomofoCompositionMode {
        guard let raw = store.object(forKey: Self.key) as? String,
              let stored = BopomofoCompositionMode(rawValue: raw)
        else { return .smart }
        return stored
    }

    public func setMode(_ mode: BopomofoCompositionMode) {
        store.set(mode.rawValue, forKey: Self.key)
    }
}

/// Independent surface choices. Keyboard writes stay in its private sandbox.
public struct SmartMandarinSpaceSettings {
    public static let key = "smartSpaceSelectsCandidates"
    private let store: KeyboardPreferenceStore
    public init(defaults: UserDefaults = .standard,
                sharedDefaults: UserDefaults? = UserDefaults(suiteName: KeyboardPreferenceStore.appGroupIdentifier),
                writesShared: Bool = false, profile: KeyboardSettingsProfile = .virtual) {
        store = KeyboardPreferenceStore(defaults: defaults, sharedDefaults: sharedDefaults,
                                       writesShared: writesShared, profile: profile)
    }
    public var enabled: Bool { store.object(forKey: Self.key) as? Bool ?? false }
    public func setEnabled(_ enabled: Bool) { store.set(enabled, forKey: Self.key) }
}

/// Frontend configuration for existing Guanyinma desktop behaviors.
public struct KeyboardTypingOptions: Equatable, Sendable {
    public var useBigrams = true
    public var candidateCursorAtEnd = false
    public var selectionReturnsToEnd = false
    public var clearComposingWithEscape = false
    public var maximumCompletedSyllables = 10
    public var ignoreCapsLockInChinese = false
    public var shiftAlwaysUppercase = false
    public init() {}
}

public struct KeyboardTypingSettings {
    private let store: KeyboardPreferenceStore
    public init(defaults: UserDefaults = .standard, sharedDefaults: UserDefaults? = nil,
                writesShared: Bool = false, profile: KeyboardSettingsProfile = .virtual) {
        store = KeyboardPreferenceStore(defaults: defaults, sharedDefaults: sharedDefaults,
                                       writesShared: writesShared, profile: profile)
    }
    public var options: KeyboardTypingOptions {
        var result = KeyboardTypingOptions()
        result.useBigrams = bool("useBigrams", default: true)
        result.candidateCursorAtEnd = bool("candidateCursorAtEnd")
        result.selectionReturnsToEnd = bool("selectionReturnsToEnd")
        result.clearComposingWithEscape = bool("clearComposingWithEscape")
        result.maximumCompletedSyllables = min(20, max(10, store.object(forKey: "maximumCompletedSyllables") as? Int ?? 10))
        result.ignoreCapsLockInChinese = bool("ignoreCapsLockInChinese")
        result.shiftAlwaysUppercase = bool("shiftAlwaysUppercase")
        return result
    }
    public func setOptions(_ value: KeyboardTypingOptions) {
        let previous = options
        if value.useBigrams != previous.useBigrams { store.set(value.useBigrams, forKey: "useBigrams") }
        if value.candidateCursorAtEnd != previous.candidateCursorAtEnd { store.set(value.candidateCursorAtEnd, forKey: "candidateCursorAtEnd") }
        if value.selectionReturnsToEnd != previous.selectionReturnsToEnd { store.set(value.selectionReturnsToEnd, forKey: "selectionReturnsToEnd") }
        if value.clearComposingWithEscape != previous.clearComposingWithEscape { store.set(value.clearComposingWithEscape, forKey: "clearComposingWithEscape") }
        let maximum = min(20, max(10, value.maximumCompletedSyllables))
        if maximum != previous.maximumCompletedSyllables { store.set(maximum, forKey: "maximumCompletedSyllables") }
        if value.ignoreCapsLockInChinese != previous.ignoreCapsLockInChinese { store.set(value.ignoreCapsLockInChinese, forKey: "ignoreCapsLockInChinese") }
        if value.shiftAlwaysUppercase != previous.shiftAlwaysUppercase { store.set(value.shiftAlwaysUppercase, forKey: "shiftAlwaysUppercase") }
    }
    private func bool(_ key: String, default value: Bool = false) -> Bool {
        store.object(forKey: key) as? Bool ?? value
    }
}

/// The keyboard can change this preference in its private sandbox.
public struct SmartMandarinToneOmissionSettings {
    public static let displayName = "好打注音省略聲調"
    private static let key = "smartOmitsTones"
    private let store: KeyboardPreferenceStore

    public init(
        defaults: UserDefaults = .standard, sharedDefaults: UserDefaults? = nil,
        writesShared: Bool = false, profile: KeyboardSettingsProfile = .virtual
    ) {
        store = KeyboardPreferenceStore(
            defaults: defaults, sharedDefaults: sharedDefaults, writesShared: writesShared, profile: profile
        )
    }

    public var enabled: Bool { store.object(forKey: Self.key) as? Bool ?? false }
    public func setEnabled(_ enabled: Bool) { store.set(enabled, forKey: Self.key) }
}

public struct KeyboardClickSettings {
    private static let key = "inputClicksEnabled"
    private let store: KeyboardPreferenceStore

    public init(
        defaults: UserDefaults = .standard, sharedDefaults: UserDefaults? = nil,
        writesShared: Bool = false
    ) {
        store = KeyboardPreferenceStore(
            defaults: defaults, sharedDefaults: sharedDefaults, writesShared: writesShared
        )
    }

    public var enabled: Bool { store.object(forKey: Self.key) as? Bool ?? true }
    public func setEnabled(_ enabled: Bool) { store.set(enabled, forKey: Self.key) }
}

public struct KeyboardLearningResetRequest {
    private let sharedKey: String
    private let appliedKey: String
    private let localDefaults: UserDefaults
    private let sharedDefaults: UserDefaults?
    private let glyphSupport: CandidateGlyphSupport

    public init(
        localDefaults: UserDefaults = .standard, sharedDefaults: UserDefaults? = nil,
        glyphSupport: CandidateGlyphSupport = .shared
    ) {
        sharedKey = "guanyinmaLearningResetRequest"
        appliedKey = "guanyinmaLearningResetApplied"
        self.localDefaults = localDefaults
        self.sharedDefaults = sharedDefaults
        self.glyphSupport = glyphSupport
    }

    public func request() {
        glyphSupport.reset()
        sharedDefaults?.set(UUID().uuidString, forKey: sharedKey)
    }

    /// Consume only this core's request, and only after its storage reset succeeds.
    public func applyIfNeeded(using reset: () throws -> Void) -> Bool {
        guard let request = sharedDefaults?.string(forKey: sharedKey),
              request != localDefaults.string(forKey: appliedKey) else { return false }
        glyphSupport.reset()
        do {
            try reset()
            localDefaults.set(request, forKey: appliedKey)
            return true
        } catch {
            return false
        }
    }

}
