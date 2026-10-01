import Foundation
import Testing
@testable import KeyKeyEngine

@Suite("macOS table input parity")
struct TableInputTests {
    private var root: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<7 { url.deleteLastPathComponent() }
        return url
    }
    private func engine(_ method: ChineseInputMethod, defaults: UserDefaults) throws -> BopomofoEngine {
        let database = try Database(url: root.appendingPathComponent("Source/Distributions/Takao/CookedDatabase/KeyKey.db"))
        let engine = BopomofoEngine(dictionary: try CandidateStore(database: database))
        engine.setTableCandidateSource(TableCandidateStore(database: database, defaults: defaults))
        engine.setChineseInputMethod(method)
        return engine
    }
    @Test("shared golden cases query the real cooked tables")
    func goldenCases() throws {
        let text = try String(contentsOf: root.appendingPathComponent("tests/fixtures/mobile-table-input/cases.tsv"), encoding: .utf8)
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            let suite = "TableInputTests." + UUID().uuidString
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let engine = try engine(try #require(ChineseInputMethod(rawValue: fields[1])), defaults: defaults)
            var committed = ""
            for token in fields[2].split(separator: " ").map(String.init) {
                switch token {
                case "SPACE": committed += engine.space().text
                case "ENTER": committed += engine.enter().text
                case "BACKSPACE": committed += engine.backspace().text
                case "ESCAPE": committed += engine.escape().text
                case "DOWN": engine.moveHighlight(by: 1)
                case "PAGE": engine.changePage(by: 1)
                case "ENGLISH": committed += engine.toggleHardwareLanguage().text
                case "HANDOFF": committed += engine.finishCompositionForInputHandoff().text
                case "SOFT_COMMA": committed += engine.handleSoftKey("，").text
                case "SYMBOL", "EMOJI": committed += engine.handleSoftKey(token).text
                case "REALTIME": engine.tableOptions.composeWhileTyping = true
                default: for key in token { committed += engine.handleHardwareCharacter(key).text }
                }
            }
            #expect(committed == (fields[3] == "-" ? "" : fields[3]), "\(fields[0]): committed")
            #expect(engine.readingText == (fields[4] == "-" ? "" : fields[4]), "\(fields[0]): reading")
            #expect(engine.displayedCandidates.first == (fields[5] == "-" ? nil : fields[5]), "\(fields[0]): candidates")
        }
    }
    @Test("Cangjie learning persists while Simplex keeps original order")
    func learning() throws {
        let suite = "TableLearningTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = try engine(.cangjie, defaults: defaults)
        first.handleHardwareCharacter("a"); first.space()
        #expect(first.selectDisplayedCandidate(1).text == "曰")
        let reopened = try engine(.cangjie, defaults: defaults)
        reopened.handleHardwareCharacter("a"); reopened.space()
        #expect(reopened.displayedCandidates.first == "曰")
        reopened.tableOptions.dynamicFrequency = false
        reopened.escape(); reopened.handleHardwareCharacter("a"); reopened.space()
        #expect(reopened.displayedCandidates.first == "日")
        let simplex = try engine(.simplex, defaults: defaults)
        simplex.handleHardwareCharacter("a"); simplex.space()
        #expect(simplex.displayedCandidates.first == "日")
    }
    @Test("live candidates append roots and backspace refreshes the shorter code")
    func realtime() throws {
        let suite = "TableRealtimeTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let engine = try engine(.cangjie, defaults: defaults)
        engine.tableOptions.composeWhileTyping = true
        engine.handleSoftKey("a")
        #expect(engine.displayedCandidates == ["日", "曰"])
        engine.handleSoftKey("b")
        #expect(engine.readingText == "日月")
        #expect(engine.displayedCandidates.first == "明")
        engine.backspace()
        #expect(engine.readingText == "日")
        #expect(engine.displayedCandidates.first == "日")
    }
    @Test("method settings migrate and keep app-group revision semantics")
    func settings() throws {
        let localName = "TableLocal." + UUID().uuidString, sharedName = "TableShared." + UUID().uuidString
        let local = try #require(UserDefaults(suiteName: localName)), shared = try #require(UserDefaults(suiteName: sharedName))
        defer { local.removePersistentDomain(forName: localName); shared.removePersistentDomain(forName: sharedName) }
        local.set("traditional", forKey: BopomofoCompositionModeSettings.key)
        let keyboard = ChineseInputMethodSettings(defaults: local, sharedDefaults: shared)
        #expect(keyboard.method == .traditional)
        let app = ChineseInputMethodSettings(defaults: local, sharedDefaults: shared, writesShared: true)
        app.setMethod(.cangjie)
        #expect(keyboard.method == .cangjie)
        keyboard.setMethod(.simplex)
        #expect(keyboard.method == .simplex)
        app.setMethod(.smart)
        #expect(keyboard.method == .smart)
    }
}
