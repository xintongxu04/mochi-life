import SwiftData
import SwiftUI

/// Screens inside the Log Food sheet.
enum LogRoute: Hashable {
    /// The size-and-portion picker for a food. `autoMatch` is set when the food was chosen
    /// automatically from a package, to offer "Not this one".
    case portion(Food, Portion?, autoMatch: AutoMatch?)
    /// Two or three possible foods to choose from.
    case candidates(CandidateChoice)
    case quickEntry(String)
    case browse
    /// Find a food on the web with the AI lookup, then log it.
    case web(String)
}

struct AutoMatch: Hashable {
    var alternatives: [Food]
    var text: String
}

struct CandidateChoice: Hashable {
    var foods: [Food]
    /// What was typed or read, for size preselection and web search.
    var text: String
}

/// State of the Log Food sheet: navigation, the library index, and the camera decision.
@MainActor
@Observable
final class LogFlowModel {
    var path: [LogRoute] = []
    var isMatchingPhoto = false
    var photoMessage: String?

    private(set) var foods: [Food] = []
    private var matcher = FoodMatcher(items: [])
    private var indexSignature = 0

    /// Rebuilds the matching index when saved foods change (built off the main actor).
    func updateIndex(with foods: [Food]) async {
        var hasher = Hasher()
        for food in foods {
            hasher.combine(food.persistentModelID)
            hasher.combine(food.name)
            hasher.combine(food.brand)
            hasher.combine(food.line)
            hasher.combine(food.sizes.count)
        }
        let signature = hasher.finalize()
        guard signature != indexSignature else { return }
        indexSignature = signature
        let items = foods.enumerated().map { index, food in
            FoodMatcher.Item(id: index, brand: food.brand, line: food.line, name: food.name,
                             sizes: food.sizes.map { .init(label: $0.name, grams: $0.grams) })
        }
        let built = await Task.detached(priority: .userInitiated) { FoodMatcher(items: items) }.value
        self.foods = foods
        self.matcher = built
    }

    /// Ranked foods for typed text: matcher results first, then plain substring matches
    /// (so partly typed words still find something). Off the main actor.
    func results(for query: String) async -> (foods: [Food], classification: FoodMatcher.Classification) {
        let matcher = matcher
        let result = await Task.detached(priority: .userInitiated) { matcher.match(query) }.value
        var ranked = result.candidates.compactMap { foods.indices.contains($0.id) ? foods[$0.id] : nil }
        let substring = foods.filter { FoodSearch.matches($0, query: query) }.sortedByName()
        for food in substring where !ranked.contains(food) { ranked.append(food) }
        return (Array(ranked.prefix(12)), result.classification)
    }

    /// A starting portion with the size mentioned in the text (e.g. "5.5 oz") preselected.
    static func portion(for food: Food, text: String) -> Portion? {
        guard let index = FoodMatcher.sizeIndex(in: text, sizes: food.sizes.map { .init(label: $0.name, grams: $0.grams) })
        else { return nil }
        return Portion(measure: .containers, size: food.sizes[index], containers: 1, exactContainers: .one)
    }

    private var matchingTask: Task<Void, Never>?

    /// Starts matching recognized text; cancelled by `cancelWork()` when the sheet closes.
    func startMatching(_ lines: [PackageTextReader.Line]) {
        matchingTask?.cancel()
        matchingTask = Task { await handleRecognized(lines) }
    }

    func cancelWork() {
        matchingTask?.cancel()
        matchingTask = nil
    }

