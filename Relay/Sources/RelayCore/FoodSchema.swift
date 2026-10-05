import Foundation

// The Food type the relay returns and the JSON Schema Claude must fill in live together in this
// file. `FoodSchema.selfCheck()` compares them and fails if they drift; every relay command runs
// it before doing anything else.

/// A cat food found by a lookup, shaped like the app's bundled seed data so it imports cleanly.
public struct RelayFood: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case food, topper, supplement, treat
    }

    public enum Form: String, Codable, Sendable, CaseIterable {
        case wet, dry, other
    }

    public enum Confidence: String, Codable, Sendable, CaseIterable {
        case high, medium, low
    }

    public struct Serving: Codable, Sendable, Equatable {
        public enum Basis: String, Codable, Sendable, CaseIterable {
            case statedOnPage = "stated on page"
            case calculatedFromKcalPerKg = "calculated from kcal per kg"
        }

        /// As the brand names it, e.g. "2.8 oz can".
        public var size: String
        public var grams: Double?
        /// Calories in one whole can or pouch.
        public var kcal: Double?
        public var basis: Basis

        public init(size: String, grams: Double?, kcal: Double?, basis: Basis) {
            self.size = size
            self.grams = grams
            self.kcal = kcal
            self.basis = basis
        }
    }

    public struct GuaranteedAnalysis: Codable, Sendable, Equatable {
        public var crudeProteinMinPct: Double?
        public var crudeFatMinPct: Double?
        public var crudeFiberMaxPct: Double?
        public var moistureMaxPct: Double?
        public var other: [String]

        public init(crudeProteinMinPct: Double?, crudeFatMinPct: Double?, crudeFiberMaxPct: Double?,
                    moistureMaxPct: Double?, other: [String]) {
            self.crudeProteinMinPct = crudeProteinMinPct
            self.crudeFatMinPct = crudeFatMinPct
            self.crudeFiberMaxPct = crudeFiberMaxPct
            self.moistureMaxPct = moistureMaxPct
            self.other = other
        }

        enum CodingKeys: String, CodingKey {
            case crudeProteinMinPct = "crude_protein_min_pct"
            case crudeFatMinPct = "crude_fat_min_pct"
            case crudeFiberMaxPct = "crude_fiber_max_pct"
            case moistureMaxPct = "moisture_max_pct"
            case other
        }
    }

    public var brand: String
    public var line: String?
    public var name: String
    public var type: Kind
    public var form: Form
    public var servings: [Serving]
    public var kcalPerG: Double?
    public var calorieStatement: String?
    public var ingredients: String?
    public var guaranteedAnalysis: GuaranteedAnalysis
    public var sourceURL: String?
    public var imageURL: String?
    /// Added by the relay after the lookup; Claude always leaves it null.
    public var thumbnailJPEGBase64: String?
    public var confidence: Confidence
    public var notes: [String]

    enum CodingKeys: String, CodingKey {
        case brand, line, name, type, form, servings, ingredients, confidence, notes
        case kcalPerG = "kcal_per_g"
        case calorieStatement = "calorie_statement"
        case guaranteedAnalysis = "guaranteed_analysis"
        case sourceURL = "source_url"
        case imageURL = "image_url"
        case thumbnailJPEGBase64 = "thumbnail_jpeg_base64"
    }
}

/// What Claude returns: whether a confident match was found, and the food if so.
public struct LookupOutcome: Codable, Sendable, Equatable {
    public enum Status: String, Codable, Sendable, CaseIterable {
        case ok
        case notFound = "not_found"
    }

    public var status: Status
    public var food: RelayFood?
}

