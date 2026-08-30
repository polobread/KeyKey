import Foundation

/// Character candidates and punctuation, both read from `Mandarin-bpmf-cin`.
///
/// The desktop cookers put the `_punctuation_*` and `_ctrl_*` rows in the same
/// table as the syllables, and `OVIMTraditionalMandarin` relies on that (its
/// `Punctuations-punctuation*` wildcard matches nothing, so it falls back to the
/// Bopomofo table). Row order is candidate priority and must be preserved.
public final class CandidateStore {
    private let byKey: Statement

    public init(database: Database) throws {
        byKey = try database.prepare(
            "SELECT value FROM 'Mandarin-bpmf-cin' WHERE key = ? ORDER BY rowid"
        )
    }

    /// Candidates for a composed reading.
    public func candidates(for reading: BopomofoReading) -> [String] {
        guard !reading.isEmpty else { return [] }
        return byKey.firstColumnStrings([reading.queryKey])
    }

    /// Candidates for one of the table's named keys, e.g. `_punctuation_[`.
    public func values(forNamedKey key: String) -> [String] {
        byKey.firstColumnStrings([key])
    }
}

/// Associated phrases, offered after a single Chinese character is committed.
///
/// `associated_phrases.data` is a comma-joined list of suffixes already sorted
/// by frequency at cook time, so unlike the Android port there is no runtime
/// frequency threshold to apply.
public final class AssociatedPhraseStore {
    public struct Collection: Equatable, Sendable {
        public let source: String
        public let display: String
        public let sortOrder: Int
    }

    private let database: Database
    private var byHeadCharacter: [String: Statement] = [:]
    private var sources: [String] = []

    public init(database: Database) {
        self.database = database
    }

    /// Every collection in the database, base collection first. Drives the
    /// settings list, so no separate name asset is needed.
    public func collections() throws -> [Collection] {
        let statement = try database.prepare(
            "SELECT source, display, sortorder FROM collection_names "
                + "ORDER BY sortorder, source"
        )
        return statement.allRows(columnCount: 3).map {
            Collection(source: $0[0], display: $0[1], sortOrder: Int($0[2]) ?? 0)
        }
    }

    /// Limits later lookups to the given collections. An empty set means the
    /// user turned everything off, which yields no phrases at all.
    public func setEnabledSources(_ sources: [String]) {
        self.sources = sources
        byHeadCharacter.removeAll()
    }

    public func phrases(forHeadCharacter character: String) -> [String] {
        guard !sources.isEmpty, !character.isEmpty else { return [] }

        let statement: Statement
        if let cached = byHeadCharacter[cacheKey] {
            statement = cached
        } else {
            let placeholders = Array(repeating: "?", count: sources.count).joined(separator: ", ")
            guard let prepared = try? database.prepare(
                "SELECT data, source FROM associated_phrases WHERE headchar = ? "
                    + "AND source IN (\(placeholders))"
            ) else { return [] }
            byHeadCharacter[cacheKey] = prepared
            statement = prepared
        }

        var rowsBySource: [String: String] = [:]
        for row in statement.allRows([character] + sources, columnCount: 2) {
            rowsBySource[row[1]] = row[0]
        }

        var seen = Set<String>()
        var result: [String] = []
        for source in sources {
            guard let row = rowsBySource[source] else { continue }
            for suffix in row.split(separator: ",", omittingEmptySubsequences: true) {
                let phrase = String(suffix)
                if seen.insert(phrase).inserted {
                    result.append(phrase)
                }
            }
        }
        return result
    }

    /// One prepared statement per enabled-source arity; the set only changes
    /// when the user edits settings.
    private var cacheKey: String { String(sources.count) }
}
