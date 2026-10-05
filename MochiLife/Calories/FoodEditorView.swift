import PhotosUI
import SwiftData
import SwiftUI

/// The one form for saved foods: creating one by hand, reviewing an AI lookup result, and
/// editing any saved food. Nothing is written until Save; Cancel discards everything,
/// including a newly picked photo (kept in memory until Save).
struct FoodEditorView: View {
    enum Mode {
        /// A new food typed by hand, optionally with the name filled in.
        case create(name: String?)
        /// An AI lookup result to check before saving.
        case review(FoodDraft)
        case edit(Food)
    }

    let mode: Mode
    /// Called with the saved food right after a successful save (before `onFinish`), e.g. to
    /// continue straight to logging it.
    var onSavedFood: ((Food) -> Void)?
    /// Called with true after saving, false after Cancel.
    let onFinish: (Bool) -> Void

    @Environment(\.modelContext) private var modelContext
    @Query private var foods: [Food]

    // Identity
    @State private var brand = ""
    @State private var line = ""
    @State private var name = ""
    @State private var kind = FoodKind.kibble
    // Calories
    @State private var sizes: [EditableSize] = []
    @State private var perGramText = ""
    @State private var basis = CalorieBasis.perGram
    @State private var calorieStatement = ""
    @State private var ingredients = ""
    // Guaranteed analysis
    @State private var proteinText = ""
    @State private var fatText = ""
    @State private var fiberText = ""
    @State private var moistureText = ""
    @State private var otherAnalysis = ""
    // Other
    @State private var notes = ""
    @State private var sourceText = ""
    // Photo
    @State private var photoChange = PhotoChange.unchanged
    @State private var photoItem: PhotosPickerItem?
    @State private var isTakingPhoto = false
    @State private var isFindingOnline = false
    @State private var isProcessingPhoto = false
    @State private var isConfirmingRemove = false
    @State private var isConfirmingReset = false
    // Review
    @State private var duplicate: Food?
    @FocusState private var isPerGramFocused: Bool

    enum CalorieBasis: String, CaseIterable, Identifiable {
        case perGram = "per gram"
        case per100Grams = "per 100 g"
        var id: Self { self }
    }

    enum PhotoChange: Equatable {
        case unchanged
        case replaced(Data)
        case removed
        case resetToOriginal
    }

    struct EditableSize: Identifiable, Equatable {
        var id = UUID()
        var label: String
        var gramsText: String
        var caloriesText: String
        var isCalculated: Bool
        /// From an AI lookup: each figure's status and source, until the owner edits the row.
        var detail: String?
    }

    static let kilocaloriesPerGramRange = 0.2...6.0

