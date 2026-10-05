import Foundation

// Explicit mapping between the @Model classes and the backup DTOs, in both directions.
// When a persisted property is added, map it here, add it to the DTO, and to the round-trip test.

extension FoodSizeDTO {
    init(_ size: FoodSize) {
        self.init(name: size.name, grams: size.grams, kilocalories: size.kilocalories,
                  kilocaloriesPerGram: size.kilocaloriesPerGram, isCalculated: size.isCalculated)
    }

    var model: FoodSize {
        FoodSize(name: name, grams: grams, kilocalories: kilocalories,
                 kilocaloriesPerGram: kilocaloriesPerGram, isCalculated: isCalculated)
    }
}

extension WeightDTO {
    init(_ entry: WeightEntry) {
        self.init(date: entry.date, kilograms: entry.kilograms, createdAt: entry.createdAt)
    }

    func makeModel() -> WeightEntry {
        WeightEntry(date: date, kilograms: kilograms, createdAt: createdAt)
    }
}

extension FoodDTO {
    init(_ food: Food) {
        self.init(
            name: food.name, kilocaloriesPerGram: food.kilocaloriesPerGram, createdAt: food.createdAt,
            brand: food.brand, line: food.line, kind: food.kindRawValue,
            sizes: food.sizes.map(FoodSizeDTO.init),
            calorieStatement: food.calorieStatement, ingredients: food.ingredients,
            guaranteedAnalysis: food.guaranteedAnalysis.map { AnalysisRowDTO(nutrient: $0.nutrient, amount: $0.amount) },
            notes: food.notes, sourceURL: food.sourceURL?.absoluteString,
            libraryIdentifier: food.libraryIdentifier, seedID: food.seedID,
            isUserModified: food.isUserModified, origin: food.origin.rawValue, thumbnailKey: food.thumbnailKey
        )
    }

    /// Copies every field onto `food` (a new food, or a seeded food being overridden).
    func apply(to food: Food) {
        food.name = name
        food.kilocaloriesPerGram = kilocaloriesPerGram
        food.createdAt = createdAt
        food.brand = brand
        food.line = line
        food.kindRawValue = kind
        food.sizes = sizes.map(\.model)
        food.calorieStatement = calorieStatement
        food.ingredients = ingredients
        food.guaranteedAnalysis = guaranteedAnalysis.map { GuaranteedAnalysisRow(nutrient: $0.nutrient, amount: $0.amount) }
        food.notes = notes
        food.sourceURL = sourceURL.flatMap(URL.init(string:))
        food.libraryIdentifier = libraryIdentifier
        food.seedID = seedID
        food.isUserModified = isUserModified
        food.originRawValue = origin
        food.thumbnailKey = thumbnailKey
    }
}

extension FoodLogEntryDTO {
    init(_ entry: FoodLogEntry) {
        self.init(
            loggedAt: entry.loggedAt, foodName: entry.foodName, foodBrand: entry.foodBrand,
            foodLine: entry.foodLine, foodLibraryIdentifier: entry.foodLibraryIdentifier,
            portionSource: entry.portionSource.map {
                PortionSourceDTO(sizes: $0.sizes.map(FoodSizeDTO.init), kilocaloriesPerGram: $0.kilocaloriesPerGram)
            },
            measure: entry.measureRawValue, sizeName: entry.sizeName, containers: entry.containers,
            grams: entry.grams, containersNumerator: entry.containersNumerator,
            containersDenominator: entry.containersDenominator, kilocalories: entry.kilocalories,
            isCustomKilocalories: entry.isCustomKilocalories, createdAt: entry.createdAt,
            carryGroupID: entry.carryGroupID, carryDay: entry.carryDay, openedAt: entry.openedAt,
            scheduleID: entry.scheduleID, kind: entry.kindRawValue
        )
    }

    func makeModel() -> FoodLogEntry {
        let entry = FoodLogEntry(foodName: foodName, kilocalories: kilocalories, loggedAt: loggedAt, createdAt: createdAt)
        entry.foodBrand = foodBrand
        entry.foodLine = foodLine
        entry.foodLibraryIdentifier = foodLibraryIdentifier
        entry.portionSource = portionSource.map {
            PortionSource(sizes: $0.sizes.map(\.model), kilocaloriesPerGram: $0.kilocaloriesPerGram)
        }
        entry.measureRawValue = measure
        entry.sizeName = sizeName
        entry.containers = containers
        entry.grams = grams
        entry.containersNumerator = containersNumerator
        entry.containersDenominator = containersDenominator
        entry.isCustomKilocalories = isCustomKilocalories
        entry.carryGroupID = carryGroupID
        entry.carryDay = carryDay
        entry.openedAt = openedAt
        entry.scheduleID = scheduleID
        entry.kindRawValue = kind
        return entry
    }
}

