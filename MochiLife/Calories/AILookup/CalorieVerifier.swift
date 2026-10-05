import Foundation

/// Calorie figures and package sizes from one or more readings, after checking. Values that
/// failed a check are left out; `rejections` names why (reason codes only, for diagnostics).
struct StatedFacts: Sendable, Equatable {
    struct Size: Sendable, Equatable {
        var label: String
        var container: String?
        var grams: Fact
        var kilocalories: Fact?
    }

    /// Calories per gram as stated (converted from the page's unit), not calculated.
    var kilocaloriesPerGram: Fact?
    var sizes: [Size] = []
    var rejections: [String] = []
}

/// The final calorie picture: stated figures plus app calculations, with statuses.
struct VerifiedReading: Sendable, Equatable {
    var kilocaloriesPerGram: Fact?
    var sizes: [StatedFacts.Size]
    var rejections: [String]

    /// Calories can be logged: a kcal/g figure (stated or calculated from a verified size).
    var hasCalorieBasis: Bool { kilocaloriesPerGram != nil }
    /// At least one package size with a weight.
    var hasSizeWithWeight: Bool { !sizes.isEmpty }
    var isComplete: Bool { hasCalorieBasis && hasSizeWithWeight }
}

/// Checks the model's calorie and size figures against the text it was given. Pure code: no
/// network, no model, so every rule is unit-tested (`CalorieVerifierTests`).
///
/// Rules: (a) the quoted evidence must occur in the text that was sent (after normalizing case,
/// spaces, dashes, quotes and thousands separators) and must contain the number; (b) kJ figures,
/// per-cup figures used for a can, and feeding-guide amounts are rejected; (c) kcal/kg 300–6,000,
/// kcal/g 0.3–6.0, a wet container 10–1,000 g, a dry bag up to 20 kg, and calories per container
/// that fit the form; (d) kcal/kg × grams vs stated calories per container within 8%, otherwise
/// both are marked conflicting; (e) oz × 28.3495 and lb × 453.592 to grams, multipack totals
/// never used as a unit size, sizes deduplicated; (f) anything the app works out is "calculated".
enum CalorieVerifier {
    static let gramsPerOunce = 28.3495
    static let gramsPerPound = 453.592
    static let kilocaloriesPerKilogramRange = 300.0...6_000.0
    static let kilocaloriesPerGramRange = 0.3...6.0
    static let wetContainerGrams = 10.0...1_000.0
    static let dryContainerGrams = 10.0...20_000.0
    /// kcal per gram a whole container can plausibly have, by form.
    static let wetContainerKilocaloriesPerGram = 0.3...2.5
    static let dryContainerKilocaloriesPerGram = 2.0...6.0
    static let disagreementTolerance = 0.08
    static let confirmationTolerance = 0.03
    static let maximumEvidenceLength = 300

    static let containerWords = ["can", "pouch", "tray", "cup", "bag", "sachet", "carton", "tub", "box", "tube", "jar", "bottle"]

    // MARK: - Entry points

    /// Checks one reading and adds the app's calculations.
    static func verify(_ food: ExtractedFood, sentText: String, source: FactSource) -> VerifiedReading {
        derive(check(food, sentText: sentText, source: source))
    }

