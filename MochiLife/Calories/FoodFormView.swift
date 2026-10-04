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
    @State private var basis = CalorieBasis.perGram
    @State private var caloriesText = ""
    @State private var originalCaloriesText = ""

    init(food: Food?) {
        self.food = food
        if let food {
            let text = food.kilocaloriesPerGram.formatted(.number.precision(.fractionLength(0...3)).grouping(.never))
            _name = State(initialValue: food.name)
            _caloriesText = State(initialValue: text)
            _originalCaloriesText = State(initialValue: text)
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var kilocaloriesPerGram: Double? {
        guard let value = Self.parseCalories(caloriesText) else { return nil }
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

    private var canSave: Bool {
        !trimmedName.isEmpty && kilocaloriesPerGram != nil && caloriesProblem == nil
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)
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

    private func save() {
        guard canSave, let kilocaloriesPerGram else { return }
        if let food {
            food.name = trimmedName
            // Only replace the saved value if it was actually changed, so opening and saving
            // a food never loses precision from the rounded number shown in the form.
            if caloriesText != originalCaloriesText || basis != .perGram {
                food.kilocaloriesPerGram = kilocaloriesPerGram
            }
        } else {
            modelContext.insert(Food(name: trimmedName, kilocaloriesPerGram: kilocaloriesPerGram))
        }
        try? modelContext.save()
        dismiss()
    }

    /// Parses a typed number such as "3", "3.5" or "385,25". Returns nil unless it is
    /// a positive number with at most three decimal places.
    static func parseCalories(_ text: String) -> Double? {
        let normalized = text
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        guard normalized.wholeMatch(of: /\d{1,5}(\.\d{1,3})?/) != nil,
              let value = Double(normalized),
              value > 0
        else { return nil }
        return value
    }
}
