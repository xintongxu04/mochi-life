import Charts
import SwiftUI

struct WeightChartView: View {
    /// Sorted newest first, matching the list below the chart.
    let entries: [WeightEntry]
    let unit: WeightUnit

    private var oldestFirst: [WeightEntry] { entries.reversed() }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Chart(oldestFirst) { entry in
                LineMark(
                    x: .value("Date", entry.date, unit: .day),
                    y: .value("Weight", unit.value(fromKilograms: entry.kilograms))
                )
                PointMark(
                    x: .value("Date", entry.date, unit: .day),
                    y: .value("Weight", unit.value(fromKilograms: entry.kilograms))
                )
            }
            .chartYScale(domain: yDomain)
            .chartXScale(domain: xDomain)
            .chartYAxisLabel(unit.rawValue)
            .frame(height: 200)

            if let changeSummary {
                Text(changeSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("weightChange")
            }
        }
        .padding(.vertical, 8)
    }

    /// Fits the weight axis to Mochi's actual range, with a little room above and below.
    private var yDomain: ClosedRange<Double> {
        let values = entries.map { unit.value(fromKilograms: $0.kilograms) }
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let minimumPadding = unit == .kilograms ? 0.2 : 0.5
        let padding = max((high - low) * 0.15, minimumPadding)
        return (low - padding)...(high + padding)
    }

    /// Adds a little room on each side so the first and latest dots don't sit on the chart's edges
    /// (and a single day's entries appear in the middle).
    private var xDomain: ClosedRange<Date> {
        let calendar = Calendar.current
        guard let first = oldestFirst.first?.date, let last = oldestFirst.last?.date else {
            return Date.now...Date.now
        }
        let start = calendar.startOfDay(for: first)
        let end = calendar.startOfDay(for: last)
        let oneDay: TimeInterval = 24 * 60 * 60
        let padding = max(end.timeIntervalSince(start) * 0.06, oneDay)
        return start.addingTimeInterval(-padding)...end.addingTimeInterval(padding)
    }

    /// For example "Up 0.30 kg since Jun 12". Nil when there's only one entry.
    private var changeSummary: String? {
        guard entries.count > 1, let first = oldestFirst.first, let latest = entries.first else { return nil }
        // Compare the rounded values shown in the list, so the summary always matches them.
        let change = rounded(unit.value(fromKilograms: latest.kilograms))
            - rounded(unit.value(fromKilograms: first.kilograms))
        let since = first.date.formatted(sinceDateFormat(for: first.date))
        if abs(change) < 0.005 {
            return "No change since \(since)"
        }
        let amount = abs(change).formatted(.number.precision(.fractionLength(2)))
        return "\(change > 0 ? "Up" : "Down") \(amount) \(unit.rawValue) since \(since)"
    }

    private func rounded(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    private func sinceDateFormat(for date: Date) -> Date.FormatStyle {
        let sameYear = Calendar.current.isDate(date, equalTo: .now, toGranularity: .year)
        return sameYear ? .dateTime.month(.abbreviated).day() : .dateTime.month(.abbreviated).day().year()
    }
}
