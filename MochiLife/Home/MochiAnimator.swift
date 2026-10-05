import Observation
import UIKit

/// Drives Mochi's sprite. Each state runs at its own frame rate (`MochiState.fps`); every change
/// of state happens at a loop boundary (frame 16 → frame 01), except user-triggered sequences,
/// which cut in immediately.
///
/// **Awake schedule:** a rest segment (sitting 3–6 loops, weight 0.6, or loafing 4–8 loops, 0.4),
/// then an activity (playing 4–6 loops, 0.55, or stretching 1–2 loops, 0.45; never the same
/// activity three times in a row), repeated. The scheduler can't pick eating or grooming: its
/// picks come from enums that only contain the rest and activity states.
///
/// **Sleep:** from 23:00 to 07:00 she sleeps instead. In the day she falls asleep after 180 s of
/// visible time with no touch anywhere in the app. Wake triggers (tap, drag, long-press, Play, a
/// logged food) wake her; after a night wake she stays up for a full awake cycle and at least 60 s.
///
/// **Sequences:** queued (state, loops) steps played back to back at loop boundaries, then the
/// schedule resumes with a rest segment. Play: playing × 10. A logged food: eating × 6 then
/// grooming × 3. Petting (long-press): grooming × 3. Waking by tap, drag or Play stretches once
/// first.
///
/// Time only passes while the sprite's clock runs (visible, app active); nothing runs in the
/// background. Memory: only sitting's frames and the current state's are kept decoded.
@Observable
@MainActor
final class MochiAnimator {
    private(set) var state = MochiState.sitting
    private(set) var frameIndex = 0
    /// Set by the view from the Reduce Motion setting.
    var reduceMotion = false {
        didSet { if reduceMotion != oldValue { startRest() } }
    }

    // MARK: Timings and weights

    static let sittingLoops = 3...6
    static let loafingLoops = 4...8
    static let sittingWeight = 0.6
    static let playingLoops = 4...6
    static let stretchingLoops = 1...2
    static let playingWeight = 0.55
    static let playLoops = 10
    static let eatingLoops = 6
    static let groomingLoops = 3
    static let wakeStretchLoops = 1
    static let inactivitySleepSeconds: Double = 180
    static let nightWakeMinimumSeconds: Double = 60
    /// Night is from 23:00 until 07:00 local time.
    static let nightStartHour = 23
    static let nightEndHour = 7
    /// Under Reduce Motion, each sequence step shows one still frame for this long.
    static let reducedMotionStepSeconds = 1.5

    enum SleepReason { case night, inactivity }

    /// What the current state is part of.
    private enum Segment {
        case rest, activity, sleep(SleepReason), sequence
    }

    /// The scheduler's choices. Eating and grooming aren't in either, so the scheduler can never
    /// pick them.
    private enum Rest { case sitting, loafing }
    private enum Activity { case playing, stretching }

    @ObservationIgnored private var segment = Segment.rest
    @ObservationIgnored private var loopsRemaining = 0
    @ObservationIgnored private var queue: [(MochiState, Int)] = []
    @ObservationIgnored private var recentActivities: [Activity] = []
    /// Visible seconds since the last touch anywhere in the app.
    @ObservationIgnored private var inactiveSeconds: Double = 0
    /// Set when woken at night: seconds awake since, and whether a full awake cycle has finished.
    @ObservationIgnored private var nightWake: (seconds: Double, cycleDone: Bool)?
    @ObservationIgnored private var reducedMotionTicks = 0
    @ObservationIgnored private var frames: [MochiState: [UIImage]] = [:]
    /// The clock, replaceable for previews.
    @ObservationIgnored var now: () -> Date = { .now }

    init() {
        if isNight { startSleep(.night) } else { startRest() }
    }

    // MARK: - Triggers

    /// Any touch anywhere in the app: resets the inactivity timer, but doesn't wake her.
    func userTouchedApp() {
        inactiveSeconds = 0
    }

    /// A tap or the start of a drag on Mochi: if she's asleep, she wakes and stretches once.
    func spriteTouched() {
        inactiveSeconds = 0
        guard isSleeping else { return }
        wake()
        startSequence([(.stretching, Self.wakeStretchLoops)])
    }

    /// The Play button: playing × 10 (a stretch first if she was asleep). Replaces any sequence.
    func playWithBall() {
        let wasSleeping = isSleeping
        wake()
        startSequence((wasSleeping ? [(.stretching, Self.wakeStretchLoops)] : []) + [(.playing, Self.playLoops)])
    }

    /// A food was logged: eating × 6, then grooming × 3. A new one restarts from eating.
    func ateFood() {
        wake()
        startSequence([(.eating, Self.eatingLoops), (.grooming, Self.groomingLoops)])
    }

    /// Petting (long-press): grooming × 3. Ignored during a meal. Returns whether she grooms.
    @discardableResult
    func pet() -> Bool {
        if state == .eating, case .sequence = segment { return false }
        wake()
        startSequence([(.grooming, Self.groomingLoops)])
        return true
    }

