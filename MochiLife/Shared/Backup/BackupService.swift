import Foundation
import os
import SwiftData
import UIKit

/// Builds backups from a background ModelContext, so exporting never blocks the main actor.
@ModelActor
actor BackupService {
    /// Reads every backed-up record and file into an envelope.
    /// - Parameters:
    ///   - settings: Values read from UserDefaults by the caller.
    ///   - deletedSeedIDs: From UserDefaults (`FoodLibraryLoader.deletedSeedIDsKey`).
    func makeEnvelope(settings: SettingsDTO, deletedSeedIDs: [String], deviceName: String,
                      thumbnailsDirectory: URL = FoodThumbnailStore.directory) throws -> BackupEnvelope {
        let context = modelContext
        let weights = try context.fetch(FetchDescriptor<WeightEntry>())
            .sorted { ($0.date, $0.createdAt) < ($1.date, $1.createdAt) }
        try Task.checkCancellation()
        // Foods added by hand or with AI in full; seeded foods only when the owner edited them.
        let foods = try context.fetch(FetchDescriptor<Food>())
            .filter { $0.seedID == nil || $0.isUserModified }
            .sorted { ($0.seedID ?? "", $0.name, $0.createdAt) < ($1.seedID ?? "", $1.name, $1.createdAt) }
        let log = try context.fetch(FetchDescriptor<FoodLogEntry>())
            .sorted { ($0.loggedAt, $0.createdAt) < ($1.loggedAt, $1.createdAt) }
        try Task.checkCancellation()
        let profile = try context.fetch(FetchDescriptor<CatProfile>()).sortedOldestFirst().first
        let vaccinations = try context.fetch(FetchDescriptor<Vaccination>())
            .sorted { ($0.dateGiven, $0.name) < ($1.dateGiven, $1.name) }
        let records = try context.fetch(FetchDescriptor<MedicalRecord>())
            .sorted { ($0.date, $0.title) < ($1.date, $1.title) }

        // Every photo file referenced by a food or a log entry that exists in the container.
        var files: [BackupFile] = []
        let keys = Set(foods.compactMap(\.thumbnailKey) + log.compactMap(\.foodLibraryIdentifier))
        for key in keys.sorted() {
            try Task.checkCancellation()
            guard let name = FoodThumbnailStore.fileName(forKey: key),
                  let data = try? Data(contentsOf: thumbnailsDirectory.appending(path: name))
            else { continue }
            files.append(BackupFile(name: name, role: .foodThumbnail, base64: data.base64EncodedString()))
        }
        var photoFile: String?
        if let photo = profile?.photoData {
            photoFile = "profile-photo"
            files.append(BackupFile(name: "profile-photo", role: .profilePhoto, base64: photo.base64EncodedString()))
        }

        return BackupEnvelope(
            formatVersion: BackupFormat.currentFormatVersion,
            schemaVersion: BackupFormat.currentSchemaVersion.text,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            createdAt: .now,
            deviceName: deviceName,
            payload: BackupPayload(
                weights: weights.map(WeightDTO.init),
                foods: foods.map(FoodDTO.init),
                deletedSeedIDs: deletedSeedIDs.sorted(),
                foodLog: log.map(FoodLogEntryDTO.init),
                profile: profile.map { ProfileDTO($0, photoFile: photoFile) },
                vaccinations: vaccinations.map(VaccinationDTO.init),
                medicalRecords: records.map(MedicalRecordDTO.init),
                settings: settings
            ),
            files: files
        )
    }
}

extension Schema.Version {
    var text: String { "\(major).\(minor).\(patch)" }

    init?(text: String) {
        let parts = text.split(separator: ".").map { Int($0) }
        guard parts.count == 3, let major = parts[0], let minor = parts[1], let patch = parts[2] else { return nil }
        self.init(major, minor, patch)
    }
}

