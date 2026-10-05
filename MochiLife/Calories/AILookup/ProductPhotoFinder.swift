import Foundation

/// Finds a product photo: candidates from the product page first, then (if none works) Brave
/// image search. Used automatically by AI lookup and to fill the photo picker.
struct ProductPhotoFinder: Sendable {
    let fetcher: any WebFetcher
    /// Nil when there's no Brave key.
    let imageSearch: (any ImageSearchClient)?
    static let maximumAttempts = 4

    /// The first candidate that downloads and decodes, as a thumbnail JPEG: up to four page
    /// candidates, then up to four image-search results. Nil if none works.
    func firstPhoto(pageCandidates: [ImageCandidate], searchQuery: String) async -> Data? {
        AILog.logger.info("thumbnail_candidates page=\(pageCandidates.count) sources=\(Set(pageCandidates.map(\.source.rawValue)).sorted().joined(separator: ","), privacy: .public)")
        if let photo = await firstWorking(Array(pageCandidates.prefix(Self.maximumAttempts))) {
            return photo
        }
        guard !Task.isCancelled,
              let searched = try? await searchCandidates(searchQuery, count: 8), !searched.isEmpty
        else { return nil }
        return await firstWorking(Array(searched.prefix(Self.maximumAttempts)))
    }

    /// Up to `limit` candidates for the picker: the source page's photos, then image search.
    func pickerCandidates(sourceURL: URL?, searchQuery: String, limit: Int = 8) async throws -> [ImageCandidate] {
        var candidates: [ImageCandidate] = []
        if let sourceURL, sourceURL.scheme?.lowercased() == "https",
           let page = try? await fetcher.fetchPage(sourceURL) {
            candidates = HTMLReducer.reduce(page).imageCandidates
            AILog.logger.info("picker_candidates page=\(candidates.count)")
        }
        try Task.checkCancellation()
        if candidates.count < limit, let searched = try await searchCandidates(searchQuery, count: limit) {
            candidates += searched.filter { !candidates.contains($0) }
        }
        return Array(candidates.prefix(limit))
    }

    /// Brave image search, counted toward the daily lookup cap. Nil when unavailable (no key,
    /// plan doesn't include it, or today's cap is used up).
    private func searchCandidates(_ query: String, count: Int) async throws -> [ImageCandidate]? {
        guard let imageSearch, !ImageSearchAvailability.isKnownUnavailable else {
            AILog.logger.info("image_search skipped available=false")
            return nil
        }
        guard AILookupLimit.reserve() else {
            AILog.logger.info("image_search skipped daily_cap_reached")
            return nil
        }
        do {
            return try await imageSearch.searchImages(query, count: count)
        } catch is ImageSearchUnavailable {
            ImageSearchAvailability.markUnavailable()
            AILog.logger.notice("image_search unavailable_for_plan")
            return nil
        }
    }

    private func firstWorking(_ candidates: [ImageCandidate]) async -> Data? {
        for candidate in candidates {
            if Task.isCancelled { return nil }
            if let photo = try? await fetcher.fetchThumbnail(candidate) { return photo }
        }
        return nil
    }
}
