import Foundation
import CoreText

/// A bounded, memory-only cache. OS upgrades restart the process, so unsupported
/// characters are tested again with the new system fonts. All mutable state and
/// injected probes are protected by the lock.
public final class CandidateGlyphSupport: @unchecked Sendable {
    public static let shared = CandidateGlyphSupport()
    private let cache = NSCache<NSString, NSNumber>()
    private let lock = NSLock()
    private let probe: (String) -> Bool

    public init(probe: ((String) -> Bool)? = nil) {
        cache.countLimit = 4096
        if let probe {
            self.probe = probe
        } else {
            let font = CTFontCreateUIFontForLanguage(.system, 24, nil)!
            self.probe = { Self.supports($0, font: font) }
        }
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAllObjects()
    }

    public func canDisplay(_ text: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        for character in text {
            let cluster = String(character)
            let key = cluster as NSString
            let supported: Bool
            if let value = cache.object(forKey: key) {
                supported = value.boolValue
            } else {
                supported = probe(cluster)
                cache.setObject(NSNumber(value: supported), forKey: key)
            }
            if !supported { return false }
        }
        return true
    }

    private static func supports(_ cluster: String, font: CTFont) -> Bool {
        let attributes = [NSAttributedString.Key(kCTFontAttributeName as String): font]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: cluster, attributes: attributes))
        let runs = CTLineGetGlyphRuns(line) as! [CTRun]
        let shaped = !runs.isEmpty && runs.allSatisfy { run in
            let attributes = CTRunGetAttributes(run) as NSDictionary
            let used = attributes[kCTFontAttributeName] as! CTFont
            guard !isLastResort(used) else { return false }
            var glyphs = [CGGlyph](repeating: 0, count: CTRunGetGlyphCount(run))
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            return !glyphs.contains(0)
        }
        if shaped { return true }
        // Variation selectors and joiners may have no standalone glyph while
        // their base characters still display correctly. Preserve those bases.
        return cluster.unicodeScalars.allSatisfy { scalar in
            let cp = scalar.value
            if CharacterSet.whitespacesAndNewlines.contains(scalar)
                || scalar.properties.generalCategory == .format
                || (0xFE00...0xFE0F).contains(cp) || (0xE0100...0xE01EF).contains(cp) { return true }
            let text = String(scalar) as CFString
            let fallback = CTFontCreateForString(font, text, CFRange(location: 0, length: CFStringGetLength(text)))
            guard !isLastResort(fallback) else { return false }
            let characters = Array(String(scalar).utf16)
            var glyphs = [CGGlyph](repeating: 0, count: characters.count)
            // The Boolean handles surrogate pairs; their second glyph may be 0.
            return CTFontGetGlyphsForCharacters(fallback, characters, &glyphs, characters.count)
        }
    }

    private static func isLastResort(_ font: CTFont) -> Bool {
        (CTFontCopyPostScriptName(font) as String).lowercased().contains("lastresort")
    }
}
