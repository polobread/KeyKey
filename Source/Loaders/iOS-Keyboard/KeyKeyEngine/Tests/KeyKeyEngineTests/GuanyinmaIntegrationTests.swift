import Foundation
import Testing
import CGuanyinma
import SQLite3
@testable import KeyKeyEngine

/// A small native-adapter suite. Core algorithms and their complete matrix live
/// in guanyinma-core.yml; these tests exercise the actual Swift/C linkage.
struct GuanyinmaIntegrationTests {
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
                    layout: BopomofoKeyboardLayout = .standard,
                    filter: @escaping (String) -> Bool = { _ in true }) throws -> GuanyinmaInputEngine {
            try GuanyinmaInputEngine(modelURL: model, userDatabaseURL: user, method: method,
                                    hardwareSmartEditing: hardware, keyboardLayout: layout, candidateFilter: filter)
        }
        func facade(modelURL: URL? = nil) throws -> KeyboardInputEngine {
            try KeyboardInputEngine(modelURL: modelURL ?? model, userDatabaseURL: user)
        }
        func phrases() throws -> SharedPhrasePublication {
            try SharedPhrasePublication(phrasesURL: directory.appendingPathComponent("GuanyinmaUserPhrase.db"),
                                        writablePhrases: true)
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

    @Test func hanyuPinyinReusesTheNativeTouchAndHardwareInputPaths() throws {
        let fixture = try Fixture()
        let smart = try fixture.engine()
        _ = smart.setKeyboardLayout(.hanyuPinyin)
        type("ni", in: smart)
        #expect(smart.readingText == "ni")
        _ = smart.handleSoftKey("BACKSPACE")
        #expect(smart.readingText == "n")
        type("i3hao3", in: smart)
        #expect(smart.completedSmartText == "你好")
        #expect(smart.enter().text == "你好")

        let traditional = try fixture.engine(method: .traditional, hardware: true, layout: .hanyuPinyin)
        type("zhong", in: traditional, hardware: true)
        #expect(traditional.readingText == "zhong")
        _ = traditional.space()
        let middle = try #require(traditional.displayedCandidates.firstIndex(of: "中"))
        #expect(traditional.selectDisplayedCandidate(middle).text == "中")
    }

    @Test func toneOmissionIsOptInAndKeepsAllTouchLayoutsAndExplicitTones() throws {
        let fixture = try Fixture()
        let engine = try fixture.engine()
        #expect(!engine.omitsTones)

        for (layout, untoned, toned, reading) in [
            (BopomofoKeyboardLayout.standard, "sucl", "su3cl3", "ㄋㄧㄏㄠ"),
            (.hsu, "nehw", "nefhwf", "nehw"),
            (.hanyuPinyin, "nihao", "ni3hao3", "nihao"),
        ] {
            _ = engine.setKeyboardLayout(layout)
            engine.omitsTones = false
            type(untoned, in: engine)
            #expect(!engine.isShowingPhoneticSuggestions && engine.displayedCandidates.isEmpty)
            engine.reset()
            if layout == .hsu {
                type(toned, in: engine)
                #expect(engine.completedSmartText == "你好")
                #expect(engine.enter().text == "你好")
            }

            engine.omitsTones = true
            type(untoned, in: engine)
            #expect(engine.hasPendingPhoneticInput)
            #expect(engine.usesTouchPhoneticGrid)
            #expect(engine.displayedCandidates.isEmpty)
            #expect(engine.touchSmartCells == ["你", "好"])
            #expect(engine.touchSmartEditableCount == 2)
            #expect(engine.touchSmartHostReading == reading)
            #expect(engine.completedSmartText.isEmpty)
            #expect(engine.selectTouchSmartCell(0))
            #expect(engine.displayedCandidates.allSatisfy { $0.count == 1 })
            #expect(engine.selectTouchSmartCell(0))
            #expect(engine.displayedCandidates.isEmpty)
            #expect(engine.selectTouchSmartCell(0))
            let choice = try #require(engine.displayedCandidates.firstIndex { $0 != "你" })
            let replacement = engine.displayedCandidates[choice]
            #expect(engine.selectDisplayedCandidate(choice) == .update)
            #expect(engine.touchSmartCells == [replacement, "好"])
            #expect(engine.touchSmartHostReading == reading)
            #expect(engine.enter().text == replacement + "好")
            #expect(engine.finishCompositionForInputHandoff() == .update)

            type(untoned, in: engine)
            let entered = engine.enter()
            #expect(entered.text == "你好" && entered.sendsReturn)

            type(toned, in: engine)
            if layout == .hsu {
                #expect(engine.touchSmartCells == ["你", "好"])
                #expect(engine.touchSmartHostReading == toned)
            } else {
                #expect(engine.completedSmartText == "你好")
            }
            #expect(engine.enter().text == "你好")
            #expect(engine.lastError == nil)
        }

        _ = engine.setKeyboardLayout(.hsu)
        #expect(engine.usesTouchPhoneticGrid)
        _ = engine.setKeyboardLayout(.standard)
        #expect(engine.usesTouchPhoneticGrid)

        let hardware = try fixture.engine(hardware: true, layout: .hanyuPinyin)
        hardware.omitsTones = true
        type("nihao", in: hardware, hardware: true)
        #expect(!hardware.hasPendingPhoneticInput && hardware.displayedCandidates.isEmpty)
    }

    @Test func toneOmissionPinyinKeepsAnElevenCellWindowWhenTheHostPrefixShifts() throws {
        let fixture = try Fixture()
        let engine = try fixture.engine(layout: .hanyuPinyin)
        engine.omitsTones = true
        let elevenReadings = String(repeating: "zhuang", count: 11)
        type(elevenReadings, in: engine)
        #expect(engine.touchSmartCells.count == 11)
        #expect(engine.touchSmartHostReading == elevenReadings)

        var committed = ""
        for key in "zhuang" { committed += engine.handleSoftKey(String(key)).text }
        #expect(!committed.isEmpty)
        #expect(engine.touchSmartCells.count <= 11)
        #expect(engine.touchSmartHostReading == String(repeating: "zhuang", count: 12 - committed.count))
        let tail = engine.touchSmartCells.joined()
        #expect(engine.enter().text == tail)
        #expect(committed.count + tail.count == 12)
        #expect(engine.touchSmartHostReading.isEmpty)
    }

    @Test func keyboardDismissalKeepsConvertedSmartTextAndDropsPendingReadingOnce() throws {
        let f = try Fixture(), engine = try f.facade()
        type("su3c", in: engine)
        #expect(engine.completedSmartText == "你" && engine.readingText == "ㄏ")
        var host = TouchSmartHostTextState()
        _ = host.update(to: engine.completedSmartText)
        let handoff = engine.finishCompositionForKeyboardDismissal()
        #expect(handoff.succeeded)
        #expect(handoff.result == .commit("你"))
        #expect(host.finish(with: handoff.result.text).isEmpty, "The host already contains the completed prefix")
        #expect(!engine.hasComposition && engine.readingText.isEmpty && engine.displayedCandidates.isEmpty)
        let repeated = engine.finishCompositionForKeyboardDismissal()
        #expect(repeated.succeeded && repeated.result == .update)
        engine.acknowledgeHostEffects()
        #expect(engine.finishCompositionForKeyboardDismissal().result == .update)
        #expect(engine.finishCompositionForInputHandoff() == .update)
        #expect(engine.coreError == nil)
    }

    @Test func keyboardDismissalKeepsCompletedSmartTextWithCandidatesOpen() throws {
        let f = try Fixture(), engine = try f.facade()
        type("su3cl3", in: engine)
        let completed = engine.completedSmartText
        try #require(engine.selectTouchSmartCell(0))
        try #require(!engine.displayedCandidates.isEmpty)
        engine.moveHighlight(by: 1)
        let handoff = engine.finishCompositionForKeyboardDismissal()
        #expect(handoff.succeeded && handoff.result == .commit(completed))
        #expect(!engine.hasComposition && engine.displayedCandidates.isEmpty)
        engine.acknowledgeHostEffects()
        #expect(engine.finishCompositionForKeyboardDismissal().result == .update)
        #expect(engine.coreError == nil)
    }

    @Test func keyboardDismissalCancelsAPureSmartReading() throws {
        let f = try Fixture(), engine = try f.facade()
        type("c", in: engine)
        #expect(engine.completedSmartText.isEmpty && engine.readingText == "ㄏ")
        let handoff = engine.finishCompositionForKeyboardDismissal()
        #expect(handoff.succeeded && handoff.result == .update)
        #expect(!engine.hasComposition && engine.readingText.isEmpty)
        #expect(engine.finishCompositionForKeyboardDismissal().result == .update)
        #expect(engine.coreError == nil)
    }

    @Test func keyboardDismissalConfirmsTraditionalCandidateButCancelsUnfinishedReading() throws {
        let f = try Fixture()
        let engine = try KeyboardInputEngine(modelURL: f.model, userDatabaseURL: f.user, method: .traditional)
        type("su3", in: engine)
        try #require(!engine.displayedCandidates.isEmpty)
        if engine.pageCount > 1 { engine.changePage(by: 1) }
        engine.moveHighlight(by: 1)
        let expected = engine.displayedCandidates[engine.highlightedIndex]
        let completed = engine.finishCompositionForKeyboardDismissal()
        #expect(completed.succeeded && completed.result == .commit(expected))
        engine.acknowledgeHostEffects()
        type("c", in: engine)
        try #require(engine.hasComposition && engine.displayedCandidates.isEmpty)
        let pending = engine.finishCompositionForKeyboardDismissal()
        #expect(pending.succeeded && pending.result == .update)
        #expect(!engine.hasComposition && engine.readingText.isEmpty)
        #expect(engine.finishCompositionForKeyboardDismissal().result == .update)
        #expect(engine.coreError == nil)
    }

    @Test func keyboardDismissalCancelsUnselectedRootsWithAndWithoutPreviewCandidates() throws {
        for method in [ChineseInputMethod.cangjie, .simplex] {
            for preview in [false, true] {
                let f = try Fixture()
                var options = TableInputOptions(method: method)
                options.queryAtMaximum = false
                options.composeWhileTyping = preview
                options.prefixCandidates = preview && method == .cangjie
                options.clearOnError = false
                let engine = try KeyboardInputEngine(modelURL: f.model, userDatabaseURL: f.user,
                    method: method, tableOptions: options)
                type("h", in: engine)
                try #require(engine.hasComposition)
                if preview { try #require(!engine.displayedCandidates.isEmpty) }
                let handoff = engine.finishCompositionForKeyboardDismissal()
                #expect(handoff.succeeded && handoff.result == .update)
                #expect(!engine.hasComposition && engine.readingText.isEmpty && engine.displayedCandidates.isEmpty)
                engine.acknowledgeHostEffects()
                #expect(engine.finishCompositionForKeyboardDismissal().result == .update)
                #expect(engine.coreError == nil)
            }
        }
    }

    @Test func closeTouchCandidatesPreservesCompositionAndSentenceEnd() throws {
        let f = try Fixture(), facade = try f.facade()
        let engine: any InputEngine = facade
        type("su3cl3", in: engine)
        #expect(engine.selectTouchSmartCell(0))
        let correction = try #require(engine.displayedCandidates.firstIndex(of: "妳"))
        #expect(engine.selectDisplayedCandidate(correction) == .update)
        #expect(engine.composingText == "妳好")
        #expect(engine.composingCaretUTF16Offset == 2)
        #expect(engine.selectTouchSmartCell(0))
        let firstPage = engine.displayedCandidates
        try #require(engine.pageCount > 1)
        engine.changePage(by: 1)
        #expect(engine.page == 1)
        var host = TouchSmartHostTextState()
        _ = host.update(to: engine.completedSmartText)
        #expect(engine.closeTouchSmartCandidates() == .update)
        #expect(engine.composingText == "妳好" && engine.smartCompositionReadingCount == 2)
        #expect(engine.displayedCandidates.isEmpty && !engine.isShowingSmartCandidates)
        #expect(engine.page == 0 && engine.pageCount == 0)
        #expect(host.update(to: engine.completedSmartText).isEmpty)
        #expect(engine.closeTouchSmartCandidates() == .update)
        #expect(engine.selectTouchSmartCell(0))
        #expect(engine.displayedCandidates == firstPage)
        _ = engine.closeTouchSmartCandidates()
        type("su3", in: engine)
        // Selection learning can change the new syllable's candidate. The FE
        // contract is insertion at the sentence end and an unchanged prefix.
        let completed = engine.composingText
        #expect(completed.hasPrefix("妳好") && engine.smartCompositionReadingCount == 3)
        #expect(engine.finishCompositionForInputHandoff() == .commit(completed))
        #expect(facade.coreError == nil)
    }

    @Test(arguments: [false, true])
    func closeTouchCandidatesAllowsBackspaceAtSentenceEnd(toggleSameCell: Bool) throws {
        let f = try Fixture(), engine = try f.facade()
        type("su3cl3", in: engine)
        try #require(engine.selectTouchSmartCell(0))
        let correction = try #require(engine.displayedCandidates.firstIndex(of: "妳"))
        #expect(engine.selectDisplayedCandidate(correction) == .update)
        let completed = engine.completedSmartText
        #expect(completed == "妳好")
        var host = TouchSmartHostTextState()
        _ = host.update(to: completed)
        engine.acknowledgeHostEffects()
        try #require(engine.selectTouchSmartCell(0))
        try #require(!engine.displayedCandidates.isEmpty)
        if toggleSameCell { #expect(engine.selectTouchSmartCell(0)) }
        else { #expect(engine.closeTouchSmartCandidates() == .update) }
        #expect(engine.completedSmartText == completed && engine.displayedCandidates.isEmpty)
        #expect(host.update(to: engine.completedSmartText).isEmpty)
        let beforeCount = engine.smartCompositionReadingCount
        #expect(engine.backspace() == .update)
        #expect(engine.smartCompositionReadingCount == beforeCount - 1)
        #expect(engine.completedSmartText == "妳", "Delete the sentence tail, not the candidate target or its override")
        #expect(host.update(to: engine.completedSmartText) == .init(deleteCount: 1, insertion: ""))
        engine.acknowledgeHostEffects()
        #expect(engine.coreError == nil)
    }

    @Test func closeTouchCandidatesAllowsBackspaceWithoutEditingEvictedPrefix() throws {
        let f = try Fixture(), engine = try f.facade()
        var host = TouchSmartHostTextState()
        var document = "", evictedPrefix = ""
        func applyToHost(_ result: KeyboardInput.Result) {
            let edit = host.update(to: engine.completedSmartText, evictedPrefix: result.text)
            document.removeLast(edit.deleteCount)
            document += edit.insertion
            evictedPrefix += result.text
            engine.acknowledgeHostEffects()
        }
        // The touch frontend uses the existing nine/ten-syllable handoff.
        for syllable in 0..<10 {
            for key in "su3" { applyToHost(engine.handleSoftKey(String(key))) }
            if syllable == 8 { #expect(evictedPrefix.isEmpty) }
        }
        try #require(!evictedPrefix.isEmpty)
        let retainedCount = engine.smartCompositionReadingCount
        try #require(retainedCount > 0 && retainedCount < 10)
        #expect(document == evictedPrefix + engine.completedSmartText)
        try #require(engine.selectTouchSmartCell(0))
        try #require(!engine.displayedCandidates.isEmpty)
        #expect(engine.closeTouchSmartCandidates() == .update)
        #expect(host.update(to: engine.completedSmartText).isEmpty)
        for remaining in stride(from: retainedCount, through: 1, by: -1) {
            let result = engine.backspace()
            #expect(result == .update)
            applyToHost(result)
            #expect(engine.smartCompositionReadingCount == remaining - 1)
            #expect(document.hasPrefix(evictedPrefix))
        }
        #expect(document == evictedPrefix, "Backspace within the graph cannot revisit its already-evicted prefix")
        #expect(host.editableText.isEmpty && !engine.hasComposition)
        #expect(engine.coreError == nil)
    }

    @Test func closeTouchCandidatesPreservesUnfinishedReadingAndConvertedPrefix() throws {
        let f = try Fixture(), facade = try f.facade()
        let engine: any InputEngine = facade
        // Guanyinma has one model source; retain the old fallback regression's
        // unfinished-reading intent without recreating the removed Swift engine.
        type("su3cl", in: engine)
        #expect(engine.composingText == "你ㄏㄠ" && engine.readingText == "ㄏㄠ")
        #expect(engine.displayedCandidates.isEmpty)
        #expect(engine.closeTouchSmartCandidates() == .update)
        #expect(engine.composingText == "你ㄏㄠ" && engine.readingText == "ㄏㄠ")
        #expect(engine.backspace() == .update)
        #expect(engine.composingText == "你ㄏ")
        type("l3", in: engine)
        #expect(engine.composingText == "你好")
        #expect(engine.finishCompositionForInputHandoff() == .commit("你好"))
        #expect(facade.coreError == nil)
    }

    @Test func closeTouchCandidatesDoesNotAlterTraditionalOrHardwareModes() throws {
        for (method, hardware) in [(ChineseInputMethod.traditional, false), (.smart, true)] {
            let f = try Fixture()
            let facade = try KeyboardInputEngine(modelURL: f.model, userDatabaseURL: f.user,
                method: method, hardwareSmartEditing: hardware)
            let engine: any InputEngine = facade
            type("su3", in: engine, hardware: hardware)
            if hardware { _ = engine.openSmartCandidates() }
            let text = engine.composingText, candidates = engine.displayedCandidates
            try #require(!candidates.isEmpty)
            #expect(!engine.isTouchSmartComposition)
            #expect(engine.closeTouchSmartCandidates() == .update)
            #expect(engine.composingText == text && engine.displayedCandidates == candidates)
            #expect(facade.coreError == nil)
        }
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
        #expect(legacy.enabledSources == ["McBopomofo"])
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

    @Test(arguments: [0, 1, 2])
    func physicalCandidatesTargetTheRightHandWordAndResumeAfterSelection(position: Int) throws {
        let f = try Fixture(), engine = try f.engine(hardware: true)
        type("su3cl3", in: engine, hardware: true)
        #expect(engine.moveSmartCompositionCursor(by: position - 2))
        #expect(engine.openSmartCandidates() == .update)
        let target = position == 0 ? "妳" : "郝"
        let selected = try #require(engine.displayedCandidates.firstIndex(of: target))
        #expect(engine.selectDisplayedCandidate(selected) == .update)
        #expect(engine.completedSmartText == (position == 0 ? "妳好" : "你郝"))
        #expect(engine.composingCaretUTF16Offset == (position == 0 ? 1 : 2))
        type("a8 ", in: engine, hardware: true)
        #expect(engine.smartCompositionReadingCount == 3)
        let completed = engine.completedSmartText
        #expect(completed.count == 3)
        #expect(position == 0
            ? completed.hasPrefix("妳") && completed.hasSuffix("好")
            : completed.hasPrefix("你郝"))
        #expect(engine.lastError == nil)
    }

    @Test(arguments: [0, 1, 2])
    func physicalForwardDeleteRemovesOnlyTheRightReadingAndStaysDeleted(position: Int) throws {
        let f = try Fixture(), engine = try f.engine(hardware: true)
        type("su3cl3", in: engine, hardware: true)
        #expect(engine.moveSmartCompositionCursor(by: position - 2))
        #expect(engine.deleteForward() == .update)
        #expect(engine.completedSmartText == (position == 0 ? "好" : position == 1 ? "你" : "你好"))
        #expect(engine.smartCompositionReadingCount == (position == 2 ? 2 : 1))
        type("a8 ", in: engine, hardware: true)
        #expect(engine.smartCompositionReadingCount == (position == 2 ? 3 : 2))
        let completed = engine.completedSmartText
        #expect(completed.count == (position == 2 ? 3 : 2))
        #expect(position == 0 ? completed.hasSuffix("好") : completed.hasPrefix("你"))
        #expect(engine.lastError == nil)
    }

    @Test func physicalForwardDeleteClearsLastReadingAndLeavesHostDeletionToFrontend() throws {
        let f = try Fixture()
        let engine = try KeyboardInputEngine(modelURL: f.model, userDatabaseURL: f.user,
                                            hardwareSmartEditing: true)
        #expect(engine.deleteForward() == .update)
        #expect(!engine.hasComposition)
        type("su3", in: engine, hardware: true)
        #expect(engine.moveSmartCompositionCursor(by: -1))
        #expect(engine.deleteForward() == .update)
        #expect(!engine.hasComposition && engine.composingText.isEmpty)
        #expect(engine.smartCompositionReadingCount == 0)
        type("cl3", in: engine, hardware: true)
        #expect(engine.completedSmartText == "好")
        #expect(engine.enter() == .commit("好"))
        engine.acknowledgeHostEffects()
        #expect(engine.deleteForward() == .update)
        #expect(engine.coreError == nil)
    }

    @Test func physicalForwardDeletePreservesPendingReadingsAndOpenCandidates() throws {
        do {
            let f = try Fixture(), engine = try f.engine(hardware: true)
            type("su3cl3s", in: engine, hardware: true)
            let before = engine.composingText, reading = engine.readingText
            try #require(!reading.isEmpty)
            #expect(engine.deleteForward() == .update)
            #expect(engine.composingText == before && engine.readingText == reading)
            #expect(engine.smartCompositionReadingCount == 2)
            #expect(engine.lastError == nil)
        }
        do {
            let f = try Fixture(), engine = try f.engine(hardware: true)
            type("su3cl3", in: engine, hardware: true)
            #expect(engine.moveSmartCompositionCursor(by: -1))
            _ = engine.openSmartCandidates()
            let candidates = engine.displayedCandidates, before = engine.composingText
            try #require(!candidates.isEmpty)
            #expect(engine.deleteForward() == .update)
            #expect(engine.displayedCandidates == candidates && engine.composingText == before)
            #expect(engine.smartCompositionReadingCount == 2)
            #expect(engine.lastError == nil)
        }
    }

    @Test func requiredRustConstructionFailsWithoutCreatingAnAlternateStore() throws {
        let f = try Fixture()
        #expect(throws: GuanyinmaInputError.self) {
            _ = try f.facade(modelURL: f.directory.appendingPathComponent("missing.db"))
        }
        #expect(!FileManager.default.fileExists(atPath: f.user.path))
    }

    @Test func publicationWaitsForCompositionAndAcceptedHostEffects() throws {
        let f = try Fixture(), engine = try f.facade(), source = try f.phrases()
        type("su3cl3", in: engine)
        try source.savePhrase(text: "測測", reading: "ㄕˋ ㄕˋ")
        try engine.refreshUserPhrases(from: source)
        #expect((try f.exportedUserData()["phrases"] as? [[String: Any]])?.isEmpty == true)
        #expect(engine.enter().text == "你好")
        #expect((try f.exportedUserData()["phrases"] as? [[String: Any]])?.isEmpty == true)
        engine.acknowledgeHostEffects()
        #expect((try f.exportedUserData()["phrases"] as? [[String: Any]])?.first?["current"] as? String == "測測")
        #expect(engine.coreError == nil)
        #expect(engine.finishCompositionForInputHandoff().text.isEmpty)
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
        let reader = try SharedPhrasePublication(phrasesURL: f.directory.appendingPathComponent("absent.db"), writablePhrases: false)
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

    @Test func frontendTemporaryEnglishModeRemainsIndependentOfRustComposition() throws {
        let f = try Fixture(), engine = try f.facade()
        _ = engine.handleSoftKey("SHIFT")
        #expect(engine.inputMode == .english && engine.isTemporaryEnglish)
        _ = engine.handleSoftKey("MODE")
        #expect(engine.inputMode == .english && !engine.isTemporaryEnglish)
        #expect(engine.handleSoftKey("a").text == "a")
        engine.acknowledgeHostEffects()
        #expect(engine.inputMode == .english)
        _ = engine.toggleHardwareLanguage()
        #expect(engine.handleSoftKey("s").text.isEmpty)
        #expect(engine.readingText == "ㄋ")
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
