import SwiftUI

/// The Calories tab. Each part of the tab is its own section, so later features
/// (like logging meals or daily totals) can be added as new sections here.
struct CaloriesView: View {
    @State private var isAddingFood = false
    @State private var foodBeingEdited: Food?

    var body: some View {
        NavigationStack {
            List {
                SavedFoodsSection(onSelect: { foodBeingEdited = $0 })
            }
            .navigationTitle("Calories")
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
            .sheet(item: $foodBeingEdited) { food in
                FoodFormView(food: food)
            }
        }
    }
}

#Preview {
    CaloriesView()
        .modelContainer(for: Food.self, inMemory: true)
}
