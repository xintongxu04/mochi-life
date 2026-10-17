import SwiftData
import SwiftUI

/// Screens opened from the Calories screen's toolbar.
enum CaloriesScreen: Hashable {
    case savedFoods
    case dailyCalorieSettings
    case schedules
}

/// The app's root: one navigation stack on the Calories screen (what the cat has eaten today,
/// with Mochi at the top). Weight, profile and Settings are pushed onto the same stack.
struct CaloriesView: View {
    @Environment(MochiHome.self) private var home

    var body: some View {
        @Bindable var home = home
        NavigationStack(path: $home.path) {
            DayLogView()
                .navigationDestination(for: AppScreen.self) { screen in
                    switch screen {
                    case .weight: WeightView()
                    case .profile: MochiView()
                    case .settings: SettingsView()
                    }
                }
        }
    }
}

/// One day's food log: the total, then each entry. Arrows (or a swipe on the total) move
/// between days: back to any earlier day, and forward up to the last future day that has
/// entries (such as the rest of an opened can).
struct DayLogView: View {
    @State private var day = Calendar.current.startOfDay(for: .now)
    @Environment(MochiHome.self) private var home
    @Environment(\.modelContext) private var modelContext
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
        @Bindable var home = home
        DayEntriesList(day: day, isFuture: isFuture, dayControls: dayControls, onSwipe: move(by:))
            .navigationTitle(title)
            .toolbar {
                // High priority: these stay visible as their own buttons, never in an overflow
                // menu (conventions, "Controls stay visible").
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
                .visibilityPriority(.high)
                // The one primary action: a filled pill, outermost on the right (or at the end of
                // a vertical bar), on every day. The highest priority of all.
                ToolbarItem(placement: .topBarTrailing) {
                    // System toolbar styling only, so the glass hugs the whole label.
                    Button("Log Food", systemImage: "plus") { home.openLogFood() }
                        .labelStyle(.titleAndIcon)
                        .buttonStyle(.glassProminent)
                        .tint(.accentColor)
                        .fixedSize()
                        .accessibilityLabel("Log Food")
                        .accessibilityHint(isToday ? "Opens search and camera logging for today"
                                                   : "Opens search and camera logging for \(title)")
                        .accessibilityIdentifier("logFoodButton")
                }
                .visibilityPriority(ToolbarItemVisibilityPriority(higherThan: .high))
            }
            // Where the toolbar is, for Mochi's layer outside the stack: the content's left and
            // right safe-area insets (larger when bars are vertical at the side). Only values
            // that never change while scrolling.
            .onGeometryChange(for: [CGFloat].self) { proxy in
                [proxy.safeAreaInsets.leading, proxy.safeAreaInsets.trailing]
            } action: { insets in
                home.toolbarPlacement.leadingInset = insets[0]
                home.toolbarPlacement.trailingInset = insets[1]
            }
            .background {
                if #available(iOS 27.1, *) {
                    ToolbarVerticalEdgeReader { home.toolbarPlacement.isVertical = $0 }
                }
            }
            .sheet(isPresented: $home.isLoggingFood) {
                LogFoodFlowView(day: day)
            }
            // Mochi eats after a food is logged, once this screen is showing again.
            .onChange(of: home.isLoggingFood) { _, isLogging in
                if !isLogging { home.playEatingIfPending() }
            }
            .onChange(of: home.path.count) { _, count in
                if count == 0 { home.playEatingIfPending() }
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
        // Scheduled meals beyond the 60-day horizon are logged on demand, one day ahead of the
        // day shown, so forward navigation never reaches an empty scheduled day.
        if days > 0, let next = calendar.date(byAdding: .day, value: 1, to: newDay),
           next > ScheduleMaterializer(context: modelContext).horizon() {
            ScheduleMaterializer(context: modelContext).materialize(through: next)
        }
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
    @Environment(MochiHome.self) private var home
    @Query private var entries: [FoodLogEntry]
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

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The chart's height in the split layout's trailing pane: the room left under the summary,
    /// at least 200 pt.
    @State private var chartHeight = CalorieChartView.defaultChartHeight

    var body: some View {
        // The shared fold-aware root: measures the window and the fold, draws the one background
        // (the lists hide their own, so nothing shows at the fold) and passes the layout down.
        FoldAwareContainer { foldLayout in
            let layout = CaloriesLayout(foldLayout, isRegularWidth: sizeClass == .regular, margin: AdaptiveLayout.minimumMargin)
            CalorieTargetReader { target in
                content(target: target, layout: layout, foldLayout: foldLayout)
            }
            .animation(reduceMotion ? nil : .default, value: layout)
            // Floating Mochi keeps out of whichever fold band the layout uses (in window points).
            .onChange(of: layout.foldBand.map { $0.offsetBy(dx: -foldLayout.container.minX, dy: -foldLayout.container.minY) },
                      initial: true) { _, band in
                home.calorieFoldBand = band
            }
        }
        // Outside the layout switch, so folding, unfolding or turning keeps an open sheet.
        .onChange(of: entryBeingEdited != nil) { _, isEditing in home.isEditingEntry = isEditing }
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
                ScheduleMaterializer.recordDeletion(of: entry, in: modelContext)
                modelContext.delete(entry)
                Persistence.save(modelContext)
            }
            Button(entry.isCarriedForward ? "Remove Only This Day" : "Remove Only This Entry") {
                ScheduleMaterializer.recordDeletion(of: entry, in: modelContext)
                modelContext.delete(entry)
                Persistence.save(modelContext)
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func content(target: CalorieTarget, layout: CaloriesLayout, foldLayout: FoldLayout) -> some View {
        switch layout {
        case let .split(split):
            splitPanes(split, target: target)
        case .singleColumn where layout.stacksAroundFold:
            // iPhone Duo open, turned and partly folded: the same two parts above and below the
            // fold, so nothing sits in the band.
            FoldPanes(layout: foldLayout) { _ in
                List {
                    summarySection(target: target, showsDayControls: true)
                    chartSection(target: target)
                }
            } secondary: { _ in
                List {
                    entriesSection
                }
            }
        case .singleColumn:
            // Today's iPhone layout at the full available width (also iPhone Duo closed, and open
            // and turned).
            List {
                summarySection(target: target, showsDayControls: true)
                entriesSection
                chartSection(target: target)
            }
        }
    }

    /// Two panes meeting at the fold: the day's foods on the leading side (under the date
    /// controls), the summary and the chart on the trailing side, each scrolling on its own.
    /// Nothing is drawn in the fold band, and the lists draw no background of their own: the
    /// screen's one background (`FoldAwareContainer`) shows through both and the band. Each pane's list sets its margins
    /// from the layout: the standard margin from the band, and the trailing pane's also clear the
    /// action bar. VoiceOver reads the food list, then the summary, then the chart.
    private func splitPanes(_ split: CaloriesLayout.Split, target: CalorieTarget) -> some View {
        // The root's origin (x = 0) is the safe area's leading edge, as in the layout's rects.
        HStack(spacing: 0) {
            List {
                entriesSection
            }
            .contentMargins(.leading, split.leadingMargins.leading, for: .scrollContent)
            .contentMargins(.trailing, split.leadingMargins.trailing, for: .scrollContent)
            .safeAreaInset(edge: .top, spacing: 0) {
                dayControls
                    .padding(.horizontal, AdaptiveLayout.minimumMargin)
                    .padding(.vertical, 8)
                    .contentShape(.rect)
                    .gesture(swipeBetweenDays)
            }
            .frame(width: max(0, split.foldBand.minX))

            // The fold band: empty and transparent.
            Color.clear
                .frame(width: split.foldBand.width)
                .accessibilityHidden(true)

            List {
                summarySection(target: target, showsDayControls: false)
                chartSection(target: target, chartHeight: chartHeight)
            }
            .contentMargins(.leading, split.trailingMargins.leading, for: .scrollContent)
            .contentMargins(.trailing, split.trailingMargins.trailing, for: .scrollContent)
            // The chart takes the height the summary leaves (at least 200 pt); with large text or
            // a short window the pane scrolls instead.
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.containerSize.height - geometry.contentInsets.top - geometry.contentInsets.bottom
                    - geometry.contentSize.height
            } action: { _, room in
                let height = max(CalorieChartView.defaultChartHeight, (chartHeight + room).rounded())
                if abs(height - chartHeight) >= 1 { chartHeight = height }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// The day's calories against the target, with the day arrows when they aren't shown above
    /// the food list (split layout).
    private func summarySection(target: CalorieTarget, showsDayControls: Bool) -> some View {
        Section {
            VStack(spacing: 12) {
                if showsDayControls {
                    dayControls
                }
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
    }

    private var entriesSection: some View {
        Section {
            if entries.isEmpty {
                ContentUnavailableView(
                    "Nothing logged",
                    systemImage: "fork.knife",
                    description: Text("Tap Log Food to log something \(catName) ate.")
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
    }

    private func chartSection(target: CalorieTarget, chartHeight: CGFloat = CalorieChartView.defaultChartHeight) -> some View {
        Section("Daily Calories") {
            CalorieChartView(target: target, chartHeight: chartHeight)
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
            // Deleting a scheduled day skips it for good (a tombstone on its schedule).
            ScheduleMaterializer.recordDeletion(of: entry, in: modelContext)
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

    static let spacing: CGFloat = 12
    /// Width of the icon slot in the "From a can opened…" and "Scheduled" lines.
    static let iconSlotWidth: CGFloat = 16

    var body: some View {
        HStack(spacing: Self.spacing) {
            FoodThumbnail(libraryIdentifier: entry.foodLibraryIdentifier, kind: entry.kind, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.foodName)
                    .lineLimit(2)
                Text([entry.amountDescription, entry.isScheduled ? nil : entry.loggedAt.formatted(date: .omitted, time: .shortened)]
                    .compactMap(\.self).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if entry.isCarriedForward, let openedAt = entry.openedAt {
                    indicator("arrow.turn.down.right",
                              "From a \(entry.containerName) opened \(openedAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))")
                }
                if entry.isScheduled {
                    indicator("repeat", "Scheduled")
                        .accessibilityLabel("Added by a feeding schedule")
                }
            }
            Spacer()
            Text("\(Portion.formatKilocalories(entry.kilocalories)) kcal")
                .monospacedDigit()
        }
        // One separator for every row, set explicitly at the text column (carried and scheduled
        // rows included).
        .rowSeparatorAligned(leading: thumbnailRowSeparatorLeading)
        .accessibilityValue(entry.kind.displayName)
    }

    /// A small icon in a fixed-width slot, centred on its caption line, then the caption.
    private func indicator(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .center, spacing: 4) {
            Image(systemName: symbol)
                .frame(width: Self.iconSlotWidth)
                .accessibilityHidden(true)
            Text(text)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

/// Reports whether the toolbar is placed vertically at the side (iOS 27.1: iPhone Duo's outer
/// display, turned), so Mochi's area doesn't reserve a button row at the top.
@available(iOS 27.1, *)
private struct ToolbarVerticalEdgeReader: View {
    let onChange: (Bool) -> Void

    @Environment(\.toolbarVerticalEdge) private var verticalEdge

    var body: some View {
        Color.clear
            .onChange(of: verticalEdge != nil, initial: true) { _, isVertical in onChange(isVertical) }
    }
}