/// Settings that go into a backup, read from and written back to UserDefaults.
@MainActor
enum BackupSettings {
    static func read(from defaults: UserDefaults) -> (SettingsDTO, deletedSeedIDs: [String]) {
        let target = defaults.double(forKey: CalorieTarget.ownTargetKey)
        let settings = SettingsDTO(
            weightUnit: defaults.string(forKey: "weightUnit"),
            ownCalorieTarget: target > 0 ? target : nil,
            gainsWeightEasily: defaults.bool(forKey: CalorieTarget.gainsWeightEasilyKey)
        )
        return (settings, defaults.stringArray(forKey: FoodLibraryLoader.deletedSeedIDsKey) ?? [])
    }

    static func write(_ settings: SettingsDTO, deletedSeedIDs: [String], to defaults: UserDefaults) {
        if let unit = settings.weightUnit { defaults.set(unit, forKey: "weightUnit") } else { defaults.removeObject(forKey: "weightUnit") }
        defaults.set(settings.ownCalorieTarget ?? 0, forKey: CalorieTarget.ownTargetKey)
        defaults.set(settings.gainsWeightEasily, forKey: CalorieTarget.gainsWeightEasilyKey)
        defaults.set(deletedSeedIDs, forKey: FoodLibraryLoader.deletedSeedIDsKey)
    }
}

/// Writing, naming and keeping backup files.
enum BackupFiles {
    /// Seconds since the reference date of the last successful export (per device; not backed up).
    static let lastExportKey = "backup.lastExport"
    static let safetyDirectory = URL.documentsDirectory.appending(path: "SafetyBackups", directoryHint: .isDirectory)
    static let keptSafetyBackups = 3

    /// "MochiLife-2026-10-05-1430.mochibackup"
    static func fileName(for date: Date, prefix: String = "MochiLife") -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "\(prefix)-\(formatter.string(from: date)).\(BackupFormat.fileExtension)"
    }

    /// Encodes the envelope and writes it atomically. Runs off the main actor.
    static func write(_ envelope: BackupEnvelope, to url: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            let data = try BackupCoding.encoder().encode(envelope)
            try Task.checkCancellation()
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }.value
    }

    /// The current data as a backup in the temporary folder, ready to share.
    @MainActor
    static func exportCurrentData(container: ModelContainer, defaults: UserDefaults = .standard) async throws -> URL {
        let envelope = try await makeEnvelope(container: container, defaults: defaults)
        let url = URL.temporaryDirectory.appending(path: fileName(for: envelope.createdAt))
        try await write(envelope, to: url)
        defaults.set(envelope.createdAt.timeIntervalSinceReferenceDate, forKey: lastExportKey)
        Persistence.logger.notice("Backup exported: \(envelope.payload.foodLog.count) log entries, \(envelope.files.count) files")
        return url
    }

    /// An automatic safety backup in Documents/SafetyBackups, keeping the three most recent.
    @MainActor
    static func writeSafetyBackup(container: ModelContainer, defaults: UserDefaults = .standard) async throws {
        let envelope = try await makeEnvelope(container: container, defaults: defaults)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let url = safetyDirectory.appending(path: "MochiLife-safety-\(formatter.string(from: envelope.createdAt)).\(BackupFormat.fileExtension)")
        try await write(envelope, to: url)
        for old in safetyBackups().dropFirst(keptSafetyBackups) {
            try? FileManager.default.removeItem(at: old.url)
        }
    }

    struct SafetyBackup: Identifiable, Hashable {
        var url: URL
        var date: Date
        var id: URL { url }
    }

    /// Safety backups, newest first.
    static func safetyBackups() -> [SafetyBackup] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: safetyDirectory, includingPropertiesForKeys: [.creationDateKey])) ?? []
        return urls.filter { $0.pathExtension == BackupFormat.fileExtension }
            .map { url in
                let date = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return SafetyBackup(url: url, date: date)
            }
            .sorted { $0.date > $1.date }
    }

    @MainActor
    private static func makeEnvelope(container: ModelContainer, defaults: UserDefaults) async throws -> BackupEnvelope {
        let (settings, deleted) = BackupSettings.read(from: defaults)
        let deviceName = UIDevice.current.name
        let service = BackupService(modelContainer: container)
        return try await service.makeEnvelope(settings: settings, deletedSeedIDs: deleted, deviceName: deviceName)
    }
}
