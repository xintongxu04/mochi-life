import Observation
import UIKit

/// Drives Mochi's sprite. `.sitting` loops while idle; every 20–40 seconds of visible idle time
/// she stretches once. `play(_:loops:)` runs a one-shot (eating, playing…) for whole 16-frame
/// loops and then returns to sitting; a new one-shot replaces the current one.
///
/// The clock is `MochiSpriteView`'s task, which calls `advance()` 8 times a second only while the
/// sprite is visible and the app is active, so nothing runs in the background.
///
/// Memory: only the sitting frames and the current state's frames are kept decoded (2 × 16).
@Observable
@MainActor
final class MochiAnimator {
    private(set) var state = MochiState.sitting
    private(set) var frameIndex = 0
    /// Set by the view from the Reduce Motion setting.
    var reduceMotion = false {
        didSet { if reduceMotion != oldValue { returnToSitting() } }
    }

    /// Frames left in the current one-shot; nil while idle.
    private var remainingFrames: Int?
    /// Idle ticks until the next stretch.
    private var ticksUntilStretch = 0
    @ObservationIgnored private var frames: [MochiState: [UIImage]] = [:]
    @ObservationIgnored private var reducedMotionReturn: Task<Void, Never>?

    init() {
        armIdleStretch()
    }

    /// Plays `state` for `loops` full loops, then returns to sitting. Under Reduce Motion, shows
    /// that state's frame 08 for about 1.5 seconds instead.
    func play(_ state: MochiState, loops: Int) {
        reducedMotionReturn?.cancel()
        setState(state)
        if reduceMotion {
            frameIndex = MochiState.representativeFrame
            remainingFrames = nil
            reducedMotionReturn = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { return }
                self?.returnToSitting()
            }
        } else {
            frameIndex = 0
            remainingFrames = max(1, loops) * state.frameCount
        }
    }

    /// One frame step (1/8 s). Called by the sprite view's clock only while it's visible.
    func advance() {
        guard !reduceMotion else { return }
        if let remaining = remainingFrames {
            if remaining <= 1 {
                returnToSitting()
                return
            }
            remainingFrames = remaining - 1
            frameIndex = (frameIndex + 1) % state.frameCount
            return
        }
        frameIndex = (frameIndex + 1) % state.frameCount
        ticksUntilStretch -= 1
        if ticksUntilStretch <= 0 {
            play(.stretching, loops: 1)
        }
    }

    /// The frame to draw now.
    var currentImage: UIImage? {
        let index = reduceMotion && state == .sitting ? 0 : frameIndex
        return images(for: state)[safe: index]
    }

    // MARK: - Private

    private func returnToSitting() {
        reducedMotionReturn?.cancel()
        reducedMotionReturn = nil
        remainingFrames = nil
        setState(.sitting)
        frameIndex = 0
        armIdleStretch()
    }

    private func setState(_ newState: MochiState) {
        state = newState
        // Keep sitting plus the active state decoded; drop the others.
        for cached in frames.keys where cached != .sitting && cached != newState {
            frames[cached] = nil
        }
    }

    private func armIdleStretch() {
        ticksUntilStretch = Int.random(in: 20...40) * Int(MochiState.sitting.fps)
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

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
