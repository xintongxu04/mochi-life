import Foundation

/// A product photo address to try, with the page it came from (sent as Referer, since many
/// sites refuse images requested without it).
struct ImageCandidate: Sendable, Equatable, Hashable {
    enum Source: String, Sendable {
        case openGraph = "og"
        case twitter
        case jsonLD = "jsonld"
        case linkImageSource = "link"
        case pageImage = "img"
        case imageSearch = "image_search"
    }

    var url: URL
    var referer: URL?
    var source: Source
}

/// Finds product photo candidates in a page's HTML, in priority order: og:image and
/// og:image:secure_url; twitter:image and twitter:image:src; JSON-LD Product images;
/// <link rel="image_src">; then <img> elements in the main product area (src, data-src,
/// data-lazy-src, or the largest srcset entry). Relative and protocol-relative addresses are
/// resolved against the final page address, http is upgraded to https, and data: URIs, SVGs,
/// sprites and images stated to be under 200 px are skipped.
enum ImageCandidateFinder {
    static let minimumStatedSize = 200
    static let maximumPageImages = 12

    static func candidates(in html: String, pageURL: URL, metas: [String: String], productImages: [String]) -> [ImageCandidate] {
        var raw: [(String, ImageCandidate.Source)] = []
        for key in ["og:image", "og:image:secure_url", "og:image:url"] {
            if let value = metas[key] { raw.append((value, .openGraph)) }
        }
        for key in ["twitter:image", "twitter:image:src"] {
            if let value = metas[key] { raw.append((value, .twitter)) }
        }
        raw += productImages.map { ($0, .jsonLD) }
        for match in html.matches(of: /(?i)<link\b[^>]*>/) {
            let attributes = HTMLReducer.attributes(of: String(match.output))
            if attributes["rel"]?.lowercased().split(separator: " ").contains("image_src") == true,
               let href = attributes["href"] {
                raw.append((href, .linkImageSource))
            }
        }
        raw += productAreaImages(in: html).map { ($0, .pageImage) }

        var seen = Set<URL>()
        return raw.compactMap { value, source in
            guard let url = resolve(value, against: pageURL), seen.insert(url).inserted else { return nil }
            return ImageCandidate(url: url, referer: pageURL, source: source)
        }
    }

    /// <img> addresses inside the first element whose id or class mentions the product (or
    /// <main>), skipping images stated to be small.
    private static func productAreaImages(in html: String) -> [String] {
        let marker = html.firstMatch(of: /(?i)<(?:div|section|main|figure|article)\b[^>]*(?:id|class)\s*=\s*["'][^"']*(?:product|gallery|pdp)[^"']*["'][^>]*>/)
            ?? html.firstMatch(of: /(?i)<main\b[^>]*>/)
        guard let start = marker?.range.lowerBound else { return [] }
        let end = html.index(start, offsetBy: 200_000, limitedBy: html.endIndex) ?? html.endIndex
        var images: [String] = []
        for match in html[start..<end].matches(of: /(?i)<img\b[^>]*>/) {
            let attributes = HTMLReducer.attributes(of: String(match.output))
            if let width = attributes["width"].flatMap({ Int($0) }), width < minimumStatedSize { continue }
            if let height = attributes["height"].flatMap({ Int($0) }), height < minimumStatedSize { continue }
            let address = largestSrcset(attributes["srcset"] ?? attributes["data-srcset"])
                ?? attributes["data-src"] ?? attributes["data-lazy-src"] ?? attributes["src"]
            if let address { images.append(address) }
            if images.count == maximumPageImages { break }
        }
        return images
    }

    /// The entry with the largest width (w) or density (x) descriptor.
    static func largestSrcset(_ srcset: String?) -> String? {
        guard let srcset, !srcset.isEmpty else { return nil }
        let entries = srcset.split(separator: ",").compactMap { entry -> (String, Double)? in
            let parts = entry.split(whereSeparator: \.isWhitespace)
            guard let address = parts.first else { return nil }
            let descriptor = parts.dropFirst().first.map(String.init) ?? "1x"
            let number = Double(descriptor.dropLast()) ?? 1
            return (String(address), descriptor.hasSuffix("w") ? number : number * 1000)
        }
        return entries.max { $0.1 < $1.1 }?.0
    }

    /// Absolute https URL, or nil for data: URIs, SVGs and sprites.
    static func resolve(_ value: String, against pageURL: URL) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()
        guard !trimmed.isEmpty, !lowercased.hasPrefix("data:"), !lowercased.contains("sprite") else { return nil }
        guard var components = URL(string: trimmed, relativeTo: pageURL)
            .flatMap({ URLComponents(url: $0.absoluteURL, resolvingAgainstBaseURL: true) })
        else { return nil }
        if components.scheme?.lowercased() == "http" { components.scheme = "https" }
        guard components.scheme?.lowercased() == "https", let url = components.url,
              !url.path.lowercased().hasSuffix(".svg")
        else { return nil }
        return url
    }
}