public enum FoodSchema {
    /// JSON Schema for `LookupOutcome`, passed to `claude --json-schema`. Every property is listed
    /// in `required` (optional values are nullable instead) and extra properties are not allowed.
    public static let lookupOutcomeJSON = #"""
    {
      "type": "object",
      "additionalProperties": false,
      "required": ["status", "food"],
      "properties": {
        "status": { "type": "string", "enum": ["ok", "not_found"] },
        "food": {
          "anyOf": [
            { "type": "null" },
            {
              "type": "object",
              "additionalProperties": false,
              "required": ["brand", "line", "name", "type", "form", "servings", "kcal_per_g",
                           "calorie_statement", "ingredients", "guaranteed_analysis", "source_url",
                           "image_url", "thumbnail_jpeg_base64", "confidence", "notes"],
              "properties": {
                "brand": { "type": "string" },
                "line": { "type": ["string", "null"] },
                "name": { "type": "string" },
                "type": { "type": "string", "enum": ["food", "topper", "supplement", "treat"] },
                "form": { "type": "string", "enum": ["wet", "dry", "other"] },
                "servings": {
                  "type": "array",
                  "items": {
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["size", "grams", "kcal", "basis"],
                    "properties": {
                      "size": { "type": "string" },
                      "grams": { "type": ["number", "null"] },
                      "kcal": { "type": ["number", "null"] },
                      "basis": { "type": "string", "enum": ["stated on page", "calculated from kcal per kg"] }
                    }
                  }
                },
                "kcal_per_g": { "type": ["number", "null"] },
                "calorie_statement": { "type": ["string", "null"] },
                "ingredients": { "type": ["string", "null"] },
                "guaranteed_analysis": {
                  "type": "object",
                  "additionalProperties": false,
                  "required": ["crude_protein_min_pct", "crude_fat_min_pct", "crude_fiber_max_pct",
                               "moisture_max_pct", "other"],
                  "properties": {
                    "crude_protein_min_pct": { "type": ["number", "null"] },
                    "crude_fat_min_pct": { "type": ["number", "null"] },
                    "crude_fiber_max_pct": { "type": ["number", "null"] },
                    "moisture_max_pct": { "type": ["number", "null"] },
                    "other": { "type": "array", "items": { "type": "string" } }
                  }
                },
                "source_url": { "type": ["string", "null"] },
                "image_url": { "type": ["string", "null"] },
                "thumbnail_jpeg_base64": { "type": "null" },
                "confidence": { "type": "string", "enum": ["high", "medium", "low"] },
                "notes": { "type": "array", "items": { "type": "string" } }
              }
            }
          ]
        }
      }
    }
    """#

    /// The schema as compact single-line JSON, for the command line.
    public static func compactJSON() throws -> String {
        let object = try JSONSerialization.jsonObject(with: Data(lookupOutcomeJSON.utf8))
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    public struct DriftError: Error, CustomStringConvertible {
        public var description: String
    }

    /// Fails if the schema and the Codable types disagree: same property names at every level,
    /// every property required, and the same allowed values for every enum.
    public static func selfCheck() throws {
        let schema = try object(JSONSerialization.jsonObject(with: Data(lookupOutcomeJSON.utf8)), "schema")
        let sample = LookupOutcome(status: .ok, food: .fullySpecifiedSample)
        let encoded = try object(
            JSONSerialization.jsonObject(with: JSONEncoder.relay.encode(sample)), "encoded sample"
        )
        try compare(schema: schema, value: encoded, path: "$")

        let food = try object(foodSchema(in: schema), "food schema")
        let foodProperties = try object(food["properties"], "food properties")
        try expectEnum(schema, path: ["properties", "status"], equals: LookupOutcome.Status.allCases.map(\.rawValue))
        try expectEnum(foodProperties["type"], equals: RelayFood.Kind.allCases.map(\.rawValue), name: "type")
        try expectEnum(foodProperties["form"], equals: RelayFood.Form.allCases.map(\.rawValue), name: "form")
        try expectEnum(foodProperties["confidence"], equals: RelayFood.Confidence.allCases.map(\.rawValue), name: "confidence")
        let serving = try object(object(foodProperties["servings"], "servings")["items"], "serving")
        try expectEnum(object(serving["properties"], "serving properties")["basis"],
                       equals: RelayFood.Serving.Basis.allCases.map(\.rawValue), name: "basis")
    }

    // MARK: - Drift check helpers

    private static func compare(schema: [String: Any], value: [String: Any], path: String) throws {
        let properties = try object(schema["properties"], "\(path) properties")
        let required = Set(schema["required"] as? [String] ?? [])
        let schemaKeys = Set(properties.keys)
        let valueKeys = Set(value.keys)
        guard schemaKeys == valueKeys else {
            throw DriftError(description: "\(path): schema has \(schemaKeys.sorted()) but the Codable type encodes \(valueKeys.sorted())")
        }
        guard required == schemaKeys else {
            throw DriftError(description: "\(path): every property must be required; missing \(schemaKeys.subtracting(required).sorted())")
        }
        guard schema["additionalProperties"] as? Bool == false else {
            throw DriftError(description: "\(path): additionalProperties must be false")
        }
        for (key, child) in value {
            let childSchema = try object(properties[key], "\(path).\(key)")
            if let childObject = child as? [String: Any] {
                try compare(schema: objectSchema(childSchema), value: childObject, path: "\(path).\(key)")
            } else if let array = child as? [Any], let first = array.first as? [String: Any] {
                let items = try object(childSchema["items"], "\(path).\(key) items")
                try compare(schema: items, value: first, path: "\(path).\(key)[]")
            }
        }
    }

    /// The object branch of a schema that may be `anyOf: [null, object]`.
    private static func objectSchema(_ schema: [String: Any]) throws -> [String: Any] {
        if let anyOf = schema["anyOf"] as? [[String: Any]],
           let branch = anyOf.first(where: { $0["type"] as? String == "object" }) {
            return branch
        }
        return schema
    }

    private static func foodSchema(in schema: [String: Any]) throws -> [String: Any] {
        try objectSchema(object(object(schema["properties"], "properties")["food"], "food"))
    }

    private static func expectEnum(_ schema: [String: Any], path: [String], equals values: [String]) throws {
        var node: Any? = schema
        for key in path { node = (node as? [String: Any])?[key] }
        try expectEnum(node, equals: values, name: path.joined(separator: "."))
    }

    private static func expectEnum(_ node: Any?, equals values: [String], name: String) throws {
        let schemaValues = Set(((node as? [String: Any])?["enum"] as? [String]) ?? [])
        guard schemaValues == Set(values) else {
            throw DriftError(description: "enum \(name): schema allows \(schemaValues.sorted()) but the Codable type has \(values.sorted())")
        }
    }

    private static func object(_ value: Any?, _ name: String) throws -> [String: Any] {
        guard let object = value as? [String: Any] else {
            throw DriftError(description: "\(name) is not a JSON object")
        }
        return object
    }
}

extension RelayFood {
    /// Every optional filled in, so encoding shows every key the type can produce.
    static let fullySpecifiedSample = RelayFood(
        brand: "b", line: "l", name: "n", type: .food, form: .wet,
        servings: [Serving(size: "s", grams: 1, kcal: 1, basis: .statedOnPage)],
        kcalPerG: 1, calorieStatement: "c", ingredients: "i",
        guaranteedAnalysis: GuaranteedAnalysis(crudeProteinMinPct: 1, crudeFatMinPct: 1, crudeFiberMaxPct: 1,
                                               moistureMaxPct: 1, other: ["o"]),
        sourceURL: "https://example.com", imageURL: "https://example.com/i.jpg", thumbnailJPEGBase64: "AA==",
        confidence: .high, notes: ["n"]
    )
}
