import Foundation

/// Mochi's sprite animations. Every frame is 352 × 336 px (@2x, so 176 × 168 pt) on a
/// transparent canvas with her feet on the same baseline, so drawing every frame in the same
/// rectangle keeps her from jumping between states.
enum MochiState: String, CaseIterable, Sendable {
    case sitting, eating, playing, stretching

    var frameCount: Int { 16 }
    var fps: Double { 8 }

    /// Asset catalog name of a frame (0-based index), e.g. "Mochi/mochi_sitting_01".
    func imageName(frame index: Int) -> String {
        "Mochi/mochi_\(rawValue)_\(String(format: "%02d", index + 1))"
    }

    /// The single frame shown for this state when Reduce Motion is on (frame 08).
    static let representativeFrame = 7
}
