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
    /// Used only to show the food's photo.
    var foodLibraryIdentifier: String?
    /// The food's sizes and calories when it was logged, for editing the amount later.
    /// Nil for quick entries, which are just a name and a calorie number.
    var portionSource: PortionSource?

    var measureRawValue: String?
    var sizeName: String?
    var containers: Double?
    var grams: Double?
    var kilocalories: Double
    var isCustomKilocalories: Bool = false
    var createdAt: Date

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
        foodLibraryIdentifier = food.libraryIdentifier
        portionSource = PortionSource(food)
        record(portion)
    }

    /// Updates the amount and calories, keeping the food details copied when it was logged.
    func record(_ portion: Portion) {
        measureRawValue = portion.measure == .grams ? "grams" : "containers"
        sizeName = portion.size?.name
        containers = portion.containers
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
            grams: grams,
            calculatedKilocalories: nil,
            customKilocalories: isCustomKilocalories ? kilocalories : nil
        )
    }

    /// Like "1/2 of a 2.8 oz can" or "20 g". Nil for quick entries.
    var amountDescription: String? { portion?.amountDescription }
}
