import Foundation
import Testing
import CGuanyinma
import SQLite3
@testable import KeyKeyEngine

/// A small native-adapter suite. Core algorithms and their complete matrix live
/// in guanyinma-core.yml; these tests exercise the actual Swift/C linkage.
struct GuanyinmaIntegrationTests {
    private struct Dictionary: CandidateSource {
        func candidates(for reading: BopomofoReading) -> [String] { ["你", "妳"] }
    }
    private final class Fixture {
        let directory: URL
        let model: URL
        var user: URL { directory.appendingPathComponent("Rust 使用者.db") }
        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("KeyKey-iOS-bridge-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let value = ProcessInfo.processInfo.environment["GUANYINMA_TEST_MODEL_PATH"] {
                model = URL(fileURLWithPath: value)
            } else {
                var source = URL(fileURLWithPath: #filePath)
                for _ in 0..<6 { source.deleteLastPathComponent() }
                model = source.appendingPathComponent("Distributions/Takao/CookedDatabase/KeyKey.db")
            }
            #expect(FileManager.default.fileExists(atPath: model.path))
        }
        deinit { try? FileManager.default.removeItem(at: directory) }
        func engine(method: ChineseInputMethod = .smart, hardware: Bool = false,
                    filter: @escaping (String) -> Bool = { _ in true }) throws -> GuanyinmaInputEngine {
            try GuanyinmaInputEngine(modelURL: model, userDatabaseURL: user, method: method,
                                    hardwareSmartEditing: hardware, candidateFilter: filter)
        }
        func facade(modelURL: URL? = nil) -> DualCoreInputEngine {
            DualCoreInputEngine(legacy: BopomofoEngine(dictionary: Dictionary()),
                                modelURL: modelURL ?? model, userDatabaseURL: user)
        }
        func phrases() throws -> SmartMandarinUserData {
            try SmartMandarinUserData(phrasesURL: directory.appendingPathComponent("GuanyinmaUserPhrase.db"),
                                     learningURL: directory.appendingPathComponent("GuanyinmaPhraseBridge.db"), writablePhrases: true)
        }
        func exportedUserData() throws -> [String: Any] {
            var session: OpaquePointer?
            let path = Array(model.path.utf8)
            let config = try JSONSerialization.data(withJSONObject: ["user_database": user.path])
            let code = path.withUnsafeBufferPointer { path in config.withUnsafeBytes { bytes in
                guanyinma_session_open(path.baseAddress, path.count, bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count, &session)
            } }
            #expect(code == 0)
            defer { guanyinma_session_close(&session) }
            var result: OpaquePointer?
            #expect(guanyinma_session_user_data(session, &result) == 0)
            defer { guanyinma_result_close(&result) }
            var count = 0
            #expect(guanyinma_result_json(result, nil, 0, &count) == 5)
            var bytes = [UInt8](repeating: 0, count: count)
            let capacity = bytes.count
            #expect(guanyinma_result_json(result, &bytes, capacity, &count) == 0)
            let json = try #require(JSONSerialization.jsonObject(with: Data(bytes.dropLast())) as? [String: Any])
            return try #require(json["data"] as? [String: Any])
        }
    }
    private func type(_ text: String, in engine: any InputEngine, hardware: Bool = false) {
        for character in text {
            if hardware { _ = engine.handleHardwareCharacter(character) }
            else { _ = engine.handleSoftKey(String(character)) }
        }
    }

    @Test func realCABIMapsTouchCompositionAndHostEffects() throws {
        let f = try Fixture(), engine = try f.engine()
        type("su3cl3", in: engine)
        #expect(engine.lastError == nil)
        #expect(engine.completedSmartText == "你好")
        #expect(engine.touchSmartCells == ["你", "好"])
        #expect(engine.isTouchSmartComposition)
        let entered = engine.enter()
        #expect(entered.text == "你好")
        #expect(entered.sendsReturn)
        #expect(!engine.hasComposition)
        #expect(engine.finishCompositionForInputHandoff().text.isEmpty)
        #expect(engine.backspace().deletesBackward)
    }

