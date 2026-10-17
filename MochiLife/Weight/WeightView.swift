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

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var width: CGFloat = 0

    var body: some View {
        content
            .overlay {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "No weights yet",
                        systemImage: "scalemass",
                        description: Text("Tap + to log \(catName)'s first weight.")
                    )
                }
            }
            .onGeometryChange(for: CGFloat.self) { AdaptiveLayout.contentWidth(in: $0) } action: { width = $0 }
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

    /// One list (chart, then entries), or with 800 pt of regular width the unit and chart beside
    /// the entries.
    @ViewBuilder
    private var content: some View {
        switch AdaptiveLayout.Columns(sizeClass: sizeClass, width: width) {
        case .single:
            List {
                chartSection
                entriesSection
            }
            .readableContent()
            .safeAreaInset(edge: .top) { unitPicker }
        case .two:
            SplitPanes {
                List { chartSection }
                    .readableContent()
                    .safeAreaInset(edge: .top) { unitPicker }
            } secondary: {
                List { entriesSection }
                    .readableContent()
            }
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
