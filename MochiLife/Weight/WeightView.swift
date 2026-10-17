import SwiftData
import SwiftUI

/// Mochi's weights and chart, pushed from the ring around Mochi.
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
        FoldAwareContainer { layout in
            content(layout)
        }
        .navigationTitle("Weight")
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

    /// One list (chart, then entries), or, when the fold splits the screen, the unit and chart in
    /// the leading (or top) pane and the entries in the other.
    @ViewBuilder
    private func content(_ layout: FoldLayout) -> some View {
        if layout.isSplit {
            FoldPanes(layout: layout) { pane in
                List { chartSection }
                    .paneMargins(pane)
                    .safeAreaInset(edge: .top) { unitPicker }
            } secondary: { pane in
                List { entriesSection }
                    .paneMargins(pane)
                    .overlay { emptyState }
            }
        } else {
            List {
                chartSection
                entriesSection
            }
            .placedInColumn(of: layout)
            .safeAreaInset(edge: .top) { unitPicker }
            .overlay { emptyState }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if entries.isEmpty {
            ContentUnavailableView(
                "No weights yet",
                systemImage: "scalemass",
                description: Text("Tap + to log \(catName)'s first weight.")
            )
        }
    }

    @ViewBuilder
    private var chartSection: some View {
        if !entries.isEmpty {
            Section {
                WeightChartView(entries: entries, unit: unit)
            }
        }
    }

    private var entriesSection: some View {
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

    private var unitPicker: some View {
        Picker("Unit", selection: $unit) {
            ForEach(WeightUnit.allCases) { unit in
                Text(unit.rawValue).tag(unit)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.bottom, 8)
        .frame(maxWidth: AdaptiveLayout.readableWidth)
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
