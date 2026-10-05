import Foundation
import SwiftData
import Testing
@testable import MochiLife

/// Export → file → read and validate → restore into a second container → export again, and
/// compare. Covers every backed-up type. When a persisted field is added, add it here too.
@MainActor
struct BackupRoundTripTests {
    @Test func exportAndRestoreKeepEveryRecordAndPhoto() async throws {
        let schema = Schema(versionedSchema: SchemaV5.self)
        let source = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let target = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let work = URL.temporaryDirectory.appending(path: "backup-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        let sourcePhotos = work.appending(path: "source-photos", directoryHint: .isDirectory)
        let targetPhotos = work.appending(path: "target-photos", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sourcePhotos, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let sourceDefaults = try #require(UserDefaults(suiteName: "backup-test-source-\(UUID().uuidString)"))
        let targetDefaults = try #require(UserDefaults(suiteName: "backup-test-target-\(UUID().uuidString)"))

        // MARK: Populate one of everything
        let context = source.mainContext
        let date = Date(timeIntervalSinceReferenceDate: 812_000_000.123)
        context.insert(WeightEntry(date: date, kilograms: 3.25, createdAt: date))

        let photoBytes = Data((0..<256).map { UInt8($0) })
        try photoBytes.write(to: sourcePhotos.appending(path: "food-test.jpg"))
        let manual = Food(name: "Home Cooked Chicken", kilocaloriesPerGram: 1.5, brand: nil, line: nil,
                          sizes: [FoodSize(name: "1 cup", grams: 120, kilocalories: 180, kilocaloriesPerGram: 1.5, isCalculated: false)],
                          notes: ["Boiled, no salt"], createdAt: date)
        manual.origin = .manual
        manual.thumbnailKey = "user/food-test"
        context.insert(manual)

        let aiFood = Food(name: "Paw Lickin' Chicken", kilocaloriesPerGram: 0.85, brand: "Weruva", line: "Classic",
                          kind: .wetFood,
                          sizes: [FoodSize(name: "3 oz can", grams: 85, kilocalories: 72.3, kilocaloriesPerGram: 0.85, isCalculated: true)],
                          calorieStatement: "850 kcal/kg", ingredients: "Chicken, water",
                          guaranteedAnalysis: [GuaranteedAnalysisRow(nutrient: "Crude protein", amount: "12% min")],
                          notes: ["Found with AI lookup"], sourceURL: URL(string: "https://www.weruva.com/x"), createdAt: date)
        aiFood.origin = .aiLookup
        aiFood.thumbnailKey = FoodThumbnailStore.noPhotoKey
        context.insert(aiFood)

        let editedSeed = Food(name: "After Dark Chicken & Pork (edited)", kilocaloriesPerGram: 0.75, brand: "Tiki Cat",
                              line: "After Dark", seedID: "tiki-cat-after-dark-chicken-and-pork-recipe-in-broth", createdAt: date)
        editedSeed.libraryIdentifier = "tiki-cat-wet-food/Tiki Cat After Dark Chicken & Pork Recipe in Broth"
        editedSeed.isUserModified = true
        editedSeed.origin = .seed
        context.insert(editedSeed)

        let opened = FoodLogEntry(foodName: "Paw Lickin' Chicken", kilocalories: 18.075, loggedAt: date, createdAt: date)
        opened.record(aiFood, portion: Portion(measure: .containers, size: aiFood.sizes[0], containers: 0.25,
                                               exactContainers: Fraction(1, 4), calculatedKilocalories: 18.075))
        context.insert(opened)
        let carried = try #require(opened.makeCarriedEntries().first)
        context.insert(carried)
        let quick = FoodLogEntry(foodName: "Treat", kilocalories: 5, loggedAt: date, createdAt: date.addingTimeInterval(1))
        quick.foodLibraryIdentifier = "user/food-test"
        quick.kind = .treat
        context.insert(quick)

        // A feeding schedule already caught up to today, and one entry it made.
        let schedule = FeedingSchedule(foodName: aiFood.name, measureRawValue: "containers", kilocaloriesPerOccurrence: 36.15,
                                       weekdays: Weekdays.weekdaysOnly, startDate: Calendar.current.startOfDay(for: date), createdAt: date)
        schedule.record(aiFood)
        schedule.record(Portion(measure: .containers, size: aiFood.sizes[0], containers: 0.5,
                                exactContainers: Fraction(1, 2), calculatedKilocalories: 36.15))
        schedule.label = "Morning"
        schedule.endDate = Calendar.current.date(byAdding: .year, value: 1, to: Calendar.current.startOfDay(for: date))
        schedule.lastMaterializedDay = Calendar.current.startOfDay(for: .now)
        context.insert(schedule)
        context.insert(schedule.makeEntry(for: date))

        let profile = CatProfile(createdAt: date)
        profile.name = "Mochi"
        profile.photoData = Data([9, 8, 7])
        profile.birthday = date
        profile.birthdayPrecision = .approximate
        profile.breed = "Domestic shorthair"
        profile.colorAndMarkings = "Calico"
        profile.sex = .female
        profile.spayedOrNeutered = .yes
        profile.microchipNumber = "985112345678901"
        profile.notes = "Loves tuna"
        context.insert(profile)
        context.insert(Vaccination(name: "FVRCP", dateGiven: date, nextDue: date.addingTimeInterval(86_400 * 365), notes: "Annual"))
        context.insert(MedicalRecord(date: date, title: "Dental cleaning", kind: .surgery, clinic: "City Vet", notes: "All good"))
        try context.save()

        sourceDefaults.set("lb", forKey: "weightUnit")
        sourceDefaults.set(210.0, forKey: CalorieTarget.ownTargetKey)
        sourceDefaults.set(true, forKey: CalorieTarget.gainsWeightEasilyKey)
        sourceDefaults.set(["tiki-cat-after-dark-pate-beef-and-beef-liver-recipe"], forKey: FoodLibraryLoader.deletedSeedIDsKey)

        // MARK: Export to a real file, read it back, restore
        let (settings, deleted) = BackupSettings.read(from: sourceDefaults)
        let exported = try await BackupService(modelContainer: source)
            .makeEnvelope(settings: settings, deletedSeedIDs: deleted, deviceName: "Test", thumbnailsDirectory: sourcePhotos)
        let file = work.appending(path: "test.\(BackupFormat.fileExtension)")
        try await BackupFiles.write(exported, to: file)
        let prepared = try await BackupReader.prepare(from: file)
        try BackupRestorer.restore(prepared, into: target.mainContext, defaults: targetDefaults, thumbnailsDirectory: targetPhotos)

        // MARK: Compare
        let (restoredSettings, restoredDeleted) = BackupSettings.read(from: targetDefaults)
        let reexported = try await BackupService(modelContainer: target)
            .makeEnvelope(settings: restoredSettings, deletedSeedIDs: restoredDeleted, deviceName: "Test", thumbnailsDirectory: targetPhotos)

        let encoder = BackupCoding.encoder()
        // Every field of every record, compared as the backup encodes it.
        #expect(try encoder.encode(reexported.payload) == encoder.encode(exported.payload))
        #expect(reexported.files == exported.files)
        #expect(exported.payload.weights.count == 1)
        #expect(exported.payload.foods.count == 3)
        #expect(exported.payload.foodLog.count == 4)
        #expect(exported.payload.schedules.count == 1)
        #expect(exported.formatVersion == 3)
        #expect(exported.payload.vaccinations.count == 1)
        #expect(exported.payload.medicalRecords.count == 1)
        #expect(exported.payload.profile != nil)
        #expect(exported.files.map(\.role).sorted { $0.rawValue < $1.rawValue } == [.foodThumbnail, .profilePhoto])

        // Files and links landed where the app reads them.
        let restoredPhoto = targetPhotos.appending(path: "food-test.jpg")
        #expect(FileManager.default.fileExists(atPath: restoredPhoto.path))
        #expect(try Data(contentsOf: restoredPhoto) == photoBytes)
        let restoredLog = try target.mainContext.fetch(FetchDescriptor<FoodLogEntry>())
        let restoredCarried = try #require(restoredLog.first { $0.isCarriedForward })
        #expect(restoredCarried.carryGroupID == opened.carryGroupID)
        #expect(restoredCarried.exactContainers == Fraction(1, 4))
        #expect(try target.mainContext.fetch(FetchDescriptor<CatProfile>()).first?.photoData == Data([9, 8, 7]))
        // The schedule and its entry came back linked, and catching up after the restore added nothing.
        let restoredSchedule = try #require(try target.mainContext.fetch(FetchDescriptor<FeedingSchedule>()).first)
        #expect(restoredSchedule.id == schedule.id)
        #expect(restoredSchedule.exactContainers == Fraction(1, 2))
        #expect(restoredLog.count == 4)
        #expect(restoredLog.filter { $0.scheduleID == schedule.id }.count == 1)

        // A format 1 file (no schedules, no scheduleID) is upgraded on reading.
        var oldFile = try #require(try JSONSerialization.jsonObject(with: encoder.encode(exported)) as? [String: Any])
        var oldPayload = try #require(oldFile["payload"] as? [String: Any])
        oldPayload.removeValue(forKey: "schedules")
        oldPayload["foodLog"] = (oldPayload["foodLog"] as? [[String: Any]])?.map { entry in
            var entry = entry
            entry.removeValue(forKey: "scheduleID")
            return entry
        }
        oldFile["payload"] = oldPayload
        oldFile["formatVersion"] = 1
        let upgraded = try BackupReader.decode(JSONSerialization.data(withJSONObject: oldFile))
        #expect(upgraded.payload.schedules.isEmpty)
        #expect(upgraded.payload.foodLog.count == 4)
        #expect(upgraded.payload.foodLog.allSatisfy { $0.scheduleID == nil })

        // Bundled foods were re-applied on top: the edited one kept, the deleted one absent.
        let restoredFoods = try target.mainContext.fetch(FetchDescriptor<Food>())
        #expect(restoredFoods.first { $0.seedID == editedSeed.seedID }?.name == "After Dark Chicken & Pork (edited)")
        #expect(!restoredFoods.contains { $0.seedID == "tiki-cat-after-dark-pate-beef-and-beef-liver-recipe" })
        #expect(restoredFoods.filter { $0.seedID != nil }.count == 98)
        #expect(Set(restoredFoods.compactMap(\.seedID)).count == restoredFoods.filter { $0.seedID != nil }.count)
    }
}
