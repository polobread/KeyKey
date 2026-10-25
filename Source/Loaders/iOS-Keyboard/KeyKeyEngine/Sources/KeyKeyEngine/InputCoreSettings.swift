import Foundation

/// The preferred backend uses the same per-setting App Group revision as the
/// input method. Keyboard/editor overrides remain private until the App changes
/// this setting again. Applying the preference waits for a safe engine boundary.
public final class InputCoreSettings {
    public static let key = "inputCore"
    private let store: KeyboardPreferenceStore

    public init(
        defaults: UserDefaults = .standard, sharedDefaults: UserDefaults? = nil,
        writesShared: Bool = false
    ) {
        store = KeyboardPreferenceStore(
            defaults: defaults, sharedDefaults: sharedDefaults, writesShared: writesShared
        )
    }

    public var core: InputCore {
        guard let raw = store.object(forKey: Self.key) as? String,
              let core = InputCore(rawValue: raw) else { return .swift }
        return core
    }

    public func setCore(_ core: InputCore) {
        store.set(core.rawValue, forKey: Self.key)
    }
}
