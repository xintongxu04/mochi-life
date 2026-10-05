import Foundation

/// Mochi Relay message protocol, version 1. Every frame carries one JSON envelope.
public enum RelayProtocol {
    public static let version = 1
    /// Requests whose typed name and OCR lines together exceed this many characters are rejected.
    public static let maximumTextLength = 8_000
    /// Frames larger than this close the connection.
    public static let maximumFrameSize = 2 * 1024 * 1024
    /// Bonjour service type the relay advertises.
    public static let bonjourServiceType = "_mochirelay._tcp"
}

public struct RelayRequest: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case ping
        case lookup
    }

    public var v: Int
    public var id: UUID
    public var type: Kind
    public var lookup: LookupQuery?

    public init(v: Int = RelayProtocol.version, id: UUID = UUID(), type: Kind, lookup: LookupQuery? = nil) {
        self.v = v
        self.id = id
        self.type = type
        self.lookup = lookup
    }

    /// Checks the request is something the relay can act on. Returns nil when valid.
    public func validationError() -> RelayError? {
        guard v == RelayProtocol.version else {
            return RelayError(code: .unsupportedVersion, message: "This relay speaks protocol version \(RelayProtocol.version).")
        }
        switch type {
        case .ping:
            return nil
        case .lookup:
            guard let lookup else {
                return RelayError(code: .invalidRequest, message: "A lookup request needs a lookup field.")
            }
            return lookup.validationError()
        }
    }
}

public struct LookupQuery: Codable, Sendable, Equatable {
    public var typedName: String?
    public var ocrLines: [String]?
    public var brandHint: String?

    public init(typedName: String? = nil, ocrLines: [String]? = nil, brandHint: String? = nil) {
        self.typedName = typedName
        self.ocrLines = ocrLines
        self.brandHint = brandHint
    }

    enum CodingKeys: String, CodingKey {
        case typedName = "typed_name"
        case ocrLines = "ocr_lines"
        case brandHint = "brand_hint"
    }

    var trimmedName: String? {
        typedName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var trimmedLines: [String] {
        (ocrLines ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    public func validationError() -> RelayError? {
        guard trimmedName != nil || !trimmedLines.isEmpty else {
            return RelayError(code: .invalidRequest, message: "Give a typed name or at least one OCR line.")
        }
        let total = (typedName?.count ?? 0) + (ocrLines ?? []).reduce(0) { $0 + $1.count } + (brandHint?.count ?? 0)
        guard total <= RelayProtocol.maximumTextLength else {
            return RelayError(code: .invalidRequest, message: "The query text is longer than \(RelayProtocol.maximumTextLength) characters.")
        }
        return nil
    }
}

public struct RelayResponse: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case pong
        case progress
        case result
    }

    public enum Stage: String, Codable, Sendable {
        case queued
        case searching
        case fetchingImage = "fetching_image"
    }

    public enum Status: String, Codable, Sendable {
        case ok
        case notFound = "not_found"
        case error
    }

    public var v: Int
    public var id: UUID
    public var type: Kind
    public var relayVersion: String?
    public var stage: Stage?
    public var status: Status?
    public var food: RelayFood?
    public var error: RelayError?

    public init(
        id: UUID, type: Kind, relayVersion: String? = nil, stage: Stage? = nil,
        status: Status? = nil, food: RelayFood? = nil, error: RelayError? = nil
    ) {
        self.v = RelayProtocol.version
        self.id = id
        self.type = type
        self.relayVersion = relayVersion
        self.stage = stage
        self.status = status
        self.food = food
        self.error = error
    }

    enum CodingKeys: String, CodingKey {
        case v, id, type, stage, status, food, error
        case relayVersion = "relay_version"
    }

    public static func pong(id: UUID, relayVersion: String) -> RelayResponse {
        RelayResponse(id: id, type: .pong, relayVersion: relayVersion)
    }

    public static func progress(id: UUID, _ stage: Stage) -> RelayResponse {
        RelayResponse(id: id, type: .progress, stage: stage)
    }

    public static func result(id: UUID, food: RelayFood?) -> RelayResponse {
        RelayResponse(id: id, type: .result, status: food == nil ? .notFound : .ok, food: food)
    }

    public static func failure(id: UUID, _ error: RelayError) -> RelayResponse {
        RelayResponse(id: id, type: .result, status: .error, error: error)
    }
}

public struct RelayError: Codable, Sendable, Equatable, Error {
    public enum Code: String, Codable, Sendable, CaseIterable {
        case busy
        case rateLimited = "rate_limited"
        case invalidRequest = "invalid_request"
        case claudeUnavailable = "claude_unavailable"
        case claudeFailed = "claude_failed"
        case timeout
        case unsupportedVersion = "unsupported_version"
    }

    public var code: Code
    public var message: String

    public init(code: Code, message: String) {
        self.code = code
        self.message = message
    }
}

public extension JSONEncoder {
    /// The encoder for relay frames.
    static var relay: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
