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

public struct SmartMandarinSelection: Equatable, Sendable {
    public let length: Int
    public let text: String

    public init(length: Int, text: String) {
        self.length = length
        self.text = text
    }
}

public struct SmartMandarinCandidate: Equatable, Sendable {
    public let length: Int
    public let text: String

    public init(length: Int, text: String) {
        self.length = length
        self.text = text
    }
}

public protocol SmartMandarinSource {
    func compose(readings: [String], overrides: [Int: String]) -> SmartMandarinComposition?
    func compose(
        readings: [String], selections: [Int: SmartMandarinSelection]
    ) -> SmartMandarinComposition?
    func candidates(
        for readings: [String], at index: Int, composition: SmartMandarinComposition?
    ) -> [String]
    func candidateOptions(
        for readings: [String], at index: Int, composition: SmartMandarinComposition?
    ) -> [SmartMandarinCandidate]
    func learnSelection(
        readings: [String], at index: Int, selected: String,
        composition: SmartMandarinComposition?
    )
    func learnSelection(
        readings: [String], at index: Int, candidate: SmartMandarinCandidate,
        composition: SmartMandarinComposition?
    )
    func learnConfirmedComposition(_ composition: SmartMandarinComposition)
}

public extension SmartMandarinSource {
    func compose(
        readings: [String], selections: [Int: SmartMandarinSelection]
    ) -> SmartMandarinComposition? {
        guard selections.values.allSatisfy({ $0.length == 1 }) else { return nil }
        return compose(readings: readings, overrides: selections.mapValues(\.text))
    }

    func candidateOptions(
        for readings: [String], at index: Int, composition: SmartMandarinComposition?
    ) -> [SmartMandarinCandidate] {
        candidates(for: readings, at: index, composition: composition).map {
            SmartMandarinCandidate(length: 1, text: $0)
        }
    }

    func learnSelection(
        readings: [String], at index: Int, selected: String,
        composition: SmartMandarinComposition?
    ) {}
    func learnSelection(
        readings: [String], at index: Int, candidate: SmartMandarinCandidate,
        composition: SmartMandarinComposition?
    ) {
        if candidate.length == 1 {
            learnSelection(
                readings: readings, at: index, selected: candidate.text,
                composition: composition
            )
        }
    }
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
        compose(readings: readings, selections: overrides.mapValues {
            SmartMandarinSelection(length: 1, text: $0)
        })
    }

    public func compose(
        readings: [String], selections: [Int: SmartMandarinSelection]
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
                let overlapping = selections.filter { selectedStart, selection in
                    selectedStart < end && start < selectedStart + selection.length
                }
                if !overlapping.isEmpty && !(overlapping.count == 1
                    && overlapping[start]?.length == length) {
                    continue
                }

                var entries = unigrams(for: query)
                let learned = userData?.learnedCandidate(for: query)
                if let required = selections[start] {
                    entries = entries.filter { $0.text == required.text }
                }
                guard !entries.isEmpty else { continue }

                for entry in entries {
                    let segment = SmartMandarinSegment(
                        start: start, length: length, query: query, text: entry.text
                    )
                    for previousPath in paths[start].values {
                        let transition: Double
                        if let previous = previousPath.segments.last {
                            let fallback = previousPath.lastBackoff + entry.probability
                            let observed = bigramProbability(
                                previousQuery: previous.query,
                                currentQuery: query,
                                previousText: previous.text,
                                currentText: entry.text
                            )
                            transition = max(observed ?? fallback, fallback)
                        } else {
                            let observed = bigramProbability(
                                previousQuery: "!",
                                currentQuery: query,
                                previousText: "",
                                currentText: entry.text
                            )
                            transition = max(observed ?? entry.probability, entry.probability)
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

        // For an isolated syllable, match the desktop walker's first choice:
        // the end marker must not rerank the candidate shown to the user.
        guard let best = paths[readings.count].values.max(by: {
            let first = readings.count == 1 ? $0.score : finalScore($0)
            let second = readings.count == 1 ? $1.score : finalScore($1)
            return first < second
        }) else { return nil }
        return SmartMandarinComposition(
            text: best.segments.map(\.text).joined(), segments: best.segments
        )
    }

    public func candidates(
        for readings: [String], at index: Int, composition: SmartMandarinComposition?
    ) -> [String] {
        candidateOptions(for: readings, at: index, composition: composition).map(\.text)
    }

    public func candidateOptions(
        for readings: [String], at index: Int, composition: SmartMandarinComposition?
    ) -> [SmartMandarinCandidate] {
        guard readings.indices.contains(index) else { return [] }
        let previous = composition?.segments.last(where: { $0.start + $0.length == index })
        let previousBackoff = previous.flatMap { segment in
            unigrams(for: segment.query).first(where: { $0.text == segment.text })?.backoff
        } ?? 0
        var ranked: [(SmartMandarinCandidate, Double)] = []
        for length in 1...min(maximumSpan, readings.count - index) {
            let query = readings[index..<(index + length)].joined()
            let learned = userData?.learnedCandidate(for: query)
            for entry in unigrams(for: query) {
                let score: Double
                if learned == entry.text {
                    score = 0
                } else if let previous {
                    let fallback = previousBackoff + entry.probability
                    let observed = bigramProbability(
                        previousQuery: previous.query,
                        currentQuery: query,
                        previousText: previous.text,
                        currentText: entry.text
                    )
                    score = max(observed ?? fallback, fallback)
                } else {
                    let observed = bigramProbability(
                        previousQuery: "!", currentQuery: query,
                        previousText: "", currentText: entry.text
                    )
                    score = max(observed ?? entry.probability, entry.probability)
                }
                ranked.append((SmartMandarinCandidate(length: length, text: entry.text), score))
            }
        }
        ranked.sort { $0.1 > $1.1 }

        var seen = Set<String>()
        return ranked.compactMap { candidate, _ in
            seen.insert("\(candidate.length)\u{1f}\(candidate.text)").inserted
                ? candidate : nil
        }
    }

    public func learnSelection(
        readings: [String], at index: Int, selected: String,
        composition: SmartMandarinComposition?
    ) {
        learnSelection(
            readings: readings, at: index,
            candidate: SmartMandarinCandidate(length: 1, text: selected),
            composition: composition
        )
    }

    public func learnSelection(
        readings: [String], at index: Int, candidate: SmartMandarinCandidate,
        composition: SmartMandarinComposition?
    ) {
        guard readings.indices.contains(index), candidate.length > 0,
              index + candidate.length <= readings.count else { return }
        let previous = composition?.segments.last(where: { $0.start + $0.length == index })
        userData?.learnCandidate(
            query: readings[index..<(index + candidate.length)].joined(),
            current: candidate.text,
            previousQuery: previous?.query, previous: previous?.text
        )
    }

    public func learnConfirmedComposition(_ composition: SmartMandarinComposition) {
        userData?.learnComposition(composition)
    }

    private func finalScore(_ path: Path) -> Double {
        guard let last = path.segments.last else { return path.score }
        let observed = bigramProbability(
            previousQuery: last.query,
            currentQuery: "$",
            previousText: last.text,
            currentText: ""
        )
        return path.score + max(observed ?? path.lastBackoff, path.lastBackoff)
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
