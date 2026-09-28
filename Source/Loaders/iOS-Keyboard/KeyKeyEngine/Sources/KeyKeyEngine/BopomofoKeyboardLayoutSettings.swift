import Foundation

public final class BopomofoKeyboardLayoutSettings {
    public static let key = "bopomofoKeyboardLayout"
    private let store: KeyboardPreferenceStore

    public init(defaults: UserDefaults = .standard, sharedDefaults: UserDefaults? = nil,
                writesShared: Bool = false) {
        store = KeyboardPreferenceStore(defaults: defaults, sharedDefaults: sharedDefaults,
                                        writesShared: writesShared)
    }

    public var layout: BopomofoKeyboardLayout {
        (store.object(forKey: Self.key) as? String)
            .flatMap(BopomofoKeyboardLayout.init(rawValue:)) ?? .standard
    }

    public func setLayout(_ layout: BopomofoKeyboardLayout) {
        store.set(layout.rawValue, forKey: Self.key)
    }
}
