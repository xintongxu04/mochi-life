import Foundation
import SwiftData

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

    init() {}

    static let defaultName = "Mochi"

    var displayName: String { name ?? Self.defaultName }

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
