import Foundation

/// A visual preset, independent of Standard/Hsu mappings and the input engine.
/// Stable IDs are stored in preferences; labels and the number of presets may change.
public struct KeyboardLayoutProfile: Equatable, Identifiable, Sendable {
    public enum Orientation: CaseIterable, Sendable { case portrait, landscape }
    public enum Plane: CaseIterable, Hashable, Sendable {
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

    /// Horizontal key geometry is independent of the engine's input plane.
    public struct KeyRowGeometry: Equatable, Sendable {
        public let weights: [Double]
        public let leadingUnits: Double
        public let totalUnits: Double
        public let splitIndex: Int?

        public func frames(width: Double, height: Double, spacing: Double) -> [CGRect] {
            guard totalUnits > 0, width > 0, height > 0 else { return [] }
            if splitIndex != nil {
                return KeyboardRowGeometry.frames(width: width, height: height, weights: weights,
                    splitIndex: splitIndex, spacing: spacing)
            }
            // One pitch for the whole plane keeps reading keys identical across
            // rows, including the row whose last control consumes the remainder.
            let pitch = (width + spacing) / totalUnits
            var units = leadingUnits
            return weights.map { weight in
                defer { units += weight }
                return CGRect(x: units * pitch, y: 0,
                    width: max(0, weight * pitch - spacing), height: height)
            }
        }
    }

    public struct PlaneGeometry: Equatable, Sendable {
        public let rowOffsets: [Double]
    }

    public var rowOffsets: [Double] = []
    public var planeGeometryOverrides: [Plane: PlaneGeometry] = [:]
    public var usesStaggeredRows: Bool { rowOffsets.contains { $0 != 0 }
        || planeGeometryOverrides.values.contains { $0.rowOffsets.contains { $0 != 0 } } }

