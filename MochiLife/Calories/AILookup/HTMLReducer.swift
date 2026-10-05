import Foundation

/// The useful parts of a product page, small enough to send to the AI.
struct ReducedPage: Sendable {
    struct Product: Sendable {
        var name: String?
        var brand: String?
        var image: String?
        var description: String?
    }

    var url: URL
    var title: String?
    var ogTitle: String?
    var ogImage: String?
    var twitterImage: String?
    var products: [Product]
    var text: String

    /// Image candidates in the order to try: og:image, twitter:image, then JSON-LD images,
    /// resolved against the page address.
    var imageCandidates: [URL] {
        ([ogImage, twitterImage] + products.map(\.image))
            .compactMap { $0 }
            .compactMap { URL(string: $0.trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: url)?.absoluteURL }
    }
}

/// Reduces HTML to plain text and a few metadata fields without third-party parsers.
enum HTMLReducer {
    static let maximumTextLength = 24_000
    static let headLength = 6_000
    static let windowLength = 3_000
    static let keywords = ["kcal", "calorie", "metabolizable", "ingredients", "guaranteed analysis", "crude protein"]

    static func reduce(_ page: FetchedPage) -> ReducedPage {
        let html = page.html
        let metas = metaTags(in: html)
        return ReducedPage(
            url: page.url,
            title: firstMatch(of: /(?is)<title[^>]*>(.*?)<\/title>/, in: html).map(plainText(fromFragment:)),
            ogTitle: metas["og:title"],
            ogImage: metas["og:image"] ?? metas["og:image:url"] ?? metas["og:image:secure_url"],
            twitterImage: metas["twitter:image"] ?? metas["twitter:image:src"],
            products: jsonLDProducts(in: html),
            text: trimmed(visibleText(of: html))
        )
    }

    /// Plain text of a small HTML fragment (search snippets, titles).
    static func plainText(fromFragment fragment: String) -> String {
        collapse(decodeEntities(fragment.replacing(/<[^>]*>/, with: " ")))
    }

    // MARK: - Metadata

    /// property/name → content for every <meta> tag, in either attribute order.
    private static func metaTags(in html: String) -> [String: String] {
        var result: [String: String] = [:]
        for match in html.matches(of: /(?i)<meta\b[^>]*>/) {
            let tag = String(match.output)
            var attributes: [String: String] = [:]
            for attribute in tag.matches(of: /(?i)([a-z:_-]+)\s*=\s*("([^"]*)"|'([^']*)')/) {
                let value = attribute.output.3 ?? attribute.output.4 ?? ""
                attributes[attribute.output.1.lowercased()] = decodeEntities(String(value))
            }
            if let key = (attributes["property"] ?? attributes["name"])?.lowercased(),
               let content = attributes["content"], !content.isEmpty, result[key] == nil {
                result[key] = content
            }
        }
        return result
    }

    private static func jsonLDProducts(in html: String) -> [ReducedPage.Product] {
        var products: [ReducedPage.Product] = []
        for match in html.matches(of: /(?is)<script[^>]*type\s*=\s*["']application\/ld\+json["'][^>]*>(.*?)<\/script>/) {
            guard let data = String(match.output.1).data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            else { continue }
            collectProducts(from: json, into: &products)
        }
        return products
    }

    private static func collectProducts(from json: Any, into products: inout [ReducedPage.Product]) {
        if let array = json as? [Any] {
            array.forEach { collectProducts(from: $0, into: &products) }
            return
        }
        guard let object = json as? [String: Any] else { return }
        if let graph = object["@graph"] { collectProducts(from: graph, into: &products) }
        let types = (object["@type"] as? [String]) ?? [(object["@type"] as? String) ?? ""]
        guard types.contains(where: { $0.caseInsensitiveCompare("Product") == .orderedSame }) else { return }
        products.append(ReducedPage.Product(
            name: object["name"] as? String,
            brand: (object["brand"] as? String) ?? ((object["brand"] as? [String: Any])?["name"] as? String),
            image: firstImage(object["image"]),
            description: (object["description"] as? String).map(plainText(fromFragment:))
        ))
    }

    private static func firstImage(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let array = value as? [Any] { return array.lazy.compactMap(firstImage).first }
        if let object = value as? [String: Any] { return (object["url"] as? String) ?? (object["contentUrl"] as? String) }
        return nil
    }

    // MARK: - Text

    private static func visibleText(of html: String) -> String {
        var text = html
        text.replace(/(?s)<!--.*?-->/, with: " ")
        for element in ["script", "style", "noscript", "svg", "nav", "footer", "head", "template", "iframe"] {
            text.replace(try! Regex("(?is)<\(element)\\b.*?</\(element)\\s*>"), with: " ")
        }
        text.replace(/(?i)<(br|\/p|\/div|\/li|\/tr|\/h[1-6]|\/section|\/table)\b[^>]*>/, with: "\n")
        text.replace(/<[^>]*>/, with: " ")
        return collapse(decodeEntities(text))
    }

    /// Keeps everything if short; otherwise the head plus windows around nutrition keywords.
    private static func trimmed(_ text: String) -> String {
        guard text.count > maximumTextLength else { return text }
        let lowercased = text.lowercased()
        var ranges: [Range<Int>] = [0..<headLength]
        for keyword in keywords {
            var searchStart = lowercased.startIndex
            while let found = lowercased.range(of: keyword, range: searchStart..<lowercased.endIndex) {
                let center = lowercased.distance(from: lowercased.startIndex, to: found.lowerBound)
                let lower = max(0, center - windowLength / 2)
                ranges.append(lower..<min(text.count, lower + windowLength))
                searchStart = found.upperBound
            }
        }
        // Merge overlapping windows, in page order, until the length limit.
        var merged: [Range<Int>] = []
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = merged.last, range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        var pieces: [String] = []
        var total = 0
        let characters = Array(text)
        for range in merged where total < maximumTextLength {
            let clipped = range.lowerBound..<min(range.upperBound, range.lowerBound + maximumTextLength - total)
            pieces.append(String(characters[clipped]))
            total += clipped.count
        }
        return pieces.joined(separator: "\n…\n")
    }

    private static func collapse(_ text: String) -> String {
        text.replacing(/[ \t\u{00A0}\r\f\v]+/, with: " ")
            .replacing(/\ *\n[\ \n]*/, with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        let named: [String: String] = [
            "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "ndash": "–",
            "mdash": "—", "rsquo": "’", "lsquo": "‘", "rdquo": "”", "ldquo": "“", "hellip": "…",
            "deg": "°", "reg": "®", "trade": "™", "copy": "©", "eacute": "é", "egrave": "è",
            "agrave": "à", "ccedil": "ç", "uuml": "ü", "ouml": "ö", "auml": "ä", "frac12": "½", "frac14": "¼",
        ]
        return text.replacing(/&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);/) { match in
            let entity = String(match.output.1)
            if entity.hasPrefix("#x"), let code = UInt32(entity.dropFirst(2), radix: 16), let scalar = Unicode.Scalar(code) {
                return String(Character(scalar))
            }
            if entity.hasPrefix("#"), let code = UInt32(entity.dropFirst()), let scalar = Unicode.Scalar(code) {
                return String(Character(scalar))
            }
            return named[entity.lowercased()] ?? String(match.output.0)
        }
    }

    private static func firstMatch(of regex: Regex<(Substring, Substring)>, in text: String) -> String? {
        text.firstMatch(of: regex).map { String($0.output.1) }
    }
}
