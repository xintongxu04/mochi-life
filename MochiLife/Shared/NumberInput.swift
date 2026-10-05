import Foundation

/// Reads numbers people type. Used by every numeric field so they all behave the same:
/// surrounding spaces are ignored, "." and "," both work as the decimal separator, and
/// negative, non-finite or out-of-range values are rejected.
enum NumberInput {
    /// Returns the typed value, or nil if it isn't a plain number within `range` with at most
    /// `maximumFractionDigits` decimal places.
    static func value(_ text: String, in range: ClosedRange<Double>, maximumFractionDigits: Int) -> Double? {
        guard let decimal = decimal(text, maximumFractionDigits: maximumFractionDigits) else { return nil }
        let value = NSDecimalNumber(decimal: decimal).doubleValue
        guard value.isFinite, range.contains(value) else { return nil }
        return value
    }

    /// The typed value as an exact fraction, e.g. "0.4" is 2/5, for portions of a can.
    static func fraction(_ text: String, in range: ClosedRange<Double>, maximumFractionDigits: Int) -> Fraction? {
        guard value(text, in: range, maximumFractionDigits: maximumFractionDigits) != nil,
              let normalized = normalize(text),
              let match = normalized.wholeMatch(of: /(\d*)(?:\.(\d+))?/)
        else { return nil }
        let decimals = match.2.map(String.init) ?? ""
        let scale = Int(pow(10, Double(decimals.count)))
        let whole = Int(match.1) ?? 0
        return Fraction(whole * scale + (Int(decimals) ?? 0), scale)
    }

    private static func decimal(_ text: String, maximumFractionDigits: Int) -> Decimal? {
        guard let normalized = normalize(text),
              let match = normalized.wholeMatch(of: /(\d*)(?:\.(\d+))?/),
              !(match.1.isEmpty && match.2 == nil),
              (match.2?.count ?? 0) <= maximumFractionDigits,
              match.1.count <= 9
        else { return nil }
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Trims spaces and turns the user's decimal separator (or a comma) into ".".
    private static func normalize(_ text: String) -> String? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let separator = Locale.current.decimalSeparator, separator != "." {
            trimmed = trimmed.replacingOccurrences(of: separator, with: ".")
        }
        trimmed = trimmed.replacingOccurrences(of: ",", with: ".")
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// The accepted range and decimal places for each kind of number the app asks for.
extension NumberInput {
    struct Field {
        var range: ClosedRange<Double>
        var maximumFractionDigits: Int

        func value(_ text: String) -> Double? {
            NumberInput.value(text, in: range, maximumFractionDigits: maximumFractionDigits)
        }

        func fraction(_ text: String) -> Fraction? {
            NumberInput.fraction(text, in: range, maximumFractionDigits: maximumFractionDigits)
        }
    }

    /// A weight in kg or lb.
    static let weight = Field(range: 0.01...999.99, maximumFractionDigits: 2)
    /// How many cans or pouches.
    static let containers = Field(range: 0.001...100, maximumFractionDigits: 3)
    /// An amount in grams.
    static let grams = Field(range: 0.001...10_000, maximumFractionDigits: 3)
    /// Calories for one entry, or for a whole can or pouch.
    static let kilocalories = Field(range: 0.001...10_000, maximumFractionDigits: 3)
    /// Calories per gram or per 100 g as typed on the food form (sanity limits are checked
    /// separately so the form can explain them).
    static let foodCalories = Field(range: 0.001...99_999, maximumFractionDigits: 3)
    /// A guaranteed-analysis percentage.
    static let percent = Field(range: 0...100, maximumFractionDigits: 2)
    /// The owner's own daily calorie target.
    static let dailyTarget = Field(range: 50...1_000, maximumFractionDigits: 0)
}
