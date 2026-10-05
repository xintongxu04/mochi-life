# Mochi Relay

A small Mac program that lets the Mochi Life iPhone app ask this Mac to look up a cat food
with Claude, over your home network. The phone sends a food name (or text read from the label),
the Mac runs Claude Code to find the manufacturer's product page, and sends back the calories,
ingredients, guaranteed analysis and a small photo, in the same shape as the app's built-in
food data.

The iPhone side isn't built yet; this is the Mac side only.

**Each lookup uses your Claude plan's allowance** (or your API key, if you switch to that).
There's a daily cap of 40 lookups by default.

## Build

```sh
cd Relay
swift build -c release
```

The program is then at `.build/release/mochi-relay`.

## Commands

| Command | What it does |
|---|---|
| `mochi-relay test "<query>"` | Runs one lookup on this Mac (no network) and prints the food as JSON. Uses your Claude plan. |
| `mochi-relay run` | Starts the relay in this Terminal window. Stop it with Control-C. |
| `mochi-relay pair` | Shows the pairing code, as text and as a QR code. |
| `mochi-relay pair --rotate` | Replaces the pairing code. Phones paired before must pair again. |
| `mochi-relay status` | Shows settings, whether it's running in the background, today's lookups, and the Claude Code it uses. |
| `mochi-relay install-agent` | Copies the program to `~/.local/bin/mochi-relay` and starts it in the background, now and whenever you log in. |
| `mochi-relay uninstall-agent` | Stops the background relay and removes it from login. |

The first time the relay reads the pairing code, macOS may ask whether `mochi-relay` can use
your Keychain. Choose **Always Allow**. (After rebuilding the program you may be asked again.)

## Files it creates

| Where | What |
|---|---|
| Keychain, "com.xintongxu.MochiRelay" / "psk" | The pairing code (32 random bytes). Only ever stored here. |
| Keychain, "com.xintongxu.MochiRelay" / "anthropic_api_key" | Only if you use API-key mode; you add it yourself (see below). |
| `~/Library/Application Support/MochiRelay/config.json` | Settings: `port` (0 = automatic), `daily_cap`, `auth_mode` (`subscription` or `api_key`), `claude_path`, `timeout_seconds`. No secrets. |
| `~/Library/Application Support/MochiRelay/state.json` | Today's date and lookup count. |
| `~/Library/Application Support/MochiRelay/lookup.lock` | Makes sure only one lookup runs at a time. |
| `~/Library/Logs/MochiRelay/relay.log` (+ `relay.1.log` …) | Request ids, timings, results and Claude's cost figures. Never the food query, label text, pairing code or keys. |
| `~/Library/Logs/MochiRelay/launchd.*.log` | Anything the background agent prints. |
| `~/.local/bin/mochi-relay` | The installed program (from `install-agent`). |
| `~/Library/LaunchAgents/com.xintongxu.MochiRelay.plist` | The background agent (from `install-agent`). |

To use an Anthropic API key instead of your Claude subscription, set `"auth_mode": "api_key"`
in config.json and store the key with
`security add-generic-password -s com.xintongxu.MochiRelay -a anthropic_api_key -w`
(it asks for the key without showing it).

## Uninstall

```sh
mochi-relay uninstall-agent
rm ~/.local/bin/mochi-relay
rm -r "$HOME/Library/Application Support/MochiRelay" "$HOME/Library/Logs/MochiRelay"
security delete-generic-password -s com.xintongxu.MochiRelay -a psk
security delete-generic-password -s com.xintongxu.MochiRelay -a anthropic_api_key   # only if you added one
```

## How it's kept safe

- Only devices that know the pairing code can connect: the connection is encrypted and
  authenticated with TLS using the code as a pre-shared key, and anything else is rejected.
- It only answers devices on your local network (private, link-local and unique-local
  addresses). It doesn't use peer-to-peer Wi-Fi (AWDL).
- Claude runs with only the web search and web page tools. It can't run commands, read or
  write files, or use any connectors, and it works in an empty temporary folder that is
  deleted afterwards.
- Programs are started with argument lists, never through a shell.

See `docs/ARCHITECTURE.md` (section "Mochi Relay") for the protocol and technical details.
