import Foundation

/// The selected Chinese method is independent of the English/number key plane.
public enum ChineseInputMethod: String, CaseIterable, Sendable {
    case smart, traditional, cangjie, simplex
    public var displayName: String {
        switch self {
        case .smart: "好打注音"
        case .traditional: "傳統注音"
        case .cangjie: "倉頡"
        case .simplex: "簡易"
        }
    }
    public var isTable: Bool { self == .cangjie || self == .simplex }
    public var symbol: String { self == .cangjie ? "倉" : self == .simplex ? "簡" : "ㄅ" }
    public var tableName: String { self == .simplex ? "Generic-simplex-cin" : "Generic-cj-cin" }
    public var maximumCodeLength: Int { self == .simplex ? 2 : 5 }
    public static func root(for key: String) -> String? {
        let names = Array("日月金木水火土竹戈十大中一弓人心手口尸廿山女田難卜重")
        guard key.utf8.count == 1, let byte = key.lowercased().utf8.first,
              byte >= 97, byte <= 122 else { return nil }
        return String(names[Int(byte - 97)])
    }
}

public final class ChineseInputMethodSettings {
    public static let key = "chineseInputMethod"
    private let store: KeyboardPreferenceStore
    public init(defaults: UserDefaults = .standard, sharedDefaults: UserDefaults? = nil,
                writesShared: Bool = false) {
        store = KeyboardPreferenceStore(defaults: defaults, sharedDefaults: sharedDefaults,
                                        writesShared: writesShared)
    }
    public var method: ChineseInputMethod {
        if let raw = store.object(forKey: Self.key) as? String,
           let method = ChineseInputMethod(rawValue: raw) { return method }
        return store.object(forKey: BopomofoCompositionModeSettings.key) as? String == "traditional"
            ? .traditional : .smart
    }
    public func setMethod(_ method: ChineseInputMethod) {
        store.set(method.rawValue, forKey: Self.key)
        if !method.isTable { store.set(method.rawValue, forKey: BopomofoCompositionModeSettings.key) }
    }
    public func options(for method: ChineseInputMethod, virtualKeyboard: Bool = false) -> TableInputOptions {
        var options = TableInputOptions(method: method)
        if let data = store.object(forKey: "tableOptions." + method.rawValue) as? Data,
           let decoded = try? JSONDecoder().decode(TableInputOptions.self, from: data) { options = decoded }
        if method == .cangjie, virtualKeyboard {
            // Missing old data means a new virtual-keyboard installation.
            let legacy = store.object(forKey: "tableOptions." + method.rawValue) as? Data
            options.composeWhileTyping = store.object(forKey: "tablePreview.cangjie.virtual.realtime") as? Bool
                ?? (legacy == nil ? true : options.composeWhileTyping)
            options.prefixCandidates = store.object(forKey: "tablePreview.cangjie.virtual.prefix") as? Bool ?? true
        }
        return options
    }
    public func setOptions(_ options: TableInputOptions, for method: ChineseInputMethod,
                           virtualKeyboard: Bool = false) {
        var shared = options
        if method == .cangjie, !virtualKeyboard,
           store.object(forKey: "tablePreview.cangjie.virtual.realtime") == nil {
            store.set(self.options(for: method, virtualKeyboard: true).composeWhileTyping,
                      forKey: "tablePreview.cangjie.virtual.realtime")
        }
        if method == .cangjie, virtualKeyboard {
            // Freeze the old physical preference before saving shared non-preview options.
            shared.composeWhileTyping = self.options(for: method).composeWhileTyping
            store.set(options.composeWhileTyping, forKey: "tablePreview.cangjie.virtual.realtime")
            store.set(options.prefixCandidates, forKey: "tablePreview.cangjie.virtual.prefix")
        }
        if let data = try? JSONEncoder().encode(shared) {
            store.set(data, forKey: "tableOptions." + method.rawValue)
        }
    }
}

/// Defaults follow macOS OVIMGeneric and TakaoCangjie/TakaoSimplex preferences.
public struct TableInputOptions: Equatable, Codable, Sendable {
    public var queryAtMaximum: Bool
    public var clearOnError: Bool
    public var composeWhileTyping: Bool = false
    public var prefixCandidates: Bool = false
    private enum CodingKeys: String, CodingKey {
        case queryAtMaximum, clearOnError, composeWhileTyping, dynamicFrequency, punctuation
    }
    public var dynamicFrequency: Bool
    /// 0: original CIN punctuation, 1: mixed width, 2: half width (Cangjie).
    public var punctuation: Int = 0
    public init(method: ChineseInputMethod) {
        queryAtMaximum = method == .simplex
        clearOnError = method == .cangjie
        dynamicFrequency = method == .cangjie
    }
}

public protocol TableCandidateSource {
    func values(method: ChineseInputMethod, code: String, punctuation: Int) -> [String]
    func enumeratePrefixValues(code: String, _ body: (String) -> Void)
    func keyName(method: ChineseInputMethod, key: String) -> String?
    func endKeys(method: ChineseInputMethod) -> String
    func learn(code: String, text: String)
    func ordered(_ values: [String], code: String) -> [String]
}

