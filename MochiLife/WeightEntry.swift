import Foundation
import SwiftData

@Model
final class WeightEntry {
    var date: Date
    /// Always stored in kilograms. The unit picker only changes how this is displayed.
    var kilograms: Double
    /// Breaks ties between entries logged for the same day, so the newest shows first.
    var createdAt: Date

    init(date: Date, kilograms: Double, createdAt: Date = .now) {
        self.date = date
        self.kilograms = kilograms
        self.createdAt = createdAt
    }
}
