import Foundation
import SwiftData

/// Gives every food, log entry and schedule a `FoodKind`. Runs in the V4 → V5 migration, at
/// every launch and after a restore; it only touches items that don't have a valid kind yet, so
/// it's safe to repeat. Rules:
/// - Foods still on the old "food" kind: bundled Tiki Cat products (they have a seed ID) are
///   wet food; other foods with container sizes (can, pouch, tray, cup, stick…) are wet food;
///   foods measured only by weight are kibble. Treats, supplements and toppers keep their kind.
/// - Log entries: the kind of the saved food they were logged from (matched by photo key, seed
///   ID or brand + line + name, as entries don't link to foods); if that food is gone, the
///   serving rule on the entry's own copy of the sizes; quick entries are kibble.
/// - Schedules: their food's kind the same way, else the serving rule.
nonisolated enum FoodKindBackfill {
    static func run(in context: ModelContext) {
        let foods = (try? context.fetch(FetchDescriptor<Food>())) ?? []
        for food in foods where FoodKind(rawValue: food.kindRawValue) == nil {
            food.kindRawValue = (food.seedID != nil ? FoodKind.wetFood
                : FoodKind.byServing(hasContainerSizes: !food.sizes.isEmpty)).rawValue
        }

        var byKey: [String: Food] = [:]
        var byName: [String: Food] = [:]
        for food in foods {
            for key in [food.seedID, food.libraryIdentifier, food.thumbnailKey].compactMap({ $0 }) where byKey[key] == nil {
                byKey[key] = food
            }
            let name = FoodMatching.key(brand: food.brand, line: food.line, name: food.name)
            if byName[name] == nil { byName[name] = food }
        }
        func savedFood(photoKey: String?, seedID: String?, brand: String?, line: String?, name: String) -> Food? {
            for key in [photoKey, seedID].compactMap({ $0 }) {
                if let food = byKey[key] { return food }
            }
            return byName[FoodMatching.key(brand: brand, line: line, name: name)]
        }

        let entries = (try? context.fetch(FetchDescriptor<FoodLogEntry>())) ?? []
        for entry in entries where entry.kindRawValue.flatMap(FoodKind.init(rawValue:)) == nil {
            let kind: FoodKind
            if entry.portionSource == nil {
                kind = .kibble
            } else if let food = savedFood(photoKey: entry.foodLibraryIdentifier, seedID: nil, brand: entry.foodBrand,
                                           line: entry.foodLine, name: entry.foodName) {
                kind = FoodKind.stored(food.kindRawValue, hasContainerSizes: !food.sizes.isEmpty)
            } else {
                kind = .byServing(hasContainerSizes: !(entry.portionSource?.sizes.isEmpty ?? true))
            }
            entry.kindRawValue = kind.rawValue
        }

        let schedules = (try? context.fetch(FetchDescriptor<FeedingSchedule>())) ?? []
        for schedule in schedules where schedule.foodKindRawValue.flatMap(FoodKind.init(rawValue:)) == nil {
            let kind: FoodKind
            if let food = savedFood(photoKey: schedule.foodPhotoKey, seedID: schedule.foodSeedID, brand: schedule.foodBrand,
                                    line: schedule.foodLine, name: schedule.foodName) {
                kind = FoodKind.stored(food.kindRawValue, hasContainerSizes: !food.sizes.isEmpty)
            } else {
                kind = .byServing(hasContainerSizes: !(schedule.portionSource?.sizes.isEmpty ?? true))
            }
            schedule.foodKindRawValue = kind.rawValue
        }
    }
}
