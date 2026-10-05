import Foundation
import RelayCore

let usage = """
Mochi Relay \(LookupService.relayVersion) — cat-food lookups for the Mochi Life app over the local network.

Usage:
  mochi-relay run              Start the relay in the foreground
  mochi-relay pair [--rotate]  Show the pairing code, or replace it with a new one
  mochi-relay test "<query>"   Run one lookup on this Mac (no network) and print the food JSON
  mochi-relay status           Show settings, the background agent, today's lookups and Claude Code
  mochi-relay install-agent    Install to ~/.local/bin and start the relay in the background
  mochi-relay uninstall-agent  Stop and remove the background agent
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("mochi-relay: \(message)\n".utf8))
    exit(1)
}

// The food schema and the Codable types must match before anything else runs.
do {
    try FoodSchema.selfCheck()
} catch {
    fail("the food schema and the Food type have drifted apart: \(error)")
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "run":
    do {
        let config = try RelayConfig.load()
        let secret = try PairingSecret.current()
        let server = try RelayServer(config: config, secret: secret, service: LookupService(config: config))
        server.start()
        RelayLog.shared.info("relay \(LookupService.relayVersion) started auth_mode=\(config.authMode.rawValue) daily_cap=\(config.dailyCap)")
        print("Mochi Relay is running. Press Control-C to stop.")
        while true {
            try await Task.sleep(for: .seconds(3600))
        }
    } catch {
        fail("couldn't start: \(error)")
    }

case "pair":
    do {
        if arguments.dropFirst().first == "--rotate" {
            let secret = try PairingSecret.rotate()
            RelayLog.shared.info("pairing code rotated")
            print("Made a new pairing code. Phones paired with the old code must pair again.\n")
            PairingCode.printPairing(secret: secret)
            LaunchAgent.restartIfLoaded()
        } else {
            PairingCode.printPairing(secret: try PairingSecret.current())
        }
    } catch {
        fail("couldn't read the pairing code from the Keychain: \(error)")
    }

case "prepare":
    // Used by install-agent: makes sure the installed binary can read the pairing secret.
    do {
        _ = try PairingSecret.current()
    } catch {
        fail("\(error)")
    }

case "test":
    let query = arguments.dropFirst().joined(separator: " ")
    guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { fail("give a query, e.g. mochi-relay test \"Tiki Cat After Dark Chicken\"") }
    do {
        let config = try RelayConfig.load()
        let service = LookupService(config: config)
        print("Looking up… (this uses your Claude plan and can take up to \(Int(config.timeoutSeconds)) seconds)")
        let response = await service.lookup(id: UUID(), query: LookupQuery(typedName: query)) { stage in
            print("  \(stage.rawValue)…")
        }
        switch response.status {
        case .ok?:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            print(String(decoding: try encoder.encode(response.food), as: UTF8.self))
        case .notFound?:
            print("No confident match was found.")
            exit(2)
        default:
            fail("\(response.error?.code.rawValue ?? "error"): \(response.error?.message ?? "the lookup failed")")
        }
    } catch {
        fail("\(error)")
    }

case "status":
    do {
        let config = try RelayConfig.load()
        let hasSecret = ((try? Keychain.read(account: Keychain.pskAccount)) ?? nil) != nil
        let claudeVersion = config.claudePath.flatMap { toolOutput($0, ["--version"]) }
        print("""
        Mochi Relay \(LookupService.relayVersion)
        Config:          \(Paths.configFile.path)
          port:          \(config.port == 0 ? "automatic (found through Bonjour)" : String(config.port))
          daily cap:     \(config.dailyCap)
          auth mode:     \(config.authMode.rawValue)
          timeout:       \(Int(config.timeoutSeconds)) seconds
        Background agent: \(LaunchAgent.isLoaded() ? "loaded" : "not loaded")
        Lookups today:   \(DailyLimit.todayCount()) of \(config.dailyCap)
        Pairing code:    \(hasSecret ? "set (in the Keychain)" : "not created yet")
        Claude Code:     \(config.claudePath ?? "not found")
          version:       \(claudeVersion ?? "unknown")
        Logs:            \(Paths.logDirectory.path)
        """)
    } catch {
        fail("\(error)")
    }

case "install-agent":
    do {
        try LaunchAgent.install()
    } catch {
        fail("\(error)")
    }

case "uninstall-agent":
    do {
        try LaunchAgent.uninstall()
    } catch {
        fail("\(error)")
    }

case "-h", "--help", "help", nil:
    print(usage)

default:
    print(usage)
    exit(64)
}
