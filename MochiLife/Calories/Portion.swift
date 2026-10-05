import Foundation

/// How much of a food was chosen in a `PortionPicker`, and its calories.
struct Portion: Equatable {
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
    /// Used when measuring by grams.
    var grams: Double?
    /// Calories worked out from the size and amount, or from grams.
    var calculatedKilocalories: Double?
    /// Calories the user typed in themselves, which replace the worked-out number.
    var customKilocalories: Double?

    var kilocalories: Double? { customKilocalories ?? calculatedKilocalories }

    static let quickFractions: [(label: String, value: Double)] = [
        ("1/4", 1.0 / 4), ("1/3", 1.0 / 3), ("1/2", 1.0 / 2),
        ("2/3", 2.0 / 3), ("3/4", 3.0 / 4), ("1 whole", 1),
    ]

    /// Parses a typed positive number such as "1.5" or "0,75", with up to three decimal places.
    static func parseAmount(_ text: String) -> Double? {
        let normalized = text
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        guard normalized.wholeMatch(of: /\d{0,5}(\.\d{1,3})?/) != nil,
              let value = Double(normalized),
              value > 0
        else { return nil }
        return value
    }

    static func formatKilocalories(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).grouping(.never))
    }

    static func formatAmount(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...3)).grouping(.never))
    }

    /// Describes the amount in plain words, like "1/2 of a 2.8 oz can", "1.5 × 5.5 oz can"
    /// or "20 g".
    var amountDescription: String? {
        switch measure {
        case .containers:
            guard let size, let containers else { return nil }
            if abs(containers - 1) < 0.0001 {
                return "1 whole \(size.name)"
            }
            if let quick = Self.quickFractions.first(where: { abs($0.value - containers) < 0.0001 }) {
                return "\(quick.label) of a \(size.name)"
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
