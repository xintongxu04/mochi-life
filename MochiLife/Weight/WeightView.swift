import SwiftData
import SwiftUI

struct WeightView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [
        SortDescriptor(\WeightEntry.date, order: .reverse),
        SortDescriptor(\WeightEntry.createdAt, order: .reverse),
    ])
    private var entries: [WeightEntry]
    @AppStorage("weightUnit") private var unit: WeightUnit = .kilograms
    @State private var isAddingEntry = false
    @Environment(\.catName) private var catName

    var body: some View {
        NavigationStack {
            List {
                if !entries.isEmpty {
                    Section {
                        WeightChartView(entries: entries, unit: unit)
                    }
                }
                Section {
                    ForEach(entries) { entry in
                        HStack {
                            Text(entry.date, format: .dateTime.day().month(.abbreviated).year())
                            Spacer()
                            Text(unit.formatted(kilograms: entry.kilograms))
                                .monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("weightEntry")
                    }
                    .onDelete(perform: deleteEntries)
                }
            }
            .overlay {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "No weights yet",
                        systemImage: "scalemass",
                        description: Text("Tap + to log \(catName)'s first weight.")
                    )
                }
            }
            .safeAreaInset(edge: .top) {
                Picker("Unit", selection: $unit) {
                    ForEach(WeightUnit.allCases) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .navigationTitle("Mochi Life")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Weight", systemImage: "plus") {
                        isAddingEntry = true
                    }
                }
            }
            .sheet(isPresented: $isAddingEntry) {
                AddWeightView(unit: unit)
            }
        }
    }

    private func deleteEntries(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(entries[index])
        }
        Persistence.save(modelContext)
    }
}

#Preview {
    WeightView()
        .modelContainer(for: WeightEntry.self, inMemory: true)
}
