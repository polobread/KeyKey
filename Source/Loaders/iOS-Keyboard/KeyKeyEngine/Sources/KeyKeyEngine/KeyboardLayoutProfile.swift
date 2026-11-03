import Foundation

/// A visual preset, independent of Standard/Hsu mappings and the input engine.
/// Stable IDs are stored in preferences; labels and the number of presets may change.
public struct KeyboardLayoutProfile: Equatable, Identifiable, Sendable {
    public enum Orientation: CaseIterable, Sendable { case portrait, landscape }
    public enum Plane: CaseIterable, Sendable {
        case bopomofo, cangjie, simplex, english, numberSymbols

        public static func resolve(inputMethod: ChineseInputMethod, mode: KeyboardInput.InputMode) -> Plane {
            switch mode {
            case .english: return .english
            case .number: return .numberSymbols
            case .bopomofo:
                switch inputMethod {
                case .smart, .traditional: return .bopomofo
                case .cangjie: return .cangjie
                case .simplex: return .simplex
                }
            }
        }
    }

    /// Shift is a variant within a placement, not another input-method plane.
    public struct Placement: Equatable, Sendable {
        public let rows: [[String]]
        public let shiftedRows: [[String]]
    }

    /// Every orientation declares all five placements, even when they share rows.
    public struct Placements: Equatable, Sendable {
        public let bopomofo: Placement
        public let cangjie: Placement
        public let simplex: Placement
        public let english: Placement
        public let numberSymbols: Placement

        public func placement(for plane: Plane) -> Placement {
            switch plane {
            case .bopomofo: return bopomofo
            case .cangjie: return cangjie
            case .simplex: return simplex
            case .english: return english
            case .numberSymbols: return numberSymbols
            }
        }
    }

    public struct SplitGeometry: Equatable, Sendable {
        public let minimumExpandedWidth: Double
        public let punctuation: [String]
        public let keySplit: Int
        public let expandedKeySplit: Int
        public let compositionSplit: Int
        public let candidateSplit: Int
        public let expandedCandidateSplit: Int
        public let expandedFunctionWeights: [String: Double]
    }

    public let id: String
    public let displayName: String
    public let portrait: Placements
    public let landscape: Placements
    public let functionKeys: [String]
    public let functionWeights: [String: Double]
    public let keySpacing: Double
    public let stripSpacing: Double
    public let compositionCellCount: Int
    public let splitGeometry: SplitGeometry?
    public let portraitMetrics: KeyboardMetrics
    public let compactMetrics: KeyboardMetrics
    public let wideMetrics: KeyboardMetrics

    public func placements(for orientation: Orientation) -> Placements {
        orientation == .portrait ? portrait : landscape
    }

    public func rows(orientation: Orientation, plane: Plane, shifted: Bool) -> [[String]] {
        let placement = placements(for: orientation).placement(for: plane)
        return shifted ? placement.shiftedRows : placement.rows
    }

    public func rows(orientation: Orientation, inputMethod: ChineseInputMethod,
                     mode: KeyboardInput.InputMode, shifted: Bool) -> [[String]] {
        rows(orientation: orientation, plane: Plane.resolve(inputMethod: inputMethod, mode: mode), shifted: shifted)
    }

    public func functionWeight(for key: String, expanded: Bool = false) -> Double {
        if expanded, let weight = splitGeometry?.expandedFunctionWeights[key] { return weight }
        return functionWeights[key] ?? 1
    }

    public func metrics(compactHeight: Bool, isPad: Bool, regularWidth: Bool) -> KeyboardMetrics {
        if isPad { return wideMetrics }
        if compactHeight { return compactMetrics }
        return regularWidth ? wideMetrics : portraitMetrics
    }

    /// The original full keyboard, captured without changing key order or scale.
    public static let full = KeyboardLayoutProfile(
        id: "full", displayName: "滿版",
        portrait: OriginalFullLayout.placements, landscape: OriginalFullLayout.placements,
        functionKeys: ["MODE", "SYMBOL", "SETTINGS", "，", "SPACE", "。", "BACKSPACE", "ENTER"],
        functionWeights: ["MODE": 1.65, "SPACE": 3.8, "BACKSPACE": 1.4, "ENTER": 1.4],
        keySpacing: 3, stripSpacing: 2, compositionCellCount: 11, splitGeometry: nil,
        portraitMetrics: .portrait, compactMetrics: .compact, wideMetrics: .pad
    )