    public func rowOffsets(for plane: Plane) -> [Double] {
        planeGeometryOverrides[plane]?.rowOffsets ?? rowOffsets
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

    /// The saved original rows stay available for compatibility and baselines.
    /// Only the two control actions exchange positions; reading indices do not move.
    public func resolvedRows(orientation: Orientation, plane: Plane, shifted: Bool,
                             deleteShiftPosition: KeyboardDeleteShiftPosition) -> [[String]] {
        rows(orientation: orientation, plane: plane, shifted: shifted).map { row in
            row.map { deleteShiftPosition.mainKey(for: $0) }
        }
    }

    public func functionKeys(deleteShiftPosition: KeyboardDeleteShiftPosition) -> [String] {
        functionKeys.map { deleteShiftPosition.functionKey(for: $0) }
    }

    public func keyRowGeometry(for rows: [[String]], plane: Plane, rowIndex: Int,
                               expanded: Bool = false) -> KeyRowGeometry {
        guard rows.indices.contains(rowIndex) else {
            return .init(weights: [], leadingUnits: 0, totalUnits: 0, splitIndex: nil)
        }
        var weights = Array(repeating: 1.0, count: rows[rowIndex].count)
        if let split = splitGeometry {
            if expanded && split.punctuation.indices.contains(rowIndex) { weights.append(1) }
            return .init(weights: weights, leadingUnits: 0, totalUnits: Double(weights.count),
                splitIndex: expanded ? split.expandedKeySplit : split.keySplit)
        }
        let offsets = rowOffsets(for: plane)
        func offset(_ index: Int) -> Double {
            offsets.indices.contains(index) ? offsets[index] : 0
        }
        let units = usesStaggeredRows
            ? rows.indices.map { Double(rows[$0].count) + offset($0) }.max() ?? 0
            : Double(weights.count)
        let leading = offset(rowIndex)
        if usesStaggeredRows, let last = rows[rowIndex].last,
           last == "SHIFT" || last == "BACKSPACE", !weights.isEmpty {
            weights[weights.count - 1] += max(0, units - leading - Double(weights.count))
        }
        return .init(weights: weights, leadingUnits: leading, totalUnits: units, splitIndex: nil)
    }

    public func functionWeight(for key: String, expanded: Bool = false) -> Double {
        let weightedKey = key == "SHIFT" ? "BACKSPACE" : key
        if expanded, let weight = splitGeometry?.expandedFunctionWeights[weightedKey] { return weight }
        return functionWeights[weightedKey] ?? 1
    }

    public func metrics(compactHeight: Bool, isPad: Bool, regularWidth: Bool) -> KeyboardMetrics {
        if isPad { return wideMetrics }
        if compactHeight { return compactMetrics }
        return regularWidth ? wideMetrics : portraitMetrics
    }

    /// The original full keyboard, captured without changing key order or scale.
    public static let aligned = KeyboardLayoutProfile(
        id: "aligned", displayName: "對齊",
        portrait: OriginalFullLayout.placements, landscape: OriginalFullLayout.placements,
        functionKeys: ["MODE", "SYMBOL", "SETTINGS", "，", "SPACE", "。", "BACKSPACE", "ENTER"],
        functionWeights: ["MODE": 1.65, "SPACE": 3.8, "BACKSPACE": 1.4, "ENTER": 1.4],
        keySpacing: 3, stripSpacing: 2, compositionCellCount: 11, splitGeometry: nil,
        portraitMetrics: .portrait, compactMetrics: .compact, wideMetrics: .pad
    )

    /// Preserve the existing split choice while future visual profiles are added.
    /// This preset is usable on supported widths; width alone does not identify a Duo.
    public static let alignedSplit = KeyboardLayoutProfile(
        id: "aligned-split", displayName: "對齊分離", portrait: aligned.portrait, landscape: aligned.landscape,
        functionKeys: aligned.functionKeys, functionWeights: aligned.functionWeights,
        keySpacing: aligned.keySpacing, stripSpacing: aligned.stripSpacing,
        compositionCellCount: aligned.compositionCellCount,
        splitGeometry: SplitGeometry(minimumExpandedWidth: 600,
            punctuation: ["，", "。", "、", "？"], keySplit: 5, expandedKeySplit: 6,
            compositionSplit: 6, candidateSplit: 5, expandedCandidateSplit: 6,
            expandedFunctionWeights: ["MODE": 1.5, "SYMBOL": 1.25, "SETTINGS": 1.25,
                                      "SPACE": 2, "BACKSPACE": 2, "ENTER": 2]),
        portraitMetrics: aligned.portraitMetrics, compactMetrics: aligned.compactMetrics,
        wideMetrics: aligned.wideMetrics
    )

    public static let standard = KeyboardLayoutProfile(
        rowOffsets: [0, 1.0 / 3, 2.0 / 3, 0],
        planeGeometryOverrides: [
            .cangjie: .init(rowOffsets: [0, 1.0 / 3, 2.0 / 3, 1]),
            .simplex: .init(rowOffsets: [0, 1.0 / 3, 2.0 / 3, 1])
        ], id: "standard", displayName: "標準",
        portrait: standardPlacements(for: .portrait), landscape: standardPlacements(for: .landscape),
        functionKeys: aligned.functionKeys, functionWeights: aligned.functionWeights,
        keySpacing: aligned.keySpacing, stripSpacing: aligned.stripSpacing,
        compositionCellCount: aligned.compositionCellCount, splitGeometry: nil,
        portraitMetrics: aligned.portraitMetrics, compactMetrics: aligned.compactMetrics,
        wideMetrics: aligned.wideMetrics
    )

    private static func standardPlacements(for orientation: Orientation) -> Placements {
        let base = aligned.placements(for: orientation)
        func tablePlacement(_ placement: Placement) -> Placement {
            func withoutBottomSlash(_ rows: [[String]]) -> [[String]] {
                var result = rows
                if let last = result.indices.last { result[last].removeAll { $0 == "/" } }
                return result
            }
            return Placement(rows: withoutBottomSlash(placement.rows),
                shiftedRows: withoutBottomSlash(placement.shiftedRows))
        }
        return Placements(bopomofo: base.bopomofo, cangjie: tablePlacement(base.cangjie),
            simplex: tablePlacement(base.simplex), english: base.english, numberSymbols: base.numberSymbols)
    }

    public static let available: [KeyboardLayoutProfile] = [.standard, .aligned, .alignedSplit]

    public static func resolve(id: String?) -> KeyboardLayoutProfile {
        available.first { $0.id == id } ?? .standard
    }
}

public final class KeyboardLayoutProfileSettings {
    private let store: KeyboardPreferenceStore
    private static let layoutKey = "keyboardLayoutVariant"
    private static let spacingKey = "keyboardKeycapSpacing"
    private static let fontKey = "keyboardKeyFontLevel"
    private static let legacyFontKey = "keyboardKeyFontSize"
    private static let deleteShiftKey = "keyboardDeleteShiftPosition"
    private static let legacyProfileKeys = ["keyboardLayoutProfile", "keyboardPresentation"]
    private static let legacyAreaKey = "keyboardKeycapArea"

    public init(defaults: UserDefaults = .standard, sharedDefaults: UserDefaults? = nil,
                writesShared: Bool = false) {
        store = KeyboardPreferenceStore(defaults: defaults, sharedDefaults: sharedDefaults,
            writesShared: writesShared)
    }

    /// Old presets are read as four independent choices without rewriting them.
    /// Each new setting overrides only its corresponding legacy-derived value.
    private var legacyProfile: String? {
        let valid = ["full", "staggered", "large-full", "large-staggered", "split", "full-spaced"]
        return Self.legacyProfileKeys.compactMap { store.object(forKey: $0) as? String }
            .first { valid.contains($0) }
    }

