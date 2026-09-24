import Foundation
import SQLite3

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

/// The app writes the shared phrase database. A keyboard without Full Access
/// opens it read-only and writes learning only in its own extension container.
public final class SmartMandarinUserData {
    private var phrases: OpaquePointer? = nil
    private let phrasesURL: URL
    private let learning: OpaquePointer
    private let writablePhrases: Bool

    public init(phrasesURL: URL, learningURL: URL, writablePhrases: Bool) throws {
        self.phrasesURL = phrasesURL
        self.writablePhrases = writablePhrases
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: learningURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        learning = try Self.open(learningURL, writable: true)
        do {
            try Self.execute(learning, "CREATE TABLE IF NOT EXISTS user_bigram_cache ("
                + "qstring TEXT NOT NULL, previous TEXT NOT NULL, current TEXT NOT NULL, "
                + "probability REAL NOT NULL);"
                + "CREATE INDEX IF NOT EXISTS user_bigram_cache_index "
                + "ON user_bigram_cache(qstring);"
                + "CREATE TABLE IF NOT EXISTS user_candidate_override_cache ("
                + "qstring TEXT NOT NULL, current TEXT NOT NULL);"
                + "CREATE INDEX IF NOT EXISTS user_candidate_override_cache_index "
                + "ON user_candidate_override_cache(qstring);")
            if writablePhrases {
                try fileManager.createDirectory(
                    at: phrasesURL.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                phrases = try Self.open(phrasesURL, writable: true)
                try Self.execute(phrases!, "CREATE TABLE IF NOT EXISTS user_unigrams ("
                    + "qstring TEXT NOT NULL, current TEXT NOT NULL, "
                    + "probability REAL NOT NULL, backoff REAL NOT NULL);"
                    + "CREATE INDEX IF NOT EXISTS user_unigrams_index "
                    + "ON user_unigrams(qstring);")
            } else if fileManager.fileExists(atPath: phrasesURL.path) {
                phrases = try Self.open(phrasesURL, writable: false)
            } else {
                phrases = nil
            }
        } catch {
            sqlite3_close_v2(phrases)
            sqlite3_close_v2(learning)
            throw error
        }
    }

    deinit {
        sqlite3_close_v2(phrases)
        sqlite3_close_v2(learning)
    }

    public func unigrams(for query: String) -> [(text: String, probability: Double, backoff: Double)] {
        guard let phrases = phraseHandle() else { return [] }
        return rows(phrases, "SELECT current, probability, backoff FROM user_unigrams "
            + "WHERE qstring = ? ORDER BY probability DESC, rowid", [query]).map {
            ($0[0], Double($0[1]) ?? -1, Double($0[2]) ?? 0)
        }
    }

    public func learnedCandidate(for query: String) -> String? {
        rows(learning, "SELECT current FROM user_candidate_override_cache "
            + "WHERE qstring = ? ORDER BY rowid DESC LIMIT 1", [query]).first?.first
    }

    public func learnedBigram(
        previousQuery: String, query: String, previous: String, current: String
    ) -> Double? {
        rows(learning, "SELECT probability FROM user_bigram_cache WHERE "
            + "qstring = ? AND previous = ? AND current = ? ORDER BY rowid DESC LIMIT 1",
             [previousQuery + " " + query, previous, current]).first?.first.flatMap(Double.init)
    }

    public func learnCandidate(
        query: String, current: String, previousQuery: String? = nil, previous: String? = nil
    ) {
        guard !query.isEmpty, !current.isEmpty else { return }
        do {
            try Self.execute(learning, "BEGIN IMMEDIATE")
            try change(learning, "DELETE FROM user_candidate_override_cache WHERE qstring = ?", [query])
            try change(learning, "INSERT INTO user_candidate_override_cache VALUES (?, ?)",
                       [query, current])
            if let previousQuery, let previous, !previousQuery.isEmpty {
                try learnBigramInTransaction(
                    previousQuery: previousQuery, query: query, previous: previous, current: current
                )
            }
            try Self.execute(learning, "COMMIT")
        } catch {
            try? Self.execute(learning, "ROLLBACK")
        }
    }

    public func learnComposition(_ composition: SmartMandarinComposition) {
        let segments = composition.segments
        guard segments.count > 1 else { return }
        do {
            try Self.execute(learning, "BEGIN IMMEDIATE")
            for index in 1..<segments.count {
                let previous = segments[index - 1]
                let current = segments[index]
                try learnBigramInTransaction(
                    previousQuery: previous.query, query: current.query,
                    previous: previous.text, current: current.text
                )
            }
            try Self.execute(learning, "COMMIT")
        } catch {
            try? Self.execute(learning, "ROLLBACK")
        }
    }

    public func resetLearning() throws {
        try Self.execute(learning, "BEGIN IMMEDIATE")
        do {
            try Self.execute(learning, "DELETE FROM user_bigram_cache;"
                + "DELETE FROM user_candidate_override_cache;")
            try Self.execute(learning, "COMMIT")
        } catch {
            try? Self.execute(learning, "ROLLBACK")
            throw error
        }
    }

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

    public static func query(for reading: String) -> String? {
        let reverse = Dictionary(uniqueKeysWithValues: BopomofoSyllable.glyphs.map { ($0.value, $0.key) })
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
        var result = ""
        for text in syllables {
            var syllable = BopomofoSyllable()
            for glyph in text {
                guard let component = reverse[glyph]
                    ?? StandardBopomofoLayout.componentForKey[Character(glyph.lowercased())]
                else { return nil }
                let mask: UInt16
                if component & BopomofoSyllable.consonantMask != 0 {
                    mask = BopomofoSyllable.consonantMask
                } else if component & BopomofoSyllable.medialMask != 0 {
                    mask = BopomofoSyllable.medialMask
                } else if component & BopomofoSyllable.vowelMask != 0 {
                    mask = BopomofoSyllable.vowelMask
                } else { mask = BopomofoSyllable.toneMask }
                guard syllable.component(in: mask) == 0 else { return nil }
                syllable.add(component)
            }
            guard syllable.component(in: BopomofoSyllable.consonantMask
                | BopomofoSyllable.medialMask | BopomofoSyllable.vowelMask) != 0 else {
                return nil
            }
            result += syllable.absoluteOrderKey
        }
        return result
    }

    public static func reading(for query: String) -> String? {
        let bytes = Array(query.utf8)
        guard !bytes.isEmpty, bytes.count.isMultiple(of: 2) else { return nil }
        var readings: [String] = []
        for offset in stride(from: 0, to: bytes.count, by: 2) {
            let low = Int(bytes[offset]) - 48
            let high = Int(bytes[offset + 1]) - 48
            let order = low + high * 79
            guard (0..<6160).contains(order) else { return nil }
            readings.append(BopomofoSyllable(absoluteOrder: order).composedString)
        }
        return readings.joined(separator: " ")
    }

    private func learnBigramInTransaction(
        previousQuery: String, query: String, previous: String, current: String
    ) throws {
        let combined = previousQuery + " " + query
        try change(learning, "DELETE FROM user_bigram_cache WHERE qstring = ?", [combined])
        try change(learning, "INSERT INTO user_bigram_cache VALUES (?, ?, ?, 0)",
                   [combined, previous, current])
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
