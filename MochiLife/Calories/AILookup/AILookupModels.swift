import Foundation

/// The services "Add with AI" talks to.
enum AIService: String, Sendable {
    case brave = "Brave Search"
    case deepSeek = "DeepSeek"
}

/// One web search result.
struct SearchResult: Sendable, Equatable {
    var title: String
    var url: URL
    var description: String
}

/// The pipeline's stages, shown on the progress screen. The lookup can be cancelled at any of them.
enum LookupStage: Sendable, Equatable {
    case searching
    case choosing
    case fetching
    case extracting
    /// Opening the page in an invisible browser so tabs and scripts load.
    case rendering
    /// A second, focused reading for calories or package sizes.
    case rechecking
    /// The one extra web search for another source.
    case searchingMore
    /// Reading another source (its host) for calories or sizes.
    case checkingSource(String)
    case fetchingPhoto

    var title: String {
        switch self {
        case .searching: "Searching the web"
        case .choosing: "Choosing the product page"
        case .fetching: "Reading the product page"
        case .extracting: "Reading the label details"
        case .rendering: "Opening the page like a browser"
        case .rechecking: "Looking again for calories and sizes"
        case .searchingMore: "Searching for another source"
        case let .checkingSource(host): "Checking calories on \(host)"
        case .fetchingPhoto: "Getting the product photo"
        }
    }
}

/// Why a lookup ended without a result, in words the owner can act on.
enum LookupFailure: Error, Sendable, Equatable {
    case missingKey(AIService)
    case dailyLimitReached(Int)
    case offline
    case timeout
    case keyRejected(AIService)
    case insufficientBalance(AIService)
    case rateLimited(AIService)
    case serverError(AIService, Int)
    case unexpectedStatus(AIService, Int)
    case blockedOrEmptyPage
    case unreadableAnswer
    case notFound
    /// DeepSeek no longer offers the model this version of the app asks for.
    case modelUnavailable

    var message: String {
        switch self {
        case let .missingKey(service): "Add your \(service.rawValue) API key in AI Lookup settings first."
        case let .dailyLimitReached(cap): "Today's limit of \(cap) AI lookups is used up. Try again tomorrow."
        case .offline: "You're offline. Connect to the internet and try again."
        case .timeout: "The lookup took too long. Try again."
        case let .keyRejected(service): "\(service.rawValue) rejected the API key. Check it in AI Lookup settings."
        case let .insufficientBalance(service): "Your \(service.rawValue) account has no balance left. Add credit and try again."
        case let .rateLimited(service): "\(service.rawValue) is limiting requests right now. Wait a minute and try again."
        case let .serverError(service, status): "\(service.rawValue) had a problem (error \(status)). Try again later."
        case let .unexpectedStatus(service, status): "\(service.rawValue) answered with error \(status)."
        case .blockedOrEmptyPage: "The product pages couldn't be read (blocked or empty)."
        case .unreadableAnswer: "The AI's answer couldn't be read. Try again."
        case .notFound: "No matching cat food was found."
        case .modelUnavailable: "DeepSeek no longer offers the AI model this version of Mochi Life uses. Update the app to keep using Add with AI."
        }
    }
}

/// What the extraction step asks DeepSeek to return. Every calorie figure and package weight
/// carries the exact page text it was copied from (`evidence`), which `CalorieVerifier` checks.
/// Everything is optional so a partial answer still decodes; the verifier decides what's usable.
struct ExtractedFood: Codable, Sendable, Equatable {
    /// Calories per weight as the page writes them (kcal/kg, kcal/g, kcal per 100 g, kJ/kg…).
    struct EnergyDensity: Codable, Sendable, Equatable {
        var value: Double?
        var unit: String?
        var evidence: String?
    }

    /// Calories for one whole container or piece, as written ("per": can, pouch, cup, treat…).
    struct ContainerCalories: Codable, Sendable, Equatable {
        var sizeLabel: String?
        var value: Double?
        var unit: String?
        var per: String?
        var evidence: String?

        enum CodingKeys: String, CodingKey {
            case value, unit, per, evidence
            case sizeLabel = "size_label"
        }
    }

    /// One package size: the weight of one unit, in the unit the page uses.
    struct Size: Codable, Sendable, Equatable {
        var label: String?
        var weight: Double?
        var unit: String?
        var container: String?
        var packCount: Int?
        var evidence: String?

        enum CodingKeys: String, CodingKey {
            case label, weight, unit, container, evidence
            case packCount = "pack_count"
        }
    }

    struct Analysis: Codable, Sendable, Equatable {
        var crudeProteinMinPct: Double?
        var crudeFatMinPct: Double?
        var crudeFiberMaxPct: Double?
        var moistureMaxPct: Double?
        var other: [String]?

