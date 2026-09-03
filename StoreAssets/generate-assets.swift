#!/usr/bin/env swift

import AppKit
import Foundation

private let purple = NSColor(calibratedRed: 0.50, green: 0.00, blue: 0.50, alpha: 1)
private let deepPurple = NSColor(calibratedRed: 0.18, green: 0.04, blue: 0.23, alpha: 1)
private let palePurple = NSColor(calibratedRed: 0.96, green: 0.92, blue: 0.98, alpha: 1)

private struct Canvas {
    let width: CGFloat
    let height: CGFloat
    let bitmap: NSBitmapImageRep

    init(width: CGFloat, height: CGFloat) {
        self.width = width
        self.height = height
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(width),
            pixelsHigh: Int(height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            fatalError("Cannot create bitmap canvas")
        }
        self.bitmap = bitmap
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSGraphicsContext.current?.imageInterpolation = .high
    }

    func rect(x: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat) -> NSRect {
        NSRect(x: x, y: self.height - top - height, width: width, height: height)
    }

    func finish(to url: URL) throws {
        NSGraphicsContext.current?.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(
            using: .png,
            properties: [.compressionFactor: 0.92]
        )
        else { throw AssetError.cannotEncode }
        try png.write(to: url)
    }
}

private enum AssetError: Error {
    case cannotLoad(String)
    case cannotEncode
}

private func fillBackground(_ canvas: Canvas) {
    let bounds = NSRect(x: 0, y: 0, width: canvas.width, height: canvas.height)
    NSGradient(starting: deepPurple, ending: purple)?.draw(in: bounds, angle: 68)

    for (x, top, diameter, alpha) in [
        (canvas.width * 0.72, -canvas.width * 0.09, canvas.width * 0.58, 0.10),
        (-canvas.width * 0.16, canvas.height * 0.50, canvas.width * 0.58, 0.07),
    ] {
        NSColor.white.withAlphaComponent(alpha).setFill()
        NSBezierPath(ovalIn: canvas.rect(x: x, top: top, width: diameter, height: diameter)).fill()
    }
}

private func drawText(
    _ text: String,
    on canvas: Canvas,
    top: CGFloat,
    height: CGFloat,
    size: CGFloat,
    weight: NSFont.Weight,
    color: NSColor = .white,
    alignment: NSTextAlignment = .center,
    horizontalPadding: CGFloat = 70
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byWordWrapping
    paragraph.lineSpacing = size * 0.12
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: paragraph,
    ]
    NSAttributedString(string: text, attributes: attributes).draw(
        in: canvas.rect(
            x: horizontalPadding,
            top: top,
            width: canvas.width - horizontalPadding * 2,
            height: height
        )
    )
}

private func drawPill(_ text: String, on canvas: Canvas, top: CGFloat, width: CGFloat) {
    let frame = canvas.rect(x: (canvas.width - width) / 2, top: top, width: width, height: 68)
    NSColor.white.withAlphaComponent(0.15).setFill()
    NSBezierPath(roundedRect: frame, xRadius: 34, yRadius: 34).fill()
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    NSAttributedString(string: text, attributes: [
        .font: NSFont.systemFont(ofSize: 29, weight: .semibold),
        .foregroundColor: NSColor.white,
        .paragraphStyle: paragraph,
    ]).draw(in: frame.insetBy(dx: 12, dy: 15))
}

private func sourceRect(image: NSImage, top: CGFloat, height: CGFloat) -> NSRect {
    NSRect(x: 0, y: image.size.height - top - height, width: image.size.width, height: height)
}

private func drawScreenshot(
    _ screenshot: NSImage,
    on canvas: Canvas,
    destination: NSRect,
    source: NSRect? = nil,
    radius: CGFloat = 42
) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.34)
    shadow.shadowBlurRadius = 32
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    NSColor.white.setFill()
    NSBezierPath(roundedRect: destination, xRadius: radius, yRadius: radius).fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: destination, xRadius: radius, yRadius: radius).addClip()
    screenshot.draw(
        in: destination,
        from: source ?? NSRect(origin: .zero, size: screenshot.size),
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: true,
        hints: [.interpolation: NSImageInterpolation.high]
    )
    NSGraphicsContext.restoreGraphicsState()
}

