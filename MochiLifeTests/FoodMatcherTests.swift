import Foundation
import Testing
@testable import MochiLife

/// FoodMatcher against the bundled Tiki Cat data (read from the app bundle).
struct FoodMatcherTests {
    private struct SeedFile: Decodable {
        struct Product: Decodable {
            struct Serving: Decodable {
                var size: String
                var grams: Double
            }
            var name: String
            var line: String
            var servings: [Serving]
        }
        var brand: String
        var products: [Product]
    }

    /// Items named like saved foods: brand "Tiki Cat", product name without the brand prefix.
    private static let items: [FoodMatcher.Item] = {
        guard let url = Bundle.main.url(forResource: "tiki-cat-wet-food", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(SeedFile.self, from: data)
        else { return [] }
        return file.products.enumerated().map { index, product in
            let prefix = file.brand + " "
            let name = product.name.hasPrefix(prefix) ? String(product.name.dropFirst(prefix.count)) : product.name
            return FoodMatcher.Item(id: index, brand: file.brand, line: product.line, name: name,
                                    sizes: product.servings.map { .init(label: $0.size, grams: $0.grams) })
        }
    }()

    private let matcher = FoodMatcher(items: FoodMatcherTests.items)

    private func name(_ candidate: FoodMatcher.Candidate?) -> String? {
        candidate.flatMap { matcher.item(id: $0.id)?.name }
    }

    @Test func seedDataLoaded() {
        #expect(Self.items.count == 99)
    }

    @Test func exactProductNameIsConfident() {
        let result = matcher.match("Tiki Cat Grill Tuna & Prawn Pâté")
        #expect(result.classification == .confident)
        #expect(name(result.candidates.first) == "Grill Tuna & Prawn Pâté")
    }

    @Test func lineNamePlusRecipeIsConfident() {
        let result = matcher.match("After Dark Chicken & Pork")
        #expect(result.classification == .confident)
        #expect(name(result.candidates.first) == "After Dark Chicken & Pork Recipe in Broth")
    }

    @Test func recipeSharedByShredsAndPateIsAmbiguous() {
        let result = matcher.match("After Dark Turkey & Turkey Liver")
        #expect(result.classification == .ambiguous)
        let offered = Set(matcher.closeCandidates(in: result).compactMap(name))
        #expect(offered.contains("After Dark Pâté Turkey & Turkey Liver Recipe"))
        #expect(offered.contains("After Dark Shreds Turkey & Turkey Liver Recipe in Broth"))
    }

    @Test func oneCharacterOCRErrorStillMatches() {
        let result = matcher.match("Silver Mousse with Salmon & Pumpkln in Broth")
        #expect(result.classification == .confident)
        #expect(name(result.candidates.first) == "Silver Mousse with Salmon & Pumpkin in Broth")
    }

    @Test func unrelatedBrandMatchesNothing() {
        let result = matcher.match("Fancy Feast Gravy Lovers Turkey Feast")
        #expect(result.classification == .none)
    }

    @Test func sizeInTextSelectsTheMatchingSize() {
        let sizes: [FoodMatcher.Item.Size] = [.init(label: "2.8 oz can", grams: 79.4), .init(label: "5.5 oz can", grams: 155.9)]
        #expect(FoodMatcher.sizeIndex(in: "NET WT 5.5 OZ (156g)", sizes: sizes) == 1)
        #expect(FoodMatcher.sizeIndex(in: "79.4 g", sizes: sizes) == 0)
    }
}
