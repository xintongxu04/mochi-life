import Foundation
import SwiftData

@Model
final class Food {
    var name: String
    /// For foods with sizes, this is the first size's value; each size also has its own.
    var kilocaloriesPerGram: Double
    var createdAt: Date

    /// Nil for foods the user adds without a brand; these are grouped under "My foods".
    var brand: String?
    var line: String?
    var kindRawValue: String = FoodKind.food.rawValue
    /// The cans or pouches the food comes in. Empty for foods measured only in grams.
    var sizes: [FoodSize] = []
    /// The calorie statement exactly as the brand writes it.
    var calorieStatement: String?
    var ingredients: String?
    var guaranteedAnalysis: [GuaranteedAnalysisRow] = []
    var notes: [String] = []
    var sourceURL: URL?
    /// Identifies foods loaded from a bundled food library, so they're only ever loaded once.
    var libraryIdentifier: String?

    init(
        name: String,
        kilocaloriesPerGram: Double,
        brand: String? = nil,
        line: String? = nil,
        kind: FoodKind = .food,
        sizes: [FoodSize] = [],
        calorieStatement: String? = nil,
        ingredients: String? = nil,
        guaranteedAnalysis: [GuaranteedAnalysisRow] = [],
        notes: [String] = [],
        sourceURL: URL? = nil,
        libraryIdentifier: String? = nil,
        createdAt: Date = .now
    ) {
        self.name = name
        self.kilocaloriesPerGram = kilocaloriesPerGram
        self.brand = brand
        self.line = line
        self.kindRawValue = kind.rawValue
        self.sizes = sizes
        self.calorieStatement = calorieStatement
        self.ingredients = ingredients
        self.guaranteedAnalysis = guaranteedAnalysis
        self.notes = notes
        self.sourceURL = sourceURL
        self.libraryIdentifier = libraryIdentifier
        self.createdAt = createdAt
    }

    /// No cat food comes close to this; a bigger number almost always means a per-100 g value
    /// was typed as per gram.
    static let maximumKilocaloriesPerGram = 10.0

    static let noBrandTitle = "My foods"
    static let noLineTitle = "Other"

    var kind: FoodKind { FoodKind(rawValue: kindRawValue) ?? .food }

    var brandTitle: String { brand ?? Self.noBrandTitle }

    var formattedKilocaloriesPerGram: String {
        "\(kilocaloriesPerGram.formatted(.number.precision(.fractionLength(2...3)))) kcal/g"
    }
}

enum FoodKind: String, CaseIterable {
    case food
    case topper
    case supplement
}

/// One size a food comes in, such as a 5.5 oz can.
struct FoodSize: Codable, Hashable {
    /// As the brand names it, e.g. "5.5 oz can".
    var name: String
    var grams: Double
    /// Calories in one whole can or pouch.
    var kilocalories: Double
    var kilocaloriesPerGram: Double
    /// True when the brand didn't state this size's calories and they were worked out instead.
    var isCalculated: Bool

    /// The kind of container, e.g. "can" or "pouch".
    var containerName: String {
        name.split(separator: " ").last.map(String.init) ?? "can"
    }
}

/// One row of a guaranteed analysis table, e.g. "Crude protein" / "13% min".
struct GuaranteedAnalysisRow: Codable, Hashable {
    var nutrient: String
    var amount: String
}

extension Array where Element == Food {
    func sortedByName() -> [Food] {
        sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
