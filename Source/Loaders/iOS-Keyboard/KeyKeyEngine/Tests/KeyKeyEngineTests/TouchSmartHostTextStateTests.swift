import Testing

@testable import KeyKeyEngine

struct TouchSmartHostTextStateTests {
    @Test("an evicted phrase stays committed while the tail changes")
    func overflowAndBackspace() {
        var state = TouchSmartHostTextState()
        #expect(state.update(to: "請假要去哪裡玩呢去") == .init(
            deleteCount: 0, insertion: "請假要去哪裡玩呢去"
        ))
        #expect(state.update(to: "要去哪裡玩呢去海", evictedPrefix: "請假") == .init(
            deleteCount: 0, insertion: "海"
        ))
        #expect(state.editableText == "要去哪裡玩呢去海")
        #expect(state.update(to: "要去哪裡玩呢去") == .init(
            deleteCount: 1, insertion: ""
        ))
        #expect(state.update(to: "要去哪裡玩呢去海") == .init(
            deleteCount: 0, insertion: "海"
        ))
        #expect(state.finish(with: "要去哪裡玩呢去海").isEmpty)
        #expect(state.editableText.isEmpty)
    }

    @Test("a changed candidate replaces only the editable suffix")
    func candidateChange() {
        var state = TouchSmartHostTextState()
        _ = state.update(to: "要去哪裡完呢去海")
        #expect(state.update(to: "要去哪裡玩呢去海") == .init(
            deleteCount: 4, insertion: "玩呢去海"
        ))
    }

    @Test("a document switch forgets the replacement range, not its committed text")
    func reset() {
        var state = TouchSmartHostTextState()
        _ = state.update(to: "要去哪裡")
        state.reset()
        #expect(state.update(to: "海") == .init(deleteCount: 0, insertion: "海"))
    }
}
