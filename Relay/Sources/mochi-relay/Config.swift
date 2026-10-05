import Foundation

/// Settings in ~/Library/Application Support/MochiRelay/config.json. Contains no secrets.
struct RelayConfig: Codable, Sendable {
    enum AuthMode: String, Codable, Sendable {
        /// Use the Claude subscription login of this Mac's user.
        case subscription
        /// Run Claude in bare mode with an API key read from the Keychain.
        case apiKey = "api_key"
    }

    /// 0 lets the system choose a port (clients find the relay through Bonjour).
    var port: UInt16 = 0
    var dailyCap: Int = 40
    var authMode: AuthMode = .subscription
    /// Absolute path of the `claude` binary, resolved at install time (launchd has no shell PATH).
    var claudePath: String?
    var timeoutSeconds: Double = 150

    enum CodingKeys: String, CodingKey {
        case port
        case dailyCap = "daily_cap"
        case authMode = "auth_mode"
        case claudePath = "claude_path"
        case timeoutSeconds = "timeout_seconds"
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        port = try container.decodeIfPresent(UInt16.self, forKey: .port) ?? 0
        dailyCap = try container.decodeIfPresent(Int.self, forKey: .dailyCap) ?? 40
        authMode = try container.decodeIfPresent(AuthMode.self, forKey: .authMode) ?? .subscription
        claudePath = try container.decodeIfPresent(String.self, forKey: .claudePath)
        timeoutSeconds = try container.decodeIfPresent(Double.self, forKey: .timeoutSeconds) ?? 150
    }

    /// Reads the config, creating it (with the `claude` path resolved) if it doesn't exist yet.
    static func load() throws -> RelayConfig {
        if let data = try? Data(contentsOf: Paths.configFile) {
            var config = try JSONDecoder().decode(RelayConfig.self, from: data)
            if config.claudePath == nil, let found = ClaudeLocator.find() {
                config.claudePath = found
                try config.save()
            }
            return config
        }
        var config = RelayConfig()
        config.claudePath = ClaudeLocator.find()
        try config.save()
        return config
    }

    func save() throws {
        try Paths.ensureDirectory(Paths.supportDirectory)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(self).write(to: Paths.configFile, options: .atomic)
    }
}

/// Finds the `claude` binary without a shell: the current PATH, then the usual install places.
enum ClaudeLocator {
    static func find() -> String? {
        let pathDirectories = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").map(String.init)
        let home = Paths.home.path
        let candidates = pathDirectories.map { "\($0)/claude" } + [
            "\(home)/.local/bin/claude",
            "\(home)/.claude/local/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ]
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return URL(fileURLWithPath: candidate).resolvingSymlinksInPath().path
        }
        return nil
    }
}
