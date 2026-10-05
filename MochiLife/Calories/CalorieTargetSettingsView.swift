import SwiftUI

/// Settings for Mochi's daily calorie target: her own target from the vet, or how the estimate
/// is worked out.
struct CalorieTargetSettingsView: View {
    @AppStorage(CalorieTarget.ownTargetKey) private var ownTarget = 0.0
    @AppStorage(CalorieTarget.gainsWeightEasilyKey) private var gainsWeightEasily = false
    @State private var ownTargetText = ""
    @AppStorage("weightUnit") private var weightUnit: WeightUnit = .kilograms

    var body: some View {
        CalorieTargetReader { target in
            Form {
                Section {
                    LabeledContent("Daily calories") {
                        if let kilocalories = target.dailyKilocalories {
                            Text("\(Portion.formatKilocalories(kilocalories)) kcal")
                                .font(.headline)
                                .monospacedDigit()
                        } else {
                            Text("–")
                        }
                    }
                    if target.dailyKilocalories != nil {
                        LabeledContent("Using", value: target.label)
                    }
                }

                Section {
                    HStack {
                        TextField("Your own target", text: $ownTargetText)
                            .keyboardType(.numberPad)
                            .accessibilityIdentifier("ownTarget")
                        Text("\(rangeText) kcal per day")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .rowSeparatorAligned()
                    Button("Save Target") {
                        if let typedTarget { ownTarget = typedTarget }
                    }
                    .disabled(typedTarget == nil || typedTarget == ownTarget)
                    if ownTarget > 0 {
                        Button("Clear and use the estimate", role: .destructive) {
                            ownTarget = 0
                            ownTargetText = ""
                        }
                    }
                } header: {
                    Text("Your own target")
                } footer: {
                    if !ownTargetText.isEmpty && typedTarget == nil {
                        Text("Enter a whole number from \(rangeText) kcal.")
                            .foregroundStyle(.red)
                    } else {
                        Text("For when your vet gives you a number. It replaces the estimate everywhere.")
                    }
                }

                Section {
                    Toggle("Gains weight easily", isOn: $gainsWeightEasily)
                    estimateExplanation(for: target)
                } header: {
                    Text("Estimate")
                } footer: {
                    Text("Based on the Merck Veterinary Manual. The estimate is a starting point, not veterinary advice.")
                }
            }
        }
        .navigationTitle("Daily Calories")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            ownTargetText = ownTarget > 0 ? Portion.formatKilocalories(ownTarget) : ""
        }
    }

    /// The typed target, if it's a whole number within the accepted range.
    private var typedTarget: Double? { NumberInput.dailyTarget.value(ownTargetText) }

    /// "50–1,000"
    private var rangeText: String {
        let range = NumberInput.dailyTarget.range
        return "\(range.lowerBound.formatted())–\(range.upperBound.formatted())"
    }

    @ViewBuilder
    private func estimateExplanation(for target: CalorieTarget) -> some View {
        switch target {
        case .own:
            Text("Your own target is being used instead of the estimate. Clear it to use the estimate.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case let .missing(details):
            MissingCalorieDetailsView(missing: details)
        case let .estimate(estimate):
            VStack(alignment: .leading, spacing: 6) {
                explanationRow("Weight", "\(weightUnit.formatted(kilograms: estimate.weightKilograms)) on \(estimate.weightDate.formatted(.dateTime.month(.abbreviated).day()))")
                if weightUnit == .pounds {
                    explanationRow("In kg", WeightUnit.kilograms.formatted(kilograms: estimate.weightKilograms))
                }
                explanationRow("Age", estimate.age)
                explanationRow("Resting energy", "70 × \(kilogramsText(estimate))^0.75 = \(Portion.formatKilocalories(estimate.restingEnergy)) kcal")
                explanationRow("Factor", "\(estimate.lifeStage.factor.formatted()) (\(estimate.lifeStage.description))")
                explanationRow("Estimate", "\(Portion.formatKilocalories(estimate.restingEnergy)) × \(estimate.lifeStage.factor.formatted()), rounded to the nearest 5 = \(Portion.formatKilocalories(estimate.dailyKilocalories)) kcal per day")
            }
            .font(.subheadline)
        }
    }

    private func kilogramsText(_ estimate: CalorieEstimate) -> String {
        estimate.weightKilograms.formatted(.number.precision(.fractionLength(0...2)))
    }

    private func explanationRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
        }
    }
}