    /// Text recognized on a package → confident (open the food), ambiguous (choose), or none
    /// (search the web). Matching runs off the main actor; the model is consulted when useful.
    func handleRecognized(_ lines: [PackageTextReader.Line]) async {
        guard !lines.isEmpty else { return }
        isMatchingPhoto = true
        defer { isMatchingPhoto = false }
        let tallest = lines.map(\.height).max() ?? 1
        let weighted = lines.map {
            FoodMatcher.WeightedText(text: $0.text, weight: 0.4 + 0.6 * ($0.height / max(tallest, 0.0001)))
        }
        let allText = lines.map(\.text).joined(separator: "\n")
        // The largest lines (brand, line, recipe) make the best web query.
        let queryText = lines.sorted { $0.height > $1.height }.prefix(4).map(\.text).joined(separator: " ")

        let matcher = matcher
        let result = await Task.detached(priority: .userInitiated) { matcher.match(weighted: weighted) }.value
        guard !Task.isCancelled else { return }
        LogFlowLog.logger.info("path=camera lines=\(lines.count) classification=\(result.classification.rawValue, privacy: .public) narrow=\(result.isNarrow)")
        let shortlist = result.candidates.compactMap { foods.indices.contains($0.id) ? foods[$0.id] : nil }

        var decision = result.classification
        var ordered = shortlist
        if (decision == .ambiguous || result.isNarrow) && shortlist.count >= 2 {
            if let reason = MatchJudge.unavailableReason {
                LogFlowLog.logger.info("model_judge used=false reason=\(reason, privacy: .public)")
            } else {
                let started = ContinuousClock.now
                let verdict = await MatchJudge.judge(
                    recognizedText: allText,
                    candidates: shortlist.map { MatchJudge.Candidate(brand: $0.brand, line: $0.line, name: $0.name) }
                )
                guard !Task.isCancelled else { return }
                let elapsed = ContinuousClock.now - started
                LogFlowLog.logger.info("model_judge used=\(verdict != nil) latency_ms=\(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000) certainty=\(verdict.map { "\($0.certainty)" } ?? "-", privacy: .public)")
                if let verdict {
                    if let selected = verdict.selectedIndex {
                        let order = [selected] + verdict.runnerUpIndices + shortlist.indices.filter { $0 != selected && !verdict.runnerUpIndices.contains($0) }
                        ordered = order.map { shortlist[$0] }
                        decision = verdict.certainty == .low ? .ambiguous : .confident
                    } else {
                        decision = .ambiguous
                    }
                }
            }
        }

        switch decision {
        case .confident:
            guard let food = ordered.first else { fallthrough }
            path.append(.portion(food, Self.portion(for: food, text: allText),
                                 autoMatch: AutoMatch(alternatives: Array(ordered.dropFirst().prefix(3)), text: queryText)))
        case .ambiguous:
            let close = matcher.closeCandidates(in: result).compactMap { foods.indices.contains($0.id) ? foods[$0.id] : nil }
            let choices = ordered == shortlist ? close : Array(ordered.prefix(3))
            path.append(.candidates(CandidateChoice(foods: choices.isEmpty ? Array(shortlist.prefix(3)) : choices, text: allText)))
        case .none:
            LogFlowLog.logger.info("web_fallback=true source=camera")
            path.append(.web(queryText))
        }
    }

    /// "Not this one": swap the automatic match for the list of other choices.
    func showAlternatives(_ match: AutoMatch, instead food: Food) {
        if !path.isEmpty { path.removeLast() }
        path.append(.candidates(CandidateChoice(foods: match.alternatives.filter { $0 != food }, text: match.text)))
    }
}

/// The Log Food sheet: one place to find what Mochi ate — recent and frequent foods, live
/// library search, the camera, quick entry, browsing, and web lookup as a fallback.
struct LogFoodFlowView: View {
    /// The day being viewed; new entries default to it.
    let day: Date

    @Environment(\.dismiss) private var dismiss
    @State private var model = LogFlowModel()
    @State private var manualAddName: String?

    var body: some View {
        NavigationStack(path: $model.path) {
            LogFoodHomeView(model: model)
                .navigationDestination(for: LogRoute.self) { route in
                    destination(route)
                }
                .savedFoodsDestinations(mode: .pick(onFinish: { dismiss() }))
        }
        .environment(\.isPickingFood, true)
        .environment(\.logDay, day)
        .onDisappear { model.cancelWork() }
        .sheet(item: Binding(get: { manualAddName.map(ManualAdd.init) }, set: { manualAddName = $0?.name })) { add in
            NavigationStack {
                FoodEditorView(mode: .create(name: add.name), onSavedFood: { food in
                    model.path.append(.portion(food, nil, autoMatch: nil))
                }) { _ in manualAddName = nil }
            }
        }
    }

    private struct ManualAdd: Identifiable {
        var name: String
        var id: String { name }
    }

    @ViewBuilder
    private func destination(_ route: LogRoute) -> some View {
        switch route {
        case let .portion(food, portion, autoMatch):
            LogEntryForm(
                mode: .logFood(food, startingFrom: portion),
                notThisOne: autoMatch.map { match in { model.showAlternatives(match, instead: food) } },
                onFinish: { dismiss() }
            )
        case let .candidates(choice):
            CandidateListView(choice: choice, model: model) { manualAddName = choice.text }
        case let .quickEntry(name):
            LogEntryForm(mode: .quickEntry, initialName: name, onFinish: { dismiss() })
        case .browse:
            SavedFoodsView(mode: .pick(onFinish: { dismiss() }))
        case let .web(query):
            LogWebLookupView(
                query: query,
                onFoodSaved: { food in model.path.append(.portion(food, LogFlowModel.portion(for: food, text: query), autoMatch: nil)) },
                onQuickEntry: { model.path.append(.quickEntry(query)) },
                onManualAdd: { manualAddName = query }
            )
        }
    }
}

/// Search field, camera, Recent and Frequent, live results, and the secondary actions.
private struct LogFoodHomeView: View {
    let model: LogFlowModel