    /// The app became active: check night and day straight away.
    func appBecameActive() {
        switch segment {
        case .sleep(.night) where !isNight:
            startRest()
        case .rest, .activity:
            if isNight && nightWake == nil { startSleep(.night) }
        default:
            break
        }
    }

    // MARK: - Clock

    /// One frame step at the current state's frame rate. Called by the sprite view's clock only
    /// while it's visible and the app is active.
    func advance() {
        let seconds = 1 / state.fps
        inactiveSeconds += seconds
        nightWake?.seconds += seconds
        if reduceMotion {
            // Still frames; a "loop" is one 1.5 s step for sequences, one second otherwise.
            reducedMotionTicks += 1
            let ticks = Int((isInSequence ? Self.reducedMotionStepSeconds : 1) * state.fps)
            if reducedMotionTicks >= ticks {
                reducedMotionTicks = 0
                loopBoundary()
            }
            return
        }
        frameIndex += 1
        if frameIndex >= state.frameCount {
            frameIndex = 0
            loopBoundary()
        }
    }

    /// The frame to draw now.
    var currentImage: UIImage? {
        let index = reduceMotion ? (isInSequence ? MochiState.representativeFrame : 0) : frameIndex
        let images = images(for: state)
        return images.indices.contains(index) ? images[index] : nil
    }

    // MARK: - Loop boundaries

    private func loopBoundary() {
        switch segment {
        case let .sleep(reason):
            // Night sleep ends in the morning; inactivity sleep lasts until a wake trigger.
            if reason == .night && !isNight { startRest() }
        case .sequence:
            loopsRemaining -= 1
            if reduceMotion { loopsRemaining = 0 }
            guard loopsRemaining <= 0 else { return }
            if queue.isEmpty {
                startRest()
            } else {
                let next = queue.removeFirst()
                play(next.0, loops: next.1)
            }
        case .rest, .activity:
            if let reason = sleepReasonNow() {
                startSleep(reason)
                return
            }
            if reduceMotion { return }
            loopsRemaining -= 1
            guard loopsRemaining <= 0 else { return }
            if case .rest = segment {
                startActivity()
            } else {
                nightWake?.cycleDone = true
                startRest()
            }
        }
    }

    /// Whether the awake schedule should give way to sleep now.
    private func sleepReasonNow() -> SleepReason? {
        if isNight {
            guard let wake = nightWake else { return .night }
            return wake.cycleDone && wake.seconds >= Self.nightWakeMinimumSeconds ? .night : nil
        }
        nightWake = nil
        return inactiveSeconds >= Self.inactivitySleepSeconds ? .inactivity : nil
    }

    // MARK: - Segments

    private func startSequence(_ steps: [(MochiState, Int)]) {
        guard let first = steps.first else { return }
        queue = Array(steps.dropFirst())
        play(first.0, loops: first.1)
    }

    private func play(_ newState: MochiState, loops: Int) {
        segment = .sequence
        setState(newState)
        frameIndex = reduceMotion ? MochiState.representativeFrame : 0
        reducedMotionTicks = 0
        loopsRemaining = max(1, loops)
    }

    private func startRest() {
        queue = []
        segment = .rest
        let rest: Rest = Double.random(in: 0..<1) < Self.sittingWeight ? .sitting : .loafing
        switch rest {
        case .sitting: schedule(.sitting, loops: Int.random(in: Self.sittingLoops))
        case .loafing: schedule(.loafing, loops: Int.random(in: Self.loafingLoops))
        }
        if reduceMotion { setState(.sitting) }
    }

    private func startActivity() {
        segment = .activity
        var activity: Activity = Double.random(in: 0..<1) < Self.playingWeight ? .playing : .stretching
        if recentActivities.count >= 2, recentActivities.suffix(2).allSatisfy({ $0 == activity }) {
            activity = activity == .playing ? .stretching : .playing
        }
        recentActivities = Array((recentActivities + [activity]).suffix(2))
        switch activity {
        case .playing: schedule(.playing, loops: Int.random(in: Self.playingLoops))
        case .stretching: schedule(.stretching, loops: Int.random(in: Self.stretchingLoops))
        }
    }

    private func startSleep(_ reason: SleepReason) {
        queue = []
        segment = .sleep(reason)
        nightWake = nil
        schedule(.sleeping, loops: .max)
    }

    /// A state chosen by the scheduler (never eating or grooming).
    private func schedule(_ newState: MochiState, loops: Int) {
        assert(newState != .eating && newState != .grooming, "The scheduler must never pick eating or grooming")
        setState(newState)
        frameIndex = 0
        reducedMotionTicks = 0
        loopsRemaining = loops
    }

    private func wake() {
        inactiveSeconds = 0
        if isNight { nightWake = (0, false) }
    }

    private var isSleeping: Bool {
        if case .sleep = segment { true } else { false }
    }

    private var isInSequence: Bool {
        if case .sequence = segment { true } else { false }
    }

    private var isNight: Bool {
        let hour = Calendar.current.component(.hour, from: now())
        return hour >= Self.nightStartHour || hour < Self.nightEndHour
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
