import SwiftUI

/// Five icon-only Liquid Glass buttons around Mochi: Eat, Play, Settings, Weight, Profile,
/// clockwise. The ring is always centred on her and uses a fixed preset (full ring, edge fan or
/// corner fan, `RadialMenuGeometry`) chosen once per opening. Drawn over everything. The buttons share
/// one `GlassEffectContainer` and emerge from (and return to) a small glass seed at Mochi's centre
/// with the glass morph; under Reduce Motion they simply fade. There's no dimming: an invisible
/// tap catcher (with a hole over Mochi, so she can still be tapped or dragged) closes the ring.
/// One flat level, no submenus.
struct RadialActionMenu: View {
    let home: MochiHome

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glassNamespace
    @State private var isShown = false
    @State private var placement: RadialMenuGeometry.Placement?

    struct Action: Identifiable {
        var id: String { title }
        var title: String
        var symbol: String
        var hint: String
    }

    /// Clockwise order.
    static let actions = [
        Action(title: "Eat", symbol: "fork.knife", hint: "Opens Log Food"),
        Action(title: "Play", symbol: "tennisball.fill", hint: "Mochi plays with her ball"),
        Action(title: "Settings", symbol: "gearshape.fill", hint: "Opens Settings"),
        Action(title: "Weight", symbol: "scalemass.fill", hint: "Opens weight tracking"),
        Action(title: "Profile", symbol: "pawprint.fill", hint: "Opens Mochi's profile"),
    ]
    static let buttonDiameter = RadialMenuGeometry.buttonDiameter
    static let iconSize: CGFloat = 20
    static let seedDiameter: CGFloat = 28

    var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: home.spriteFrame.midX, y: home.spriteFrame.midY)
            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(TapCatcher(hole: home.spriteFrame), eoFill: true)
                    .onTapGesture { close() }
                    .accessibilityHidden(true)
                GlassEffectContainer(spacing: 0) {
                    ZStack(alignment: .topLeading) {
                        if isShown, let placement {
                            ForEach(Array(Self.actions.enumerated()), id: \.element.id) { index, action in
                                button(action)
                                    .position(placement.points[index])
                            }
                        } else if !reduceMotion {
                            Circle()
                                .fill(.clear)
                                .frame(width: Self.seedDiameter, height: Self.seedDiameter)
                                .glassEffect(.regular, in: .circle)
                                .glassEffectID("seed", in: glassNamespace)
                                .position(center)
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape) { close() }
            .onAppear { open(center: center) }
        }
        .ignoresSafeArea()
    }

    /// Picks the preset from her position (once per opening) and opens. The bounds are Mochi's
    /// own area (`MochiArea`): inside the safe area, below or beside the toolbar, with a 4 pt
    /// margin, and trimmed to her side of iPhone Duo's division band; buttons also keep clear of
    /// the camera and status occlusions.
    private func open(center: CGPoint) {
        guard let area = home.mochiArea else {
            home.isMenuOpen = false
            return
        }
        let bounds = area.menuBounds(around: center)
        let scale = area.spriteSize.width / MochiSpriteView.compactSize.width
        let edges = RadialMenuGeometry.nearEdges(center: center, bounds: bounds, previous: home.menuNearEdges, scale: scale)
        home.menuNearEdges = edges
        placement = RadialMenuGeometry.place(center: center, bounds: bounds, nearEdges: edges, count: Self.actions.count,
                                             scale: scale, obstacles: area.obstacles)
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.4, bounce: 0.2)) {
            isShown = true
        }
    }

    private func button(_ action: Action) -> some View {
        Button {
            perform(action)
        } label: {
            Image(systemName: action.symbol)
                .font(.system(size: Self.iconSize, weight: .medium))
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
        .accessibilityHint(action.hint)
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
