import Foundation
import SwiftData

/// Data upkeep that runs each time the app opens. Every step is safe to repeat.
@MainActor
enum LaunchMaintenance {
    static func run(in context: ModelContext) {
        _ = CatProfile.current(in: context)
        FoodLibraryLoader.updateBundledLibraries(in: context)
        deriveMissingFractions(in: context)
        // Repeat-safe: anything still without a kind gets one (normally done by the migration).
        FoodKindBackfill.run(in: context)
        ScheduleUpgrade.run(in: context)
        if context.hasChanges { Persistence.save(context) }
        ScheduleMaterializer(context: context).materialize()
    }

    /// Entries logged by can or pouch before exact fractions were stored get one when their
    /// amount is within 1e-6 of a fraction with denominator 12 or less (e.g. 0.333333 → 1/3).
    /// Other amounts are left unchanged.
    static func deriveMissingFractions(in context: ModelContext) {
        let entries = (try? context.fetch(FetchDescriptor<FoodLogEntry>(
            predicate: #Predicate { $0.measureRawValue == "containers" && $0.containersNumerator == nil }
        ))) ?? []
        var changed = false
        for entry in entries {
            guard let containers = entry.containers, let fraction = Fraction.nearest(to: containers) else { continue }
            entry.containersNumerator = fraction.numerator
            entry.containersDenominator = fraction.denominator
            changed = true
        }
        if changed { Persistence.save(context) }
    }
}
