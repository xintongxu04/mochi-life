import Foundation

/// One labeled block of embedded product data, flattened to "path: value" lines.
struct EmbeddedSection: Sendable, Equatable {
    var label: String
    var text: String
}

/// Package weights and multipack phrases found in the page by the app. Sent to the AI as
/// pointers only; the AI must still quote evidence from the page itself.
struct SizeHints: Sendable, Equatable {
    /// Like "3 oz can", "85 g", "5.5 oz".
    var unitSizes: [String] = []
    /// Like "case of 24", "12-pack": counts, never unit sizes.
    var multipacks: [String] = []

    static let maximumUnitSizes = 25
    static let maximumMultipacks = 10

    static func find(in text: String) -> SizeHints {
        var hints = SizeHints()
        let lowered = text.lowercased()
        let weight = #"(\d+(?:\.\d+)?)\s?-?\s?(oz|ounces?|lbs?|pounds?|kg|g|grams?)\b\.?(?:\s?(cans?|pouch(?:es)?|trays?|cups?|bags?|sachets?|cartons?|tubs?|boxes|box))?"#
        for groups in RX.matches(of: weight, in: lowered) {
            guard let number = groups[0].flatMap(Double.init), let unit = groups[1],
                  let factor = CalorieVerifier.gramsFactor(for: unit)
            else { continue }
            let grams = number * factor
            guard (10...25_000).contains(grams) else { continue }
            let hint = [groups[0], unit, groups[2]].compactMap { $0 }.joined(separator: " ")
            if !hints.unitSizes.contains(hint) { hints.unitSizes.append(hint) }
            if hints.unitSizes.count >= maximumUnitSizes { break }
        }
        let multipack = #"(case of \d+|pack of \d+|\d+\s?-?\s?(?:pack|pk|count|ct)\b|\d+\s?x\s?\d+(?:\.\d+)?\s?(?:oz|g|lbs?|kg)\b)"#
        for groups in RX.matches(of: multipack, in: lowered) {
            guard let phrase = groups[0] else { continue }
            if !hints.multipacks.contains(phrase) { hints.multipacks.append(phrase) }
            if hints.multipacks.count >= maximumMultipacks { break }
        }
        return hints
    }

    var description: String? {
        var lines: [String] = []
        if !unitSizes.isEmpty { lines.append("Unit weights seen: " + unitSizes.joined(separator: "; ")) }
        if !multipacks.isEmpty { lines.append("Multipack phrases seen (counts, not unit sizes): " + multipacks.joined(separator: "; ")) }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}

/// Finds product data embedded in a page's HTML: every JSON-LD block, framework state blobs
/// (`__NEXT_DATA__`, `__NUXT__`, `__INITIAL_STATE__`…), Shopify product JSON, and product
/// data-* attributes. Each section is capped at 30,000 characters, keeping first the values
/// inside objects that mention the product name.
enum EmbeddedData {
    static let sectionLimit = 30_000
    static let leafValueLimit = 1_500
    /// Keys that only add bulk (images, reviews, links).
    static let skippedKeys: Set<String> = [
        "image", "images", "logo", "review", "reviews", "potentialaction", "breadcrumb", "thumbnail",
        "thumbnailurl", "featured_image", "media", "srcset", "src", "icon", "video", "videos",
    ]
    /// Keys or values worth keeping from large state blobs.
    static let relevant = #"kcal|calori|energy|metaboli|weight|size|ounce|\boz\b|gram|\blbs?\b|\bkg\b|ingredient|analysis|protein|\bfat\b|fiber|fibre|moisture|nutrition|feeding|variant|title|name|description|pack|count"#

