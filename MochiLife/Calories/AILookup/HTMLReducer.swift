import Foundation

/// The useful parts of a product page, small enough to send to the AI.
struct ReducedPage: Sendable {
    struct Product: Sendable {
        var name: String?
        var brand: String?
        /// Every image the JSON-LD gives (string, array, or ImageObject url).
        var images: [String]
        var description: String?
    }

    /// Sizes for diagnostics only (never content).
    struct Diagnostics: Sendable {
        var htmlBytes = 0
        var textLength = 0
        var reducedLength = 0
        /// Section label → characters kept.
        var sections: [(String, Int)] = []
        var sizeHints = 0
        var rendered = false
    }

    var url: URL
    var title: String?
    var ogTitle: String?
    var products: [Product]
    var text: String
    /// Embedded product data (JSON-LD, page state, Shopify product JSON, data-* attributes),
    /// flattened to "path: value" lines and labeled.
    var sections: [EmbeddedSection] = []
    /// Package weights and multipack phrases found by the app (pointers, not evidence).
    var sizeHints = SizeHints()
    /// Product photo candidates in priority order (see `ImageCandidateFinder`).
    var imageCandidates: [ImageCandidate]
    var diagnostics = Diagnostics()

    /// Everything sent to the AI that evidence may be quoted from (text plus data sections).
    var evidenceText: String {
        ([text] + sections.map(\.text)).joined(separator: "\n")
    }
}

/// Reduces HTML to plain text and a few metadata fields without third-party parsers.
enum HTMLReducer {
    /// Characters of page text kept; longer pages keep the head plus windows around keywords.
    static let maximumTextLength = 120_000
    static let headLength = 12_000
    static let windowLength = 6_000
    /// Keyword groups in priority order: windows for earlier groups are kept first.
    static let keywordGroups: [[String]] = [
        [#"kcal"#, #"calori"#, #"metaboli[sz]able"#, #"\bME\b"#],
        [#"net weight"#, #"net wt"#],
        [#"ingredients"#, #"guaranteed analysis"#],
        [#"\boz\b"#, #"\bounces?\b"#, #"\bgrams?\b"#, #"\bsizes?\b"#],
    ]

    static func reduce(_ page: FetchedPage, productName: String? = nil, renderedText: String? = nil) -> ReducedPage {
        let html = page.html
        let metas = metaTags(in: html)
        let products = jsonLDProducts(in: html)
        let title = firstMatch(of: /(?is)<title[^>]*>(.*?)<\/title>/, in: html).map(plainText(fromFragment:))
        let name = [productName, products.first?.name, metas["og:title"], title].compactMap { $0 }.first ?? ""
        let fullText = renderedText.map(collapse) ?? visibleText(of: html)
        let text = trimmed(fullText)
        let sections = EmbeddedData.sections(in: html, productName: name)
        let hints = SizeHints.find(in: ([fullText] + sections.map(\.text)).joined(separator: "\n"))
        var diagnostics = ReducedPage.Diagnostics()
        diagnostics.htmlBytes = html.utf8.count
        diagnostics.textLength = fullText.count
        diagnostics.reducedLength = text.count
        diagnostics.sections = sections.map { ($0.label, $0.text.count) }
        diagnostics.sizeHints = hints.unitSizes.count + hints.multipacks.count
        diagnostics.rendered = renderedText != nil
        return ReducedPage(
            url: page.url,
            title: title,
            ogTitle: metas["og:title"],
            products: products,
            text: text,
            sections: sections,
            sizeHints: hints,
            imageCandidates: ImageCandidateFinder.candidates(in: html, pageURL: page.url, metas: metas,
                                                             productImages: products.flatMap(\.images)),
            diagnostics: diagnostics
        )
    }

    /// Plain text of a small HTML fragment (search snippets, titles).
    static func plainText(fromFragment fragment: String) -> String {
        collapse(decodeEntities(fragment.replacing(/<[^>]*>/, with: " ")))
    }

    // MARK: - Metadata

    /// Attributes of one HTML tag, lowercased names, entities decoded.
    static func attributes(of tag: String) -> [String: String] {
        var attributes: [String: String] = [:]
        for attribute in tag.matches(of: /(?i)([a-z:_-]+)\s*=\s*("([^"]*)"|'([^']*)'|([^\s"'>]+))/) {
            let value = attribute.output.3 ?? attribute.output.4 ?? attribute.output.5 ?? ""
            let name = attribute.output.1.lowercased()
            if attributes[name] == nil { attributes[name] = decodeEntities(String(value)) }
        }
        return attributes
    }

    /// property/name → content for every <meta> tag, in either attribute order.
    private static func metaTags(in html: String) -> [String: String] {
        var result: [String: String] = [:]
        for match in html.matches(of: /(?i)<meta\b[^>]*>/) {
            let attributes = attributes(of: String(match.output))
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
            images: allImages(object["image"]),
            description: (object["description"] as? String).map(plainText(fromFragment:))
        ))
    }

    private static func allImages(_ value: Any?) -> [String] {
        if let string = value as? String { return [string] }
        if let array = value as? [Any] { return array.flatMap(allImages) }
        if let object = value as? [String: Any] {
            return [(object["url"] as? String) ?? (object["contentUrl"] as? String)].compactMap { $0 }
        }
        return []
    }

    // MARK: - Text

    /// Page text with tags removed. Hidden tab, accordion and details content is kept (only
    /// tags are stripped); `<template>` and script templates are unwrapped; table cells are
    /// separated by " | " and rows by line breaks.
    static func visibleText(of html: String) -> String {
        var text = html
        text = RX.replace(#"(?s)<!--.*?-->"#, in: text, with: " ")
        // Script templates hold tab/accordion markup on some sites: keep their contents.
        text = RX.replace(#"(?is)<script\b[^>]*type\s*=\s*["']text/(?:template|x-template|html)["'][^>]*>(.*?)</script\s*>"#, in: text, with: " $1 ")
        for element in ["script", "style", "noscript", "svg", "nav", "head", "iframe"] {
            text = RX.replace("(?is)<\(element)\\b.*?</\(element)\\s*>", in: text, with: " ")
        }
        text = RX.replace(#"(?i)</t[dh]\s*>"#, in: text, with: " | ")
        text = RX.replace(#"(?i)<(br|/p|/div|/li|/tr|/h[1-6]|/section|/table|/dt|/dd|/summary|/details|/caption|/article)\b[^>]*>"#, in: text, with: "\n")
        text = RX.replace(#"<[^>]*>"#, in: text, with: " ")
        return collapse(decodeEntities(text))
    }

    /// Keeps everything up to the budget; otherwise the head plus windows around keywords, the
    /// calorie keywords first, then net weight, ingredients and analysis, then size words.
    static func trimmed(_ text: String) -> String {
        let string = text as NSString
        guard string.length > maximumTextLength else { return text }
        var covered = IndexSet(integersIn: 0..<min(headLength, string.length))
        groups: for group in keywordGroups {
            for pattern in group {
                for location in RX.locations(of: pattern, in: text, caseInsensitive: pattern != #"\bME\b"#) {
                    if covered.count >= maximumTextLength { break groups }
                    let lower = max(0, location - windowLength / 2)
                    covered.insert(integersIn: lower..<min(string.length, lower + windowLength))
                }
            }
        }
        var pieces: [String] = []
        var total = 0
        for range in covered.rangeView where total < maximumTextLength {
            let length = min(range.count, maximumTextLength - total)
            pieces.append(string.substring(with: NSRange(location: range.lowerBound, length: length)))
            total += length
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
