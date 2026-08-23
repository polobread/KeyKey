import Testing

@testable import KeyKeyEngine

@Suite("Keyboard metrics")
struct KeyboardMetricsTests {
    @Test("the compact scale is chosen by height, not by width")
    func selection() {
        #expect(KeyboardMetrics.forCompactHeight(false) == .portrait)
        #expect(KeyboardMetrics.forCompactHeight(true) == .compact)
    }

    @Test("landscape is shorter and smaller throughout")
    func compactIsSmaller() {
        let portrait = KeyboardMetrics.portrait
        let compact = KeyboardMetrics.compact
        #expect(compact.contentHeight < portrait.contentHeight)
        #expect(compact.candidateStripHeight < portrait.candidateStripHeight)
        #expect(compact.candidateFont < portrait.candidateFont)
        #expect(compact.candidateIndexFont < portrait.candidateIndexFont)
        #expect(compact.keyGlyphFont < portrait.keyGlyphFont)
        #expect(compact.functionFont < portrait.functionFont)
        #expect(compact.pageFont < portrait.pageFont)
        #expect(compact.statusFont < portrait.statusFont)
    }

    @Test("the Android heights are preserved")
    func androidHeights() {
        #expect(KeyboardMetrics.portrait.contentHeight == 330)
        #expect(KeyboardMetrics.compact.contentHeight == 155)
    }

    @Test("only portrait has room to stack the dual key labels")
    func labelStacking() {
        #expect(KeyboardMetrics.portrait.stacksKeyLabels)
        #expect(!KeyboardMetrics.compact.stacksKeyLabels)
    }

    @Test("the compact flag identifies the landscape scale directly")
    func compactFlag() {
        #expect(!KeyboardMetrics.portrait.isCompactHeight)
        #expect(KeyboardMetrics.compact.isCompactHeight)
    }

    @Test("five bands share the height left under the candidate strip")
    func bandHeight() {
        for metrics in [KeyboardMetrics.portrait, .compact] {
            let total = metrics.candidateStripHeight + metrics.bandHeight * 5
            #expect(abs(total - metrics.contentHeight) < 0.001)
            #expect(metrics.bandHeight > 0)
        }
        // Landscape keys end up a little over half the portrait height.
        #expect(KeyboardMetrics.compact.bandHeight < KeyboardMetrics.portrait.bandHeight)
    }
}
