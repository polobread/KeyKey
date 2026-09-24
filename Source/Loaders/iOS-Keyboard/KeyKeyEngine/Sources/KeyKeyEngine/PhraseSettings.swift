import Foundation

/// Which associated-phrase collections are enabled.
///
/// Keyboard changes stay in its own `UserDefaults`; the containing app can
/// provide a newer value through the App Group without Full Access.
///
/// An absent key is a first run and gets the base collection. An explicitly
/// empty set means the user turned everything off and must not be quietly
/// reset -- the same contract as the Android `PhraseSettings`.
public struct PhraseSettings {
    public static let baseCollection = "McBopomofo"
    private static let key = "enabled_phrase_collections"

    private let store: KeyboardPreferenceStore

    public init(
        defaults: UserDefaults = .standard, sharedDefaults: UserDefaults? = nil,
        writesShared: Bool = false
    ) {
        store = KeyboardPreferenceStore(
            defaults: defaults, sharedDefaults: sharedDefaults, writesShared: writesShared
        )
    }

    public var enabledCollections: Set<String> {
        guard let stored = store.object(forKey: Self.key) as? [String] else {
            return [Self.baseCollection]
        }
        return Set(stored)
    }

    public func setEnabledCollections(_ collections: Set<String>) {
        store.set(Array(collections).sorted(), forKey: Self.key)
    }

    public func setCollection(_ source: String, enabled: Bool) {
        var collections = enabledCollections
        if enabled {
            collections.insert(source)
        } else {
            collections.remove(source)
        }
        setEnabledCollections(collections)
    }

    /// Restores the first-run state, so a later read falls back to the base
    /// collection rather than to an empty set.
    public func clearStoredSelection() {
        store.removeObject(forKey: Self.key)
    }
}
