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
        let legacy = (store.object(forKey: "tableOptions." + method.rawValue) as? Data)
            .flatMap { try? JSONDecoder().decode(TableInputOptions.self, from: $0) }
        var options = legacy ?? TableInputOptions(method: method)
        if method == .cangjie {
            if let data = store.object(forKey: "tableOptions.cangjie.shared") as? Data,
               let decoded = try? JSONDecoder().decode(TableInputOptions.self, from: data) {
                options = decoded
            }
            let profile = virtualKeyboard ? "virtual" : "physical"
            // The legacy blob is read-only: changing one profile must not alter
            // the other profile's migration fallback or App Group revision.
            options.composeWhileTyping = store.object(forKey: "tablePreview.cangjie." + profile + ".realtime") as? Bool
                ?? legacy?.composeWhileTyping ?? virtualKeyboard
            options.clearOnError = store.object(forKey: "tablePreview.cangjie." + profile + ".clear") as? Bool
                ?? options.clearOnError
            options.prefixCandidates = store.object(forKey: "tablePreview.cangjie." + profile + ".prefix") as? Bool
                ?? virtualKeyboard
        }
        if options.composeWhileTyping { options.clearOnError = false }
        return options
    }
    public func setOptions(_ options: TableInputOptions, for method: ChineseInputMethod,
                           virtualKeyboard: Bool = false) {
        var options = options
        if options.composeWhileTyping { options.clearOnError = false }
        let key: String
        if method == .cangjie {
            let profile = virtualKeyboard ? "virtual" : "physical"
            store.set(options.composeWhileTyping, forKey: "tablePreview.cangjie." + profile + ".realtime")
            store.set(options.clearOnError, forKey: "tablePreview.cangjie." + profile + ".clear")
            store.set(options.prefixCandidates, forKey: "tablePreview.cangjie." + profile + ".prefix")
            key = "tableOptions.cangjie.shared"
            // Keep the former shared clear value only as a migration fallback.
            // The active choice now lives in each profile's own key.
            options.clearOnError = [key, "tableOptions.cangjie"].compactMap { storedKey in
                (store.object(forKey: storedKey) as? Data)
                    .flatMap { try? JSONDecoder().decode(TableInputOptions.self, from: $0) }
            }.first?.clearOnError ?? TableInputOptions(method: .cangjie).clearOnError
        } else {
            key = "tableOptions." + method.rawValue
        }
        if let data = try? JSONEncoder().encode(options) {
            store.set(data, forKey: key)
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


public extension TableInputOptions {
    func switches(for method: ChineseInputMethod) -> [(key: String, title: String, enabled: Bool)] {
        var rows = [("realtime", "即時候選", composeWhileTyping),
                    ("clear", "錯碼清除", clearOnError)]
        if method == .cangjie {
            rows.insert(("prefix", "未打完也能選字", prefixCandidates), at: 1)
            rows += [("maximum", "滿五碼查詢", queryAtMaximum), ("learning", "依選字紀錄排序", dynamicFrequency)]
        }
        return rows
    }
    mutating func toggle(_ key: String) {
        switch key {
        case "realtime": composeWhileTyping.toggle(); if composeWhileTyping { clearOnError = false }
        case "clear": clearOnError.toggle(); if clearOnError { composeWhileTyping = false }
        case "prefix": if composeWhileTyping { prefixCandidates.toggle() }
        case "maximum": queryAtMaximum.toggle()
        case "learning": dynamicFrequency.toggle()
        default: break
        }
    }
}
