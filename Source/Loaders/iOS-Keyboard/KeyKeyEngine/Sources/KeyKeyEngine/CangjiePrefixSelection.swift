import Foundation

/// Retains only the best 36 visible values while scanning the indexed range.
struct CangjiePrefixSelection {
    static let limit = 36
    private var seen: Set<String>
    private(set) var values: [String] = []
    init(excluding: [String]) { seen = Set(excluding) }

    static func isPrefixCode(_ code: String) -> Bool {
        (1...4).contains(code.utf8.count) && code.utf8.allSatisfy { (97...122).contains($0) }
    }

    mutating func consider(_ text: String, filter: (String) -> Bool) {
        guard !seen.contains(text), let first = text.unicodeScalars.first,
              !CharacterSet.punctuationCharacters.contains(first),
              !CharacterSet.symbols.contains(first),
              !CharacterSet.whitespacesAndNewlines.contains(first) else { return }
        let rank = CangjieCommonRanking.ranks[text] ?? Int.max
        // A later equal-ranked row cannot displace an earlier one. Avoid
        // probing fonts for candidates that cannot enter the retained set.
        if values.count == Self.limit,
           rank >= (CangjieCommonRanking.ranks[values.last!] ?? Int.max) { return }
        guard filter(text) else { return }
        seen.insert(text)
        let index = values.firstIndex { (CangjieCommonRanking.ranks[$0] ?? Int.max) > rank } ?? values.count
        values.insert(text, at: index)
        if values.count > Self.limit { values.removeLast() }
    }
}
