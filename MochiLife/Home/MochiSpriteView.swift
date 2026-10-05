import SwiftUI

/// Mochi's animated sprite, 176 × 168 pt. Frames advance 8 times a second only while the view
/// is on screen and the app is active; under Reduce Motion it's a still picture.
struct MochiSpriteView: View {
    let animator: MochiAnimator

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    static let size = CGSize(width: 176, height: 168)

    private var isRunning: Bool { isVisible && scenePhase == .active && !reduceMotion }

    var body: some View {
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
        .onAppear {
            isVisible = true
            animator.reduceMotion = reduceMotion
        }
        .onDisappear { isVisible = false }
        .onChange(of: reduceMotion) { _, newValue in animator.reduceMotion = newValue }
        // The frame clock: lives and dies with the view, paused when hidden or inactive.
        .task(id: isRunning) {
            guard isRunning else { return }
            let interval = Duration.seconds(1 / MochiState.sitting.fps)
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                animator.advance()
            }
        }
    }
}
