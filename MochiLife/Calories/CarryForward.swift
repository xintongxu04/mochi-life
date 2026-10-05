import Foundation

/// An exact fraction like 1/3, so portions of a can always add up to exactly one whole.
struct Fraction: Hashable, Comparable, Codable {
    private(set) var numerator: Int
    private(set) var denominator: Int

    init(_ numerator: Int, _ denominator: Int) {
        precondition(denominator != 0)
        let sign = denominator < 0 ? -1 : 1
        let divisor = Swift.max(Self.gcd(abs(numerator), abs(denominator)), 1)
        self.numerator = sign * numerator / divisor
        self.denominator = sign * denominator / divisor
    }

    static let zero = Fraction(0, 1)
    static let one = Fraction(1, 1)

    /// Reads typed amounts like "1.5", ".25" or "0,4" exactly (1.5 is 3/2, not 1.4999…).
    init?(decimalText text: String) {
        let normalized = text
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        guard let match = normalized.wholeMatch(of: /(\d{0,5})(?:\.(\d{1,3}))?/) else { return nil }
        let whole = Int(match.1) ?? 0
        let decimals = match.2.map(String.init) ?? ""
        let scale = Int(pow(10, Double(decimals.count)))
        let value = Fraction(whole * scale + (Int(decimals) ?? 0), scale)
        guard value > .zero else { return nil }
        self = value
    }

    var doubleValue: Double { Double(numerator) / Double(denominator) }

    /// The part after the whole cans, e.g. 1/2 for 3/2.
    var fractionalPart: Fraction { Fraction(numerator % denominator, denominator) }

    /// Like "1/4", or "1" for a whole.
    var label: String { denominator == 1 ? "\(numerator)" : "\(numerator)/\(denominator)" }

    static func + (lhs: Fraction, rhs: Fraction) -> Fraction {
        Fraction(lhs.numerator * rhs.denominator + rhs.numerator * lhs.denominator, lhs.denominator * rhs.denominator)
    }

    static func - (lhs: Fraction, rhs: Fraction) -> Fraction {
        Fraction(lhs.numerator * rhs.denominator - rhs.numerator * lhs.denominator, lhs.denominator * rhs.denominator)
    }

    static func < (lhs: Fraction, rhs: Fraction) -> Bool {
        lhs.numerator * rhs.denominator < rhs.numerator * lhs.denominator
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        b == 0 ? a : gcd(b, a % b)
    }
}

/// When less than a whole can or pouch is logged, the rest is used up over the following days
/// in the same portion, one entry per day; the last day gets whatever is left.
enum CarryForward {
    /// Plans longer than this ask first.
    static let daysBeforeAsking = 7
    /// Amounts so small they'd take longer than this aren't carried forward at all.
    static let maximumDays = 90

    /// The portion for each following day, e.g. [1/4, 1/4, 1/4] for 1/4. Empty when nothing's
    /// left over (whole cans) or the plan would be too long. For more than one can (like 1.5),
    /// the rest of the last can is carried forward the same way.
    static func plan(for amount: Fraction) -> [Fraction] {
        let used = amount.fractionalPart
        guard amount > .zero, used > .zero else { return [] }
        var remaining = Fraction.one - used
        var portions: [Fraction] = []
        while remaining > .zero {
            let portion = Swift.min(amount, remaining)
            portions.append(portion)
            remaining = remaining - portion
            if portions.count > maximumDays { return [] }
        }
        return portions
    }

    /// One line describing a plan, like "1/4 can each day through Thursday" or
    /// "1/3 can each day through Tuesday, then 1/5 can on Wednesday".
    static func preview(of portions: [Fraction], containerName: String, startingAfter day: Date,
                        calendar: Calendar = .current) -> String {
        guard let first = portions.first, let last = portions.last else { return "" }
        func dayName(_ offset: Int) -> String {
            let date = calendar.date(byAdding: .day, value: offset, to: day) ?? day
            return offset > 6
                ? date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
                : date.formatted(.dateTime.weekday(.wide))
        }
        if portions.count == 1 {
            return "\(first.label) \(containerName) on \(dayName(1))"
        }
        if first == last {
            return "\(first.label) \(containerName) each day through \(dayName(portions.count))"
        }
        let fullDays = portions.count - 1
        let start = fullDays == 1
            ? "\(first.label) \(containerName) on \(dayName(1))"
            : "\(first.label) \(containerName) each day through \(dayName(fullDays))"
        return "\(start), then \(last.label) \(containerName) on \(dayName(portions.count))"
    }
}
