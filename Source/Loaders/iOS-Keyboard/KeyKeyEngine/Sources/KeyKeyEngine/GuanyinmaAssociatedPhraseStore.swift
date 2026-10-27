// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
import Foundation
import CGuanyinma

/// Read-only transport to Guanyinma's associated-phrase queries. The frontend
/// supplies the enabled collection order and retains candidate/keyboard state.
public final class GuanyinmaAssociatedPhraseStore: AssociatedPhraseSource {
    public struct Collection: Decodable, Equatable, Sendable {
        public let source: String
        public let display: String
        public let sortOrder: Int
    }
    private struct Snapshot<Row: Decodable>: Decodable {
        let schemaVersion: Int
        let kind: String
        let rows: [Row]
    }
    private var database: OpaquePointer?
    private let enabledSources: () -> [String]
    public private(set) var lastError: Error?

    /// The selection is read for every query, so a preferences change does not
    /// require reopening the independent read-only model connection.
    public init(modelURL: URL, enabledSources: @escaping () -> [String]) throws {
        self.enabledSources = enabledSources
        let path = Array(modelURL.path.utf8)
        let status = path.withUnsafeBufferPointer {
            guanyinma_database_open($0.baseAddress, $0.count, &database)
        }
        guard status == 0, database != nil else { throw Self.failure(status) }
    }
    deinit { guanyinma_database_close(&database) }

    /// Names use the common source order; the settings UI may retain its own
    /// display order without affecting the caller's query priority.
    public func collections() throws -> [Collection] {
        try query(["order": "source"], kind: "associated_collections",
                  operation: guanyinma_database_associated_collections)
    }

    public func phrases(forHeadCharacter character: String) -> [String] {
        guard !character.isEmpty else { lastError = nil; return [] }
        do {
            let values: [String] = try query(
                ["head": character, "collections": enabledSources(), "omit_empty_suffixes": true],
                kind: "associated_phrases", operation: guanyinma_database_associated_phrases)
            lastError = nil
            return values
        } catch {
            lastError = error
            return []
        }
    }

    private func query<Row: Decodable>(
        _ request: [String: Any], kind: String,
        operation: (OpaquePointer?, UnsafePointer<UInt8>?, Int, UnsafeMutablePointer<OpaquePointer?>?) -> Int32
    ) throws -> [Row] {
        let data = try JSONSerialization.data(withJSONObject: request)
        var result: OpaquePointer?
        defer { guanyinma_result_close(&result) }
        let status = data.withUnsafeBytes { bytes in
            operation(database, bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count, &result)
        }
        guard status == 0 else { throw Self.failure(status) }
        var required = 0
        let probe = guanyinma_result_json(result, nil, 0, &required)
        guard probe == 5, required > 0, required <= 32 * 1024 * 1024 else { throw Self.failure(probe) }
        var bytes = [UInt8](repeating: 0, count: required)
        let capacity = bytes.count
        let copy = guanyinma_result_json(result, &bytes, capacity, &required)
        guard copy == 0, required == capacity, bytes.last == 0 else { throw Self.failure(copy) }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let snapshot = try decoder.decode(Snapshot<Row>.self, from: Data(bytes.dropLast()))
        guard snapshot.schemaVersion == 1, snapshot.kind == kind else {
            throw GuanyinmaInputError(message: "不支援的 Guanyinma 關聯詞結果。")
        }
        return snapshot.rows
    }

    private static func failure(_ status: Int32) -> GuanyinmaInputError {
        var required = 0
        _ = guanyinma_last_error(nil, 0, &required)
        var bytes = [UInt8](repeating: 0, count: max(required, 1))
        let capacity = bytes.count
        _ = guanyinma_last_error(&bytes, capacity, &required)
        let message = String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        return GuanyinmaInputError(message: message.isEmpty ? "Guanyinma 錯誤 \(status)" : message)
    }
}
