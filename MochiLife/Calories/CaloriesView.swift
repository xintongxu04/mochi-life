import SwiftData
import SwiftUI

/// The Calories tab. Opens on what Mochi has eaten today, with saved foods one tap away.
struct CaloriesView: View {
    var body: some View {
        NavigationStack {
            DayLogView()
        }
    }
}

/// One day's food log: the total, then each entry. Arrows (or a swipe on the total) move
/// between days.
struct DayLogView: View {
    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var isLogging = false

    private var calendar: Calendar { .current }
    private var isToday: Bool { calendar.isDateInToday(day) }

    private var title: String {
        if isToday { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    var body: some View {
        DayEntriesList(day: day, dayControls: dayControls, onSwipe: move(by:))
            .navigationTitle(title)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    NavigationLink {
                        SavedFoodsView()
                    } label: {
                        Label("Saved Foods", systemImage: "books.vertical")
                    }
                    NavigationLink {
                        CalorieTargetSettingsView()
                    } label: {
                        Label("Daily Calories", systemImage: "slider.horizontal.3")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Log Food", systemImage: "plus") {
                        isLogging = true
                    }
                }
            }
            .sheet(isPresented: $isLogging) {
                LogFoodSheet()
            }
    }

    private var dayControls: some View {
        HStack {
            Button("Previous Day", systemImage: "chevron.left") { move(by: -1) }
            Spacer()
            if !isToday {
                Button("Back to Today") {
                    day = calendar.startOfDay(for: .now)
                }
                .font(.subheadline.weight(.semibold))
                Spacer()
            }
            Button("Next Day", systemImage: "chevron.right") { move(by: 1) }
                .disabled(isToday)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
    }

    private func move(by days: Int) {
        guard let newDay = calendar.date(byAdding: .day, value: days, to: day),
              newDay <= .now
        else { return }
        day = newDay
    }
}

private struct DayEntriesList<Controls: View>: View {
    let day: Date
    let dayControls: Controls
    /// Called with -1 to show the day before, or 1 for the day after.
    let onSwipe: (Int) -> Void

    @Environment(\.modelContext) private var modelContext
    @Query private var entries: [FoodLogEntry]
    @State private var entryBeingEdited: FoodLogEntry?
    /// An entry with carried days after it, waiting for the owner to say what to remove.
    @State private var entryBeingDeleted: FoodLogEntry?

    init(day: Date, dayControls: Controls, onSwipe: @escaping (Int) -> Void) {
        self.day = day
        self.dayControls = dayControls
        self.onSwipe = onSwipe
        let start = day
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        _entries = Query(
            filter: #Predicate { $0.loggedAt >= start && $0.loggedAt < end },
            sort: [SortDescriptor(\.loggedAt, order: .reverse), SortDescriptor(\.createdAt, order: .reverse)]
        )
    }

    private var total: Double { entries.reduce(0) { $0 + $1.kilocalories } }

    var body: some View {
        CalorieTargetReader { target in
            list(target: target)
        }
    }

    private func list(target: CalorieTarget) -> some View {
        List {
            Section {
                VStack(spacing: 12) {
                    dayControls
                    CalorieProgressView(eaten: total, target: target)
                }
                .padding(.vertical, 4)
                .contentShape(.rect)
                .gesture(swipeBetweenDays)
            }

            Section {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "Nothing logged",
                        systemImage: "fork.knife",
                        description: Text("Tap + to log something Mochi ate.")
                    )
                } else {
                    ForEach(entries) { entry in
                        Button {
                            entryBeingEdited = entry
                        } label: {
                            LogEntryRow(entry: entry)
                        }
                        .tint(.primary)
                        .accessibilityIdentifier("logEntry")
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            delete(entries[index])
                        }
                    }
                }
            }

            Section("Daily Calories") {
                CalorieChartView(target: target)
            }
        }
        .sheet(item: $entryBeingEdited) { entry in
            NavigationStack {
                LogEntryForm(mode: .edit(entry), onFinish: { entryBeingEdited = nil })
            }
        }
        .confirmationDialog(
            deletionQuestion,
            isPresented: Binding(get: { entryBeingDeleted != nil }, set: { if !$0 { entryBeingDeleted = nil } }),
            titleVisibility: .visible,
            presenting: entryBeingDeleted
        ) { entry in
            Button(entry.isCarriedForward ? "Remove This and Later Days" : "Remove All", role: .destructive) {
                entry.laterCarriedEntries(in: modelContext).forEach(modelContext.delete)
                modelContext.delete(entry)
                try? modelContext.save()
            }
            Button(entry.isCarriedForward ? "Remove Only This Day" : "Remove Only This Entry") {
                modelContext.delete(entry)
                try? modelContext.save()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var deletionQuestion: String {
        guard let entry = entryBeingDeleted else { return "" }
        let container = entry.containerName
        return entry.isCarriedForward
            ? "Also remove the later days from this \(container)?"
            : "Also remove the rest of this \(container) from the following days?"
    }

    /// Deletes an entry, first asking about any days carried forward after it.
    private func delete(_ entry: FoodLogEntry) {
        if entry.laterCarriedEntries(in: modelContext).isEmpty {
            modelContext.delete(entry)
            try? modelContext.save()
        } else {
            entryBeingDeleted = entry
        }
    }

    /// Swiping right on the total shows the day before; swiping left shows the day after.
    private var swipeBetweenDays: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                onSwipe(value.translation.width > 0 ? -1 : 1)
            }
    }
}

/// Calories eaten against the daily target, as numbers and a progress bar. Going over just
/// changes the color slightly and says by how much.
private struct CalorieProgressView: View {
    let eaten: Double
    let target: CalorieTarget

    var body: some View {
        VStack(spacing: 8) {
            Text("\(Portion.formatKilocalories(eaten)) kcal")
                .font(.largeTitle.bold())
                .monospacedDigit()
                .contentTransition(.numericText())
                .accessibilityIdentifier("dayTotal")
            if let goal = target.dailyKilocalories {
                let isOver = eaten > goal
                Text("\(Portion.formatKilocalories(eaten)) of \(Portion.formatKilocalories(goal)) kcal · \(target.label.lowercased())")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ProgressView(value: min(eaten / goal, 1))
                    .tint(isOver ? .indigo : .accentColor)
                if isOver {
                    Text("\(Portion.formatKilocalories(eaten - goal)) kcal over")
                        .font(.subheadline)
                        .foregroundStyle(.indigo)
                }
            } else {
                Text("eaten")
                    .foregroundStyle(.secondary)
                if case let .missing(details) = target {
                    MissingCalorieDetailsView(missing: details)
                        .padding(.top, 4)
                }
            }
        }
    }
}

private struct LogEntryRow: View {
    let entry: FoodLogEntry

    var body: some View {
        HStack(spacing: 12) {
            if entry.isQuickEntry {
                Image(systemName: "bolt")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .background(.fill.tertiary, in: .rect(cornerRadius: 8))
            } else {
                FoodThumbnail(libraryIdentifier: entry.foodLibraryIdentifier, size: 44)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.foodName)
                    .lineLimit(2)
                Text([entry.amountDescription, entry.loggedAt.formatted(date: .omitted, time: .shortened)]
                    .compactMap(\.self).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if entry.isCarriedForward, let openedAt = entry.openedAt {
                    Label(
                        "From a \(entry.containerName) opened \(openedAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))",
                        systemImage: "arrow.turn.down.right"
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("\(Portion.formatKilocalories(entry.kilocalories)) kcal")
                .monospacedDigit()
        }
    }
}
