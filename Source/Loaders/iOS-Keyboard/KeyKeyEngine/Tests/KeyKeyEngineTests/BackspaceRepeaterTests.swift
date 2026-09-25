import Testing

@testable import KeyKeyEngine

@Suite("Backspace repeat pace")
struct BackspaceRepeaterTests {
    @Test("holding repeats, releasing stops every pending delete")
    @MainActor
    func holdAndRelease() async throws {
        let repeater = BackspaceRepeater()
        var deletes = 0
        repeater.start { deletes += 1 }
        try await Task.sleep(for: .milliseconds(800))
        #expect(deletes >= 1)
        repeater.stop()
        let countAfterRelease = deletes
        try await Task.sleep(for: .milliseconds(250))
        #expect(deletes == countAfterRelease)
    }
}
