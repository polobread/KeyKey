import Foundation
import Testing

@testable import KeyKeyEngine

/// The cooked database is not in version control. When it is missing, say so
/// plainly -- a bare file-not-found here reads like a broken checkout.
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
        "KeyKey.db is missing. Run: (cd Source/Distributions/Takao/DatabaseCooker && make)"
    )
    return url
}

@Suite("Cooked database")
struct CandidateStoreTests {
    @Test("reading lookup matches the desktop candidate order")
    func readingLookup() throws {
        let store = try CandidateStore(database: Database(url: try cookedDatabaseURL()))

        var reading = BopomofoReading()
        for key in "su3" { reading.combine(key) }
        let candidates = store.candidates(for: reading)

        // Same expectation Android's FullDictionaryIntegrationTest pins.
        #expect(Array(candidates.prefix(3)) == ["你", "妳", "擬"])
        #expect(candidates.count > 9, "expected more than one page")
    }

    @Test("an empty reading yields nothing")
    func emptyReading() throws {
        let store = try CandidateStore(database: Database(url: try cookedDatabaseURL()))
        #expect(store.candidates(for: BopomofoReading()).isEmpty)
    }

    @Test(
        "punctuation rows live in the same table",
        arguments: [("_punctuation_<", "，"), ("_punctuation_>", "。"), ("_ctrl_opt_i", "、")]
    )
    func punctuation(key: String, expected: String) throws {
        let store = try CandidateStore(database: Database(url: try cookedDatabaseURL()))
        #expect(store.values(forNamedKey: key).first == expected)
    }

    @Test("the symbol list is a multi-row named key")
    func symbolList() throws {
        let store = try CandidateStore(database: Database(url: try cookedDatabaseURL()))
        #expect(store.values(forNamedKey: "_punctuation_list").count > 90)
    }
}

@Suite("Associated phrases")
struct AssociatedPhraseStoreTests {
    @Test("collections are listed base-first")
    func collections() throws {
        let store = AssociatedPhraseStore(database: try Database(url: try cookedDatabaseURL()))
        let collections = try store.collections()
        #expect(collections.first?.source == "McBopomofo")
        #expect(collections.first?.display == "小麥注音")
        #expect(collections.first?.sortOrder == 0)
    }

    @Test("phrases come back as frequency-ordered suffixes")
    func phrases() throws {
        let store = AssociatedPhraseStore(database: try Database(url: try cookedDatabaseURL()))
        store.setEnabledSources(["McBopomofo"])
        let phrases = store.phrases(forHeadCharacter: "一")
        #expect(!phrases.isEmpty)
        #expect(phrases.allSatisfy { !$0.isEmpty })
        // Suffixes only -- the head character is not repeated.
        #expect(phrases.allSatisfy { !$0.hasPrefix("一") } || phrases.contains("一"))
    }

    @Test("no enabled collections means no phrases")
    func noCollections() throws {
        let store = AssociatedPhraseStore(database: try Database(url: try cookedDatabaseURL()))
        store.setEnabledSources([])
        #expect(store.phrases(forHeadCharacter: "一").isEmpty)
    }

    @Test("multiple collections follow the caller's priority and deduplicate")
    func collectionPriority() throws {
        let store = AssociatedPhraseStore(database: try Database(url: try cookedDatabaseURL()))

        store.setEnabledSources(["general"])
        let general = store.phrases(forHeadCharacter: "一")
        store.setEnabledSources(["McBopomofo"])
        let base = store.phrases(forHeadCharacter: "一")
        #expect(general.first == "卡通")
        #expect(base.first == "個")

        store.setEnabledSources(["general", "McBopomofo"])
        let generalFirst = store.phrases(forHeadCharacter: "一")
        #expect(Array(generalFirst.prefix(general.count)) == general)
        #expect(generalFirst.count == Set(general + base).count)

        store.setEnabledSources(["McBopomofo", "general"])
        let baseFirst = store.phrases(forHeadCharacter: "一")
        #expect(Array(baseFirst.prefix(base.count)) == base)
        #expect(baseFirst.count == Set(general + base).count)
    }
}
