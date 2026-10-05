import CoreGraphics

/// Where the ring's five buttons go, from a few fixed presets. Pure geometry, no views. The ring
/// is always centred on Mochi; within a preset the buttons' offsets from her centre are
/// constants, so small moves never shuffle them.
///
/// Angles are in degrees: 0 = right, −90 = up, positive = clockwise (screen coordinates). The
/// actions are always laid out in clockwise order: Eat, Play, Settings, Weight, Profile.
enum RadialMenuGeometry {
    static let radius: CGFloat = 96
    static let buttonDiameter: CGFloat = 48
    /// An edge becomes "near" when Mochi's centre is closer to it than this…
    static let nearDistance: CGFloat = radius + 28
    /// …and stops being near only once she's farther than this (hysteresis).
    static let farDistance: CGFloat = radius + 52
    static let fullStep: Double = 72
    static let edgeSpan: Double = 180
    static let cornerSpan: Double = 140
    /// Narrowing step when a preset doesn't fit.
    static let spanStep: Double = 10
    /// Neighbouring centres closer than this make the radius grow instead.
    static let minimumSpacing: CGFloat = 56
    static let radiusStep: CGFloat = 4
    static let maximumRadius: CGFloat = 160

    struct Edges: OptionSet, Sendable, Equatable {
        let rawValue: Int
        static let left = Edges(rawValue: 1)
        static let right = Edges(rawValue: 2)
        static let top = Edges(rawValue: 4)
        static let bottom = Edges(rawValue: 8)
    }

    enum Preset: Equatable {
        case full
        case edge(Edges)
        case corner(Edges)
    }

    struct Placement: Equatable {
        /// Button centres in clockwise action order.
        var points: [CGPoint]
        var radius: CGFloat
        var preset: Preset
    }

    /// The edges Mochi is near, with hysteresis: an edge joins below `nearDistance` and leaves
    /// only above `farDistance`, so the preset doesn't flip on small moves.
    static func nearEdges(center: CGPoint, bounds: CGRect, previous: Edges) -> Edges {
        let distances: [(Edges, CGFloat)] = [
            (.left, center.x - bounds.minX), (.right, bounds.maxX - center.x),
            (.top, center.y - bounds.minY), (.bottom, bounds.maxY - center.y),
        ]
        var edges: Edges = []
        for (edge, distance) in distances {
            let threshold = previous.contains(edge) ? farDistance : nearDistance
            if distance < threshold { edges.insert(edge) }
        }
        return edges
    }

    /// The preset for a set of near edges. Two opposite edges (not possible in iPhone portrait)
    /// count as the nearer one.
    static func preset(for edges: Edges, center: CGPoint, bounds: CGRect) -> Preset {
        var edges = edges
        if edges.contains([.left, .right]) {
            edges.remove(center.x - bounds.minX <= bounds.maxX - center.x ? .right : .left)
        }
        if edges.contains([.top, .bottom]) {
            edges.remove(center.y - bounds.minY <= bounds.maxY - center.y ? .bottom : .top)
        }
        switch edges.rawValue.nonzeroBitCount {
        case 0: return .full
        case 1: return .edge(edges)
        default: return .corner(edges)
        }
    }

    /// The five button centres for `edges` (from `nearEdges`), checked once: if a fan doesn't
    /// fit inside `bounds`, its span narrows in 10° steps, and only when neighbours would be
    /// closer than 56 pt does the radius grow, in 4 pt steps. The ring never moves off Mochi.
    static func place(center: CGPoint, bounds: CGRect, nearEdges edges: Edges, count: Int = 5) -> Placement {
        let preset = preset(for: edges, center: center, bounds: bounds)
        guard case let (middle?, initialSpan) = fan(for: preset) else {
            // Full ring: 72° steps from the top.
            let angles = (0..<count).map { -90 + fullStep * Double($0) }
            return Placement(points: angles.map { point(center, radius, $0) }, radius: radius, preset: preset)
        }
        var span = initialSpan
        var currentRadius = radius
        while true {
            let angles = fanAngles(middle: middle, span: span, count: count)
            let points = angles.map { point(center, currentRadius, $0) }
            let fits = points.allSatisfy { bounds.contains(circle(at: $0)) }
            if fits || currentRadius >= maximumRadius { return Placement(points: points, radius: currentRadius, preset: preset) }
            let narrower = span - spanStep
            if narrower > 0, chord(currentRadius, narrower / Double(count - 1)) >= minimumSpacing {
                span = narrower
            } else {
                currentRadius += radiusStep
            }
        }
    }

    /// The direction a fan opens (its middle angle) and its span; nil middle for the full ring.
    static func fan(for preset: Preset) -> (Double?, Double) {
        switch preset {
        case .full:
            return (nil, 360)
        case let .edge(edge):
            let middle: Double = switch edge {
            case .left: 0
            case .right: 180
            case .top: 90
            default: -90
            }
            return (middle, edgeSpan)
        case let .corner(edges):
            let middle: Double = switch (edges.contains(.top), edges.contains(.left)) {
            case (true, true): 45
            case (true, false): 135
            case (false, true): -45
            case (false, false): -135
            }
            return (middle, cornerSpan)
        }
    }

    /// Evenly spaced angles across the fan, in clockwise order (increasing angle).
    static func fanAngles(middle: Double, span: Double, count: Int) -> [Double] {
        let step = count > 1 ? span / Double(count - 1) : 0
        return (0..<count).map { middle - span / 2 + step * Double($0) }
    }

    // MARK: - Helpers

    private static func point(_ center: CGPoint, _ radius: CGFloat, _ degrees: Double) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(x: center.x + radius * cos(radians), y: center.y + radius * sin(radians))
    }

    private static func circle(at point: CGPoint) -> CGRect {
        CGRect(x: point.x - buttonDiameter / 2, y: point.y - buttonDiameter / 2, width: buttonDiameter, height: buttonDiameter)
    }

    /// Distance between neighbouring centres `stepDegrees` apart on a circle of `radius`.
    private static func chord(_ radius: CGFloat, _ stepDegrees: Double) -> CGFloat {
        2 * radius * CGFloat(sin(stepDegrees * .pi / 360))
    }
}
