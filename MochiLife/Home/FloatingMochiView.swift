import SwiftUI

/// Mochi as a "desktop pet" floating above the Calories screen. Only her own rectangle takes
/// touches; everything else passes through to the list. Drag (8 pt or more) moves her 1:1; a tap
/// toggles the ring of actions. She stays where she's dropped, kept inside the safe area (8 pt
/// inset, below the navigation bar); if dropped outside it she springs back in. Her position is
/// saved as fractions (0…1) of the space available, so it survives launches and size changes.
struct FloatingMochiView: View {
    let home: MochiHome

    /// Fractions of the available space; −1 means "never moved" (use the default corner).
    @AppStorage("mochi.position.x") private var storedX = -1.0
    @AppStorage("mochi.position.y") private var storedY = -1.0
    @State private var translation = CGSize.zero
    @State private var isDragging = false

    static let inset: CGFloat = 8
    static let defaultEdgeDistance: CGFloat = 16
    static let draggingScale: CGFloat = 1.06

    var body: some View {
        GeometryReader { proxy in
            let area = proxy.size
            let origin = Self.origin(storedX: storedX, storedY: storedY, in: area)
            MochiSpriteView(animator: home.animator)
                .scaleEffect(isDragging ? Self.draggingScale : 1)
                .shadow(color: .black.opacity(isDragging ? 0.25 : 0), radius: 10, y: 6)
                .contentShape(Rectangle())
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { home.spriteFrame = $0 }
                .gesture(drag(from: origin, in: area).exclusively(before: tap))
                .accessibilityElement()
                .accessibilityLabel("Mochi")
                .accessibilityHint("Opens actions")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { home.spriteTapped() }
                .offset(x: origin.x + translation.width, y: origin.y + translation.height)
                .animation(.spring(duration: 0.2), value: isDragging)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: isDragging) { _, dragging in dragging }
    }

    private var tap: some Gesture {
        TapGesture().onEnded { home.spriteTapped() }
    }

    private func drag(from origin: CGPoint, in area: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    home.isMenuOpen = false
                }
                translation = value.translation
            }
            .onEnded { value in
                let dropped = CGPoint(x: origin.x + value.translation.width, y: origin.y + value.translation.height)
                let clamped = Self.clamp(dropped, in: area)
                let (x, y) = Self.fractions(of: clamped, in: area)
                if clamped == dropped {
                    storedX = x
                    storedY = y
                    translation = .zero
                } else {
                    withAnimation(.spring(duration: 0.35, bounce: 0.3)) {
                        storedX = x
                        storedY = y
                        translation = .zero
                    }
                }
                isDragging = false
            }
    }

    // MARK: - Position

    /// Allowed top-left corners: the area inset by 8 pt, minus her size.
    static func range(in area: CGSize) -> (x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>) {
        let size = MochiSpriteView.size
        let maxX = max(inset, area.width - inset - size.width)
        let maxY = max(inset, area.height - inset - size.height)
        return (inset...maxX, inset...maxY)
    }

    static func clamp(_ point: CGPoint, in area: CGSize) -> CGPoint {
        let range = range(in: area)
        return CGPoint(x: min(max(point.x, range.x.lowerBound), range.x.upperBound),
                       y: min(max(point.y, range.y.lowerBound), range.y.upperBound))
    }

    static func fractions(of point: CGPoint, in area: CGSize) -> (Double, Double) {
        let range = range(in: area)
        func fraction(_ value: CGFloat, _ range: ClosedRange<CGFloat>) -> Double {
            let span = range.upperBound - range.lowerBound
            return span > 0 ? Double((value - range.lowerBound) / span) : 0
        }
        return (fraction(point.x, range.x), fraction(point.y, range.y))
    }

    /// The saved position, or bottom-trailing 16 pt from the edges if she was never moved.
    static func origin(storedX: Double, storedY: Double, in area: CGSize) -> CGPoint {
        let range = range(in: area)
        guard storedX >= 0, storedY >= 0 else {
            let size = MochiSpriteView.size
            return clamp(CGPoint(x: area.width - defaultEdgeDistance - size.width,
                                 y: area.height - defaultEdgeDistance - size.height), in: area)
        }
        func value(_ fraction: Double, _ range: ClosedRange<CGFloat>) -> CGFloat {
            range.lowerBound + CGFloat(min(max(fraction, 0), 1)) * (range.upperBound - range.lowerBound)
        }
        return CGPoint(x: value(storedX, range.x), y: value(storedY, range.y))
    }
}
