import SwiftUI

/// Mochi as a "desktop pet" floating above the Calories screen.
///
/// **Coordinate space:** a full-screen root layer (`ContentView`, above the `NavigationStack`,
/// `.ignoresSafeArea()`), so her position is in window points and nothing that happens while the
/// list scrolls (the large title collapsing, the bar or safe area changing) can move her.
///
/// **Drag area** (`MochiArea`): the window inside the safe area, minus the toolbar (the button
/// row on top, or the strip at the side when bars are vertical), inset 8 pt at the sides and
/// bottom, and clear of every active reserved region (iPhone Duo's division band and its camera
/// and status occlusions). She may sit over the large title, the summary card and the list.
///
/// **Saved position:** one per display configuration, as fractions of the drag area: compact
/// width (an ordinary iPhone, iPhone Duo closed) and regular width (iPhone Duo open). Each starts
/// bottom-trailing. She's placed on launch and after a real change of window size or
/// configuration (fold, unfold, rotate), animating to that configuration's saved spot; she's
/// re-clamped if the area changes (reserved regions can arrive a few layout passes late), and
/// never in response to scrolling.
///
/// Only her own rectangle takes touches. Drag (8 pt or more) moves her 1:1; a tap toggles the
/// ring. Dropped outside the area, she springs back in; otherwise she stays where dropped.
struct FloatingMochiView: View {
    let home: MochiHome

    @Environment(\.horizontalSizeClass) private var sizeClass

    /// Saved positions as fractions (0…1) of the drag area, per configuration; −1 = not saved.
    @AppStorage("mochi.compact.x") private var compactX = -1.0
    @AppStorage("mochi.compact.y") private var compactY = -1.0
    @AppStorage("mochi.regular.x") private var regularX = -1.0
    @AppStorage("mochi.regular.y") private var regularY = -1.0
    /// Older versions saved her top-left corner in screen points, and before that fractions of
    /// the area. Read once, for compact width, to convert.
    @AppStorage("mochi.origin.x") private var legacyX = -1.0
    @AppStorage("mochi.origin.y") private var legacyY = -1.0
    @AppStorage("mochi.position.x") private var legacyFractionX = -1.0
    @AppStorage("mochi.position.y") private var legacyFractionY = -1.0

    /// The window as measured by this layer.
    @State private var window = WindowGeometry()
    /// Her top-left corner in window points, while the screen is live.
    @State private var origin: CGPoint?
    /// The window size and size class `origin` was placed for.
    @State private var placedConfiguration: Configuration?
    @State private var translation = CGSize.zero
    @State private var isDragging = false
    /// A finger is down on her.
    @State private var isPressing = false
    /// The long-press (petting) fired during this touch, so its release isn't a tap.
    @State private var didLongPress = false
    @State private var longPressTask: Task<Void, Never>?
    /// Counts accepted pets, for the soft haptic.
    @State private var petCount = 0
    /// True only while an explicit move animates (the release spring, or a configuration change).
    @State private var isSettling = false

    static let dragThreshold: CGFloat = 8
    static let longPressDuration: Duration = .milliseconds(450)
    static let draggingScale: CGFloat = 1.06

    struct WindowGeometry: Equatable, Sendable {
        var size = CGSize.zero
        var safeArea = EdgeInsets()
        var reserved = ReservedAreas()
    }

    struct Configuration: Equatable {
        var size: CGSize
        var isRegular: Bool
    }

    private var isRegular: Bool { sizeClass == .regular }

    private var area: MochiArea {
        MochiArea(window: window.size, safeArea: window.safeArea, toolbar: home.toolbarPlacement,
                  reserved: window.reserved.all, spriteSize: MochiSpriteView.size(for: sizeClass))
    }