    @Test func associatedQueryUsesModelWhileOverlayAndKeysStayInFrontend() throws {
        let f = try Fixture()
        let decoy = f.directory.appendingPathComponent("legacy-associated.db")
        var handle: OpaquePointer?
        #expect(sqlite3_open(decoy.path, &handle) == SQLITE_OK)
        defer { sqlite3_close(handle) }
        let schema = """
            CREATE TABLE unigrams(qstring, current, probability, backoff);
            CREATE TABLE bigrams(qstring, previous, current, probability);
            CREATE TABLE "Mandarin-bpmf-cin"(key, value);
            CREATE TABLE "Generic-cj-cin"(key, value);
            CREATE TABLE "Generic-simplex-cin"(key, value);
            CREATE TABLE associated_phrases(headchar, data, source);
            INSERT INTO associated_phrases VALUES('你', '假的', 'McBopomofo');
            INSERT INTO associated_phrases VALUES('', '空鍵不應出現', 'McBopomofo');
            """
        #expect(sqlite3_exec(handle, schema, nil, nil, nil) == SQLITE_OK)
        let emptyHeadSource = try GuanyinmaAssociatedPhraseStore(modelURL: decoy, enabledSources: { ["McBopomofo"] })
        #expect(emptyHeadSource.phrases(forHeadCharacter: "你") == ["假的"])
        #expect(emptyHeadSource.phrases(forHeadCharacter: "").isEmpty)
        #expect(emptyHeadSource.lastError == nil)
        let legacy = AssociatedPhraseStore(database: try Database(url: decoy))
        legacy.setEnabledSources(["McBopomofo"])
        #expect(legacy.phrases(forHeadCharacter: "你") == ["假的"])
        let source = try GuanyinmaAssociatedPhraseStore(modelURL: f.model, enabledSources: { legacy.enabledSources })
        let expected = source.phrases(forHeadCharacter: "你")
        #expect(!expected.isEmpty)
        let engine = try GuanyinmaInputEngine(modelURL: f.model, userDatabaseURL: f.user,
            method: .traditional, hardwareSmartEditing: true, associatedPhrases: legacy)
        type("su3", in: engine, hardware: true)
        #expect(engine.selectDisplayedCandidate(0).text == "你")
        #expect(engine.lastError == nil)
        #expect(engine.isShowingAssociatedPhrases)
        #expect(engine.displayedCandidates == Array(expected.prefix(9)))
        #expect(engine.selectDisplayedCandidate(0).text == expected[0])
        #expect(!engine.isShowingAssociatedPhrases)
        legacy.setEnabledSources([])
        type("su3", in: engine, hardware: true)
        #expect(engine.selectDisplayedCandidate(0).text == "你")
        #expect(!engine.isShowingAssociatedPhrases)
        engine.setAssociatedPhraseSource(legacy)
        legacy.setEnabledSources(["McBopomofo"])
        type("su3", in: engine, hardware: true)
        #expect(engine.selectDisplayedCandidate(0).text == "你")
        #expect(engine.displayedCandidates == Array(expected.prefix(9)))
        engine.setAssociatedPhraseSource(nil)
        #expect(!engine.isShowingAssociatedPhrases)
        #expect(engine.displayedCandidates.isEmpty)
    }