    /// Checks one reading without calculating anything.
    static func check(_ food: ExtractedFood, sentText: String, source: FactSource) -> StatedFacts {
        let corpus = normalize(sentText)
        let form = food.parsedForm
        var facts = StatedFacts()

        // Package sizes first, so calories per container can be matched to them.
        for size in food.sizes ?? [] {
            switch checkSize(size, corpus: corpus, form: form) {
            case let .success(grams):
                guard !facts.sizes.contains(where: { abs($0.grams.value - grams) / grams < 0.01 }) else { continue }
                let label = clean(size.label) ?? "\(grams.formatted()) g"
                facts.sizes.append(StatedFacts.Size(
                    label: label,
                    container: containerWord(in: size.container) ?? containerWord(in: size.label),
                    grams: Fact(value: grams, status: .verified, evidence: size.evidence, source: source)
                ))
            case let .failure(reason):
                facts.rejections.append("size:\(reason.rawValue)")
            }
        }

        for density in food.energyDensity ?? [] {
            switch checkDensity(density, corpus: corpus) {
            case let .success(perGram):
                let fact = Fact(value: perGram, status: .verified, evidence: density.evidence, source: source)
                if let existing = facts.kilocaloriesPerGram {
                    if differs(existing.value, perGram, by: disagreementTolerance) {
                        facts.kilocaloriesPerGram?.status = .conflicting
                        facts.kilocaloriesPerGram?.conflict = "The page gives two calorie figures: \(describePerKilogram(existing.value)) and \(describePerKilogram(perGram)). Kept the first."
                    }
                } else {
                    facts.kilocaloriesPerGram = fact
                }
            case let .failure(reason):
                facts.rejections.append("density:\(reason.rawValue)")
            }
        }

        for calories in food.containerCalories ?? [] {
            switch checkContainerCalories(calories, corpus: corpus, form: form, sizes: facts.sizes) {
            case let .success((index, kilocalories)):
                if facts.sizes[index].kilocalories == nil {
                    facts.sizes[index].kilocalories = Fact(value: kilocalories, status: .verified, evidence: calories.evidence, source: source)
                }
            case let .failure(reason):
                facts.rejections.append("container_kcal:\(reason.rawValue)")
            }
        }
        return facts
    }

    /// Adds the app's calculations and the consistency check (rule d): kcal/g from a size when
    /// no figure per weight was stated, calories per container from kcal/g, and conflicts when a
    /// stated container figure and kcal/g × grams disagree by more than 8%.
    static func derive(_ stated: StatedFacts) -> VerifiedReading {
        var perGram = stated.kilocaloriesPerGram
        var sizes = stated.sizes

        if perGram == nil,
           let size = sizes.first(where: { $0.kilocalories != nil && $0.kilocalories?.status != .calculated }),
           let kilocalories = size.kilocalories {
            let value = kilocalories.value / size.grams.value
            if kilocaloriesPerGramRange.contains(value) {
                perGram = Fact(value: value, status: .calculated, source: kilocalories.source)
            }
        }

        if let basis = perGram {
            for index in sizes.indices {
                let calculated = basis.value * sizes[index].grams.value
                if let stated = sizes[index].kilocalories {
                    guard basis.status != .calculated, stated.status != .calculated,
                          differs(stated.value, calculated, by: disagreementTolerance)
                    else { continue }
                    let note = "\(sizes[index].label): \(format(stated.value)) kcal stated\(hostSuffix(stated.source)), but \(describePerKilogram(basis.value))\(hostSuffix(basis.source)) works out to \(format(calculated)) kcal."
                    sizes[index].kilocalories?.status = .conflicting
                    sizes[index].kilocalories?.conflict = note
                    let existingConflict = perGram?.conflict
                    perGram?.status = .conflicting
                    perGram?.conflict = existingConflict ?? note
                } else {
                    sizes[index].kilocalories = Fact(value: (calculated * 10).rounded() / 10, status: .calculated, source: basis.source)
                }
            }
        }
        return VerifiedReading(kilocaloriesPerGram: perGram, sizes: sizes, rejections: stated.rejections)
    }

    // MARK: - Checks

    enum Rejection: String, Error {
        case missingValue = "missing_value"
        case noEvidence = "no_evidence"
        case evidenceTooLong = "evidence_too_long"
        case notInSource = "not_in_source"
        case valueNotInEvidence = "value_not_in_evidence"
        case kilojoules = "kj"
        case perCup = "per_cup"
        case feedingGuide = "feeding_guide"
        case unknownUnit = "unknown_unit"
        case outOfRange = "out_of_range"
        case multipackTotal = "multipack_total"
        case unmatchedSize = "unmatched_size"
        case formMismatch = "form_mismatch"
    }

