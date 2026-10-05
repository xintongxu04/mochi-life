import PhotosUI
import SwiftData
import SwiftUI

/// Review and edit what an AI lookup found. Nothing is saved until Save.
struct FoodReviewView: View {
    let onSaved: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query private var foods: [Food]

    @State private var brand: String
    @State private var line: String
    @State private var name: String
    @State private var kind: FoodKind
    @State private var sizes: [EditableSize]
    @State private var perGramText: String
    @State private var calorieStatement: String
    @State private var ingredients: String
    @State private var proteinText: String
    @State private var fatText: String
    @State private var fiberText: String
    @State private var moistureText: String
    @State private var otherAnalysis: String
    @State private var thumbnailJPEG: Data?
    @State private var photoItem: PhotosPickerItem?
    @State private var duplicate: Food?
    private let draft: FoodDraft

    struct EditableSize: Identifiable {
        var id = UUID()
        var label: String
        var gramsText: String
        var caloriesText: String
        var isCalculated: Bool
    }

    init(draft: FoodDraft, onSaved: @escaping () -> Void) {
        self.draft = draft
        self.onSaved = onSaved
        func text(_ value: Double?, digits: Int = 2) -> String {
            value.map { $0.formatted(.number.precision(.fractionLength(0...digits)).grouping(.never)) } ?? ""
        }
        _brand = State(initialValue: draft.brand)
        _line = State(initialValue: draft.line)
        _name = State(initialValue: draft.name)
        _kind = State(initialValue: draft.kind)
        _sizes = State(initialValue: draft.sizes.map {
            EditableSize(label: $0.label, gramsText: text($0.grams, digits: 1), caloriesText: text($0.kilocalories, digits: 1),
                         isCalculated: $0.isCalculated)
        })
        _perGramText = State(initialValue: text(draft.kilocaloriesPerGram, digits: 3))
        _calorieStatement = State(initialValue: draft.calorieStatement)
        _ingredients = State(initialValue: draft.ingredients)
        _proteinText = State(initialValue: text(draft.proteinMinPercent))
        _fatText = State(initialValue: text(draft.fatMinPercent))
        _fiberText = State(initialValue: text(draft.fiberMaxPercent))
        _moistureText = State(initialValue: text(draft.moistureMaxPercent))
        _otherAnalysis = State(initialValue: draft.otherAnalysis.joined(separator: "\n"))
        _thumbnailJPEG = State(initialValue: draft.thumbnailJPEG)
    }

    // MARK: - Validation

    private func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Sizes with both a weight and calories, which is what the portion picker needs.
    private var completeSizes: [FoodSize] {
        sizes.compactMap { size in
            guard !trimmed(size.label).isEmpty,
                  let grams = NumberInput.grams.value(size.gramsText),
                  let kilocalories = NumberInput.kilocalories.value(size.caloriesText),
                  kilocalories / grams <= Food.maximumKilocaloriesPerGram
            else { return nil }
            return FoodSize(name: trimmed(size.label), grams: grams, kilocalories: kilocalories,
                            kilocaloriesPerGram: kilocalories / grams, isCalculated: size.isCalculated)
        }
    }

    private var kilocaloriesPerGram: Double? {
        if let typed = NumberInput.foodCalories.value(perGramText), typed <= Food.maximumKilocaloriesPerGram {
            return typed
        }
        return completeSizes.first?.kilocaloriesPerGram
    }

    private var canSave: Bool { !trimmed(name).isEmpty && kilocaloriesPerGram != nil }

    private var saveProblem: String? {
        if trimmed(name).isEmpty { return "Add the product name." }
        if kilocaloriesPerGram == nil { return "Add calories per gram, or a size with its grams and calories." }
        return nil
    }

    // MARK: - Form

    var body: some View {
        Form {
            identitySection
            sizesSection
            Section("Calorie statement") {
                TextField("As written on the label", text: $calorieStatement, axis: .vertical)
            }
            Section("Ingredients") {
                TextField("Ingredients", text: $ingredients, axis: .vertical)
                    .lineLimit(3...12)
            }
            analysisSection
            photoSection
            sourceSection
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(!canSave)
            }
        }
        .confirmationDialog(
            "\(duplicate?.name ?? "This food") is already saved",
            isPresented: Binding(get: { duplicate != nil }, set: { if !$0 { duplicate = nil } }),
            titleVisibility: .visible,
            presenting: duplicate
        ) { existing in
            Button("Update Existing") { store(into: existing) }
            Button("Save as New") { store(into: nil) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Update the saved food with these details, or keep both.")
        }
        .onChange(of: photoItem) {
            guard let photoItem else { return }
            Task {
                if let data = try? await photoItem.loadTransferable(type: Data.self) {
                    thumbnailJPEG = await Task.detached { FoodThumbnailStore.thumbnailJPEG(from: data) }.value
                }
                self.photoItem = nil
            }
        }
    }

    private var identitySection: some View {
        Section {
            TextField("Brand", text: $brand)
                .textInputAutocapitalization(.words)
            TextField("Line (optional)", text: $line)
                .textInputAutocapitalization(.words)
            TextField("Product name", text: $name, axis: .vertical)
                .textInputAutocapitalization(.words)
            Picker("Type", selection: $kind) {
                ForEach(FoodKind.allCases, id: \.self) { kind in
                    Text(kind.rawValue.capitalized).tag(kind)
                }
            }
        } header: {
            Text("Product")
        } footer: {
            if let saveProblem {
                Text(saveProblem).foregroundStyle(.red)
            }
        }
    }

