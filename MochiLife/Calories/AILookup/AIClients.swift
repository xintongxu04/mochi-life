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
    /// Downloads an image and returns it shrunk to the app's thumbnail size and format. Throws
    /// if it isn't a supported image or can't be decoded.
    func fetchThumbnail(_ candidate: ImageCandidate) async throws -> Data
}

/// Searches for images. Brave's image search may not be included in every plan; an
/// `ImageSearchUnavailable` error means the key doesn't allow it.
protocol ImageSearchClient: Sendable {
    func searchImages(_ query: String, count: Int) async throws -> [ImageCandidate]
}

struct ImageSearchUnavailable: Error {}

/// Remembers that the Brave key doesn't allow image search, so the fallback is skipped quietly.
/// Cleared when a Brave key is saved.
enum ImageSearchAvailability {
    private static let key = "braveImageSearch.unavailable"
    static var isKnownUnavailable: Bool { UserDefaults.standard.bool(forKey: key) }
    static func markUnavailable() { UserDefaults.standard.set(true, forKey: key) }
    static func reset() { UserDefaults.standard.removeObject(forKey: key) }
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
        URLSession(configuration: configuration(timeout: timeout))
    }

    /// For Brave and DeepSeek API calls: redirects aren't followed, so a key header can never be
    /// dropped or sent elsewhere by one; a redirect shows up as its 3xx status instead.
    static func apiSession(timeout: TimeInterval) -> URLSession {
        URLSession(configuration: configuration(timeout: timeout), delegate: NoRedirects(), delegateQueue: nil)
    }

    private static func configuration(timeout: TimeInterval) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return configuration
    }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? {
            AILog.logger.notice("api_redirect_refused http_status=\(response.statusCode)")
            return nil
        }
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
            let session = HTTPCheck.apiSession(timeout: 15)
            defer { session.finishTasksAndInvalidate() }
            let (data, response) = try await session.data(for: request)
            // Brave answers an invalid token with 422 rather than 401.
            if (response as? HTTPURLResponse)?.statusCode == 422,
               String(decoding: data, as: UTF8.self).lowercased().contains("token") {
                AILog.logger.info("brave_search http_status=422 token_rejected")
                throw LookupFailure.keyRejected(.brave)
            }
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

/// The DeepSeek model and request settings for AI lookup — the only place the model is named.
///
/// Chosen 2026-10-05 from DeepSeek's models & pricing page and API reference: `deepseek-flash`
/// (DeepSeek-V4.1-Flash) supports JSON output, has a 1M-token context, is the speed tier, and is
/// the cheapest. Re-verify the identifier whenever DeepSeek changes its lineup.
enum DeepSeekModelConfig {
    static let model = "deepseek-flash"
    /// Choosing a page needs only a short JSON answer.
    static let selectionMaxTokens = 300
    /// Room for the full extraction JSON, including long ingredient lists.
    static let extractionMaxTokens = 2_000
    /// Per request; a timeout is reported as the usual "took too long" error.
    static let requestTimeout: TimeInterval = 45
}

/// Brave image search: GET https://api.search.brave.com/res/v1/images/search. Uses each result's
/// Brave-hosted thumbnail (thumbnail.src, about 500 px wide), which loads reliably, with the
/// original image's page as Referer.
struct BraveImageSearchClient: ImageSearchClient {
    let apiKey: String

    private struct Response: Decodable {
        struct Result: Decodable {
            struct Thumbnail: Decodable { var src: String? }
            struct Properties: Decodable { var url: String? }
            var source: String?
            var url: String?
            var thumbnail: Thumbnail?
            var properties: Properties?
        }
        var results: [Result]?
    }