    public var profile: KeyboardLayoutProfile {
        if let value = store.object(forKey: Self.layoutKey) as? String {
            return KeyboardLayoutProfile.resolve(id: value)
        }
        switch legacyProfile {
        case "full", "large-full", "full-spaced": return .aligned
        case "split": return .alignedSplit
        default: return .standard
        }
    }

    public func setProfile(_ profile: KeyboardLayoutProfile) {
        store.set(profile.id, forKey: Self.layoutKey)
    }

    public var keycapArea: KeyboardKeycapArea {
        if let value = store.object(forKey: Self.spacingKey) as? String {
            return KeyboardKeycapArea(rawValue: value) ?? .small
        }
        guard legacyProfile == "full-spaced" else { return .small }
        return store.object(forKey: Self.legacyAreaKey) as? String == "85" ? .large : .medium
    }

    public func setKeycapArea(_ area: KeyboardKeycapArea) {
        store.set(area.rawValue, forKey: Self.spacingKey)
    }

    public var fontSize: KeyboardKeyFontSize {
        if let value = store.object(forKey: Self.fontKey) as? String {
            return KeyboardKeyFontSize(rawValue: value) ?? .normal
        }
        if let oldValue = store.object(forKey: Self.legacyFontKey) as? String {
            return oldValue == "large" ? .extraLarge : .normal
        }
        return legacyProfile == "large-full" || legacyProfile == "large-staggered" ? .extraLarge : .normal
    }

    public func setFontSize(_ size: KeyboardKeyFontSize) {
        store.set(size.rawValue, forKey: Self.fontKey)
    }

    public var deleteShiftPosition: KeyboardDeleteShiftPosition {
        (store.object(forKey: Self.deleteShiftKey) as? String).flatMap(KeyboardDeleteShiftPosition.init(rawValue:)) ?? .aboveEnter
    }

    public func setDeleteShiftPosition(_ position: KeyboardDeleteShiftPosition) {
        store.set(position.rawValue, forKey: Self.deleteShiftKey)
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

/// A visible cap shrinks around its centre; the touch target and text do not.
public enum KeyboardKeycapArea: String, CaseIterable, Sendable {
    case small = "100", medium = "90", large = "80"
    public var displayName: String {
        switch self { case .small: "小"; case .medium: "中"; case .large: "大" }
    }
    public var areaRatio: Double {
        switch self { case .small: 1; case .medium: 0.90; case .large: 0.80 }
    }
    public var linearScale: Double { sqrt(areaRatio) }

    public func frame(in hitBounds: CGRect) -> CGRect {
        let width = hitBounds.width * linearScale
        let height = hitBounds.height * linearScale
        return CGRect(x: hitBounds.midX - width / 2, y: hitBounds.midY - height / 2,
            width: width, height: height)
    }
}

public enum KeyboardKeyFontSize: String, CaseIterable, Sendable {
    case normal, medium, large, extraLarge = "extra-large"

    public var displayName: String {
        switch self { case .normal: "標準"; case .medium: "中"; case .large: "大"; case .extraLarge: "特大" }
    }
    public var showsKeyHints: Bool { self == .normal }
    public var stripScale: Double {
        switch self { case .normal: 1; case .medium: 1.15; case .large: 1.30; case .extraLarge: 1.45 }
    }

    /// Evaluate the normal typography independently of the selected font level.
    /// Hiding its secondary hint must not turn an inline tone into a stacked one.
    public static func normalKeyPointSize(base: Double, readingScale: Double,
                                          inlineHints: Bool, temporaryEnglish: Bool,
                                          tableInput: Bool) -> Double {
        base * (inlineHints || temporaryEnglish || tableInput ? 1 : readingScale)
    }

    /// Extra large preserves the legacy large fit. Intermediate levels use a
    /// stable normal baseline, never the font fitted during an earlier layout.
    public func keyPointSize(normal: Double, largeFit: Double) -> Double {
        let start = min(normal, largeFit)
        switch self {
        case .normal: return normal
        case .medium: return start + (largeFit - start) / 3
        case .large: return start + (largeFit - start) * 2 / 3
        case .extraLarge: return largeFit
        }
    }

    public func stripPointSize(base: Double) -> Double {
        base * stripScale
    }
}

public enum KeyboardDeleteShiftPosition: String, CaseIterable, Sendable {
    case aboveEnter = "above-enter", leftOfEnter = "left-of-enter"
    public var displayName: String { self == .aboveEnter ? "右側" : "下方" }

    fileprivate func mainKey(for key: String) -> String {
        self == .aboveEnter && key == "SHIFT" ? "BACKSPACE" : key
    }

    fileprivate func functionKey(for key: String) -> String {
        self == .aboveEnter && key == "BACKSPACE" ? "SHIFT" : key
    }
}
