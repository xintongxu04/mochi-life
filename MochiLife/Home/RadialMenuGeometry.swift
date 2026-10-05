import CoreGraphics

/// Where the ring's five buttons go. Pure geometry, no views: the ring is always centred on
/// Mochi; near an edge or corner the buttons fan across the largest free arc instead of the ring
/// moving away from her.
enum RadialMenuGeometry {
    static let startRadius: CGFloat = 118
    static let radiusStep: CGFloat = 8
    static let maximumRadius: CGFloat = 190
    /// The smallest distance between neighbouring buttons' centres.
    static let minimumSpacing: CGFloat = 68
    /// Full-ring layout: 72° steps from the top.
    static let fullRingStart: Double = -90

    struct Placement: Equatable {
        /// Button centres, in the order of the footprints (clockwise: Eat, Play, Settings,
        /// Weight, Profile).
        var points: [CGPoint]
        var radius: CGFloat
    }

    /// - Parameters:
    ///   - center: Mochi's centre. The ring is always centred here.
    ///   - bounds: where buttons and captions may go (the screen inset by the safe area + 8 pt,
    ///     below the navigation bar).
    ///   - footprints: each button's circle plus caption, relative to the button's centre.
    ///   - avoiding: Mochi's rectangle; no footprint may overlap it.
    static func place(center: CGPoint, bounds: CGRect, footprints: [CGRect], avoiding sprite: CGRect) -> Placement {
        let count = footprints.count
        guard count > 0 else { return Placement(points: [], radius: startRadius) }
        // Validity is tested with the largest footprint so any button fits at a valid angle.
        let widest = footprints.reduce(footprints[0]) { $0.union($1) }
        var best: (placement: Placement, spacing: CGFloat, overlaps: Bool)?

        var radius = startRadius
        while radius <= maximumRadius {
            let valid = (0..<360).map { degrees in
                let frame = widest.offsetBy(point(center, radius, Double(degrees)))
                return bounds.contains(frame) && !frame.intersects(sprite)
            }
            if let angles = angles(for: valid, count: count) {
                let points = angles.map { point(center, radius, $0) }
                let placement = Placement(points: points, radius: radius)
                let spacing = minimumNeighbourSpacing(points, isFullRing: valid.allSatisfy { $0 })
                let overlaps = hasOverlaps(points, footprints)
                if spacing >= minimumSpacing && !overlaps { return placement }
                if best == nil || isBetter((spacing, overlaps), than: (best!.spacing, best!.overlaps)) {
                    best = (placement, spacing, overlaps)
                }
            }
            radius += radiusStep
        }
        if let best { return best.placement }
        // Nowhere fits at any radius (not possible on an iPhone screen): the full ring.
        return Placement(points: (0..<count).map { point(center, startRadius, fullRingStart + 360 * Double($0) / Double(count)) },
                         radius: startRadius)
    }

    /// Five angles: the full ring at 72° steps if every angle is valid, else spread evenly over
    /// the largest contiguous valid arc (circular), first and last on its ends, clockwise.
    static func angles(for valid: [Bool], count: Int) -> [Double]? {
        if valid.allSatisfy({ $0 }) {
            return (0..<count).map { fullRingStart + 360 * Double($0) / Double(count) }
        }
        guard let arc = largestArc(valid) else { return nil }
        let length = Double(arc.length - 1)
        return (0..<count).map { index in
            Double(arc.start) + (count > 1 ? length * Double(index) / Double(count - 1) : 0)
        }
    }

    /// The longest run of valid angles, wrapping past 359°. Nil if none is valid.
    static func largestArc(_ valid: [Bool]) -> (start: Int, length: Int)? {
        let n = valid.count
        guard let firstInvalid = valid.firstIndex(of: false) else { return (0, n) }
        var best: (start: Int, length: Int)?
        var runStart: Int?
        // Walk once around, starting just after an invalid angle, so runs never split at 0°.
        for step in 1...n {
            let index = (firstInvalid + step) % n
            if valid[index] {
                if runStart == nil { runStart = firstInvalid + step }
            } else if let start = runStart {
                let length = firstInvalid + step - start
                if best == nil || length > best!.length { best = (start % n, length) }
                runStart = nil
            }
        }
        return best
    }

    // MARK: - Helpers

    private static func point(_ center: CGPoint, _ radius: CGFloat, _ degrees: Double) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(x: center.x + radius * cos(radians), y: center.y + radius * sin(radians))
    }

    private static func minimumNeighbourSpacing(_ points: [CGPoint], isFullRing: Bool) -> CGFloat {
        guard points.count > 1 else { return .infinity }
        var pairs = zip(points, points.dropFirst()).map { ($0, $1) }
        if isFullRing, let first = points.first, let last = points.last { pairs.append((last, first)) }
        return pairs.map { hypot($0.0.x - $0.1.x, $0.0.y - $0.1.y) }.min() ?? .infinity
    }

    private static func hasOverlaps(_ points: [CGPoint], _ footprints: [CGRect]) -> Bool {
        let frames = zip(points, footprints).map { $1.offsetBy($0) }
        for i in frames.indices {
            for j in frames.indices where j > i && frames[i].intersects(frames[j]) {
                return true
            }
        }
        return false
    }

    /// No overlaps beats overlaps; then wider spacing.
    private static func isBetter(_ candidate: (CGFloat, Bool), than current: (CGFloat, Bool)) -> Bool {
        if candidate.1 != current.1 { return !candidate.1 }
        return candidate.0 > current.0
    }
}

private extension CGRect {
    func offsetBy(_ point: CGPoint) -> CGRect { offsetBy(dx: point.x, dy: point.y) }
}
