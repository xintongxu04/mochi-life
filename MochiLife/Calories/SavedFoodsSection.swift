import SwiftData
import SwiftUI

struct SavedFoodsSection: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allFoods: [Food]
    /// Called when a food is tapped, so the screen showing this section can open it for editing.
    let onSelect: (Food) -> Void

    private var foods: [Food] { allFoods.sortedByName() }

    var body: some View {
        Section("Saved Foods") {
            if foods.isEmpty {
                ContentUnavailableView(
                    "No foods yet",
                    systemImage: "fork.knife",
                    description: Text("Tap + to add a food Mochi eats.")
                )
            } else {
                ForEach(foods) { food in
                    Button {
                        onSelect(food)
                    } label: {
                        HStack {
                            Text(food.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(food.formattedKilocaloriesPerGram)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.primary)
                    .accessibilityIdentifier("savedFood")
                }
                .onDelete(perform: deleteFoods)
            }
        }
    }

    private func deleteFoods(at offsets: IndexSet) {
        let foods = foods
        for index in offsets {
            modelContext.delete(foods[index])
        }
        try? modelContext.save()
    }
}
