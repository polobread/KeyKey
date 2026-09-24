import Foundation

public struct SmartMandarinSegment: Equatable, Sendable {
    public let start: Int
    public let length: Int
    public let query: String
    public let text: String

    public init(start: Int, length: Int, query: String, text: String) {
        self.start = start
        self.length = length
        self.query = query
        self.text = text
    }
}

public struct SmartMandarinComposition: Equatable, Sendable {
    public let text: String
    public let segments: [SmartMandarinSegment]

    public init(text: String, segments: [SmartMandarinSegment]) {
        self.text = text
        self.segments = segments
    }
}

public protocol SmartMandarinSource {
    func compose(readings: [String], overrides: [Int: String]) -> SmartMandarinComposition?
    func candidates(
        for readings: [String], at index: Int, composition: SmartMandarinComposition?
    ) -> [String]
    func learnSelection(
        readings: [String], at index: Int, selected: String,
        composition: SmartMandarinComposition?
    )
    func learnConfirmedComposition(_ composition: SmartMandarinComposition)
}

public extension SmartMandarinSource {
    func learnSelection(
        readings: [String], at index: Int, selected: String,
        composition: SmartMandarinComposition?
    ) {}
    func learnConfirmedComposition(_ composition: SmartMandarinComposition) {}
}

/// A small, read-only Viterbi walker over the same `unigrams` and `bigrams`
/// tables used by macOS Manjusri. Queries stay lazy and cached so the keyboard
/// extension does not load the complete language model into its limited memory.
public final class SmartMandarinStore: SmartMandarinSource {
    private struct Unigram {
        let text: String
        let probability: Double
        let backoff: Double
    }

    private struct BigramKey: Hashable {
        let previous: String
        let current: String
    }

    private struct Path {
        let score: Double
        let lastProbability: Double
        let lastBackoff: Double
        let segments: [SmartMandarinSegment]
    }

    private let database: Database
    private let userData: SmartMandarinUserData?
    private let unigramStatement: Statement
    private let bigramStatement: Statement
    private var unigramCache: [String: [Unigram]] = [:]
    private var bigramCache: [String: [BigramKey: Double]] = [:]
    private let maximumSpan = 8

    public init(database: Database, userData: SmartMandarinUserData? = nil) throws {
        self.database = database
        self.userData = userData
        unigramStatement = try database.prepare(
            "SELECT current, probability, backoff FROM unigrams "
                + "WHERE qstring = ? ORDER BY probability DESC LIMIT 64"
        )
        bigramStatement = try database.prepare(
            "SELECT previous, current, probability FROM bigrams WHERE qstring = ?"
        )
    }

    public func compose(
        readings: [String], overrides: [Int: String] = [:]
    ) -> SmartMandarinComposition? {
        guard !readings.isEmpty else {
            return SmartMandarinComposition(text: "", segments: [])
        }

        var paths = Array(repeating: [String: Path](), count: readings.count + 1)
        paths[0][""] = Path(score: 0, lastProbability: 0, lastBackoff: 0, segments: [])

        for start in readings.indices where !paths[start].isEmpty {
            let largestSpan = min(maximumSpan, readings.count - start)
            for length in 1...largestSpan {
                let end = start + length
                let query = readings[start..<end].joined()
                let protectedIndices = overrides.keys.filter { start <= $0 && $0 < end }
                if !protectedIndices.isEmpty && !(length == 1 && protectedIndices == [start]) {
                    continue
                }

                var entries = unigrams(for: query)
                let learned = userData?.learnedCandidate(for: query)
                if let required = overrides[start] {
                    entries = entries.filter { $0.text == required }
                }
                guard !entries.isEmpty else { continue }

                for entry in entries {
                    let segment = SmartMandarinSegment(
                        start: start, length: length, query: query, text: entry.text
                    )
                    for previousPath in paths[start].values {
                        let transition: Double
                        if let previous = previousPath.segments.last {
                            transition = bigramProbability(
                                previousQuery: previous.query,
                                currentQuery: query,
                                previousText: previous.text,
                                currentText: entry.text
                            ) ?? (previousPath.lastBackoff + entry.probability)
                        } else {
                            transition = bigramProbability(
                                previousQuery: "!",
                                currentQuery: query,
                                previousText: "",
                                currentText: entry.text
                            ) ?? entry.probability
                        }

                        let learnedTransition = learned == entry.text
                            ? max(transition, 0) : transition
                        let path = Path(
                            score: previousPath.score + learnedTransition,
                            lastProbability: entry.probability,
                            lastBackoff: entry.backoff,
                            segments: previousPath.segments + [segment]
                        )
                        let stateKey = query + "\u{1f}" + entry.text
                        if path.score > (paths[end][stateKey]?.score ?? -.infinity) {
                            paths[end][stateKey] = path
                        }
                    }
                }
            }
        }

        guard let best = paths[readings.count].values.max(by: {
            finalScore($0) < finalScore($1)
        }) else { return nil }
        return SmartMandarinComposition(
            text: best.segments.map(\.text).joined(), segments: best.segments
        )
    }

