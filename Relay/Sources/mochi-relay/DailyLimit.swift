import Foundation

/// The daily lookup count, persisted with the date in state.json.
struct DailyLimit {
    private struct State: Codable {
        var date: String
        var lookups: Int
    }

    private static var today: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: .now)
    }

    static func todayCount() -> Int {
        guard let data = try? Data(contentsOf: Paths.stateFile),
              let state = try? JSONDecoder().decode(State.self, from: data),
              state.date == today
        else { return 0 }
        return state.lookups
    }

    /// Counts one lookup if today's count is under `cap`. Returns false when the cap is reached.
    static func reserve(cap: Int) throws -> Bool {
        let count = todayCount()
        guard count < cap else { return false }
        try Paths.ensureDirectory(Paths.supportDirectory)
        let data = try JSONEncoder().encode(State(date: today, lookups: count + 1))
        try data.write(to: Paths.stateFile, options: .atomic)
        return true
    }
}

/// An exclusive, non-blocking file lock so only one lookup runs at a time on this Mac, even
/// when `mochi-relay test` runs while the relay is serving the phone.
final class LookupLock {
    private let descriptor: Int32

    init?() {
        try? Paths.ensureDirectory(Paths.supportDirectory)
        let fd = open(Paths.lookupLockFile.path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { return nil }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            return nil
        }
        descriptor = fd
    }

    deinit {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}