    func searchImages(_ query: String, count: Int) async throws -> [ImageCandidate] {
        var components = URLComponents(string: "https://api.search.brave.com/res/v1/images/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: String(query.prefix(400))),
            URLQueryItem(name: "count", value: String(count)),
            URLQueryItem(name: "safesearch", value: "strict"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(apiKey, forHTTPHeaderField: "X-Subscription-Token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let session = HTTPCheck.apiSession(timeout: 15)
            defer { session.finishTasksAndInvalidate() }
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            AILog.logger.info("brave_image_search http_status=\(status)")
            // The web search key works (it's checked first), so a refusal here means the plan
            // doesn't include image search.
            if [401, 402, 403, 422].contains(status) { throw ImageSearchUnavailable() }
            try HTTPCheck.validate(response, service: .brave, purpose: "brave_image_search")
            let results = (try JSONDecoder().decode(Response.self, from: data)).results ?? []
            AILog.logger.info("brave_image_search results=\(results.count)")
            return results.compactMap { result in
                let page = (result.source ?? result.url).flatMap(URL.init(string:))
                guard let src = result.thumbnail?.src ?? result.properties?.url,
                      let url = ImageCandidateFinder.resolve(src, against: page ?? URL(string: "https://search.brave.com")!)
                else { return nil }
                return ImageCandidate(url: url, referer: page, source: .imageSearch)
            }
        } catch is DecodingError {
            throw LookupFailure.unreadableAnswer
        } catch let error as ImageSearchUnavailable {
            throw error
        } catch {
            throw HTTPCheck.translate(error)
        }
    }
}

/// DeepSeek chat completions (OpenAI format) with JSON output, temperature 0, streaming off and
/// thinking turned off (thinking mode ignores temperature and is slower).
struct DeepSeekClient: ChatCompletionClient {
    let apiKey: String

    private struct Body: Encodable {
        struct ResponseFormat: Encodable { var type = "json_object" }
        struct Thinking: Encodable { var type = "disabled" }
        var model = DeepSeekModelConfig.model
        var messages: [ChatMessage]
        var temperature = 0.0
        var max_tokens: Int
        var response_format = ResponseFormat()
        var thinking = Thinking()
        var stream = false
    }

    private struct ErrorBody: Decodable {
        struct Detail: Decodable { var message: String? }
        var error: Detail?
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
            let session = HTTPCheck.apiSession(timeout: DeepSeekModelConfig.requestTimeout)
            defer { session.finishTasksAndInvalidate() }
            let (data, response) = try await session.data(for: request)
            try Self.checkModelAvailable(response, data: data, purpose: purpose)
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

    /// A request error that names the model means DeepSeek no longer offers this app's model
    /// (DeepSeek's docs don't define a specific code, so 400, 404 and 422 are checked).
    private static func checkModelAvailable(_ response: URLResponse, data: Data, purpose: String) throws {
        guard let status = (response as? HTTPURLResponse)?.statusCode, [400, 404, 422].contains(status) else { return }
        let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error?.message?.lowercased() ?? ""
        guard message.contains("model") else { return }
        AILog.logger.error("deepseek_\(purpose, privacy: .public) model_unavailable model=\(DeepSeekModelConfig.model, privacy: .public) http_status=\(status)")
        throw LookupFailure.modelUnavailable
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

    /// Image types accepted for product photos (all decodable by ImageIO).
    static let imageTypes: Set<String> = [
        "image/jpeg", "image/jpg", "image/pjpeg", "image/png", "image/webp", "image/avif",
        "image/heic", "image/heif", "image/gif",
    ]
    static let imageAccept = "image/avif,image/webp,image/heic,image/jpeg,image/png,image/gif;q=0.9,image/*;q=0.8"

    func fetchThumbnail(_ candidate: ImageCandidate) async throws -> Data {
        let (data, response) = try await download(
            candidate.url, timeout: 10, cap: 5 * 1024 * 1024, purpose: "image_fetch",
            accept: Self.imageAccept, referer: candidate.referer
        )
        let type = response.mimeType?.lowercased() ?? "none"
        AILog.logger.info("image_fetch source=\(candidate.source.rawValue, privacy: .public) host=\(candidate.url.host() ?? "-", privacy: .public) content_type=\(type, privacy: .public) bytes=\(data.count)")
        guard Self.imageTypes.contains(type) else {
            AILog.logger.info("image_fetch rejected unsupported content_type")
            throw LookupFailure.blockedOrEmptyPage
        }
        let jpeg = await Task.detached(priority: .userInitiated) { FoodThumbnailStore.thumbnailJPEG(from: data) }.value
        AILog.logger.info("image_decode ok=\(jpeg != nil)")
        guard let jpeg else { throw LookupFailure.blockedOrEmptyPage }
        return jpeg
    }

    private func download(_ url: URL, timeout: TimeInterval, cap: Int, purpose: String,
                          accept: String = "text/html,application/xhtml+xml,*/*;q=0.8",
                          referer: URL? = nil) async throws -> (Data, HTTPURLResponse) {
        guard url.scheme?.lowercased() == "https" else { throw LookupFailure.blockedOrEmptyPage }
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if let referer { request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer") }
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
