import Foundation
import SwiftData

/// Loads the food libraries bundled with the app (such as Tiki Cat wet foods) into saved foods.
/// Each library is loaded once only, so relaunching never adds duplicates and foods the user
/// deletes don't come back.
enum FoodLibraryLoader {
    static let bundledLibraries = ["tiki-cat-wet-food"]

    @MainActor
    static func loadBundledLibrariesIfNeeded(into context: ModelContext, defaults: UserDefaults = .standard) {
        for library in bundledLibraries {
            let loadedKey = "loadedFoodLibrary.\(library)"
            guard !defaults.bool(forKey: loadedKey),
                  let url = Bundle.main.url(forResource: library, withExtension: "json")
            else { continue }
            do {
                let file = try JSONDecoder.snakeCase.decode(LibraryFile.self, from: Data(contentsOf: url))
                let existing = try context.fetch(FetchDescriptor<Food>())
                let existingIdentifiers = Set(existing.compactMap(\.libraryIdentifier))
                for product in file.products {
                    let food = product.makeFood(brand: file.brand, library: library)
                    guard let identifier = food.libraryIdentifier,
                          !existingIdentifiers.contains(identifier)
                    else { continue }
                    context.insert(food)
                }
                try context.save()
                defaults.set(true, forKey: loadedKey)
            } catch {
                // Leave the flag unset so loading is tried again on the next launch.
                context.rollback()
                print("Couldn't load food library \(library): \(error)")
            }
        }
    }
}

private extension JSONDecoder {
    static var snakeCase: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

// MARK: - File layout

private struct LibraryFile: Decodable {
    var brand: String
    var products: [Product]
}

private struct Product: Decodable {
    struct PerGram: Decodable {
        var size: String
        var kcalPerG: Double
    }

    struct Serving: Decodable {
        var size: String
        var grams: Double
        var kcal: Double
        var basis: String
    }

    struct Analysis: Decodable {
        var crudeProteinMinPct: Double?
        var crudeFatMinPct: Double?
        var crudeFiberMaxPct: Double?
        var moistureMaxPct: Double?
        var other: [String]
    }

    var name: String
    var line: String
    var type: String
    var calorieStatement: String
    var kcalPerG: [PerGram]
    var ingredients: String
    var guaranteedAnalysis: Analysis
    var notes: [String]
    var sourceUrl: String
    var servings: [Serving]

    func makeFood(brand: String, library: String) -> Food {
        let sizes = servings.map { serving in
            let perGram = kcalPerG.first { $0.size == serving.size }
                ?? kcalPerG.first { $0.size == "all sizes" }
            return FoodSize(
                name: serving.size,
                grams: serving.grams,
                kilocalories: serving.kcal,
                kilocaloriesPerGram: perGram?.kcalPerG ?? serving.kcal / serving.grams,
                isCalculated: serving.basis != "stated on page"
            )
        }
        return Food(
            name: productName(brand: brand),
            kilocaloriesPerGram: sizes.first?.kilocaloriesPerGram ?? kcalPerG.first?.kcalPerG ?? 0,
            brand: brand,
            line: line,
            kind: FoodKind(rawValue: type) ?? .food,
            sizes: sizes,
            calorieStatement: calorieStatement,
            ingredients: ingredients,
            guaranteedAnalysis: analysisRows,
            notes: notes,
            sourceURL: URL(string: sourceUrl),
            libraryIdentifier: "\(library)/\(name)"
        )
    }

    /// "Tiki Cat Grill Tuna & Prawn Pâté" becomes "Grill Tuna & Prawn Pâté".
    private func productName(brand: String) -> String {
        let prefix = brand + " "
        return name.hasPrefix(prefix) ? String(name.dropFirst(prefix.count)) : name
    }

    private var analysisRows: [GuaranteedAnalysisRow] {
        let analysis = guaranteedAnalysis
        let main: [(String, Double?, String)] = [
            ("Crude protein", analysis.crudeProteinMinPct, "min"),
            ("Crude fat", analysis.crudeFatMinPct, "min"),
            ("Crude fiber", analysis.crudeFiberMaxPct, "max"),
            ("Moisture", analysis.moistureMaxPct, "max"),
        ]
        let mainRows = main.compactMap { nutrient, value, limit in
            value.map { GuaranteedAnalysisRow(nutrient: nutrient, amount: "\($0.formatted())% \(limit)") }
        }
        return mainRows + analysis.other.map(Self.analysisRow)
    }

    /// Splits text like "Taurine (min) 0.2%" into "Taurine" and "0.2% min".
    private static func analysisRow(from text: String) -> GuaranteedAnalysisRow {
        let pattern = /^(?<nutrient>.+?)(?: \((?<limit>min|max)\))?(?<dryMatter> DM)? (?<amount>[\d.,]+ ?(?:%|mg\/kg|IU\/kg))$/
        guard let match = text.wholeMatch(of: pattern) else {
            return GuaranteedAnalysisRow(nutrient: text, amount: "")
        }
        var amount = String(match.amount)
        if let limit = match.limit { amount += " \(limit)" }
        if match.dryMatter != nil { amount += " (dry matter)" }
        return GuaranteedAnalysisRow(nutrient: String(match.nutrient), amount: amount)
    }
}
