import AppKit
import Foundation
import ImageIO

let root = FileManager.default.currentDirectoryPath
let output = root + "/StoreAssets"
let fm = FileManager.default
try fm.createDirectory(atPath: output, withIntermediateDirectories: true)

func col(_ hex: UInt32) -> NSColor {
    NSColor(calibratedRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
}
let plum = col(0x341A4A), purple = col(0x8A1997), lavender = col(0xEEE2F5)
let white = NSColor.white, gold = col(0xFFD46D)

final class Canvas {
    let width: CGFloat, height: CGFloat, rep: NSBitmapImageRep
    init(_ width: Int, _ height: Int) {
        self.width = CGFloat(width); self.height = CGFloat(height)
        rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bitmapFormat: [], bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    }
    func rect(_ x: CGFloat, _ top: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
        NSRect(x: x, y: height - top - h, width: w, height: h)
    }
    func fill(_ color: NSColor) {
        color.setFill(); NSBezierPath(rect: rect(0, 0, width, height)).fill()
    }
    func rounded(_ x: CGFloat, _ top: CGFloat, _ w: CGFloat, _ h: CGFloat,
                 _ radius: CGFloat, _ color: NSColor) {
        color.setFill(); NSBezierPath(roundedRect: rect(x, top, w, h),
                                       xRadius: radius, yRadius: radius).fill()
    }
    func text(_ value: String, x: CGFloat, top: CGFloat, width: CGFloat,
              height: CGFloat, size: CGFloat, weight: NSFont.Weight = .regular,
              color: NSColor, align: NSTextAlignment = .left) {
        let style = NSMutableParagraphStyle()
        style.alignment = align
        style.lineBreakMode = .byWordWrapping
        style.lineSpacing = size * 0.07
        NSAttributedString(string: value, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color, .paragraphStyle: style
        ]).draw(in: rect(x, top, width, height))
    }
    func screenshot(_ path: String, x: CGFloat, top: CGFloat,
                    maxWidth: CGFloat, maxHeight: CGFloat, radius: CGFloat = 30) {
        guard let source = NSImage(contentsOfFile: path) else { fatalError("Missing screenshot: \(path)") }
        let scale = min(maxWidth / source.size.width, maxHeight / source.size.height)
        let w = source.size.width * scale, h = source.size.height * scale
        let px = x + (maxWidth - w) / 2, py = top + (maxHeight - h) / 2
        let frame = rect(px, py, w, h)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = col(0x160B22).withAlphaComponent(0.32)
        shadow.shadowBlurRadius = 28; shadow.shadowOffset = NSSize(width: 0, height: -10)
        shadow.set(); white.setFill()
        NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius).fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius).addClip()
        source.draw(in: frame, from: NSRect(origin: .zero, size: source.size),
                    operation: .sourceOver, fraction: 1, respectFlipped: true,
                    hints: [.interpolation: NSImageInterpolation.high])
        NSGraphicsContext.restoreGraphicsState()
    }
    func save(_ path: String) {
        NSGraphicsContext.current?.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        try! fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                withIntermediateDirectories: true)
        // App Store screenshots must not carry an alpha channel.
        guard let source = rep.cgImage,
              let context = CGContext(data: nil, width: Int(width), height: Int(height),
                                      bitsPerComponent: 8, bytesPerRow: Int(width) * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            fatalError("Could not create RGB canvas")
        }
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL,
                                                                 "public.png" as CFString, 1, nil) else {
            fatalError("Could not save PNG: \(path)")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { fatalError("Could not finalize PNG: \(path)") }
    }
}

struct Page {
    let title: String
    let subtitle: String
    let tag: String
    let image: String
}
let ios = root + "/docs/images/"
let iphone: [Page] = [
    .init(title: "好打注音，整句順著打", subtitle: "請假要去哪裡玩呢去海邊", tag: "連續組句", image: ios + "keykey-ios-v130-smart-typing.png"),
    .init(title: "傳統注音，逐字精準選", subtitle: "熟悉的 1–9 候選與標準鍵位", tag: "傳統注音", image: root + "/StoreAssets/Sources/ios-notes-qi.png"),
    .init(title: "接上鍵盤，選字也順手", subtitle: "在琦琦 App 內輸入，再複製或分享", tag: "實體鍵盤", image: ios + "keykey-ios-v130-hardware-editor-boundary.png"),
    .init(title: "好打或傳統，隨時切換", subtitle: "兩種注音節奏，依你的習慣選", tag: "自由切換", image: ios + "keykey-ios-v130-keyboard-settings.png")
]
let ipad: [Page] = [
    .init(title: "好打注音，整句順著打", subtitle: "請假要去哪裡玩呢去海邊", tag: "iPad 原生畫面", image: output + "/Sources/ios-ipad-v130-smart-full.png"),
    .init(title: "傳統注音，逐字精準選", subtitle: "熟悉的 1–9 候選與標準鍵位", tag: "傳統注音", image: root + "/StoreAssets/Sources/ios-ipad-notes-qi.png"),
    .init(title: "接上鍵盤，選字也順手", subtitle: "在琦琦 App 內輸入，再複製或分享", tag: "實體鍵盤", image: output + "/Sources/ios-ipad-v130-hardware-editor.png"),
    .init(title: "好打或傳統，隨時切換", subtitle: "兩種注音節奏，依你的習慣選", tag: "自由切換", image: output + "/Sources/ios-ipad-v130-settings.png")
]
let android: [Page] = [
    .init(title: "好打注音，整句順著打", subtitle: "請假要去哪裡玩呢去海邊", tag: "連續組句", image: output + "/Sources/android-v130-smart-full.png"),
    .init(title: "想改中間的字，直接點", subtitle: "回頭選字，整句不用重打", tag: "句中選字", image: output + "/Sources/android-v130-smart-middle-candidate.png"),
    .init(title: "傳統注音，照熟悉的方式選", subtitle: "固定 1–9 候選，標準注音鍵位", tag: "傳統注音", image: root + "/StoreAssets/Sources/android-phone-touch-portrait.png"),
    .init(title: "接上鍵盤，候選跟著游標", subtitle: "浮動候選與數字選字都保留", tag: "實體鍵盤", image: root + "/StoreAssets/Sources/android-notes-floating-qi.png"),
    .init(title: "五個平台，同一套注音習慣", subtitle: "Android・iOS・macOS・Windows・Linux", tag: "跨平台", image: "")
]

