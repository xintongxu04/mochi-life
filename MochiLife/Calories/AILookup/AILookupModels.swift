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

/// The pipeline's stages, shown on the progress screen.
enum LookupStage: String, Sendable {
    case searching = "Searching the web"
    case choosing = "Choosing the product page"
    case fetching = "Reading the product page"
    case extracting = "Reading the label details"
    case fetchingPhoto = "Getting the product photo"
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

/// What the extraction step asks DeepSeek to return.
struct ExtractedFood: Codable, Sendable, Equatable {
    struct Size: Codable, Sendable, Equatable {
        var label: String
        var ounces: Double?
        var grams: Double?
        var kcalPerContainer: Double?

        enum CodingKeys: String, CodingKey {
            case label, ounces, grams
            case kcalPerContainer = "kcal_per_container"
        }
    }

    struct Analysis: Codable, Sendable, Equatable {
        var crudeProteinMinPct: Double?
        var crudeFatMinPct: Double?
        var crudeFiberMaxPct: Double?
        var moistureMaxPct: Double?
        var other: [String]

        enum CodingKeys: String, CodingKey {
            case crudeProteinMinPct = "crude_protein_min_pct"
            case crudeFatMinPct = "crude_fat_min_pct"
            case crudeFiberMaxPct = "crude_fiber_max_pct"
            case moistureMaxPct = "moisture_max_pct"
            case other
        }
    }

    enum Kind: String, Codable, Sendable { case food, topper, supplement, treat }
    enum Form: String, Codable, Sendable { case wet, dry, other }
    enum Confidence: String, Codable, Sendable { case high, medium, low }

    var found: Bool
    var brand: String?
    var line: String?
    var name: String?
    var type: Kind
    var form: Form
    var sizes: [Size]
    var kcalPerKg: Double?
    var calorieStatement: String?
    var ingredients: String?
    var guaranteedAnalysis: Analysis
    var confidence: Confidence
    var notes: [String]

    enum CodingKeys: String, CodingKey {
        case found, brand, line, name, type, form, sizes, ingredients, confidence, notes
        case kcalPerKg = "kcal_per_kg"
        case calorieStatement = "calorie_statement"
        case guaranteedAnalysis = "guaranteed_analysis"
    }
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
        var grams: Double?
        var kilocalories: Double?
        /// True when the calories were worked out from kcal/kg rather than stated per container.
        var isCalculated: Bool
    }

    var brand: String
    var line: String
    var name: String
    var kind: FoodKind
    var form: ExtractedFood.Form
    var sizes: [Size]
    var kilocaloriesPerGram: Double?
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
