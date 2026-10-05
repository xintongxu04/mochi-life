import Foundation
import SwiftData

/// One thing Mochi ate. Each entry keeps its own copy of the food's details from when it was
/// logged, so editing or deleting a saved food later never changes past entries.
@Model
final class FoodLogEntry {
    var loggedAt: Date
    var foodName: String
    var foodBrand: String?
    var foodLine: String?
    /// Used only to show the food's photo: the food's `photoKey` when logged (a seed ID, an
    /// older "<library>/<name>" identifier, or a "user/<uuid>" photo the app saved).
    var foodLibraryIdentifier: String?
    /// The food's sizes and calories when it was logged, for editing the amount later.
    /// Nil for quick entries, which are just a name and a calorie number.
    var portionSource: PortionSource?

    var measureRawValue: String?
    var sizeName: String?
    var containers: Double?
    var grams: Double?
    /// The exact fraction of a can or pouch, e.g. 1/3, when logged by can or pouch.
    var containersNumerator: Int?
    var containersDenominator: Int?
    var kilocalories: Double
    var isCustomKilocalories: Bool = false
    var createdAt: Date

    /// Shared by an entry and the entries carrying the rest of its can or pouch forward.
    var carryGroupID: UUID?
    /// 0 for the entry the can or pouch was opened with, then 1, 2, … for each following day.
    var carryDay: Int = 0
    /// For carried entries: when the can or pouch was opened.
    var openedAt: Date?

    init(foodName: String, kilocalories: Double, loggedAt: Date, createdAt: Date = .now) {
        self.foodName = foodName
        self.kilocalories = kilocalories
        self.loggedAt = loggedAt
        self.createdAt = createdAt
    }

    var isQuickEntry: Bool { portionSource == nil }

    /// Copies the food's details and the chosen portion into this entry.
    func record(_ food: Food, portion: Portion) {
        foodName = food.name
        foodBrand = food.brand
        foodLine = food.line
        foodLibraryIdentifier = food.photoKey
        portionSource = PortionSource(food)
        record(portion)
    }

    /// Updates the amount and calories, keeping the food details copied when it was logged.
    func record(_ portion: Portion) {
        measureRawValue = portion.measure == .grams ? "grams" : "containers"
        sizeName = portion.size?.name
        containers = portion.containers
        containersNumerator = portion.exactContainers?.numerator
        containersDenominator = portion.exactContainers?.denominator
        grams = portion.grams
        kilocalories = portion.kilocalories ?? kilocalories
        isCustomKilocalories = portion.customKilocalories != nil
    }

    /// The portion as it was chosen, to start the size-and-portion picker from when editing.
    var portion: Portion? {
        guard let portionSource else { return nil }
        let size = portionSource.sizes.first { $0.name == sizeName }
        return Portion(
            measure: measureRawValue == "grams" ? .grams : .containers,
            size: size,
            containers: containers,
            exactContainers: exactContainers,
            grams: grams,
            calculatedKilocalories: nil,
            customKilocalories: isCustomKilocalories ? kilocalories : nil
        )
    }

    /// Like "1/2 of a 2.8 oz can" or "20 g". Nil for quick entries.
    var amountDescription: String? { portion?.amountDescription }

    var exactContainers: Fraction? {
        guard let containersNumerator, let containersDenominator, containersDenominator != 0 else { return nil }
        return Fraction(containersNumerator, containersDenominator)
    }

    var isCarriedForward: Bool { carryGroupID != nil && carryDay > 0 }

    /// "can" or "pouch", from the size it was logged with.
    var containerName: String {
        portionSource?.sizes.first { $0.name == sizeName }?.containerName ?? "can"
    }

    /// The portions for the following days if the rest of this entry's can or pouch were
    /// carried forward. Empty for grams, quick entries and whole cans.
    var carryPlan: [Fraction] {
        guard measureRawValue == "containers", let exactContainers else { return [] }
        return CarryForward.plan(for: exactContainers)
    }

    /// Makes one entry per following day for the rest of this entry's can or pouch. They keep
    /// the same food, size and calories per can, including a calorie number typed in by hand.
    func makeCarriedEntries(calendar: Calendar = .current) -> [FoodLogEntry] {
        let plan = carryPlan
        guard !plan.isEmpty, let exactContainers else { return [] }
        let group = carryGroupID ?? UUID()
        carryGroupID = group
        carryDay = 0
        let kilocaloriesPerContainer = kilocalories / exactContainers.doubleValue
        return plan.enumerated().map { index, portion in
            let day = index + 1
            let carried = FoodLogEntry(
                foodName: foodName,
                kilocalories: kilocaloriesPerContainer * portion.doubleValue,
                loggedAt: calendar.date(byAdding: .day, value: day, to: loggedAt) ?? loggedAt
            )
            carried.foodBrand = foodBrand
            carried.foodLine = foodLine
            carried.foodLibraryIdentifier = foodLibraryIdentifier
            carried.portionSource = portionSource
            carried.measureRawValue = measureRawValue
            carried.sizeName = sizeName
            carried.containers = portion.doubleValue
            carried.containersNumerator = portion.numerator
            carried.containersDenominator = portion.denominator
            carried.isCustomKilocalories = isCustomKilocalories
            carried.carryGroupID = group
            carried.carryDay = day
            carried.openedAt = loggedAt
            return carried
        }
    }

    /// The carried entries after this one from the same can or pouch.
    func laterCarriedEntries(in context: ModelContext) -> [FoodLogEntry] {
        guard let carryGroupID else { return [] }
        let all = (try? context.fetch(FetchDescriptor<FoodLogEntry>())) ?? []
        return all.filter { $0.carryGroupID == carryGroupID && $0.carryDay > carryDay }
    }
}
