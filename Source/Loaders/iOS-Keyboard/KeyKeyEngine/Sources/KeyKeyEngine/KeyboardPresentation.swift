import Foundation

/// A manual choice: extension geometry does not reveal the device's fold state.
public enum KeyboardPresentation: String, CaseIterable, Sendable {
    case full, split

    public var displayName: String { self == .full ? "完整" : "左右分離" }
}

public final class KeyboardPresentationSettings {
    private let defaults: UserDefaults
    private static let key = "keyboardPresentation"

    // This preference belongs to the extension and requires no Full Access.
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var presentation: KeyboardPresentation {
        defaults.string(forKey: Self.key).flatMap(KeyboardPresentation.init(rawValue:)) ?? .full
    }

    public func setPresentation(_ presentation: KeyboardPresentation) {
        defaults.set(presentation.rawValue, forKey: Self.key)
    }
}

/// Shared geometry for key, composition, candidate and weighted function rows.
/// Split halves have equal width; no button spans the centre gap.
public enum KeyboardRowGeometry {
    public static func frames(width: Double, height: Double, weights: [Double],
                              splitIndex: Int? = nil, spacing: Double = 3) -> [CGRect] {
        guard !weights.isEmpty, width > 0, height > 0 else { return [] }
        func group(_ range: Range<Int>, x: Double, width: Double) -> [CGRect] {
            let total = range.reduce(0.0) { $0 + weights[$1] }
            let available = max(0, width - spacing * Double(range.count - 1))
            var nextX = x
            return range.map { index in
                let keyWidth = available * weights[index] / total
                defer { nextX += keyWidth + spacing }
                return CGRect(x: nextX, y: 0, width: keyWidth, height: height)
            }
        }
        if let splitIndex, splitIndex > 0, splitIndex < weights.count {
            let gap = min(80, width * 0.1)
            let half = (width - gap) / 2
            return group(0..<splitIndex, x: 0, width: half)
                + group(splitIndex..<weights.count, x: half + gap, width: half)
        }
        return group(0..<weights.count, x: 0, width: width)
    }
}

/// A twelve-column layout for split keyboards with enough usable width.
/// The underlying eleven-key input planes and engine indices stay unchanged.
public enum ExpandedSplitKeyboardLayout {
    public static let minimumWidth: Double = 600
    public static let punctuation = ["，", "。", "、", "？"]

    public static func functionWeight(for key: String) -> Double {
        switch key {
        case "MODE": return 1.5
        case "SYMBOL", "SETTINGS": return 1.25
        case "SPACE", "BACKSPACE", "ENTER": return 2
        default: return 1
        }
    }
}
