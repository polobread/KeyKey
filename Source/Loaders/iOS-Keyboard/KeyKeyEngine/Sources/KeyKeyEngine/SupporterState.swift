import Foundation

/// Shared, local state for the optional one-time supporter purchase.
///
/// The keyboard remains fully functional without a purchase. After 30 days the
/// empty Bopomofo status line may show a small invitation to support continued
/// development, matching the Android frontend. The cached entitlement and
/// first-use date live in an App Group so the container app can update them
/// without granting the keyboard extension Full Access.
public struct SupporterState {
    public static let productIdentifier = "chichi_supporter"
    public static let appGroupIdentifier = "group.io.github.polobread.inputmethod.chichi77.ios"
    public static let trialDuration: TimeInterval = 30 * 24 * 60 * 60

    private enum Key {
        static let firstUse = "supporter_first_use"
        static let supporter = "supporter_entitled"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
            ?? UserDefaults(suiteName: Self.appGroupIdentifier)
            ?? .standard
    }

    @discardableResult
    public func recordFirstUse(at date: Date = Date()) -> Date {
        let timestamp = defaults.double(forKey: Key.firstUse)
        guard timestamp <= 0 else { return Date(timeIntervalSince1970: timestamp) }
        defaults.set(date.timeIntervalSince1970, forKey: Key.firstUse)
        return date
    }

    public var isSupporter: Bool {
        defaults.bool(forKey: Key.supporter)
    }

    public func setSupporter(_ supporter: Bool) {
        defaults.set(supporter, forKey: Key.supporter)
    }

    public func shouldShowSupportPrompt(at now: Date = Date()) -> Bool {
        Self.shouldShowSupportPrompt(
            firstUse: recordFirstUse(at: now), now: now, supporter: isSupporter
        )
    }

    public static func shouldShowSupportPrompt(
        firstUse: Date, now: Date, supporter: Bool
    ) -> Bool {
        !supporter && now.timeIntervalSince(firstUse) >= trialDuration
    }
}