func render(_ page: Page, index: Int, count: Int, variant: String,
            width: Int, height: Int, kind: String, path: String) {
    let c = Canvas(width, height)
    let w = c.width, h = c.height, k = w / 1242
    let darkTheme = variant == "A"
    if darkTheme {
        NSGradient(starting: col(0x271037), ending: col(0x882598))!
            .draw(in: c.rect(0, 0, w, h), angle: 67)
        c.rounded(w * 0.68, -w * 0.07, w * 0.5, w * 0.5, w * 0.25,
                  white.withAlphaComponent(0.08))
        c.rounded(-w * 0.30, h * 0.64, w * 0.7, w * 0.7, w * 0.35,
                  white.withAlphaComponent(0.07))
        c.rounded(82*k, 95*k, 255*k, 72*k, 36*k, white.withAlphaComponent(0.17))
        c.text(page.tag, x: 95*k, top: 112*k, width: 230*k, height: 50*k,
               size: 37*k, weight: .semibold, color: white, align: .center)
        c.text(page.title, x: 80*k, top: 210*k, width: w-160*k,
               height: 145*k, size: 76*k, weight: .bold, color: white)
        c.text(page.subtitle, x: 85*k, top: 365*k, width: w-170*k,
               height: 105*k, size: 45*k, weight: .medium, color: lavender)
        c.rounded(80*k, 505*k, w-160*k, 5*k, 2*k, gold)
    } else {
        c.fill(col(0xFAF7FD))
        c.rounded(0, 0, w, 104*k, 0, plum)
        c.text("琦琦注音  /  \(kind)", x: 68*k, top: 30*k,
               width: w-136*k, height: 54*k, size: 38*k,
               weight: .semibold, color: white)
        c.rounded(80*k, 155*k, 16*k, 216*k, 8*k, purple)
        c.text(page.tag, x: 125*k, top: 155*k, width: w-205*k,
               height: 62*k, size: 39*k, weight: .bold, color: purple)
        c.text(page.title, x: 125*k, top: 235*k, width: w-205*k,
               height: 165*k, size: 74*k, weight: .bold, color: plum)
        c.text(page.subtitle, x: 83*k, top: 415*k, width: w-166*k,
               height: 94*k, size: 43*k, weight: .medium, color: col(0x604B6B))
    }
    let photoTop: CGFloat = kind == "Google Play" ? 540*k : 535*k
    let photoBottom: CGFloat = kind == "Google Play" ? 130*k : 112*k
    let photoWidth: CGFloat = kind == "iPad" ? w*0.78 : (kind == "Google Play" ? w*0.73 : w*0.79)
    let frameX = (w-photoWidth)/2
    if darkTheme {
        c.rounded(frameX-29*k, photoTop-29*k, photoWidth+58*k,
                  h-photoTop-photoBottom+58*k, 54*k, white.withAlphaComponent(0.18))
    } else {
        c.rounded(frameX-29*k, photoTop-29*k, photoWidth+58*k,
                  h-photoTop-photoBottom+58*k, 54*k, lavender)
    }
    c.screenshot(page.image, x: frameX, top: photoTop,
                 maxWidth: photoWidth, maxHeight: h-photoTop-photoBottom,
                 radius: 28*k)
    c.text(String(format: "%02d / %02d", index, count), x: w-215*k,
           top: h-80*k, width: 160*k, height: 50*k, size: 32*k,
           weight: .semibold, color: darkTheme ? white : purple, align: .right)
    c.save(path)
}

