import SwiftUI

/// Five Liquid Glass buttons in a ring around Mochi: Eat, Play, Settings, Weight, Profile,
/// clockwise from the top (−90°, −18°, 54°, 126°, 198°). Drawn over everything. The buttons share
/// one `GlassEffectContainer` and emerge from (and return to) a small glass seed at Mochi's centre
/// with the glass morph; under Reduce Motion they simply fade. There's no dimming: an invisible
/// tap catcher (with a hole over Mochi, so she can still be tapped or dragged) closes the ring.
/// One flat level, no submenus.
struct RadialActionMenu: View {
    let home: MochiHome

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glassNamespace
    @State private var isShown = false

    struct Action: Identifiable {
        var id: String { title }
        var title: String
        var symbol: String
        var angle: Double
    }

    static let actions = [
        Action(title: "Eat", symbol: "fork.knife", angle: -90),
        Action(title: "Play", symbol: "tennisball.fill", angle: -18),
        Action(title: "Settings", symbol: "gearshape.fill", angle: 54),
        Action(title: "Weight", symbol: "scalemass.fill", angle: 126),
        Action(title: "Profile", symbol: "pawprint.fill", angle: 198),
    ]
    static let preferredRadius: CGFloat = 118
    static let minimumRadius: CGFloat = 72
    static let buttonDiameter: CGFloat = 56
    /// The caption capsule's centre, below the button's centre.
    static let labelOffset: CGFloat = 42
    /// From the button's centre to the bottom of its caption.
    static let labelBottom: CGFloat = 54
    static let margin: CGFloat = 8
    static let seedDiameter: CGFloat = 28

    var body: some View {
        GeometryReader { proxy in
            let sprite = CGPoint(x: home.spriteFrame.midX, y: home.spriteFrame.midY)
            let layout = Self.layout(around: sprite, in: proxy.size, safeArea: proxy.safeAreaInsets)
            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(TapCatcher(hole: home.spriteFrame), eoFill: true)
                    .onTapGesture { close() }
                    .accessibilityHidden(true)
                GlassEffectContainer(spacing: 0) {
                    ZStack(alignment: .topLeading) {
                        if isShown {
                            ForEach(Self.actions) { action in
                                let point = layout.position(for: action.angle)
                                button(action)
                                    .position(point)
                                label(action)
                                    .position(x: point.x, y: point.y + Self.labelOffset)
                            }
                        } else if !reduceMotion {
                            Circle()
                                .fill(.clear)
                                .frame(width: Self.seedDiameter, height: Self.seedDiameter)
                                .glassEffect(.regular, in: .circle)
                                .glassEffectID("seed", in: glassNamespace)
                                .position(layout.center)
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape) { close() }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.4, bounce: 0.2)) {
                isShown = true
            }
        }
    }

    private func button(_ action: Action) -> some View {
        Button {
            perform(action)
        } label: {
            Image(systemName: action.symbol)
                .font(.title2)
                .foregroundStyle(.primary)
                .frame(width: Self.buttonDiameter, height: Self.buttonDiameter)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .glassEffectID(action.id, in: glassNamespace)
        .glassEffectTransition(reduceMotion ? .identity : .matchedGeometry)
        .transition(.opacity)
        .accessibilityLabel(action.title)
    }

    private func label(_ action: Action) -> some View {
        Text(action.title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .glassEffect(.regular, in: .capsule)
            .glassEffectID("\(action.id).label", in: glassNamespace)
            .glassEffectTransition(reduceMotion ? .identity : .matchedGeometry)
            .transition(.opacity)
            .accessibilityHidden(true)
    }

    private func close(then work: (@MainActor () -> Void)? = nil) {
        withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(duration: 0.3, bounce: 0)) {
            isShown = false
        }
        Task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 120 : 280))
            home.isMenuOpen = false
            work?()
        }
    }

    private func perform(_ action: Action) {
        close {
            switch action.title {
            case "Eat": home.openLogFood()
            case "Play": home.playWithBall()
            case "Settings": home.push(.settings)
            case "Weight": home.push(.weight)
            default: home.push(.profile)
            }
        }
    }

    // MARK: - Layout

    struct Layout {
        var center: CGPoint
        var radius: CGFloat

        func position(for angle: Double) -> CGPoint {
            let radians = angle * .pi / 180
            return CGPoint(x: center.x + radius * cos(radians), y: center.y + radius * sin(radians))
        }
    }

    /// The ring around `sprite`, with its centre moved the minimum distance needed so every
    /// button and caption is inside the safe area (Mochi herself doesn't move). Only if the
    /// screen is too small even then does the radius shrink.
    static func layout(around sprite: CGPoint, in size: CGSize, safeArea: EdgeInsets) -> Layout {
        let safe = CGRect(x: safeArea.leading + margin, y: safeArea.top + margin,
                          width: size.width - safeArea.leading - safeArea.trailing - 2 * margin,
                          height: size.height - safeArea.top - safeArea.bottom - 2 * margin)
        let half = buttonDiameter / 2
        var radius = preferredRadius
        while true {
            let points = actions.map { Layout(center: .zero, radius: radius).position(for: $0.angle) }
            let minX = (points.map(\.x).min() ?? 0) - half
            let maxX = (points.map(\.x).max() ?? 0) + half
            let minY = (points.map(\.y).min() ?? 0) - half
            let maxY = (points.map(\.y).max() ?? 0) + labelBottom
            let fits = safe.maxX - maxX >= safe.minX - minX && safe.maxY - maxY >= safe.minY - minY
            if fits || radius <= minimumRadius {
                let xRange = (safe.minX - minX)...max(safe.minX - minX, safe.maxX - maxX)
                let yRange = (safe.minY - minY)...max(safe.minY - minY, safe.maxY - maxY)
                let center = CGPoint(x: min(max(sprite.x, xRange.lowerBound), xRange.upperBound),
                                     y: min(max(sprite.y, yRange.lowerBound), yRange.upperBound))
                return Layout(center: center, radius: radius)
            }
            radius -= 4
        }
    }
}

/// The whole screen with a hole over Mochi (used with even-odd fill), so taps outside the ring
/// close it while Mochi stays tappable and draggable.
private struct TapCatcher: Shape {
    var hole: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addRect(hole)
        return path
    }
}
