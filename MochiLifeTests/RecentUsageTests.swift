import Foundation
import SwiftData
import Testing
@testable import MochiLife

/// Recent and Frequent in the Log Food sheet: every logged item stays tappable, ids are unique,
/// and nothing is listed twice.
@MainActor
struct RecentUsageTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let now = Date(timeIntervalSinceReferenceDate: 812_000_000)

    init() throws {
        container = try ModelContainer(for: Schema(versionedSchema: SchemaV4.self),
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func food(_ name: String, brand: String? = nil, seedID: String? = nil) -> Food {
        let food = Food(name: name, kilocaloriesPerGram: 1.5, brand: brand, line: nil, seedID: seedID, createdAt: now)
        context.insert(food)
        return food
    }

    @discardableResult
    private func log(_ food: Food, minutesAgo: Int) -> FoodLogEntry {
        let entry = FoodLogEntry(foodName: food.name, kilocalories: 0, loggedAt: now.addingTimeInterval(Double(-minutesAgo * 60)))
        entry.record(food, portion: Portion(measure: .grams, grams: 10, calculatedKilocalories: 15))
        context.insert(entry)
        return entry
    }

    private func lists() throws -> (recent: [RecentUsage.Item], frequent: [RecentUsage.Item]) {
        try context.save()
        return RecentUsage.lists(entries: try context.fetch(FetchDescriptor<FoodLogEntry>()),
                                 foods: try context.fetch(FetchDescriptor<Food>()), now: now)
    }

    @Test func deletedFoodStaysAsSnapshot() throws {
        let chicken = food("Home Chicken")
        log(chicken, minutesAgo: 5)
        context.delete(chicken)
        let recent = try lists().recent
        #expect(recent.count == 1)
        #expect(recent[0].isInSavedFoods == false)
        #expect(recent[0].name == "Home Chicken")
        #expect(recent[0].portion?.grams == 10)
        guard case .snapshot = recent[0].target else { Issue.record("expected a snapshot item"); return }
    }

    @Test func quickEntryOpensPrefilled() throws {
        context.insert(FoodLogEntry(foodName: "Treat", kilocalories: 5, loggedAt: now))
        let recent = try lists().recent
        #expect(recent.count == 1)
        guard case let .quickEntry(name, kilocalories) = recent[0].target else { Issue.record("expected a quick entry"); return }
        #expect(name == "Treat")
        #expect(kilocalories == 5)
    }

    @Test func foodInRecentIsNotRepeatedInFrequent() throws {
        let favorite = food("Favorite")
        for minutes in [10, 20, 30] { log(favorite, minutesAgo: minutes) }
        log(food("Other"), minutesAgo: 1)
        var (recent, frequent) = try lists()
        #expect(recent.map(\.name) == ["Other", "Favorite"])
        #expect(frequent.isEmpty)

        // Pushed out of Recent by eight newer foods, the favorite shows in Frequent once.
        for index in 0..<8 { log(food("Newer \(index)"), minutesAgo: index) }
        (recent, frequent) = try lists()
        #expect(recent.count == 8)
        #expect(!recent.contains { $0.name == "Favorite" })
        #expect(frequent.filter { $0.name == "Favorite" }.count == 1)
        let ids = (recent + frequent).map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(recent.allSatisfy { $0.id.hasPrefix("recent-") } && frequent.allSatisfy { $0.id.hasPrefix("frequent-") })
    }

    @Test func sameNameDifferentFoodsAreSeparateRows() throws {
        let first = food("Chicken Pâté", seedID: "seed-a")
        let second = food("Chicken Pâté", seedID: "seed-b")
        log(first, minutesAgo: 2)
        log(second, minutesAgo: 1)
        let recent = try lists().recent
        #expect(recent.count == 2)
        #expect(Set(recent.map(\.id)).count == 2)
        let resolved: [Food] = recent.compactMap { if case let .food(food) = $0.target { food } else { nil } }
        #expect(Set(resolved.map(\.seedID)) == ["seed-a", "seed-b"])
    }
}
