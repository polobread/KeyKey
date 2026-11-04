import Testing

@testable import KeyKeyEngine

@Suite("Original full profile metrics")
struct FullKeyboardMetricsTests {
    private let profile = KeyboardLayoutProfile.aligned

    @Test("the full preset chooses compact sizing independently of orientation")
    func selection() {
        #expect(profile.metrics(compactHeight: false, isPad: false, regularWidth: false) == .portrait)
        #expect(profile.metrics(compactHeight: true, isPad: false, regularWidth: false) == .compact)
        #expect(profile.metrics(compactHeight: false, isPad: true, regularWidth: false) == .pad)
        #expect(profile.metrics(compactHeight: true, isPad: true, regularWidth: false) == .pad)
    }

    @Test("regular-width phones cap wide keys without using the short landscape scale")
    func regularWidthPhone() {
        let inner = profile.metrics(compactHeight: false, isPad: false, regularWidth: true)
        #expect(inner.maximumContentWidth == profile.wideMetrics.maximumContentWidth)
        #expect(inner.contentHeight == profile.portraitMetrics.contentHeight)
        #expect(inner.stacksKeyLabels)
        #expect(profile.metrics(compactHeight: true, isPad: false, regularWidth: true) == .compact)
        #expect(profile.metrics(compactHeight: false, isPad: false, regularWidth: false) == .portrait)
    }

    @Test("the original compact scale is shorter and smaller")
    func compactIsSmaller() {
        let portrait = profile.portraitMetrics
        let compact = profile.compactMetrics
        #expect(compact.contentHeight < portrait.contentHeight)
        #expect(compact.candidateStripHeight < portrait.candidateStripHeight)
        #expect(compact.candidateFont < portrait.candidateFont)
        #expect(compact.candidateIndexFont < portrait.candidateIndexFont)
        #expect(compact.keyGlyphFont < portrait.keyGlyphFont)
        #expect(compact.functionFont < portrait.functionFont)
        #expect(compact.pageFont < portrait.pageFont)
        #expect(compact.statusFont < portrait.statusFont)
    }

    @Test("the full preset preserves its original iPhone content heights")
    func originalIPhoneHeights() {
        #expect(profile.portraitMetrics.contentHeight == 330)
        #expect(profile.compactMetrics.contentHeight == 155)
    }

    @Test("the full preset caps regular-width content without shrinking its height")
    func padWidth() {
        #expect(profile.wideMetrics.contentHeight == profile.portraitMetrics.contentHeight)
        #expect(profile.wideMetrics.maximumContentWidth < profile.portraitMetrics.maximumContentWidth)
        #expect(profile.wideMetrics.maximumContentWidth == 820)
    }

    @Test("the original compact scale collapses dual labels")
    func labelStacking() {
        #expect(profile.portraitMetrics.stacksKeyLabels)
        #expect(!profile.compactMetrics.stacksKeyLabels)
    }

    @Test("the full preset marks only its compact metrics as compact")
    func compactFlag() {
        #expect(!profile.portraitMetrics.isCompactHeight)
        #expect(profile.compactMetrics.isCompactHeight)
    }

    @Test("five bands share the height left under the candidate strip")
    func bandHeight() {
        for metrics in [profile.portraitMetrics, profile.compactMetrics, profile.wideMetrics] {
            let total = metrics.candidateStripHeight + metrics.bandHeight * 5
            #expect(abs(total - metrics.contentHeight) < 0.001)
            #expect(metrics.bandHeight > 0)
        }
        // Only this captured preset has five equal bands; other profiles may arrange rows differently.
        #expect(profile.compactMetrics.bandHeight < profile.portraitMetrics.bandHeight)
    }
}
