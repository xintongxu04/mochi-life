import SwiftUI

/// Mochi's animated sprite, 132 × 126 pt (the frames' 352:336 aspect), with a soft ground shadow
/// at her feet. Frames advance at the current state's rate (8 fps, sleeping 4 fps) only while the
/// view is on screen and the app is active. Under Reduce Motion the picture stays still, but the
/// clock keeps running so the sleep rules and sequence steps still move on.
struct MochiSpriteView: View {
    let animator: MochiAnimator

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var isVisible = false

    static let size = CGSize(width: 132, height: 126)
    /// The feet's baseline: 320 of 336 px from the top of every frame.
    static let baseline = size.height * 320 / 336

    private var isRunning: Bool { isVisible && scenePhase == .active }

    private struct ClockKey: Equatable {
        var isRunning: Bool
        var fps: Double
    }

    var body: some View {
        ZStack(alignment: .top) {
            Ellipse()
                .fill(Color.black.opacity(colorScheme == .dark ? 0.55 : 0.18))
                .frame(width: Self.size.width * 0.5, height: 9)
                .blur(radius: 3)
                .offset(y: Self.baseline - 4.5)
            Group {
                if let image = animator.currentImage {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.high)
                } else {
                    Color.clear
                }
            }
            .frame(width: Self.size.width, height: Self.size.height)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .onAppear {
            isVisible = true
            animator.reduceMotion = reduceMotion
        }
        .onDisappear { isVisible = false }
        .onChange(of: reduceMotion) { _, newValue in animator.reduceMotion = newValue }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { animator.appBecameActive() }
        }
        // The frame clock: lives and dies with the view, paused when hidden or inactive, and
        // restarted at the new rate when the state's frame rate changes.
        .task(id: ClockKey(isRunning: isRunning, fps: animator.state.fps)) {
            guard isRunning else { return }
            let interval = Duration.seconds(1 / animator.state.fps)
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                animator.advance()
            }
        }
    }
}
