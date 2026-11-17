import CGuanyinma
import Foundation

/// Shared geometry for key, composition, candidate and weighted function rows.
/// Split halves have equal width; no button spans the centre gap.
public enum KeyboardRowGeometry {
    public static func frames(width: Double, height: Double, weights: [Double],
                              splitIndex: Int? = nil, spacing: Double = 3) -> [CGRect] {
        frames(width: width, height: height, weights: weights, splitIndex: splitIndex,
            spacing: spacing, leadingUnits: 0, totalUnits: 0)
    }

    static func frames(width: Double, height: Double, weights: [Double], splitIndex: Int? = nil,
                       spacing: Double, leadingUnits: Double, totalUnits: Double) -> [CGRect] {
        guard !weights.isEmpty, width > 0, height > 0 else { return [] }
        let split = splitIndex.flatMap { $0 > 0 && $0 < weights.count ? $0 : nil } ?? 0
        let gap = split == 0 ? 0 : min(80, width * 0.1)
        var slots = Array(repeating: GuanyinmaKeyboardSlot(), count: weights.count)
        let status = guanyinma_keyboard_row_layout(width, spacing, leadingUnits, totalUnits,
            split, gap, weights, weights.count, &slots)
        guard status == 0 else { return [] }
        return slots.map { CGRect(x: $0.left, y: 0, width: $0.right - $0.left, height: height) }
    }
}
