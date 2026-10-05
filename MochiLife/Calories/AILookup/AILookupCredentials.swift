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
              let key = String(data: data, encoding: .utf8), !key.isEmpty
        else { return nil }
        return key
    }

    /// Saves the key, or removes it when `key` is empty. Returns false if the Keychain refused.
    @discardableResult
    static func setKey(_ key: String, for service: AIService) -> Bool {
        let match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: account(service),
        ]
        SecItemDelete(match as CFDictionary)
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
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

/// "Test keys": one minimal request to each service, reporting success or the HTTP status.
enum AIKeyTester {
    static func test(_ service: AIService) async -> String {
        guard let key = AIKeychain.key(for: service) else { return "No key saved" }
        var request: URLRequest
        switch service {
        case .brave:
            request = URLRequest(url: URL(string: "https://api.search.brave.com/res/v1/web/search?q=cat%20food&count=1")!)
            request.setValue(key, forHTTPHeaderField: "X-Subscription-Token")
        case .deepSeek:
            // Listing models checks the key without using any tokens.
            request = URLRequest(url: URL(string: "https://api.deepseek.com/models")!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let session = HTTPCheck.session(timeout: 15)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (_, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            AILog.logger.info("key_test service=\(service.rawValue, privacy: .public) http_status=\(status)")
            switch status {
            case 200..<300: return "Working"
            case 401, 403: return "Key rejected (HTTP \(status))"
            case 402: return "No balance left (HTTP 402)"
            case 429: return "Rate limited (HTTP 429)"
            default: return "HTTP \(status)"
            }
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost].contains(error.code) {
            return "Offline"
        } catch {
            return "Couldn't connect"
        }
    }
}
