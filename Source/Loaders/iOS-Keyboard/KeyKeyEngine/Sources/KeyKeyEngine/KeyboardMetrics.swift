/// Portrait and landscape differ only in height and type scale -- same eleven
/// columns, same rows, same function row. The numbers come from
/// `Source/Loaders/Android-IME/.../BopomofoKeyboardView.java` so the two touch
/// keyboards look like one product.
///
/// Deliberately free of UIKit so it stays testable; the view maps the trait
/// collection onto `compactHeight`.
public struct KeyboardMetrics: Equatable, Sendable {
    /// True for the landscape scale, where there is no vertical room to spare.
    public var isCompactHeight: Bool
    public var contentHeight: Double
    public var candidateStripHeight: Double
    public var candidateFont: Double
    public var candidateIndexFont: Double
    public var keyGlyphFont: Double
    public var keyHintFont: Double
    /// Portrait stacks the Bopomofo glyph over the key position; landscape has
    /// no vertical room and collapses them into one line.
    public var stacksKeyLabels: Bool
    public var functionFont: Double
    public var functionFontSmall: Double
    public var pageFont: Double
    public var statusFont: Double

    public static let portrait = KeyboardMetrics(
        isCompactHeight: false,
        contentHeight: 330,
        candidateStripHeight: 49.5,
        candidateFont: 18,
        candidateIndexFont: 10,
        keyGlyphFont: 18,
        keyHintFont: 10,
        stacksKeyLabels: true,
        functionFont: 18,
        functionFontSmall: 12,
        pageFont: 16,
        statusFont: 14
    )

    /// iPhone landscape, where the vertical size class is compact.
    public static let compact = KeyboardMetrics(
        isCompactHeight: true,
        contentHeight: 155,
        candidateStripHeight: 155 / 6,
        candidateFont: 12,
        candidateIndexFont: 7,
        keyGlyphFont: 11,
        keyHintFont: 8,
        stacksKeyLabels: false,
        functionFont: 12,
        functionFontSmall: 9,
        pageFont: 14,
        statusFont: 11
    )

    public static func forCompactHeight(_ compact: Bool) -> KeyboardMetrics {
        compact ? .compact : .portrait
    }

    /// The five bands below the strip -- four key rows and the function row --
    /// share the remaining height evenly, as they do on Android.
    public var bandHeight: Double {
        (contentHeight - candidateStripHeight) / 5
    }
}
