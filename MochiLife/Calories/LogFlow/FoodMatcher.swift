import Foundation

/// Matches typed or recognized text against saved foods. Pure and synchronous over an
/// in-memory index, so it's independently testable and can run on any thread.
///
/// Index: normalized tokens from each food's brand, line and product name. Size labels are kept
/// separately and used to preselect a size, not to identify the product (every "2.8 oz can"
/// would otherwise look alike). Scoring: tokens weighted by inverse document frequency, so
/// distinctive words (a line name) outweigh common ones (chicken, recipe, broth); word order is
/// ignored; tokens at Damerau-Levenshtein distance 1 match at reduced strength when the longer of
/// the two has at least five letters. The score is a cosine-style ratio in 0…1.
struct FoodMatcher: Sendable {
    /// All thresholds in one place, tuned against the bundled Tiki Cat data.
    enum Thresholds {
        /// A confident match needs at least this score…
        static let confidentScore = 0.60
        /// …and must beat the runner-up by at least this much.
        static let confidentMargin = 0.12
        /// Below this, nothing is a plausible match.
        static let plausibleScore = 0.35
        /// A confident match whose lead is smaller than this is checked by the on-device model.
        static let narrowMargin = 0.20
        /// Candidates within this distance of the top are offered when ambiguous.
        static let ambiguousSpread = 0.20
        static let fuzzyMinimumLength = 5
        static let fuzzyStrength = 0.8
        static let candidateLimit = 8
    }

    struct Item: Sendable, Equatable {
        /// The caller's identifier (an index into its own list).
        var id: Int
        var brand: String?
        var line: String?
        var name: String
        var sizes: [Size]

        struct Size: Sendable, Equatable {
            var label: String
            var grams: Double
        }
    }

    enum Classification: String, Sendable, Equatable {
        case confident
        case ambiguous
        case none
    }

    struct Candidate: Sendable, Equatable {
        var id: Int
        /// 0…1.
        var score: Double
    }

    struct Result: Sendable, Equatable {
        /// Best first, at most `Thresholds.candidateLimit`, only plausible ones.
        var candidates: [Candidate]
        var classification: Classification
        /// Top score minus runner-up score (1 when there's only one candidate).
        var margin: Double

        static let empty = Result(candidates: [], classification: .none, margin: 0)

        /// A confident match close enough to the runner-up to be worth a second opinion.
        var isNarrow: Bool { classification == .confident && margin < Thresholds.narrowMargin }
    }

    /// Text with a weight, e.g. a recognized label line weighted by its letter height.
    struct WeightedText: Sendable {
        var text: String
        var weight: Double
    }

    private let items: [Item]
    private let documents: [Set<String>]
    private let documentMass: [Double]
    private let inverseFrequency: [String: Double]
    private let unknownWeight: Double

    init(items: [Item]) {
        self.items = items
        let documents = items.map { Set(Self.tokens([$0.brand, $0.line, $0.name].compactMap { $0 }.joined(separator: " "))) }
        var frequency: [String: Int] = [:]
        for document in documents { for token in document { frequency[token, default: 0] += 1 } }
        let count = Double(max(documents.count, 1))
        let inverse = frequency.mapValues { log((count + 1) / (Double($0) + 0.5)) }
        self.documents = documents
        self.inverseFrequency = inverse
        self.documentMass = documents.map { $0.reduce(0) { $0 + (inverse[$1] ?? 0) } }
        // A query word that appears in no saved food is strong evidence of a different product.
        self.unknownWeight = inverse.values.max() ?? 1
    }

    func match(_ text: String) -> Result {
        match(weighted: [WeightedText(text: text, weight: 1)])
    }

