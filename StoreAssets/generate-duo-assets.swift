import AppKit
import Foundation
import ImageIO

// Run from the repository root. This standalone entry point only writes the
// iPhone Duo set; the existing iPhone, iPad and Google Play artwork is untouched.
let fileManager = FileManager.default
let root = URL(fileURLWithPath: fileManager.currentDirectoryPath)
var sourceDirectory = root.appendingPathComponent("StoreAssets/Sources")
var outputDirectory = root.appendingPathComponent("StoreAssets/AppStore/iPhone-Duo-2007x2853")

enum ArtworkError: Error, CustomStringConvertible {
    case invalidArguments
    case invalidSource(String)
    case output(String)

    var description: String {
        switch self {
        case .invalidArguments:
            return "Usage: swift StoreAssets/generate-duo-assets.swift [--sources DIRECTORY] [--output DIRECTORY]"
        case .invalidSource(let message), .output(let message):
            return message
        }
    }
}

func color(_ hex: UInt32) -> NSColor {
    NSColor(calibratedRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
}

let white = NSColor.white
let lavender = color(0xEEE2F5)
let gold = color(0xFFD46D)

struct Page {
    let title: String
    let subtitle: String
    let tag: String
    let filename: String
    let splitHero: Bool
}

let pages = [
    Page(title: "分離鍵盤，雙手自在打", subtitle: "展開內螢幕，左右分區更順手",
         tag: "iPhone Duo", filename: "ios-duo-v150-split.png", splitHero: true),
    Page(title: "好打注音，整句順著打", subtitle: "連續組句，回頭選字也方便",
         tag: "連續組句", filename: "ios-duo-v150-smart.png", splitHero: false),
    Page(title: "傳統注音，逐字精準選", subtitle: "熟悉的候選選字與標準注音鍵位",
         tag: "傳統注音", filename: "ios-duo-v150-traditional.png", splitHero: false),
    Page(title: "接上鍵盤，選字也順手", subtitle: "在琦琦 App 內輸入，再複製或分享",
         tag: "實體鍵盤", filename: "ios-duo-v150-hardware-editor.png", splitHero: false),
    Page(title: "好打注音・傳統注音\n倉頡・簡易，隨你切換",
         subtitle: "四種輸入方式，依你的習慣選",
         tag: "自由切換", filename: "ios-duo-v150-settings.png", splitHero: false)
]

struct Screenshot {
    let image: NSImage
    let pixels: CGSize

    init(url: URL, allowLandscape: Bool) throws {
        guard let data = try? Data(contentsOf: url),
              let bitmap = NSBitmapImageRep(data: data),
              let image = NSImage(data: data) else {
            throw ArtworkError.invalidSource("Missing or unreadable Duo screenshot: \(url.path)")
        }
        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        guard (width == 2007 && height == 2853) ||
                (allowLandscape && width == 2853 && height == 2007) else {
            throw ArtworkError.invalidSource(
                "Expected a native Duo inner-display screenshot, got \(width) × \(height): \(url.path)")
        }
        self.image = image
        pixels = CGSize(width: width, height: height)
    }
}

final class Canvas {
    let width: CGFloat
    let height: CGFloat
    let bitmap: NSBitmapImageRep
    let scale: CGFloat

    init(width: Int = 2007, height: Int = 2853) {
        self.width = CGFloat(width)
        self.height = CGFloat(height)
        scale = min(self.width / 1242, self.height / 2688)
        bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width,
                                  pixelsHigh: height, bitsPerSample: 8,
                                  samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                  colorSpaceName: .deviceRGB, bitmapFormat: [],
                                  bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high
    }

    func rect(x: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat) -> NSRect {
        NSRect(x: x, y: self.height - top - height, width: width, height: height)
    }

    func rounded(x: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat,
                 radius: CGFloat, fill: NSColor) {
        fill.setFill()
        NSBezierPath(roundedRect: rect(x: x, top: top, width: width, height: height),
                     xRadius: radius, yRadius: radius).fill()
    }

    func text(_ value: String, x: CGFloat, top: CGFloat, width: CGFloat,
              height: CGFloat, size: CGFloat, weight: NSFont.Weight,
              fill: NSColor, alignment: NSTextAlignment = .left) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = size * 0.07
        NSAttributedString(string: value, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: fill, .paragraphStyle: paragraph
        ]).draw(in: rect(x: x, top: top, width: width, height: height))
    }

    func background() {
        NSGradient(starting: color(0x271037), ending: color(0x882598))!
            .draw(in: rect(x: 0, top: 0, width: width, height: height), angle: 67)
        rounded(x: width * 0.68, top: -width * 0.07, width: width * 0.5,
                height: width * 0.5, radius: width * 0.25,
                fill: white.withAlphaComponent(0.08))
        rounded(x: -width * 0.30, top: height * 0.64, width: width * 0.7,
                height: width * 0.7, radius: width * 0.35,
                fill: white.withAlphaComponent(0.07))
    }

    // Draw the complete original screenshot once, keeping its aspect ratio.
    // The frame follows the fitted image rather than a taller phone template.
    @discardableResult
    func screenshot(_ source: Screenshot, top: CGFloat,
                    maxWidth: CGFloat, maxHeight: CGFloat) -> CGFloat {
        let ratio = min(maxWidth / source.pixels.width, maxHeight / source.pixels.height)
        let imageWidth = source.pixels.width * ratio
        let imageHeight = source.pixels.height * ratio
        let x = (width - imageWidth) / 2
        let frame = rect(x: x, top: top, width: imageWidth, height: imageHeight)
        let mat: CGFloat = 25 * scale
        rounded(x: x - mat, top: top - mat, width: imageWidth + mat * 2,
                height: imageHeight + mat * 2, radius: 52 * scale,
                fill: white.withAlphaComponent(0.18))
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = color(0x160B22).withAlphaComponent(0.32)
        shadow.shadowBlurRadius = 28 * scale
        shadow.shadowOffset = NSSize(width: 0, height: -10 * scale)
        shadow.set()
        white.setFill()
        NSBezierPath(roundedRect: frame, xRadius: 28 * scale, yRadius: 28 * scale).fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: frame, xRadius: 28 * scale, yRadius: 28 * scale).addClip()
        source.image.draw(in: frame, from: NSRect(origin: .zero, size: source.image.size),
                          operation: .sourceOver, fraction: 1, respectFlipped: true,
                          hints: [.interpolation: NSImageInterpolation.high])
        NSGraphicsContext.restoreGraphicsState()
        return top + imageHeight
    }

    func save(to url: URL, format: CFString = "public.png" as CFString,
              properties: CFDictionary? = nil) throws {
        NSGraphicsContext.current?.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        guard let source = bitmap.cgImage,
              let context = CGContext(data: nil, width: Int(width), height: Int(height),
                                      bitsPerComponent: 8, bytesPerRow: Int(width) * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw ArtworkError.output("Could not create the RGB output canvas.")
        }
        context.setFillColor(white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let flattened = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL, format, 1, nil) else {
            throw ArtworkError.output("Could not save image: \(url.path)")
        }
        CGImageDestinationAddImage(destination, flattened, properties)
        guard CGImageDestinationFinalize(destination) else {
            throw ArtworkError.output("Could not finalize image: \(url.path)")
        }
    }
}