    static func sections(in html: String, productName: String) -> [EmbeddedSection] {
        let nameWords = SourceIdentity.words(productName)
        var sections: [EmbeddedSection] = []

        // JSON-LD: every block (Product, Offer, hasVariant, additionalProperty, weight, nutrition…).
        var jsonLD: [Any] = []
        for groups in RX.matches(of: #"(?is)<script[^>]*type\s*=\s*["']application/ld\+json["'][^>]*>(.*?)</script>"#, in: html) {
            if let json = groups[0].flatMap(parseJSON) { jsonLD.append(json) }
        }
        if !jsonLD.isEmpty {
            add("JSON-LD structured data", jsonLD, filtered: false, nameWords: nameWords, to: &sections)
        }

        // JSON script blocks: Next.js data, Shopify product JSON, other state.
        var nextData: [Any] = []
        var shopify: [Any] = []
        var state: [Any] = []
        for match in RX.matches(of: #"(?is)<script([^>]*type\s*=\s*["']application/json["'][^>]*)>(.*?)</script>"#, in: html) {
            guard let attributes = match[0]?.lowercased(), let json = match[1].flatMap(parseJSON) else { continue }
            if attributes.contains("__next_data__") {
                nextData.append(json)
            } else if attributes.contains("product") || match[1]?.contains("\"variants\"") == true {
                shopify.append(json)
            } else {
                state.append(json)
            }
        }
        // Assignments in inline scripts: window.__X__ = {...}, ShopifyAnalytics.meta = {...}, var meta = {...}.
        for match in RX.matches(of: #"(?:window\.)?(__[A-Za-z_]+__|ShopifyAnalytics\.meta|\bmeta|__remixContext)\s*=\s*\{"#, in: html, includeRanges: true) {
            guard let name = match.groups[0], let object = balancedObject(in: html, from: match.end - 1),
                  let json = parseJSON(object)
            else { continue }
            if name.lowercased().contains("meta") { shopify.append(json) } else { state.append(json) }
        }
        if !nextData.isEmpty { add("Next.js page data", nextData, filtered: true, nameWords: nameWords, to: &sections) }
        if !shopify.isEmpty { add("Shopify product data", shopify, filtered: false, nameWords: nameWords, to: &sections) }
        if !state.isEmpty { add("Page state data", state, filtered: true, nameWords: nameWords, to: &sections) }

        // data-* attributes about the product.
        var attributeLines: [String] = []
        for groups in RX.matches(of: #"(?i)\s(data-[a-z0-9_-]*(?:product|variant|nutrition|weight|size|kcal|calor|ingredient|analysis)[a-z0-9_-]*)\s*=\s*("[^"]{2,}"|'[^']{2,}')"#, in: html) {
            guard let name = groups[0], var value = groups[1] else { continue }
            value = HTMLReducer.decodeEntities(String(value.dropFirst().dropLast()))
            if let json = parseJSON(value) {
                var leaves: [Leaf] = []
                flatten(json, path: name.lowercased(), nameWords: nameWords, insideNamed: false, into: &leaves)
                attributeLines += leaves.map(\.line)
            } else {
                attributeLines.append("\(name.lowercased()): \(String(value.prefix(leafValueLimit)))")
            }
        }
        if !attributeLines.isEmpty {
            sections.append(EmbeddedSection(label: "Product data attributes", text: capped(unique(attributeLines))))
        }
        return sections
    }

    // MARK: - Flattening

    struct Leaf {
        var path: String
        var value: String
        /// Inside an object that mentions the product name.
        var preferred: Bool
        var line: String { "\(path): \(value)" }
    }

    private static func add(_ label: String, _ blocks: [Any], filtered: Bool, nameWords: Set<String>, to sections: inout [EmbeddedSection]) {
        var leaves: [Leaf] = []
        for block in blocks {
            flatten(block, path: "", nameWords: nameWords, insideNamed: false, into: &leaves)
        }
        if filtered {
            leaves = leaves.filter { RX.contains(relevant, in: $0.path.lowercased()) || RX.contains(relevant, in: $0.value.lowercased()) }
        }
        let ordered = leaves.filter(\.preferred) + leaves.filter { !$0.preferred }
        let text = capped(unique(ordered.map(\.line)))
        if !text.isEmpty { sections.append(EmbeddedSection(label: label, text: text)) }
    }

    static func flatten(_ json: Any, path: String, nameWords: Set<String>, insideNamed: Bool, into leaves: inout [Leaf]) {
        if let object = json as? [String: Any] {
            let mentions = insideNamed || mentionsName(object, nameWords: nameWords)
            for key in object.keys.sorted() where !skippedKeys.contains(key.lowercased()) && !key.hasPrefix("@context") {
                flatten(object[key]!, path: join(path, key), nameWords: nameWords, insideNamed: mentions, into: &leaves)
            }
        } else if let array = json as? [Any] {
            for (index, element) in array.prefix(200).enumerated() {
                flatten(element, path: "\(path)[\(index)]", nameWords: nameWords, insideNamed: insideNamed, into: &leaves)
            }
        } else if let string = json as? String {
            var value = string.contains("<") ? HTMLReducer.plainText(fromFragment: string) : string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, !value.hasPrefix("http"), !value.hasPrefix("/") || value.contains(" ") else { return }
            if value.count > leafValueLimit { value = String(value.prefix(leafValueLimit)) + "…" }
            leaves.append(Leaf(path: shortened(path), value: value, preferred: insideNamed))
        } else if let number = json as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            leaves.append(Leaf(path: shortened(path), value: number.stringValue, preferred: insideNamed))
        }
    }

