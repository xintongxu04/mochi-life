import SwiftUI

/// Picks a size and portion of a food and works out its calories. Place it inside a `Form`
/// or `List`; it adds its own sections. Used on the food detail screen, and meant to be reused
/// when logging what Mochi eats.
struct PortionPicker: View {
    let food: Food
    @Binding var portion: Portion

    @State private var measure: Portion.Measure
    @State private var sizeIndex = 0
    @State private var quickFraction: Double? = 1
    @State private var amountText = ""
    @State private var gramsText = ""
    @State private var caloriesText = ""
    @State private var isCustomCalories = false

    init(food: Food, portion: Binding<Portion>) {
        self.food = food
        _portion = portion
        _measure = State(initialValue: food.sizes.isEmpty ? .grams : .containers)
    }

    private var size: FoodSize? {
        food.sizes.indices.contains(sizeIndex) ? food.sizes[sizeIndex] : nil
    }

    private var containerName: String { size?.containerName ?? "can" }

    private var kilocaloriesPerGram: Double {
        size?.kilocaloriesPerGram ?? food.kilocaloriesPerGram
    }

    private var containers: Double? {
        quickFraction ?? Portion.parseAmount(amountText)
    }

    private var grams: Double? { Portion.parseAmount(gramsText) }

    private var calculatedKilocalories: Double? {
        switch measure {
        case .containers:
            guard let size, let containers else { return nil }
            return size.kilocalories * containers
        case .grams:
            return grams.map { $0 * kilocaloriesPerGram }
        }
    }

    private var currentPortion: Portion {
        Portion(
            measure: measure,
            size: size,
            containers: measure == .containers ? containers : nil,
            grams: measure == .grams ? grams : nil,
            calculatedKilocalories: calculatedKilocalories,
            customKilocalories: isCustomCalories ? Portion.parseAmount(caloriesText) : nil
        )
    }

    private var calculatedText: String {
        calculatedKilocalories.map(Portion.formatKilocalories) ?? ""
    }

    var body: some View {
        Section("Portion") {
            if food.sizes.count > 1 {
                Picker("Size", selection: $sizeIndex) {
                    ForEach(food.sizes.indices, id: \.self) { index in
                        Text(food.sizes[index].name).tag(index)
                    }
                }
            }
            if !food.sizes.isEmpty {
                Picker("Measure by", selection: $measure) {
                    Text("By \(containerName)").tag(Portion.Measure.containers)
                    Text("By grams").tag(Portion.Measure.grams)
                }
                .pickerStyle(.segmented)
            }
            switch measure {
            case .containers:
                containerRows
            case .grams:
                gramsRow
            }
        }
        Section {
            HStack {
                Text("Calories")
                TextField("Calories", text: $caloriesText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.title3.bold())
                    .accessibilityIdentifier("portionCalories")
                Text("kcal")
                    .foregroundStyle(.secondary)
            }
            if isCustomCalories {
                Button("Use worked-out number (\(calculatedText.isEmpty ? "–" : calculatedText) kcal)") {
                    isCustomCalories = false
                    caloriesText = calculatedText
                }
            }
        } footer: {
            Text(caloriesExplanation)
                .accessibilityIdentifier("portionExplanation")
        }
        .onAppear { caloriesText = calculatedText }
        .onChange(of: calculatedText) {
            if !isCustomCalories { caloriesText = calculatedText }
        }
        .onChange(of: caloriesText) {
            if caloriesText != calculatedText { isCustomCalories = true }
        }
        .onChange(of: measure) { switchedMeasure() }
        .onChange(of: currentPortion, initial: true) { portion = currentPortion }
    }

    @ViewBuilder
    private var containerRows: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
            ForEach(Portion.quickFractions, id: \.label) { fraction in
                let isSelected = quickFraction == fraction.value
                Button(fraction.label) {
                    quickFraction = fraction.value
                    amountText = ""
                }
                .buttonStyle(.bordered)
                .tint(isSelected ? .accentColor : .secondary)
                .fontWeight(isSelected ? .semibold : .regular)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
        HStack {
            Text("Other amount")
            TextField("e.g. 1.5", text: $amountText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier("portionAmount")
                .onChange(of: amountText) {
                    if !amountText.isEmpty { quickFraction = nil }
                }
            Text(amountText == "1" ? containerName : "\(containerName)s")
                .foregroundStyle(.secondary)
        }
    }

    private var gramsRow: some View {
        HStack {
            Text("Amount")
            TextField("Grams", text: $gramsText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier("portionGrams")
            Text("g")
                .foregroundStyle(.secondary)
        }
    }

    private var caloriesExplanation: String {
        if isCustomCalories {
            return "Using your own number."
        }
        let perGram = kilocaloriesPerGram.formatted(.number.precision(.fractionLength(2...3)))
        switch measure {
        case .containers:
            guard let size else { return "" }
            return "Worked out from \(Portion.formatKilocalories(size.kilocalories)) kcal per \(size.name)."
        case .grams:
            if let size {
                let wholeGrams = size.grams.formatted(.number.precision(.fractionLength(0...1)))
                return "Worked out from \(perGram) kcal per gram. One whole \(size.name) is \(wholeGrams) g."
            }
            return "Worked out from \(perGram) kcal per gram."
        }
    }

    /// When switching to grams, start from the grams in the chosen portion so nothing is lost.
    private func switchedMeasure() {
        guard measure == .grams, gramsText.isEmpty, let size, let containers else { return }
        gramsText = (size.grams * containers).formatted(.number.precision(.fractionLength(0...1)).grouping(.never))
    }
}
