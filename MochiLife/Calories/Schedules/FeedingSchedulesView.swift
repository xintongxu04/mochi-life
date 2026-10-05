import SwiftData
import SwiftUI

/// Feeding schedules: foods fed on a fixed routine and counted automatically. Swipe to pause,
/// resume or delete; tap to edit.
struct FeedingSchedulesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.catName) private var catName
    @Query(sort: [SortDescriptor(\FeedingSchedule.createdAt)]) private var schedules: [FeedingSchedule]
    @State private var isAdding = false
    @State private var scheduleBeingEdited: FeedingSchedule?
    @State private var scheduleBeingDeleted: FeedingSchedule?

    var body: some View {
        List {
            ForEach(schedules) { schedule in
                Button {
                    scheduleBeingEdited = schedule
                } label: {
                    ScheduleRow(schedule: schedule)
                }
                .tint(.primary)
                .swipeActions(edge: .trailing) {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        scheduleBeingDeleted = schedule
                    }
                    .accessibilityLabel("Delete schedule")
                }
                .swipeActions(edge: .leading) {
                    Button(schedule.isPaused ? "Resume" : "Pause",
                           systemImage: schedule.isPaused ? "play.fill" : "pause.fill") {
                        togglePause(schedule)
                    }
                    .tint(schedule.isPaused ? .green : .orange)
                    .accessibilityLabel(schedule.isPaused ? "Resume schedule" : "Pause schedule")
                }
                .accessibilityIdentifier("scheduleRow")
            }
        }
        .overlay {
            if schedules.isEmpty {
                ContentUnavailableView {
                    Label("No Schedules", systemImage: "calendar.badge.clock")
                } description: {
                    Text("Add food \(catName) gets on a routine, like morning kibble, and it's counted every day without logging it.")
                } actions: {
                    Button("Add a Schedule") { isAdding = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Schedules")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Schedule", systemImage: "plus") { isAdding = true }
            }
        }
        .sheet(isPresented: $isAdding) {
            NavigationStack {
                SavedFoodsView(mode: .schedule(onFinish: { isAdding = false }))
                    .savedFoodsDestinations(mode: .schedule(onFinish: { isAdding = false }))
            }
            .environment(\.isPickingFood, true)
        }
        .sheet(item: $scheduleBeingEdited) { schedule in
            NavigationStack {
                ScheduleEditorView(mode: .edit(schedule)) { scheduleBeingEdited = nil }
            }
        }
        .confirmationDialog(
            "Delete this schedule?",
            isPresented: Binding(get: { scheduleBeingDeleted != nil }, set: { if !$0 { scheduleBeingDeleted = nil } }),
            titleVisibility: .visible,
            presenting: scheduleBeingDeleted
        ) { schedule in
            Button("Delete Schedule", role: .destructive) {
                ScheduleMaterializer(context: modelContext).removeUpcomingEntries(of: schedule)
                modelContext.delete(schedule)
                Persistence.save(modelContext)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Its entries from today on are removed. Past entries stay in the food log.")
        }
    }

    /// Pausing removes the entries from today on (except days you changed). Resuming fills in
    /// from today on again; the days that passed while paused stay empty.
    private func togglePause(_ schedule: FeedingSchedule) {
        let materializer = ScheduleMaterializer(context: modelContext)
        if schedule.isPaused {
            materializer.resume(schedule)
        } else {
            schedule.isPaused = true
            materializer.removeUpcomingEntries(of: schedule)
        }
        schedule.updatedAt = .now
        guard Persistence.save(modelContext) else { return }
        materializer.materialize()
    }
}

private struct ScheduleRow: View {
    let schedule: FeedingSchedule

    var body: some View {
        HStack(spacing: 12) {
            FoodThumbnail(libraryIdentifier: schedule.foodPhotoKey, kind: schedule.kind, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(schedule.title)
                    .lineLimit(2)
                if schedule.label != nil {
                    Text(schedule.foodName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text([schedule.amountDescription, Weekdays.describe(schedule.weekdays)].compactMap(\.self).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel([schedule.amountDescription, Weekdays.spokenDescription(schedule.weekdays)]
                        .compactMap(\.self).joined(separator: ", "))
                if schedule.isPaused {
                    HStack(spacing: 4) {
                        Image(systemName: "pause.circle")
                            .frame(width: 16)
                            .accessibilityHidden(true)
                        Text("Paused")
                    }
                    .font(.caption2)
                    .foregroundStyle(.orange)
                } else if let endDate = schedule.endDate {
                    Text("Until \(endDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("\(Portion.formatKilocalories(schedule.kilocaloriesPerOccurrence)) kcal")
                .monospacedDigit()
                .foregroundStyle(schedule.isPaused ? .secondary : .primary)
        }
        .rowSeparatorAligned(leading: thumbnailRowSeparatorLeading)
        .accessibilityElement(children: .combine)
        .accessibilityValue(schedule.kind.displayName)
    }
}