    /// Rule (a): the evidence is in the source and contains the value. Returns the normalized evidence.
    static func checkEvidence(_ evidence: String?, value: Double, corpus: String) -> Result<String, Rejection> {
        guard let evidence, !evidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .failure(.noEvidence) }
        guard evidence.count <= maximumEvidenceLength else { return .failure(.evidenceTooLong) }
        let normalized = normalize(evidence)
        guard corpus.contains(normalized) else { return .failure(.notInSource) }
        guard numberRanges(of: value, in: normalized).isEmpty == false else { return .failure(.valueNotInEvidence) }
        return .success(normalized)
    }

    static func checkDensity(_ density: ExtractedFood.EnergyDensity, corpus: String) -> Result<Double, Rejection> {
        guard let value = density.value, value > 0 else { return .failure(.missingValue) }
        let evidence: String
        switch checkEvidence(density.evidence, value: value, corpus: corpus) {
        case let .success(text): evidence = text
        case let .failure(reason): return .failure(reason)
        }
        let unit = compact(density.unit ?? "")
        let following = unitText(after: value, in: evidence)
        if unit.contains("kj") || following.hasPrefix("kj") { return .failure(.kilojoules) }
        if isFeedingGuide(evidence) { return .failure(.feedingGuide) }
        if unit.contains("cup") || following.range(of: #"^(kcal|calories?)?\s*(me)?\s*(/|per)\s*cup"#, options: .regularExpression) != nil {
            return .failure(.perCup)
        }
        let perGram: Double
        if unit.contains("/kg") || unit.contains("perkg") || unit.contains("kilogram") {
            guard kilocaloriesPerKilogramRange.contains(value) else { return .failure(.outOfRange) }
            perGram = value / 1000
        } else if unit.contains("/100g") || unit.contains("per100g") {
            perGram = value / 100
        } else if unit.contains("/g") || unit.contains("pergram") || unit.hasSuffix("/gram") {
            perGram = value
        } else if unit.contains("/lb") || unit.contains("perlb") || unit.contains("pound") {
            perGram = value / gramsPerPound
        } else if unit.contains("/oz") || unit.contains("peroz") || unit.contains("ounce") {
            perGram = value / gramsPerOunce
        } else {
            return .failure(.unknownUnit)
        }
        guard kilocaloriesPerGramRange.contains(perGram) else { return .failure(.outOfRange) }
        return .success(perGram)
    }

    static func checkSize(_ size: ExtractedFood.Size, corpus: String, form: ExtractedFood.Form?) -> Result<Double, Rejection> {
        guard let weight = size.weight, weight > 0 else { return .failure(.missingValue) }
        let evidence: String
        switch checkEvidence(size.evidence, value: weight, corpus: corpus) {
        case let .success(text): evidence = text
        case let .failure(reason): return .failure(reason)
        }
        guard let factor = gramsFactor(for: size.unit) else { return .failure(.unknownUnit) }
        if isFeedingGuide(evidence) { return .failure(.feedingGuide) }
        let grams = (weight * factor * 10).rounded() / 10
        if isMultipackTotal(grams: grams, evidence: evidence) { return .failure(.multipackTotal) }
        let container = containerWord(in: size.container) ?? containerWord(in: size.label)
        if form == .dry && container == "cup" { return .failure(.perCup) }
        let range = form == .wet ? wetContainerGrams : dryContainerGrams
        guard range.contains(grams) else { return .failure(.outOfRange) }
        return .success(grams)
    }

    /// Returns the index of the matching size and the calories.
    static func checkContainerCalories(_ calories: ExtractedFood.ContainerCalories, corpus: String,
                                       form: ExtractedFood.Form?, sizes: [StatedFacts.Size]) -> Result<(Int, Double), Rejection> {
        guard let value = calories.value, value > 0 else { return .failure(.missingValue) }
        let evidence: String
        switch checkEvidence(calories.evidence, value: value, corpus: corpus) {
        case let .success(text): evidence = text
        case let .failure(reason): return .failure(reason)
        }
        let unit = compact(calories.unit ?? "")
        let following = unitText(after: value, in: evidence)
        if unit.contains("kj") || following.hasPrefix("kj") { return .failure(.kilojoules) }
        if isFeedingGuide(evidence) { return .failure(.feedingGuide) }
        let per = containerWord(in: calories.per) ?? containerWord(in: following)
        let perCup = compact(calories.per ?? "").contains("cup") || compact(calories.per ?? "").contains("scoop")
            || following.range(of: #"^(kcal|calories?)?\s*(me)?\s*(/|per|a)\s*(cup|scoop)"#, options: .regularExpression) != nil
        guard let index = matchingSize(for: calories, per: per, evidence: evidence, sizes: sizes) else {
            return .failure(perCup ? .perCup : .unmatchedSize)
        }
        // A per-cup figure only counts for food actually sold in cups (wet cups), never as per can.
        if perCup && (form == .dry || sizes[index].container != "cup") { return .failure(.perCup) }
        let perGram = value / sizes[index].grams.value
        let range: ClosedRange<Double> = switch form {
        case .wet: wetContainerKilocaloriesPerGram
        case .dry: dryContainerKilocaloriesPerGram
        default: kilocaloriesPerGramRange
        }
        guard range.contains(perGram) else { return .failure(.formMismatch) }
        return .success((index, value))
    }

    // MARK: - Helpers

    /// Lowercased, accents folded, dashes, quotes and odd spaces unified, thousands separators
    /// removed between digits, all whitespace collapsed to one space.
    static func normalize(_ text: String) -> String {
        var result = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let replacements: [(String, String)] = [
            ("\u{2010}", "-"), ("\u{2011}", "-"), ("\u{2012}", "-"), ("\u{2013}", "-"), ("\u{2014}", "-"), ("\u{2212}", "-"),
            ("\u{2018}", "'"), ("\u{2019}", "'"), ("\u{201C}", "\""), ("\u{201D}", "\""), ("\u{00D7}", "x"),
            ("\u{00A0}", " "), ("\u{2009}", " "), ("\u{202F}", " "), ("\u{200B}", ""), ("\u{00AD}", ""),
        ]
        for (from, to) in replacements { result = result.replacingOccurrences(of: from, with: to) }
        result = result.replacingOccurrences(of: #"(?<=\d),(?=\d{3}(?!\d))"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Ranges of numbers in `text` equal to `value` (text already normalized).
    static func numberRanges(of value: Double, in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var searchStart = text.startIndex
        while let range = text.range(of: #"(?<![\d.])\d+(\.\d+)?(?![\d])"#, options: .regularExpression, range: searchStart..<text.endIndex) {
            if let number = Double(text[range]), abs(number - value) <= max(0.0005, abs(value) * 0.000_1) {
                ranges.append(range)
            }
            searchStart = range.upperBound
        }
        return ranges
    }

    /// The text right after the first occurrence of `value` in the evidence (spaces trimmed).
    static func unitText(after value: Double, in evidence: String) -> String {
        guard let range = numberRanges(of: value, in: evidence).first else { return "" }
        return String(evidence[range.upperBound...].prefix(24)).trimmingCharacters(in: .whitespaces)
    }

    static func isFeedingGuide(_ evidence: String) -> Bool {
        evidence.range(of: #"\bfeed(ing)?\b|per day|\bdaily\b|a day\b|body ?weight|\bweighing\b|lbs? of (cat|body)"#,
                       options: .regularExpression) != nil
    }

    /// A weight equal to N × a smaller weight in the same evidence, where N is a pack count
    /// ("case of 12", "12-pack", "12 x 3 oz"), is a multipack total, never a unit size.
    static func isMultipackTotal(grams: Double, evidence: String) -> Bool {
        let counts = matches(of: #"case of (\d+)|pack of (\d+)|(\d+) ?-? ?(?:pack|pk|count|ct)\b|(\d+) ?x ?\d"#, in: evidence)
            .compactMap { groups in groups.compactMap { $0 }.first.flatMap(Double.init) }
            .filter { $0 > 1 }
        guard !counts.isEmpty else { return false }
        let weights = matches(of: #"(\d+(?:\.\d+)?) ?-? ?(oz|ounces?|lbs?|pounds?|kg|g|grams?)\b"#, in: evidence)
            .compactMap { groups -> Double? in
                guard let number = groups[0].flatMap(Double.init), let factor = gramsFactor(for: groups[1]) else { return nil }
                return number * factor
            }
        return counts.contains { count in
            weights.contains { unit in unit < grams && abs(unit * count - grams) / grams < confirmationTolerance }
        }
    }

    static func gramsFactor(for unit: String?) -> Double? {
        let unit = compact(unit ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "."))
        switch unit {
        case "oz", "ounce", "ounces", "netwtoz": return gramsPerOunce
        case "g", "gram", "grams", "gr": return 1
        case "lb", "lbs", "pound", "pounds": return gramsPerPound
        case "kg", "kilogram", "kilograms", "kgs": return 1000
        default: return nil
        }
    }

    static func containerWord(in text: String?) -> String? {
        guard let text = text?.lowercased(), !text.isEmpty else { return nil }
        let words = Set(text.split { !$0.isLetter }.map { $0.hasSuffix("es") && $0.count > 4 ? String($0.dropLast(2)) : $0.hasSuffix("s") ? String($0.dropLast()) : String($0) })
        return containerWords.first { words.contains($0) }
    }

    private static func matchingSize(for calories: ExtractedFood.ContainerCalories, per: String?, evidence: String,
                                     sizes: [StatedFacts.Size]) -> Int? {
        guard !sizes.isEmpty else { return nil }
        if let label = clean(calories.sizeLabel).map(normalize) {
            if let index = sizes.firstIndex(where: { normalize($0.label) == label }) { return index }
            if let index = sizes.firstIndex(where: { label.contains(normalize($0.label)) || normalize($0.label).contains(label) }) {
                return index
            }
        }
        // The evidence names one size's weight ("80 kcal per 3 oz can").
        let named = sizes.indices.filter { index in
            guard let quoted = sizes[index].grams.evidence.map(normalize),
                  let weight = quoted.firstMatch(#"\d+(\.\d+)? ?-? ?(oz|ounces?|g|grams?|lbs?|kg)\b"#) else { return false }
            return evidence.contains(weight)
        }
        if named.count == 1 { return named[0] }
        if let per {
            let sameContainer = sizes.indices.filter { sizes[$0].container == per }
            if sameContainer.count == 1 { return sameContainer[0] }
            if sizes.count == 1 && (sizes[0].container == nil || per == "cup") { return 0 }
        }
        return nil
    }

    static func differs(_ a: Double, _ b: Double, by tolerance: Double) -> Bool {
        abs(a - b) / max(abs(b), .ulpOfOne) > tolerance
    }

    static func format(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...1))) }

    static func describePerKilogram(_ perGram: Double) -> String {
        "\((perGram * 1000).formatted(.number.precision(.fractionLength(0)))) kcal/kg"
    }

    private static func hostSuffix(_ source: FactSource?) -> String {
        source.map { " (\($0.host))" } ?? ""
    }

    private static func compact(_ text: String) -> String {
        text.lowercased().filter { !$0.isWhitespace }
    }

    private static func clean(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    private static func matches(of pattern: String, in text: String) -> [[String?]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let string = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: string.length)).map { match in
            (1..<match.numberOfRanges).map { index in
                let range = match.range(at: index)
                return range.location == NSNotFound ? nil : string.substring(with: range)
            }
        }
    }
}

