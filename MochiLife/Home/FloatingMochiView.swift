import SwiftUI

/// Mochi as a "desktop pet" floating above the Calories screen.
///
/// **Coordinate space:** a full-screen root layer (`ContentView`, above the `NavigationStack`,
/// `.ignoresSafeArea()`), so her position is in screen points and nothing that happens while the
/// list scrolls (the large title collapsing, the bar or safe area changing) can move her.
///
/// **Drag area:** the screen inset by the safe area + 8 pt at the sides and bottom; the top is
/// just below the toolbar button row (`MochiHome.topLimit`: the window's top safe area + the
/// 44 pt inline bar + 4 pt), a constant. She may sit over the large title, the summary card and
/// the list.
///
/// **Saved position:** her top-left corner in screen points. When she's placed (launch, or a real
/// screen size change) it's used as is, and clamped only if it now falls outside the area.
/// Positions saved by older versions as fractions of the area are converted once.
///
/// Only her own rectangle takes touches. Drag (8 pt or more) moves her 1:1; a tap toggles the
/// ring. Dropped outside the region, she springs back in; otherwise she stays where dropped.
struct FloatingMochiView: View {
    let home: MochiHome

    /// Her top-left corner in screen points; −1 means "not saved".
    @AppStorage("mochi.origin.x") private var savedX = -1.0
    @AppStorage("mochi.origin.y") private var savedY = -1.0
    /// Older versions saved fractions (0…1) of the area; read once to convert.
    @AppStorage("mochi.position.x") private var legacyFractionX = -1.0
    @AppStorage("mochi.position.y") private var legacyFractionY = -1.0
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
            let region = Self.region(screen: proxy.size, safeArea: proxy.safeAreaInsets)
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
            // Placed when the screen size is known, and again only if it really changes.
            .onChange(of: proxy.size, initial: true) { _, screen in
                guard screen != .zero, placedScreenSize != screen else { return }
                placedScreenSize = screen
                place(in: region)
            }
        }
        .ignoresSafeArea()
        .sensoryFeedback(.impact(weight: .light), trigger: isDragging) { _, dragging in dragging }
    }

    /// True only during the spring-back after a release outside the region.
    @State private var isSettling = false

    /// Her saved point, clamped only if it's now outside the area; else the converted older
    /// fractions; else the default corner.
    private func place(in region: CGRect) {
        let point: CGPoint
        if savedX >= 0, savedY >= 0 {
            point = CGPoint(x: savedX, y: savedY)
        } else if legacyFractionX >= 0, legacyFractionY >= 0 {
            point = CGPoint(x: region.minX + CGFloat(min(max(legacyFractionX, 0), 1)) * region.width,
                            y: region.minY + CGFloat(min(max(legacyFractionY, 0), 1)) * region.height)
        } else {
            point = Self.defaultOrigin(in: region)
        }
        let placed = region.contains(point) ? point : Self.clamp(point, in: region)
        origin = placed
        (savedX, savedY) = (Double(placed.x), Double(placed.y))
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
                (savedX, savedY) = (Double(clamped.x), Double(clamped.y))
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
    static func region(screen: CGSize, safeArea: EdgeInsets) -> CGRect {
        let size = MochiSpriteView.size
        let minX = safeArea.leading + inset
        let minY = MochiHome.topLimit(safeAreaTop: safeArea.top)
        let maxX = max(minX, screen.width - safeArea.trailing - inset - size.width)
        let maxY = max(minY, screen.height - safeArea.bottom - inset - size.height)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func clamp(_ point: CGPoint, in region: CGRect) -> CGPoint {
        CGPoint(x: min(max(point.x, region.minX), region.maxX), y: min(max(point.y, region.minY), region.maxY))
    }

    /// Bottom-trailing, 16 pt from the safe edges.
    static func defaultOrigin(in region: CGRect) -> CGPoint {
        let edgeShift = defaultEdgeDistance - inset
        return clamp(CGPoint(x: region.maxX - edgeShift, y: region.maxY - edgeShift), in: region)
    }
}