extension FeedingScheduleDTO {
    init(_ schedule: FeedingSchedule) {
        self.init(
            id: schedule.id, foodName: schedule.foodName, foodBrand: schedule.foodBrand, foodLine: schedule.foodLine,
            foodSeedID: schedule.foodSeedID, foodPhotoKey: schedule.foodPhotoKey,
            portionSource: schedule.portionSource.map {
                PortionSourceDTO(sizes: $0.sizes.map(FoodSizeDTO.init), kilocaloriesPerGram: $0.kilocaloriesPerGram)
            },
            measure: schedule.measureRawValue, sizeName: schedule.sizeName,
            containersNumerator: schedule.containersNumerator, containersDenominator: schedule.containersDenominator,
            grams: schedule.grams, kilocaloriesPerOccurrence: schedule.kilocaloriesPerOccurrence,
            isKilocaloriesOverridden: schedule.isKilocaloriesOverridden, label: schedule.label,
            weekdays: schedule.weekdays, startDate: schedule.startDate, endDate: schedule.endDate,
            isPaused: schedule.isPaused, lastMaterializedDay: schedule.lastMaterializedDay,
            createdAt: schedule.createdAt, updatedAt: schedule.updatedAt, kind: schedule.foodKindRawValue
        )
    }

    func makeModel() -> FeedingSchedule {
        let schedule = FeedingSchedule(id: id, foodName: foodName, measureRawValue: measure,
                                       kilocaloriesPerOccurrence: kilocaloriesPerOccurrence, weekdays: weekdays,
                                       startDate: startDate, createdAt: createdAt)
        schedule.foodBrand = foodBrand
        schedule.foodLine = foodLine
        schedule.foodSeedID = foodSeedID
        schedule.foodPhotoKey = foodPhotoKey
        schedule.portionSource = portionSource.map {
            PortionSource(sizes: $0.sizes.map(\.model), kilocaloriesPerGram: $0.kilocaloriesPerGram)
        }
        schedule.sizeName = sizeName
        schedule.containersNumerator = containersNumerator
        schedule.containersDenominator = containersDenominator
        schedule.grams = grams
        schedule.isKilocaloriesOverridden = isKilocaloriesOverridden
        schedule.label = label
        schedule.endDate = endDate
        schedule.isPaused = isPaused
        schedule.lastMaterializedDay = lastMaterializedDay
        schedule.updatedAt = updatedAt
        schedule.foodKindRawValue = kind
        return schedule
    }
}

extension ProfileDTO {
    init(_ profile: CatProfile, photoFile: String?) {
        self.init(
            name: profile.name, photoFile: photoFile, birthday: profile.birthday,
            birthdayPrecision: profile.birthdayPrecisionRawValue, breed: profile.breed,
            colorAndMarkings: profile.colorAndMarkings, sex: profile.sexRawValue,
            spayedOrNeutered: profile.spayedOrNeuteredRawValue, microchipNumber: profile.microchipNumber,
            notes: profile.notes, createdAt: profile.createdAt
        )
    }

    func makeModel(photoData: Data?) -> CatProfile {
        let profile = CatProfile()
        profile.createdAt = createdAt
        profile.name = name
        profile.photoData = photoData
        profile.birthday = birthday
        profile.birthdayPrecisionRawValue = birthdayPrecision
        profile.breed = breed
        profile.colorAndMarkings = colorAndMarkings
        profile.sexRawValue = sex
        profile.spayedOrNeuteredRawValue = spayedOrNeutered
        profile.microchipNumber = microchipNumber
        profile.notes = notes
        return profile
    }
}

extension VaccinationDTO {
    init(_ vaccination: Vaccination) {
        self.init(name: vaccination.name, dateGiven: vaccination.dateGiven, nextDue: vaccination.nextDue,
                  notes: vaccination.notes)
    }

    func makeModel() -> Vaccination {
        Vaccination(name: name, dateGiven: dateGiven, nextDue: nextDue, notes: notes)
    }
}

extension MedicalRecordDTO {
    init(_ record: MedicalRecord) {
        self.init(date: record.date, title: record.title, kind: record.kindRawValue, clinic: record.clinic,
                  notes: record.notes)
    }

    func makeModel() -> MedicalRecord {
        let record = MedicalRecord(date: date, title: title, kind: .other, clinic: clinic, notes: notes)
        record.kindRawValue = kind
        return record
    }
}
