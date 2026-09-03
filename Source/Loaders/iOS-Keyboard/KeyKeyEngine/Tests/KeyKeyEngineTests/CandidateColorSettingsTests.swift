import Foundation
import Testing

@testable import KeyKeyEngine

@Suite("Candidate color settings")
struct CandidateColorSettingsTests {
    private func settings() -> (CandidateColorSettings, UserDefaults) {
        let name = "tw.chichi77.keykey.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return (CandidateColorSettings(defaults: defaults), defaults)
    }

    @Test("purple is the first-run and invalid-value default")
    func defaultsToPurple() {
        let (settings, defaults) = settings()
        #expect(settings.color == .purple)
        defaults.set("unknown", forKey: "candidate_highlight_color")
        #expect(settings.color == .purple)
    }

    @Test("all desktop colors survive a new reader")
    func persistence() {
        let (settings, defaults) = settings()
        for color in CandidateColor.allCases {
            settings.setColor(color)
            #expect(CandidateColorSettings(defaults: defaults).color == color)
        }
    }
}