func render(_ page: Page, screenshot: Screenshot, index: Int, destination: URL) throws {
    let canvas = Canvas()
    let k = canvas.scale
    let w = canvas.width
    let h = canvas.height
    let multiline = page.title.contains("\n")
    let landscapeHero = page.splitHero && screenshot.pixels.width > screenshot.pixels.height
    canvas.background()
    canvas.rounded(x: 82 * k, top: 95 * k, width: 300 * k, height: 72 * k,
                   radius: 36 * k, fill: white.withAlphaComponent(0.17))
    canvas.text(page.tag, x: 96 * k, top: 111 * k, width: 272 * k,
                height: 52 * k, size: 39 * k, weight: .semibold,
                fill: white, alignment: .center)
    canvas.text(page.title, x: 80 * k, top: (multiline ? 195 : 210) * k,
                width: w - 160 * k, height: (multiline ? 212 : 145) * k,
                size: (multiline ? 83 : 94) * k, weight: .bold, fill: white)
    canvas.text(page.subtitle, x: 85 * k, top: (multiline ? 428 : 365) * k,
                width: w - 170 * k, height: 105 * k, size: 45 * k,
                weight: .medium, fill: lavender)
    let dividerTop: CGFloat = (multiline ? 565 : 505) * k
    canvas.rounded(x: 80 * k, top: dividerTop, width: w - 160 * k,
                   height: 5 * k, radius: 2 * k, fill: gold)

    if landscapeHero {
        let bottom = canvas.screenshot(screenshot, top: 740 * k,
                                       maxWidth: w - 220 * k, maxHeight: 1500 * k)
        canvas.text("左右分區・兩側空白鍵", x: 95 * k, top: bottom + 145 * k,
                    width: w - 190 * k, height: 100 * k, size: 61 * k,
                    weight: .semibold, fill: white, alignment: .center)
        canvas.text("好打注音、傳統注音、倉頡與簡易", x: 95 * k,
                    top: bottom + 267 * k, width: w - 190 * k, height: 95 * k,
                    size: 43 * k, weight: .medium, fill: lavender, alignment: .center)
    } else {
        let photoTop: CGFloat = (multiline ? 620 : 565) * k
        canvas.screenshot(screenshot, top: photoTop, maxWidth: w - 220 * k,
                          maxHeight: h - photoTop - 135 * k)
    }
    canvas.text("琦琦輸入法", x: 95 * k, top: h - 80 * k,
                width: 500 * k, height: 50 * k, size: 32 * k,
                weight: .semibold, fill: white)
    canvas.text(String(format: "%02d / %02d", index, pages.count), x: w - 255 * k,
                top: h - 80 * k, width: 160 * k, height: 50 * k, size: 32 * k,
                weight: .semibold, fill: white, alignment: .right)
    try canvas.save(to: destination)
}