    func match(weighted texts: [WeightedText]) -> Result {
        var queryWeights: [String: Double] = [:]
        for text in texts {
            for token in Self.tokens(text.text) {
                queryWeights[token] = max(queryWeights[token] ?? 0, text.weight)
            }
        }
        guard !queryWeights.isEmpty, !items.isEmpty else { return .empty }

        // Each query token resolves to exact or fuzzy vocabulary tokens with a strength.
        var resolved: [String: [(token: String, strength: Double)]] = [:]
        var queryMass = 0.0
        for (token, weight) in queryWeights {
            if let idf = inverseFrequency[token] {
                resolved[token] = [(token, 1)]
                queryMass += weight * idf
            } else {
                let fuzzy = inverseFrequency.keys.filter { Self.isWithinOneEdit(token, $0) }.map { ($0, Thresholds.fuzzyStrength) }
                if fuzzy.isEmpty {
                    queryMass += weight * unknownWeight
                } else {
                    resolved[token] = fuzzy
                    queryMass += weight * (fuzzy.compactMap { inverseFrequency[$0.0] }.max() ?? 0)
                }
            }
        }
        guard queryMass > 0 else { return .empty }

        var scored: [Candidate] = []
        for (index, document) in documents.enumerated() where documentMass[index] > 0 {
            var matched = 0.0
            for (token, weight) in queryWeights {
                let best = (resolved[token] ?? [])
                    .filter { document.contains($0.token) }
                    .map { $0.strength * (inverseFrequency[$0.token] ?? 0) }
                    .max() ?? 0
                matched += weight * best
            }
            guard matched > 0 else { continue }
            let score = min(1, matched / (queryMass * documentMass[index]).squareRoot())
            scored.append(Candidate(id: items[index].id, score: score))
        }
        scored.sort { $0.score != $1.score ? $0.score > $1.score : $0.id < $1.id }

        let top = scored.first?.score ?? 0
        let runnerUp = scored.dropFirst().first?.score ?? 0
        let margin = scored.count > 1 ? top - runnerUp : (scored.isEmpty ? 0 : 1)
        let classification: Classification
        if top >= Thresholds.confidentScore && margin >= Thresholds.confidentMargin {
            classification = .confident
        } else if top >= Thresholds.plausibleScore {
            classification = .ambiguous
        } else {
            classification = .none
        }
        let plausible = scored.filter { $0.score >= Thresholds.plausibleScore }
        return Result(candidates: Array(plausible.prefix(Thresholds.candidateLimit)),
                      classification: classification, margin: margin)
    }

    /// The candidates to offer when the result is ambiguous: those close to the top (2 or 3).
    func closeCandidates(in result: Result, limit: Int = 3) -> [Candidate] {
        guard let top = result.candidates.first?.score else { return [] }
        let close = result.candidates.filter { top - $0.score <= Thresholds.ambiguousSpread }
        return Array((close.count >= 2 ? close : result.candidates).prefix(limit))
    }

    func item(id: Int) -> Item? { items.first { $0.id == id } }

    // MARK: - Sizes

    /// The index of the size whose weight appears in the text, e.g. "2.8 oz" or "85 g".
    static func sizeIndex(in text: String, sizes: [Item.Size]) -> Int? {
        let normalized = text.lowercased().replacingOccurrences(of: ",", with: ".")
        var grams: [Double] = []
        for match in normalized.matches(of: /(\d+(?:\.\d+)?)\s*(oz|ounces?|g|grams?)\b/) {
            guard let value = Double(match.output.1) else { continue }
            grams.append(match.output.2.hasPrefix("o") ? value * 28.3495 : value)
        }
        guard !grams.isEmpty else { return nil }
        return sizes.firstIndex { size in grams.contains { abs($0 - size.grams) / size.grams < 0.03 } }
    }

    // MARK: - Normalization

    /// Words too common on cat food labels to help identify a product.
    static let stopWords: Set<String> = [
        "a", "an", "the", "of", "in", "with", "and", "for", "cat", "cats", "food", "foods", "net", "wt",
        "oz", "g", "can", "cans", "pouch", "pouches", "complete", "balanced",
    ]

    /// Case-folded, without diacritics, "&" as "and", punctuation removed, whitespace collapsed;
    /// stop words and bare numbers dropped.
    static func tokens(_ text: String) -> [String] {
        normalizedWords(text).filter { !stopWords.contains($0) && !$0.allSatisfy(\.isNumber) }
    }

    static func normalizedWords(_ text: String) -> [String] {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "&", with: " and ")
        var cleaned = ""
        cleaned.reserveCapacity(folded.count)
        for character in folded {
            cleaned.append(character.isLetter || character.isNumber ? character : " ")
        }
        return cleaned.split(separator: " ").map(String.init)
    }

    /// Damerau-Levenshtein distance of at most 1 (one insertion, deletion, substitution or
    /// adjacent swap), when the longer word has at least `fuzzyMinimumLength` letters.
    static func isWithinOneEdit(_ a: String, _ b: String) -> Bool {
        guard a != b, max(a.count, b.count) >= Thresholds.fuzzyMinimumLength, abs(a.count - b.count) <= 1 else {
            return false
        }
        let x = Array(a), y = Array(b)
        if x.count == y.count {
            let differences = x.indices.filter { x[$0] != y[$0] }
            if differences.count == 1 { return true }
            return differences.count == 2 && differences[1] == differences[0] + 1
                && x[differences[0]] == y[differences[1]] && x[differences[1]] == y[differences[0]]
        }
        let (short, long) = x.count < y.count ? (x, y) : (y, x)
        var i = 0, j = 0, skipped = false
        while i < short.count && j < long.count {
            if short[i] == long[j] {
                i += 1; j += 1
            } else {
                if skipped { return false }
                skipped = true
                j += 1
            }
        }
        return true
    }
}
