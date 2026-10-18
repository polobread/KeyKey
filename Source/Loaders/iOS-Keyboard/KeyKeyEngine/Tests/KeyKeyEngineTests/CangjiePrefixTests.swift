import Foundation
import Testing
@testable import KeyKeyEngine

@Suite("Mobile Cangjie prefix candidates")
struct CangjiePrefixTests {
    private var root: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<7 { url.deleteLastPathComponent() }
        return url
    }
    private func engine(_ defaults: UserDefaults, virtualKeyboard: Bool = true) throws -> BopomofoEngine {
        let database = try Database(url: root.appendingPathComponent("Source/Distributions/Takao/CookedDatabase/KeyKey.db"))
        let engine = BopomofoEngine(dictionary: try CandidateStore(database: database), hardwareSmartEditing: !virtualKeyboard)
        engine.setTableCandidateSource(TableCandidateStore(database: database, defaults: defaults))
        engine.setChineseInputMethod(.cangjie)
        engine.tableOptions = ChineseInputMethodSettings(defaults: defaults).options(for: .cangjie, virtualKeyboard: virtualKeyboard)
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

    @Test("Physical previews honor all four option combinations", arguments: [false, true], [false, true])
    func physicalOptions(realtime: Bool, prefix: Bool) throws {
        let name = "PrefixPhysical." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = ChineseInputMethodSettings(defaults: defaults)
        var options = settings.options(for: .cangjie)
        options.composeWhileTyping = realtime
        options.prefixCandidates = prefix
        settings.setOptions(options, for: .cangjie)
        let engine = try engine(defaults, virtualKeyboard: false)
        for key in "hk" { #expect(engine.handleHardwareCharacter(key).text.isEmpty) }
        #expect(engine.readingText == "竹大")
        #expect(engine.displayedCandidates.isEmpty == (!realtime && !prefix))
        #expect(engine.displayedCandidates.contains("喬") == prefix)
        if prefix {
            #expect(engine.displayedCandidates.first == "夭")
            let index = try #require(engine.displayedCandidates.firstIndex(of: "喬"))
            #expect(engine.selectDisplayedCandidate(index).text == "喬")
            #expect(defaults.dictionary(forKey: "cangjieOrder.hk") == nil)
        } else if realtime {
            #expect(engine.space().text == "夭")
            #expect(engine.readingText.isEmpty)
        } else {
            #expect(engine.space().text.isEmpty)
            #expect(!engine.displayedCandidates.isEmpty)
            #expect(!all(engine).contains("喬"))
        }
        #expect(settings.options(for: .cangjie, virtualKeyboard: true).composeWhileTyping)
        #expect(settings.options(for: .cangjie, virtualKeyboard: true).prefixCandidates)
    }

    @Test("Physical roots, paging and backspace refresh without an automatic fifth-root commit")
    func physicalQiao() throws {
        let name = "PrefixPhysicalQiao." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = ChineseInputMethodSettings(defaults: defaults)
        var options = settings.options(for: .cangjie)
        options.prefixCandidates = true
        options.queryAtMaximum = true
        settings.setOptions(options, for: .cangjie)
        let engine = try engine(defaults, virtualKeyboard: false)
        for (index, key) in Array("hkrbr").enumerated() {
            #expect(engine.handleHardwareCharacter(key).text.isEmpty)
            #expect(engine.displayedCandidates.contains("喬") == (index > 0))
            if index == 1 {
                engine.changePage(by: 1)
                #expect(!engine.displayedCandidates.contains("喬"))
            }
        }
        #expect(engine.readingText == "竹大口月口")
        #expect(engine.displayedCandidates == ["喬"])
        engine.backspace()
        #expect(engine.displayedCandidates == ["喬", "䀉"])
        #expect(engine.enter().text == "喬")
        #expect(!engine.hasComposition)
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
        hardware.prefixCandidates = true
        settings.setOptions(hardware, for: .cangjie)
        #expect(!settings.options(for: .cangjie, virtualKeyboard: true).composeWhileTyping)
        #expect(!settings.options(for: .cangjie, virtualKeyboard: true).prefixCandidates)
        #expect(settings.options(for: .cangjie).composeWhileTyping)
        #expect(settings.options(for: .cangjie).prefixCandidates)
        let app = ChineseInputMethodSettings(defaults: local, sharedDefaults: shared, writesShared: true)
        var appVirtual = app.options(for: .cangjie, virtualKeyboard: true)
        appVirtual.prefixCandidates = true
        app.setOptions(appVirtual, for: .cangjie, virtualKeyboard: true)
        #expect(settings.options(for: .cangjie, virtualKeyboard: true).prefixCandidates)
        let reopened = ChineseInputMethodSettings(defaults: local, sharedDefaults: shared)
        #expect(reopened.options(for: .cangjie).prefixCandidates)
        #expect(reopened.options(for: .cangjie).composeWhileTyping)
        var toggled = reopened.options(for: .cangjie)
        toggled.toggle("realtime", preserveClearOnError: true)
        #expect(toggled.clearOnError)
        #expect(toggled.switches(for: .cangjie).contains { $0.key == "prefix" })
        // An App physical edit cannot override an extension-local virtual choice.
        var localVirtual = settings.options(for: .cangjie, virtualKeyboard: true)
        localVirtual.composeWhileTyping = false
        localVirtual.prefixCandidates = false
        settings.setOptions(localVirtual, for: .cangjie, virtualKeyboard: true)
        var appHardware = app.options(for: .cangjie)
        appHardware.composeWhileTyping = false
        appHardware.prefixCandidates = false
        app.setOptions(appHardware, for: .cangjie)
        #expect(!settings.options(for: .cangjie, virtualKeyboard: true).composeWhileTyping)
        #expect(!settings.options(for: .cangjie, virtualKeyboard: true).prefixCandidates)
        // Legacy explicit false remains false on virtual migration; new prefix defaults on.
        let oldName = "PrefixLegacy." + UUID().uuidString
        let old = try #require(UserDefaults(suiteName: oldName))
        defer { old.removePersistentDomain(forName: oldName) }
        old.set(try JSONEncoder().encode(TableInputOptions(method: .cangjie)), forKey: "tableOptions.cangjie")
        let migrated = ChineseInputMethodSettings(defaults: old)
        #expect(!migrated.options(for: .cangjie, virtualKeyboard: true).composeWhileTyping)
        #expect(migrated.options(for: .cangjie, virtualKeyboard: true).prefixCandidates)
        #expect(!migrated.options(for: .simplex, virtualKeyboard: true).composeWhileTyping)
        var legacyEnabled = TableInputOptions(method: .cangjie)
        legacyEnabled.composeWhileTyping = true
        old.set(try JSONEncoder().encode(legacyEnabled), forKey: "tableOptions.cangjie")
        var migratedVirtual = migrated.options(for: .cangjie, virtualKeyboard: true)
        migratedVirtual.composeWhileTyping = false
        migrated.setOptions(migratedVirtual, for: .cangjie, virtualKeyboard: true)
        #expect(migrated.options(for: .cangjie).composeWhileTyping)
    }
}
