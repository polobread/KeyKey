#!/usr/bin/env swift
import AppKit
import Foundation
import ImageIO

let purple = NSColor(calibratedRed: 0.50, green: 0, blue: 0.50, alpha: 1)
let dark = NSColor(calibratedRed: 0.12, green: 0.03, blue: 0.20, alpha: 1)
let pale = NSColor(calibratedRed: 0.96, green: 0.92, blue: 0.98, alpha: 1)
let ink = NSColor(calibratedWhite: 0.12, alpha: 1)
let paper = NSColor(calibratedWhite: 0.97, alpha: 1)

enum Err: Error { case image(String); case png }
struct C {
    let w: CGFloat; let h: CGFloat; let bitmap: NSBitmapImageRep
    init(_ w: CGFloat, _ h: CGFloat) {
        self.w = w; self.h = h
        guard let b = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w), pixelsHigh: Int(h), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bitmapFormat: [], bytesPerRow: 0, bitsPerPixel: 0), let ctx = NSGraphicsContext(bitmapImageRep: b) else { fatalError() }
        bitmap = b; NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ctx
    }
    func r(_ x: CGFloat, _ top: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSRect { NSRect(x: x, y: h - top - height, width: width, height: height) }
    func save(_ url: URL) throws {
        NSGraphicsContext.current?.flushGraphics(); NSGraphicsContext.restoreGraphicsState()
        guard let source = bitmap.cgImage,
              let context = CGContext(data: nil, width: Int(w), height: Int(h), bitsPerComponent: 8, bytesPerRow: Int(w) * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let destinationImage = { () -> CGImage? in
                  context.setFillColor(NSColor.white.cgColor)
                  context.fill(CGRect(x: 0, y: 0, width: w, height: h))
                  context.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))
                  return context.makeImage()
              }() else { throw Err.png }
        let rgb = URL(fileURLWithPath: "/private/tmp/keykey-\(UUID().uuidString)-rgb.png")
        defer { try? FileManager.default.removeItem(at: rgb) }
        guard let destination = CGImageDestinationCreateWithURL(rgb as CFURL, "public.png" as CFString, 1, nil) else { throw Err.png }
        CGImageDestinationAddImage(destination, destinationImage, nil)
        guard CGImageDestinationFinalize(destination) else { throw Err.png }
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        try FileManager.default.moveItem(at: rgb, to: url)
    }
}
func bg(_ c: C) {
    NSGradient(starting: dark, ending: purple)?.draw(in: NSRect(x: 0, y: 0, width: c.w, height: c.h), angle: 68)
    for v in [(c.w * 0.73, -c.w * 0.1, c.w * 0.62, CGFloat(0.12)), (-c.w * 0.22, c.h * 0.52, c.w * 0.66, CGFloat(0.08))] { NSColor.white.withAlphaComponent(v.3).setFill(); NSBezierPath(ovalIn: c.r(v.0, v.1, v.2, v.2)).fill() }
}
func txt(_ s: String, _ c: C, _ x: CGFloat = 70, _ top: CGFloat, _ width: CGFloat? = nil, _ height: CGFloat, _ size: CGFloat, _ weight: NSFont.Weight = .regular, _ color: NSColor = .white, _ align: NSTextAlignment = .center) {
    let p = NSMutableParagraphStyle(); p.alignment = align; p.lineBreakMode = .byWordWrapping; p.lineSpacing = size * 0.1
    NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: p]).draw(in: c.r(x, top, width ?? c.w - x * 2, height))
}
func box(_ c: C, _ x: CGFloat, _ top: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: NSColor, _ radius: CGFloat = 24, _ shadow: Bool = false) {
    let r = c.r(x, top, w, h)
    if shadow { NSGraphicsContext.saveGraphicsState(); let s = NSShadow(); s.shadowColor = NSColor.black.withAlphaComponent(0.28); s.shadowBlurRadius = 19; s.shadowOffset = NSSize(width: 0, height: -7); s.set() }
    color.setFill(); NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill(); if shadow { NSGraphicsContext.restoreGraphicsState() }
}
func image(_ i: NSImage, _ c: C, _ x: CGFloat, _ top: CGFloat, _ w: CGFloat, _ h: CGFloat, _ source: NSRect? = nil, framed: Bool = true) {
    let d = c.r(x, top, w, h)
    if framed { box(c, x, top, w, h, .white, 26, true); NSGraphicsContext.saveGraphicsState(); NSBezierPath(roundedRect: d, xRadius: 26, yRadius: 26).addClip() }
    i.draw(in: d, from: source ?? NSRect(origin: .zero, size: i.size), operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
    if framed { NSGraphicsContext.restoreGraphicsState() }
}
func imageFit(_ i: NSImage, _ c: C, _ x: CGFloat, _ top: CGFloat, _ w: CGFloat, _ h: CGFloat, framed: Bool = true) {
    if framed { box(c, x, top, w, h, .white, 26, true) }
    let inset: CGFloat = framed ? 12 : 0
    let aw = w - inset * 2, ah = h - inset * 2
    let scale = min(aw / i.size.width, ah / i.size.height)
    let dw = i.size.width * scale, dh = i.size.height * scale
    image(i, c, x + inset + (aw - dw) / 2, top + inset + (ah - dh) / 2, dw, dh, framed: false)
}
func imageSourceFit(_ i: NSImage, _ c: C, _ x: CGFloat, _ top: CGFloat, _ w: CGFloat, _ h: CGFloat, _ source: NSRect, framed: Bool = true) {
    if framed { box(c, x, top, w, h, .white, 12, true) }
    let inset: CGFloat = framed ? 7 : 0
    let aw = w - inset * 2, ah = h - inset * 2
    let scale = min(aw / source.width, ah / source.height)
    let dw = source.width * scale, dh = source.height * scale
    image(i, c, x + inset + (aw - dw) / 2, top + inset + (ah - dh) / 2, dw, dh, source, framed: false)
}
func imageFill(_ i: NSImage, _ c: C, _ x: CGFloat, _ top: CGFloat, _ w: CGFloat, _ h: CGFloat, _ source: NSRect? = nil, framed: Bool = true) {
    let src = source ?? NSRect(origin: .zero, size: i.size)
    let targetRatio = w / h
    var crop = src
    if src.width / src.height > targetRatio {
        crop.size.width = src.height * targetRatio
        crop.origin.x += (src.width - crop.width) / 2
    } else {
        crop.size.height = src.width / targetRatio
        crop.origin.y += (src.height - crop.height) / 2
    }
    image(i, c, x, top, w, h, crop, framed: framed)
}
func label(_ c: C, _ value: String, _ x: CGFloat, _ top: CGFloat, _ w: CGFloat, selected: Bool = false, small: Bool = false) {
    let h: CGFloat = small ? 24 : 38
    if selected { box(c, x, top, w, h, purple, 6) }
    txt(value, c, x + 7, top + (small ? 5 : 9), w - 14, h - 5, small ? 13 : 20, selected ? .bold : .medium, selected ? .white : ink, .left)
}
enum Mode { case vertical, horizontal, fixed, touch }
func modeCard(_ c: C, _ x: CGFloat, _ top: CGFloat, _ w: CGFloat, _ h: CGFloat, _ mode: Mode, _ caption: String) {
    box(c, x, top, w, h, paper, 28, true); box(c, x, top, w, 40, NSColor(calibratedRed: 0.11, green: 0.12, blue: 0.21, alpha: 1), 28)
    txt("記事本", c, x + 17, top + 11, w - 34, 24, min(17, w * 0.06), .bold, .white, .left)
    txt("ㄅ半注音的第一選擇", c, x + 18, top + 58, w - 36, 28, min(16, w * 0.06), .medium, ink, .left)
    txt("琦ㄑㄧˊ注音輸入法", c, x + 18, top + 91, w - 36, 28, min(16, w * 0.06), .medium, ink, .left)
    txt(caption, c, x + 16, top + h - 31, w - 32, 22, min(13, w * 0.05), .bold, purple)
    let candidates = ["1 其","2 期","3 齊","4 奇","5 旗","6 騎","7 祈","8 棋","9 祺"]
    if mode == .vertical {
        // Anchor the floating list immediately below the inline reading instead
        // of letting it drift into the middle of the editor mockup.
        let cx = x + w * 0.27, cy = top + 116, cw = w * 0.43
        box(c, cx, cy, cw, 238, NSColor(calibratedRed: 0.96, green: 0.97, blue: 1, alpha: 1), 9, true)
        for (n,v) in candidates.enumerated() { label(c, v, cx + 4, cy + 5 + CGFloat(n) * 25, cw - 8, selected: n == 0, small: true) }
    }
    if mode == .horizontal || mode == .fixed { let cy = mode == .fixed ? top + h - 108 : top + 140; let cw = w * 0.92; let cx = x + w * 0.04; box(c, cx, cy, cw, 52, NSColor(calibratedRed: 0.91, green: 0.89, blue: 0.96, alpha: 1), 8, mode == .horizontal); for (n,v) in candidates.enumerated() { let cell = cw / 9; if n == 0 { box(c, cx + CGFloat(n) * cell, cy + 7, cell, 38, purple, 6) }; txt(v.replacingOccurrences(of: " ", with: ""), c, cx + CGFloat(n) * cell, cy + 18, cell, 19, min(11, cell * 0.25), n == 0 ? .bold : .medium, n == 0 ? .white : ink) } }
    if mode == .touch { let k = min(23, w * 0.09); let l = x + (w - k * 9 - 40) / 2; for (row,count) in [(0,9),(1,8),(2,7)] { for n in 0..<count { box(c, l + CGFloat(n) * (k + 5) + CGFloat(row) * k * 0.35, top + h - 150 + CGFloat(row) * 37, k, k * 0.75, NSColor(calibratedRed: 0.93, green: 0.89, blue: 0.96, alpha: 1), 6) } }; txt("ㄅ   ㄆ   ㄇ   ㄈ   ㄉ   ㄊ   ㄋ", c, l, top + h - 147, k * 8.5, 18, 11, .bold, purple, .left) }
}
func library(_ c: C, _ x: CGFloat, _ top: CGFloat, _ w: CGFloat, _ title: String, _ sub: String, _ rows: [String], _ active: String? = nil) {
    box(c, x, top, w, 220, paper, 24, true); txt(title, c, x + 20, top + 18, w - 40, 28, 20, .bold, ink, .left); txt(sub, c, x + 20, top + 49, w - 40, 24, 13, .medium, .gray, .left)
    for (n,v) in rows.enumerated() { box(c, x + 18, top + 82 + CGFloat(n) * 38, w - 36, 31, v == active ? purple : NSColor(calibratedWhite: 0.92, alpha: 1), 8); txt(v, c, x + 28, top + 89 + CGFloat(n) * 38, w - 56, 20, 15, v == active ? .bold : .medium, v == active ? .white : ink, .left) }
}
func phoneShot(_ c: C, _ shot: NSImage, _ x: CGFloat, _ top: CGFloat, _ w: CGFloat, _ h: CGFloat, _ caption: String, zoomCandidates: Bool = false, candidateSourceY: CGFloat? = nil) {
    box(c, x, top, w, h, paper, 24, true)
    let captionH: CGFloat = 58
    imageFit(shot, c, x + 10, top + 10, w - 20, h - captionH - 18, framed: false)
    if zoomCandidates {
        // The AVD candidate row sits immediately above the touch keyboard. Keep
        // the complete row, including both arrows and candidates 1–9. Fitting the
        // crop is intentional: filling this wide strip would cut candidate 1 or 9.
        let source = NSRect(x: 0, y: candidateSourceY ?? shot.size.height - 2070, width: shot.size.width, height: 205)
        imageSourceFit(shot, c, x + 14, top + h - 150, w - 28, 68, source, framed: true)
    }
    txt(caption, c, x + 12, top + h - 48, w - 24, 30, min(18, w * 0.06), .bold, purple)
}
func comic(_ sprite: NSImage, _ c: C, _ panel: Int, _ x: CGFloat, _ top: CGFloat, _ w: CGFloat, _ h: CGFloat) {
    // Image generation leaves different amounts of transparent space around each
    // illustration. Crop each panel at its own transparent gutter so a neighbouring
    // device never leaks into the frame, then aspect-fit it into the available space.
    let panels: [(CGFloat, CGFloat)] = [
        (0, 480),
        (485, 330),
        (820, 400),
        (1260, 325),
        (1625, sprite.size.width - 1625),
    ]
    let (sourceX, sourceW) = panels[panel]
    let sourceH = sprite.size.height * 0.72
    let source = NSRect(x: sourceX, y: sprite.size.height * 0.14, width: sourceW, height: sourceH)
    let scale = min(w / sourceW, h / sourceH)
    let dw = sourceW * scale, dh = sourceH * scale
    image(sprite, c, x + (w - dw) / 2, top + (h - dh) / 2, dw, dh, source, framed: false)
}
func header(_ c: C, _ title: String, _ sub: String, _ compact: Bool) { txt(title, c, 70, compact ? 58 : 85, c.w - 140, compact ? 88 : 110, c.w * (compact ? 0.052 : 0.058), .bold); txt(sub, c, 70, compact ? 155 : 210, c.w - 140, compact ? 56 : 76, c.w * 0.026, .medium, pale); let pw = c.w * 0.35; box(c, (c.w-pw)/2, compact ? 225 : 315, pw, 60, NSColor.white.withAlphaComponent(0.16), 30); txt("琦琦注音", c, (c.w-pw)/2, (compact ? 225 : 315)+15, pw, 34, 25, .semibold) }
func copy(_ page: Int, _ android: Bool) -> (String,String) {
    if android { return [
        ("接上鍵盤，候選跟著跑","直式或橫式浮動窗貼近游標，1–9 一伸手就到"),
        ("不想浮動，也能穩穩選","關閉浮動，候選字留在實體鍵盤列"),
        ("觸控也有熟悉的五排","直式、橫式都保留ㄅ半注音的肌肉記憶"),
        ("30 種詞庫，與你更關聯","小麥注音或動漫詞庫，候選跟著你的世界走"),
        ("手機桌機，都用同一套手感","Android、iOS、macOS、Windows 都能安裝")
    ][page-1] }
    return [
        ("ㄅ半注音的第一選擇","琦琦注音，讓手指快樂回家"),
        ("五排都在，藍牙鍵盤也在","iPhone 接上實體鍵盤，熟悉的選字手感不變"),
        ("iPad 接上鍵盤，直接開打","大畫面、五排鍵盤、固定 1–9 候選都在"),
        ("30 種詞庫，與你更關聯","小麥注音或動漫詞庫，候選跟著你的世界走"),
        ("手機桌機，都用同一套手感","Android、iOS、macOS、Windows 都能安裝")
    ][page-1]
}
func page(_ c: C, _ n: Int, _ androidSet: Bool, _ ios: NSImage, _ android: NSImage, _ mac: NSImage, _ win: NSImage, _ sprite: NSImage, _ tablet: NSImage, _ dictionaries: NSImage, _ mcAssociated: NSImage, _ animeAssociated: NSImage, _ touchPortrait: NSImage, _ touchLandscape: NSImage, _ fixedPortrait: NSImage, _ fixedLandscape: NSImage, _ iosIPad: NSImage, _ iosDictionaries: NSImage, _ iosMcAssociated: NSImage, _ iosAnimeAssociated: NSImage) {
    let compact = c.h < 2200; let top: CGFloat = compact ? 330 : 470; let (title,sub) = copy(n, androidSet); header(c,title,sub,compact)
    if androidSet && n == 1 {
        let cw = c.w * 0.40
        modeCard(c,c.w*0.07,top+20,cw,570,.vertical,"直式浮動窗")
        modeCard(c,c.w*0.53,top+20,cw,570,.horizontal,"橫式浮動窗")
        imageFit(tablet,c,c.w*0.07,top+620,c.w*0.86,540)
        comic(sprite,c,0,c.w*0.30,c.h-310,c.w*0.40,250)
        return
    }
    if androidSet && n == 2 {
        // These are full AVD captures, not reconstructed keyboard mockups. Keep
        // each device orientation's native aspect ratio and every 1–9 cell.
        let portraitW = c.w * 0.36
        let portraitH = portraitW * fixedPortrait.size.height / fixedPortrait.size.width
        imageFit(fixedPortrait,c,c.w*0.045,top+20,portraitW,portraitH)
        txt("直式畫面・關閉浮動",c,c.w*0.045,top+portraitH+42,portraitW,42,24,.bold,pale)

        let landscapeW = c.w * 0.56
        let landscapeH = landscapeW * fixedLandscape.size.height / fixedLandscape.size.width
        imageFit(fixedLandscape,c,c.w*0.42,top+150,landscapeW,landscapeH)
        txt("畫面打橫・關閉浮動",c,c.w*0.42,top+landscapeH+172,landscapeW,42,24,.bold,pale)
        txt("兩張都是手機實際操作畫面；候選固定留在鍵盤列，方向改變也完整保留 1–9",c,c.w*0.43,top+landscapeH+235,c.w*0.53,110,24,.semibold,pale)
        comic(sprite,c,1,c.w*0.47,c.h-620,c.w*0.46,520)
        return
    }
    if androidSet && n == 3 {
        let portraitW = c.w * 0.37
        let portraitH = portraitW * touchPortrait.size.height / touchPortrait.size.width
        imageFit(touchPortrait,c,c.w*0.06,top+20,portraitW,portraitH)
        txt("直式觸控",c,c.w*0.06,top+portraitH+40,portraitW,40,24,.bold,pale)
        let landscapeW = c.w * 0.50
        let landscapeH = landscapeW * touchLandscape.size.height / touchLandscape.size.width
        imageFit(touchLandscape,c,c.w*0.46,top+150,landscapeW,landscapeH)
        txt("畫面打橫後的橫式觸控",c,c.w*0.46,top+landscapeH+170,landscapeW,45,24,.bold,pale)
        txt("直式、橫式都是實際操作畫面，五排鍵位與 1–9 候選完整保留",c,c.w*0.46,top+landscapeH+230,landscapeW,100,23,.semibold,pale)
        comic(sprite,c,2,c.w*0.30,c.h-310,c.w*0.40,250)
        return
    }
    if n == 4 {
        if androidSet {
            let w = c.w * 0.285, h: CGFloat = 930, y = top + 15
            phoneShot(c,dictionaries,c.w*0.045,y,w,h,"A・可選 30 種詞庫")
            phoneShot(c,mcAssociated,c.w*0.3575,y,w,h,"B・只選小麥注音",zoomCandidates:true)
            phoneShot(c,animeAssociated,c.w*0.67,y,w,h,"C・只選動漫",zoomCandidates:true)
            comic(sprite,c,2,c.w*0.33,c.h-360,c.w*0.34,300)
        } else {
            let w = c.w * 0.285, h: CGFloat = 1260, y = top + 15
            phoneShot(c,iosDictionaries,c.w*0.045,y,w,h,"A・可選 30 種詞庫")
            phoneShot(c,iosMcAssociated,c.w*0.3575,y,w,h,"B・只選小麥注音",zoomCandidates:true,candidateSourceY:iosMcAssociated.size.height*0.40)
            phoneShot(c,iosAnimeAssociated,c.w*0.67,y,w,h,"C・只選動漫",zoomCandidates:true,candidateSourceY:iosAnimeAssociated.size.height*0.40)
            comic(sprite,c,2,c.w*0.33,c.h-390,c.w*0.34,320)
        }
        return
    }
    if n == 5 { let sw = c.w*0.39; let sh: CGFloat = compact ? 430 : 560; let x1=c.w*0.08, x2=c.w*0.53, y1=top, y2=top+sh+68; imageFit(android,c,x1,y1,sw,sh); imageFit(ios,c,x2,y1,sw,sh); imageFit(mac,c,x1,y2,sw,sh); imageFit(win,c,x2,y2,sw,sh); txt("Android     iOS     macOS     Windows",c,70,y2+sh+35,c.w-140,60,min(30,c.w*0.025),.semibold,pale); return }
    if !androidSet && (n == 2 || n == 3) { let p = n == 2 ? 3 : 4; let source = n == 2 ? ios : iosIPad; let iw = c.w*(n == 2 ? 0.56 : 0.84); let ih = min(iw*source.size.height/source.size.width,c.h-top-580); imageFit(source,c,(c.w-iw)/2,top,iw,ih); comic(sprite,c,p,c.w*0.30,c.h-430,c.w*0.40,340); if n == 3 { txt("iPad 的大畫面，仍是同一套ㄅ半位置",c,70,top+ih+25,c.w-140,50,min(30,c.w*0.025),.semibold,pale) }; return }
    let iw=c.w*0.62; let ih=min(iw*ios.size.height/ios.size.width,c.h-top-80); imageFit(ios,c,(c.w-iw)/2,top,iw,ih)
}
func feature(_ android: NSImage, _ sprite: NSImage, _ out: URL) throws { let c=C(1024,500); bg(c); txt("ㄅ半注音的\n第一選擇",c,68,70,410,160,61,.bold,.white,.left); txt("浮動候選跟著游標，\n實體鍵盤也能快樂選字",c,72,276,440,84,24,.medium,pale,.left); comic(sprite,c,0,30,365,270,105); modeCard(c,535,40,205,400,.vertical,"直式浮動"); modeCard(c,770,40,205,400,.horizontal,"橫式浮動"); try c.save(out) }

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let store = root.appendingPathComponent("StoreAssets")
func load(_ name:String) throws -> NSImage { let u=store.appendingPathComponent("Sources/\(name)"); guard let i=NSImage(contentsOf:u) else { throw Err.image(u.path) }; return i }
let ios=try load("ios-notes-qi.png"), android=try load("android-notes-floating-qi.png"), mac=try load("chichi-macos.png"), win=try load("chichi-windows.png"), sprite=try load("comic-devices.png")
let tablet=try load("android-tablet-candidates.png"), dictionaries=try load("android-phone-dictionaries.png"), mcAssociated=try load("android-phone-mcbopomofo-associated-ya.png"), animeAssociated=try load("android-phone-anime-associated-ya.png")
let touchPortrait=try load("android-phone-touch-portrait.png"), touchLandscape=try load("android-phone-touch-landscape.png")
let fixedPortrait=try load("android-phone-hardware-fixed-portrait.png"), fixedLandscape=try load("android-phone-hardware-fixed-landscape.png")
let iosIPad=try load("ios-ipad-notes-qi.png"), iosDictionaries=try load("ios-phone-dictionaries.png"), iosMcAssociated=try load("ios-phone-mcbopomofo-associated-ya.png"), iosAnimeAssociated=try load("ios-phone-anime-associated-ya.png")
for (path,size,flag) in [
    ("AppStore/iPhone-1206x2622",NSSize(width:1206,height:2622),false),
    ("AppStore/iPhone-1242x2688",NSSize(width:1242,height:2688),false),
    ("AppStore/iPad-2048x2732",NSSize(width:2048,height:2732),false),
    ("GooglePlay/Phone",NSSize(width:1080,height:1920),true),
] { let out=store.appendingPathComponent(path); try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true); for n in 1...5 { let c=C(size.width,size.height); bg(c); page(c,n,flag,ios,android,mac,win,sprite,tablet,dictionaries,mcAssociated,animeAssociated,touchPortrait,touchLandscape,fixedPortrait,fixedLandscape,iosIPad,iosDictionaries,iosMcAssociated,iosAnimeAssociated); try c.save(out.appendingPathComponent(String(format:"%02d.png",n))) } }
try feature(android,sprite,store.appendingPathComponent("GooglePlay/feature-graphic-1024x500.png"))
print("Generated store artwork in \(store.path)")
