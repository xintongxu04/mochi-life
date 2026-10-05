import SwiftData
import SwiftUI

/// Logs a food, edits a log entry, or makes a quick entry with just a name and calories.
struct LogEntryForm: View {
    enum Mode {
        case logFood(Food, startingFrom: Portion?)
        case quickEntry
        case edit(FoodLogEntry)
    }

    let mode: Mode
    /// Called after saving or cancelling, to close the screen this form is in.
    let onFinish: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var portion = Portion()
    @State private var loggedAt = Date.now
    @State private var name = ""
    @State private var caloriesText = ""

    init(mode: Mode, onFinish: @escaping () -> Void) {
        self.mode = mode
        self.onFinish = onFinish
        if case let .edit(entry) = mode {
            _loggedAt = State(initialValue: entry.loggedAt)
            _name = State(initialValue: entry.foodName)
            _caloriesText = State(initialValue: Portion.formatKilocalories(entry.kilocalories))
        }
    }

    /// The saved copy of the food the portion picker works from, if there is one.
    private var portionSource: PortionSource? {
        switch mode {
        case let .logFood(food, _): PortionSource(food)
        case .quickEntry: nil
        case let .edit(entry): entry.portionSource
        }
    }

    private var startingPortion: Portion? {
        switch mode {
        case let .logFood(_, portion): portion
        case .quickEntry: nil
        case let .edit(entry): entry.portion
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var quickCalories: Double? { Portion.parseAmount(caloriesText) }

    private var canSave: Bool {
        if portionSource != nil {
            return portion.kilocalories != nil
        }
        return !trimmedName.isEmpty && quickCalories != nil
    }

    private var title: String {
        switch mode {
        case .logFood: "Log Food"
        case .quickEntry: "Quick Entry"
        case .edit: "Edit Entry"
        }
    }

    var body: some View {
        Form {
            header
            if let portionSource {
                PortionPicker(source: portionSource, portion: $portion, startingFrom: startingPortion)
            } else {
                Section {
                    TextField("Name, like Freeze-dried treat", text: $name)
                        .textInputAutocapitalization(.sentences)
                        .accessibilityIdentifier("quickName")
                    HStack {
                        Text("Calories")
                        TextField("Calories", text: $caloriesText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("quickCalories")
                        Text("kcal")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                DatePicker("When", selection: $loggedAt)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onFinish)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(!canSave)
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        switch mode {
        case let .logFood(food, _):
            foodHeader(name: food.name, brand: food.brandTitle, line: food.line, libraryIdentifier: food.libraryIdentifier)
        case let .edit(entry) where !entry.isQuickEntry:
            foodHeader(name: entry.foodName, brand: entry.foodBrand ?? Food.noBrandTitle, line: entry.foodLine, libraryIdentifier: entry.foodLibraryIdentifier)
        default:
            EmptyView()
        }
    }

    private func foodHeader(name: String, brand: String, line: String?, libraryIdentifier: String?) -> some View {
        Section {
            HStack(spacing: 12) {
                FoodThumbnail(libraryIdentifier: libraryIdentifier, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.headline)
                    Text([brand, line].compactMap(\.self).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func save() {
        guard canSave else { return }
        switch mode {
        case let .logFood(food, _):
            let entry = FoodLogEntry(foodName: food.name, kilocalories: 0, loggedAt: loggedAt)
            entry.record(food, portion: portion)
            modelContext.insert(entry)
        case .quickEntry:
            modelContext.insert(FoodLogEntry(foodName: trimmedName, kilocalories: quickCalories ?? 0, loggedAt: loggedAt))
        case let .edit(entry):
            entry.loggedAt = loggedAt
            if entry.isQuickEntry {
                entry.foodName = trimmedName
                entry.kilocalories = quickCalories ?? entry.kilocalories
            } else {
                entry.record(portion)
            }
        }
        try? modelContext.save()
        onFinish()
    }
}

/// The "+" flow: find a food by browsing or searching (or make a quick entry), then log it.
struct LogFoodSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SavedFoodsView(mode: .pick(onFinish: { dismiss() }))
        }
        .environment(\.isPickingFood, true)
    }
}
