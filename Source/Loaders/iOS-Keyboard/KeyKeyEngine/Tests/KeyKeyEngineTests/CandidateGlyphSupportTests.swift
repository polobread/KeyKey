import Foundation
import Testing
@testable import KeyKeyEngine

@Suite("Candidate glyph support")
struct CandidateGlyphSupportTests {
    @Test("cache whole graphemes, both positive and negative results")
    func caching() {
        var probes: [String] = []
        var nowSupported = false
        let cache = CandidateGlyphSupport { text in probes.append(text); return text != "缺" || nowSupported }
        #expect(cache.canDisplay("你好𠮷e\u{301}👩‍💻"))
        #expect(probes == ["你", "好", "𠮷", "e\u{301}", "👩‍💻"])
        #expect(cache.canDisplay("你好𠮷e\u{301}👩‍💻"))
        #expect(probes.count == 5)
        #expect(!cache.canDisplay("缺"))
        nowSupported = true
        #expect(!cache.canDisplay("缺"))
        cache.reset()
        #expect(cache.canDisplay("缺"))
        #expect(probes.count == 7)
    }

    @Test("a new process cache rechecks characters previously unsupported")
    func newLifetime() {
        let old = CandidateGlyphSupport { _ in false }
        #expect(!old.canDisplay("𠮷"))
        let afterUpgrade = CandidateGlyphSupport { _ in true }
        #expect(afterUpgrade.canDisplay("𠮷"))
    }

    @Test("shared learning reset clears glyphs even if learning database is unavailable")
    func learningReset() {
        let name = "glyph-reset-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var supported = false
        let glyphs = CandidateGlyphSupport { _ in supported }
        let app = KeyboardLearningResetRequest(localDefaults: defaults, sharedDefaults: defaults, glyphSupport: glyphs)
        #expect(!glyphs.canDisplay("字"))
        supported = true
        app.request()
        #expect(glyphs.canDisplay("字"))
        supported = false
        #expect(glyphs.canDisplay("字"))
        #expect(!app.applyIfNeeded { throw CocoaError(.fileReadNoSuchFile) })
        #expect(!glyphs.canDisplay("字"))
    }

    @Test("native fallback accepts words and emoji without accepting unassigned characters")
    func nativeFallback() {
        let glyphs = CandidateGlyphSupport()
        for text in ["你好", "妳", "A", "e\u{301}", "✌️", "🇹🇼", "👩‍💻", "你\u{E0100}", " "] {
            #expect(glyphs.canDisplay(text), "Unexpected missing glyph for \(text)")
        }
        #expect(!glyphs.canDisplay("\u{10FFFF}"))
        #expect(!glyphs.canDisplay("你\u{10FFFF}"))
    }
}
