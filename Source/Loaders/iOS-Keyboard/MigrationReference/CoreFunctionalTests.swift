import Foundation
import Testing

@testable import KeyKeyEngine

private struct MigrationFailure: Error, CustomStringConvertible {
    let description: String
}

private func migrationRequire(_ value: Bool, _ message: String) throws {
    if !value { throw MigrationFailure(description: message) }
}

/// An explicit Rust-migration baseline recorder, excluded from ordinary test runs.
@Suite("Rust migration baseline", .enabled(if:
    ProcessInfo.processInfo.environment["KEYKEY_MIGRATION_BASELINE"] == "1"))
struct CoreFunctionalTests {
    @Test("Record all four input methods, full candidates and persistent selection learning")
    func migrationBaseline() throws {
        let environment = ProcessInfo.processInfo.environment
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<7 { root.deleteLastPathComponent() }
        let fixture = environment["KEYKEY_CORE_FUNCTIONAL_FIXTURE"].map { URL(fileURLWithPath: $0) }
            ?? root.appendingPathComponent("tests/fixtures/core-functional/migration-scenarios.tsv")
        guard let tracePath = environment["KEYKEY_MIGRATION_TRACE"] else {
            throw MigrationFailure(description: "Set KEYKEY_MIGRATION_TRACE to an output JSONL file")
        }
        let traceURL = URL(fileURLWithPath: tracePath)
        let base = environment["KEYKEY_MIGRATION_SCRATCH"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory
        let scratch = base.appendingPathComponent("swift-migration-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        try FileManager.default.createDirectory(at: traceURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data().write(to: traceURL)
        let output = try FileHandle(forWritingTo: traceURL)
        defer { try? output.close() }
        let contents = try String(contentsOf: fixture, encoding: .utf8)
        let model = root.appendingPathComponent("Source/Distributions/Takao/CookedDatabase/KeyKey.db")
        var session: MigrationSession?
        var activeCase = "", initialMethod = "", activeProfile = ""
        var seenCases = Set<String>(), methods = Set<String>(), profiles = Set<String>()
        var caseIndex = 0, step = 0

        for (lineNumber, raw) in contents.components(separatedBy: "\n").enumerated() {
            let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
            if line.isEmpty || line.hasPrefix("#") { continue }
            let fields = line.components(separatedBy: "\t")
            let location = "\(fixture.lastPathComponent):\(lineNumber + 1)"
            try migrationRequire(fields.count == 5, "\(location): expected five TSV columns")
            let name = fields[0], profile = fields[1], method = fields[2]
            let context = "\(location) [\(name), \(fields[3])]"
            try migrationRequire(!name.isEmpty, "\(context): empty case name")
            try migrationRequire(profile == "hardware" || profile == "touch",
                                 "\(context): unknown profile \(profile)")
            guard let parsedMethod = ChineseInputMethod(rawValue: method) else {
                throw MigrationFailure(description: "\(context): unknown method \(method)")
            }
            if name != activeCase {
                try migrationRequire(seenCases.insert(name).inserted, "\(context): noncontiguous case")
                session = nil
                caseIndex += 1
                session = try MigrationSession(
                    model: model, scratch: scratch.appendingPathComponent(String(caseIndex)),
                    method: parsedMethod, profile: profile
                )
                activeCase = name
                initialMethod = method
                activeProfile = profile
                step = 0
            } else {
                try migrationRequire(profile == activeProfile && method == initialMethod,
                                     "\(context): profile or initial method changed within case")
            }
            guard let session else { throw MigrationFailure(description: "\(context): no session") }
            let unsupported = try session.apply(fields[3], argument: fields[4], context: context)
            step += 1
            var snapshot = try session.snapshot()
            snapshot["case"] = name
            snapshot["step"] = step
            snapshot["profile"] = profile
            snapshot["operation"] = fields[3]
            snapshot["argument"] = fields[4]
            if !unsupported.isEmpty { snapshot["unsupported"] = unsupported }
            var data = try JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys])
            data.append(0x0a)
            try output.write(contentsOf: data)
            methods.insert(method)
            profiles.insert(profile)
        }
        session = nil
        try migrationRequire(!seenCases.isEmpty, "Migration fixture is empty")
        try migrationRequire(methods == ["smart", "traditional", "cangjie", "simplex"],
                             "Migration fixture must include all four methods")
        try migrationRequire(profiles == ["hardware", "touch"], "Migration fixture must include both profiles")
    }
}

private struct MigrationConfiguration {
    let layout: BopomofoKeyboardLayout
    let spaceSelects: Bool
    let table: TableInputOptions
    init(method: ChineseInputMethod) {
        layout = .standard
        spaceSelects = false
        table = TableInputOptions(method: method)
    }
    init(engine: BopomofoEngine) {
        layout = engine.keyboardLayout
        spaceSelects = engine.spaceSelectsCandidates
        table = engine.tableOptions
    }
}

