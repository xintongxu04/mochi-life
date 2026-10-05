import Foundation
import SwiftData

/// The Recent and Frequent lists of the Log Food sheet, worked out from log entries (which are
/// snapshots, not links to saved foods). Every item can be tapped: a saved food opens its
/// portion picker; an entry whose saved food is gone logs again from its own copy; a quick
/// entry opens quick entry prefilled.
@MainActor
enum RecentUsage {
    static let recentLimit = 8
    static let frequentLimit = 5
    static let frequentWindowDays = 30

    enum Section: String { case recent, frequent }

    enum Target {
        /// The saved food still exists.
        case food(Food)
        /// The saved food is gone (deleted or renamed): log from the entry's own copy.
        case snapshot(FoodLogEntry)
        /// A quick entry: just a name and calories.
        case quickEntry(name: String, kilocalories: Double)
    }

    struct Item: Identifiable {
        /// Unique across both sections, like "recent-food-…" or "frequent-quick-treat".
        var id: String
        /// What the item is, independent of the section.
        var key: String
        var target: Target
        /// The last amount used, to start the portion picker from.
        var portion: Portion?
        var name: String
        var brand: String?
        var line: String?
        var photoKey: String?
        /// For the default picture when there's no photo.
        var kind: FoodKind = .kibble
        /// Like "1/2 of a 2.8 oz can", or "12 kcal" for a quick entry.
        var detail: String?

        var isInSavedFoods: Bool {
            if case .food = target { true } else { false }
        }
    }

    /// Recent: the last distinct items, newest first. Frequent: the most-logged items in the
    /// last 30 days that aren't already in Recent. Carried-forward days are left out (they
    /// repeat the entry the can was opened with).
    static func lists(entries: [FoodLogEntry], foods: [Food], now: Date = .now,
                      calendar: Calendar = .current) -> (recent: [Item], frequent: [Item]) {
        let keyed = Dictionary(foods.map { (FoodMatching.key(brand: $0.brand, line: $0.line, name: $0.name), $0) }) { first, _ in first }
        var byPhotoKey: [String: Food] = [:]
        for food in foods {
            for key in [food.seedID, food.libraryIdentifier, food.thumbnailKey].compactMap({ $0 }) where byPhotoKey[key] == nil {
                byPhotoKey[key] = food
            }
        }
        let monthAgo = calendar.date(byAdding: .day, value: -frequentWindowDays, to: now) ?? .distantPast
        var recent: [Item] = []
        var counts: [String: (count: Int, latest: Item)] = [:]
        for entry in entries.sorted(by: { ($0.loggedAt, $0.createdAt) > ($1.loggedAt, $1.createdAt) })
        where !entry.isCarriedForward {
            let item = makeItem(entry, keyed: keyed, byPhotoKey: byPhotoKey)
            if recent.count < recentLimit && !recent.contains(where: { $0.key == item.key }) { recent.append(item) }
            if entry.loggedAt >= monthAgo {
                let existing = counts[item.key]
                counts[item.key] = ((existing?.count ?? 0) + 1, existing?.latest ?? item)
            }
        }
        let recentKeys = Set(recent.map(\.key))
        let frequent = counts.values
            .filter { !recentKeys.contains($0.latest.key) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.latest.key < $1.latest.key }
            .prefix(frequentLimit)
            .map(\.latest)
        return (recent.map { withSection($0, .recent) }, frequent.map { withSection($0, .frequent) })
    }

    /// The saved food an entry was made from: by product ID or photo key, else by brand + line +
    /// name. Nil when it no longer exists, and for quick entries.
    static func savedFood(for entry: FoodLogEntry, keyed: [String: Food], byPhotoKey: [String: Food]) -> Food? {
        guard !entry.isQuickEntry else { return nil }
        if let identifier = entry.foodLibraryIdentifier, let food = byPhotoKey[identifier] { return food }
        return keyed[FoodMatching.key(brand: entry.foodBrand, line: entry.foodLine, name: entry.foodName)]
    }

    private static func makeItem(_ entry: FoodLogEntry, keyed: [String: Food], byPhotoKey: [String: Food]) -> Item {
        if entry.isQuickEntry {
            let name = entry.foodName
            return Item(id: "", key: "quick-\(name.lowercased())", target: .quickEntry(name: name, kilocalories: entry.kilocalories),
                        portion: nil, name: name, kind: entry.kind, detail: "\(Portion.formatKilocalories(entry.kilocalories)) kcal")
        }
        if let food = savedFood(for: entry, keyed: keyed, byPhotoKey: byPhotoKey) {
            return Item(id: "", key: "food-\(food.persistentModelID.hashValue)", target: .food(food), portion: entry.portion,
                        name: food.name, brand: food.brandTitle, line: food.line, photoKey: food.photoKey,
                        kind: food.kind, detail: entry.amountDescription)
        }
        let key = FoodMatching.key(brand: entry.foodBrand, line: entry.foodLine, name: entry.foodName)
        return Item(id: "", key: "snapshot-\(key)", target: .snapshot(entry), portion: entry.portion,
                    name: entry.foodName, brand: entry.foodBrand ?? Food.noBrandTitle, line: entry.foodLine,
                    photoKey: entry.foodLibraryIdentifier, kind: entry.kind, detail: entry.amountDescription)
    }

    private static func withSection(_ item: Item, _ section: Section) -> Item {
        var item = item
        item.id = "\(section.rawValue)-\(item.key)"
        return item
    }
}
