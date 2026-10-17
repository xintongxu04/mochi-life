import Foundation
import SwiftData
import Testing
@testable import MochiLife

/// Saved Foods when the fold splits the screen: picking a brand in the brands pane gives the
/// products pane exactly that brand's foods, grouped by line.
@MainActor
struct BrandCatalogTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() throws {
        container = try ModelContainer(for: Schema(versionedSchema: SchemaV6.self),
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @discardableResult
    private func food(_ name: String, brand: String?, line: String?) -> Food {
        let food = Food(name: name, kilocaloriesPerGram: 1, brand: brand, line: line, seedID: nil, createdAt: .now)
        context.insert(food)
        return food
    }

    private func catalog() throws -> BrandCatalog {
        BrandCatalog(foods: try context.fetch(FetchDescriptor<Food>()))
    }

    private func names(_ lines: [(line: String?, foods: [Food])]) -> [String] {
        lines.flatMap { $0.foods.map(\.name) }
    }

    @Test func pickingABrandShowsItsProductsByLine() throws {
        food("Grill Tuna", brand: "Tiki Cat", line: "Grill")
        food("After Dark Chicken", brand: "Tiki Cat", line: "After Dark")
        food("Plain Chicken", brand: "Tiki Cat", line: nil)
        food("Salmon Pâté", brand: "Other Brand", line: "Pâté")
        food("Home Kibble", brand: nil, line: nil)
        let catalog = try catalog()

        // Brands alphabetical, "My foods" (no brand) last.
        #expect(catalog.brands.map(\.brand) == ["Other Brand", "Tiki Cat", nil])

        let picked = catalog.current(selected: BrandSelection(brand: "Tiki Cat"))
        #expect(picked == BrandSelection(brand: "Tiki Cat"))
        let lines = catalog.lines(for: picked?.brand)
        // Only that brand's foods, lines alphabetical, foods without a line last.
        #expect(lines.map(\.line) == ["After Dark", "Grill", nil])
        #expect(names(lines) == ["After Dark Chicken", "Grill Tuna", "Plain Chicken"])

        // Picking another brand replaces them.
        let other = catalog.lines(for: catalog.current(selected: BrandSelection(brand: "Other Brand"))?.brand)
        #expect(names(other) == ["Salmon Pâté"])
    }

    @Test func withNothingPickedTheFirstBrandShows() throws {
        food("Grill Tuna", brand: "Tiki Cat", line: "Grill")
        food("Salmon Pâté", brand: "Other Brand", line: nil)
        let catalog = try catalog()

        #expect(catalog.current(selected: nil) == BrandSelection(brand: "Other Brand"))
        // A brand whose foods are all gone falls back to the first brand.
        #expect(catalog.current(selected: BrandSelection(brand: "Deleted Brand")) == BrandSelection(brand: "Other Brand"))
    }

    @Test func noFoodsMeansNoBrand() throws {
        #expect(try catalog().current(selected: nil) == nil)
    }
}
