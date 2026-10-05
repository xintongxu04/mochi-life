import SwiftUI

/// Mochi as a "desktop pet" floating above the Calories screen.
///
/// **Coordinate space:** a full-screen root layer (`ContentView`, above the `NavigationStack`,
/// `.ignoresSafeArea()`), so her position is in screen points and nothing that happens while the
/// list scrolls (the large title collapsing, the bar or safe area changing) can move her. Her
/// position is an absolute point while the app runs. It's converted to and from the saved
/// fractions (0…1 of the allowed range) only when she's first placed, when a drag ends, and if
/// the screen size really changes.
///
/// **Clamp region:** the screen inset 8 pt, with the side and bottom safe-area insets, and a fixed
/// top limit at the bottom of the expanded navigation bar (`MochiHome.restingTopLimit`, measured
/// at rest; it doesn't follow the bar as it collapses).
///
/// Only her own rectangle takes touches. Drag (8 pt or more) moves her 1:1; a tap toggles the
/// ring. Dropped outside the region, she springs back in; otherwise she stays where dropped.
struct FloatingMochiView: View {
    let home: MochiHome

    /// Fractions of the allowed range; −1 means "never moved" (use the default corner).
    @AppStorage("mochi.position.x") private var storedX = -1.0
    @AppStorage("mochi.position.y") private var storedY = -1.0
    /// Her top-left corner in screen points, while the screen is live.
    @State private var origin: CGPoint?
    /// The screen size `origin` was placed for.
    @State private var placedScreenSize: CGSize?
    @State private var translation = CGSize.zero
    @State private var isDragging = false

    static let inset: CGFloat = 8
    static let defaultEdgeDistance: CGFloat = 16
    static let draggingScale: CGFloat = 1.06

    var body: some View {
        GeometryReader { proxy in
            let region = Self.region(screen: proxy.size, safeArea: proxy.safeAreaInsets, topLimit: home.restingTopLimit)
            ZStack(alignment: .topLeading) {
                if let origin {
                    MochiSpriteView(animator: home.animator)
                        // Only the lift is animated; her position never is (except the release spring).
                        .animation(.spring(duration: 0.2)) { content in
                            content
                                .scaleEffect(isDragging ? Self.draggingScale : 1)
                                .shadow(color: .black.opacity(isDragging ? 0.25 : 0), radius: 10, y: 6)
                        }
                        .contentShape(Rectangle())
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { home.spriteFrame = $0 }
                        .gesture(drag(from: origin, region: region).exclusively(before: tap))
                        .accessibilityElement()
                        .accessibilityLabel("Mochi")
                        .accessibilityHint("Opens actions")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { home.spriteTapped() }
                        .offset(x: origin.x + translation.width, y: origin.y + translation.height)
                        .transaction { $0.animation = isSettling ? $0.animation : nil }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            // Placed once the resting top limit is known, and again only if the screen size changes.
            .onChange(of: PlacementKey(screen: proxy.size, hasTopLimit: home.restingTopLimit > 0), initial: true) { _, key in
                guard key.hasTopLimit, placedScreenSize != key.screen else { return }
                placedScreenSize = key.screen
                origin = Self.origin(storedX: storedX, storedY: storedY, in: region)
            }
        }
        .ignoresSafeArea()
        .sensoryFeedback(.impact(weight: .light), trigger: isDragging) { _, dragging in dragging }
    }

    /// True only during the spring-back after a release outside the region.
    @State private var isSettling = false

    private struct PlacementKey: Equatable {
        var screen: CGSize
        var hasTopLimit: Bool
    }

    private var tap: some Gesture {
        TapGesture().onEnded { home.spriteTapped() }
    }

    private func drag(from origin: CGPoint, region: CGRect) -> some Gesture {
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
                let clamped = Self.clamp(dropped, in: region)
                (storedX, storedY) = Self.fractions(of: clamped, in: region)
                if clamped == dropped {
                    self.origin = clamped
                    translation = .zero
                } else {
                    isSettling = true
                    withAnimation(.spring(duration: 0.35, bounce: 0.3)) {
                        self.origin = clamped
                        translation = .zero
                    } completion: {
                        isSettling = false
                    }
                }
                isDragging = false
            }
    }

    // MARK: - Position

    /// Where her top-left corner may go, in screen points.
    static func region(screen: CGSize, safeArea: EdgeInsets, topLimit: CGFloat) -> CGRect {
        let size = MochiSpriteView.size
        let minX = safeArea.leading + inset
        let minY = max(topLimit, safeArea.top) + inset
        let maxX = max(minX, screen.width - safeArea.trailing - inset - size.width)
        let maxY = max(minY, screen.height - safeArea.bottom - inset - size.height)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func clamp(_ point: CGPoint, in region: CGRect) -> CGPoint {
        CGPoint(x: min(max(point.x, region.minX), region.maxX), y: min(max(point.y, region.minY), region.maxY))
    }

    static func fractions(of point: CGPoint, in region: CGRect) -> (Double, Double) {
        func fraction(_ value: CGFloat, _ start: CGFloat, _ span: CGFloat) -> Double {
            span > 0 ? Double((value - start) / span) : 0
        }
        return (fraction(point.x, region.minX, region.width), fraction(point.y, region.minY, region.height))
    }

    /// The saved position, or bottom-trailing 16 pt from the safe edges if she was never moved.
    static func origin(storedX: Double, storedY: Double, in region: CGRect) -> CGPoint {
        guard storedX >= 0, storedY >= 0 else {
            let edgeShift = defaultEdgeDistance - inset
            return clamp(CGPoint(x: region.maxX - edgeShift, y: region.maxY - edgeShift), in: region)
        }
        return CGPoint(x: region.minX + CGFloat(min(max(storedX, 0), 1)) * region.width,
                       y: region.minY + CGFloat(min(max(storedY, 0), 1)) * region.height)
    }
}
