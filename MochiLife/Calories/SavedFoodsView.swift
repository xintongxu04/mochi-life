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

/// Opens the quick entry form when picking a food to log.
struct QuickEntrySelection: Hashable {}

extension EnvironmentValues {
    /// True while saved foods are shown for picking a food to log, which turns off deleting.
    @Entry var isPickingFood = false
}

/// Saved foods, browsed by brand, then line, then product, with search across all of them.
struct SavedFoodsView: View {
    enum Mode {
        /// Browse, add, edit and delete saved foods.
        case browse
        /// Choose a food to log. `onFinish` closes the logging screens.
        case pick(onFinish: () -> Void)
        /// Choose a food for a new feeding schedule. `onFinish` closes the schedule screens.
        case schedule(onFinish: () -> Void)
    }

    var mode: Mode = .browse

    @Environment(\.isPickingFood) private var isPickingFood
    @Environment(\.catName) private var catName
    @Query private var foods: [Food]
    @State private var searchText = ""
    @State private var isAddingFood = false
    @State private var isAddingWithAI = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// The brand shown in the second column (regular width).
    @State private var selectedBrand: BrandSelection?

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

    private var isPicking: Bool {
        switch mode {
        case .browse: false
        case .pick, .schedule: true
        }
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Regular width (iPhone Duo open) browses in two columns: brands, then the chosen brand's
    /// products grouped by line. Compact width pushes brand → line → product. Search results are
    /// one list either way.
    private var showsColumns: Bool { sizeClass == .regular && !isSearching && !foods.isEmpty }

    private var currentBrand: BrandSelection? {
        if let selectedBrand, brands.contains(where: { $0.brand == selectedBrand.brand }) { return selectedBrand }
        return brands.first.map { BrandSelection(brand: $0.brand) }
    }

    var body: some View {
        Group {
            if showsColumns {
                columns
            } else {
                list
            }
        }
        .overlay {
            if foods.isEmpty {
                ContentUnavailableView(
                    "No foods yet",
                    systemImage: "fork.knife",
                    description: Text("Tap + to add a food \(catName) eats.")
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
        .navigationTitle(isPicking ? "Choose a Food" : "Saved Foods")
        .toolbar {
            switch mode {
            case .browse:
                ToolbarItem(placement: .primaryAction) {
                    Button("Add with AI", systemImage: "sparkles") {
                        isAddingWithAI = true
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Food", systemImage: "plus") {
                        isAddingFood = true
                    }
                }
            case let .pick(onFinish), let .schedule(onFinish):
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onFinish)
                }
            }
        }
        .sheet(isPresented: $isAddingFood) {
            NavigationStack {
                FoodEditorView(mode: .create(name: nil)) { _ in isAddingFood = false }
            }
        }
        .sheet(isPresented: $isAddingWithAI) {
            AddWithAIView()
        }
    }

    /// The compact-width list: brands to push, or search results.
    private var list: some View {
        List {
            if isSearching {
                ForEach(searchResults) { food in
                    FoodRow(food: food, showsBrandAndLine: true)
                }
                .onDelete { offsets in
                    FoodRow.delete(offsets.map { searchResults[$0] })
                }
                .deleteDisabled(isPickingFood)
            } else {
                quickEntrySection
                ForEach(brands, id: \.brand) { brand in
                    NavigationLink(value: BrandSelection(brand: brand.brand)) {
                        LabeledContent(brand.brand ?? Food.noBrandTitle, value: "\(brand.count)")
                    }
                    .accessibilityIdentifier("brandRow")
                }
            }
        }
        .readableContent()
    }

    /// Brands beside the chosen brand's products (regular width). Tapping a brand shows its
    /// products; tapping a product opens it as usual.
    private var columns: some View {
        SplitPanes {
            List {
                quickEntrySection
                Section("Brands") {
                    ForEach(brands, id: \.brand) { brand in
                        let isSelected = currentBrand?.brand == brand.brand
                        Button {
                            selectedBrand = BrandSelection(brand: brand.brand)
                        } label: {
                            LabeledContent(brand.brand ?? Food.noBrandTitle, value: "\(brand.count)")
                                .foregroundStyle(.primary)
                        }
                        .listRowBackground(isSelected ? Color.accentColor.opacity(0.15) : nil)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .accessibilityIdentifier("brandRow")
                    }
                }
            }
            .readableContent()
        } secondary: {
            if let currentBrand {
                BrandProductsList(brand: currentBrand.brand)
                    .readableContent()
            }
        }
    }

    /// "Quick Entry", when picking a food to log.
    @ViewBuilder
    private var quickEntrySection: some View {
        if case .pick = mode {
            Section {
                NavigationLink(value: QuickEntrySelection()) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Quick Entry")
                            Text("Just a name and calories, for one-off treats")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "bolt")
                    }
                }
                .accessibilityIdentifier("quickEntryRow")
            }
        }
    }
}