    init(mode: Mode, onSavedFood: ((Food) -> Void)? = nil, onFinish: @escaping (Bool) -> Void) {
        self.mode = mode
        self.onSavedFood = onSavedFood
        self.onFinish = onFinish
        func text(_ value: Double?, digits: Int = 2) -> String {
            value.map { $0.formatted(.number.precision(.fractionLength(0...digits)).grouping(.never)) } ?? ""
        }
        switch mode {
        case let .create(initialName):
            _name = State(initialValue: initialName ?? "")
        case let .review(draft):
            _brand = State(initialValue: draft.brand)
            _line = State(initialValue: draft.line)
            _name = State(initialValue: draft.name)
            _kind = State(initialValue: draft.kind)
            _sizes = State(initialValue: draft.sizes.map { size in
                var detail = "Weight: \(FactLabel.describe(size.grams))"
                if let kilocalories = size.kilocalories { detail += " · Calories: \(FactLabel.describe(kilocalories))" }
                return EditableSize(label: size.label, gramsText: text(size.grams.value, digits: 1),
                                    caloriesText: text(size.kilocalories?.value, digits: 1),
                                    isCalculated: size.kilocalories?.status == .calculated, detail: detail)
            })
            _perGramText = State(initialValue: text(draft.kilocaloriesPerGram?.value, digits: 3))
            _calorieStatement = State(initialValue: draft.calorieStatement)
            _ingredients = State(initialValue: draft.ingredients)
            _proteinText = State(initialValue: text(draft.proteinMinPercent))
            _fatText = State(initialValue: text(draft.fatMinPercent))
            _fiberText = State(initialValue: text(draft.fiberMaxPercent))
            _moistureText = State(initialValue: text(draft.moistureMaxPercent))
            _otherAnalysis = State(initialValue: draft.otherAnalysis.joined(separator: "\n"))
            let header = "Found with AI lookup (confidence: \(draft.confidence.rawValue), form: \(draft.form.rawValue))."
            _notes = State(initialValue: ([header] + draft.notes).joined(separator: "\n"))
            _sourceText = State(initialValue: draft.sourceURL?.absoluteString ?? "")
            if let photo = draft.thumbnailJPEG { _photoChange = State(initialValue: .replaced(photo)) }
        case let .edit(food):
            _brand = State(initialValue: food.brand ?? "")
            _line = State(initialValue: food.line ?? "")
            _name = State(initialValue: food.name)
            _kind = State(initialValue: food.kind)
            _sizes = State(initialValue: food.sizes.map {
                EditableSize(label: $0.name, gramsText: text($0.grams, digits: 1),
                             caloriesText: text($0.kilocalories, digits: 1), isCalculated: $0.isCalculated)
            })
            _perGramText = State(initialValue: text(food.kilocaloriesPerGram, digits: 3))
            _calorieStatement = State(initialValue: food.calorieStatement ?? "")
            _ingredients = State(initialValue: food.ingredients ?? "")
            let rows = food.guaranteedAnalysis
            func standard(_ nutrient: String) -> String {
                text(rows.first { $0.nutrient == nutrient }?.percentValue)
            }
            _proteinText = State(initialValue: standard("Crude protein"))
            _fatText = State(initialValue: standard("Crude fat"))
            _fiberText = State(initialValue: standard("Crude fiber"))
            _moistureText = State(initialValue: standard("Moisture"))
            _otherAnalysis = State(initialValue: rows.filter { !$0.isStandard || $0.percentValue == nil }
                .map(\.labelLine).joined(separator: "\n"))
            _notes = State(initialValue: food.notes.joined(separator: "\n"))
            _sourceText = State(initialValue: food.sourceURL?.absoluteString ?? "")
        }
    }

    private var editingFood: Food? {
        if case let .edit(food) = mode { food } else { nil }
    }

    private var isReview: Bool {
        if case .review = mode { true } else { false }
    }

    private var title: String {
        switch mode {
        case .create: "Add Food"
        case .review: "Review Food"
        case .edit: "Edit Food"
        }
    }

    // MARK: - Validation

