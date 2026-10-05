import Foundation
import Security

/// API keys for AI lookup, kept only in the iOS Keychain on this device
/// (kSecAttrAccessibleWhenUnlockedThisDeviceOnly). Never in UserDefaults, logs or the repository.
enum AIKeychain {
    static let service = "com.xintongxu.MochiLife.ailookup"

    static func key(for service: AIService) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: account(service),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let stored = String(data: data, encoding: .utf8)
        else { return nil }
        // Clean on read too, so a key saved by an earlier version is fixed without re-entering it.
        let key = normalize(stored)
        return key.isEmpty ? nil : key
    }

    /// Cleans a pasted API key. Keys never contain spaces, so every whitespace, line break and
    /// invisible character is removed — not just at the ends — along with surrounding quotes and
    /// a pasted "Bearer " prefix.
    static func normalize(_ key: String) -> String {
        var text = key.trimmingCharacters(in: .whitespacesAndNewlines.union(invisibleCharacters))
        if text.lowercased().hasPrefix("bearer ") { text = String(text.dropFirst("bearer ".count)) }
        text = String(text.unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0) && !invisibleCharacters.contains($0)
        }.map(Character.init))
        let quotes = CharacterSet(charactersIn: "\"'“”‘’`")
        return text.trimmingCharacters(in: quotes)
    }

    /// Control and format characters that can ride along when copying text: zero-width spaces
    /// and joiners, the byte-order mark, soft hyphens, and so on.
    private static let invisibleCharacters: CharacterSet = {
        var set = CharacterSet.controlCharacters
        set.insert(charactersIn: "\u{00AD}\u{200B}\u{200C}\u{200D}\u{200E}\u{200F}\u{2060}\u{FEFF}")
        return set
    }()

    /// Saves the key, or removes it when `key` is empty. Returns false if the Keychain refused.
    @discardableResult
    static func setKey(_ key: String, for service: AIService) -> Bool {
        let match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: account(service),
        ]
        SecItemDelete(match as CFDictionary)
        let trimmed = normalize(key)
        guard !trimmed.isEmpty else { return true }
        var item = match
        item[kSecValueData as String] = Data(trimmed.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func hasKey(for service: AIService) -> Bool { key(for: service) != nil }

    private static func account(_ service: AIService) -> String {
        switch service {
        case .brave: "brave_search"
        case .deepSeek: "deepseek"
        }
    }
}

/// The daily cap on AI lookups, stored with the date (not secret, so UserDefaults is fine).
enum AILookupLimit {
    static let dailyCap = 50
    private static let dateKey = "aiLookup.date"
    private static let countKey = "aiLookup.count"

    private static var today: String {
        Date.now.formatted(.iso8601.year().month().day())
    }

    static var usedToday: Int {
        let defaults = UserDefaults.standard
        return defaults.string(forKey: dateKey) == today ? defaults.integer(forKey: countKey) : 0
    }

    static var remainingToday: Int { max(0, dailyCap - usedToday) }

    /// Counts one lookup. Returns false when today's cap is already reached.
    static func reserve() -> Bool {
        let used = usedToday
        guard used < dailyCap else { return false }
        UserDefaults.standard.set(today, forKey: dateKey)
        UserDefaults.standard.set(used + 1, forKey: countKey)
        return true
    }
}

/// The outcome of testing one key, with enough detail to spot a wrong, cut-off or stale key
/// without showing the key itself.
struct KeyTestResult: Sendable, Equatable {
    var summary: String
    /// The service's own error message, on a rejected key.
    var serviceMessage: String?
    /// Length and first three characters of the key that was sent, on a rejected key.
    var keyHint: String?
}

/// "Test keys": one minimal request to each service with the given key (the value in the field,
/// not necessarily the saved one), reporting success or the HTTP status.
enum AIKeyTester {
    static func test(_ service: AIService, key rawKey: String) async -> KeyTestResult {
        let key = AIKeychain.normalize(rawKey)
        guard !key.isEmpty else { return KeyTestResult(summary: "No key entered") }
        var request: URLRequest
        switch service {
        case .brave:
            request = URLRequest(url: URL(string: "https://api.search.brave.com/res/v1/web/search?q=cat%20food&count=1")!)
            request.setValue(key, forHTTPHeaderField: "X-Subscription-Token")
        case .deepSeek:
            // Same request as `curl https://api.deepseek.com/models -H "Authorization: Bearer <key>"`;
            // listing models checks the key without using any tokens.
            request = URLRequest(url: URL(string: "https://api.deepseek.com/models")!)
            request.httpMethod = "GET"
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let session = HTTPCheck.apiSession(timeout: 15)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            AILog.logger.info("key_test service=\(service.rawValue, privacy: .public) http_status=\(status)")
            switch status {
            case 200..<300:
                return KeyTestResult(summary: "Working")
            case 401, 403:
                return KeyTestResult(
                    summary: "Key rejected (HTTP \(status))",
                    serviceMessage: errorMessage(in: data),
                    keyHint: hint(for: key, service: service)
                )
            case 300..<400:
                return KeyTestResult(summary: "Redirected (HTTP \(status)); the request wasn't sent on")
            case 402: return KeyTestResult(summary: "No balance left (HTTP 402)")
            case 429: return KeyTestResult(summary: "Rate limited (HTTP 429)")
            default: return KeyTestResult(summary: "HTTP \(status)", serviceMessage: errorMessage(in: data))
            }
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost].contains(error.code) {
            return KeyTestResult(summary: "Offline")
        } catch {
            return KeyTestResult(summary: "Couldn't connect")
        }
    }

    /// "Key sent: 35 characters, starting “sk-”" — never more of the key than that.
    static func hint(for key: String, service: AIService) -> String {
        var text = "Key sent: \(key.count) characters, starting “\(key.prefix(3))”."
        if service == .deepSeek && !key.hasPrefix("sk-") {
            text += " DeepSeek keys start with “sk-”."
        }
        return text
    }

    /// The service's error message from a JSON error body, if any (DeepSeek uses
    /// {"error": {"message": …}}; Brave uses {"error": {"detail": …}}).
    private static func errorMessage(in data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let error = object["error"] as? [String: Any] {
            return (error["message"] as? String) ?? (error["detail"] as? String)
        }
        return (object["message"] as? String) ?? (object["detail"] as? String)
    }
}
