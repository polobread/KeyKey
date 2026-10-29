import Foundation

/// Frontend collection metadata and current selection. The input adapter
/// resolves this selection through Guanyinma's read-only phrase API.
public final class AssociatedPhraseStore: AssociatedPhraseSource {
    public struct Collection: Equatable, Sendable {
        public let source: String
        public let display: String
        public let sortOrder: Int
    }
    private let database: Database
    private var sources: [String] = []
    public var enabledSources: [String] { sources }

    public init(database: Database) { self.database = database }

    public func collections() throws -> [Collection] {
        let statement = try database.prepare(
            "SELECT source, display, sortorder FROM collection_names ORDER BY sortorder, source"
        )
        return statement.allRows(columnCount: 3).map {
            Collection(source: $0[0], display: $0[1], sortOrder: Int($0[2]) ?? 0)
        }
    }
    public func setEnabledSources(_ sources: [String]) { self.sources = sources }

    public func phrases(forHeadCharacter character: String) -> [String] {
        // Selection metadata does not perform model queries itself.
        []
    }
}
