import SwiftData
import SwiftUI

/// Identifies a brand's page of lines. A nil brand is "My foods".
struct BrandSelection: Hashable {
    var brand: String?
}

/// Identifies a page of products: one line of one brand. A nil line is the "Other" group.
struct LineSelection: Hashable {
    var brand: String?
    var line: String?
}

/// Saved foods, browsed by brand, then line, then product, with search across all of them.
struct SavedFoodsView: View {
    @Query private var foods: [Food]
    @State private var searchText = ""
    @State private var isAddingFood = false

    private var brands: [(brand: String?, count: Int)] {
        let grouped = Dictionary(grouping: foods, by: \.brand)
        return grouped
            .map { (brand: $0.key, count: $0.value.count) }
            .sorted { first, second in
                // Brands in alphabetical order, with "My foods" last.
                switch (first.brand, second.brand) {
                case (nil, _): false
                case (_, nil): true
                case let (first?, second?): first.localizedStandardCompare(second) == .orderedAscending
                }
            }
    }

    private var searchResults: [Food] {
        foods.filter { FoodSearch.matches($0, query: searchText) }.sortedByName()
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        List {
            if isSearching {
                ForEach(searchResults) { food in
                    FoodRow(food: food, showsBrandAndLine: true)
                }
                .onDelete { offsets in
                    FoodRow.delete(offsets.map { searchResults[$0] })
                }
            } else {
                ForEach(brands, id: \.brand) { brand in
                    NavigationLink(value: BrandSelection(brand: brand.brand)) {
                        LabeledContent(brand.brand ?? Food.noBrandTitle, value: "\(brand.count)")
                    }
                    .accessibilityIdentifier("brandRow")
                }
            }
        }
        .overlay {
            if foods.isEmpty {
                ContentUnavailableView(
                    "No foods yet",
                    systemImage: "fork.knife",
                    description: Text("Tap + to add a food Mochi eats.")
                )
            } else if isSearching && searchResults.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search brand, line or food"
        )
        .navigationTitle("Saved Foods")
        .navigationDestination(for: BrandSelection.self) { selection in
            BrandFoodsView(brand: selection.brand)
        }
        .navigationDestination(for: LineSelection.self) { selection in
            LineFoodsView(brand: selection.brand, line: selection.line)
        }
        .navigationDestination(for: Food.self) { food in
            FoodDetailView(food: food)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Food", systemImage: "plus") {
                    isAddingFood = true
                }
            }
        }
        .sheet(isPresented: $isAddingFood) {
            FoodFormView(food: nil)
        }
    }
}

/// A brand's lines, each with how many products it has. Foods without a line are grouped
/// under "Other"; if none of the brand's foods have a line, the products are listed directly.
struct BrandFoodsView: View {
    let brand: String?

    @Query private var allFoods: [Food]

    private var foods: [Food] { allFoods.filter { $0.brand == brand } }

    private var lines: [(line: String?, count: Int)] {
        Dictionary(grouping: foods, by: \.line)
            .map { (line: $0.key, count: $0.value.count) }
            .sorted { first, second in
                switch (first.line, second.line) {
                case (nil, _): false
                case (_, nil): true
                case let (first?, second?): first.localizedStandardCompare(second) == .orderedAscending
                }
            }
    }

    var body: some View {
        Group {
            if lines.allSatisfy({ $0.line == nil }) {
                FoodsList(foods: foods)
            } else {
                List(lines, id: \.line) { line in
                    NavigationLink(value: LineSelection(brand: brand, line: line.line)) {
                        LabeledContent(line.line ?? Food.noLineTitle, value: "\(line.count)")
                    }
                    .accessibilityIdentifier("lineRow")
                }
            }
        }
        .navigationTitle(brand ?? Food.noBrandTitle)
    }
}

/// The products in one line of one brand.
struct LineFoodsView: View {
    let brand: String?
    let line: String?

    @Query private var allFoods: [Food]

    var body: some View {
        FoodsList(foods: allFoods.filter { $0.brand == brand && $0.line == line })
            .navigationTitle(line ?? Food.noLineTitle)
    }
}

/// An alphabetical list of foods that opens each one's details, with swipe to delete.
private struct FoodsList: View {
    let foods: [Food]

    private var sortedFoods: [Food] { foods.sortedByName() }

    var body: some View {
        List {
            ForEach(sortedFoods) { food in
                FoodRow(food: food, showsBrandAndLine: false)
            }
            .onDelete { offsets in
                FoodRow.delete(offsets.map { sortedFoods[$0] })
            }
        }
        .overlay {
            if foods.isEmpty {
                ContentUnavailableView("No foods here", systemImage: "fork.knife")
            }
        }
    }
}

private struct FoodRow: View {
    let food: Food
    let showsBrandAndLine: Bool

    var body: some View {
        NavigationLink(value: food) {
            HStack(spacing: 12) {
                FoodThumbnail(food: food, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(food.name)
                    if showsBrandAndLine {
                        Text([food.brandTitle, food.line].compactMap(\.self).joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(food.formattedKilocaloriesPerGram)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("savedFood")
    }

    @MainActor
    static func delete(_ foods: [Food]) {
        guard let context = foods.first?.modelContext else { return }
        for food in foods {
            context.delete(food)
        }
        try? context.save()
    }
}