private final class MigrationSession {
    private let model: URL
    private let scratch: URL
    private let phrases: URL
    private let learning: URL
    private let suiteName = "RustMigration." + UUID().uuidString
    private var defaults: UserDefaults
    private var userData: SmartMandarinUserData?
    private var engine: BopomofoEngine!
    private let profile: String
    private var committed = ""
    private var configurations: [String: MigrationConfiguration] = [:]

    init(model: URL, scratch: URL, method: ChineseInputMethod, profile: String) throws {
        self.model = model
        self.scratch = scratch
        self.profile = profile
        phrases = scratch.appendingPathComponent("phrases.db")
        learning = scratch.appendingPathComponent("learning.db")
        guard let preferences = UserDefaults(suiteName: suiteName) else {
            throw MigrationFailure(description: "Cannot create isolated preferences")
        }
        defaults = preferences
        defaults.removePersistentDomain(forName: suiteName)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        try open(method: method, layout: .standard, spaceSelects: false, options: nil)
    }

    deinit {
        engine = nil
        userData = nil
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func open(method: ChineseInputMethod, layout: BopomofoKeyboardLayout,
                      spaceSelects: Bool, options: TableInputOptions?) throws {
        userData = try SmartMandarinUserData(phrasesURL: phrases, learningURL: learning,
                                             writablePhrases: true)
        let database = try Database(url: model)
        engine = BopomofoEngine(
            dictionary: try CandidateStore(database: database),
            smartSource: try SmartMandarinStore(database: database, userData: userData),
            compositionMode: method == .smart ? .smart : .traditional,
            hardwareSmartEditing: profile == "hardware", keyboardLayout: layout,
            spaceSelectsCandidates: spaceSelects
        )
        engine.setTableCandidateSource(TableCandidateStore(database: database, defaults: defaults))
        _ = engine.setChineseInputMethod(method)
        if let options { engine.tableOptions = options }
    }

    private func reopen(resetLearning: Bool, context: String) throws {
        try migrationRequire(!engine.hasComposition, "\(context): reopen/reset requires empty composition")
        let method = engine.chineseInputMethod, layout = engine.keyboardLayout
        let space = engine.spaceSelectsCandidates, options = engine.tableOptions
        configurations[method.rawValue] = MigrationConfiguration(engine: engine)
        if resetLearning {
            try userData?.resetLearning()
            defaults.removePersistentDomain(forName: suiteName)
        }
        _ = defaults.synchronize()
        engine = nil
        userData = nil
        guard let reopened = UserDefaults(suiteName: suiteName) else {
            throw MigrationFailure(description: "\(context): cannot reopen preferences")
        }
        defaults = reopened
        try open(method: method, layout: layout, spaceSelects: space, options: options)
    }

    func apply(_ operation: String, argument: String, context: String) throws -> [String] {
        if operation == "REOPEN" || operation == "RESET_LEARNING" {
            try migrationRequire(argument.isEmpty, "\(context): unexpected argument")
            try reopen(resetLearning: operation == "RESET_LEARNING", context: context)
            return []
        }
        switch operation {
        case "TYPE":
            try migrationRequire(argument.unicodeScalars.allSatisfy { $0.isASCII },
                                 "\(context): TYPE requires ASCII keys")
            for key in argument {
                if key == " " { committed += engine.space().text }
                else if profile == "hardware" { committed += engine.handleHardwareCharacter(key).text }
                else { committed += engine.handleSoftKey(String(key)).text }
            }
        case "KEY":
            switch argument {
            case "RETURN": committed += engine.enter().text
            case "BACKSPACE": committed += engine.backspace().text
            case "ESCAPE": committed += engine.escape().text
            case "SPACE": committed += engine.space().text
            case "DOWN":
                if engine.chineseInputMethod == .smart && !engine.isShowingSmartCandidates {
                    committed += engine.openSmartCandidates().text
                } else { engine.moveHighlight(by: 1) }
            case "PAGE_DOWN": engine.changePage(by: 1)
            case "PAGE_UP": engine.changePage(by: -1)
            case "LEFT", "RIGHT", "END":
                guard profile == "hardware", engine.chineseInputMethod == .smart else {
                    return ["KEY:" + argument]
                }
                _ = engine.moveSmartCompositionCursor(by:
                    argument == "LEFT" ? -1 : argument == "RIGHT" ? 1 : Int.max / 2)
            default: throw MigrationFailure(description: "\(context): unknown key \(argument)")
            }
        case "OPEN":
            guard let index = Int(argument), index >= 0 else {
                throw MigrationFailure(description: "\(context): invalid reading index")
            }
            guard engine.chineseInputMethod == .smart else { return ["OPEN"] }
            if profile == "hardware" {
                guard let cursor = engine.smartCompositionCursor else {
                    throw MigrationFailure(description: "\(context): no composition cursor")
                }
                try migrationRequire(index < engine.smartCompositionReadingCount,
                                     "\(context): reading index outside composition")
                try migrationRequire(engine.moveSmartCompositionCursor(by: index - cursor),
                                     "\(context): could not move to reading")
                committed += engine.openSmartCandidates().text
            } else {
                try migrationRequire(engine.selectTouchSmartCell(index), "\(context): could not open touch cell")
            }
        case "SELECT":
            try migrationRequire(!argument.isEmpty, "\(context): empty selection")
            let count = engine.pageCount
            for _ in 0..<count {
                if let index = engine.displayedCandidates.firstIndex(of: argument) {
                    committed += engine.selectDisplayedCandidate(index).text
                    return []
                }
                engine.changePage(by: 1)
            }
            throw MigrationFailure(description: "\(context): candidate \(argument) not found")
        case "METHOD":
            guard let method = ChineseInputMethod(rawValue: argument) else {
                throw MigrationFailure(description: "\(context): unknown method \(argument)")
            }
            configurations[engine.chineseInputMethod.rawValue] = MigrationConfiguration(engine: engine)
            committed += engine.setChineseInputMethod(method).text
            let config = configurations[method.rawValue] ?? MigrationConfiguration(method: method)
            committed += engine.setKeyboardLayout(config.layout).text
            engine.spaceSelectsCandidates = config.spaceSelects
            engine.tableOptions = config.table
        case "OPTION":
            let fields = argument.components(separatedBy: "=")
            try migrationRequire(fields.count == 2, "\(context): OPTION requires key=value")
            let key = fields[0], value = fields[1]
            if key == "layout" {
                guard value == "standard" || value == "hsu" else {
                    throw MigrationFailure(description: "\(context): unknown layout \(value)")
                }
                committed += engine.setKeyboardLayout(value == "hsu" ? .hsu : .standard).text
            } else if key == "punctuation" {
                guard let punctuation = Int(value), (0...2).contains(punctuation) else {
                    throw MigrationFailure(description: "\(context): invalid punctuation mode")
                }
                engine.tableOptions.punctuation = punctuation
            } else {
                try migrationRequire(["realtime", "prefix", "dynamic", "clear_on_error", "space_selects"].contains(key),
                                     "\(context): unknown option \(key)")
                try migrationRequire(value == "true" || value == "false", "\(context): invalid boolean")
                let enabled = value == "true"
                switch key {
                case "realtime": engine.tableOptions.composeWhileTyping = enabled
                case "prefix": engine.tableOptions.prefixCandidates = enabled
                case "dynamic": engine.tableOptions.dynamicFrequency = enabled
                case "clear_on_error": engine.tableOptions.clearOnError = enabled
                case "space_selects": engine.spaceSelectsCandidates = enabled
                default: break
                }
            }
        default: throw MigrationFailure(description: "\(context): unknown operation \(operation)")
        }
        return []
    }

    private func allCandidates() -> [String] {
        let page = engine.page, highlight = engine.highlightedIndex, count = engine.pageCount
        guard count > 0 else { return [] }
        engine.changePage(by: -page)
        var result: [String] = []
        for index in 0..<count {
            result += engine.displayedCandidates
            if index + 1 < count { engine.changePage(by: 1) }
        }
        engine.changePage(by: page - engine.page)
        if highlight > 0 { engine.moveHighlight(by: highlight) }
        return result
    }

    private func rows(_ url: URL, _ sql: String, count: Int) throws -> [[String]] {
        try Database(url: url).prepare(sql).allRows(columnCount: Int32(count))
    }

    private func number(_ string: String) throws -> String {
        guard let value = Double(string), value.isFinite else {
            throw MigrationFailure(description: "Invalid learning probability")
        }
        return String(value)
    }

    private func learningSnapshot() throws -> [String: Any] {
        let overrides = try rows(learning,
            "SELECT qstring, current FROM user_candidate_override_cache ORDER BY qstring, current", count: 2)
        let bigrams = try rows(learning,
            "SELECT qstring, previous, current, probability FROM user_bigram_cache ORDER BY qstring, previous, current",
            count: 4).map { row in [row[0], row[1], row[2], try number(row[3])] }
        let unigrams = try rows(phrases,
            "SELECT qstring, current, probability, backoff FROM user_unigrams ORDER BY qstring, current",
            count: 4).map { row in [row[0], row[1], try number(row[2]), try number(row[3])] }
        var table: [[String]] = []
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix("cangjieOrder.") {
            guard let counts = value as? [String: Int] else {
                throw MigrationFailure(description: "Invalid table learning record")
            }
            let code = String(key.dropFirst("cangjieOrder.".count))
            for (text, count) in counts { table.append([code, text, String(count)]) }
        }
        table.sort { $0.lexicographicallyPrecedes($1) }
        return ["overrides": overrides, "bigrams": bigrams, "unigrams": unigrams, "table": table]
    }

    func snapshot() throws -> [String: Any] {
        let result: [String: Any] = [
            "method": engine.chineseInputMethod.rawValue,
            "committed": committed,
            "composition": engine.composingText,
            "reading": engine.readingText,
            "cursor": engine.composingCaretUTF16Offset,
            "cursor_unit": "utf16",
            "candidates": allCandidates(),
            "page": engine.page,
            "page_size": BopomofoEngine.candidatesPerPage,
            "highlight": engine.highlightedIndex,
            "learning": try learningSnapshot()
        ]
        return result
    }
}
