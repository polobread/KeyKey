import Testing

@testable import KeyKeyEngine

@Suite("Document mutation guard")
struct DocumentMutationGuardTests {
    @Test("an older completion cannot release a newer mutation")
    func coalescesMutations() {
        var guardState = DocumentMutationGuard()
        let first = guardState.begin()
        let second = guardState.begin()

        guardState.end(ifCurrent: first)
        #expect(guardState.isActive)

        guardState.end(ifCurrent: second)
        #expect(!guardState.isActive)
    }

    @Test("changing documents invalidates queued mutation completions")
    func invalidatesQueuedCompletion() {
        var guardState = DocumentMutationGuard()
        let oldDocument = guardState.begin()

        guardState.invalidate()
        #expect(!guardState.isActive)

        guardState.end(ifCurrent: oldDocument)
        #expect(!guardState.isActive)
    }
}
