import Foundation

/// Every file the relay reads or writes. Nothing secret is stored in any of them.
enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let supportDirectory = home.appending(path: "Library/Application Support/MochiRelay", directoryHint: .isDirectory)
    static let configFile = supportDirectory.appending(path: "config.json")
    static let stateFile = supportDirectory.appending(path: "state.json")
    /// Held while a lookup runs, so only one Claude invocation happens at a time across processes.
    static let lookupLockFile = supportDirectory.appending(path: "lookup.lock")
    static let logDirectory = home.appending(path: "Library/Logs/MochiRelay", directoryHint: .isDirectory)
    static let installedBinary = home.appending(path: ".local/bin/mochi-relay")
    static let agentLabel = "com.xintongxu.MochiRelay"
    static let agentPlist = home.appending(path: "Library/LaunchAgents/\(agentLabel).plist")

    static func ensureDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
    }
}
