import Foundation
import SwiftData
import UniformTypeIdentifiers

// The backup file format. These Codable types are the stable contract: they map explicitly to
// and from the @Model classes (see BackupMapping.swift) and are never the models themselves.
// Every new persisted field must be added here, to the mapping, and to the round-trip test.

extension UTType {
    /// A Mochi Life backup (.mochibackup), declared in Info.plist.
    static let mochiBackup = UTType(exportedAs: "com.xintongxu.mochilife.backup", conformingTo: .json)
}

enum BackupFormat {
    /// Raise when the file layout changes, and add an upgrade in `BackupDecoder.upgrade`.
    /// 2: adds `schedules` and `FoodLogEntryDTO.scheduleID` (format 1 files are upgraded).
    static let currentFormatVersion = 2
    static let fileExtension = "mochibackup"
    static let maximumFileSize = 100 * 1024 * 1024
    /// The SwiftData schema version the app writes.
    static var currentSchemaVersion: Schema.Version { SchemaV4.versionIdentifier }
}

struct BackupEnvelope: Codable, Sendable, Equatable {
    var formatVersion: Int
    /// The app's SwiftData schema version, e.g. "3.0.0".
    var schemaVersion: String
    var appVersion: String
    var createdAt: Date
    var deviceName: String
    var payload: BackupPayload
    var files: [BackupFile]
}

/// A binary asset, base64-encoded.
struct BackupFile: Codable, Sendable, Equatable {
    enum Role: String, Codable, Sendable {
        /// A food photo file from Application Support/FoodThumbnails; `name` is its file name.
        case foodThumbnail
        /// The cat's profile photo.
        case profilePhoto
    }

    var name: String
    var role: Role
    var base64: String
}

struct BackupPayload: Codable, Sendable, Equatable {
    var weights: [WeightDTO]
    /// Foods added by hand or with AI, in full, plus seeded foods the owner edited
    /// (`isUserModified`), which override the bundled data by `seedID`.
    var foods: [FoodDTO]
    /// Seeded foods the owner deleted, so they aren't re-added after a restore.
    var deletedSeedIDs: [String]
    var foodLog: [FoodLogEntryDTO]
    var profile: ProfileDTO?
    var vaccinations: [VaccinationDTO]
    var medicalRecords: [MedicalRecordDTO]
    /// Feeding schedules (format 2).
    var schedules: [FeedingScheduleDTO]
    var settings: SettingsDTO
}

struct WeightDTO: Codable, Sendable, Equatable {
    var date: Date
    /// Canonical unit: kilograms.
    var kilograms: Double
    var createdAt: Date
}

struct FoodSizeDTO: Codable, Sendable, Equatable {
    var name: String
    var grams: Double
    var kilocalories: Double
    var kilocaloriesPerGram: Double
    var isCalculated: Bool
}

struct AnalysisRowDTO: Codable, Sendable, Equatable {
    var nutrient: String
    var amount: String
}

struct FoodDTO: Codable, Sendable, Equatable {
    var name: String
    var kilocaloriesPerGram: Double
    var createdAt: Date
    var brand: String?
    var line: String?
    var kind: String
    var sizes: [FoodSizeDTO]
    var calorieStatement: String?
    var ingredients: String?
    var guaranteedAnalysis: [AnalysisRowDTO]
    var notes: [String]
    var sourceURL: String?
    var libraryIdentifier: String?
    var seedID: String?
    var isUserModified: Bool
    var origin: String
    /// "user/<name>" (file in `files`), "none", or nil.
    var thumbnailKey: String?
}

struct PortionSourceDTO: Codable, Sendable, Equatable {
    var sizes: [FoodSizeDTO]
    var kilocaloriesPerGram: Double
}

struct FoodLogEntryDTO: Codable, Sendable, Equatable {
    var loggedAt: Date
    var foodName: String
    var foodBrand: String?
    var foodLine: String?
    var foodLibraryIdentifier: String?
    var portionSource: PortionSourceDTO?
    var measure: String?
    var sizeName: String?
    var containers: Double?
    var grams: Double?
    /// Exact fraction of a can or pouch.
    var containersNumerator: Int?
    var containersDenominator: Int?
    var kilocalories: Double
    var isCustomKilocalories: Bool
    var createdAt: Date
    /// Links an opened can's entry and the entries carrying it forward.
    var carryGroupID: UUID?
    var carryDay: Int
    var openedAt: Date?
    /// The feeding schedule that made the entry (format 2); nil for entries logged by hand.
    var scheduleID: UUID?
}

struct FeedingScheduleDTO: Codable, Sendable, Equatable {
    var id: UUID
    var foodName: String
    var foodBrand: String?
    var foodLine: String?
    var foodSeedID: String?
    /// A photo key like the log's `foodLibraryIdentifier` ("user/<name>" files are in `files`).
    var foodPhotoKey: String?
    var portionSource: PortionSourceDTO?
    var measure: String
    var sizeName: String?
    var containersNumerator: Int?
    var containersDenominator: Int?
    var grams: Double?
    var kilocaloriesPerOccurrence: Double
    var isKilocaloriesOverridden: Bool
    var label: String?
    /// Calendar weekdays as bits: bit 0 = Sunday … bit 6 = Saturday.
    var weekdays: Int
    var startDate: Date
    var endDate: Date?
    var isPaused: Bool
    var lastMaterializedDay: Date?
    var createdAt: Date
    var updatedAt: Date
}

