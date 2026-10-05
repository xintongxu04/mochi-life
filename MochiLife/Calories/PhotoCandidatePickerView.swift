import SwiftUI

/// "Find online": up to 8 product photos from the food's source page and Brave image search,
/// loaded lazily (each one's download is cancelled if it scrolls away or the sheet closes).
/// Needs the Brave Search key.
struct PhotoCandidatePickerView: View {
    let searchQuery: String
    let sourceURL: URL?
    let onPick: (Data) -> Void

    private enum Phase {
        case loading
        case ready([ImageCandidate])
        case empty(String)
        case needsKey
    }

    @Environment(\.dismiss) private var dismiss
    @State private var phase = Phase.loading
    @State private var photos: [ImageCandidate: Data] = [:]
    @State private var failed: Set<ImageCandidate> = []
    @State private var isShowingSettings = false
    private let fetcher = URLSessionWebFetcher()

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .loading:
                    ProgressView("Finding photos…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case let .ready(candidates):
                    grid(candidates)
                case let .empty(message):
                    ContentUnavailableView("No Photos Found", systemImage: "photo", description: Text(message))
                case .needsKey:
                    ContentUnavailableView {
                        Label("Brave Search Key Needed", systemImage: "key")
                    } description: {
                        Text("Finding photos online uses your Brave Search API key.")
                    } actions: {
                        Button("Open AI Lookup Settings") { isShowingSettings = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Find a Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .navigationDestination(isPresented: $isShowingSettings) {
                AILookupSettingsView()
            }
            .task { await load() }
            .onChange(of: isShowingSettings) {
                if !isShowingSettings, case .needsKey = phase {
                    phase = .loading
                    Task { await load() }
                }
            }
        }
    }

    private func grid(_ candidates: [ImageCandidate]) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
                ForEach(Array(candidates.enumerated()), id: \.element) { index, candidate in
                    cell(candidate, number: index + 1, of: candidates.count)
                }
            }
            .padding()
            Text("Tap a photo to use it. Photos load from the product's website or Brave image search.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
    }

    private func cell(_ candidate: ImageCandidate, number: Int, of total: Int) -> some View {
        let label = "Photo option \(number) of \(total), from \(candidate.referer?.host() ?? candidate.url.host() ?? "the web")"
        return Button {
            if let data = photos[candidate] {
                onPick(data)
                dismiss()
            }
        } label: {
            Group {
                if let data = photos[candidate], let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFit().background(.white)
                } else if failed.contains(candidate) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
            .frame(width: 100, height: 100)
            .frame(maxWidth: .infinity)
            .background(.fill.tertiary, in: .rect(cornerRadius: 12))
            .clipShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(photos[candidate] == nil)
        .accessibilityLabel(failed.contains(candidate) ? "\(label), couldn't load" : label)
        .accessibilityHint(photos[candidate] == nil ? "" : "Uses this photo")
        .task(id: candidate) {
            guard photos[candidate] == nil, !failed.contains(candidate) else { return }
            do {
                photos[candidate] = try await fetcher.fetchThumbnail(candidate)
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled { failed.insert(candidate) }
            }
        }
    }

    private func load() async {
        guard let braveKey = AIKeychain.key(for: .brave) else {
            phase = .needsKey
            return
        }
        let finder = ProductPhotoFinder(fetcher: fetcher, imageSearch: BraveImageSearchClient(apiKey: braveKey))
        do {
            let candidates = try await finder.pickerCandidates(sourceURL: sourceURL, searchQuery: searchQuery)
            if candidates.isEmpty {
                phase = .empty(ImageSearchAvailability.isKnownUnavailable
                    ? "No photos were found on the product page, and your Brave plan doesn't include image search."
                    : AILookupLimit.remainingToday == 0
                        ? "Today's limit of AI lookups is used up, so image search was skipped."
                        : "Try adding a photo from your library or taking one.")
            } else {
                phase = .ready(candidates)
            }
        } catch is CancellationError {
        } catch let failure as LookupFailure {
            phase = .empty(failure.message)
        } catch {
            phase = .empty("Photos couldn't be found right now.")
        }
    }
}