    private var sizesSection: some View {
        Section {
            ForEach($sizes) { $size in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        TextField("Size, like 2.8 oz can", text: $size.label)
                        if size.isCalculated {
                            Text("calculated")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .overlay(Capsule().stroke(.secondary.opacity(0.5)))
                                .accessibilityLabel("Calories calculated from kcal per kilogram")
                        }
                    }
                    HStack {
                        TextField("Grams", text: $size.gramsText)
                            .keyboardType(.decimalPad)
                            .accessibilityLabel("Grams in \(size.label)")
                        Text("g").foregroundStyle(.secondary)
                        TextField("Calories", text: $size.caloriesText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .accessibilityLabel("Calories in one whole \(size.label)")
                            .onChange(of: size.caloriesText) { size.isCalculated = false }
                        Text("kcal").foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { sizes.remove(atOffsets: $0) }
            Button("Add Size", systemImage: "plus") {
                sizes.append(EditableSize(label: "", gramsText: "", caloriesText: "", isCalculated: false))
            }
            HStack {
                Text("Per gram")
                TextField("kcal/g", text: $perGramText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel("Calories per gram")
                Text("kcal/g").foregroundStyle(.secondary)
            }
        } header: {
            Text("Sizes and calories")
        } footer: {
            Text("Calories are for one whole can or pouch. Sizes without both grams and calories aren't saved.")
        }
    }

    private var analysisSection: some View {
        Section {
            percentRow("Crude protein (min)", $proteinText)
            percentRow("Crude fat (min)", $fatText)
            percentRow("Crude fiber (max)", $fiberText)
            percentRow("Moisture (max)", $moistureText)
            TextField("Other lines, one per line", text: $otherAnalysis, axis: .vertical)
                .lineLimit(1...8)
        } header: {
            Text("Guaranteed analysis")
        }
    }

    private func percentRow(_ label: String, _ text: Binding<String>) -> some View {
        HStack {
            Text(label)
            TextField("–", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel(label)
            Text("%").foregroundStyle(.secondary)
        }
    }

    private var photoSection: some View {
        Section("Photo") {
            HStack(spacing: 16) {
                Group {
                    if let thumbnailJPEG, let image = UIImage(data: thumbnailJPEG) {
                        Image(uiImage: image).resizable().scaledToFit().background(.white)
                    } else {
                        Image(systemName: "fork.knife")
                            .font(.title)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.fill.tertiary)
                    }
                }
                .frame(width: 80, height: 80)
                .clipShape(.rect(cornerRadius: 14))
                .accessibilityLabel(thumbnailJPEG == nil ? "No photo" : "Product photo")
                VStack(alignment: .leading, spacing: 8) {
                    PhotosPicker("Replace", selection: $photoItem, matching: .images)
                    if thumbnailJPEG != nil {
                        Button("Remove", role: .destructive) { thumbnailJPEG = nil }
                    }
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private var sourceSection: some View {
        Section("Found with AI") {
            if let url = draft.sourceURL {
                Link(url.host() ?? url.absoluteString, destination: url)
            }
            LabeledContent("Confidence", value: draft.confidence.rawValue.capitalized)
            ForEach(draft.notes, id: \.self) { note in
                Text(note).font(.subheadline)
            }
        }
    }

    // MARK: - Saving

    private func save() {
        guard canSave else { return }
        let key = FoodMatching.key(brand: trimmed(brand), line: trimmed(line), name: trimmed(name))
        if let existing = foods.first(where: { FoodMatching.key(brand: $0.brand, line: $0.line, name: $0.name) == key }) {
            duplicate = existing
        } else {
            store(into: nil)
        }
    }

    /// Writes the reviewed details into `existing`, or into a new saved food.
    private func store(into existing: Food?) {
        guard let kilocaloriesPerGram else { return }
        let food = existing ?? Food(name: trimmed(name), kilocaloriesPerGram: kilocaloriesPerGram)
        food.name = trimmed(name)
        food.brand = trimmed(brand).isEmpty ? nil : trimmed(brand)
        food.line = trimmed(line).isEmpty ? nil : trimmed(line)
        food.kilocaloriesPerGram = kilocaloriesPerGram
        food.kindRawValue = kind.rawValue
        food.sizes = completeSizes
        food.calorieStatement = trimmed(calorieStatement).isEmpty ? nil : trimmed(calorieStatement)
        food.ingredients = trimmed(ingredients).isEmpty ? nil : trimmed(ingredients)
        food.guaranteedAnalysis = GuaranteedAnalysisRow.rows(
            proteinMin: NumberInput.percent.value(proteinText), fatMin: NumberInput.percent.value(fatText),
            fiberMax: NumberInput.percent.value(fiberText), moistureMax: NumberInput.percent.value(moistureText),
            other: otherAnalysis.split(whereSeparator: \.isNewline).map { trimmed(String($0)) }.filter { !$0.isEmpty }
        )
        food.notes = ["Found with AI lookup (confidence: \(draft.confidence.rawValue), form: \(draft.form.rawValue))."] + draft.notes
        food.sourceURL = draft.sourceURL
        food.origin = .aiLookup
        if food.seedID != nil { food.isUserModified = true }
        if let thumbnailJPEG {
            food.thumbnailKey = try? FoodThumbnailStore.save(thumbnailJPEG)
        } else if existing != nil {
            food.thumbnailKey = nil
        }
        if existing == nil { modelContext.insert(food) }
        if Persistence.save(modelContext) { onSaved() }
    }
}
