import CoreGraphics
import Foundation
import ImageIO

// Run from the repository root. The existing iOS AppIcon is the shared artwork.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourceURL = root.appendingPathComponent(
    "Source/Loaders/iOS-Keyboard/ContainerApp/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
let res = root.appendingPathComponent("Source/Loaders/Android-IME/app/src/main/res")
guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      image.width == 1024, image.height == 1024 else {
    fatalError("Expected the existing 1024 x 1024 iOS AppIcon.png")
}
let colorSpace = CGColorSpaceCreateDeviceRGB()
let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue

func canvas(_ size: Int) -> CGContext {
    guard let context = CGContext(data: nil, width: size, height: size,
                                  bitsPerComponent: 8, bytesPerRow: size * 4,
                                  space: colorSpace, bitmapInfo: bitmapInfo) else {
        fatalError("Could not create icon canvas")
    }
    context.interpolationQuality = .high
    return context
}

func save(_ context: CGContext, _ path: String) throws {
    guard let image = context.makeImage() else { fatalError("Could not render icon") }
    let url = res.appendingPathComponent(path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                           withIntermediateDirectories: true)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Could not save icon") }
    print(path)
}

// The app requires Android 8 (API 26), so all supported versions use adaptive icons.
// Extract the black 琦 from its near-white background. Keeping the glyph in alpha
// also lets Android 13+ tint the monochrome layer without showing a solid square.
let glyph = canvas(image.width)
glyph.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
let pixels = glyph.data!.assumingMemoryBound(to: UInt8.self)
let center = Double(image.width) / 2
var radius = 0.0
for y in 0..<image.height {
    for x in 0..<image.width {
        let index = (y * image.width + x) * 4
        let lightness = max(pixels[index], max(pixels[index + 1], pixels[index + 2]))
        let alpha: UInt8 = lightness >= 240 ? 0 : 255 - lightness
        pixels[index] = 0
        pixels[index + 1] = 0
        pixels[index + 2] = 0
        pixels[index + 3] = alpha
        if alpha > 0 {
            radius = max(radius, hypot(Double(x) + 0.5 - center, Double(y) + 0.5 - center))
        }
    }
}
guard radius > 0 else { fatalError("No glyph found in source icon") }
// 108 dp at xxxhdpi, with the entire glyph inside a 64 dp circle. Android's
// guaranteed safe circle is 66 dp; the extra margin accommodates resampling.
let foreground = canvas(432)
let artworkSize = Double(image.width) * (32 * 4 / radius)
let offset = (432 - artworkSize) / 2
foreground.draw(glyph.makeImage()!, in: CGRect(x: offset, y: offset,
                                              width: artworkSize, height: artworkSize))
try save(foreground, "drawable-nodpi/ic_launcher_foreground.png")
