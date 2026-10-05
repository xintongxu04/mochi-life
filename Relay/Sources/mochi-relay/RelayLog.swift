import Foundation
import os

/// Logs to the unified log (subsystem com.xintongxu.MochiRelay) and to a rotating text file in
/// ~/Library/Logs/MochiRelay/. Callers must never pass query text, OCR text, the pairing secret
/// or API keys.
final class RelayLog: @unchecked Sendable {
    static let shared = RelayLog()

    private let logger = Logger(subsystem: "com.xintongxu.MochiRelay", category: "relay")
    private let lock = NSLock()
    private let file = Paths.logDirectory.appending(path: "relay.log")
    private let maximumFileSize = 1_000_000
    private let keptFiles = 3
    private let timestamp = ISO8601DateFormatter()

    func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        append("INFO", message)
    }

    func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        append("ERROR", message)
    }

    private func append(_ level: String, _ message: String) {
        lock.lock()
        defer { lock.unlock() }
        do {
            try Paths.ensureDirectory(Paths.logDirectory)
            rotateIfNeeded()
            let line = "\(timestamp.string(from: .now)) \(level) \(message)\n"
            if let handle = try? FileHandle(forWritingTo: file) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(line.utf8))
            } else {
                try Data(line.utf8).write(to: file, options: .atomic)
            }
        } catch {
            logger.error("Couldn't write the log file: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// relay.log → relay.1.log → relay.2.log …, keeping `keptFiles` old files.
    private func rotateIfNeeded() {
        let manager = FileManager.default
        guard let size = (try? manager.attributesOfItem(atPath: file.path))?[.size] as? Int,
              size >= maximumFileSize
        else { return }
        let base = file.deletingPathExtension().lastPathComponent
        let rotated = { (index: Int) in Paths.logDirectory.appending(path: "\(base).\(index).log") }
        try? manager.removeItem(at: rotated(keptFiles))
        for index in stride(from: keptFiles - 1, through: 1, by: -1) {
            try? manager.moveItem(at: rotated(index), to: rotated(index + 1))
        }
        try? manager.moveItem(at: file, to: rotated(1))
    }
}