    /// Preserve the existing split choice while future visual profiles are added.
    /// This preset is usable on supported widths; width alone does not identify a Duo.
    public static let split = KeyboardLayoutProfile(
        id: "split", displayName: "左右分離", portrait: full.portrait, landscape: full.landscape,
        functionKeys: full.functionKeys, functionWeights: full.functionWeights,
        keySpacing: full.keySpacing, stripSpacing: full.stripSpacing,
        compositionCellCount: full.compositionCellCount,
        splitGeometry: SplitGeometry(minimumExpandedWidth: 600,
            punctuation: ["，", "。", "、", "？"], keySplit: 5, expandedKeySplit: 6,
            compositionSplit: 6, candidateSplit: 5, expandedCandidateSplit: 6,
            expandedFunctionWeights: ["MODE": 1.5, "SYMBOL": 1.25, "SETTINGS": 1.25,
                                      "SPACE": 2, "BACKSPACE": 2, "ENTER": 2]),
        portraitMetrics: full.portraitMetrics, compactMetrics: full.compactMetrics,
        wideMetrics: full.wideMetrics
    )

    /// The picker and shared profile checks enumerate this registry, not two fixed cases.
    public static let available: [KeyboardLayoutProfile] = [.full, .split]

    public static func resolve(id: String?) -> KeyboardLayoutProfile {
        available.first { $0.id == id } ?? .full
    }
}

public final class KeyboardLayoutProfileSettings {
    private let defaults: UserDefaults
    private static let key = "keyboardLayoutProfile"
    private static let previousKey = "keyboardPresentation"

    // Extension-private preferences do not require Full Access.
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var profile: KeyboardLayoutProfile {
        KeyboardLayoutProfile.resolve(id: defaults.string(forKey: Self.key)
            ?? defaults.string(forKey: Self.previousKey))
    }

    public func setProfile(_ profile: KeyboardLayoutProfile) {
        defaults.set(profile.id, forKey: Self.key)
    }
}

/// Original full-layout data is kept once; profiles can reuse or replace the planes.
private enum OriginalFullLayout {
    static let bopomofoRows: [[String]] = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-"],
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "@"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l", ";", "EMOJI"],
        ["z", "x", "c", "v", "b", "n", "m", ",", ".", "/", "SHIFT"]
    ]

    static let shiftedEnglishRows: [[String]] = [
        ["!", "@", "#", "$", "%", "^", "&", "*", "(", ")", "_"],
        ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "@"],
        ["A", "S", "D", "F", "G", "H", "J", "K", "L", ":", "EMOJI"],
        ["Z", "X", "C", "V", "B", "N", "M", "<", ">", "?", "SHIFT"]
    ]

    static let numberRows: [[String]] = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-"],
        ["!", "@", "#", "$", "%", "^", "&", "*", "(", ")", "_"],
        ["+", "=", "[", "]", "{", "}", "<", ">", "/", "\\", "|"],
        ["~", "`", "\"", "'", ":", ";", "?", ",", ".", "…", "SHIFT"]
    ]

    static let shiftedNumberRows: [[String]] = [
        ["$", "€", "£", "¥", "₩", "₹", "₽", "¢", "₫", "₱", "฿"],
        ["＋", "－", "×", "÷", "=", "≠", "≈", "±", "<", ">", "∞"],
        ["←", "→", "↑", "↓", "↔", "↕", "↖", "↗", "↘", "↙", "⇒"],
        ["★", "☆", "●", "○", "■", "□", "▲", "△", "▼", "▽", "SHIFT"]
    ]

}

private extension OriginalFullLayout {
    static let placements = KeyboardLayoutProfile.Placements(
        bopomofo: .init(rows: bopomofoRows, shiftedRows: bopomofoRows),
        cangjie: .init(rows: bopomofoRows, shiftedRows: bopomofoRows),
        simplex: .init(rows: bopomofoRows, shiftedRows: bopomofoRows),
        english: .init(rows: bopomofoRows, shiftedRows: shiftedEnglishRows),
        numberSymbols: .init(rows: numberRows, shiftedRows: shiftedNumberRows)
    )
}
