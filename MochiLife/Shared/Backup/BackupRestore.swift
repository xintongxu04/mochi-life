import Foundation
import SwiftData

/// A backup that has been fully read, checked and had its photos staged, ready to replace the
/// data on this device. Nothing has been changed yet.
struct PreparedRestore: Sendable {
    var envelope: BackupEnvelope
    /// Temporary folder holding the backup's photo files until the restore commits.
    var stagingDirectory: URL
    var profilePhoto: Data?
    var counts: BackupCounts { BackupCounts(envelope.payload, files: envelope.files) }

    func discardStaging() {
        try? FileManager.default.removeItem(at: stagingDirectory)
    }
}

/// Reads and checks a backup file before anything on the device is touched.
enum BackupReader {
    /// Reads, decodes, upgrades and validates the file, and stages its photos. Runs off the
    /// main actor and stops if the task is cancelled.
    static func prepare(from url: URL) async throws -> PreparedRestore {
        try await Task.detached(priority: .userInitiated) {
            let data = try read(url)
            try Task.checkCancellation()
            let envelope = try decode(data)
            try Task.checkCancellation()
            try validate(envelope)
            return try stage(envelope)
        }.value
    }

    private static func read(_ url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { throw BackupError.unreadableFile }
        guard size <= BackupFormat.maximumFileSize else { throw BackupError.fileTooLarge }
        guard let data = try? Data(contentsOf: url) else { throw BackupError.unreadableFile }
        return data
    }

    private struct Header: Decodable {
        var formatVersion: Int
        var schemaVersion: String
    }