    private func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func lines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).map { trimmed(String($0)) }.filter { !$0.isEmpty }
    }

    private var kilocaloriesPerGram: Double? {
        guard let value = NumberInput.foodCalories.value(perGramText) else { return nil }
        let perGram = basis == .perGram ? value : value / 100
        return Self.kilocaloriesPerGramRange.contains(perGram) ? perGram : nil
    }

    private var perGramProblem: String? {
        guard !trimmed(perGramText).isEmpty, kilocaloriesPerGram == nil else { return nil }
        guard NumberInput.foodCalories.value(perGramText) != nil else { return "Enter calories as a number, like 3.5." }
        return basis == .perGram
            ? "Calories per gram must be between 0.2 and 6.0."
            : "Calories per 100 g must be between 20 and 600."
    }

    /// Sizes with a label, grams and calories, in the order shown.
    private var completeSizes: [FoodSize] {
        sizes.compactMap { size in
            guard !trimmed(size.label).isEmpty,
                  let grams = NumberInput.grams.value(size.gramsText),
                  let kilocalories = NumberInput.kilocalories.value(size.caloriesText),
                  Self.kilocaloriesPerGramRange.contains(kilocalories / grams)
            else { return nil }
            return FoodSize(name: trimmed(size.label), grams: grams, kilocalories: kilocalories,
                            kilocaloriesPerGram: kilocalories / grams, isCalculated: size.isCalculated)
        }
    }

    private var sizeProblems: [String] {
        sizes.compactMap { size in
            let label = trimmed(size.label).isEmpty ? "A size" : trimmed(size.label)
            let hasGrams = !trimmed(size.gramsText).isEmpty
            let hasCalories = !trimmed(size.caloriesText).isEmpty
            let grams = NumberInput.grams.value(size.gramsText)
            let kilocalories = NumberInput.kilocalories.value(size.caloriesText)
            if hasGrams && grams == nil { return "\(label): grams must be a number." }
            if hasCalories && kilocalories == nil { return "\(label): calories must be a number." }
            if let grams, let kilocalories, !Self.kilocaloriesPerGramRange.contains(kilocalories / grams) {
                return "\(label): \(Portion.formatKilocalories(kilocalories)) kcal in \(grams.formatted()) g is outside 0.2–6.0 kcal per gram."
            }
            if (hasGrams || hasCalories) && trimmed(size.label).isEmpty { return "Each size needs a name, like 2.8 oz can." }
            return nil
        }
    }

    private var hasIncompleteSizes: Bool {
        sizes.contains { size in
            let parts = [size.label, size.gramsText, size.caloriesText].map { trimmed($0).isEmpty }
            return parts.contains(true) && parts.contains(false)
        }
    }

    private var percentProblem: String? {
        let fields = [proteinText, fatText, fiberText, moistureText]
        return fields.contains { !trimmed($0).isEmpty && NumberInput.percent.value($0) == nil }
            ? "Percentages must be numbers from 0 to 100." : nil
    }

    private var sourceURL: URL? {
        guard let url = URL(string: trimmed(sourceText)), ["http", "https"].contains(url.scheme?.lowercased()),
              url.host() != nil
        else { return nil }
        return url
    }

    private var sourceProblem: String? {
        !trimmed(sourceText).isEmpty && sourceURL == nil ? "Enter a web address starting with https://" : nil
    }

    private var nameProblem: String? { trimmed(name).isEmpty ? "Add the product name." : nil }

    private var basisProblem: String? {
        kilocaloriesPerGram == nil && completeSizes.isEmpty && perGramProblem == nil
            ? "Add calories per gram, or a size with its grams and calories." : nil
    }

    private var canSave: Bool {
        nameProblem == nil && perGramProblem == nil && sizeProblems.isEmpty && percentProblem == nil
            && sourceProblem == nil && basisProblem == nil && !isProcessingPhoto
    }

    // MARK: - Photo

    private var displayedPhoto: UIImage? {
        switch photoChange {
        case let .replaced(data): UIImage(data: data)
        case .removed: nil
        case .resetToOriginal: editingFood.flatMap(FoodThumbnails.bundledImage(for:))
        case .unchanged: editingFood.flatMap(FoodThumbnails.image(for:))
        }
    }

    private var canResetToOriginal: Bool {
        guard let food = editingFood, food.seedID != nil, FoodThumbnails.bundledImage(for: food) != nil else { return false }
        switch photoChange {
        case .resetToOriginal: return false
        case .unchanged: return food.thumbnailKey != nil
        default: return true
        }
    }

    private var photoSearchQuery: String {
        [brand, line, name, "cat food"].map(trimmed).filter { !$0.isEmpty }.joined(separator: " ")
    }

    // MARK: - Form

    var body: some View {
        Form {
            if case let .review(draft) = mode {
                // Calories and sizes first; empty best-effort sections are left out.
                findingsSection(draft)
                sizesSection
                identitySection
                photoSection
                if !draft.calorieStatement.isEmpty { calorieStatementSection }
                if !draft.ingredients.isEmpty { ingredientsSection }
                if draft.proteinMinPercent != nil || draft.fatMinPercent != nil || draft.fiberMaxPercent != nil
                    || draft.moistureMaxPercent != nil || !draft.otherAnalysis.isEmpty {
                    analysisSection
                }
                notesSection
            } else {
                photoSection
                identitySection
                sizesSection
                calorieStatementSection
                ingredientsSection
                analysisSection
                notesSection
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isReview {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onFinish(false) }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(!canSave)
            }
        }
        .confirmationDialog("\(duplicate?.name ?? "This food") is already saved",
                            isPresented: Binding(get: { duplicate != nil }, set: { if !$0 { duplicate = nil } }),
                            titleVisibility: .visible, presenting: duplicate) { existing in
            Button("Update Existing") { store(into: existing) }
            Button("Save as New") { store(into: nil) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Update the saved food with these details, or keep both.")
        }
        .confirmationDialog("Remove this photo?", isPresented: $isConfirmingRemove, titleVisibility: .visible) {
            Button("Remove Photo", role: .destructive) { photoChange = .removed }
        } message: {
            Text("The food will show a placeholder instead.")
        }
        .confirmationDialog("Go back to the original photo?", isPresented: $isConfirmingReset, titleVisibility: .visible) {
            Button("Reset to Original") { photoChange = .resetToOriginal }
        } message: {
            Text("Your photo for this food will be replaced by the built-in one.")
        }
        .sheet(isPresented: $isFindingOnline) {
            PhotoCandidatePickerView(searchQuery: photoSearchQuery, sourceURL: sourceURL) { photo in
                photoChange = .replaced(photo)
            }
        }
        .fullScreenCover(isPresented: $isTakingPhoto) {
            CameraPicker { image in
                if let data = image.jpegData(compressionQuality: 0.9) { process(data) }
            }
            .ignoresSafeArea()
        }
        .onChange(of: photoItem) {
            guard let photoItem else { return }
            Task {
                if let data = try? await photoItem.loadTransferable(type: Data.self) { process(data) }
                self.photoItem = nil
            }
        }
    }

    private var photoSection: some View {
        Section {
            VStack(spacing: 12) {
                Group {
                    if isProcessingPhoto {
                        ProgressView()
                    } else if let image = displayedPhoto {
                        Image(uiImage: image).resizable().scaledToFit().background(.white)
                    } else {
                        Image(systemName: "fork.knife")
                            .font(.system(size: 56))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.fill.tertiary)
                    }
                }
                .frame(width: 160, height: 160)
                .clipShape(.rect(cornerRadius: 160 * 0.18))
                .accessibilityLabel(displayedPhoto == nil ? "No photo" : "Food photo")

                if isReview, case .unchanged = photoChange {
                    Text("No product photo was found. You can find one online, choose one, or take one.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                ViewThatFits {
                    HStack(spacing: 10) { photoButtons }
                    VStack(spacing: 10) { photoButtons }
                }
                .buttonStyle(.bordered)
                .font(.subheadline)
            }
            .frame(maxWidth: .infinity)
        }
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private var photoButtons: some View {
        PhotosPicker(selection: $photoItem, matching: .images) {
            Label("Library", systemImage: "photo.on.rectangle")
        }
        .accessibilityLabel("Choose a photo from your library")
        if CameraPicker.isAvailable {
            Button("Camera", systemImage: "camera") { isTakingPhoto = true }
                .accessibilityLabel("Take a photo")
        }
        Button("Find Online", systemImage: "magnifyingglass") { isFindingOnline = true }
            .accessibilityLabel("Find a photo online")
        if displayedPhoto != nil {
            Button("Remove", systemImage: "trash", role: .destructive) { isConfirmingRemove = true }
                .accessibilityLabel("Remove the photo")
        }
        if canResetToOriginal {
            Button("Reset", systemImage: "arrow.uturn.backward") { isConfirmingReset = true }
                .accessibilityLabel("Reset to the original photo")
        }
    }

    private var calorieStatementSection: some View {
        Section("Calorie statement") {
            TextField("As written on the label", text: $calorieStatement, axis: .vertical)
        }
    }

    private var ingredientsSection: some View {
        Section("Ingredients") {
            TextField("Ingredients", text: $ingredients, axis: .vertical)
                .lineLimit(3...12)
        }
    }

    /// What the AI lookup found for calories and sizes, with each figure's status and source.
    @ViewBuilder
    private func findingsSection(_ draft: FoodDraft) -> some View {
        Section {
            if let perGram = draft.kilocaloriesPerGram {
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent("Calories", value: CalorieVerifier.describePerKilogram(perGram.value))
                    statusLine(perGram)
                }
                if draft.sizes.isEmpty {
                    Text("No reliable package size was found. You can save now and log by grams, or add a size below.")
                        .font(.subheadline)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Reliable calories couldn't be found for this food.", systemImage: "exclamationmark.triangle")
                        .font(.headline)
                    Text(draft.sizes.isEmpty
                         ? "No checked calorie figure or package size was found online. Enter them from the package, or cancel."
                         : "No checked calorie figure was found online. Enter the calories from the package, or cancel.")
                        .font(.subheadline)
                    HStack {
                        Button("Enter Calories") { isPerGramFocused = true }
                            .buttonStyle(.borderedProminent)
                        Button("Cancel", role: .cancel) { onFinish(false) }
                            .buttonStyle(.bordered)
                    }
                }
                .padding(.vertical, 4)
            }
            let sizeConflicts = draft.sizes.flatMap { [$0.grams.conflict, $0.kilocalories?.conflict] }
                .compactMap { $0 }.filter { $0 != draft.kilocaloriesPerGram?.conflict }
            ForEach(Array(Set(sizeConflicts)).sorted(), id: \.self) { conflict in
                Label(conflict, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            LabeledContent("Confidence", value: draft.confidence.rawValue.capitalized)
        } header: {
            Text("Found with AI")
        } footer: {
            Text("Verified: copied from the page and checked. Calculated: worked out by the app from verified figures. Conflicting: figures disagree; both are shown.")
        }
    }

    private func statusLine(_ fact: Fact) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(FactLabel.describe(fact).prefix(1).uppercased() + FactLabel.describe(fact).dropFirst())
                .font(.caption)
                .foregroundStyle(fact.status == .conflicting ? .orange : .secondary)
            if let conflict = fact.conflict {
                Text(conflict)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var identitySection: some View {
        Section {
            TextField("Name", text: $name)
                .textInputAutocapitalization(.words)
                .accessibilityLabel("Product name")
            TextField("Brand (optional)", text: $brand)
                .textInputAutocapitalization(.words)
                .accessibilityIdentifier("Brand")
            TextField("Line (optional)", text: $line)
                .textInputAutocapitalization(.words)
                .accessibilityIdentifier("Line")
            FoodKindSelector(kind: $kind)
        } header: {
            Text("Product")
        } footer: {
            if let nameProblem { Text(nameProblem).foregroundStyle(.red) }
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
                    if let detail = size.detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        TextField("Grams", text: $size.gramsText)
                            .onChange(of: size.gramsText) { size.detail = nil }
                            .keyboardType(.decimalPad)
                            .accessibilityLabel("Grams in \(size.label)")
                        Text("g").foregroundStyle(.secondary)
                        TextField("Calories", text: $size.caloriesText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .accessibilityLabel("Calories in one whole \(size.label)")
                            .accessibilityIdentifier("sizeCaloriesField")
                            .onChange(of: size.caloriesText) {
                                size.isCalculated = false
                                size.detail = nil
                            }
                        Text("kcal").foregroundStyle(.secondary)
                    }
                }
                .rowSeparatorAligned()
            }
            .onDelete { sizes.remove(atOffsets: $0) }
            .onMove { sizes.move(fromOffsets: $0, toOffset: $1) }
            Button("Add Size", systemImage: "plus") {
                sizes.append(EditableSize(label: "", gramsText: "", caloriesText: "", isCalculated: false))
            }
            Picker("Calories", selection: $basis) {
                ForEach(CalorieBasis.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            HStack {
                Text(basis == .perGram ? "Per gram" : "Per 100 g")
                TextField("Calories", text: $perGramText)
                    .keyboardType(.decimalPad)
                    .focused($isPerGramFocused)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel(basis == .perGram ? "Calories per gram" : "Calories per 100 grams")
                Text(basis == .perGram ? "kcal/g" : "kcal/100 g").foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text("Sizes and calories")
                Spacer()
                if sizes.count > 1 { EditButton().font(.caption) }
            }
        } footer: {
            let problems = sizeProblems + [perGramProblem, basisProblem].compactMap { $0 }
            if !problems.isEmpty {
                Text(problems.joined(separator: "\n")).foregroundStyle(.red)
            } else if hasIncompleteSizes {
                Text("Sizes without a name, grams and calories aren't saved.")
            } else {
                Text("Calories are for one whole can or pouch.")
            }
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
        } footer: {
            if let percentProblem { Text(percentProblem).foregroundStyle(.red) }
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

    private var notesSection: some View {
        Section {
            TextField("Notes, one per line", text: $notes, axis: .vertical)
                .lineLimit(1...8)
            TextField("Source web address", text: $sourceText)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if let sourceURL {
                Link(sourceURL.host() ?? sourceURL.absoluteString, destination: sourceURL)
            }
        } header: {
            Text("Notes and source")
        } footer: {
            if let sourceProblem { Text(sourceProblem).foregroundStyle(.red) }
        }
    }

    // MARK: - Saving

    /// Shrinks a picked or taken photo off the main actor; kept in memory until Save.
    private func process(_ data: Data) {
        isProcessingPhoto = true
        Task {
            let photo = await Task.detached(priority: .userInitiated) { FoodThumbnailStore.thumbnailJPEG(from: data) }.value
            if let photo { photoChange = .replaced(photo) }
            isProcessingPhoto = false
        }
    }

    private func save() {
        guard canSave else { return }
        switch mode {
        case .create:
            store(into: nil)
        case .review:
            let key = FoodMatching.key(brand: trimmed(brand), line: trimmed(line), name: trimmed(name))
            if let existing = foods.first(where: { FoodMatching.key(brand: $0.brand, line: $0.line, name: $0.name) == key }) {
                duplicate = existing
            } else {
                store(into: nil)
            }
        case let .edit(food):
            store(into: food)
        }
    }

    /// Writes the form into `existing`, or into a new saved food.
    private func store(into existing: Food?) {
        let perGram = kilocaloriesPerGram ?? completeSizes.first?.kilocaloriesPerGram
        guard let perGram else { return }
        let food = existing ?? Food(name: trimmed(name), kilocaloriesPerGram: perGram)
        food.name = trimmed(name)
        food.brand = trimmed(brand).isEmpty ? nil : trimmed(brand)
        food.line = trimmed(line).isEmpty ? nil : trimmed(line)
        food.kilocaloriesPerGram = perGram
        food.kind = kind
        food.sizes = completeSizes
        food.calorieStatement = trimmed(calorieStatement).isEmpty ? nil : trimmed(calorieStatement)
        food.ingredients = trimmed(ingredients).isEmpty ? nil : trimmed(ingredients)
        food.guaranteedAnalysis = GuaranteedAnalysisRow.rows(
            proteinMin: NumberInput.percent.value(proteinText), fatMin: NumberInput.percent.value(fatText),
            fiberMax: NumberInput.percent.value(fiberText), moistureMax: NumberInput.percent.value(moistureText),
            other: lines(otherAnalysis)
        )
        food.notes = lines(notes)
        food.sourceURL = sourceURL
        switch mode {
        case .create: if existing == nil { food.origin = .manual }
        case .review: food.origin = .aiLookup
        case .edit: break
        }
        // Seed updates must not overwrite the owner's changes.
        if food.seedID != nil || food.libraryIdentifier != nil { food.isUserModified = true }

        if existing == nil { modelContext.insert(food) }
        // Save first, so a new food has its stable identifier for the photo's file name.
        guard Persistence.save(modelContext) else { return }
        applyPhoto(to: food)
        if Persistence.save(modelContext) {
            onSavedFood?(food)
            onFinish(true)
        }
    }

    private func applyPhoto(to food: Food) {
        switch photoChange {
        case .unchanged:
            break
        case let .replaced(photo):
            do {
                try FoodThumbnailStore.setPhoto(photo, for: food)
            } catch {
                Persistence.logger.error("Couldn't save a food photo: \(error.localizedDescription, privacy: .public)")
            }
        case .removed:
            FoodThumbnailStore.removePhoto(for: food, showPlaceholder: true)
        case .resetToOriginal:
            FoodThumbnailStore.removePhoto(for: food, showPlaceholder: false)
        }
    }
}
