import Foundation
import Testing

@testable import KeyKeyEngine

@Suite("Keyboard height")
struct KeyboardHeightTests {
    @Test("Moving the upper edge changes only the top and respects the iOS height limits")
    func upperDrag() {
        let original = KeyboardEdgeGeometry(top: 1.15, bottom: 0.125)
        let raised = original.moving(.top, by: 1)
        let lowered = original.moving(.top, by: -1)
        #expect(raised.top == 1.40)
        #expect(lowered.top == 0.875)
        #expect(raised.bottom == original.bottom)
        #expect(lowered.bottom == original.bottom)
        #expect(original.moving(.top, by: .infinity) == original)
    }

    @Test("The lower edge stops when flush and can be pulled back up")
    func lowerDrag() {
        let flush = KeyboardEdgeGeometry(top: 1.125)
        #expect(flush.moving(.bottom, by: -0.05) == flush)
        let raised = flush.moving(.bottom, by: 0.5)
        #expect(raised.bottom == 0.25)
        #expect(raised.top == flush.top)
        #expect(raised.moving(.bottom, by: -0.5) == flush)

        let shortest = KeyboardEdgeGeometry(top: 0.75)
        #expect(shortest.moving(.bottom, by: 0.125) == shortest)
        let tallest = KeyboardEdgeGeometry(top: 1.40)
        #expect(tallest.moving(.bottom, by: -0.5) == tallest)
    }

    @Test("A capped UIKit viewport reduces custom clearance before shrinking rows past their minimum")
    func cappedGap() {
        let geometry = KeyboardEdgeGeometry(top: 1.2, bottom: 0.125)
        #expect(geometry.fittedBottomGap(defaultHeight: 330, usableHeight: 350, safeAreaInsetHeight: 20) == 41.25)
        #expect(geometry.fittedBottomGap(defaultHeight: 330, usableHeight: 236, safeAreaInsetHeight: 20) == 8.5)
        #expect(geometry.fittedBottomGap(defaultHeight: 330, usableHeight: 216, safeAreaInsetHeight: 20) == 0)
        #expect(geometry.fittedBottomGap(defaultHeight: 155, usableHeight: 125, safeAreaInsetHeight: 8) == 16.75)
    }

    @Test("Hardware candidate rows reserve their native heights subject to the available viewport")
    func hardwareEditorRowFit() {
        #expect(KeyboardHeight.fittedContentHeight(24, in: 420) == 24)
        #expect(KeyboardHeight.fittedContentHeight(32, in: 780) == 32)
        #expect(KeyboardHeight.fittedContentHeight(38, in: 1024) == 38)
        #expect(KeyboardHeight.fittedContentHeight(24, in: 20) == 20)
    }

    @Test("Stored ratios survive separately in both orientations and invalid values are normalized")
    func orientationSettings() throws {
        let suite = "KeyKey.KeyboardHeightTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = KeyboardHeightSettings(defaults: defaults)
        let portrait = KeyboardEdgeGeometry(top: 1.25, bottom: 0.125)
        let landscape = KeyboardEdgeGeometry(top: 0.875, bottom: 0.0625)

        #expect(settings.geometry(for: .portrait) == KeyboardEdgeGeometry())
        settings.setGeometry(portrait, for: .portrait)
        #expect(settings.geometry(for: .landscape) == KeyboardEdgeGeometry())
        settings.setGeometry(landscape, for: .landscape)
        #expect(settings.geometry(for: .portrait) == portrait)
        #expect(settings.geometry(for: .landscape) == landscape)

        defaults.set([0.7, 0.4], forKey: "keyboardHeightPortraitEdges")
        #expect(settings.geometry(for: .portrait) == KeyboardEdgeGeometry(top: 0.75))
        #expect(settings.geometry(for: .landscape) == landscape)
        #expect(KeyboardEdgeGeometry(top: .nan, bottom: .infinity) == KeyboardEdgeGeometry())
    }
}
