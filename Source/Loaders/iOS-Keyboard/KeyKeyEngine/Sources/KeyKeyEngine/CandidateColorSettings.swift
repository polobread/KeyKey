import Foundation

/// The candidate-selection colours shared with the desktop frontends.
public enum CandidateColor: String, CaseIterable, Sendable, Equatable {
    case purple = "Purple"
    case green = "Green"
    case yellow = "Yellow"
    case red = "Red"
}

/// Persists the candidate selection colour inside the keyboard extension.
/// Missing and unknown values intentionally fall back to the macOS default.
public struct CandidateColorSettings {
    private static let key = "candidate_highlight_color"
    private let store: KeyboardPreferenceStore

    public init(
        defaults: UserDefaults = .standard, sharedDefaults: UserDefaults? = nil,
        writesShared: Bool = false
    ) {
        store = KeyboardPreferenceStore(
            defaults: defaults, sharedDefaults: sharedDefaults, writesShared: writesShared
        )
    }

    public var color: CandidateColor {
        guard let value = store.object(forKey: Self.key) as? String,
              let color = CandidateColor(rawValue: value)
        else { return .purple }
        return color
    }

    public func setColor(_ color: CandidateColor) {
        store.set(color.rawValue, forKey: Self.key)
    }
}
