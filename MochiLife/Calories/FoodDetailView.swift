import SwiftUI

struct FoodDetailView: View {
    let food: Food

    @State private var portion = Portion()
    @State private var isEditing = false
    @State private var isLogging = false

    var body: some View {
        Form {
            Section {
                FoodThumbnail(food: food, size: 160)
                    .frame(maxWidth: .infinity)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(food.name)
                        .font(.title2.bold())
                    Text([food.brandTitle, food.line].compactMap(\.self).joined(separator: " · "))
                        .foregroundStyle(.secondary)
                    if food.kind != .food {
                        Text(food.kind.rawValue.capitalized)
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.tint.opacity(0.15), in: .capsule)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Calories") {
                ForEach(food.sizes, id: \.self) { size in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(size.name)
                            Text("\(size.grams.formatted(.number.precision(.fractionLength(0...1)))) g · \(size.kilocaloriesPerGram.formatted(.number.precision(.fractionLength(2...3)))) kcal/g")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if size.isCalculated {
                            Text("calculated")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .overlay(Capsule().stroke(.secondary.opacity(0.5)))
                        }
                        Text("\(Portion.formatKilocalories(size.kilocalories)) kcal per \(size.containerName)")
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("sizeCalories")
                }
                if food.sizes.isEmpty {
                    LabeledContent("Per gram", value: food.formattedKilocaloriesPerGram)
                }
                if let statement = food.calorieStatement {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("As written by the brand")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(statement)
                    }
                }
            }

            PortionPicker(food: food, portion: $portion)

            Section {
                Button {
                    isLogging = true
                } label: {
                    Label("Log This", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .disabled(portion.kilocalories == nil)
            }

            if let ingredients = food.ingredients {
                Section("Ingredients") {
                    Text(ingredients)
                }
            }

            if !food.guaranteedAnalysis.isEmpty {
                Section("Guaranteed Analysis") {
                    Grid(alignment: .leading, verticalSpacing: 8) {
                        ForEach(food.guaranteedAnalysis, id: \.self) { row in
                            GridRow {
                                Text(row.nutrient)
                                Text(row.amount)
                                    .monospacedDigit()
                                    .gridColumnAlignment(.trailing)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }

            if !food.notes.isEmpty {
                Section("Notes") {
                    ForEach(food.notes, id: \.self) { note in
                        Text(note)
                    }
                }
            }

            if let sourceURL = food.sourceURL {
                Section("Source") {
                    Link(sourceURL.host() ?? sourceURL.absoluteString, destination: sourceURL)
                }
            }
        }
        .navigationTitle(food.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Edit") { isEditing = true }
        }
        .sheet(isPresented: $isEditing) {
            FoodFormView(food: food)
        }
        .sheet(isPresented: $isLogging) {
            NavigationStack {
                // Starts from the size and portion already chosen on this screen.
                LogEntryForm(mode: .logFood(food, startingFrom: portion), onFinish: { isLogging = false })
            }
        }
    }
}
