import Charts
import SwiftData
import SwiftUI

/// Total calories per day as bars, with a line at Mochi's daily target.
struct CalorieChartView: View {
    let target: CalorieTarget

    enum Range: Int, CaseIterable, Identifiable {
        case week = 7
        case month = 30

        var id: Self { self }
        var label: String { "\(rawValue) days" }
    }

    @Query private var allEntries: [FoodLogEntry]
    @State private var range = Range.week

    private var calendar: Calendar { .current }
    private var today: Date { calendar.startOfDay(for: .now) }
    private var firstDay: Date { calendar.date(byAdding: .day, value: -(range.rawValue - 1), to: today) ?? today }

    /// One total per day that has entries, within the chosen range.
    private var dailyTotals: [(day: Date, kilocalories: Double)] {
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let inRange = allEntries.filter { $0.loggedAt >= firstDay && $0.loggedAt < end }
        return Dictionary(grouping: inRange) { calendar.startOfDay(for: $0.loggedAt) }
            .map { (day: $0.key, kilocalories: $0.value.reduce(0) { $0 + $1.kilocalories }) }
            .sorted { $0.day < $1.day }
    }

    private var yDomain: ClosedRange<Double> {
        let highest = max(dailyTotals.map(\.kilocalories).max() ?? 0, target.dailyKilocalories ?? 0)
        return 0...max(highest * 1.15, 10)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Range", selection: $range) {
                ForEach(Range.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            if allEntries.isEmpty {
                ContentUnavailableView(
                    "No calories logged yet",
                    systemImage: "chart.bar",
                    description: Text("Log what Mochi eats to see each day's total here.")
                )
            } else {
                chart
            }
        }
        .padding(.vertical, 8)
    }

    private var chart: some View {
        Chart {
            ForEach(dailyTotals, id: \.day) { total in
                BarMark(
                    x: .value("Day", total.day, unit: .day),
                    y: .value("Calories", total.kilocalories)
                )
                .foregroundStyle(.tint)
            }
            if let kilocalories = target.dailyKilocalories {
                RuleMark(y: .value(target.label, kilocalories))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("\(target.label): \(Portion.formatKilocalories(kilocalories)) kcal")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .chartXScale(domain: firstDay...(calendar.date(byAdding: .day, value: 1, to: today) ?? today))
        .chartYScale(domain: yDomain)
        .chartYAxisLabel("kcal")
        .chartXAxis {
            if range == .week {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                }
            } else {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
        }
        .frame(height: 200)
    }
}
