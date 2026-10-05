import Foundation
import SwiftData

/// Keeps the food libraries bundled with the app (such as Tiki Cat wet foods) in saved foods.
///
/// Each bundled file has a `data_version` and a stable `id` per product. When the bundled
/// version is newer than the one last imported, an upsert keyed on `Food.seedID` runs:
/// products not present are inserted, seeded foods the owner hasn't edited are updated, and
/// foods the owner edited or created are left alone. Nothing is ever deleted, and seeded foods
/// the owner deleted are not added back. Food log entries are snapshots and never touched.
@MainActor
enum FoodLibraryLoader {
    static let bundledLibraries = ["tiki-cat-wet-food"]
    /// Seed IDs of seeded foods the owner deleted, so updates don't bring them back.
    static let deletedSeedIDsKey = "deletedSeedIDs"

    static func updateBundledLibraries(in context: ModelContext, defaults: UserDefaults = .standard) {
        for library in bundledLibraries {
            guard let url = Bundle.main.url(forResource: library, withExtension: "json") else { continue }
            let file: LibraryFile
            do {
                file = try JSONDecoder.snakeCase.decode(LibraryFile.self, from: Data(contentsOf: url))
            } catch {
                Persistence.logger.error("Couldn't read food library \(library, privacy: .public): \(error.localizedDescription, privacy: .public)")
                continue
            }
            let versionKey = "foodLibraryVersion.\(library)"
            var importedVersion = defaults.integer(forKey: versionKey)
            // Installs from before versioning only recorded that version 1 had been loaded.
            if importedVersion == 0 && defaults.bool(forKey: "loadedFoodLibrary.\(library)") {
                importedVersion = 1
            }

            let foods = (try? context.fetch(FetchDescriptor<Food>())) ?? []
            let backfilled = backfillSeedIDs(foods, from: file, library: library)
            guard file.dataVersion > importedVersion else {
                if backfilled { Persistence.save(context) }
                continue
            }

            let deleted = Set(defaults.stringArray(forKey: deletedSeedIDsKey) ?? [])
            let bySeedID = Dictionary(foods.compactMap { food in food.seedID.map { ($0, food) } }) { first, _ in first }
            var inserted = 0
            var updated = 0
            for product in file.products where !deleted.contains(product.id) {
                if let food = bySeedID[product.id] {
                    guard !food.isUserModified else { continue }
                    product.apply(to: food, brand: file.brand)
                    updated += 1
                } else {
                    let food = Food(name: "", kilocaloriesPerGram: 0)
                    product.apply(to: food, brand: file.brand)
                    food.seedID = product.id
                    food.origin = .seed
                    food.libraryIdentifier = "\(library)/\(product.name)"
                    context.insert(food)
                    inserted += 1
                }
            }
            if Persistence.save(context) {
                defaults.set(file.dataVersion, forKey: versionKey)
                Persistence.logger.notice("Food library \(library, privacy: .public) v\(file.dataVersion): \(inserted) added, \(updated) updated")
            }
        }
    }

    /// Records that the owner deleted these foods, so seed updates don't add them back.
    static func rememberDeletion(of foods: [Food], defaults: UserDefaults = .standard) {
        let seedIDs = foods.compactMap(\.seedID)
        guard !seedIDs.isEmpty else { return }
        let existing = defaults.stringArray(forKey: deletedSeedIDsKey) ?? []
        defaults.set(Array(Set(existing + seedIDs)).sorted(), forKey: deletedSeedIDsKey)
    }

    /// Gives seed IDs to foods imported before seed IDs existed, matching them to bundled
    /// products by normalized brand + line + product name (or by the original product name
    /// they were imported with). Returns true if anything changed. Safe to run every launch.
    private static func backfillSeedIDs(_ foods: [Food], from file: LibraryFile, library: String) -> Bool {
        let unmatched = foods.filter { $0.seedID == nil && $0.libraryIdentifier?.hasPrefix("\(library)/") == true }
        guard !unmatched.isEmpty else { return false }
        var taken = Set(foods.compactMap(\.seedID))
        var byKey: [String: String] = [:]
        var byOriginalName: [String: String] = [:]
        for product in file.products {
            byKey[matchKey(brand: file.brand, line: product.line, name: product.productName(brand: file.brand))] = product.id
            byOriginalName[normalize(product.name)] = product.id
        }
        var changed = false
        for food in unmatched {
            let originalName = food.libraryIdentifier.map { String($0.dropFirst(library.count + 1)) } ?? ""
            let candidate = byKey[matchKey(brand: food.brand, line: food.line, name: food.name)]
                ?? byOriginalName[normalize(originalName)]
            guard let seedID = candidate, !taken.contains(seedID) else {
                Persistence.logger.notice("No bundled product matches saved food \(food.name, privacy: .public)")
                continue
            }
            food.seedID = seedID
            taken.insert(seedID)
            changed = true
        }
        return changed
    }

    private static func matchKey(brand: String?, line: String?, name: String) -> String {
        FoodMatching.key(brand: brand, line: line, name: name)
    }

    private static func normalize(_ text: String) -> String {
        FoodMatching.normalize(text)
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
    var dataVersion: Int
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

    var id: String
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

    /// Copies this product's details onto a saved food (not its seed ID or library identifier).
    func apply(to food: Food, brand: String) {
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
        food.name = productName(brand: brand)
        food.kilocaloriesPerGram = sizes.first?.kilocaloriesPerGram ?? kcalPerG.first?.kcalPerG ?? 0
        food.brand = brand
        food.line = line
        food.kindRawValue = (FoodKind(rawValue: type) ?? .food).rawValue
        food.sizes = sizes
        food.calorieStatement = calorieStatement
        food.ingredients = ingredients
        food.guaranteedAnalysis = analysisRows
        food.notes = notes
        food.sourceURL = URL(string: sourceUrl)
    }

    /// "Tiki Cat Grill Tuna & Prawn Pâté" becomes "Grill Tuna & Prawn Pâté".
    func productName(brand: String) -> String {
        let prefix = brand + " "
        return name.hasPrefix(prefix) ? String(name.dropFirst(prefix.count)) : name
    }

    private var analysisRows: [GuaranteedAnalysisRow] {
        let analysis = guaranteedAnalysis
        return GuaranteedAnalysisRow.rows(
            proteinMin: analysis.crudeProteinMinPct, fatMin: analysis.crudeFatMinPct,
            fiberMax: analysis.crudeFiberMaxPct, moistureMax: analysis.moistureMaxPct, other: analysis.other
        )
    }
}
