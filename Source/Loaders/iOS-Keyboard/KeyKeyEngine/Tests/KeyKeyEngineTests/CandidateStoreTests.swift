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

@Suite("Smart Mandarin language model")
struct SmartMandarinStoreTests {
    @Test("the cooked mobile language model includes the current bigram corpus")
    func bigramCorpusSize() throws {
        let database = try Database(url: try cookedDatabaseURL())
        let rows = try database.prepare("SELECT COUNT(*) FROM bigrams")
            .firstColumnStrings([])
        #expect((Int(rows.first ?? "") ?? 0) == 885_614)
    }

    private func query(_ keys: String) -> String {
        var reading = BopomofoReading()
        for key in keys { reading.combine(key) }
        return reading.queryKey
    }

    @Test("the iOS walker uses the cooked bigram model for continuous text")
    func continuousSentence() throws {
        let database = try Database(url: try cookedDatabaseURL())
        let store = try SmartMandarinStore(database: database)
        let readings = ["rup", "wu0", "1o4", "fu;6", "54", "g/", "ru6", "2l4"]
            .map(query)
        let composition = try #require(store.compose(readings: readings, overrides: [:]))
        #expect(composition.text == "今天被強制升級到")
        #expect(composition.segments.map(\.text) == ["今天", "被", "強制", "升級", "到"])
    }

    @Test("common first syllables outrank rare readings of frequent characters")
    func readingSpecificFirstSyllables() throws {
        let store = try SmartMandarinStore(database: Database(url: try cookedDatabaseURL()))
        for (keys, expected) in [
            ("1j4", "不"), ("xu,4", "列"), ("au4", "密"),
            ("up4", "印"), ("294", "代"), ("cj06", "環"),
            ("b4", "日"), ("su3", "你"), ("vm,4", "血")
        ] {
            let reading = query(keys)
            #expect(store.compose(readings: [reading], overrides: [:])?.text == expected)
            #expect(store.candidates(for: [reading], at: 0, composition: nil).first == expected)
        }

        let phrase = ["xu,4", "g;4", "fm4"].map(query)
        #expect(store.compose(readings: phrase, overrides: [:])?.text == "列上去")
    }

    @Test("an explicit candidate override is preserved while the rest is reranked")
    func override() throws {
        let database = try Database(url: try cookedDatabaseURL())
        let store = try SmartMandarinStore(database: database)
        let reading = query("su3")
        let composition = try #require(store.compose(
            readings: [reading], overrides: [0: "妳"]
        ))
        #expect(composition.text == "妳")
    }

    @Test("shared custom phrases and private learning affect composition without changing cooked data")
    func userData() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let phrasesURL = directory.appendingPathComponent("group/UserPhrase.db")
        let keyboard = try SmartMandarinUserData(
            phrasesURL: phrasesURL,
            learningURL: directory.appendingPathComponent("keyboard/learning.db"),
            writablePhrases: false
        )
        #expect(keyboard.unigrams(for: query("su3") + query("cl3")).isEmpty)
        let editor = try SmartMandarinUserData(
            phrasesURL: phrasesURL,
            learningURL: directory.appendingPathComponent("app/learning.db"),
            writablePhrases: true
        )
        try editor.savePhrase(text: "琦琦", reading: "su3cl3")
        #expect(editor.userPhrases().first?.reading == "ㄋㄧˇ ㄏㄠˇ")

        let store = try SmartMandarinStore(
            database: Database(url: try cookedDatabaseURL()), userData: keyboard
        )
        let readings = [query("su3"), query("cl3")]
        #expect(store.compose(readings: readings, overrides: [:])?.text == "琦琦")
        keyboard.learnCandidate(query: readings[0], current: "妳")
        #expect(store.candidates(for: [readings[0]], at: 0, composition: nil).first == "妳")
        try keyboard.resetLearning()
        #expect(keyboard.learnedCandidate(for: readings[0]) == nil)
        #expect(editor.userPhrases().count == 1)

        let imported = try SmartMandarinUserData(
            phrasesURL: directory.appendingPathComponent("second/UserPhrase.db"),
            learningURL: directory.appendingPathComponent("second/learning.db"),
            writablePhrases: true
        )
        #expect(try imported.importPhrases(editor.exportPhrases()).imported == 1)
        #expect(imported.userPhrases().first?.text == "琦琦")
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
