import Foundation

/// The containing app may write App Group preferences without Full Access.
/// The keyboard reads those values, while its own changes stay in its sandbox.
/// Changes in the App supersede older keyboard choices for the same setting.
/// The App can also explicitly reapply all defaults with a shared revision.
public struct KeyboardPreferenceStore {
    public static let appGroupIdentifier = "group.io.github.polobread.inputmethod.chichi77.ios"
    private static let applyDefaultsRevisionKey = "keyboardAppDefaultsRevision"

    private let defaults: UserDefaults
    private let sharedDefaults: UserDefaults?
    private let writesShared: Bool

    public init(
        defaults: UserDefaults = .standard, sharedDefaults: UserDefaults? = nil,
        writesShared: Bool = false
    ) {
        self.defaults = defaults
        self.sharedDefaults = sharedDefaults
        self.writesShared = writesShared
    }

    public func object(forKey key: String) -> Any? {
        if writesShared { return sharedDefaults?.object(forKey: key) }
        let sharedValue = sharedDefaults?.object(forKey: key)
        let defaultsRevision = sharedDefaults?.string(forKey: Self.applyDefaultsRevisionKey)
        let revision = sharedDefaults?.string(forKey: revisionKey(key))
        if defaults.string(forKey: appliedDefaultsRevisionKey(key)) == defaultsRevision,
           sharedValue == nil || defaults.string(forKey: appliedRevisionKey(key)) == revision {
            return defaults.object(forKey: key) ?? sharedValue
        }
        return sharedValue
    }

    /// Reapply all App choices together, including built-in defaults for unset preferences.
    public static func applyAppDefaults(in sharedDefaults: UserDefaults) {
        sharedDefaults.set(UUID().uuidString, forKey: applyDefaultsRevisionKey)
    }

    public func set(_ value: Any, forKey key: String) {
        if writesShared {
            sharedDefaults?.set(value, forKey: key)
            sharedDefaults?.set(UUID().uuidString, forKey: revisionKey(key))
        } else {
            let revision = sharedDefaults?.string(forKey: revisionKey(key))
            let defaultsRevision = sharedDefaults?.string(forKey: Self.applyDefaultsRevisionKey)
            defaults.set(value, forKey: key)
            defaults.set(revision, forKey: appliedRevisionKey(key))
            defaults.set(defaultsRevision, forKey: appliedDefaultsRevisionKey(key))
        }
    }

    public func removeObject(forKey key: String) {
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
        writesShared: Bool = false
    ) {
        store = KeyboardPreferenceStore(
            defaults: defaults, sharedDefaults: sharedDefaults, writesShared: writesShared
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

/// One App Group value for both input surfaces. Only the container App writes it;
/// the extension can read it without requesting Full Access.
public struct SmartMandarinSpaceSettings {
    public static let key = "smartSpaceSelectsCandidates"
    private let sharedDefaults: UserDefaults?

    public init(sharedDefaults: UserDefaults? = UserDefaults(
        suiteName: KeyboardPreferenceStore.appGroupIdentifier
    )) {
        self.sharedDefaults = sharedDefaults
    }

    public var enabled: Bool { sharedDefaults?.bool(forKey: Self.key) ?? false }
    public func setEnabled(_ enabled: Bool) { sharedDefaults?.set(enabled, forKey: Self.key) }
}

/// The keyboard can change this preference in its private sandbox.
public struct SmartMandarinToneOmissionSettings {
    public static let displayName = "好打注音省略聲調"
    private static let key = "smartOmitsTones"
    private let store: KeyboardPreferenceStore

    public init(
        defaults: UserDefaults = .standard, sharedDefaults: UserDefaults? = nil,
        writesShared: Bool = false
    ) {
        store = KeyboardPreferenceStore(
            defaults: defaults, sharedDefaults: sharedDefaults, writesShared: writesShared
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