    @Test func fourMethodsUseOneNativeAdapter() throws {
        let f = try Fixture()
        for method in ChineseInputMethod.allCases {
            let engine = try f.engine(method: method, hardware: true)
            if method == .smart { type("su3cl3", in: engine, hardware: true); #expect(engine.completedSmartText == "你好") }
            else if method == .traditional { type("su3", in: engine, hardware: true); #expect(!engine.displayedCandidates.isEmpty) }
            else { type("a", in: engine, hardware: true); _ = engine.space(); #expect(!engine.displayedCandidates.isEmpty || !engine.hasComposition) }
            #expect(engine.lastError == nil)
            #expect(engine.chineseInputMethod == method)
            engine.reset()
        }
    }

    @Test func switchWaitsForCandidateAndAppliedHostTransaction() throws {
        let f = try Fixture(), engine = f.facade()
        type("su3", in: engine)
        engine.requestCore(.guanyinma)
        #expect(engine.activeCore == .swift)
        #expect(engine.displayedCandidates == ["你", "妳"])
        let result = engine.selectDisplayedCandidate(1)
        #expect(result.text == "妳")
        #expect(engine.activeCore == .swift)
        engine.acknowledgeHostEffects()
        #expect(engine.activeCore == .guanyinma)
        #expect(engine.coreError == nil)
        #expect(!engine.hasComposition)
        #expect(engine.finishCompositionForInputHandoff().text.isEmpty)
    }

    @Test func missingRustModelFallsBackBeforeFirstInput() throws {
        let f = try Fixture(), engine = f.facade(modelURL: f.directory.appendingPathComponent("missing.db"))
        engine.requestCore(.guanyinma)
        #expect(engine.activeCore == .swift)
        #expect(engine.coreError != nil)
        type("su3", in: engine)
        #expect(engine.selectDisplayedCandidate(0).text == "你")
        engine.requestCore(.swift)
        #expect(engine.coreError == nil)
    }

    @Test func nativeGlyphCallbackFiltersBeforeDisplayedNumbering() throws {
        let f = try Fixture()
        let engine = try f.engine(method: .cangjie, filter: { !["天", "喬"].contains($0) })
        var options = TableInputOptions(method: .cangjie)
        options.composeWhileTyping = true; options.prefixCandidates = true
        engine.tableOptions = options
        type("hk", in: engine)
        #expect(engine.lastError == nil)
        #expect(!engine.displayedCandidates.isEmpty)
        #expect(!engine.displayedCandidates.contains("天"))
        #expect(!engine.displayedCandidates.contains("喬"))
        let selected = engine.displayedCandidates[0]
        #expect(engine.selectDisplayedCandidate(0).text == selected)
    }

    @Test func phrasePublicationReplacesOnlyPhrasesAndMissingSourcePreservesThem() throws {
        let f = try Fixture(), engine = try f.engine(), source = try f.phrases()
        try source.savePhrase(text: "測測", reading: "ㄕˋ ㄕˋ")
        let before = try Data(contentsOf: f.directory.appendingPathComponent("GuanyinmaUserPhrase.db"))
        try engine.refreshUserPhrases(from: source)
        #expect(try Data(contentsOf: f.directory.appendingPathComponent("GuanyinmaUserPhrase.db")) == before)
        let first = try f.exportedUserData()
        #expect((first["phrases"] as? [[String: Any]])?.first?["current"] as? String == "測測")
        try engine.refreshUserPhrases(from: nil)
        #expect((try f.exportedUserData()["phrases"] as? [[String: Any]])?.count == 1)
        try source.deletePhrase(id: try #require(source.userPhrases().first?.id))
        try engine.refreshUserPhrases(from: source)
        #expect((try f.exportedUserData()["phrases"] as? [[String: Any]])?.isEmpty == true)
    }

    @Test func unreadablePublicationDoesNotErasePrivatePhrases() throws {
        let f = try Fixture(), engine = try f.engine(), source = try f.phrases()
        try source.savePhrase(text: "測測", reading: "ㄕˋ ㄕˋ")
        try engine.refreshUserPhrases(from: source)
        let bad = f.directory.appendingPathComponent("bad-publication.db")
        try Data("not SQLite".utf8).write(to: bad)
        let reader = try SmartMandarinUserData(phrasesURL: f.directory.appendingPathComponent("absent.db"),
            learningURL: f.directory.appendingPathComponent("readonly-tool.db"), writablePhrases: false)
        try engine.refreshUserPhrases(from: reader)
        #expect((try f.exportedUserData()["phrases"] as? [[String: Any]])?.count == 1)
        // A file can become invalid after the FE utility was opened. The bridge
        // must report this failure and retain its last successful publication.
        try FileManager.default.removeItem(at: f.directory.appendingPathComponent("GuanyinmaUserPhrase.db"))
        try Data("not SQLite".utf8).write(to: f.directory.appendingPathComponent("GuanyinmaUserPhrase.db"))
        #expect(throws: (any Error).self) { try engine.refreshUserPhrases(from: source) }
        #expect((try f.exportedUserData()["phrases"] as? [[String: Any]])?.count == 1)
    }

    @Test func resetHelperPreservesPublishedPhrases() throws {
        let f = try Fixture(), engine = try f.engine(), source = try f.phrases()
        try source.savePhrase(text: "測測", reading: "ㄕˋ ㄕˋ")
        try engine.refreshUserPhrases(from: source)
        try GuanyinmaInputEngine.resetLearning(modelURL: f.model, userDatabaseURL: f.user)
        #expect((try f.exportedUserData()["phrases"] as? [[String: Any]])?.count == 1)
    }

    @Test func temporaryEnglishModeKeyLocksEnglishWithoutCyclingToNumbers() throws {
        let f = try Fixture(), rust = try f.engine()
        let legacy = BopomofoEngine(dictionary: Dictionary())
        for engine in [legacy as any InputEngine, rust as any InputEngine] {
            _ = engine.handleSoftKey("SHIFT")
            #expect(engine.inputMode == .english)
            #expect(engine.isTemporaryEnglish)
            _ = engine.handleSoftKey("MODE")
            #expect(engine.inputMode == .english)
            #expect(!engine.isTemporaryEnglish)
            #expect(engine.handleSoftKey("a").text == "a")
            #expect(engine.inputMode == .english)
        }
    }

    @Test func idleCoreSwitchTransfersOneShotEnglishAsStateInBothDirections() throws {
        let f = try Fixture()
        for original in InputCore.allCases {
            let engine = f.facade()
            engine.requestCore(original)
            #expect(engine.activeCore == original)
            _ = engine.handleSoftKey("SHIFT")
            #expect(engine.inputMode == .english && engine.isTemporaryEnglish)
            let destination: InputCore = original == .swift ? .guanyinma : .swift
            engine.requestCore(destination)
            #expect(engine.activeCore == destination)
            #expect(engine.inputMode == .english && engine.isTemporaryEnglish)
            #expect(engine.handleSoftKey("a").text == "a")
            #expect(engine.inputMode == .bopomofo && !engine.isTemporaryEnglish)
            engine.acknowledgeHostEffects()
            #expect(engine.handleSoftKey("s").text.isEmpty)
            #expect(engine.readingText == "ㄋ")
        }
    }

    @Test func lockedSelectionKeepsCompositionAndSymbolsCannotReplaceFailedHandoff() throws {
        let f = try Fixture(), engine = try f.engine(method: .cangjie, hardware: true)
        type("hk", in: engine, hardware: true)
        _ = engine.space()
        try #require(engine.displayedCandidates.count > 1)
        engine.moveHighlight(by: 1)
        let candidates = engine.displayedCandidates, reading = engine.readingText
        let expected = candidates[engine.highlightedIndex]
        var handle: OpaquePointer?
        try #require(sqlite3_open_v2(f.user.path, &handle, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK)
        let writer = try #require(handle)
        defer {
            sqlite3_exec(writer, "ROLLBACK", nil, nil, nil)
            sqlite3_close_v2(writer)
        }
        try #require(sqlite3_exec(writer, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK)
        #expect(engine.finishCompositionForInputHandoff().text.isEmpty)
        #expect(engine.lastError != nil)
        #expect(engine.readingText == reading)
        #expect(engine.displayedCandidates == candidates)
        #expect(engine.handleSoftKey("SYMBOL").text.isEmpty)
        #expect(engine.lastError != nil)
        #expect(engine.readingText == reading)
        #expect(engine.displayedCandidates == candidates)
        try #require(sqlite3_exec(writer, "ROLLBACK", nil, nil, nil) == SQLITE_OK)
        #expect(engine.finishCompositionForInputHandoff().text == expected)
        #expect(engine.lastError == nil)
        #expect(!engine.hasComposition && engine.displayedCandidates.isEmpty)
        #expect(engine.finishCompositionForInputHandoff().text.isEmpty)
    }

}