extension View {
    /// Registers the screens saved foods navigate to (brand, line, food, quick entry). Apply it
    /// once at the root of the NavigationStack that shows `SavedFoodsView`, so the links work
    /// however saved foods was opened.
    func savedFoodsDestinations(mode: SavedFoodsView.Mode) -> some View {
        navigationDestination(for: BrandSelection.self) { selection in
            BrandFoodsView(brand: selection.brand)
        }
        .navigationDestination(for: LineSelection.self) { selection in
            LineFoodsView(brand: selection.brand, line: selection.line)
        }
        .navigationDestination(for: Food.self) { food in
            switch mode {
            case .browse:
                FoodDetailView(food: food)
            case let .pick(onFinish):
                LogEntryForm(mode: .logFood(food, startingFrom: nil), onFinish: onFinish)
            case let .schedule(onFinish):
                ScheduleEditorView(mode: .create(food), onFinish: onFinish)
            }
        }
        .navigationDestination(for: QuickEntrySelection.self) { _ in
            if case let .pick(onFinish) = mode {
                LogEntryForm(mode: .quickEntry, onFinish: onFinish)
            }
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
                .readableContent()
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

/// One brand's products, grouped under their lines, for the second column of the regular-width
/// browser. Foods without a line come last under "Other" (no heading if the brand has no lines).
private struct BrandProductsList: View {
    let brand: String?

    @Environment(\.isPickingFood) private var isPickingFood
    @Query private var allFoods: [Food]

    private var lines: [(line: String?, foods: [Food])] {
        Dictionary(grouping: allFoods.filter { $0.brand == brand }, by: \.line)
            .map { (line: $0.key, foods: $0.value.sortedByName()) }
            .sorted { first, second in
                switch (first.line, second.line) {
                case (nil, _): false
                case (_, nil): true
                case let (first?, second?): first.localizedStandardCompare(second) == .orderedAscending
                }
            }
    }

    var body: some View {
        let lines = lines
        let hasLines = lines.contains { $0.line != nil }
        List {
            ForEach(lines, id: \.line) { line in
                Section {
                    ForEach(line.foods) { food in
                        FoodRow(food: food, showsBrandAndLine: false)
                    }
                    .onDelete { offsets in
                        FoodRow.delete(offsets.map { line.foods[$0] })
                    }
                    .deleteDisabled(isPickingFood)
                } header: {
                    if hasLines {
                        Text(line.line ?? Food.noLineTitle)
                    }
                }
            }
        }
        .overlay {
            if lines.isEmpty {
                ContentUnavailableView("No foods here", systemImage: "fork.knife")
            }
        }
    }
}

/// An alphabetical list of foods that opens each one's details, with swipe to delete.
private struct FoodsList: View {
    let foods: [Food]

    @Environment(\.isPickingFood) private var isPickingFood

    private var sortedFoods: [Food] { foods.sortedByName() }

    var body: some View {
        List {
            ForEach(sortedFoods) { food in
                FoodRow(food: food, showsBrandAndLine: false)
            }
            .onDelete { offsets in
                FoodRow.delete(offsets.map { sortedFoods[$0] })
            }
            .deleteDisabled(isPickingFood)
        }
        .readableContent()
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
        .accessibilityValue(food.kind.displayName)
        .accessibilityIdentifier("savedFood")
    }

    @MainActor
    static func delete(_ foods: [Food]) {
        guard let context = foods.first?.modelContext else { return }
        FoodLibraryLoader.rememberDeletion(of: foods)
        for food in foods {
            // The food's own photo file goes with it (log entries then show a placeholder).
            if let key = food.thumbnailKey { FoodThumbnailStore.deleteFile(forKey: key) }
            context.delete(food)
        }
        Persistence.save(context)
    }
}
