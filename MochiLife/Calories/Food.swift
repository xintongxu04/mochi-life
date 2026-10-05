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
    /// A `FoodKind` raw value ("food" for foods saved before V5 until they're converted).
    var kindRawValue: String = "food"
    /// The cans or pouches the food comes in. Empty for foods measured only in grams.
    var sizes: [FoodSize] = []
    /// The calorie statement exactly as the brand writes it.
    var calorieStatement: String?
    var ingredients: String?
    var guaranteedAnalysis: [GuaranteedAnalysisRow] = []
    var notes: [String] = []
    var sourceURL: URL?
    /// Identifies foods loaded from a bundled food library ("<library>/<original name>" for
    /// foods imported before seed IDs existed). Log entries copy it to find the thumbnail.
    var libraryIdentifier: String?
    /// The bundled food file's stable product id. Nil for foods the owner created.
    @Attribute(.unique) var seedID: String?
    /// True once the owner edits a seeded food, so seed updates leave it alone.
    var isUserModified: Bool = false
    /// Where the food came from (`FoodOrigin`). Nil for foods saved before V3; see `origin`.
    var originRawValue: String?
    /// Key of a photo the app saved for this food ("user/<uuid>", see `FoodThumbnailStore`).
    var thumbnailKey: String?

    init(
        name: String,
        kilocaloriesPerGram: Double,
        brand: String? = nil,
        line: String? = nil,
        kind: FoodKind = .kibble,
        sizes: [FoodSize] = [],
        calorieStatement: String? = nil,
        ingredients: String? = nil,
        guaranteedAnalysis: [GuaranteedAnalysisRow] = [],
        notes: [String] = [],
        sourceURL: URL? = nil,
        libraryIdentifier: String? = nil,
        seedID: String? = nil,
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
        self.seedID = seedID
        self.createdAt = createdAt
    }

    /// No cat food comes close to this; a bigger number almost always means a per-100 g value
    /// was typed as per gram.
    static let maximumKilocaloriesPerGram = 10.0

    static let noBrandTitle = "My foods"
    static let noLineTitle = "Other"

    var kind: FoodKind {
        get { FoodKind.stored(kindRawValue, hasContainerSizes: !sizes.isEmpty) }
        set { kindRawValue = newValue.rawValue }
    }

    /// Where the food came from. Foods saved before this was recorded count as seeded if they
    /// have a seed ID, otherwise as added by hand.
    var origin: FoodOrigin {
        get { originRawValue.flatMap(FoodOrigin.init(rawValue:)) ?? (seedID != nil ? .seed : .manual) }
        set { originRawValue = newValue.rawValue }
    }

    /// The key used to find this food's photo: a photo the app saved, else the bundled photo
    /// for its seed ID or older library identifier. Log entries copy it.
    var photoKey: String? { thumbnailKey ?? seedID ?? libraryIdentifier }

    var brandTitle: String { brand ?? Self.noBrandTitle }

    var formattedKilocaloriesPerGram: String {
        "\(kilocaloriesPerGram.formatted(.number.precision(.fractionLength(2...3)))) kcal/g"
    }
}

/// What kind of food something is. Stored as the raw value in `Food.kindRawValue`,
/// `FoodLogEntry.kindRawValue` and `FeedingSchedule.foodKindRawValue`. Before schema V5 foods
/// used a single "food" kind; that's split into kibble and wet food (`FoodKindBackfill`).
enum FoodKind: String, Codable, CaseIterable, Sendable {
    case kibble
    case wetFood
    case treat
    case supplement
    case topper

    /// The kind every food had before V5, read only to convert it.
    static let legacyFoodRawValue = "food"

    var displayName: String {
        switch self {
        case .kibble: "Kibble"
        case .wetFood: "Wet food"
        case .treat: "Treat"
        case .supplement: "Supplement"
        case .topper: "Topper"
        }
    }

    /// The pixel-art picture shown for items of this kind that have no photo.
    var defaultImageName: String {
        switch self {
        case .kibble: "FoodKind/default_kibble"
        case .wetFood: "FoodKind/default_wet"
        case .treat: "FoodKind/default_treat"
        case .supplement: "FoodKind/default_supplement"
        case .topper: "FoodKind/default_topper"
        }
    }