private func drawSwatches(on canvas: Canvas, top: CGFloat, diameter: CGFloat) {
    let colors: [(NSColor, String)] = [
        (purple, "紫"),
        (NSColor(calibratedRed: 0.23, green: 0.68, blue: 0.12, alpha: 1), "綠"),
        (NSColor(calibratedRed: 0.92, green: 0.71, blue: 0.00, alpha: 1), "黃"),
        (NSColor(calibratedRed: 0.75, green: 0.00, blue: 0.16, alpha: 1), "紅"),
    ]
    let gap: CGFloat = diameter * 0.42
    let total = diameter * 4 + gap * 3
    var x = (canvas.width - total) / 2
    for (color, label) in colors {
        let frame = canvas.rect(x: x, top: top, width: diameter, height: diameter)
        color.setFill()
        NSBezierPath(ovalIn: frame).fill()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let textColor: NSColor = label == "黃" ? .black : .white
        NSAttributedString(string: label, attributes: [
            .font: NSFont.systemFont(ofSize: diameter * 0.33, weight: .bold),
            .foregroundColor: textColor,
            .paragraphStyle: paragraph,
        ]).draw(in: frame.insetBy(dx: 0, dy: diameter * 0.29))
        x += diameter + gap
    }
}

private func makePortraitSet(
    screenshot: NSImage,
    companion: NSImage,
    size: NSSize,
    output: URL,
    platform: String,
    isAndroid: Bool
) throws {
    let pages: [(String, String)] = [
        ("ㄅ半注音的第一選擇", "琦琦注音，讓手指快樂回家"),
        (isAndroid ? "接上鍵盤，候選跟著跑" : "五排都在，熟悉手感也在",
         isAndroid ? "浮動選字窗貼著游標，1–9 一伸手就到" : "多數鍵盤只有四排，琦琦把完整注音排回來"),
        ("1–9 乖乖站好，不亂跑", "眼睛不用追、手指不用猜，選字位置一直都在"),
        ("紫綠黃紅，今天選哪一色？", "預設琦琦紫，選字底色也能有個性"),
        ("手機桌機，都用同一套手感", "在 \(platform) 使用，也可安裝 macOS 與 Windows 版"),
    ]

    for (index, copy) in pages.enumerated() {
        let canvas = Canvas(width: size.width, height: size.height)
        fillBackground(canvas)
        drawText(copy.0, on: canvas, top: 95, height: 180,
                 size: size.width * (index == 4 ? 0.057 : 0.067), weight: .bold)
        drawText(copy.1, on: canvas, top: 285, height: 130,
                 size: size.width * (index == 4 ? 0.027 : 0.032), weight: .medium,
                 color: palePurple)
        drawPill("琦琦注音", on: canvas, top: 420, width: size.width * 0.36)

        switch index {
        case 0:
            let width = size.width * (isAndroid ? 0.57 : 0.79)
            let height = width * screenshot.size.height / screenshot.size.width
            drawScreenshot(screenshot, on: canvas, destination: canvas.rect(
                x: (size.width - width) / 2, top: 535, width: width, height: height
            ))
        case 1:
            let cropTop = screenshot.size.height * (isAndroid ? 0.15 : 0.39)
            let cropHeight = screenshot.size.height - cropTop
            let source = sourceRect(image: screenshot, top: cropTop, height: cropHeight)
            let width = size.width * (isAndroid ? 0.67 : 0.91)
            let height = width * cropHeight / screenshot.size.width
            drawScreenshot(screenshot, on: canvas, destination: canvas.rect(
                x: (size.width - width) / 2, top: isAndroid ? 535 : 620,
                width: width, height: height
            ), source: source)
        case 2:
            let width = size.width * (isAndroid ? 0.57 : 0.73)
            let height = width * screenshot.size.height / screenshot.size.width
            drawScreenshot(screenshot, on: canvas, destination: canvas.rect(
                x: (size.width - width) / 2, top: 610, width: width, height: height
            ))
        case 3:
            drawSwatches(on: canvas, top: 590, diameter: size.width * 0.15)
            let width = size.width * (isAndroid ? 0.42 : 0.60)
            let height = width * screenshot.size.height / screenshot.size.width
            drawScreenshot(screenshot, on: canvas, destination: canvas.rect(
                x: (size.width - width) / 2, top: 870, width: width, height: height
            ), radius: 30)
        default:
            let firstWidth = size.width * 0.43
            let firstHeight = firstWidth * screenshot.size.height / screenshot.size.width
            let secondWidth = size.width * 0.39
            let secondHeight = secondWidth * companion.size.height / companion.size.width
            drawScreenshot(screenshot, on: canvas, destination: canvas.rect(
                x: size.width * 0.08, top: 650, width: firstWidth, height: firstHeight
            ), radius: 28)
            drawScreenshot(companion, on: canvas, destination: canvas.rect(
                x: size.width * 0.54, top: 760, width: secondWidth, height: secondHeight
            ), radius: 28)
            drawText("macOS  ·  Windows  ·  Android  ·  iOS", on: canvas,
                     top: size.height - 190, height: 80, size: size.width * 0.027,
                     weight: .semibold, color: palePurple)
        }

        try canvas.finish(to: output.appendingPathComponent(String(format: "%02d.png", index + 1)))
    }
}

