import PhotosUI
import SwiftData
import SwiftUI

/// Runs one AI lookup and holds its state for the screens.
@MainActor
@Observable
final class AILookupSession {
    enum Phase: Equatable {
        case input
        case running(LookupStage)
        case review(FoodDraft)
        case notFound
        case failed(LookupFailure)
    }

    var phase = Phase.input
    private var task: Task<Void, Never>?

    /// Starts a lookup. Returns the missing service if a key isn't set (so the caller can open
    /// AI Lookup settings) instead of starting.
    func start(query: String) -> AIService? {
        guard let braveKey = AIKeychain.key(for: .brave) else { return .brave }
        guard let deepSeekKey = AIKeychain.key(for: .deepSeek) else { return .deepSeek }
        guard AILookupLimit.reserve() else {
            phase = .failed(.dailyLimitReached(AILookupLimit.dailyCap))
            return nil
        }
        let searchText = query.split(whereSeparator: \.isNewline).joined(separator: " ")
        let service = FoodLookupService(
            search: BraveSearchClient(apiKey: braveKey),
            chat: DeepSeekClient(apiKey: deepSeekKey),
            fetcher: URLSessionWebFetcher(),
            imageSearch: BraveImageSearchClient(apiKey: braveKey),
            renderer: WebKitPageRenderer()
        )
        phase = .running(.searching)
        task = Task {
            do {
                let draft = try await service.lookUp(searchText) { stage in
                    await MainActor.run { self.phase = .running(stage) }
                }
                phase = .review(draft)
            } catch is CancellationError {
                phase = .input
            } catch let failure as LookupFailure {
                phase = failure == .notFound ? .notFound : .failed(failure)
            } catch {
                phase = Task.isCancelled ? .input : .failed(.unreadableAnswer)
            }
        }
        return nil
    }

    func cancel() {
        task?.cancel()
        task = nil
        phase = .input
    }
}

/// "Add with AI": type a name or photograph the package, look it up, then review and save.
struct AddWithAIView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var session = AILookupSession()
    @State private var query = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var isTakingPhoto = false
    @State private var isReadingPhoto = false
    @State private var photoMessage: String?
    @State private var isShowingSettings = false
    @State private var isAddingManually = false
    @FocusState private var isQueryFocused: Bool

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Group {
                switch session.phase {
                case .input:
                    inputForm
                case let .running(stage):
                    progressView(stage)
                case let .review(draft):
                    FoodEditorView(mode: .review(draft)) { saved in
                        if saved { dismiss() } else { session.phase = .input }
                    }
                case .notFound:
                    notFoundView
                case let .failed(failure):
                    failureView(failure)
                }
            }
            .navigationTitle("Add with AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        session.cancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("AI Lookup Settings", systemImage: "key") { isShowingSettings = true }
                }
            }
            .navigationDestination(isPresented: $isShowingSettings) {
                AILookupSettingsView()
            }
            .sheet(isPresented: $isAddingManually) {
                NavigationStack {
                    FoodEditorView(mode: .create(name: trimmedQuery)) { saved in
                        isAddingManually = false
                        if saved { dismiss() }
                    }
                }
            }
            .fullScreenCover(isPresented: $isTakingPhoto) {
                CameraPicker { image in
                    if let data = image.jpegData(compressionQuality: 0.9) {
                        Task { await readPhoto(data) }
                    }
                }
                .ignoresSafeArea()
            }
            .onChange(of: photoItem) {
                guard let photoItem else { return }
                Task {
                    if let data = try? await photoItem.loadTransferable(type: Data.self) {
                        await readPhoto(data)
                    }
                    self.photoItem = nil
                }
            }
        }
    }

    private var inputForm: some View {
        Form {
            Section {
                TextField("Product name, like Tiki Cat Grill Tuna Pâté", text: $query, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($isQueryFocused)
                    .submitLabel(.search)
            } header: {
                Text("Food to look up")
            } footer: {
                Text("Include the brand and flavor. You can edit text read from a photo before searching.")
            }

            Section {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Choose a Photo of the Package", systemImage: "photo")
                }
                if CameraPicker.isAvailable {
                    Button("Take a Photo of the Package", systemImage: "camera") { isTakingPhoto = true }
                }
                if isReadingPhoto {
                    HStack {
                        ProgressView()
                        Text("Reading the package…")
                    }
                }
            } footer: {
                Text(photoMessage ?? "The photo is read on this iPhone and never uploaded.")
            }

            Section {
                Button {
                    isQueryFocused = false
                    if session.start(query: trimmedQuery) != nil {
                        isShowingSettings = true
                    }
                } label: {
                    Label("Look Up", systemImage: "sparkle.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .disabled(trimmedQuery.isEmpty || isReadingPhoto)
            } footer: {
                Text("\(AILookupLimit.remainingToday) of \(AILookupLimit.dailyCap) lookups left today.")
            }
        }
    }

    private func progressView(_ stage: LookupStage) -> some View {
        VStack(spacing: 20) {
            ProgressView()
                .controlSize(.large)
            Text(stage.title + "…")
                .font(.headline)
                .multilineTextAlignment(.center)
            Button("Cancel", role: .cancel) { session.cancel() }
                .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }

    private var notFoundView: some View {
        ContentUnavailableView {
            Label("Not Found", systemImage: "magnifyingglass")
        } description: {
            Text("No matching cat food page was found for “\(trimmedQuery)”.")
        } actions: {
            Button("Enter Manually") { isAddingManually = true }
                .buttonStyle(.borderedProminent)
            Button("Search Again") { session.phase = .input }
        }
    }

    private func failureView(_ failure: LookupFailure) -> some View {
        ContentUnavailableView {
            Label("Lookup Stopped", systemImage: "exclamationmark.triangle")
        } description: {
            Text(failure.message)
        } actions: {
            switch failure {
            case .missingKey, .keyRejected:
                Button("Open AI Lookup Settings") { isShowingSettings = true }
                    .buttonStyle(.borderedProminent)
            default:
                EmptyView()
            }
            Button("Back") { session.phase = .input }
            Button("Enter Manually") { isAddingManually = true }
        }
    }

    private func readPhoto(_ data: Data) async {
        isReadingPhoto = true
        defer { isReadingPhoto = false }
        do {
            let lines = try await PackageTextReader.lines(in: data)
            if lines.isEmpty {
                photoMessage = "No text was found in the photo. Type the name instead."
            } else {
                query = lines.joined(separator: "\n")
                photoMessage = "Edit the text to keep just the brand and product name, then tap Look Up."
            }
        } catch {
            photoMessage = "The photo couldn't be read. Type the name instead."
        }
    }
}
