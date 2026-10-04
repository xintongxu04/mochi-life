import Foundation
import SwiftData

@Model
final class Food {
    var name: String
    var kilocaloriesPerGram: Double
    var createdAt: Date

    init(name: String, kilocaloriesPerGram: Double, createdAt: Date = .now) {
        self.name = name
        self.kilocaloriesPerGram = kilocaloriesPerGram
        self.createdAt = createdAt
    }

    /// No cat food comes close to this; a bigger number almost always means a per-100 g value
    /// was typed as per gram.
    static let maximumKilocaloriesPerGram = 10.0

    var formattedKilocaloriesPerGram: String {
        "\(kilocaloriesPerGram.formatted(.number.precision(.fractionLength(2...3)))) kcal/g"
    }
}

extension Array where Element == Food {
    func sortedByName() -> [Food] {
        sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