    /// Decodes the envelope, upgrading older format versions and refusing newer ones.
    static func decode(_ data: Data) throws -> BackupEnvelope {
        guard (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else { throw BackupError.notABackup }
        let header: Header
        do {
            header = try BackupCoding.decoder().decode(Header.self, from: data)
        } catch {
            throw translate(error)
        }
        guard header.formatVersion <= BackupFormat.currentFormatVersion else {
            throw BackupError.newerFormat(header.formatVersion)
        }
        guard let schema = Schema.Version(text: header.schemaVersion) else {
            throw BackupError.invalidValue("schema version “\(header.schemaVersion)”")
        }
        guard schema <= BackupFormat.currentSchemaVersion else { throw BackupError.newerSchema(header.schemaVersion) }
        do {
            return try upgrade(data, from: header.formatVersion)
        } catch let error as BackupError {
            throw error
        } catch {
            throw translate(error)
        }
    }

    /// One explicit step per older format version. Version 3 is the current format.
    static func upgrade(_ data: Data, from formatVersion: Int) throws -> BackupEnvelope {
        switch formatVersion {
        case 1:
            // Format 1 had no schedules; log entries had no `scheduleID` (decoded as nil).
            guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  var payload = root["payload"] as? [String: Any]
            else { throw BackupError.notABackup }
            payload["schedules"] = payload["schedules"] ?? [Any]()
            root["payload"] = payload
            root["formatVersion"] = 2
            return try upgrade(JSONSerialization.data(withJSONObject: root), from: 2)
        case 2:
            // Format 2 had no kinds on entries or schedules (they decode as nil) and foods used
            // "food"; FoodKindBackfill assigns them after the restore.
            var envelope = try BackupCoding.decoder().decode(BackupEnvelope.self, from: data)
            envelope.formatVersion = 3
            return envelope
        case 3:
            return try BackupCoding.decoder().decode(BackupEnvelope.self, from: data)
        default:
            throw BackupError.invalidValue("format version \(formatVersion)")
        }
    }

    private static func translate(_ error: Error) -> BackupError {
        switch error {
        case let DecodingError.keyNotFound(key, context):
            return .missingField((context.codingPath.map(\.stringValue) + [key.stringValue]).joined(separator: "."))
        case let DecodingError.valueNotFound(_, context):
            return .missingField(context.codingPath.map(\.stringValue).joined(separator: "."))
        case let DecodingError.typeMismatch(_, context), let DecodingError.dataCorrupted(context):
            return .invalidValue("“\(context.codingPath.map(\.stringValue).joined(separator: "."))”")
        default:
            return .notABackup
        }
    }

    /// Rejects values the app could never have saved.
    static func validate(_ envelope: BackupEnvelope) throws {
        let payload = envelope.payload
        func check(_ condition: Bool, _ detail: @autoclosure () -> String) throws {
            if !condition { throw BackupError.invalidValue(detail()) }
        }
        for weight in payload.weights {
            try check(weight.kilograms > 0 && weight.kilograms <= 200, "a weight of \(weight.kilograms) kg")
        }
        for food in payload.foods {
            try check(!food.name.isEmpty, "a food without a name")
            try check(food.kilocaloriesPerGram > 0 && food.kilocaloriesPerGram <= 100, "\(food.kilocaloriesPerGram) kcal per gram for “\(food.name)”")
            for size in food.sizes {
                try check(size.grams > 0 && size.grams <= 100_000 && size.kilocalories >= 0 && size.kilocalories <= 100_000,
                          "the size “\(size.name)” of “\(food.name)”")
            }
            if let key = food.thumbnailKey, key != FoodThumbnailStore.noPhotoKey {
                try check(FoodThumbnailStore.fileName(forKey: key) != nil || !FoodThumbnailStore.isStoredKey(key),
                          "the photo name of “\(food.name)”")
            }
        }
        for entry in payload.foodLog {
            try check(entry.kilocalories >= 0 && entry.kilocalories <= 100_000, "\(entry.kilocalories) kcal in a log entry")
            try check((entry.containers ?? 0) >= 0 && (entry.grams ?? 0) >= 0, "a negative amount in a log entry")
            try check((entry.containersDenominator ?? 1) > 0, "a fraction with denominator 0 in a log entry")
            try check(entry.carryDay >= 0, "a negative carry-forward day")
            try check(entry.kind.map { FoodKind(rawValue: $0) != nil } ?? true, "the kind “\(entry.kind ?? "")” in a log entry")
        }
        for food in payload.foods {
            try check(FoodKind(rawValue: food.kind) != nil || food.kind == FoodKind.legacyFoodRawValue,
                      "the kind “\(food.kind)” of “\(food.name)”")
        }
        for schedule in payload.schedules {
            try check(!schedule.foodName.isEmpty, "a feeding schedule without a food name")
            try check((1...Weekdays.everyDay).contains(schedule.weekdays), "the days of the schedule for “\(schedule.foodName)”")
            try check(schedule.kilocaloriesPerOccurrence >= 0 && schedule.kilocaloriesPerOccurrence <= 100_000,
                      "\(schedule.kilocaloriesPerOccurrence) kcal in a feeding schedule")
            try check((schedule.containersDenominator ?? 1) > 0 && (schedule.grams ?? 0) >= 0,
                      "the amount of the schedule for “\(schedule.foodName)”")
            try check(schedule.endDate.map { $0 >= schedule.startDate } ?? true, "a schedule that ends before it starts")
        }
        try check(Set(payload.schedules.map(\.id)).count == payload.schedules.count, "two schedules with the same ID")
        if let target = payload.settings.ownCalorieTarget {
            try check(target >= 0 && target <= 5_000, "a daily calorie target of \(target)")
        }
        for file in envelope.files {
            try check(!file.name.isEmpty && !file.name.contains("/") && !file.name.contains(".."), "the file name “\(file.name)”")
            try check(Data(base64Encoded: file.base64) != nil, "the contents of “\(file.name)”")
        }
    }

    /// Decodes photo files into a temporary folder; the profile photo stays in memory.
    private static func stage(_ envelope: BackupEnvelope) throws -> PreparedRestore {
        let staging = URL.temporaryDirectory.appending(path: "restore-\(UUID().uuidString)", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            var profilePhoto: Data?
            for file in envelope.files {
                try Task.checkCancellation()
                guard let data = Data(base64Encoded: file.base64) else { throw BackupError.invalidValue("the contents of “\(file.name)”") }
                switch file.role {
                case .foodThumbnail: try data.write(to: staging.appending(path: file.name), options: .atomic)
                case .profilePhoto: profilePhoto = data
                }
            }
            return PreparedRestore(envelope: envelope, stagingDirectory: staging, profilePhoto: profilePhoto)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }
}

/// Replaces all data on this device with a prepared backup, in one save.
@MainActor
enum BackupRestorer {
    /// Deletes every record and inserts the backup's, saving once. Only after that save
    /// succeeds are staged photos moved into place, orphaned photos removed, settings written
    /// and the bundled foods re-applied. On failure the context is rolled back, staged files are
    /// discarded, and existing data and files are left untouched.
    static func restore(_ prepared: PreparedRestore, into context: ModelContext,
                        defaults: UserDefaults = .standard,
                        thumbnailsDirectory: URL = FoodThumbnailStore.directory) throws {
        defer { prepared.discardStaging() }
        let payload = prepared.envelope.payload
        do {
            // Seeded foods the backup overrides are updated in place (their seed ID is unique);
            // every other record is deleted.
            let overrides = Dictionary(payload.foods.compactMap { food in food.seedID.map { ($0, food) } }) { first, _ in first }
            for food in try context.fetch(FetchDescriptor<Food>()) {
                if let seedID = food.seedID, let override = overrides[seedID] {
                    override.apply(to: food)
                } else {
                    context.delete(food)
                }
            }
            try context.fetch(FetchDescriptor<WeightEntry>()).forEach(context.delete)
            try context.fetch(FetchDescriptor<FoodLogEntry>()).forEach(context.delete)
            try context.fetch(FetchDescriptor<CatProfile>()).forEach(context.delete)
            try context.fetch(FetchDescriptor<Vaccination>()).forEach(context.delete)
            try context.fetch(FetchDescriptor<MedicalRecord>()).forEach(context.delete)
            try context.fetch(FetchDescriptor<FeedingSchedule>()).forEach(context.delete)

            let existingSeedIDs = Set(try context.fetch(FetchDescriptor<Food>()).filter { !$0.isDeleted }.compactMap(\.seedID))
            for dto in payload.foods where dto.seedID == nil || !existingSeedIDs.contains(dto.seedID!) {
                let food = Food(name: dto.name, kilocaloriesPerGram: dto.kilocaloriesPerGram)
                dto.apply(to: food)
                context.insert(food)
            }
            payload.weights.forEach { context.insert($0.makeModel()) }
            payload.foodLog.forEach { context.insert($0.makeModel()) }
            payload.vaccinations.forEach { context.insert($0.makeModel()) }
            payload.medicalRecords.forEach { context.insert($0.makeModel()) }
            payload.schedules.forEach { context.insert($0.makeModel()) }
            if let profile = payload.profile {
                context.insert(profile.makeModel(photoData: prepared.profilePhoto))
            }
            try Persistence.saveOrThrow(context)
        } catch {
            context.rollback()
            Persistence.logger.error("Restore failed and was rolled back: \(error.localizedDescription, privacy: .public)")
            throw BackupError.saveFailed
        }

        // Committed: put photos in place and remove ones nothing refers to any more.
        movePhotos(from: prepared.stagingDirectory, to: thumbnailsDirectory, context: context)
        FoodThumbnailStore.invalidateCache()

        BackupSettings.write(payload.settings, deletedSeedIDs: payload.deletedSeedIDs, to: defaults)
        // Re-apply the bundled foods on top: missing ones are added, edited and deleted ones
        // are left as the backup says.
        for library in FoodLibraryLoader.bundledLibraries {
            defaults.removeObject(forKey: "foodLibraryVersion.\(library)")
            defaults.removeObject(forKey: "loadedFoodLibrary.\(library)")
        }
        FoodLibraryLoader.updateBundledLibraries(in: context, defaults: defaults)
        _ = CatProfile.current(in: context)
        // Backups from before kinds: give foods, entries and schedules their kind (same rules as
        // the V4 → V5 migration).
        FoodKindBackfill.run(in: context)
        try? Persistence.saveOrThrow(context)
        // Restored schedules catch up from their own last day; existing entries aren't duplicated.
        ScheduleMaterializer(context: context).materialize()
        Persistence.logger.notice("Restore completed from a backup made \(prepared.envelope.createdAt.formatted(.iso8601), privacy: .public)")
    }

    private static func movePhotos(from staging: URL, to directory: URL, context: ModelContext) {
        let manager = FileManager.default
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in (try? manager.contentsOfDirectory(atPath: staging.path)) ?? [] {
            let destination = directory.appending(path: name)
            try? manager.removeItem(at: destination)
            try? manager.moveItem(at: staging.appending(path: name), to: destination)
        }
        let foods = (try? context.fetch(FetchDescriptor<Food>())) ?? []
        let log = (try? context.fetch(FetchDescriptor<FoodLogEntry>())) ?? []
        let schedules = (try? context.fetch(FetchDescriptor<FeedingSchedule>())) ?? []
        let referenced = Set((foods.compactMap(\.thumbnailKey) + log.compactMap(\.foodLibraryIdentifier)
            + schedules.compactMap(\.foodPhotoKey))
            .compactMap(FoodThumbnailStore.fileName(forKey:)))
        for name in (try? manager.contentsOfDirectory(atPath: directory.path)) ?? [] where !referenced.contains(name) {
            try? manager.removeItem(at: directory.appending(path: name))
        }
    }
}
