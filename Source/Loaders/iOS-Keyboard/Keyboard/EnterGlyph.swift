import UIKit

/// The Enter key's arrow, stroked rather than typeset. `↵` draws thin and
/// differs between the Android and iOS system faces, so both touch keyboards
/// draw this shape instead.
///
/// The geometry is `Source/Branding/enter.svg`; the Android keyboard strokes
/// the same coordinates in `BopomofoKeyboardView.drawEnterKey`. Keep the three
/// in step.
enum EnterGlyph {
    /// A template image `side` points square, so the caller's tint colour
    /// decides the colour and dark mode comes for free.
    static func image(side: Double) -> UIImage {
        let unit = side / 24
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 18 * unit, y: 6 * unit))
        path.addLine(to: CGPoint(x: 18 * unit, y: 13 * unit))
        path.addLine(to: CGPoint(x: 6 * unit, y: 13 * unit))
        path.move(to: CGPoint(x: 11 * unit, y: 9 * unit))
        path.addLine(to: CGPoint(x: 6 * unit, y: 13 * unit))
        path.addLine(to: CGPoint(x: 11 * unit, y: 17 * unit))
        path.lineWidth = 2 * unit
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        let size = CGSize(width: side, height: side)
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            UIColor.black.setStroke()
            path.stroke()
        }
        return image.withRenderingMode(.alwaysTemplate)
    }
}