private extension String {
    func firstMatch(_ pattern: String) -> String? {
        range(of: pattern, options: .regularExpression).map { String(self[$0]) }
    }
}

/// Combines readings: a second reading of the same page, or another source. Pure code.
///
/// Fills only what's missing. Across hosts: figures within 3% add "confirmed by" the other host;
/// more than 8% apart keeps the manufacturer's figure (or the first one when neither or both are
/// the manufacturer), marks it conflicting and notes both hosts. A verified manufacturer figure
/// is never replaced by a retailer's.
enum SourceMerger {
    static func merge(_ base: StatedFacts, with extra: StatedFacts) -> StatedFacts {
        var merged = base
        merged.rejections += extra.rejections

        if let incoming = extra.kilocaloriesPerGram {
            if let current = merged.kilocaloriesPerGram {
                merged.kilocaloriesPerGram = reconcile(current, incoming, describe: CalorieVerifier.describePerKilogram)
            } else {
                merged.kilocaloriesPerGram = incoming
            }
        }

        for size in extra.sizes {
            if let index = merged.sizes.firstIndex(where: { !CalorieVerifier.differs($0.grams.value, size.grams.value, by: CalorieVerifier.confirmationTolerance) }) {
                merged.sizes[index].grams = reconcile(merged.sizes[index].grams, size.grams) { "\(CalorieVerifier.format($0)) g" }
                if let incoming = size.kilocalories {
                    if let current = merged.sizes[index].kilocalories {
                        merged.sizes[index].kilocalories = reconcile(current, incoming) { "\(CalorieVerifier.format($0)) kcal" }
                    } else {
                        merged.sizes[index].kilocalories = incoming
                    }
                }
            } else if base.sizes.isEmpty {
                // No unit size was known yet: take the other source's sizes.
                merged.sizes.append(size)
            }
        }
        return merged
    }