    private static func mentionsName(_ object: [String: Any], nameWords: Set<String>) -> Bool {
        guard !nameWords.isEmpty else { return false }
        for value in object.values {
            guard let string = value as? String, string.count < 400 else { continue }
            let shared = SourceIdentity.words(string).intersection(nameWords).count
            if Double(shared) >= max(1, Double(nameWords.count) * 0.5) { return true }
        }
        return false
    }

    private static func join(_ path: String, _ key: String) -> String { path.isEmpty ? key : "\(path).\(key)" }

    /// The last four path components, to keep deep state paths readable.
    private static func shortened(_ path: String) -> String {
        let parts = path.split(separator: ".")
        return parts.count > 4 ? "…." + parts.suffix(4).joined(separator: ".") : path
    }

    private static func unique(_ lines: [String]) -> [String] {
        var seen = Set<String>()
        return lines.filter { seen.insert($0).inserted }
    }

    private static func capped(_ lines: [String]) -> String {
        var result: [String] = []
        var total = 0
        for line in lines {
            guard total + line.count + 1 <= sectionLimit else { break }
            result.append(line)
            total += line.count + 1
        }
        return result.joined(separator: "\n")
    }

    static func parseJSON(_ text: String) -> Any? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, first == "{" || first == "[" else { return nil }
        return trimmed.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0, options: [.fragmentsAllowed]) }
    }

    /// The `{...}` starting at a UTF-16 offset, matching braces outside strings. Nil if unbalanced
    /// or over 3 MB.
    static func balancedObject(in text: String, from offset: Int) -> String? {
        let units = Array(text.utf16)
        guard offset < units.count, units[offset] == UInt16(UInt8(ascii: "{")) else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var quote: UInt16 = 0
        var index = offset
        while index < units.count, index - offset < 3_000_000 {
            let unit = units[index]
            if inString {
                if escaped { escaped = false }
                else if unit == UInt16(UInt8(ascii: "\\")) { escaped = true }
                else if unit == quote { inString = false }
            } else if unit == UInt16(UInt8(ascii: "\"")) || unit == UInt16(UInt8(ascii: "'")) {
                inString = true
                quote = unit
            } else if unit == UInt16(UInt8(ascii: "{")) {
                depth += 1
            } else if unit == UInt16(UInt8(ascii: "}")) {
                depth -= 1
                if depth == 0 { return String(utf16CodeUnits: Array(units[offset...index]), count: index - offset + 1) }
            }
            index += 1
        }
        return nil
    }
}

/// Small NSRegularExpression helpers: much faster than Swift Regex on megabyte-sized HTML.
enum RX {
    struct Match {
        var groups: [String?]
        /// UTF-16 offset just past the match.
        var end: Int
    }

    private nonisolated(unsafe) static var cache: [String: NSRegularExpression] = [:]
    private static let lock = NSLock()

    static func regex(_ pattern: String, caseInsensitive: Bool = false) -> NSRegularExpression? {
        let key = (caseInsensitive ? "i:" : "s:") + pattern
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[key] { return cached }
        let compiled = try? NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
        cache[key] = compiled
        return compiled
    }

    static func matches(of pattern: String, in text: String) -> [[String?]] {
        matches(of: pattern, in: text, includeRanges: true).map(\.groups)
    }

    static func matches(of pattern: String, in text: String, includeRanges: Bool) -> [Match] {
        guard let regex = regex(pattern) else { return [] }
        let string = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: string.length)).map { match in
            Match(groups: (1..<max(1, match.numberOfRanges)).map { index in
                let range = match.range(at: index)
                return range.location == NSNotFound ? nil : string.substring(with: range)
            }, end: NSMaxRange(match.range))
        }
    }

    static func replace(_ pattern: String, in text: String, with template: String) -> String {
        guard let regex = regex(pattern) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: template)
    }

    static func contains(_ pattern: String, in text: String) -> Bool {
        guard let regex = regex(pattern) else { return false }
        return regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }

    /// UTF-16 offsets where the pattern matches.
    static func locations(of pattern: String, in text: String, caseInsensitive: Bool) -> [Int] {
        guard let regex = regex(pattern, caseInsensitive: caseInsensitive) else { return [] }
        return regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)).map(\.range.location)
    }
}
