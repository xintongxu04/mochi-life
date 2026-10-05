import Foundation
import os

/// Searches the web. Replaceable for previews or other providers.
protocol WebSearchClient: Sendable {
    func search(_ query: String, count: Int) async throws -> [SearchResult]
}

/// Sends a chat conversation and returns the model's reply text.
protocol ChatCompletionClient: Sendable {
    func complete(_ messages: [ChatMessage], maxTokens: Int, purpose: String) async throws -> String
}

/// Downloads a web page or image.
protocol WebFetcher: Sendable {
    func fetchPage(_ url: URL) async throws -> FetchedPage
    func fetchImage(_ url: URL) async throws -> Data
}

struct ChatMessage: Codable, Sendable, Equatable {
    enum Role: String, Codable, Sendable { case system, user, assistant }
    var role: Role
    var content: String
}

struct FetchedPage: Sendable {
    var url: URL
    var html: String
}

enum AILog {
    static let logger = Logger(subsystem: "com.xintongxu.MochiLife", category: "aiLookup")
}

/// Turns HTTP and network errors into `LookupFailure`s that name the service.
enum HTTPCheck {
    static func validate(_ response: URLResponse, service: AIService, purpose: String) throws {
        guard let http = response as? HTTPURLResponse else { throw LookupFailure.unexpectedStatus(service, 0) }
        AILog.logger.info("\(purpose, privacy: .public) http_status=\(http.statusCode)")
        switch http.statusCode {
        case 200..<300: return
        case 401, 403: throw LookupFailure.keyRejected(service)
        case 402: throw LookupFailure.insufficientBalance(service)
        case 429: throw LookupFailure.rateLimited(service)
        case 500..<600: throw LookupFailure.serverError(service, http.statusCode)
        default: throw LookupFailure.unexpectedStatus(service, http.statusCode)
        }
    }

    /// Maps URLSession errors; passes LookupFailure and cancellation through.
    static func translate(_ error: Error) -> Error {
        if error is LookupFailure || error is CancellationError { return error }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled: return CancellationError()
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
                return LookupFailure.offline
            case .timedOut: return LookupFailure.timeout
            default: return LookupFailure.blockedOrEmptyPage
            }
        }
        return error
    }

    static func session(timeout: TimeInterval) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }
}

/// Brave Search web results: GET https://api.search.brave.com/res/v1/web/search with the key
/// in the X-Subscription-Token header.
struct BraveSearchClient: WebSearchClient {
    let apiKey: String

    private struct Response: Decodable {
        struct Web: Decodable {
            struct Result: Decodable {
                var title: String?
                var url: String?
                var description: String?
            }
            var results: [Result]?
        }
        var web: Web?
    }

    func search(_ query: String, count: Int) async throws -> [SearchResult] {
        var components = URLComponents(string: "https://api.search.brave.com/res/v1/web/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: String(query.prefix(400))),
            URLQueryItem(name: "count", value: String(count)),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(apiKey, forHTTPHeaderField: "X-Subscription-Token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let session = HTTPCheck.session(timeout: 15)
            defer { session.finishTasksAndInvalidate() }
            let (data, response) = try await session.data(for: request)
            try HTTPCheck.validate(response, service: .brave, purpose: "brave_search")
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            return (decoded.web?.results ?? []).compactMap { result in
                guard let urlString = result.url, let url = URL(string: urlString) else { return nil }
                return SearchResult(
                    title: HTMLReducer.plainText(fromFragment: result.title ?? ""),
                    url: url,
                    description: HTMLReducer.plainText(fromFragment: result.description ?? "")
                )
            }
        } catch is DecodingError {
            throw LookupFailure.unreadableAnswer
        } catch {
            throw HTTPCheck.translate(error)
        }
    }
}

/// DeepSeek chat completions (OpenAI format) with JSON output, temperature 0 and thinking turned
/// off (thinking mode ignores temperature).
struct DeepSeekClient: ChatCompletionClient {
    let apiKey: String
    static let model = "deepseek-flash"

    private struct Body: Encodable {
        struct ResponseFormat: Encodable { var type = "json_object" }
        struct Thinking: Encodable { var type = "disabled" }
        var model = DeepSeekClient.model
        var messages: [ChatMessage]
        var temperature = 0.0
        var max_tokens: Int
        var response_format = ResponseFormat()
        var thinking = Thinking()
        var stream = false
    }