func renderPreview(artwork: [URL], destination: URL) throws {
    let canvas = Canvas(width: 2000, height: 760)
    canvas.background()
    canvas.text("iPhone Duo｜琦琦輸入法", x: 30, top: 24, width: 1940,
                height: 72, size: 45, weight: .bold, fill: white)
    canvas.text("分離鍵盤・好打注音・傳統注音・實體鍵盤・自由切換",
                x: 32, top: 92, width: 1936, height: 45, size: 26,
                weight: .medium, fill: lavender)
    let gap: CGFloat = 30
    let tileWidth = (canvas.width - gap * CGFloat(artwork.count + 1)) / CGFloat(artwork.count)
    let tileHeight = tileWidth * 2853 / 2007
    for (index, url) in artwork.enumerated() {
        guard let image = NSImage(contentsOf: url) else {
            throw ArtworkError.invalidSource("Could not load artwork for preview: \(url.path)")
        }
        let frame = canvas.rect(x: gap + CGFloat(index) * (tileWidth + gap), top: 145,
                                width: tileWidth, height: tileHeight)
        image.draw(in: frame, from: NSRect(origin: .zero, size: image.size),
                   operation: .sourceOver, fraction: 1, respectFlipped: true,
                   hints: [.interpolation: NSImageInterpolation.high])
    }
    canvas.text("2007 × 2853 · 5 張獨立商店圖", x: 32, top: 700,
                width: 1936, height: 42, size: 26,
                weight: .medium, fill: lavender)
    try canvas.save(to: destination, format: "public.jpeg" as CFString,
                    properties: [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
}

do {
    var arguments = Array(CommandLine.arguments.dropFirst())
    while !arguments.isEmpty {
        let option = arguments.removeFirst()
        guard !arguments.isEmpty, option == "--sources" || option == "--output" else {
            throw ArtworkError.invalidArguments
        }
        let directory = URL(fileURLWithPath: arguments.removeFirst(), relativeTo: root).standardizedFileURL
        if option == "--sources" { sourceDirectory = directory } else { outputDirectory = directory }
    }
    // Validate every source before writing any artwork.
    let screenshots = try pages.map {
        try Screenshot(url: sourceDirectory.appendingPathComponent($0.filename),
                       allowLandscape: $0.splitHero)
    }
    try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    var artwork: [URL] = []
    for (offset, page) in pages.enumerated() {
        let destination = outputDirectory.appendingPathComponent(String(format: "%02d.png", offset + 1))
        try render(page, screenshot: screenshots[offset], index: offset + 1, destination: destination)
        artwork.append(destination)
        print(destination.path)
    }
    let preview = outputDirectory.deletingLastPathComponent().appendingPathComponent("iPhone-Duo-preview.jpg")
    try renderPreview(artwork: artwork, destination: preview)
    print(preview.path)
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(EXIT_FAILURE)
}
