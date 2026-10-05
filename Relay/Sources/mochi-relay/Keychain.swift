import Foundation
import Security

/// Generic passwords in the login Keychain, service "com.xintongxu.MochiRelay".
enum Keychain {
    static let service = "com.xintongxu.MochiRelay"
    static let pskAccount = "psk"
    static let apiKeyAccount = "anthropic_api_key"

    struct Failure: Error, CustomStringConvertible {
        var status: OSStatus
        var description: String {
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown error"
            return "Keychain error \(status): \(message)"
        }
    }

    static func read(account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Failure(status: status) }
        return result as? Data
    }

    static func write(_ data: Data, account: String) throws {
        let match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let update = SecItemUpdate(match as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw Failure(status: update) }
        var item = match
        item[kSecValueData as String] = data
        item[kSecAttrLabel as String] = "Mochi Relay \(account)"
        let add = SecItemAdd(item as CFDictionary, nil)
        guard add == errSecSuccess else { throw Failure(status: add) }
    }
}

/// The pairing secret: 32 random bytes kept only in the Keychain.
enum PairingSecret {
    static let length = 32

    /// The current secret, created on first use.
    static func current() throws -> Data {
        if let existing = try Keychain.read(account: Keychain.pskAccount), existing.count == length {
            return existing
        }
        return try rotate()
    }

    /// Replaces the secret with a new random one. Phones paired with the old one stop connecting.
    @discardableResult
    static func rotate() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        guard status == errSecSuccess else { throw Keychain.Failure(status: status) }
        let secret = Data(bytes)
        try Keychain.write(secret, account: Keychain.pskAccount)
        return secret
    }
}