func feature(_ variant: String, path: String) {
    let c = Canvas(1024,500)
    if variant == "A" {
        NSGradient(starting: plum, ending: purple)!.draw(in: c.rect(0,0,1024,500), angle: 45)
        c.text("注音照你的習慣",x:55,top:75,width:520,height:100,size:65,weight:.bold,color:white)
        c.text("好打注音・傳統注音・實體鍵盤",x:58,top:190,width:500,height:95,size:31,weight:.medium,color:lavender)
        c.rounded(55,332,500,68,34,gold)
        c.text("琦琦注音輸入法",x:75,top:343,width:460,height:53,size:34,weight:.bold,color:plum)
    } else {
        c.fill(col(0xFAF7FD))
        c.rounded(0,0,22,500,0,purple)
        c.text("注音照你的習慣",x:65,top:68,width:510,height:112,size:65,weight:.bold,color:plum)
        c.text("好打・傳統・接上鍵盤",x:68,top:193,width:485,height:105,size:38,weight:.medium,color:purple)
        c.rounded(65,352,458,76,38,plum)
        c.text("琦琦注音 1.3.0",x:85,top:362,width:420,height:55,size:37,weight:.bold,color:white)
    }
    let phone = NSImage(contentsOfFile: output + "/Sources/android-v130-smart-full.png")!
    let panel = c.rect(630,25,350,450)
    c.rounded(622,17,366,466,23,white)
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: panel, xRadius: 16, yRadius: 16).addClip()
    phone.draw(in: panel,
               from: NSRect(x:0,y:0,width:phone.size.width,height:phone.size.height*0.52),
               operation:.sourceOver,fraction:1,respectFlipped:true,
               hints:[.interpolation:NSImageInterpolation.high])
    NSGraphicsContext.restoreGraphicsState()
    c.save(path)
}

func renderFivePlatforms(_ variant: String, path: String) {
    let c = Canvas(1080,1920)
    let darkTheme = variant == "A"
    if darkTheme {
        NSGradient(starting: col(0x271037), ending: col(0x882598))!
            .draw(in:c.rect(0,0,1080,1920),angle:67)
    } else {
        c.fill(col(0xFAF7FD))
        c.rounded(0,0,1080,92,0,plum)
        c.text("琦琦注音  /  Google Play",x:58,top:25,width:950,height:55,
               size:34,weight:.semibold,color:white)
    }
    let head = darkTheme ? white : plum
    let sub = darkTheme ? lavender : purple
    c.text("五個平台，同一套注音習慣",x:55,top:darkTheme ? 84 : 145,
           width:970,height:165,size:68,weight:.bold,color:head)
    c.text("Android・iOS・macOS・Windows・Linux",x:58,top:darkTheme ? 255 : 315,
           width:970,height:75,size:34,weight:.medium,color:sub)
    let devices: [(String,String,CGFloat,CGFloat,CGFloat,CGFloat)] = [
        ("Android",output + "/Sources/android-v130-smart-full.png",55,430,465,660),
        ("iOS",ios+"keykey-ios-v130-smart-typing.png",560,430,465,660),
        ("macOS",ios+"keykey-macos-v130-candidates.png",45,1130,315,490),
        ("Windows",root+"/StoreAssets/Sources/chichi-windows.png",383,1130,315,490),
        ("Linux",ios+"keykey-linux-v130-smart-candidates.png",721,1130,315,490)
    ]
    for (name,source,x,y,w,h) in devices {
        c.rounded(x,y,w,h,30,white)
        c.text(name,x:x+14,top:y+20,width:w-28,height:55,size:37,
               weight:.bold,color:purple,align:.center)
        c.screenshot(source,x:x+20,top:y+90,maxWidth:w-40,
                     maxHeight:h-125,radius:10)
    }
    c.text("手機、桌機，都有熟悉的注音鍵位",x:70,top:1710,
           width:940,height:85,size:45,weight:.semibold,color:head,align:.center)
    c.text("05 / 05",x:810,top:1840,width:210,height:48,
           size:32,weight:.semibold,color:sub,align:.right)
    c.save(path)
}

// The selected 1.3.0 store artwork is variant A. Run this script from the
// repository root so source paths and output paths remain portable.
for (name, pages, width, height, destination) in [
    ("iPhone", iphone, 1206, 2622, "AppStore/iPhone-1206x2622"),
    ("iPhone", iphone, 1242, 2688, "AppStore/iPhone-1242x2688"),
    ("iPad", ipad, 2048, 2732, "AppStore/iPad-2048x2732"),
    ("GooglePlay", android, 1080, 1920, "GooglePlay/Phone")
] {
    for (i, page) in pages.enumerated() {
        let dest = "\(output)/\(destination)/" + String(format: "%02d.png", i + 1)
        if name == "GooglePlay" && i == 4 {
            renderFivePlatforms("A", path: dest)
        } else {
            render(page, index: i + 1, count: pages.count, variant: "A",
                   width: width, height: height,
                   kind: name == "GooglePlay" ? "Google Play" : name, path: dest)
        }
        print(dest)
    }
}
feature("A", path: "\(output)/GooglePlay/feature-graphic-1024x500.png")
let fivePlatforms = output + "/FivePlatforms/five-platforms.png"
if fm.fileExists(atPath: fivePlatforms) { try fm.removeItem(atPath: fivePlatforms) }
try fm.copyItem(atPath: output + "/GooglePlay/Phone/05.png", toPath: fivePlatforms)
