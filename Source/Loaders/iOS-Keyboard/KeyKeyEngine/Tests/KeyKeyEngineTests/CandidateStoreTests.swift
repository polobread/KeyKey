import Foundation
import Testing

@testable import KeyKeyEngine

/// Use the committed shared model; tests never rebuild or cook it.
private func cookedDatabaseURL() throws -> URL {
    let source = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // .../Tests/KeyKeyEngineTests
        .deletingLastPathComponent()  // .../Tests
        .deletingLastPathComponent()  // .../KeyKeyEngine
        .deletingLastPathComponent()  // .../iOS-Keyboard
        .deletingLastPathComponent()  // .../Loaders
        .deletingLastPathComponent()  // .../Source
    let url = source
        .appendingPathComponent("Distributions/Takao/CookedDatabase/KeyKey.db")
    try #require(
        FileManager.default.fileExists(atPath: url.path),
        "The committed shared KeyKey.db is missing."
    )
    return url
}

@Suite("Guanyinma associated-phrase transport")
struct GuanyinmaAssociatedPhraseStoreTests {
    @Test("C ABI preserves source priority and follows live collection settings")
    func queriesUseRustAndLiveSelection() throws {
        let model = try cookedDatabaseURL()
        let legacy = AssociatedPhraseStore(database: try Database(url: model))
        let rust = try GuanyinmaAssociatedPhraseStore(modelURL: model, enabledSources: { legacy.enabledSources })
        legacy.setEnabledSources(["McBopomofo"])
        let original = rust.phrases(forHeadCharacter: "一")
        #expect(!original.isEmpty && rust.lastError == nil)
        legacy.setEnabledSources([])
        #expect(rust.phrases(forHeadCharacter: "一").isEmpty)
        legacy.setEnabledSources(["McBopomofo"])
        #expect(rust.phrases(forHeadCharacter: "一") == original)
        #expect(try legacy.collections().first?.display == "小麥注音")
        let names = try rust.collections()
        #expect(names.map(\.source) == names.map(\.source).sorted())
        #expect(names.first?.source == "McBopomofo")
        #expect(names.first?.display == "小麥注音")
        #expect(names.first?.sortOrder == 0)
    }

    @Test("read-only Rust connection rejects missing models without legacy fallback")
    func missingModelFails() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".db")
        #expect(throws: GuanyinmaInputError.self) {
            _ = try GuanyinmaAssociatedPhraseStore(modelURL: missing, enabledSources: { ["McBopomofo"] })
        }
        #expect(!FileManager.default.fileExists(atPath: missing.path))
    }
}
