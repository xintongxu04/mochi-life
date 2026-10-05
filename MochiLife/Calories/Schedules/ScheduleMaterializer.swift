import Foundation
import os
import SwiftData

/// Turns feeding schedules into ordinary log entries: one entry per schedule per chosen day,
/// from the start date through the end date (or, for open-ended schedules, through a rolling
/// horizon of 60 days ahead), past, today and future alike. There's no hold, confirmation or
/// time-of-day gate.
///
/// **Idempotency key:** (schedule ID, `scheduledDay`), the start of the day an entry was made
/// for. Before inserting, the schedule's entries are fetched and any day that already has one is
/// skipped, so re-running (launch, day change, restore, edits) never duplicates.
///
/// **Overrides win:** a day whose scheduled entry the owner deleted is kept in the schedule's
/// `skippedDays` (a tombstone) and never recreated; an entry the owner edited is marked
/// `isScheduleOverridden` and never updated or removed by schedule edits.
@MainActor
struct ScheduleMaterializer {
    /// Days ahead kept materialized for open-ended (and long) schedules.
    static let horizonDays = 60
    nonisolated static let logger = Logger(subsystem: "com.xintongxu.MochiLife", category: "schedules")

    let context: ModelContext
    var calendar: Calendar = .current

    /// The last day materialized by default: today + 60 days.
    func horizon(from date: Date = .now) -> Date {
        let today = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: Self.horizonDays, to: today) ?? today
    }

    /// Every chosen day of `schedule` from its start through `last` (or its end date if sooner).
    static func days(for schedule: FeedingSchedule, through last: Date, calendar: Calendar = .current) -> [Date] {
        var end = calendar.startOfDay(for: last)
        if let endDate = schedule.endDate { end = min(end, calendar.startOfDay(for: endDate)) }
        var days: [Date] = []
        var day = calendar.startOfDay(for: schedule.startDate)
        while day <= end {
            if schedule.applies(on: day, calendar: calendar) { days.append(day) }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = calendar.startOfDay(for: next)
        }
        return days
    }

    /// Adds the missing entries for every schedule that isn't paused, through the horizon (or
    /// `through`, if later, for a day navigated to beyond it). Saves through the shared helper.
    /// Returns how many entries were added.
    @discardableResult
    func materialize(through requested: Date? = nil) -> Int {
        let last = max(horizon(), requested.map { calendar.startOfDay(for: $0) } ?? .distantPast)
        var schedules = (try? context.fetch(FetchDescriptor<FeedingSchedule>(predicate: #Predicate { !$0.isPaused }))) ?? []
        if schedules.contains(where: { $0.skippedDaysStorage == nil }) {
            // Not converted yet (normally done by the migration): convert before filling in.
            ScheduleUpgrade.run(in: context, calendar: calendar)
            schedules = schedules.filter { $0.skippedDaysStorage != nil }
        }
        var added = 0
        for schedule in schedules {
            let existing = Set(entries(of: schedule.id).map(day(of:)))
            let skipped = Set(schedule.skippedDays.map { calendar.startOfDay(for: $0) })
            for day in Self.days(for: schedule, through: last, calendar: calendar)
            where !existing.contains(day) && !skipped.contains(day) {
                context.insert(schedule.makeEntry(for: day, calendar: calendar))
                added += 1
            }
            if schedule.lastMaterializedDay.map({ $0 < last }) ?? true {
                schedule.lastMaterializedDay = last
            }
        }
        if added > 0 || context.hasChanges {
            Persistence.save(context)
        }
        if added > 0 { Self.logger.info("Added \(added) scheduled entries") }
        return added
    }

    /// After a schedule is saved or edited: entries from today on (that the owner hasn't
    /// changed) are updated to match, entries for days no longer in range are removed, and days
    /// newly in range, past ones included, are filled in. Past entries keep what was logged.
    func scheduleChanged(_ schedule: FeedingSchedule) {
        let today = calendar.startOfDay(for: .now)
        for entry in entries(of: schedule.id) where !entry.isScheduleOverridden {
            let entryDay = day(of: entry)
            guard entryDay >= today else { continue }
            if schedule.isPaused || !schedule.applies(on: entryDay, calendar: calendar) {
                context.delete(entry)
            } else {
                schedule.update(entry)
            }
        }
        materialize()
    }

    /// Before a schedule is deleted (or when it's paused): removes its entries from today on,
    /// except ones the owner changed. Past days keep their entries.
    func removeUpcomingEntries(of schedule: FeedingSchedule) {
        let today = calendar.startOfDay(for: .now)
        for entry in entries(of: schedule.id) where !entry.isScheduleOverridden && day(of: entry) >= today {
            context.delete(entry)
        }
    }

    /// Resuming a paused schedule: days it missed while paused stay empty (they become
    /// tombstones), and it continues from today.
    func resume(_ schedule: FeedingSchedule) {
        let today = calendar.startOfDay(for: .now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return }
        let existing = Set(entries(of: schedule.id).map(day(of:)))
        var skipped = Set(schedule.skippedDays.map { calendar.startOfDay(for: $0) })
        for day in Self.days(for: schedule, through: yesterday, calendar: calendar) where !existing.contains(day) {
            skipped.insert(day)
        }
        schedule.skippedDays = skipped.sorted()
        schedule.isPaused = false
    }

    /// The owner deleted a scheduled entry: remember that day so it isn't recreated.
    static func recordDeletion(of entry: FoodLogEntry, in context: ModelContext, calendar: Calendar = .current) {
        guard let scheduleID = entry.scheduleID else { return }
        let target: UUID = scheduleID
        guard let schedule = try? context.fetch(FetchDescriptor<FeedingSchedule>(predicate: #Predicate { $0.id == target })).first
        else { return }
        let day = entry.scheduledDay.map { calendar.startOfDay(for: $0) } ?? calendar.startOfDay(for: entry.loggedAt)
        if !schedule.skippedDays.contains(where: { calendar.isDate($0, inSameDayAs: day) }) {
            schedule.skippedDays.append(day)
        }
    }

    // MARK: - Helpers

    private func entries(of scheduleID: UUID) -> [FoodLogEntry] {
        let target: UUID? = scheduleID
        return (try? context.fetch(FetchDescriptor<FoodLogEntry>(predicate: #Predicate { $0.scheduleID == target }))) ?? []
    }

    /// The day an entry belongs to for the idempotency key.
    private func day(of entry: FoodLogEntry) -> Date {
        calendar.startOfDay(for: entry.scheduledDay ?? entry.loggedAt)
    }
}

/// One-time conversion of schedules and entries from before V6, where skipping a day meant
/// deleting its entry and relying on "materialized up to" never going back. Runs in the V5 → V6
/// migration, after a restore and at launch; only touches what hasn't been converted.
/// - Scheduled entries without `scheduledDay` get the start of their `loggedAt` day.
/// - Schedules without `skippedDays` (nil) get a tombstone for every chosen day from the start
///   through their old `lastMaterializedDay` that has no entry (deleted, paused or beyond the old
///   60-day catch-up), so nothing the owner removed comes back.
nonisolated enum ScheduleUpgrade {
    static func run(in context: ModelContext, calendar: Calendar = .current) {
        let entries = (try? context.fetch(FetchDescriptor<FoodLogEntry>())) ?? []
        var daysBySchedule: [UUID: Set<Date>] = [:]
        for entry in entries {
            guard let scheduleID = entry.scheduleID else { continue }
            if entry.scheduledDay == nil { entry.scheduledDay = calendar.startOfDay(for: entry.loggedAt) }
            daysBySchedule[scheduleID, default: []].insert(calendar.startOfDay(for: entry.scheduledDay ?? entry.loggedAt))
        }
        let schedules = (try? context.fetch(FetchDescriptor<FeedingSchedule>())) ?? []
        for schedule in schedules where schedule.skippedDaysStorage == nil {
            var skipped: [Date] = []
            if let last = schedule.lastMaterializedDay {
                let existing = daysBySchedule[schedule.id] ?? []
                var end = calendar.startOfDay(for: last)
                if let endDate = schedule.endDate { end = min(end, calendar.startOfDay(for: endDate)) }
                var day = calendar.startOfDay(for: schedule.startDate)
                while day <= end {
                    if schedule.applies(on: day, calendar: calendar) && !existing.contains(day) { skipped.append(day) }
                    guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                    day = calendar.startOfDay(for: next)
                }
            }
            schedule.skippedDaysStorage = skipped
        }
    }
}
