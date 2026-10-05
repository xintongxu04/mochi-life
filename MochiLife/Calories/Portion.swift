import Foundation

/// How much of a food was chosen in a `PortionPicker`, and its calories.
struct Portion: Hashable {
    enum Measure: Hashable {
        /// A number of whole or part cans or pouches.
        case containers
        case grams
    }

    var measure: Measure = .containers
    /// The chosen size, for foods that come in cans or pouches.
    var size: FoodSize?
    /// How many cans or pouches, e.g. 0.5 for half of one. Used when measuring by container.
    var containers: Double?
    /// The same amount as an exact fraction, e.g. 1/3, for carrying the rest of a can forward.
    var exactContainers: Fraction?
    /// Used when measuring by grams.
    var grams: Double?
    /// Calories worked out from the size and amount, or from grams.
    var calculatedKilocalories: Double?
    /// Calories the user typed in themselves, which replace the worked-out number.
    var customKilocalories: Double?

    var kilocalories: Double? { customKilocalories ?? calculatedKilocalories }

    /// The picker's quick amounts. The full can shows as "1" and is read by VoiceOver as "1 whole".
    static let quickFractions: [(label: String, spokenLabel: String, value: Double, fraction: Fraction)] = [
        ("1/4", "1/4", 1.0 / 4, Fraction(1, 4)), ("1/3", "1/3", 1.0 / 3, Fraction(1, 3)),
        ("1/2", "1/2", 1.0 / 2, Fraction(1, 2)), ("2/3", "2/3", 2.0 / 3, Fraction(2, 3)),
        ("3/4", "3/4", 3.0 / 4, Fraction(3, 4)), ("1", "1 whole", 1, .one),
    ]

    static func formatKilocalories(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).grouping(.never))
    }

    static func formatAmount(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...3)).grouping(.never))
    }

    /// The one formatter for a portion shown as text (day log rows, carried and scheduled
    /// entries, Recent/Frequent, schedules): like "3 oz can" for exactly one, "1/2 of a 2.8 oz
    /// can", "1.5 × 5.5 oz can", or "20 g". Exactly one of a size is just the size's own name,
    /// as stored (so "1 Stick" stays "1 Stick", never "1 1 Stick").
    var amountDescription: String? {
        switch measure {
        case .containers:
            guard let size, let containers else { return nil }
            if exactContainers == .one || (exactContainers == nil && abs(containers - 1) < 0.0001) {
                return size.name
            }
            if let quick = Self.quickFractions.first(where: { abs($0.value - containers) < 0.0001 }) {
                return "\(quick.label) of a \(size.name)"
            }
            if let exact = exactContainers, exact < .one, exact.denominator <= 12 {
                return "\(exact.label) of a \(size.name)"
            }
            return "\(Self.formatAmount(containers)) × \(size.name)"
        case .grams:
            guard let grams else { return nil }
            return "\(Self.formatAmount(grams)) g"
        }
    }
}

/// What a `PortionPicker` needs to know about a food: its sizes and calories per gram. Log
/// entries keep their own copy, so they can still be edited after the food changes.
struct PortionSource: Codable, Hashable {
    var sizes: [FoodSize]
    var kilocaloriesPerGram: Double
}

extension PortionSource {
    init(_ food: Food) {
        self.init(sizes: food.sizes, kilocaloriesPerGram: food.kilocaloriesPerGram)
    }
}