    @Environment(\.dismiss) private var dismiss
    @Query private var foods: [Food]
    @Query(sort: \FoodLogEntry.loggedAt, order: .reverse) private var entries: [FoodLogEntry]
    @State private var query = ""
    @State private var results: [Food] = []
    @State private var classification = FoodMatcher.Classification.none
    @State private var isCapturing = false
    @State private var submitted = false
    @FocusState private var isSearchFocused: Bool

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search your foods", text: $query)
                        .focused($isSearchFocused)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                        .onSubmit(submit)
                    Button {
                        isCapturing = true
                    } label: {
                        Image(systemName: "camera.viewfinder").font(.title2)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Read a package with the camera")
                    .accessibilityHint("Finds the food from the text on its package")
                }
                if model.isMatchingPhoto {
                    HStack { ProgressView(); Text("Finding the food…") }
                }
            }

            if trimmedQuery.isEmpty {
                recentSections
            } else {
                resultSections
            }

            Section {
                NavigationLink(value: LogRoute.quickEntry(trimmedQuery)) {
                    Label("Quick Entry", systemImage: "bolt")
                }
                .accessibilityHint("Logs just a name and calories")
                NavigationLink(value: LogRoute.browse) {
                    Label("Browse Saved Foods", systemImage: "books.vertical")
                }
            }
        }
        .navigationTitle("Log Food")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .fullScreenCover(isPresented: $isCapturing) {
            PackageCaptureView { lines in
                model.startMatching(lines)
            }
        }
        .task(id: foodsSignature) { await model.updateIndex(with: foods) }
        .task(id: trimmedQuery) {
            submitted = false
            guard !trimmedQuery.isEmpty else { results = []; return }
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            let found = await model.results(for: trimmedQuery)
            guard !Task.isCancelled else { return }
            results = found.foods
            classification = found.classification
        }
        .onAppear { isSearchFocused = true }
    }

    /// Changes whenever a saved food is added, removed, renamed or resized.
    private var foodsSignature: Int {
        var hasher = Hasher()
        for food in foods {
            hasher.combine(food.name)
            hasher.combine(food.brand)
            hasher.combine(food.line)
            hasher.combine(food.sizes.count)
        }
        return hasher.finalize()
    }

    // MARK: Recent and frequent

    private struct Usage {
        var food: Food
        var portion: Portion?
        var description: String?
    }

    /// The saved food a log entry was made from: by product ID or photo key, else by
    /// brand + line + name (entries are snapshots and don't link to foods).
    private func food(for entry: FoodLogEntry, keyed: [String: Food], byID: [String: Food]) -> Food? {
        if let identifier = entry.foodLibraryIdentifier, let food = byID[identifier] { return food }
        return keyed[FoodMatching.key(brand: entry.foodBrand, line: entry.foodLine, name: entry.foodName)]
    }

    private var usage: (recent: [Usage], frequent: [Usage]) {
        let keyed = Dictionary(foods.map { (FoodMatching.key(brand: $0.brand, line: $0.line, name: $0.name), $0) }) { first, _ in first }
        var byID: [String: Food] = [:]
        for food in foods {
            for key in [food.seedID, food.libraryIdentifier, food.thumbnailKey].compactMap({ $0 }) where byID[key] == nil {
                byID[key] = food
            }
        }
        var recent: [Usage] = []
        var counts: [PersistentIdentifier: (count: Int, usage: Usage)] = [:]
        let monthAgo = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .distantPast
        for entry in entries where !entry.isQuickEntry && !entry.isCarriedForward {
            guard let food = food(for: entry, keyed: keyed, byID: byID) else { continue }
            let item = Usage(food: food, portion: entry.portion, description: entry.amountDescription)
            if recent.count < 8 && !recent.contains(where: { $0.food == food }) { recent.append(item) }
            if entry.loggedAt >= monthAgo {
                let existing = counts[food.persistentModelID]
                counts[food.persistentModelID] = ((existing?.count ?? 0) + 1, existing?.usage ?? item)
            }
        }
        let frequent = counts.values.sorted { $0.count > $1.count }.prefix(5).map(\.usage)
        return (recent, Array(frequent))
    }

    @ViewBuilder
    private var recentSections: some View {
        let usage = usage
        if !usage.recent.isEmpty {
            Section("Recent") {
                ForEach(usage.recent, id: \.food) { item in usageRow(item) }
            }
        }
        if !usage.frequent.isEmpty {
            Section("Frequent") {
                ForEach(usage.frequent, id: \.food) { item in usageRow(item) }
            }
        }
    }

    private func usageRow(_ item: Usage) -> some View {
        NavigationLink(value: LogRoute.portion(item.food, item.portion, autoMatch: nil)) {
            FoodChoiceRow(food: item.food, detail: item.description)
        }
        .simultaneousGesture(TapGesture().onEnded { LogFlowLog.logger.info("path=recent") })
    }

    // MARK: Results

    @ViewBuilder
    private var resultSections: some View {
        Section {
            if results.isEmpty {
                Text(submitted ? "Nothing saved matches." : "No saved food matches yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(results, id: \.self) { food in
                NavigationLink(value: LogRoute.portion(food, LogFlowModel.portion(for: food, text: trimmedQuery), autoMatch: nil)) {
                    FoodChoiceRow(food: food, detail: food.formattedKilocaloriesPerGram)
                }
            }
            NavigationLink(value: LogRoute.web(trimmedQuery)) {
                Label(results.isEmpty ? "Search the web" : "Not listed? Search the web", systemImage: "globe")
            }
            .accessibilityHint("Looks the food up online with AI")
        } header: {
            Text("Your foods")
        }
    }

    /// On submit, with nothing in the library to show, go straight to the web.
    private func submit() {
        submitted = true
        LogFlowLog.logger.info("path=text classification=\(classification.rawValue, privacy: .public) results=\(results.count)")
        guard !trimmedQuery.isEmpty, results.isEmpty, classification == .none else { return }
        LogFlowLog.logger.info("web_fallback=true source=text")
        model.path.append(.web(trimmedQuery))
    }
}

