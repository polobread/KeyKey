import Foundation

/// Which associated-phrase collections are enabled.
///
/// Stored in the extension's own `UserDefaults`, which needs no Full Access
/// because the settings panel lives inside the keyboard rather than in the
/// container app.
///
/// An absent key is a first run and gets the base collection. An explicitly
/// empty set means the user turned everything off and must not be quietly
/// reset -- the same contract as the Android `PhraseSettings`.
public struct PhraseSettings {
    public static let baseCollection = "McBopomofo"
    private static let key = "enabled_phrase_collections"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var enabledCollections: Set<String> {
        guard let stored = defaults.array(forKey: Self.key) as? [String] else {
            return [Self.baseCollection]
        }
        return Set(stored)
    }

    public func setEnabledCollections(_ collections: Set<String>) {
        defaults.set(Array(collections).sorted(), forKey: Self.key)
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
        defaults.removeObject(forKey: Self.key)
    }
}