private func makeFeatureGraphic(android: NSImage, output: URL) throws {
    let canvas = Canvas(width: 1024, height: 500)
    fillBackground(canvas)
    drawText("ㄅ半注音的\n第一選擇", on: canvas, top: 82, height: 190,
             size: 61, weight: .bold, alignment: .left, horizontalPadding: 72)
    drawText("琦琦注音・五排鍵盤・固定候選", on: canvas,
             top: 305, height: 90, size: 25, weight: .medium,
             color: palePurple, alignment: .left, horizontalPadding: 72)

    let cropTop = android.size.height * 0.24
    let cropHeight = android.size.height * 0.70
    drawScreenshot(android, on: canvas,
                   destination: canvas.rect(x: 665, top: 28, width: 292, height: 444),
                   source: sourceRect(image: android, top: cropTop, height: cropHeight),
                   radius: 26)
    try canvas.finish(to: output)
}

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let root = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let store = root.appendingPathComponent("StoreAssets")
let iOSURL = store.appendingPathComponent("Sources/ios-notes-qi.png")
let androidURL = store.appendingPathComponent("Sources/android-notes-floating-qi.png")

guard let iOS = NSImage(contentsOf: iOSURL) else { throw AssetError.cannotLoad(iOSURL.path) }
guard let android = NSImage(contentsOf: androidURL) else { throw AssetError.cannotLoad(androidURL.path) }

try FileManager.default.createDirectory(
    at: store.appendingPathComponent("AppStore/iPhone-1206x2622"),
    withIntermediateDirectories: true
)
try FileManager.default.createDirectory(
    at: store.appendingPathComponent("GooglePlay/Phone"),
    withIntermediateDirectories: true
)

try makePortraitSet(
    screenshot: iOS,
    companion: android,
    size: NSSize(width: 1206, height: 2622),
    output: store.appendingPathComponent("AppStore/iPhone-1206x2622"),
    platform: "iPhone／iPad",
    isAndroid: false
)
try makePortraitSet(
    screenshot: android,
    companion: iOS,
    size: NSSize(width: 1080, height: 1920),
    output: store.appendingPathComponent("GooglePlay/Phone"),
    platform: "Android",
    isAndroid: true
)
try makeFeatureGraphic(
    android: android,
    output: store.appendingPathComponent("GooglePlay/feature-graphic-1024x500.png")
)

print("Generated App Store and Google Play assets in \(store.path)")
