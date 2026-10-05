import Foundation
import SwiftData

// Every change to a saved (@Model) type needs a new VersionedSchema and a MigrationStage in
// MochiLifeMigrationPlan. Earlier versions keep frozen copies of their models so old stores can
// still be recognized and upgraded. The live model types are always the latest version's.

/// Version 5 (current): adds `FoodLogEntry.kindRawValue` and `FeedingSchedule.foodKindRawValue`
/// (both optional), and the foods' single "food" kind is split into kibble and wet food. The live
/// model types are this version.
enum SchemaV5: VersionedSchema {
    static let versionIdentifier = Schema.Version(5, 0, 0)

    static var models: [any PersistentModel.Type] {
        [WeightEntry.self, Food.self, FoodLogEntry.self, CatProfile.self, Vaccination.self, MedicalRecord.self,
         FeedingSchedule.self]
    }
}

enum MochiLifeMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self, SchemaV5.self]
    }

    static var stages: [MigrationStage] {
        [
            // Only adds optional or defaulted properties, so no data has to be transformed here.
            // Data fixes that need the bundled food file run at launch (see LaunchMaintenance).
            .lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self),
            // Only adds two optional Food properties.
            .lightweight(fromVersion: SchemaV2.self, toVersion: SchemaV3.self),
            // Adds a new model and one optional FoodLogEntry property; existing entries get nil
            // (logged by hand), so they keep their meaning.
            .lightweight(fromVersion: SchemaV3.self, toVersion: SchemaV4.self),
            // Adds two optional properties, then assigns every food, entry and schedule its kind
            // (see FoodKindBackfill for the rules). Nothing is removed.
            .custom(fromVersion: SchemaV4.self, toVersion: SchemaV5.self, willMigrate: nil, didMigrate: { context in
                FoodKindBackfill.run(in: context)
                try context.save()
            }),
        ]
    }
}

/// Version 4: adds `FeedingSchedule` and `FoodLogEntry.scheduleID`. FoodLogEntry and
/// FeedingSchedule are frozen copies (they changed in V5); the other models are the live types
/// (unchanged since V4). Don't change the frozen copies.
enum SchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(4, 0, 0)

    static var models: [any PersistentModel.Type] {
        [WeightEntry.self, Food.self, FoodLogEntry.self, CatProfile.self, Vaccination.self, MedicalRecord.self,
         FeedingSchedule.self]
    }

    @Model
    final class FoodLogEntry {
        var loggedAt: Date
        var foodName: String
        var foodBrand: String?
        var foodLine: String?
        var foodLibraryIdentifier: String?
        var portionSource: PortionSource?
        var measureRawValue: String?
        var sizeName: String?
        var containers: Double?
        var grams: Double?
        var containersNumerator: Int?
        var containersDenominator: Int?
        var kilocalories: Double
        var isCustomKilocalories: Bool = false
        var createdAt: Date
        var carryGroupID: UUID?
        var carryDay: Int = 0
        var openedAt: Date?
        var scheduleID: UUID?

        init(foodName: String, kilocalories: Double, loggedAt: Date, createdAt: Date) {
            self.foodName = foodName
            self.kilocalories = kilocalories
            self.loggedAt = loggedAt
            self.createdAt = createdAt
        }
    }

    @Model
    final class FeedingSchedule {
        @Attribute(.unique) var id: UUID
        var foodName: String
        var foodBrand: String?
        var foodLine: String?
        var foodSeedID: String?
        var foodPhotoKey: String?
        var portionSource: PortionSource?
        var measureRawValue: String
        var sizeName: String?
        var containersNumerator: Int?
        var containersDenominator: Int?
        var grams: Double?
        var kilocaloriesPerOccurrence: Double
        var isKilocaloriesOverridden: Bool = false
        var label: String?
        var weekdays: Int
        var startDate: Date
        var endDate: Date?
        var isPaused: Bool = false
        var lastMaterializedDay: Date?
        var createdAt: Date
        var updatedAt: Date

        init(id: UUID, foodName: String, measureRawValue: String, kilocaloriesPerOccurrence: Double,
             weekdays: Int, startDate: Date, createdAt: Date) {
            self.id = id
            self.foodName = foodName
            self.measureRawValue = measureRawValue
            self.kilocaloriesPerOccurrence = kilocaloriesPerOccurrence
            self.weekdays = weekdays
            self.startDate = startDate
            self.createdAt = createdAt
            self.updatedAt = createdAt
        }
    }
}

