import Foundation
import SwiftData
import SwiftUI

/// Mochi's basic facts. There is only ever one profile; every field is optional.
@Model
final class CatProfile {
    var name: String?
    @Attribute(.externalStorage) var photoData: Data?
    var birthday: Date?
    var birthdayPrecisionRawValue: String = BirthdayPrecision.exact.rawValue
    var breed: String?
    var colorAndMarkings: String?
    var sexRawValue: String?
    var spayedOrNeuteredRawValue: String?
    var microchipNumber: String?
    var notes: String?
    /// Nil for the profile created before this was recorded (it is the oldest).
    var createdAt: Date?

    init(createdAt: Date = .now) {
        self.createdAt = createdAt
    }

    static let defaultName = "Mochi"

    /// The cat's name, or "Mochi" when none is set.
    var displayName: String {
        guard let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return Self.defaultName }
        return name
    }

    /// The single profile: fetches it, creating one if there is none. If more than one exists,
    /// keeps the oldest and deletes the others (nothing is merged).
    @MainActor
    static func current(in context: ModelContext) -> CatProfile {
        let profiles = (try? context.fetch(FetchDescriptor<CatProfile>())) ?? []
        guard let oldest = profiles.sortedOldestFirst().first else {
            let profile = CatProfile()
            context.insert(profile)
            Persistence.save(context)
            return profile
        }
        let extras = profiles.filter { $0 !== oldest }
        if !extras.isEmpty {
            extras.forEach(context.delete)
            Persistence.logger.notice("Removed \(extras.count) extra cat profile(s)")
            Persistence.save(context)
        }
        return oldest
    }

    var birthdayPrecision: BirthdayPrecision {
        get { BirthdayPrecision(rawValue: birthdayPrecisionRawValue) ?? .exact }
        set { birthdayPrecisionRawValue = newValue.rawValue }
    }

    var sex: CatSex? {
        get { sexRawValue.flatMap(CatSex.init(rawValue:)) }
        set { sexRawValue = newValue?.rawValue }
    }

    var spayedOrNeutered: YesNoUnsure? {
        get { spayedOrNeuteredRawValue.flatMap(YesNoUnsure.init(rawValue:)) }
        set { spayedOrNeuteredRawValue = newValue?.rawValue }
    }
}

extension EnvironmentValues {
    /// The cat's name for user-facing text, or "Mochi" when none is set. Provided by ContentView.
    @Entry var catName = CatProfile.defaultName
}

extension Array where Element == CatProfile {
    /// Oldest first; profiles without a creation date count as oldest.
    func sortedOldestFirst() -> [CatProfile] {
        sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }

    /// The profile in use, from a `@Query` of all profiles.
    var current: CatProfile? { sortedOldestFirst().first }
}

enum BirthdayPrecision: String, CaseIterable, Identifiable {
    case exact
    case approximate
    case yearOnly

    var id: Self { self }

    var label: String {
        switch self {
        case .exact: "Exact"
        case .approximate: "Roughly"
        case .yearOnly: "Year only"
        }
    }
}

enum CatSex: String, CaseIterable, Identifiable {
    case female
    case male

    var id: Self { self }
    var label: String { rawValue.capitalized }
}

enum YesNoUnsure: String, CaseIterable, Identifiable {
    case yes
    case no
    case notSure

    var id: Self { self }

    var label: String {
        switch self {
        case .yes: "Yes"
        case .no: "No"
        case .notSure: "Not sure"
        }
    }
}

@Model
final class Vaccination {
    var name: String
    var dateGiven: Date
    var nextDue: Date?
    var notes: String?

    init(name: String, dateGiven: Date, nextDue: Date? = nil, notes: String? = nil) {
        self.name = name
        self.dateGiven = dateGiven
        self.nextDue = nextDue
        self.notes = notes
    }

    enum DueStatus {
        case overdue
        case dueSoon
    }

    /// Whether the next-due date has passed, or falls within the next 30 days.
    func dueStatus(now: Date = .now, calendar: Calendar = .current) -> DueStatus? {
        guard let nextDue else { return nil }
        let today = calendar.startOfDay(for: now)
        let dueDay = calendar.startOfDay(for: nextDue)
        if dueDay < today { return .overdue }
        if let soon = calendar.date(byAdding: .day, value: 30, to: today), dueDay <= soon { return .dueSoon }
        return nil
    }
}

@Model
final class MedicalRecord {
    var date: Date
    var title: String
    var kindRawValue: String
    var clinic: String?
    var notes: String?

    init(date: Date, title: String, kind: MedicalRecordKind, clinic: String? = nil, notes: String? = nil) {
        self.date = date
        self.title = title
        self.kindRawValue = kind.rawValue
        self.clinic = clinic
        self.notes = notes
    }

    var kind: MedicalRecordKind {
        get { MedicalRecordKind(rawValue: kindRawValue) ?? .other }
        set { kindRawValue = newValue.rawValue }
    }
}

enum MedicalRecordKind: String, CaseIterable, Identifiable {
    case vetVisit
    case illness
    case injury
    case surgery
    case medication
    case other

    var id: Self { self }

    var label: String {
        switch self {
        case .vetVisit: "Vet visit"
        case .illness: "Illness"
        case .injury: "Injury"
        case .surgery: "Surgery"
        case .medication: "Medication"
        case .other: "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .vetVisit: "stethoscope"
        case .illness: "thermometer.medium"
        case .injury: "bandage"
        case .surgery: "scissors"
        case .medication: "pills"
        case .other: "doc.text"
        }
    }
}

enum CatAge {
    /// Like "3 years, 4 months". Year-only birthdays give whole years, and rough or year-only
    /// birthdays start with "About".
    static func description(birthday: Date, precision: BirthdayPrecision, now: Date = .now,
                            calendar: Calendar = .current) -> String? {
        guard birthday <= now else { return nil }
        let parts = calendar.dateComponents([.year, .month], from: birthday, to: now)
        let years = parts.year ?? 0
        let months = parts.month ?? 0
        var text: String
        if precision == .yearOnly {
            let yearGap = calendar.component(.year, from: now) - calendar.component(.year, from: birthday)
            text = yearGap < 1 ? "Under 1 year" : count(yearGap, "year")
        } else if years == 0 && months == 0 {
            text = "Under 1 month"
        } else if years == 0 {
            text = count(months, "month")
        } else if months == 0 {
            text = count(years, "year")
        } else {
            text = "\(count(years, "year")), \(count(months, "month"))"
        }
        if precision != .exact && !text.hasPrefix("Under") {
            text = "About " + text.prefix(1).lowercased() + text.dropFirst()
        }
        return text
    }

    private static func count(_ value: Int, _ unit: String) -> String {
        "\(value) \(unit)\(value == 1 ? "" : "s")"
    }
}