struct ProfileDTO: Codable, Sendable, Equatable {
    var name: String?
    /// Name of the `profilePhoto` file in `files`, if there's a photo.
    var photoFile: String?
    var birthday: Date?
    var birthdayPrecision: String
    var breed: String?
    var colorAndMarkings: String?
    var sex: String?
    var spayedOrNeutered: String?
    var microchipNumber: String?
    var notes: String?
    var createdAt: Date?
}

struct VaccinationDTO: Codable, Sendable, Equatable {
    var name: String
    var dateGiven: Date
    var nextDue: Date?
    var notes: String?
}

struct MedicalRecordDTO: Codable, Sendable, Equatable {
    var date: Date
    var title: String
    var kind: String
    var clinic: String?
    var notes: String?
}

/// Settings that change how the app behaves. API keys, AI lookup counters and per-device
/// markers are deliberately left out.
struct SettingsDTO: Codable, Sendable, Equatable {
    var weightUnit: String?
    /// 0 or nil means no own target.
    var ownCalorieTarget: Double?
    var gainsWeightEasily: Bool
}

/// Per-type record counts, for the restore summary.
struct BackupCounts: Sendable, Equatable {
    var weights = 0
    var foods = 0
    var editedSeedFoods = 0
    var deletedSeedFoods = 0
    var foodLog = 0
    var hasProfile = false
    var vaccinations = 0
    var medicalRecords = 0
    var schedules = 0
    var photos = 0

    init() {}

    init(_ payload: BackupPayload, files: [BackupFile]) {
        weights = payload.weights.count
        foods = payload.foods.filter { $0.seedID == nil }.count
        editedSeedFoods = payload.foods.filter { $0.seedID != nil }.count
        deletedSeedFoods = payload.deletedSeedIDs.count
        foodLog = payload.foodLog.count
        hasProfile = payload.profile != nil
        vaccinations = payload.vaccinations.count
        medicalRecords = payload.medicalRecords.count
        schedules = payload.schedules.count
        photos = files.count
    }
}

/// Why a backup couldn't be read or restored, in words the owner can act on.
enum BackupError: Error, Equatable {
    case fileTooLarge
    case unreadableFile
    case notABackup
    case missingField(String)
    case invalidValue(String)
    case newerFormat(Int)
    case newerSchema(String)
    case saveFailed
    case fileWriteFailed

    var message: String {
        switch self {
        case .fileTooLarge: "This file is larger than 100 MB, which is too big to be a Mochi Life backup."
        case .unreadableFile: "The file couldn't be opened. Try saving it to Files and choosing it again."
        case .notABackup: "This file isn't a readable Mochi Life backup (it isn't valid JSON)."
        case let .missingField(field): "The backup is incomplete: “\(field)” is missing."
        case let .invalidValue(detail): "The backup contains a value that isn't allowed: \(detail)."
        case let .newerFormat(version): "This backup was made by a newer version of Mochi Life (format \(version)). Update the app, then try again."
        case let .newerSchema(version): "This backup holds data from a newer version of Mochi Life (data version \(version)). Update the app, then try again."
        case .saveFailed: "The restored data couldn't be saved. Nothing on this iPhone was changed."
        case .fileWriteFailed: "The backup file couldn't be written."
        }
    }
}

/// JSON coding shared by backup writing and reading: ISO 8601 dates (UTC, millisecond
/// precision), sorted keys, and no escaped slashes.
enum BackupCoding {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(isoString(from: date))
        }
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = date(fromISOString: text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an ISO 8601 date: \(text)")
            }
            return date
        }
        return decoder
    }

    /// "2026-10-05T14:30:00.123Z". The date is rounded to the nearest millisecond, and the
    /// milliseconds are written from that whole number, so reading it back and writing it again
    /// always gives the same text (a floating-point date formatted directly can drift by 1 ms).
    static func isoString(from date: Date) -> String {
        let totalMilliseconds = Int64((date.timeIntervalSince1970 * 1000).rounded())
        var seconds = totalMilliseconds / 1000
        var milliseconds = totalMilliseconds % 1000
        if milliseconds < 0 { milliseconds += 1000; seconds -= 1 }
        let whole = Date(timeIntervalSince1970: TimeInterval(seconds)).formatted(.iso8601) // "…T14:30:00Z"
        return String(whole.dropLast()) + String(format: ".%03lldZ", milliseconds)
    }

    /// Reads ISO 8601 dates with or without fractional seconds.
    static func date(fromISOString text: String) -> Date? {
        guard let match = text.wholeMatch(of: /(.+?)(?:\.(\d{1,9}))?Z/),
              let whole = try? Date.ISO8601FormatStyle().parse(String(match.output.1) + "Z")
        else {
            return try? Date.ISO8601FormatStyle().parse(text)
        }
        guard let fraction = match.output.2 else { return whole }
        let digits = String(fraction.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
        let milliseconds = Double(Int(digits) ?? 0)
        let base = Int64(whole.timeIntervalSince1970.rounded())
        return Date(timeIntervalSince1970: (Double(base) * 1000 + milliseconds) / 1000)
    }
}
