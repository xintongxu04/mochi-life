import Foundation
import RelayCore

/// Serializes lookups: at most one Claude invocation at a time (also across processes, through
/// a file lock). Other requests get a "busy" error rather than waiting.
actor LookupService {
    static let relayVersion = "1.0.0"

    private let config: RelayConfig
    private var isBusy = false

    init(config: RelayConfig) {
        self.config = config
    }

    /// Runs one lookup, reporting progress, and returns the final result envelope.
    func lookup(id: UUID, query: LookupQuery,
                progress: @escaping @Sendable (RelayResponse.Stage) async -> Void) async -> RelayResponse {
        if let error = query.validationError() {
            return .failure(id: id, error)
        }
        guard !isBusy, let lock = LookupLock() else {
            return .failure(id: id, RelayError(code: .busy, message: "Another lookup is running. Try again in a minute."))
        }
        defer { withExtendedLifetime(lock) {} }
        do {
            guard try DailyLimit.reserve(cap: config.dailyCap) else {
                RelayLog.shared.info("request=\(id) status=rate_limited cap=\(config.dailyCap)")
                return .failure(id: id, RelayError(code: .rateLimited, message: "Today's limit of \(config.dailyCap) lookups is used up."))
            }
        } catch {
            RelayLog.shared.error("request=\(id) couldn't update the daily count: \(error.localizedDescription)")
        }

        isBusy = true
        defer { isBusy = false }
        let started = ContinuousClock.now
        await progress(.queued)
        await progress(.searching)

        let outcome: LookupOutcome
        do {
            let (result, usage) = try await ClaudeRunner(config: config).lookup(query)
            outcome = result
            RelayLog.shared.info("request=\(id) claude=done status=\(result.status.rawValue) \(usage.logDescription)")
        } catch let failure as ClaudeFailure {
            log(id: id, started: started, status: failure.error.code.rawValue, extra: failure.usage.logDescription)
            return .failure(id: id, failure.error)
        } catch let error as RelayError {
            log(id: id, started: started, status: error.code.rawValue)
            return .failure(id: id, error)
        } catch {
            log(id: id, started: started, status: "claude_failed")
            return .failure(id: id, RelayError(code: .claudeFailed, message: "The lookup failed."))
        }

        guard var food = outcome.food else {
            log(id: id, started: started, status: "not_found")
            return .result(id: id, food: nil)
        }
        if let imageURL = food.imageURL {
            await progress(.fetchingImage)
            do {
                food.thumbnailJPEGBase64 = try await Thumbnail.make(from: imageURL)
            } catch {
                // Non-fatal: return the food without a thumbnail.
                food.notes.append("Thumbnail not included: \(error).")
            }
        }
        log(id: id, started: started, status: "ok", extra: "thumbnail=\(food.thumbnailJPEGBase64 != nil)")
        return .result(id: id, food: food)
    }

    private func log(id: UUID, started: ContinuousClock.Instant, status: String, extra: String = "") {
        let elapsed = ContinuousClock.now - started
        let milliseconds = elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000
        RelayLog.shared.info("request=\(id) status=\(status) duration_ms=\(milliseconds) \(extra)")
    }
}
