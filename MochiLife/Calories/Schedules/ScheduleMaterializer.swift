import Foundation
import os
import SwiftData

/// Turns feeding schedules into log entries, one per selected day, up to today. Never makes
/// entries for future days. Safe to run any number of times: it checks for an existing entry
/// from the same schedule on the same day before adding one, and each schedule's
/// `lastMaterializedDay` only moves forward, so a scheduled entry the owner deleted (to skip
/// that day) isn't made again.
@MainActor
struct ScheduleMaterializer {
    static let catchUpLimit = 60
    nonisolated static let logger = Logger(subsystem: "com.xintongxu.MochiLife", category: "schedules")

    let context: ModelContext
    var calendar: Calendar = .current

    /// The days a schedule still needs entries for, through `date`'s day: from the day after
    /// `lastMaterializedDay` (or the start date) to today (or the end date), selected weekdays
    /// only, and at most the last 60 calendar days. `skippedDays` counts days dropped by the cap.
    static func pendingDays(for schedule: FeedingSchedule, through date: Date,
                            calendar: Calendar = .current) -> (days: [Date], skippedDays: Int) {
        let today = calendar.startOfDay(for: date)
        var first = calendar.startOfDay(for: schedule.startDate)
        if let last = schedule.lastMaterializedDay,
           let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: last)), next > first {
            first = next
        }
        var lastDay = today
        if let end = schedule.endDate { lastDay = min(lastDay, calendar.startOfDay(for: end)) }
        guard first <= lastDay else { return ([], 0) }

        var skippedDays = 0
        if let earliest = calendar.date(byAdding: .day, value: -(catchUpLimit - 1), to: lastDay), first < earliest {
            skippedDays = calendar.dateComponents([.day], from: first, to: earliest).day ?? 0
            first = earliest
        }
        var days: [Date] = []
        var day = first
        while day <= lastDay {
            if schedule.applies(on: day, calendar: calendar) { days.append(day) }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = calendar.startOfDay(for: next)
        }
        return (days, skippedDays)
    }

    /// Makes the missing entries for every schedule that isn't paused, through `date`, and
    /// saves through the shared save helper. Returns how many entries were added.
    @discardableResult
    func materialize(through date: Date = .now) -> Int {
        let schedules = (try? context.fetch(FetchDescriptor<FeedingSchedule>(predicate: #Predicate { !$0.isPaused }))) ?? []
        let today = calendar.startOfDay(for: date)
        var added = 0
        var changed = false
        for schedule in schedules {
            let (days, skipped) = Self.pendingDays(for: schedule, through: date, calendar: calendar)
            if skipped > 0 {
                Self.logger.notice("Schedule catch-up limited to \(Self.catchUpLimit) days; \(skipped) earlier days skipped")
            }
            if !days.isEmpty {
                let existing = existingDays(for: schedule.id)
                for day in days where !existing.contains(day) {
                    context.insert(schedule.makeEntry(for: day, calendar: calendar))
                    added += 1
                }
            }
            if schedule.lastMaterializedDay.map({ $0 < today }) ?? true {
                schedule.lastMaterializedDay = today
                changed = true
            }
        }
        if added > 0 || changed {
            Persistence.save(context)
        }
        if added > 0 { Self.logger.info("Added \(added) scheduled entries") }
        return added
    }

    /// Start of each day that already has an entry from this schedule.
    private func existingDays(for scheduleID: UUID) -> Set<Date> {
        let target: UUID? = scheduleID
        let entries = (try? context.fetch(FetchDescriptor<FoodLogEntry>(predicate: #Predicate { $0.scheduleID == target }))) ?? []
        return Set(entries.map { calendar.startOfDay(for: $0.loggedAt) })
    }
}
