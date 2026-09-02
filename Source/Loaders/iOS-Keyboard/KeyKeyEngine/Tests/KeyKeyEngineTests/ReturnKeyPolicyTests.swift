import Testing

@testable import KeyKeyEngine

@Suite("Return key policy")
struct ReturnKeyPolicyTests {
    @Test("every host return intent has a concise visible label")
    func captions() {
        for hint in ReturnKeyHint.allCases {
            let policy = ReturnKeyPolicy(hint: hint)
            #expect(policy.accessibilityLabel.isEmpty == false)
            #expect(policy.title?.count ?? 1 <= 3)
        }
    }

    @Test("search providers share the search action")
    func searchProviders() {
        #expect(ReturnKeyPolicy(hint: .search).title == "搜尋")
        #expect(ReturnKeyPolicy(hint: .google).title == "搜尋")
        #expect(ReturnKeyPolicy(hint: .yahoo).title == "搜尋")
    }
}
