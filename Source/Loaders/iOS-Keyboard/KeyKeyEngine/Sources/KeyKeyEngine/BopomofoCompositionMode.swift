import Foundation

/// The containing app may write App Group preferences without Full Access.
/// The keyboard reads those values, while its own changes stay in its sandbox.
/// A revision per setting lets the most recent app change override an older
/// keyboard-local value without making unrelated settings jump back.
public struct KeyboardPreferenceStore {
    public static let appGroupIdentifier = "group.io.github.polobread.inputmethod.chichi77.ios"

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
        guard let sharedValue = sharedDefaults?.object(forKey: key) else {
            return defaults.object(forKey: key)
        }
        let revision = sharedDefaults?.string(forKey: revisionKey(key))
        if let localValue = defaults.object(forKey: key),
           defaults.string(forKey: appliedRevisionKey(key)) == revision {
            return localValue
        }
        return sharedValue
    }

    public func set(_ value: Any, forKey key: String) {
        if writesShared {
            sharedDefaults?.set(value, forKey: key)
            sharedDefaults?.set(UUID().uuidString, forKey: revisionKey(key))
        } else {
            defaults.set(value, forKey: key)
            defaults.set(sharedDefaults?.string(forKey: revisionKey(key)),
                         forKey: appliedRevisionKey(key))
        }
    }

    public func removeObject(forKey key: String) {
        if writesShared {
            sharedDefaults?.removeObject(forKey: key)
            sharedDefaults?.set(UUID().uuidString, forKey: revisionKey(key))
        } else {
            defaults.removeObject(forKey: key)
            defaults.removeObject(forKey: appliedRevisionKey(key))
        }
    }

    private func revisionKey(_ key: String) -> String { key + ".appRevision" }
    private func appliedRevisionKey(_ key: String) -> String { key + ".appliedAppRevision" }
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
    private static let sharedKey = "smartMandarinLearningResetRequest"
    private static let appliedKey = "smartMandarinLearningResetApplied"
    private let localDefaults: UserDefaults
    private let sharedDefaults: UserDefaults?

    public init(
        localDefaults: UserDefaults = .standard, sharedDefaults: UserDefaults? = nil
    ) {
        self.localDefaults = localDefaults
        self.sharedDefaults = sharedDefaults
    }

    public func request() {
        sharedDefaults?.set(UUID().uuidString, forKey: Self.sharedKey)
    }

    public func applyIfNeeded(to userData: SmartMandarinUserData?) -> Bool {
        guard let request = sharedDefaults?.string(forKey: Self.sharedKey),
              request != localDefaults.string(forKey: Self.appliedKey),
              let userData else { return false }
        do {
            try userData.resetLearning()
            localDefaults.set(request, forKey: Self.appliedKey)
            return true
        } catch {
            return false
        }
    }
}
