import Foundation
import SQLite3
import CGuanyinma

public struct SmartMandarinUserPhrase: Equatable {
    public let id: Int64
    public let text: String
    public let reading: String
}

public struct SmartMandarinPhraseImportResult: Equatable {
    public let imported: Int
    public let skipped: Int
}

public enum SmartMandarinUserDataError: Error, LocalizedError {
    case invalidPhrase
    case duplicatePhrase
    case database(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPhrase: "詞句須為 1 至 8 字，且每個字都要有一組有效注音。"
        case .duplicatePhrase: "這個自訂詞與注音已存在。"
        case .database(let message): "無法儲存詞庫：\(message)"
        }
    }
}

/// App-owned custom-phrase publication. Extensions read snapshots without
/// shared writes; candidate learning and ranking are exclusively in Rust.
public final class SharedPhrasePublication {
    private var phrases: OpaquePointer?
    private let phrasesURL: URL
    private let writablePhrases: Bool

    public init(phrasesURL: URL, writablePhrases: Bool) throws {
        self.phrasesURL = phrasesURL
        self.writablePhrases = writablePhrases
        if writablePhrases {
            try FileManager.default.createDirectory(at: phrasesURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let handle = try Self.open(phrasesURL, writable: true)
            do {
                try Self.execute(handle, "CREATE TABLE IF NOT EXISTS user_unigrams ("
                    + "qstring TEXT NOT NULL, current TEXT NOT NULL, "
                    + "probability REAL NOT NULL, backoff REAL NOT NULL);"
                    + "CREATE INDEX IF NOT EXISTS user_unigrams_index ON user_unigrams(qstring);")
                phrases = handle
            } catch { sqlite3_close_v2(handle); throw error }
        } else if FileManager.default.fileExists(atPath: phrasesURL.path) {
            let handle = try Self.open(phrasesURL, writable: false)
            var statement: OpaquePointer?
            let status = sqlite3_prepare_v2(handle,
                "SELECT qstring,current,probability,backoff FROM user_unigrams WHERE 0", -1, &statement, nil)
            sqlite3_finalize(statement)
            guard status == SQLITE_OK else {
                let message = String(cString: sqlite3_errmsg(handle))
                sqlite3_close_v2(handle)
                throw SmartMandarinUserDataError.database(message)
            }
            phrases = handle
        }
    }
    deinit { sqlite3_close_v2(phrases) }

    public func userPhrases() -> [SmartMandarinUserPhrase] {
        guard let phrases = phraseHandle() else { return [] }
        return rows(phrases, "SELECT rowid, current, qstring FROM user_unigrams ORDER BY rowid", [])
            .compactMap { row in
                guard let id = Int64(row[0]), let reading = Self.reading(for: row[2]) else {
                    return nil
                }
                return SmartMandarinUserPhrase(id: id, text: row[1], reading: reading)
            }
    }

    /// A fresh readonly publication snapshot. Missing publications are distinct
    /// from an intentionally empty table, and read failures never erase a copy.
    func guanyinmaPhraseRows() throws -> [[String: Any]]? {
        guard FileManager.default.fileExists(atPath: phrasesURL.path) else { return nil }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(phrasesURL.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let opened = handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "無法開啟共用自訂詞"
            sqlite3_close_v2(handle)
            throw SmartMandarinUserDataError.database(message)
        }
        defer { sqlite3_close_v2(opened) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(opened,
            "SELECT qstring, current, probability, backoff FROM user_unigrams ORDER BY rowid", -1, &statement, nil) == SQLITE_OK,
              let prepared = statement else {
            sqlite3_finalize(statement)
            throw SmartMandarinUserDataError.database(String(cString: sqlite3_errmsg(opened)))
        }
        defer { sqlite3_finalize(prepared) }
        var result: [[String: Any]] = []
        var status = sqlite3_step(prepared)
        while status == SQLITE_ROW {
            guard sqlite3_column_type(prepared, 0) == SQLITE_TEXT,
                  sqlite3_column_type(prepared, 1) == SQLITE_TEXT,
                  [SQLITE_FLOAT, SQLITE_INTEGER].contains(sqlite3_column_type(prepared, 2)),
                  [SQLITE_FLOAT, SQLITE_INTEGER].contains(sqlite3_column_type(prepared, 3)),
                  let queryBytes = sqlite3_column_text(prepared, 0), let textBytes = sqlite3_column_text(prepared, 1),
                  let query = String(bytes: UnsafeBufferPointer(start: queryBytes, count: Int(sqlite3_column_bytes(prepared, 0))), encoding: .utf8),
                  let text = String(bytes: UnsafeBufferPointer(start: textBytes, count: Int(sqlite3_column_bytes(prepared, 1))), encoding: .utf8) else {
                throw SmartMandarinUserDataError.database("無效的共用自訂詞資料列")
            }
            let probability = sqlite3_column_double(prepared, 2), backoff = sqlite3_column_double(prepared, 3)
            guard probability.isFinite, backoff.isFinite else {
                throw SmartMandarinUserDataError.database("無效的共用自訂詞分數")
            }
            result.append(["qstring": query, "current": text,
                           "probability": probability, "backoff": backoff])
            status = sqlite3_step(prepared)
        }
        guard status == SQLITE_DONE else {
            throw SmartMandarinUserDataError.database(String(cString: sqlite3_errmsg(opened)))
        }
        return result
    }

    public func savePhrase(id: Int64? = nil, text: String, reading: String) throws {
        guard writablePhrases, let phrases else {
            throw SmartMandarinUserDataError.database("自訂詞資料庫為唯讀")
        }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let query = Self.query(for: reading),
              (1...8).contains(text.unicodeScalars.count),
              !text.contains(where: \.isWhitespace),
              text.unicodeScalars.count == query.utf8.count / 2
        else { throw SmartMandarinUserDataError.invalidPhrase }
        let duplicate = rows(phrases, "SELECT rowid FROM user_unigrams WHERE qstring = ? "
            + "AND current = ? LIMIT 1", [query, text]).first?.first.flatMap(Int64.init)
        if let duplicate, duplicate != id { throw SmartMandarinUserDataError.duplicatePhrase }
        if let id {
            try change(phrases, "UPDATE user_unigrams SET qstring = ?, current = ? WHERE rowid = ?",
                       [query, text, String(id)])
        } else {
            try change(phrases, "INSERT INTO user_unigrams VALUES (?, ?, -1.0, 0.0)",
                       [query, text])
        }
    }

    public func deletePhrase(id: Int64) throws {
        guard writablePhrases, let phrases else {
            throw SmartMandarinUserDataError.database("自訂詞資料庫為唯讀")
        }
        try change(phrases, "DELETE FROM user_unigrams WHERE rowid = ?", [String(id)])
    }

    /// The plain phrase section of macOS's MJSR 1.0.0 export format. Its
    /// encrypted automatic-learning block is intentionally not exported.
    public func exportPhrases() -> String {
        guard let phrases = phraseHandle() else { return "MJSR version 1.0.0\n" }
        var lines = ["MJSR version 1.0.0"]
        for row in rows(phrases,
                        "SELECT qstring, current, probability, backoff FROM user_unigrams ORDER BY rowid", []) {
            guard row.count == 4, let reading = Self.reading(for: row[0]) else { continue }
            lines.append("\(row[1])\t\(reading.replacingOccurrences(of: " ", with: ","))\t"
                + "\(row[2])\t\(row[3])")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public func importPhrases(_ contents: String) throws -> SmartMandarinPhraseImportResult {
        guard writablePhrases, let phrases else {
            throw SmartMandarinUserDataError.database("自訂詞資料庫為唯讀")
        }
        let lines = contents.components(separatedBy: .newlines)
        guard lines.first?.contains("MJSR version 1.0.0") == true else {
            throw SmartMandarinUserDataError.database("不是 macOS MJSR 1.0.0 詞庫檔案")
        }
        var imported = 0
        var skipped = 0
        try Self.execute(phrases, "BEGIN IMMEDIATE")
        do {
            for line in lines.dropFirst() {
                if line.contains("<database>") { break }
                if line.isEmpty || line.hasPrefix("#") { continue }
                let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard fields.count >= 2,
                      let query = Self.query(for: fields[1]),
                      (1...8).contains(fields[0].unicodeScalars.count),
                      !fields[0].contains(where: \.isWhitespace),
                      fields[0].unicodeScalars.count == query.utf8.count / 2,
                      rows(phrases, "SELECT 1 FROM user_unigrams WHERE qstring = ? "
                        + "AND current = ? LIMIT 1", [query, fields[0]]).isEmpty
                else { skipped += 1; continue }
                let importedProbability = fields.count > 2 ? Double(fields[2]) : nil
                let importedBackoff = fields.count > 3 ? Double(fields[3]) : nil
                let probability = importedProbability?.isFinite == true ? importedProbability! : -1
                let backoff = importedBackoff?.isFinite == true ? importedBackoff! : 0
                try change(phrases, "INSERT INTO user_unigrams VALUES (?, ?, ?, ?)",
                           [query, fields[0], String(probability), String(backoff)])
                imported += 1
            }
            try Self.execute(phrases, "COMMIT")
        } catch {
            try? Self.execute(phrases, "ROLLBACK")
            throw error
        }
        return SmartMandarinPhraseImportResult(imported: imported, skipped: skipped)
    }

    /// Normalize the phrase editor's key/separator spelling; Rust validates
    /// components and encodes the shared model query. This is not an input buffer.
    public static func query(for reading: String) -> String? {
        let syllables = reading.split { $0.isWhitespace || $0 == "," || $0 == "，" }
            .flatMap { part -> [String] in
                var pieces: [String] = []
                var current = ""
                for glyph in part {
                    current.append(glyph)
                    if "6347ˊˇˋ˙".contains(glyph), current.count > 1 {
                        pieces.append(current)
                        current = ""
                    }
                }
                if !current.isEmpty { pieces.append(current) }
                return pieces
            }
        guard (1...8).contains(syllables.count) else { return nil }
        let normalized = syllables.map { text in
            String(text.map { StandardBopomofoLayout.glyph(for: Character($0.lowercased())) ?? $0 })
        }.joined(separator: ",")
        return codec(["operation": "encode", "reading": normalized,
                      "options": ["components": "unique_known", "empty": "reject", "require_phonetic": true]])?["qstring"] as? String
    }

    public static func reading(for query: String) -> String? {
        guard !query.isEmpty else { return nil }
        return codec(["operation": "decode", "qstring": query,
                      "options": ["separator": "space", "query": "canonical"]])?["reading"] as? String
    }

    private static func codec(_ request: [String: Any]) -> [String: Any]? {
        guard let data = try? JSONSerialization.data(withJSONObject: request) else { return nil }
        var result: OpaquePointer?
        defer { guanyinma_result_close(&result) }
        let status = data.withUnsafeBytes { bytes in
            guanyinma_reading_codec(bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count, &result)
        }
        guard status == 0 else { return nil }
        var count = 0
        guard guanyinma_result_json(result, nil, 0, &count) == 5, count > 0, count <= 65536 else { return nil }
        var bytes = [UInt8](repeating: 0, count: count)
        let capacity = bytes.count
        guard guanyinma_result_json(result, &bytes, capacity, &count) == 0,
              count == capacity, bytes.last == 0,
              let value = try? JSONSerialization.jsonObject(with: Data(bytes.dropLast())) as? [String: Any],
              value["schema_version"] as? Int == 1, value["kind"] as? String == "reading_codec" else { return nil }
        return value
    }

    private func phraseHandle() -> OpaquePointer? {
        if let phrases { return phrases }
        guard !writablePhrases, FileManager.default.fileExists(atPath: phrasesURL.path) else {
            return nil
        }
        phrases = try? Self.open(phrasesURL, writable: false)
        return phrases
    }

    private static func open(_ url: URL, writable: Bool) throws -> OpaquePointer {
        var handle: OpaquePointer?
        let flags = writable ? SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE : SQLITE_OPEN_READONLY
        let result = sqlite3_open_v2(url.path, &handle, flags | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite \(result)"
            sqlite3_close_v2(handle)
            throw SmartMandarinUserDataError.database(message)
        }
        sqlite3_busy_timeout(handle, 1000)
        return handle
    }

    private static func execute(_ database: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw SmartMandarinUserDataError.database(String(cString: sqlite3_errmsg(database)))
        }
    }

    private func rows(_ database: OpaquePointer, _ sql: String, _ values: [String]) -> [[String]] {
        guard let statement = prepared(database, sql, values) else { return [] }
        defer { sqlite3_finalize(statement) }
        var result: [[String]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            result.append((0..<sqlite3_column_count(statement)).map { index in
                sqlite3_column_text(statement, index).map { String(cString: $0) } ?? ""
            })
        }
        return result
    }

    private func change(_ database: OpaquePointer, _ sql: String, _ values: [String]) throws {
        guard let statement = prepared(database, sql, values) else {
            throw SmartMandarinUserDataError.database(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SmartMandarinUserDataError.database(String(cString: sqlite3_errmsg(database)))
        }
    }

    private func prepared(_ database: OpaquePointer, _ sql: String, _ values: [String]) -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            sqlite3_finalize(statement)
            return nil
        }
        for (index, value) in values.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), value, -1, sqliteTransient)
        }
        return statement
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