    private struct Response: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { var content: String? }
            var message: Message
            var finish_reason: String?
        }
        struct Usage: Decodable {
            var prompt_tokens: Int?
            var completion_tokens: Int?
            var total_tokens: Int?
            var prompt_cache_hit_tokens: Int?
        }
        var choices: [Choice]
        var usage: Usage?
    }

    func complete(_ messages: [ChatMessage], maxTokens: Int, purpose: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.deepseek.com/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(Body(messages: messages, max_tokens: maxTokens))
        do {
            let session = HTTPCheck.session(timeout: 60)
            defer { session.finishTasksAndInvalidate() }
            let (data, response) = try await session.data(for: request)
            try HTTPCheck.validate(response, service: .deepSeek, purpose: "deepseek_\(purpose)")
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            let usage = decoded.usage
            AILog.logger.info("deepseek_\(purpose, privacy: .public) prompt_tokens=\(usage?.prompt_tokens ?? -1) completion_tokens=\(usage?.completion_tokens ?? -1) total_tokens=\(usage?.total_tokens ?? -1) cache_hit_tokens=\(usage?.prompt_cache_hit_tokens ?? -1) finish=\(decoded.choices.first?.finish_reason ?? "-", privacy: .public)")
            return decoded.choices.first?.message.content ?? ""
        } catch is DecodingError {
            throw LookupFailure.unreadableAnswer
        } catch {
            throw HTTPCheck.translate(error)
        }
    }
}

/// Downloads pages and images: https only (also after redirects), size-capped, desktop Safari
/// User-Agent. Redirects are followed by URLSession.
struct URLSessionWebFetcher: WebFetcher {
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    func fetchPage(_ url: URL) async throws -> FetchedPage {
        let (data, response) = try await download(url, timeout: 15, cap: 2 * 1024 * 1024, purpose: "page_fetch")
        let mimeType = response.mimeType?.lowercased() ?? ""
        guard mimeType.contains("html") else { throw LookupFailure.blockedOrEmptyPage }
        let encoding = response.textEncodingName
            .map { CFStringConvertEncodingToNSStringEncoding(CFStringConvertIANACharSetNameToEncoding($0 as CFString)) }
            .map { String.Encoding(rawValue: $0) } ?? .utf8
        let html = String(data: data, encoding: encoding) ?? String(decoding: data, as: UTF8.self)
        guard !html.isEmpty else { throw LookupFailure.blockedOrEmptyPage }
        return FetchedPage(url: response.url ?? url, html: html)
    }

    func fetchImage(_ url: URL) async throws -> Data {
        let (data, response) = try await download(url, timeout: 10, cap: 5 * 1024 * 1024, purpose: "image_fetch")
        guard response.mimeType?.lowercased().hasPrefix("image/") == true else { throw LookupFailure.blockedOrEmptyPage }
        return data
    }

    private func download(_ url: URL, timeout: TimeInterval, cap: Int, purpose: String) async throws -> (Data, HTTPURLResponse) {
        guard url.scheme?.lowercased() == "https" else { throw LookupFailure.blockedOrEmptyPage }
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,image/*;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        let session = HTTPCheck.session(timeout: timeout)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw LookupFailure.blockedOrEmptyPage }
            AILog.logger.info("\(purpose, privacy: .public) http_status=\(http.statusCode)")
            guard (200..<300).contains(http.statusCode), http.url?.scheme?.lowercased() == "https" else {
                throw LookupFailure.blockedOrEmptyPage
            }
            guard http.expectedContentLength <= Int64(cap) else { throw LookupFailure.blockedOrEmptyPage }
            var data = Data()
            data.reserveCapacity(min(Int(max(http.expectedContentLength, 0)), cap))
            var chunk = [UInt8]()
            chunk.reserveCapacity(64 * 1024)
            for try await byte in bytes {
                chunk.append(byte)
                if chunk.count == 64 * 1024 {
                    data.append(contentsOf: chunk)
                    chunk.removeAll(keepingCapacity: true)
                    guard data.count <= cap else { throw LookupFailure.blockedOrEmptyPage }
                }
            }
            data.append(contentsOf: chunk)
            guard data.count <= cap, !data.isEmpty else { throw LookupFailure.blockedOrEmptyPage }
            return (data, http)
        } catch {
            throw HTTPCheck.translate(error)
        }
    }
}