    /// The rule for anything without a kind yet: food in cans, pouches or other containers is
    /// wet food; food measured only by weight is kibble.
    static func byServing(hasContainerSizes: Bool) -> FoodKind {
        hasContainerSizes ? .wetFood : .kibble
    }

    /// A kind from a stored raw value, converting the old "food" with the serving rule.
    static func stored(_ rawValue: String?, hasContainerSizes: Bool) -> FoodKind {
        rawValue.flatMap(FoodKind.init(rawValue:)) ?? byServing(hasContainerSizes: hasContainerSizes)
    }

    /// A best guess for a food found online: the product's own type if it's a treat,
    /// supplement or topper; then clear words in its name; then dry or wet form; then the
    /// serving rule. The owner can always change it.
    static func guess(type: String?, form: String?, text: String, hasContainerSizes: Bool) -> FoodKind {
        if let type = type.flatMap({ FoodKind(rawValue: $0.lowercased()) }), type != .kibble, type != .wetFood {
            return type
        }
        let words = text.lowercased()
        func mentions(_ terms: [String]) -> Bool { terms.contains { words.contains($0) } }
        if mentions(["treat"]) { return .treat }
        if mentions(["supplement", "vitamin", "probiotic"]) { return .supplement }
        if mentions(["topper", "sprinkle"]) { return .topper }
        if mentions(["kibble", "dry food", "dry cat food"]) || form?.lowercased() == "dry" { return .kibble }
        if mentions(["pâté", "pate", "broth", "mousse", "pouch", " can", "wet"]) || form?.lowercased() == "wet" {
            return .wetFood
        }
        return byServing(hasContainerSizes: hasContainerSizes)
    }
}

enum FoodOrigin: String, CaseIterable {
    /// From a bundled food library.
    case seed
    /// Added by the owner on the Add Food form.
    case manual
    /// Found with "Add with AI" and reviewed by the owner.
    case aiLookup
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

    /// The four standard rows (when known) followed by other lines as written on the label.
    static func rows(proteinMin: Double?, fatMin: Double?, fiberMax: Double?, moistureMax: Double?,
                     other: [String]) -> [GuaranteedAnalysisRow] {
        let main: [(String, Double?, String)] = [
            ("Crude protein", proteinMin, "min"),
            ("Crude fat", fatMin, "min"),
            ("Crude fiber", fiberMax, "max"),
            ("Moisture", moistureMax, "max"),
        ]
        let mainRows = main.compactMap { nutrient, value, limit in
            value.map { GuaranteedAnalysisRow(nutrient: nutrient, amount: "\($0.formatted())% \(limit)") }
        }
        return mainRows + other.map(parse)
    }

    /// Splits text like "Taurine (min) 0.2%" into "Taurine" and "0.2% min".
    static func parse(_ text: String) -> GuaranteedAnalysisRow {
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

extension GuaranteedAnalysisRow {
    static let standardNutrients = ["Crude protein", "Crude fat", "Crude fiber", "Moisture"]

    var isStandard: Bool { Self.standardNutrients.contains(nutrient) }

    /// The percentage of a standard row, e.g. 13 for "13% min".
    var percentValue: Double? {
        amount.firstMatch(of: /^([\d.]+)%/).flatMap { Double($0.output.1) }
    }

    /// The row as one label line, the inverse of `parse`: "Taurine (min) 0.2%".
    var labelLine: String {
        guard !amount.isEmpty else { return nutrient }
        var value = amount
        var limit: String?
        var dryMatter = false
        if value.hasSuffix(" (dry matter)") { dryMatter = true; value = String(value.dropLast(" (dry matter)".count)) }
        if value.hasSuffix(" min") || value.hasSuffix(" max") {
            limit = String(value.suffix(3))
            value = String(value.dropLast(4))
        }
        return "\(nutrient)\(limit.map { " (\($0))" } ?? "")\(dryMatter ? " DM" : "") \(value)"
    }
}

/// Matches foods by normalized brand + line + product name.
enum FoodMatching {
    static func key(brand: String?, line: String?, name: String) -> String {
        [brand ?? "", line ?? "", name].map(normalize).joined(separator: "|")
    }

    /// Lowercased, without accents, with single spaces: "Grill  Tuna & Prawn Pâté" → "grill tuna & prawn pate".
    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

extension Array where Element == Food {
    func sortedByName() -> [Food] {
        sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