public extension TableCandidateSource {
    func enumeratePrefixValues(code: String, _ body: (String) -> Void) {}
    func learn(code: String, text: String) {}
    func ordered(_ values: [String], code: String) -> [String] { values }
}

/// Prepared lookups over the bundled database; only 128 recent queries are cached.
public final class TableCandidateStore: TableCandidateSource {
    private let database: Database
    private let defaults: UserDefaults
    private var statements: [String: Statement] = [:]
    private var cache: [String: [String]] = [:]
    public init(database: Database, defaults: UserDefaults = .standard) {
        self.database = database
        self.defaults = defaults
    }
    private func rows(table: String, code: String, wildcard: Bool = false) -> [String] {
        let cacheKey = table + ":" + code
        if !wildcard, let cached = cache[cacheKey] { return cached }
        let statementKey = table + (wildcard ? ":wildcard" : ":exact")
        let statement: Statement
        if let existing = statements[statementKey] { statement = existing }
        else {
            // table is selected from fixed enum/override names, never user input.
            guard let prepared = try? database.prepare(
                "SELECT value FROM '\(table)' WHERE key \(wildcard ? "GLOB" : "=") ? ORDER BY rowid"
            ) else { return [] }
            statements[statementKey] = prepared
            statement = prepared
        }
        let pattern = wildcard ? code.replacingOccurrences(of: "[", with: "[[]") : code
        let values = statement.firstColumnStrings([pattern])
        if cache.count >= 128 { cache.removeAll(keepingCapacity: true) }
        if !wildcard, values.count <= 256 { cache[cacheKey] = values }
        return values
    }
    public func values(method: ChineseInputMethod, code: String, punctuation: Int) -> [String] {
        let wildcard = method == .cangjie && code.count > 1 && (code.contains("?") || code.contains("*"))
        if method == .cangjie, punctuation > 0, !wildcard {
            let table = punctuation == 1 ? "Punctuations-cj-mixedwidth-cin" : "Punctuations-cj-halfwidth-cin"
            let override = rows(table: table, code: code)
            if !override.isEmpty { return override }
        }
        return rows(table: method.tableName, code: code, wildcard: wildcard)
    }
    public func enumeratePrefixValues(code: String, _ body: (String) -> Void) {
        guard CangjiePrefixSelection.isPrefixCode(code) else { return }
        let key = "cangjie:prefix"
        let statement: Statement
        if let cached = statements[key] { statement = cached }
        else {
            guard let prepared = try? database.prepare(
                "SELECT value FROM 'Generic-cj-cin' WHERE key GLOB ? "
                + "AND length(key) <= 5 AND key NOT GLOB '*[^a-z]*' ORDER BY rowid"
            ) else { return }
            statements[key] = prepared
            statement = prepared
        }
        statement.forEachFirstColumnString([code + "?*"], body)
    }
    public func keyName(method: ChineseInputMethod, key: String) -> String? {
        rows(table: method.tableName, code: "__property_keyname-" + key).first
    }
    public func endKeys(method: ChineseInputMethod) -> String {
        rows(table: method.tableName, code: "__property_endkey").first ?? ""
    }
    public func learn(code: String, text: String) {
        var counts = defaults.dictionary(forKey: "cangjieOrder." + code) as? [String: Int] ?? [:]
        counts[text] = min((counts[text] ?? 0) + 1, 1_000_000)
        defaults.set(counts, forKey: "cangjieOrder." + code)
    }
    public func ordered(_ values: [String], code: String) -> [String] {
        let counts = defaults.dictionary(forKey: "cangjieOrder." + code) as? [String: Int] ?? [:]
        return values.enumerated().sorted {
            let lhs = counts[$0.element] ?? 0, rhs = counts[$1.element] ?? 0
            return lhs == rhs ? $0.offset < $1.offset : lhs > rhs
        }.map(\.element)
    }
}

public extension TableInputOptions {
    func switches(for method: ChineseInputMethod, virtualKeyboard: Bool = false) -> [(key: String, title: String, enabled: Bool)] {
        var rows = [("realtime", "即時候選", composeWhileTyping),
                    ("clear", virtualKeyboard && method == .cangjie ? "錯碼清除（預覽關閉時）" : "錯碼清除", clearOnError)]
        if method == .cangjie {
            if virtualKeyboard { rows.insert(("prefix", "未打完也能選字", prefixCandidates), at: 1) }
            rows += [("maximum", "滿五碼查詢", queryAtMaximum), ("learning", "依選字紀錄排序", dynamicFrequency)]
        }
        return rows
    }
    mutating func toggle(_ key: String, virtualKeyboard: Bool = false) {
        if virtualKeyboard {
            if key == "realtime" { composeWhileTyping.toggle(); return }
            if key == "clear" { clearOnError.toggle(); return }
        }
        switch key {
        case "realtime": composeWhileTyping.toggle(); if composeWhileTyping { clearOnError = false }
        case "clear": clearOnError.toggle(); if clearOnError { composeWhileTyping = false }
        case "prefix": prefixCandidates.toggle()
        case "maximum": queryAtMaximum.toggle()
        case "learning": dynamicFrequency.toggle()
        default: break
        }
    }
}