/// Version 3: Food gains `originRawValue` (seed, manual or AI lookup) and `thumbnailKey` (a photo
/// saved by the app). FoodLogEntry is a frozen copy (it changed in V4); the other models are the
/// live types (unchanged since V3). Don't change the frozen copy.
enum SchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        [WeightEntry.self, Food.self, FoodLogEntry.self, CatProfile.self, Vaccination.self, MedicalRecord.self]
    }

    @Model
    final class FoodLogEntry {
        var loggedAt: Date
        var foodName: String
        var foodBrand: String?
        var foodLine: String?
        var foodLibraryIdentifier: String?
        var portionSource: PortionSource?
        var measureRawValue: String?
        var sizeName: String?
        var containers: Double?
        var grams: Double?
        var containersNumerator: Int?
        var containersDenominator: Int?
        var kilocalories: Double
        var isCustomKilocalories: Bool = false
        var createdAt: Date
        var carryGroupID: UUID?
        var carryDay: Int = 0
        var openedAt: Date?

        init(foodName: String, kilocalories: Double, loggedAt: Date, createdAt: Date) {
            self.foodName = foodName
            self.kilocalories = kilocalories
            self.loggedAt = loggedAt
            self.createdAt = createdAt
        }
    }
}

/// Version 2: Food gained `seedID` (unique) and `isUserModified`; CatProfile gained `createdAt`.
/// Food is a frozen copy (it changed in V3) and FoodLogEntry is V3's frozen copy (it changed in
/// V4); the other models are unchanged since V2, so the live types are used. Don't change the
/// frozen copies.
enum SchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [WeightEntry.self, Food.self, SchemaV3.FoodLogEntry.self, CatProfile.self, Vaccination.self, MedicalRecord.self]
    }

    @Model
    final class Food {
        var name: String
        var kilocaloriesPerGram: Double
        var createdAt: Date
        var brand: String?
        var line: String?
        var kindRawValue: String = "food"
        var sizes: [FoodSize] = []
        var calorieStatement: String?
        var ingredients: String?
        var guaranteedAnalysis: [GuaranteedAnalysisRow] = []
        var notes: [String] = []
        var sourceURL: URL?
        var libraryIdentifier: String?
        @Attribute(.unique) var seedID: String?
        var isUserModified: Bool = false

        init(name: String, kilocaloriesPerGram: Double, createdAt: Date) {
            self.name = name
            self.kilocaloriesPerGram = kilocaloriesPerGram
            self.createdAt = createdAt
        }
    }
}

/// Version 1: the saved-data layout as shipped before schema versioning was added. These are
/// frozen copies; don't change them.
enum SchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [WeightEntry.self, Food.self, FoodLogEntry.self, CatProfile.self, Vaccination.self, MedicalRecord.self]
    }

    @Model
    final class WeightEntry {
        var date: Date
        var kilograms: Double
        var createdAt: Date

        init(date: Date, kilograms: Double, createdAt: Date) {
            self.date = date
            self.kilograms = kilograms
            self.createdAt = createdAt
        }
    }

    @Model
    final class Food {
        var name: String
        var kilocaloriesPerGram: Double
        var createdAt: Date
        var brand: String?
        var line: String?
        var kindRawValue: String = "food"
        var sizes: [FoodSize] = []
        var calorieStatement: String?
        var ingredients: String?
        var guaranteedAnalysis: [GuaranteedAnalysisRow] = []
        var notes: [String] = []
        var sourceURL: URL?
        var libraryIdentifier: String?

        init(name: String, kilocaloriesPerGram: Double, createdAt: Date) {
            self.name = name
            self.kilocaloriesPerGram = kilocaloriesPerGram
            self.createdAt = createdAt
        }
    }

    @Model
    final class FoodLogEntry {
        var loggedAt: Date
        var foodName: String
        var foodBrand: String?
        var foodLine: String?
        var foodLibraryIdentifier: String?
        var portionSource: PortionSource?
        var measureRawValue: String?
        var sizeName: String?
        var containers: Double?
        var grams: Double?
        var containersNumerator: Int?
        var containersDenominator: Int?
        var kilocalories: Double
        var isCustomKilocalories: Bool = false
        var createdAt: Date
        var carryGroupID: UUID?
        var carryDay: Int = 0
        var openedAt: Date?

        init(foodName: String, kilocalories: Double, loggedAt: Date, createdAt: Date) {
            self.foodName = foodName
            self.kilocalories = kilocalories
            self.loggedAt = loggedAt
            self.createdAt = createdAt
        }
    }

    @Model
    final class CatProfile {
        var name: String?
        @Attribute(.externalStorage) var photoData: Data?
        var birthday: Date?
        var birthdayPrecisionRawValue: String = "exact"
        var breed: String?
        var colorAndMarkings: String?
        var sexRawValue: String?
        var spayedOrNeuteredRawValue: String?
        var microchipNumber: String?
        var notes: String?

        init() {}
    }

    @Model
    final class Vaccination {
        var name: String
        var dateGiven: Date
        var nextDue: Date?
        var notes: String?

        init(name: String, dateGiven: Date) {
            self.name = name
            self.dateGiven = dateGiven
        }
    }

    @Model
    final class MedicalRecord {
        var date: Date
        var title: String
        var kindRawValue: String
        var clinic: String?
        var notes: String?

        init(date: Date, title: String, kindRawValue: String) {
            self.date = date
            self.title = title
            self.kindRawValue = kindRawValue
        }
    }
}