    public func candidates(
        for readings: [String], at index: Int, composition: SmartMandarinComposition?
    ) -> [String] {
        guard readings.indices.contains(index) else { return [] }
        let query = readings[index]
        let learned = userData?.learnedCandidate(for: query)
        let previous = composition?.segments.last(where: { $0.start + $0.length == index })
        let ranked = unigrams(for: query).map { entry -> (String, Double) in
            let score: Double
            if learned == entry.text {
                score = 0
            } else if let previous {
                score = bigramProbability(
                    previousQuery: previous.query,
                    currentQuery: query,
                    previousText: previous.text,
                    currentText: entry.text
                ) ?? entry.probability
            } else {
                score = bigramProbability(
                    previousQuery: "!", currentQuery: query,
                    previousText: "", currentText: entry.text
                ) ?? entry.probability
            }
            return (entry.text, score)
        }.sorted { $0.1 > $1.1 }

        var seen = Set<String>()
        return ranked.compactMap { seen.insert($0.0).inserted ? $0.0 : nil }
    }

    public func learnSelection(
        readings: [String], at index: Int, selected: String,
        composition: SmartMandarinComposition?
    ) {
        guard readings.indices.contains(index) else { return }
        let previous = composition?.segments.last(where: { $0.start + $0.length == index })
        userData?.learnCandidate(
            query: readings[index], current: selected,
            previousQuery: previous?.query, previous: previous?.text
        )
    }

    public func learnConfirmedComposition(_ composition: SmartMandarinComposition) {
        userData?.learnComposition(composition)
    }

    private func finalScore(_ path: Path) -> Double {
        guard let last = path.segments.last else { return path.score }
        return path.score + (bigramProbability(
            previousQuery: last.query,
            currentQuery: "$",
            previousText: last.text,
            currentText: ""
        ) ?? 0)
    }

    private func unigrams(for query: String) -> [Unigram] {
        let base: [Unigram]
        if let cached = unigramCache[query] {
            base = cached
        } else {
            base = unigramStatement.allRows(
                [query], columnCount: 3
            ).compactMap { row -> Unigram? in
                guard row.count == 3,
                      let probability = Double(row[1]), let backoff = Double(row[2]),
                      !row[0].isEmpty
                else { return nil }
                return Unigram(text: row[0], probability: probability, backoff: backoff)
            }
            unigramCache[query] = base
        }
        let learned = userData?.learnedCandidate(for: query)
        let custom = userData?.unigrams(for: query) ?? []
        var merged: [String: Unigram] = [:]
        for item in base { merged[item.text] = item }
        for item in custom {
            merged[item.text] = Unigram(text: item.text, probability: item.probability,
                                        backoff: item.backoff)
        }
        if let learned, let item = merged[learned] {
            merged[learned] = Unigram(text: learned, probability: 0,
                                      backoff: item.backoff)
        }
        return merged.values.sorted { $0.probability > $1.probability }
    }

    private func bigramProbability(
        previousQuery: String, currentQuery: String,
        previousText: String, currentText: String
    ) -> Double? {
        if let learned = userData?.learnedBigram(
            previousQuery: previousQuery, query: currentQuery,
            previous: previousText, current: currentText
        ) { return learned }
        let query = previousQuery + " " + currentQuery
        let rows: [BigramKey: Double]
        if let cached = bigramCache[query] {
            rows = cached
        } else {
            var loaded: [BigramKey: Double] = [:]
            for row in bigramStatement.allRows([query], columnCount: 3) where row.count == 3 {
                guard let probability = Double(row[2]) else { continue }
                loaded[BigramKey(previous: row[0], current: row[1])] = probability
            }
            bigramCache[query] = loaded
            rows = loaded
        }
        return rows[BigramKey(previous: previousText, current: currentText)]
    }
}
