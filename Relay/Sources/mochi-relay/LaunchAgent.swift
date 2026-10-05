import Foundation

/// The per-user launchd agent that keeps `mochi-relay run` going in the background.
enum LaunchAgent {
    static var domain: String { "gui/\(getuid())" }
    static var serviceTarget: String { "\(domain)/\(Paths.agentLabel)" }

    static func install() throws {
        // 1. Install this binary to ~/.local/bin/mochi-relay.
        try installBinary()

        // 2. Record where claude is (launchd doesn't have the shell's PATH).
        var config = try RelayConfig.load()
        if let found = ClaudeLocator.find() { config.claudePath = found }
        try config.save()
        guard config.claudePath != nil else {
            print("Warning: Claude Code wasn't found. Set claude_path in \(Paths.configFile.path).")
            return
        }

        // 3. Let the installed binary read (or create) the pairing secret now, while you're at
        //    the terminal, so any Keychain permission prompt appears here, not in the background.
        let prepared = try runTool(Paths.installedBinary.path, ["prepare"])
        guard prepared == 0 else {
            throw ToolFailure(description: "The installed relay couldn't read the Keychain. Run `\(Paths.installedBinary.path) pair` and allow access, then try again.")
        }

        // 4. Write the agent and (re)load it.
        try Paths.ensureDirectory(Paths.logDirectory)
        try Paths.ensureDirectory(Paths.agentPlist.deletingLastPathComponent())
        let plist: [String: Any] = [
            "Label": Paths.agentLabel,
            "ProgramArguments": [Paths.installedBinary.path, "run"],
            "RunAtLoad": true,
            "KeepAlive": true,
            "StandardOutPath": Paths.logDirectory.appending(path: "launchd.out.log").path,
            "StandardErrorPath": Paths.logDirectory.appending(path: "launchd.err.log").path,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: Paths.agentPlist, options: .atomic)
        if isLoaded() {
            _ = try runTool("/bin/launchctl", ["bootout", serviceTarget])
        }
        let status = try runTool("/bin/launchctl", ["bootstrap", domain, Paths.agentPlist.path])
        guard status == 0 else {
            throw ToolFailure(description: "launchctl bootstrap failed (status \(status)).")
        }
        print("Installed \(Paths.installedBinary.path)")
        print("Installed and started the agent \(Paths.agentPlist.path)")
    }

    static func uninstall() throws {
        if isLoaded() {
            let status = try runTool("/bin/launchctl", ["bootout", serviceTarget])
            guard status == 0 else {
                throw ToolFailure(description: "launchctl bootout failed (status \(status)).")
            }
        }
        if FileManager.default.fileExists(atPath: Paths.agentPlist.path) {
            try FileManager.default.removeItem(at: Paths.agentPlist)
        }
        print("Stopped and removed the agent.")
        print("Left in place (delete them by hand if you want): \(Paths.installedBinary.path), \(Paths.supportDirectory.path), \(Paths.logDirectory.path), and the Keychain items for \(Keychain.service).")
    }

    static func isLoaded() -> Bool {
        (try? runTool("/bin/launchctl", ["print", serviceTarget], quiet: true)) == 0
    }

    /// Restarts the running agent so it picks up a new pairing secret.
    static func restartIfLoaded() {
        guard isLoaded() else { return }
        _ = try? runTool("/bin/launchctl", ["kickstart", "-k", serviceTarget], quiet: true)
        print("Restarted the background relay with the new code.")
    }

    private static func installBinary() throws {
        guard let current = Bundle.main.executableURL?.resolvingSymlinksInPath() else {
            throw ToolFailure(description: "Couldn't find this program's own file.")
        }
        let destination = Paths.installedBinary
        guard current.path != destination.resolvingSymlinksInPath().path else { return }
        try Paths.ensureDirectory(destination.deletingLastPathComponent())
        let staging = destination.deletingLastPathComponent().appending(path: ".mochi-relay.new")
        try? FileManager.default.removeItem(at: staging)
        try FileManager.default.copyItem(at: current, to: staging)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: staging.path)
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging)
        } else {
            try FileManager.default.moveItem(at: staging, to: destination)
        }
    }
}

struct ToolFailure: Error, CustomStringConvertible {
    var description: String
}

/// Runs a system tool with an argument array (no shell) and returns its exit status.
@discardableResult
func runTool(_ path: String, _ arguments: [String], quiet: Bool = false) throws -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    if quiet {
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
    }
    try process.run()
    process.waitUntilExit()
    return process.terminationStatus
}

/// Runs a tool and returns its trimmed output, or nil if it fails or takes over 10 seconds.
func toolOutput(_ path: String, _ arguments: [String]) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    process.standardInput = FileHandle.nullDevice
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return nil }
    let deadline = Date.now.addingTimeInterval(10)
    while process.isRunning && Date.now < deadline { usleep(50_000) }
    if process.isRunning {
        process.terminate()
        return nil
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}