/// A food to pick: photo, name, brand · line, and a detail such as the last portion.
struct FoodChoiceRow: View {
    let food: Food
    var detail: String?

    var body: some View {
        HStack(spacing: 12) {
            FoodThumbnail(food: food, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(food.name)
                Text([food.brandTitle, food.line, detail].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Two or three possible foods; or search the web; or quick entry.
private struct CandidateListView: View {
    let choice: CandidateChoice
    let model: LogFlowModel
    let onManualAdd: () -> Void

    var body: some View {
        List {
            Section {
                ForEach(choice.foods, id: \.self) { food in
                    NavigationLink(value: LogRoute.portion(food, LogFlowModel.portion(for: food, text: choice.text), autoMatch: nil)) {
                        FoodChoiceRow(food: food)
                    }
                    .accessibilityHint("Logs this food")
                }
            } header: {
                Text("Which one is it?")
            } footer: {
                Text("These saved foods match the package.")
            }
            Section {
                NavigationLink(value: LogRoute.web(choice.text.split(whereSeparator: \.isNewline).prefix(4).joined(separator: " "))) {
                    Label("None of these — search the web", systemImage: "globe")
                }
                NavigationLink(value: LogRoute.quickEntry("")) {
                    Label("Quick Entry", systemImage: "bolt")
                }
                Button("Add a Food by Hand", systemImage: "square.and.pencil", action: onManualAdd)
            }
        }
        .navigationTitle("Choose the Food")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The web fallback: the existing AI lookup and review form, then on to the portion picker.
private struct LogWebLookupView: View {
    let query: String
    let onFoodSaved: (Food) -> Void
    let onQuickEntry: () -> Void
    let onManualAdd: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var session = AILookupSession()
    @State private var missingKey: AIService?
    @State private var hasStarted = false

    var body: some View {
        Group {
            if let missingKey {
                alternatives(title: "Web Search Unavailable", icon: "key",
                             message: "Searching the web needs your \(missingKey.rawValue) API key, set in AI Lookup settings. You can log this as a quick entry or add the food by hand instead.")
            } else {
                switch session.phase {
                case .input:
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                case let .running(stage):
                    VStack(spacing: 20) {
                        ProgressView().controlSize(.large)
                        Text(stage.rawValue + "…").font(.headline)
                        Button("Cancel", role: .cancel) {
                            session.cancel()
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case let .review(draft):
                    FoodEditorView(mode: .review(draft), onSavedFood: onFoodSaved) { _ in }
                case .notFound:
                    alternatives(title: "Not Found", icon: "magnifyingglass",
                                 message: "No matching cat food was found online for “\(query)”.")
                case let .failed(failure):
                    alternatives(title: "Web Search Stopped", icon: "exclamationmark.triangle", message: failure.message)
                }
            }
        }
        .navigationTitle("Search the Web")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !hasStarted else { return }
            hasStarted = true
            LogFlowLog.logger.info("web_fallback=started")
            missingKey = session.start(query: query)
        }
        .onDisappear {
            if case .running = session.phase { session.cancel() }
        }
    }

    private func alternatives(title: String, icon: String, message: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(message)
        } actions: {
            Button("Quick Entry", systemImage: "bolt", action: onQuickEntry)
                .buttonStyle(.borderedProminent)
            Button("Add the Food by Hand", systemImage: "square.and.pencil", action: onManualAdd)
        }
    }
}
