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
    /// A finger is down on her.
    @State private var isPressing = false
    /// The long-press (petting) fired during this touch, so its release isn't a tap.
    @State private var didLongPress = false
    @State private var longPressTask: Task<Void, Never>?
    /// Counts accepted pets, for the soft haptic.
    @State private var petCount = 0

    static let dragThreshold: CGFloat = 8
    static let longPressDuration: Duration = .milliseconds(450)

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
                        .gesture(touch(from: origin, region: region))
                        .accessibilityElement()
                        .accessibilityLabel("Mochi")
                        .accessibilityHint("Opens actions")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { home.spriteTapped() }
                        .accessibilityAction(named: "Pet Mochi") { home.pet() }
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
        .sensoryFeedback(.impact(flexibility: .soft), trigger: petCount)
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

    /// One touch handler that tells the three gestures apart:
    /// - **Drag:** the finger moves 8 pt or more (before or after a long-press). She follows it;
    ///   the ring closes; no grooming starts (grooming already started continues).
    /// - **Long-press (petting):** held 0.45 s while moving less than 8 pt. Soft haptic, the ring
    ///   closes, she grooms; the release is not a tap.
    /// - **Tap:** released before the long-press and before moving 8 pt. Toggles the ring.
    private func touch(from origin: CGPoint, region: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if !isPressing {
                    isPressing = true
                    didLongPress = false
                    longPressTask = Task {
                        try? await Task.sleep(for: Self.longPressDuration)
                        guard !Task.isCancelled, isPressing, !isDragging else { return }
                        didLongPress = true
                        if home.pet() { petCount += 1 }
                    }
                }
                if !isDragging, hypot(value.translation.width, value.translation.height) >= Self.dragThreshold {
                    isDragging = true
                    longPressTask?.cancel()
                    home.spriteDragStarted()
                }
                if isDragging { translation = value.translation }
            }
            .onEnded { value in endTouch(value, origin: origin, region: region) }
    }

    /// Where she lands after a drag: kept where dropped, or sprung back inside the area.
    private func drop(_ value: DragGesture.Value, origin: CGPoint, region: CGRect) {
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

    /// The end of a touch: a drop after a drag, a tap if nothing else happened.
    private func endTouch(_ value: DragGesture.Value, origin: CGPoint, region: CGRect) {
        longPressTask?.cancel()
        longPressTask = nil
        isPressing = false
        defer { didLongPress = false }
        guard isDragging else {
            if !didLongPress { home.spriteTapped() }
            return
        }
        drop(value, origin: origin, region: region)
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
