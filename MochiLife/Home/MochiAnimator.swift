import Observation
import UIKit

/// Drives Mochi's sprite at 8 fps (one loop = 16 frames = 2 s).
///
/// **Autonomous schedule:** a sitting segment of 3–6 loops (6–12 s), then an activity — playing
/// for 4–6 loops (chance 0.6) or stretching for 1–2 loops (0.4), never the same activity three
/// times in a row — then a new sitting segment, and so on. Eating is never picked on its own.
/// Scheduled changes happen only at loop boundaries (frame 16 → frame 01 of the next state).
///
/// **User one-shots:** `play(_:loops:)` (Play button, a logged food) cuts in immediately, runs
/// whole loops, then the schedule resumes with a sitting segment. Playing again restarts it.
///
/// The clock is `MochiSpriteView`'s task, which calls `advance()` only while the sprite is visible
/// and the app is active. Memory: only sitting's frames and the current state's are kept decoded.
@Observable
@MainActor
final class MochiAnimator {
    private(set) var state = MochiState.sitting
    private(set) var frameIndex = 0
    /// Set by the view from the Reduce Motion setting.
    var reduceMotion = false {
        didSet { if reduceMotion != oldValue { startSittingSegment() } }
    }

    static let sittingLoops = 3...6
    static let playingLoops = 4...6
    static let stretchingLoops = 1...2
    static let playingWeight = 0.6

    /// Whole loops left in the current segment (including the one playing).
    @ObservationIgnored private var loopsRemaining = 0
    /// The last two autonomous activities, to avoid a third in a row.
    @ObservationIgnored private var recentActivities: [MochiState] = []
    @ObservationIgnored private var frames: [MochiState: [UIImage]] = [:]
    @ObservationIgnored private var reducedMotionReturn: Task<Void, Never>?

    init() {
        startSittingSegment()
    }

    /// Plays `state` now for `loops` full loops, then resumes the schedule with sitting. Under
    /// Reduce Motion, shows that state's frame 08 for about 1.5 seconds instead.
    func play(_ state: MochiState, loops: Int) {
        reducedMotionReturn?.cancel()
        setState(state)
        if reduceMotion {
            frameIndex = MochiState.representativeFrame
            reducedMotionReturn = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { return }
                self?.startSittingSegment()
            }
        } else {
            frameIndex = 0
            loopsRemaining = max(1, loops)
        }
    }

    /// One frame step (1/8 s). Called by the sprite view's clock only while it's visible.
    func advance() {
        guard !reduceMotion else { return }
        guard frameIndex + 1 >= state.frameCount else {
            frameIndex += 1
            return
        }
        // Loop boundary.
        frameIndex = 0
        loopsRemaining -= 1
        guard loopsRemaining <= 0 else { return }
        if state == .sitting {
            startActivity(Self.nextActivity(after: recentActivities, random: Double.random(in: 0..<1)))
        } else {
            startSittingSegment()
        }
    }

    /// The frame to draw now.
    var currentImage: UIImage? {
        let index = reduceMotion && state == .sitting ? 0 : frameIndex
        let images = images(for: state)
        return images.indices.contains(index) ? images[index] : nil
    }

    /// The next autonomous activity: playing with probability 0.6, else stretching, but never a
    /// third of the same in a row.
    static func nextActivity(after recent: [MochiState], random: Double) -> MochiState {
        var pick: MochiState = random < playingWeight ? .playing : .stretching
        if recent.count >= 2, recent.suffix(2).allSatisfy({ $0 == pick }) {
            pick = pick == .playing ? .stretching : .playing
        }
        return pick
    }

    // MARK: - Private

    private func startActivity(_ activity: MochiState) {
        recentActivities = Array((recentActivities + [activity]).suffix(2))
        setState(activity)
        frameIndex = 0
        loopsRemaining = Int.random(in: activity == .playing ? Self.playingLoops : Self.stretchingLoops)
    }

    private func startSittingSegment() {
        reducedMotionReturn?.cancel()
        reducedMotionReturn = nil
        setState(.sitting)
        frameIndex = 0
        loopsRemaining = Int.random(in: Self.sittingLoops)
    }

    private func setState(_ newState: MochiState) {
        state = newState
        // Keep sitting plus the active state decoded; drop the others.
        for cached in frames.keys where cached != .sitting && cached != newState {
            frames[cached] = nil
        }
    }

    private func images(for state: MochiState) -> [UIImage] {
        if let cached = frames[state] { return cached }
        let loaded = (0..<state.frameCount).compactMap { index in
            UIImage(named: state.imageName(frame: index)).map { $0.preparingForDisplay() ?? $0 }
        }
        frames[state] = loaded
        return loaded
    }
}
