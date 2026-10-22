import Foundation
import Testing
@testable import KeyKeyEngine

struct KeyboardPresentationTests {
    @Test func splitRowsKeepEveryControlOutsideTheCentre() {
        // Outer/inner Duo, capped iPad, compact landscape and narrow phone widths.
        for width in [314.0, 446, 522, 649, 795, 820] {
            for weights in [Array(repeating: 1.0, count: 11),
                            [1.65, 1, 1, 1, 3.8, 3.8, 1, 1.4, 1.4],
                            [1, 1.65, 1, 1, 1, 3.8, 3.8, 1, 1.4, 1.4]] {
                let split = weights.count == 10 ? 6 : 5
                let frames = KeyboardRowGeometry.frames(width: width, height: 24,
                                                       weights: weights, splitIndex: split)
                #expect(frames.count == weights.count)
                #expect(frames.allSatisfy { $0.width > 0 && $0.minX >= 0 && $0.maxX <= width + 0.001 })
                #expect(abs(frames[split - 1].maxX + frames[split].minX - width) < 0.001)
                #expect(frames[split].minX - frames[split - 1].maxX >= min(80, width * 0.1) - 0.001)
                for index in 1..<frames.count { #expect(frames[index].minX > frames[index - 1].maxX) }
                let full = KeyboardRowGeometry.frames(width: width, height: 24, weights: weights)
                #expect(abs(full.last!.maxX - width) < 0.001)
            }
        }
    }

    @Test func manualChoiceSurvivesRecreatingTheSettings() {
        let name = "KeyboardPresentationTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = KeyboardPresentationSettings(defaults: defaults)
        #expect(settings.presentation == .full)
        settings.setPresentation(.split)
        #expect(KeyboardPresentationSettings(defaults: defaults).presentation == .split)
        settings.setPresentation(.full)
        #expect(KeyboardPresentationSettings(defaults: defaults).presentation == .full)
    }
}