    /// Two figures for the same thing.
    static func reconcile(_ current: Fact, _ incoming: Fact, describe: (Double) -> String) -> Fact {
        guard let currentHost = current.source?.host, let incomingHost = incoming.source?.host, currentHost != incomingHost else {
            return current
        }
        if !CalorieVerifier.differs(incoming.value, current.value, by: CalorieVerifier.confirmationTolerance) {
            var confirmed = current
            if !confirmed.confirmedBy.contains(incomingHost) { confirmed.confirmedBy.append(incomingHost) }
            return confirmed
        }
        guard CalorieVerifier.differs(incoming.value, current.value, by: CalorieVerifier.disagreementTolerance) else { return current }
        let preferIncoming = incoming.source?.isManufacturer == true && current.source?.isManufacturer != true
        var kept = preferIncoming ? incoming : current
        let other = preferIncoming ? current : incoming
        kept.status = .conflicting
        kept.conflict = "\(kept.source?.host ?? "One source") says \(describe(kept.value)); \(other.source?.host ?? "another") says \(describe(other.value)). Kept \(kept.source?.host ?? "the first")."
        return kept
    }
}

/// Whether another page is the same product as the one found first: same brand, the same recipe
/// words, the same form, and (checked by `SourceMerger` when sizes are matched) the same unit size.
enum SourceIdentity {
    struct Target: Sendable {
        var brand: String
        var line: String
        var name: String
        var form: ExtractedFood.Form?
    }

