import SwiftData
import SwiftUI

/// Adds a new food, or edits an existing one when `food` is set.
struct FoodFormView: View {
    let food: Food?

    enum CalorieBasis: String, CaseIterable, Identifiable {
        case perGram = "per gram"
        case per100Grams = "per 100 g"

        var id: Self { self }
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var brand = ""
    @State private var line = ""
    @State private var basis = CalorieBasis.perGram
    @State private var caloriesText = ""
    @State private var originalCaloriesText = ""
    /// For foods that come in cans or pouches: calories per whole container, one per size.
    @State private var sizeCaloriesTexts: [String] = []
    @State private var originalSizeCaloriesTexts: [String] = []

    /// - Parameter initialName: Prefills the name of a new food (e.g. after an AI lookup found nothing).
    init(food: Food?, initialName: String? = nil) {
        self.food = food
        if food == nil, let initialName {
            _name = State(initialValue: initialName)
        }
        if let food {
            let text = food.kilocaloriesPerGram.formatted(.number.precision(.fractionLength(0...3)).grouping(.never))
            let sizeTexts = food.sizes.map { Portion.formatKilocalories($0.kilocalories) }
            _name = State(initialValue: food.name)
            _brand = State(initialValue: food.brand ?? "")
            _line = State(initialValue: food.line ?? "")
            _caloriesText = State(initialValue: text)
            _originalCaloriesText = State(initialValue: text)
            _sizeCaloriesTexts = State(initialValue: sizeTexts)
            _originalSizeCaloriesTexts = State(initialValue: sizeTexts)
        }
    }

    private var sizes: [FoodSize] { food?.sizes ?? [] }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func optional(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var kilocaloriesPerGram: Double? {
        guard let value = NumberInput.foodCalories.value(caloriesText) else { return nil }
        switch basis {
        case .perGram: return value
        case .per100Grams: return value / 100
        }
    }

    private var caloriesProblem: String? {
        guard !caloriesText.isEmpty else { return nil }
        guard let kilocaloriesPerGram else {
            return "Enter a number like 3.5, with up to three decimal places."
        }
        if kilocaloriesPerGram > Food.maximumKilocaloriesPerGram {
            return basis == .perGram
                ? "That's more than 10 kcal per gram. Did you mean per 100 g?"
                : "That's more than 1,000 kcal per 100 g, which is too high for any food."
        }
        return nil
    }

    /// Explains what's wrong with the calories typed for a size, or nil if they look right.
    private func sizeCaloriesProblem(at index: Int) -> String? {
        guard let kilocalories = NumberInput.kilocalories.value(sizeCaloriesTexts[index]) else {
            return "Enter a number like 116 for each size."
        }
        let size = sizes[index]
        if kilocalories / size.grams > Food.maximumKilocaloriesPerGram {
            return "\(Portion.formatKilocalories(kilocalories)) kcal is too much for a \(size.name). Please check it."
        }
        return nil
    }

    private var sizeCaloriesAreValid: Bool {
        sizeCaloriesTexts.indices.allSatisfy { sizeCaloriesProblem(at: $0) == nil }
    }

    private var canSave: Bool {
        guard !trimmedName.isEmpty else { return false }
        if sizes.isEmpty {
            return kilocaloriesPerGram != nil && caloriesProblem == nil
        }
        return sizeCaloriesAreValid
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                    TextField("Brand (optional)", text: $brand)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("Brand")
                    TextField("Line (optional)", text: $line)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("Line")
                }
                if sizes.isEmpty {
                    perGramSection
                } else {
                    sizesSection
                }
            }
            .navigationTitle(food == nil ? "Add Food" : "Edit Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
        }
    }

    private var perGramSection: some View {
        Section {
            Picker("Calories", selection: $basis) {
                ForEach(CalorieBasis.allCases) { basis in
                    Text(basis.rawValue).tag(basis)
                }
            }
            .pickerStyle(.segmented)
            HStack {
                TextField("Calories", text: $caloriesText)
                    .keyboardType(.decimalPad)
                Text(basis == .perGram ? "kcal/g" : "kcal/100 g")
                    .foregroundStyle(.secondary)
            }
        } footer: {
            if let caloriesProblem {
                Text(caloriesProblem)
                    .foregroundStyle(.red)
            } else if basis == .per100Grams, let kilocaloriesPerGram {
                Text("That's \(kilocaloriesPerGram.formatted(.number.precision(.fractionLength(2...3)))) kcal per gram.")
                    .accessibilityIdentifier("convertedCalories")
            } else {
                Text("You'll usually find this on the food's label.")
            }
        }
    }

    private var sizesSection: some View {
        Section {
            ForEach(sizes.indices, id: \.self) { index in
                HStack {
                    Text(sizes[index].name)
                    TextField("Calories", text: $sizeCaloriesTexts[index])
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("sizeCaloriesField")
                    Text("kcal")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Calories per whole can or pouch")
        } footer: {
            if let problem = sizeCaloriesTexts.indices.lazy.compactMap(sizeCaloriesProblem).first {
                Text(problem)
                    .foregroundStyle(.red)
            } else {
                Text("Calories per gram are worked out from each size's weight.")
            }
        }
    }

    private func save() {
        guard canSave else { return }
        if let food {
            if food.seedID != nil || food.libraryIdentifier != nil {
                food.isUserModified = true
            }
            food.name = trimmedName
            food.brand = optional(brand)
            food.line = optional(line)
            if sizes.isEmpty {
                // Only replace the saved value if it was actually changed, so opening and saving
                // a food never loses precision from the rounded number shown in the form.
                if let kilocaloriesPerGram, caloriesText != originalCaloriesText || basis != .perGram {
                    food.kilocaloriesPerGram = kilocaloriesPerGram
                }
            } else {
                var updatedSizes = food.sizes
                for index in updatedSizes.indices
                where sizeCaloriesTexts[index] != originalSizeCaloriesTexts[index] {
                    guard let kilocalories = NumberInput.kilocalories.value(sizeCaloriesTexts[index]) else { continue }
                    updatedSizes[index].kilocalories = kilocalories
                    updatedSizes[index].kilocaloriesPerGram = kilocalories / updatedSizes[index].grams
                    updatedSizes[index].isCalculated = false
                }
                food.sizes = updatedSizes
                food.kilocaloriesPerGram = updatedSizes.first?.kilocaloriesPerGram ?? food.kilocaloriesPerGram
            }
        } else if let kilocaloriesPerGram {
            let food = Food(
                name: trimmedName,
                kilocaloriesPerGram: kilocaloriesPerGram,
                brand: optional(brand),
                line: optional(line)
            )
            food.origin = .manual
            modelContext.insert(food)
        }
        if Persistence.save(modelContext) { dismiss() }
    }
}
