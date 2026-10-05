import Foundation

enum WeightUnit: String, CaseIterable, Identifiable {
    case kilograms = "kg"
    case pounds = "lb"

    var id: Self { self }

    private static let poundsPerKilogram = 2.20462262185

    /// Converts a stored kilogram value into this unit, for display only.
    func value(fromKilograms kilograms: Double) -> Double {
        switch self {
        case .kilograms: kilograms
        case .pounds: kilograms * Self.poundsPerKilogram
        }
    }

    /// Converts a value typed in this unit into kilograms, for saving.
    func kilograms(from value: Double) -> Double {
        switch self {
        case .kilograms: value
        case .pounds: value / Self.poundsPerKilogram
        }
    }

    func formatted(kilograms: Double) -> String {
        let value = value(fromKilograms: kilograms)
        return "\(value.formatted(.number.precision(.fractionLength(2)))) \(rawValue)"
    }
}
