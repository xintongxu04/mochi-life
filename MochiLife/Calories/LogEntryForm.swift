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
    /// Prefills a quick entry's name (e.g. the text that wasn't found).
    var initialName: String?
    /// For a food matched automatically: shows "Not this one", which goes back to the choices.
    var notThisOne: (() -> Void)?
    /// Called after saving or cancelling, to close the screen this form is in.
    let onFinish: () -> Void

    @Environment(\.modelContext) private var modelContext
    /// The day being viewed when logging started; new entries default to it.
    @Environment(\.logDay) private var logDay
    @State private var hasSetDefaultDate = false
    @State private var portion = Portion()
    @State private var loggedAt = Date.now
    @State private var name = ""
    @State private var caloriesText = ""
    @State private var carriesRestForward = true
    @State private var isConfirmingLongPlan = false
    @State private var isAskingAboutCarriedEntries = false

    init(mode: Mode, initialName: String? = nil, notThisOne: (() -> Void)? = nil, onFinish: @escaping () -> Void) {
        self.mode = mode
        self.initialName = initialName
        self.notThisOne = notThisOne
        self.onFinish = onFinish
        if case .quickEntry = mode, let initialName {
            _name = State(initialValue: initialName)
        }
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

    private var quickCalories: Double? { NumberInput.kilocalories.value(caloriesText) }

    private var canSave: Bool {
        if portionSource != nil {
            return portion.kilocalories != nil
        }
        return !trimmedName.isEmpty && quickCalories != nil
    }

    private var isLoggingNewFood: Bool {
        if case .logFood = mode { true } else { false }
    }

    /// What's left of the can or pouch after this portion, as portions for the following days.
    private var carryPlan: [Fraction] {
        guard portion.measure == .containers, let exact = portion.exactContainers else { return [] }
        return CarryForward.plan(for: exact)
    }

    private var hasOpenedContainer: Bool {
        guard portion.measure == .containers, let exact = portion.exactContainers else { return false }
        return exact.fractionalPart > .zero
    }

    private var containerName: String { portion.size?.containerName ?? "can" }

    private var lastCarriedDay: Date {
        Calendar.current.date(byAdding: .day, value: carryPlan.count, to: loggedAt) ?? loggedAt
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
            if let notThisOne {
                Section {
                    Button("Not this one?", systemImage: "arrow.uturn.backward", action: notThisOne)
                        .accessibilityHint("Shows the other possible foods and web search")
                } footer: {
                    Text("Matched automatically from the package.")
                }
            }
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
            if isLoggingNewFood && hasOpenedContainer {
                carryForwardSection
            }
            Section {
                DatePicker("When", selection: $loggedAt)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: defaultToViewedDay)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onFinish)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(!canSave)
            }
        }
        .confirmationDialog(
            "Add \(carryPlan.count) more days?",
            isPresented: $isConfirmingLongPlan,
            titleVisibility: .visible
        ) {
            Button("Add All \(carryPlan.count) Days") { logFood(carryingForward: true) }
            Button("Only Log This Day") { logFood(carryingForward: false) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The rest of this \(containerName) would be spread over \(carryPlan.count) days, through \(lastCarriedDay.formatted(date: .abbreviated, time: .omitted)).")
        }
        .confirmationDialog(
            "Update the following days too?",
            isPresented: $isAskingAboutCarriedEntries,
            titleVisibility: .visible
        ) {
            Button("Update Them") { finishEditingOpenedContainer(.update) }
            Button("Remove Them", role: .destructive) { finishEditingOpenedContainer(.remove) }
            Button("Keep Them as They Are", role: .cancel) { finishEditingOpenedContainer(.keep) }
        } message: {
            Text("The rest of this \(containerName) was added to the following days.")
        }
    }

    private var carryForwardSection: some View {
        Section {
            if !carryPlan.isEmpty {
                Toggle("Use the rest on the following days", isOn: $carriesRestForward)
                    .accessibilityIdentifier("carryForwardToggle")
            }
        } footer: {
            if carryPlan.isEmpty {
                Text("This amount is too small to spread over the following days.")
            } else if carriesRestForward {
                Text(CarryForward.preview(of: carryPlan, containerName: containerName, startingAfter: loggedAt))
                    .accessibilityIdentifier("carryForwardPreview")
            } else {
                Text("Only this entry will be saved.")
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
        case .logFood:
            let carries = carriesRestForward && !carryPlan.isEmpty
            if carries && carryPlan.count > CarryForward.daysBeforeAsking {
                isConfirmingLongPlan = true
            } else {
                logFood(carryingForward: carries)
            }
        case .quickEntry:
            modelContext.insert(FoodLogEntry(foodName: trimmedName, kilocalories: quickCalories ?? 0, loggedAt: loggedAt))
            finish()
        case let .edit(entry):
            let before = EntrySnapshot(entry)
            entry.loggedAt = loggedAt
            if entry.isQuickEntry {
                entry.foodName = trimmedName
                entry.kilocalories = quickCalories ?? entry.kilocalories
            } else {
                entry.record(portion)
            }
            // Changing the entry a can or pouch was opened with: ask about the following days.
            if !entry.isCarriedForward, EntrySnapshot(entry) != before,
               !entry.laterCarriedEntries(in: modelContext).isEmpty {
                isAskingAboutCarriedEntries = true
            } else {
                finish()
            }
        }
    }

    /// When logging from an earlier day's view, start on that day (at the current time).
    private func defaultToViewedDay() {
        guard !hasSetDefaultDate else { return }
        hasSetDefaultDate = true
        if case .edit = mode { return }
        let calendar = Calendar.current
        guard let logDay, !calendar.isDateInToday(logDay) else { return }
        let time = calendar.dateComponents([.hour, .minute], from: .now)
        loggedAt = calendar.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: 0, of: logDay) ?? logDay
    }

    private func logFood(carryingForward: Bool) {
        guard case let .logFood(food, _) = mode else { return }
        let entry = FoodLogEntry(foodName: food.name, kilocalories: 0, loggedAt: loggedAt)
        entry.record(food, portion: portion)
        modelContext.insert(entry)
        if carryingForward {
            entry.makeCarriedEntries().forEach(modelContext.insert)
        }
        finish()
    }

    private enum CarriedEntriesChoice { case update, remove, keep }

    private func finishEditingOpenedContainer(_ choice: CarriedEntriesChoice) {
        guard case let .edit(entry) = mode else { return }
        if choice != .keep {
            entry.laterCarriedEntries(in: modelContext).forEach(modelContext.delete)
        }
        if choice == .update {
            entry.makeCarriedEntries().forEach(modelContext.insert)
        }
        finish()
    }

    private func finish() {
        if Persistence.save(modelContext) { onFinish() }
    }
}

/// The parts of an entry that matter for the days carried forward from it.
private struct EntrySnapshot: Equatable {
    var loggedAt: Date
    var kilocalories: Double
    var sizeName: String?
    var measure: String?
    var numerator: Int?
    var denominator: Int?

    init(_ entry: FoodLogEntry) {
        loggedAt = entry.loggedAt
        kilocalories = entry.kilocalories
        sizeName = entry.sizeName
        measure = entry.measureRawValue
        numerator = entry.containersNumerator
        denominator = entry.containersDenominator
    }
}

extension EnvironmentValues {
    /// The day being viewed when the log flow started; new entries default to it.
    @Entry var logDay: Date? = nil
}
