import SwiftData
import SwiftUI

/// Creates or edits a feeding schedule: the amount (the shared size-and-portion picker, with the
/// same calorie override as logging), a label, the days, and start and end dates. A new
/// schedule that starts in the past fills in its past days right away, after saying how many.
/// Editing changes only days not yet added to the log; existing entries stay as they are.
struct ScheduleEditorView: View {
    enum Mode {
        case create(Food)
        case edit(FeedingSchedule)
    }

    let mode: Mode
    /// Called after saving or cancelling, to close the screen.
    let onFinish: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var portion = Portion()
    @State private var label = ""
    @State private var weekdays = Weekdays.everyDay
    @State private var startDate = Calendar.current.startOfDay(for: .now)
    @State private var hasEndDate = false
    @State private var endDate = Calendar.current.startOfDay(for: .now)

    init(mode: Mode, onFinish: @escaping () -> Void) {
        self.mode = mode
        self.onFinish = onFinish
        if case let .edit(schedule) = mode {
            _label = State(initialValue: schedule.label ?? "")
            _weekdays = State(initialValue: schedule.weekdays)
            _startDate = State(initialValue: schedule.startDate)
            _hasEndDate = State(initialValue: schedule.endDate != nil)
            _endDate = State(initialValue: schedule.endDate ?? schedule.startDate)
        }
    }

    private var calendar: Calendar { .current }

    private var source: PortionSource? {
        switch mode {
        case let .create(food): PortionSource(food)
        case let .edit(schedule): schedule.portionSource
        }
    }

    private var startingPortion: Portion? {
        if case let .edit(schedule) = mode { schedule.portion } else { nil }
    }

    private var isEveryDay: Binding<Bool> {
        Binding(get: { weekdays == Weekdays.everyDay }, set: { weekdays = $0 ? Weekdays.everyDay : 0 })
    }

    // MARK: - Validation

    private var amountProblem: String? {
        let amount = portion.measure == .grams ? portion.grams : portion.containers
        guard let amount, amount > 0, portion.kilocalories != nil else { return "Choose an amount greater than zero." }
        return nil
    }

    private var daysProblem: String? { weekdays == 0 ? "Choose at least one day." : nil }

    private var datesProblem: String? {
        hasEndDate && calendar.startOfDay(for: endDate) < calendar.startOfDay(for: startDate)
            ? "The end date can't be before the start date." : nil
    }

    private var canSave: Bool { amountProblem == nil && daysProblem == nil && datesProblem == nil }

    // MARK: - Form

    var body: some View {
        Form {
            header
            if let source {
                PortionPicker(source: source, portion: $portion, startingFrom: startingPortion)
            }
            if let amountProblem {
                Section {
                    Text(amountProblem).foregroundStyle(.red).font(.footnote)
                }
            }
            Section {
                TextField("Label (optional), like Morning kibble", text: $label)
                    .textInputAutocapitalization(.sentences)
            }
            Section {
                Toggle("Every day", isOn: isEveryDay)
                ForEach(Weekdays.ordered(calendar), id: \.self) { weekday in
                    Button {
                        weekdays ^= Weekdays.bit(weekday)
                    } label: {
                        HStack {
                            Text(calendar.weekdaySymbols[weekday - 1])
                                .foregroundStyle(.primary)
                            Spacer()
                            if Weekdays.contains(weekdays, weekday) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .accessibilityAddTraits(Weekdays.contains(weekdays, weekday) ? .isSelected : [])
                }
            } header: {
                Text("Days")
            } footer: {
                if let daysProblem { Text(daysProblem).foregroundStyle(.red) }
            }
            Section {
                DatePicker("Starts", selection: $startDate, displayedComponents: .date)
                Toggle("Ends", isOn: $hasEndDate)
                if hasEndDate {
                    DatePicker("Last day", selection: $endDate, in: startDate..., displayedComponents: .date)
                }
            } footer: {
                if let datesProblem {
                    Text(datesProblem).foregroundStyle(.red)
                } else {
                    Text(footerText)
                }
            }
        }
        .navigationTitle(isEditing ? "Edit Schedule" : "New Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isEditing {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onFinish)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(!canSave)
            }
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { true } else { false }
    }

    private var footerText: String {
        isEditing
            ? "Changes update this schedule's entries from today on and fill in any days newly in range. Past entries, and any day you changed yourself, stay as they are."
            : "The meal is logged on every chosen day in the range, past, today and future, and counts in that day's calories. Delete a day's entry to skip that day."
    }

    @ViewBuilder
    private var header: some View {
        let (name, brand, line, photoKey, kind): (String, String?, String?, String?, FoodKind) = switch mode {
        case let .create(food): (food.name, food.brand, food.line, food.photoKey, food.kind)
        case let .edit(schedule): (schedule.foodName, schedule.foodBrand, schedule.foodLine, schedule.foodPhotoKey, schedule.kind)
        }
        Section {
            HStack(spacing: 12) {
                FoodThumbnail(libraryIdentifier: photoKey, kind: kind, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.headline)
                    Text([brand ?? Food.noBrandTitle, line].compactMap(\.self).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            if isEditing { Text("To feed a different food, add a new schedule.") }
        }
    }

    // MARK: - Saving

    /// Saves and logs the meal on every chosen day in the range straight away: past, today and
    /// future (no confirmation).
    private func save() {
        guard canSave else { return }
        store()
    }

    private func store() {
        let schedule: FeedingSchedule
        switch mode {
        case let .create(food):
            schedule = FeedingSchedule(foodName: food.name, measureRawValue: "grams", kilocaloriesPerOccurrence: 0,
                                       weekdays: weekdays, startDate: startDate)
            schedule.record(food)
            modelContext.insert(schedule)
        case let .edit(existing):
            schedule = existing
            schedule.updatedAt = .now
        }
        schedule.record(portion)
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        schedule.label = trimmed.isEmpty ? nil : trimmed
        schedule.weekdays = weekdays
        schedule.startDate = calendar.startOfDay(for: startDate)
        schedule.endDate = hasEndDate ? calendar.startOfDay(for: endDate) : nil
        // Entries from today on match the schedule; days newly in range are filled in.
        ScheduleMaterializer(context: modelContext).scheduleChanged(schedule)
        guard Persistence.save(modelContext) else { return }
        onFinish()
    }
}
