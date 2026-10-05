import Foundation

enum FoodSearch {
    /// True when every typed word appears somewhere in the food's brand, line, or name,
    /// in any order, ignoring capital letters and accents ("tuna pate" finds "Tuna & Prawn Pâté").
    static func matches(_ food: Food, query: String) -> Bool {
        let searchable = fold([food.brand, food.line, food.name].compactMap(\.self).joined(separator: " "))
        let words = fold(query).split(whereSeparator: \.isWhitespace)
        return !words.isEmpty && words.allSatisfy { searchable.contains($0) }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
