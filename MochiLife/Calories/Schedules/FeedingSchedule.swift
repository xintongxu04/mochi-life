import Foundation
import SwiftData

/// A food fed on a fixed routine (for example dry food every morning), counted in the food log
/// automatically. Like a log entry, it keeps its own copy of the food's details, so editing or
/// deleting the saved food never changes it.
@Model
final class FeedingSchedule {
    @Attribute(.unique) var id: UUID

    // Food snapshot, copied when the schedule was made.
    var foodName: String
    var foodBrand: String?
    var foodLine: String?
    var foodSeedID: String?
    /// The food's `photoKey`, used only to show its photo.
    var foodPhotoKey: String?
    /// The food's sizes and calories, for editing the amount later.
    var portionSource: PortionSource?
    /// The food's `FoodKind` raw value, given to every entry this schedule makes. (V5)
    var foodKindRawValue: String?

    // Amount, as the size-and-portion picker represents it.
    /// `"containers"` or `"grams"`.
    var measureRawValue: String
    var sizeName: String?
    var containersNumerator: Int?
    var containersDenominator: Int?
    var grams: Double?

    /// Calories each time, worked out when saved (or typed by the owner).
    var kilocaloriesPerOccurrence: Double
    var isKilocaloriesOverridden: Bool = false

    /// Like "Morning kibble".
    var label: String?
    /// Calendar weekdays as bits: bit 0 = Sunday (weekday 1) … bit 6 = Saturday (weekday 7).
    var weekdays: Int
    /// Start of the first day.
    var startDate: Date
    /// Start of the last day, if it ends.
    var endDate: Date?
    var isPaused: Bool = false
    /// The last day entries have been made through (the rolling horizon). Before V6 it also
    /// stood for "skipped": deleted days before it weren't made again; `ScheduleUpgrade`
    /// turned those into tombstones.
    var lastMaterializedDay: Date?
    /// Tombstones: days whose scheduled entry the owner deleted (or that passed while the
    /// schedule was paused). Never recreated. Nil only until `ScheduleUpgrade` has run. (V6)
    var skippedDaysStorage: [Date]?
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), foodName: String, measureRawValue: String, kilocaloriesPerOccurrence: Double,
         weekdays: Int, startDate: Date, createdAt: Date = .now) {
        self.id = id
        self.foodName = foodName
        self.measureRawValue = measureRawValue
        self.kilocaloriesPerOccurrence = kilocaloriesPerOccurrence
        self.weekdays = weekdays
        self.startDate = startDate
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.skippedDaysStorage = []
    }

    /// Copies the food's details.
    func record(_ food: Food) {
        foodName = food.name
        foodBrand = food.brand
        foodLine = food.line
        foodSeedID = food.seedID
        foodPhotoKey = food.photoKey
        portionSource = PortionSource(food)
        foodKindRawValue = food.kind.rawValue
    }

    /// Copies the amount and calories chosen in the picker.
    func record(_ portion: Portion) {
        measureRawValue = portion.measure == .grams ? "grams" : "containers"
        sizeName = portion.measure == .containers ? portion.size?.name : nil
        let exact = portion.exactContainers ?? portion.containers.flatMap { Fraction.nearest(to: $0, maximumDenominator: 1000) }
        containersNumerator = portion.measure == .containers ? exact?.numerator : nil
        containersDenominator = portion.measure == .containers ? exact?.denominator : nil
        grams = portion.measure == .grams ? portion.grams : nil
        kilocaloriesPerOccurrence = portion.kilocalories ?? kilocaloriesPerOccurrence
        isKilocaloriesOverridden = portion.customKilocalories != nil
    }

    var kind: FoodKind {
        FoodKind.stored(foodKindRawValue, hasContainerSizes: !(portionSource?.sizes.isEmpty ?? true))
    }

    /// Days never to fill in (see `skippedDaysStorage`).
    var skippedDays: [Date] {
        get { skippedDaysStorage ?? [] }
        set { skippedDaysStorage = newValue }
    }

    var exactContainers: Fraction? {
        guard let containersNumerator, let containersDenominator, containersDenominator != 0 else { return nil }
        return Fraction(containersNumerator, containersDenominator)
    }

    /// The amount, to start the size-and-portion picker from when editing.
    var portion: Portion? {
        guard let portionSource else { return nil }
        let isGrams = measureRawValue == "grams"
        return Portion(
            measure: isGrams ? .grams : .containers,
            size: portionSource.sizes.first { $0.name == sizeName },
            containers: isGrams ? nil : exactContainers?.doubleValue,
            exactContainers: isGrams ? nil : exactContainers,
            grams: grams,
            calculatedKilocalories: nil,
            customKilocalories: isKilocaloriesOverridden ? kilocaloriesPerOccurrence : nil
        )
    }

    /// Like "1/2 of a 2.8 oz can" or "20 g".
    var amountDescription: String? { portion?.amountDescription }

    /// The label, or the food's name.
    var title: String {
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? foodName : trimmed
    }

    /// Whether the schedule feeds on `day` (ignoring pause and what's already been made).
    func applies(on day: Date, calendar: Calendar = .current) -> Bool {
        let start = calendar.startOfDay(for: startDate)
        let day = calendar.startOfDay(for: day)
        guard day >= start else { return false }
        if let endDate, day > calendar.startOfDay(for: endDate) { return false }
        return Weekdays.contains(weekdays, calendar.component(.weekday, from: day))
    }

    /// A log entry for `day`, with this schedule's food, amount and calories.
    func makeEntry(for day: Date, calendar: Calendar = .current) -> FoodLogEntry {
        let entry = FoodLogEntry(foodName: foodName, kilocalories: kilocaloriesPerOccurrence,
                                 loggedAt: calendar.startOfDay(for: day))
        entry.scheduledDay = calendar.startOfDay(for: day)
        update(entry)
        return entry
    }

    /// Copies this schedule's food, amount, calories and kind into one of its entries.
    func update(_ entry: FoodLogEntry) {
        entry.foodName = foodName
        entry.kilocalories = kilocaloriesPerOccurrence
        entry.foodBrand = foodBrand
        entry.foodLine = foodLine
        entry.foodLibraryIdentifier = foodPhotoKey
        entry.portionSource = portionSource
        entry.measureRawValue = measureRawValue
        entry.sizeName = sizeName
        entry.containers = exactContainers?.doubleValue
        entry.containersNumerator = containersNumerator
        entry.containersDenominator = containersDenominator
        entry.grams = grams
        entry.isCustomKilocalories = isKilocaloriesOverridden
        entry.scheduleID = id
        entry.kindRawValue = kind.rawValue
    }
}