        enum CodingKeys: String, CodingKey {
            case crudeProteinMinPct = "crude_protein_min_pct"
            case crudeFatMinPct = "crude_fat_min_pct"
            case crudeFiberMaxPct = "crude_fiber_max_pct"
            case moistureMaxPct = "moisture_max_pct"
            case other
        }
    }

    enum Form: String, Codable, Sendable { case wet, dry, other }
    enum Confidence: String, Codable, Sendable { case high, medium, low }

    var found: Bool
    /// For a second source: whether the page is the same brand, recipe and form as the target.
    var sameProduct: Bool?
    var brand: String?
    var line: String?
    var name: String?
    var type: String?
    var form: String?
    var energyDensity: [EnergyDensity]?
    var containerCalories: [ContainerCalories]?
    var sizes: [Size]?
    var calorieStatement: String?
    var ingredients: String?
    var guaranteedAnalysis: Analysis?
    var confidence: String?
    var notes: [String]?

    enum CodingKeys: String, CodingKey {
        case found, brand, line, name, type, form, sizes, ingredients, confidence, notes
        case sameProduct = "same_product"
        case energyDensity = "energy_density"
        case containerCalories = "container_calories"
        case calorieStatement = "calorie_statement"
        case guaranteedAnalysis = "guaranteed_analysis"
    }

    var parsedForm: Form? { form.flatMap { Form(rawValue: $0.lowercased()) } }
    var parsedConfidence: Confidence { confidence.flatMap { Confidence(rawValue: $0.lowercased()) } ?? .medium }

    /// Names of the fields that came back empty, for diagnostics (never their contents).
    var emptyFields: [String] {
        var empty: [String] = []
        if (energyDensity ?? []).isEmpty { empty.append("energy_density") }
        if (containerCalories ?? []).isEmpty { empty.append("container_calories") }
        if (sizes ?? []).isEmpty { empty.append("sizes") }
        if (calorieStatement ?? "").isEmpty { empty.append("calorie_statement") }
        if (ingredients ?? "").isEmpty { empty.append("ingredients") }
        let analysis = guaranteedAnalysis
        if analysis?.crudeProteinMinPct == nil && analysis?.crudeFatMinPct == nil
            && analysis?.crudeFiberMaxPct == nil && analysis?.moistureMaxPct == nil {
            empty.append("guaranteed_analysis")
        }
        return empty
    }
}

/// How far a calorie figure or package weight can be trusted.
enum FactStatus: String, Sendable, Equatable {
    /// Copied from the page, its quoted text found in what was read, and passed every check.
    case verified
    /// Worked out by the app from verified figures (for example kcal/kg × grams).
    case calculated
    /// Two figures disagree by more than 8%; one is kept and both are noted.
    case conflicting
    /// Failed a check; discarded and never shown as a value.
    case unverified
}

/// Where a figure came from.
struct FactSource: Sendable, Equatable {
    var host: String
    var url: URL
    /// True for the brand's own site, false for retailers and others.
    var isManufacturer: Bool
    /// Which reading supplied it, for diagnostics (for example "static.pass1", "rendered.pass2").
    var stage: String
}

/// One calorie figure or package weight with its status and provenance.
struct Fact: Sendable, Equatable {
    var value: Double
    var status: FactStatus
    /// The exact page text it was copied from; nil when calculated.
    var evidence: String?
    var source: FactSource?
    /// Other hosts whose figure agreed within 3%.
    var confirmedBy: [String] = []
    /// Both figures, in words, when figures disagree by more than 8%.
    var conflict: String?
}

/// What the selection step asks DeepSeek to return.
struct PageChoice: Codable, Sendable, Equatable {
    var choice: Int?
    var alternates: [Int]
    var reason: String
}

/// A found food, after the app's own checks and calculations, ready for the review form.
struct FoodDraft: Sendable, Equatable {
    struct Size: Sendable, Equatable, Identifiable {
        var id = UUID()
        var label: String
        /// can, pouch, tray, cup, bag… when known.
        var container: String?
        var grams: Fact
        var kilocalories: Fact?
    }

    var brand: String
    var line: String
    var name: String
    var kind: FoodKind
    var form: ExtractedFood.Form
    var sizes: [Size]
    /// The calorie basis, in kcal per gram.
    var kilocaloriesPerGram: Fact?
    var calorieStatement: String
    var ingredients: String
    var proteinMinPercent: Double?
    var fatMinPercent: Double?
    var fiberMaxPercent: Double?
    var moistureMaxPercent: Double?
    var otherAnalysis: [String]
    var sourceURL: URL?
    /// JPEG thumbnail data, already shrunk to the app's thumbnail size.
    var thumbnailJPEG: Data?
    var confidence: ExtractedFood.Confidence
    var notes: [String]
}
