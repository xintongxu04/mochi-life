import SwiftData
import SwiftUI

/// Screens opened from the Calories tab's toolbar.
enum CaloriesScreen: Hashable {
    case savedFoods
    case dailyCalorieSettings
    case schedules
}

/// The Calories tab. Opens on what the cat has eaten today, with saved foods one tap away.
struct CaloriesView: View {
    var body: some View {
        NavigationStack {
            DayLogView()
        }
    }
}

/// One day's food log: the total, then each entry. Arrows (or a swipe on the total) move
/// between days: back to any earlier day, and forward up to the last future day that has
/// entries (such as the rest of an opened can).
struct DayLogView: View {
    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var isLogging = false
    /// The entry with the latest date, to know how far forward days can be shown.
    @Query private var latestEntries: [FoodLogEntry]

    init() {
        var latest = FetchDescriptor<FoodLogEntry>(sortBy: [SortDescriptor(\.loggedAt, order: .reverse)])
        latest.fetchLimit = 1
        _latestEntries = Query(latest)
    }

    private var calendar: Calendar { .current }
    private var today: Date { calendar.startOfDay(for: .now) }
    private var isToday: Bool { calendar.isDateInToday(day) }
    private var isFuture: Bool { day > today }

    /// Today, or the last future day with entries if that's later.
    private var lastDay: Date {
        guard let latest = latestEntries.first?.loggedAt else { return today }
        return max(today, calendar.startOfDay(for: latest))
    }

    private var title: String {
        if isToday { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        if calendar.isDateInTomorrow(day) { return "Tomorrow" }
        return day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    var body: some View {
        DayEntriesList(day: day, isFuture: isFuture, dayControls: dayControls, onSwipe: move(by:))
            .navigationTitle(title)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    NavigationLink(value: CaloriesScreen.savedFoods) {
                        Label("Saved Foods", systemImage: "books.vertical")
                    }
                    NavigationLink(value: CaloriesScreen.schedules) {
                        Label("Schedules", systemImage: "calendar.badge.clock")
                    }
                    NavigationLink(value: CaloriesScreen.dailyCalorieSettings) {
                        Label("Daily Calories", systemImage: "slider.horizontal.3")
                    }
                }
            }
            // The one primary action, always visible above the tab bar; the list scrolls under it
            // and is inset so its last row is never hidden.
            .safeAreaInset(edge: .bottom) {
                Button {
                    isLogging = true
                } label: {
                    Label("Log Food", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .frame(minHeight: 44)
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityHint(isToday ? "Logs something eaten today" : "Logs something for \(title)")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(.bar)
            }
            .sheet(isPresented: $isLogging) {
                LogFoodFlowView(day: day)
            }
            // Registered here, at the root of the Calories stack, so links inside saved foods
            // (brand, line, food) are found when saved foods is opened from this screen.
            .navigationDestination(for: CaloriesScreen.self) { screen in
                switch screen {
                case .savedFoods: SavedFoodsView()
                case .dailyCalorieSettings: CalorieTargetSettingsView()
                case .schedules: FeedingSchedulesView()
                }
            }
            .savedFoodsDestinations(mode: .browse)
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
                .disabled(day >= lastDay)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
    }

    private func move(by days: Int) {
        guard let newDay = calendar.date(byAdding: .day, value: days, to: day),
              newDay <= lastDay
        else { return }
        day = newDay
    }
}

private struct DayEntriesList<Controls: View>: View {
    let day: Date
    /// Future days show their entries as planned, not eaten.
    let isFuture: Bool
    let dayControls: Controls
    /// Called with -1 to show the day before, or 1 for the day after.
    let onSwipe: (Int) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.catName) private var catName
    @Query private var entries: [FoodLogEntry]
    /// For future days: schedules shown as previews (never saved, never counted).
    @Query(filter: #Predicate<FeedingSchedule> { !$0.isPaused }, sort: [SortDescriptor(\FeedingSchedule.createdAt)])
    private var activeSchedules: [FeedingSchedule]
    @State private var entryBeingEdited: FoodLogEntry?
    /// An entry with carried days after it, waiting for the owner to say what to remove.
    @State private var entryBeingDeleted: FoodLogEntry?

    init(day: Date, isFuture: Bool, dayControls: Controls, onSwipe: @escaping (Int) -> Void) {
        self.day = day
        self.isFuture = isFuture
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

    /// Schedules that would add an entry on this future day.
    private var upcomingSchedules: [FeedingSchedule] {
        activeSchedules.filter { $0.applies(on: day) }
    }

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
                    if isFuture {
                        PlannedCaloriesView(planned: total)
                    } else {
                        CalorieProgressView(eaten: total, target: target)
                    }
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
                        description: Text("Tap + to log something \(catName) ate.")
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

            if isFuture, !upcomingSchedules.isEmpty {
                Section {
                    ForEach(upcomingSchedules) { schedule in
                        ScheduledPreviewRow(schedule: schedule)
                    }
                } header: {
                    Text("Scheduled")
                } footer: {
                    Text("Added to the log on the day. Not counted in the total until then.")
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
                Persistence.save(modelContext)
            }
            Button(entry.isCarriedForward ? "Remove Only This Day" : "Remove Only This Entry") {
                modelContext.delete(entry)
                Persistence.save(modelContext)
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
            Persistence.save(modelContext)
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

/// A future day's entries (such as the rest of an opened can) aren't eaten yet, so they're
/// shown as planned and kept out of totals, progress and the chart until the day arrives.
private struct PlannedCaloriesView: View {
    let planned: Double

    var body: some View {
        VStack(spacing: 2) {
            Text("\(Portion.formatKilocalories(planned)) kcal")
                .font(.largeTitle.bold())
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("dayTotal")
            Text("planned")
                .foregroundStyle(.secondary)
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
                Text([entry.amountDescription, entry.isScheduled ? nil : entry.loggedAt.formatted(date: .omitted, time: .shortened)]
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
                if entry.isScheduled {
                    Label("Scheduled", systemImage: "repeat")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Added by a feeding schedule")
                }
            }
            Spacer()
            Text("\(Portion.formatKilocalories(entry.kilocalories)) kcal")
                .monospacedDigit()
        }
    }
}

/// A schedule on a future day: shown dimmed and dashed, not saved and not counted.
private struct ScheduledPreviewRow: View {
    let schedule: FeedingSchedule

    var body: some View {
        HStack(spacing: 12) {
            FoodThumbnail(libraryIdentifier: schedule.foodPhotoKey, size: 44)
                .opacity(0.5)
            VStack(alignment: .leading, spacing: 2) {
                Text(schedule.title)
                    .lineLimit(2)
                if let amount = schedule.amountDescription {
                    Text(amount)
                        .font(.caption)
                }
                Label("Scheduled", systemImage: "repeat")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
            Spacer()
            Text("\(Portion.formatKilocalories(schedule.kilocaloriesPerOccurrence)) kcal")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Scheduled preview: \(schedule.title), \(Portion.formatKilocalories(schedule.kilocaloriesPerOccurrence)) kcal, not counted yet")
    }
}