/// The weekday bitmask used by schedules, and how to describe it.
enum Weekdays {
    static let everyDay = 0b111_1111
    /// Monday (weekday 2) to Friday (weekday 6).
    static let weekdaysOnly = 0b011_1110
    static let weekends = 0b100_0001

    static func bit(_ weekday: Int) -> Int { 1 << (weekday - 1) }

    static func contains(_ mask: Int, _ weekday: Int) -> Bool { mask & bit(weekday) != 0 }

    /// Calendar weekdays (1 = Sunday … 7 = Saturday) in the order the calendar starts its week.
    static func ordered(_ calendar: Calendar = .current) -> [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    /// "Every day", "Weekdays", "Weekends", or a short list like "Mon, Wed, Fri".
    static func describe(_ mask: Int, calendar: Calendar = .current) -> String {
        switch mask {
        case everyDay: return "Every day"
        case weekdaysOnly: return "Weekdays"
        case weekends: return "Weekends"
        default:
            return ordered(calendar).filter { contains(mask, $0) }
                .map { calendar.shortWeekdaySymbols[$0 - 1] }
                .joined(separator: ", ")
        }
    }

    /// The full names, for VoiceOver.
    static func spokenDescription(_ mask: Int, calendar: Calendar = .current) -> String {
        switch mask {
        case everyDay, weekdaysOnly, weekends: return describe(mask, calendar: calendar)
        default:
            return ordered(calendar).filter { contains(mask, $0) }
                .map { calendar.weekdaySymbols[$0 - 1] }
                .formatted(.list(type: .and))
        }
    }
}