    static let genericWords: Set<String> = [
        "cat", "cats", "food", "foods", "the", "and", "with", "for", "wet", "dry", "recipe", "formula",
        "adult", "kitten", "can", "cans", "canned", "pouch", "net", "complete", "natural", "flavor",
    ]

    static func words(_ text: String) -> Set<String> {
        Set(CalorieVerifier.normalize(text).split { !$0.isLetter && !$0.isNumber }.map(String.init)
            .filter { $0.count >= 3 && !genericWords.contains($0) && !$0.allSatisfy(\.isNumber) })
    }

    static func matches(_ target: Target, _ candidate: ExtractedFood, host: String) -> Bool {
        guard candidate.found, candidate.sameProduct != false else { return false }
        let candidateWords = words([candidate.brand, candidate.line, candidate.name].compactMap { $0 }.joined(separator: " "))
        let brandWords = words(target.brand)
        let compactHost = host.lowercased().filter { $0.isLetter || $0.isNumber }
        if !brandWords.isEmpty, brandWords.isDisjoint(with: candidateWords), !brandWords.contains(where: compactHost.contains) {
            return false
        }
        let recipeWords = words(target.name).subtracting(brandWords)
        if !recipeWords.isEmpty {
            let shared = recipeWords.intersection(candidateWords).count
            if Double(shared) / Double(recipeWords.count) < 0.6 { return false }
        }
        if let form = target.form, form != .other, let other = candidate.parsedForm, other != .other, other != form {
            return false
        }
        return true
    }
}
