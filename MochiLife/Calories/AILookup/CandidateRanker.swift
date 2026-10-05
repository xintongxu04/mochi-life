import Foundation

/// Orders search results before the AI chooses: pages on a host that contains a brand word from
/// the query move up, marketplaces and review/database sites move down. Deterministic: ties keep
/// the search engine's order.
enum CandidateRanker {
    static let keep = 6

    static let demotedHosts = [
        "amazon.", "chewy.", "petco.", "petsmart.", "walmart.", "ebay.", "target.", "costco.",
        "kroger.", "instacart.", "petfooddirect.", "reddit.", "youtube.", "facebook.", "pinterest.",
        "catfooddb.", "catfooddatabase.", "petfoodratings.", "dogfoodadvisor.", "catfoodadvisor.",
        "allaboutcats.", "rover.", "hepper.", "catster.", "reviews.", "trustpilot.", "consumeraffairs.",
    ]

    /// Words too common to identify a brand.
    static let commonWords: Set<String> = [
        "cat", "cats", "kitten", "food", "foods", "wet", "dry", "can", "cans", "canned", "pouch",
        "pate", "recipe", "chicken", "tuna", "salmon", "beef", "turkey", "duck", "fish", "lamb",
        "grain", "free", "adult", "senior", "formula", "flavor", "with", "and", "the", "for",
        "broth", "gravy", "loaf", "minced", "shredded", "oz", "net", "wt", "complete", "natural",
    ]

    static func rank(_ results: [SearchResult], query: String) -> [SearchResult] {
        let tokens = brandTokens(in: query)
        let scored = results.enumerated().map { index, result -> (Int, Int, SearchResult) in
            let host = (result.url.host() ?? "").lowercased()
            let compactHost = host.filter { $0.isLetter || $0.isNumber }
            var score = 0
            if tokens.contains(where: { compactHost.contains($0) }) { score += 10 }
            if demotedHosts.contains(where: { host.contains($0) }) { score -= 10 }
            return (score, index, result)
        }
        return scored
            .sorted { $0.0 != $1.0 ? $0.0 > $1.0 : $0.1 < $1.1 }
            .prefix(keep)
            .map(\.2)
    }

    /// Lowercased letters-and-digits words of at least three characters, accents removed,
    /// minus common food words.
    static func brandTokens(in query: String) -> [String] {
        query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 3 && !commonWords.contains($0) && !$0.allSatisfy(\.isNumber) }
    }
}
