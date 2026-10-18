import Foundation
import Testing
@testable import KeyKeyEngine

@Suite("Virtual Cangjie prefix candidates")
struct CangjiePrefixTests {
    private var root: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<7 { url.deleteLastPathComponent() }
        return url
    }
    private func engine(_ defaults: UserDefaults) throws -> BopomofoEngine {
        let database = try Database(url: root.appendingPathComponent("Source/Distributions/Takao/CookedDatabase/KeyKey.db"))
        let engine = BopomofoEngine(dictionary: try CandidateStore(database: database))
        engine.setTableCandidateSource(TableCandidateStore(database: database, defaults: defaults))
        engine.setChineseInputMethod(.cangjie)
        engine.tableOptions = ChineseInputMethodSettings(defaults: defaults).options(for: .cangjie, virtualKeyboard: true)
        return engine
    }
    private func all(_ engine: BopomofoEngine) -> [String] {
        var result: [String] = []
        for _ in 0..<engine.pageCount {
            result += engine.displayedCandidates
            engine.changePage(by: 1)
        }
        return result
    }

    @Test("Qiao refreshes every root and backspace; a preview never commits on its own")
    func qiao() throws {
        let name = "PrefixQiao." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let engine = try engine(defaults)
        engine.tableOptions.queryAtMaximum = true
        let expectedRoots = ["竹", "竹大", "竹大口", "竹大口月", "竹大口月口"]
        let counts = [38, 40, 11, 2, 1]
        let positions: [Int?] = [nil, 4, 5, 0, 0]
        for (i, key) in Array("hkrbr").enumerated() {
            #expect(engine.handleSoftKey(String(key)).text.isEmpty)
            #expect(engine.readingText == expectedRoots[i])
            let values = all(engine)
            #expect(values.count == counts[i])
            #expect(Set(values).count == values.count)
            #expect(values.firstIndex(of: "喬") == positions[i])
        }
        engine.backspace()
        #expect(engine.readingText == "竹大口月")
        #expect(all(engine) == ["喬", "䀉"])
        engine.backspace()
        #expect(all(engine).firstIndex(of: "喬") == 5)
        #expect(engine.selectDisplayedCandidate(5).text == "喬")
        #expect(defaults.dictionary(forKey: "cangjieOrder.hkr") == nil)
        #expect(engine.readingText.isEmpty)
    }

    @Test("Exact learning stays first; prefix works independently of exact realtime")
    func exactAndWildcard() throws {
        let name = "PrefixExact." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let engine = try engine(defaults)
        engine.tableOptions.composeWhileTyping = false
        engine.handleSoftKey("h"); engine.handleSoftKey("k")
        #expect(engine.displayedCandidates[4] == "喬")
        #expect(engine.selectDisplayedCandidate(4).text == "喬")
        #expect(defaults.dictionary(forKey: "cangjieOrder.hk") == nil)
        defaults.set(["𠆥": 7], forKey: "cangjieOrder.hk")
        engine.handleSoftKey("h"); engine.handleSoftKey("k")
        #expect(engine.displayedCandidates.first == "𠆥")
        #expect(engine.displayedCandidates[4] == "喬")
        engine.escape()
        for key in "hk?" { engine.handleSoftKey(String(key)) }
        let wildcard = all(engine)
        #expect(wildcard.count > 36)
        #expect(!wildcard.contains("喬"))
        engine.tableOptions.prefixCandidates = false
        engine.tableOptions.composeWhileTyping = true
        engine.escape()
        for key in "hk?" { engine.handleSoftKey(String(key)) }
        #expect(all(engine) == wildcard)
    }

    @Test("Ranked values after the first 36 rows displace earlier values; missing glyphs refill")
    func boundedSelection() {
        var selection = CangjiePrefixSelection(excluding: ["是"])
        for i in 0..<100 { selection.consider("候選" + String(i), filter: { _ in true }) }
        selection.consider("的", filter: { _ in true })
        selection.consider("是", filter: { _ in true })
        selection.consider("的", filter: { _ in true })
        #expect(selection.values.count == 36)
        #expect(selection.values.first == "的")
        #expect(!selection.values.contains("是"))
        #expect(selection.values.last == "候選34")
        var visible = CangjiePrefixSelection(excluding: [])
        for i in 0..<40 { visible.consider("缺字" + String(i), filter: { _ in false }) }
        for i in 0..<40 { visible.consider("可見" + String(i), filter: { _ in true }) }
        #expect(visible.values.count == 36)
        #expect(visible.values.first == "可見0")
        #expect(visible.values.last == "可見35")
        var equivalent = CangjiePrefixSelection(excluding: [])
        equivalent.consider("豈", filter: { _ in false })
        equivalent.consider("豈", filter: { _ in true })
        equivalent.consider("豈", filter: { _ in true })
        equivalent.consider("，", filter: { _ in true })
        equivalent.consider("★", filter: { _ in true })
        #expect(equivalent.values == ["豈"])
        #expect(CangjieCommonRanking.ranks.count == 1500)
        #expect(CangjieCommonRanking.ranks["喬"] == 1215)
        #expect(!CangjiePrefixSelection.isPrefixCode("h?"))
        #expect(!CangjiePrefixSelection.isPrefixCode("hkrbr"))
    }

    @Test("Virtual preferences preserve legacy physical options and independent app-group revisions")
    func settings() throws {
        let localName = "PrefixSettings." + UUID().uuidString
        let sharedName = "PrefixShared." + UUID().uuidString
        let local = try #require(UserDefaults(suiteName: localName))
        let shared = try #require(UserDefaults(suiteName: sharedName))
        defer { local.removePersistentDomain(forName: localName); shared.removePersistentDomain(forName: sharedName) }
        let settings = ChineseInputMethodSettings(defaults: local, sharedDefaults: shared)
        #expect(settings.options(for: .cangjie, virtualKeyboard: true).composeWhileTyping)
        #expect(settings.options(for: .cangjie, virtualKeyboard: true).prefixCandidates)
        #expect(!settings.options(for: .cangjie).composeWhileTyping)
        #expect(!settings.options(for: .cangjie).prefixCandidates)
        var hardware = settings.options(for: .cangjie)
        settings.setOptions(hardware, for: .cangjie)
        #expect(settings.options(for: .cangjie, virtualKeyboard: true).composeWhileTyping)
        var virtual = settings.options(for: .cangjie, virtualKeyboard: true)
        virtual.composeWhileTyping = false
        virtual.prefixCandidates = false
        settings.setOptions(virtual, for: .cangjie, virtualKeyboard: true)
        hardware.composeWhileTyping = true
        settings.setOptions(hardware, for: .cangjie)
        #expect(!settings.options(for: .cangjie, virtualKeyboard: true).composeWhileTyping)
        #expect(!settings.options(for: .cangjie, virtualKeyboard: true).prefixCandidates)
        #expect(settings.options(for: .cangjie).composeWhileTyping)
        let app = ChineseInputMethodSettings(defaults: local, sharedDefaults: shared, writesShared: true)
        var appVirtual = app.options(for: .cangjie, virtualKeyboard: true)
        appVirtual.prefixCandidates = true
        app.setOptions(appVirtual, for: .cangjie, virtualKeyboard: true)
        #expect(settings.options(for: .cangjie, virtualKeyboard: true).prefixCandidates)
        // Legacy explicit false remains false on virtual migration; new prefix defaults on.
        let oldName = "PrefixLegacy." + UUID().uuidString
        let old = try #require(UserDefaults(suiteName: oldName))
        defer { old.removePersistentDomain(forName: oldName) }
        old.set(try JSONEncoder().encode(TableInputOptions(method: .cangjie)), forKey: "tableOptions.cangjie")
        let migrated = ChineseInputMethodSettings(defaults: old)
        #expect(!migrated.options(for: .cangjie, virtualKeyboard: true).composeWhileTyping)
        #expect(migrated.options(for: .cangjie, virtualKeyboard: true).prefixCandidates)
        #expect(!migrated.options(for: .simplex, virtualKeyboard: true).composeWhileTyping)
    }
}