    var body: some View {
        let area = area
        ZStack(alignment: .topLeading) {
            if let origin {
                MochiSpriteView(animator: home.animator, size: area.spriteSize)
                    // Only the lift is animated; her position never is (except explicit moves).
                    .animation(.spring(duration: 0.2)) { content in
                        content
                            .scaleEffect(isDragging ? Self.draggingScale : 1)
                            .shadow(color: .black.opacity(isDragging ? 0.25 : 0), radius: 10, y: 6)
                    }
                    .contentShape(Rectangle())
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { home.spriteFrame = $0 }
                    .gesture(touch(from: origin, area: area))
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Read on every geometry change: reserved regions may be empty for the first passes.
        .onGeometryChange(for: WindowGeometry.self) { proxy in
            WindowGeometry(size: proxy.size, safeArea: proxy.safeAreaInsets, reserved: ReservedAreas.active(in: proxy))
        } action: { window = $0 }
        .onChange(of: area, initial: true) { _, area in update(for: area) }
        .ignoresSafeArea()
        .sensoryFeedback(.impact(weight: .light), trigger: isDragging) { _, dragging in dragging }
        .sensoryFeedback(.impact(flexibility: .soft), trigger: petCount)
    }

    /// A new configuration (first layout, fold, unfold, rotate) places her at its saved spot;
    /// any other change of the area just keeps her inside it. Nothing here follows scrolling:
    /// the area depends only on the window, the toolbar's place and reserved regions.
    private func update(for area: MochiArea) {
        guard window.size != .zero, area.usable.width > 0, area.usable.height > 0 else { return }
        home.mochiArea = area
        guard !isDragging else { return }
        let configuration = Configuration(size: window.size, isRegular: isRegular)
        if configuration != placedConfiguration {
            let isChange = placedConfiguration != nil && origin != nil
            placedConfiguration = configuration
            if isChange { home.isMenuOpen = false }
            move(to: savedPoint(in: area), animated: isChange)
        } else if let origin {
            let resolved = area.resolve(origin)
            if resolved != origin { move(to: resolved, animated: true) }
        }
    }

    /// This configuration's saved spot; for compact width, an older saved position converted
    /// once; otherwise the default corner.
    private func savedPoint(in area: MochiArea) -> CGPoint {
        let saved = isRegular ? (regularX, regularY) : (compactX, compactY)
        if saved.0 >= 0, saved.1 >= 0 {
            return area.point(fromFraction: CGPoint(x: saved.0, y: saved.1))
        }
        let point: CGPoint
        if !isRegular, legacyX >= 0, legacyY >= 0 {
            point = area.resolve(CGPoint(x: legacyX, y: legacyY))
        } else if !isRegular, legacyFractionX >= 0, legacyFractionY >= 0 {
            point = area.point(fromFraction: CGPoint(x: legacyFractionX, y: legacyFractionY))
        } else {
            point = area.defaultOrigin
        }
        save(point, in: area)
        return point
    }

    private func save(_ point: CGPoint, in area: MochiArea) {
        let fraction = area.fraction(of: point)
        if isRegular {
            (regularX, regularY) = (Double(fraction.x), Double(fraction.y))
        } else {
            (compactX, compactY) = (Double(fraction.x), Double(fraction.y))
        }
    }

    private func move(to point: CGPoint, animated: Bool) {
        guard animated, origin != nil else {
            origin = point
            translation = .zero
            return
        }
        isSettling = true
        withAnimation(.spring(duration: 0.35, bounce: 0.3)) {
            origin = point
            translation = .zero
        } completion: {
            isSettling = false
        }
    }

    /// One touch handler that tells the three gestures apart:
    /// - **Drag:** the finger moves 8 pt or more (before or after a long-press). She follows it;
    ///   the ring closes; no grooming starts (grooming already started continues).
    /// - **Long-press (petting):** held 0.45 s while moving less than 8 pt. Soft haptic, the ring
    ///   closes, she grooms; the release is not a tap.
    /// - **Tap:** released before the long-press and before moving 8 pt. Toggles the ring.
    private func touch(from origin: CGPoint, area: MochiArea) -> some Gesture {
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
            .onEnded { value in endTouch(value, origin: origin, area: area) }
    }

    /// Where she lands after a drag: kept where dropped, or sprung back inside the area (and off
    /// any reserved region, to its nearer side).
    private func drop(_ value: DragGesture.Value, origin: CGPoint, area: MochiArea) {
        let dropped = CGPoint(x: origin.x + value.translation.width, y: origin.y + value.translation.height)
        let resolved = area.resolve(dropped)
        save(resolved, in: area)
        if resolved == dropped {
            self.origin = resolved
            translation = .zero
        } else {
            move(to: resolved, animated: true)
        }
        isDragging = false
    }

    /// The end of a touch: a drop after a drag, a tap if nothing else happened.
    private func endTouch(_ value: DragGesture.Value, origin: CGPoint, area: MochiArea) {
        longPressTask?.cancel()
        longPressTask = nil
        isPressing = false
        defer { didLongPress = false }
        guard isDragging else {
            if !didLongPress { home.spriteTapped() }
            return
        }
        drop(value, origin: origin, area: area)
    }
}
