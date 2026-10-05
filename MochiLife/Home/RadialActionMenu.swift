import SwiftUI

/// Five Liquid Glass buttons around Mochi: Eat, Play, Settings, Weight, Profile, clockwise. The
/// ring is always centred on her: with room all round they sit at 72° steps from the top; near an
/// edge or corner they fan across the largest free arc (`RadialMenuGeometry`). Positions are
/// worked out once per opening, after the captions are measured. Drawn over everything. The buttons share
/// one `GlassEffectContainer` and emerge from (and return to) a small glass seed at Mochi's centre
/// with the glass morph; under Reduce Motion they simply fade. There's no dimming: an invisible
/// tap catcher (with a hole over Mochi, so she can still be tapped or dragged) closes the ring.
/// One flat level, no submenus.
struct RadialActionMenu: View {
    let home: MochiHome

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glassNamespace
    @State private var isShown = false
    /// Measured caption sizes, by action.
    @State private var labelSizes: [String: CGSize] = [:]
    @State private var placement: RadialMenuGeometry.Placement?

    struct Action: Identifiable {
        var id: String { title }
        var title: String
        var symbol: String
    }

    /// Clockwise order.
    static let actions = [
        Action(title: "Eat", symbol: "fork.knife"),
        Action(title: "Play", symbol: "tennisball.fill"),
        Action(title: "Settings", symbol: "gearshape.fill"),
        Action(title: "Weight", symbol: "scalemass.fill"),
        Action(title: "Profile", symbol: "pawprint.fill"),
    ]
    static let buttonDiameter: CGFloat = 56
    /// Gap between a button and its caption.
    static let labelGap: CGFloat = 4
    static let margin: CGFloat = 8
    static let seedDiameter: CGFloat = 28

    var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: home.spriteFrame.midX, y: home.spriteFrame.midY)
            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(TapCatcher(hole: home.spriteFrame), eoFill: true)
                    .onTapGesture { close() }
                    .accessibilityHidden(true)
                // Invisible copies of the captions, to measure their real size.
                ForEach(Self.actions) { action in
                    labelText(action)
                        .fixedSize()
                        .hidden()
                        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                            labelSizes[action.id] = size
                            placeIfReady(center: center, screen: proxy.size, safeArea: proxy.safeAreaInsets)
                        }
                }
                .accessibilityHidden(true)
                GlassEffectContainer(spacing: 0) {
                    ZStack(alignment: .topLeading) {
                        if isShown, let placement {
                            ForEach(Array(Self.actions.enumerated()), id: \.element.id) { index, action in
                                let point = placement.points[index]
                                let labelHeight = labelSizes[action.id]?.height ?? 0
                                button(action)
                                    .position(point)
                                label(action)
                                    .position(x: point.x, y: point.y + Self.buttonDiameter / 2 + Self.labelGap + labelHeight / 2)
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
        }
        .ignoresSafeArea()
    }

    /// Once every caption is measured: works out the positions (once per opening) and opens.
    private func placeIfReady(center: CGPoint, screen: CGSize, safeArea: EdgeInsets) {
        guard placement == nil, Self.actions.allSatisfy({ labelSizes[$0.id] != nil }) else { return }
        let top = max(safeArea.top, home.restingTopLimit) + Self.margin
        let bounds = CGRect(x: safeArea.leading + Self.margin, y: top,
                            width: screen.width - safeArea.leading - safeArea.trailing - 2 * Self.margin,
                            height: screen.height - safeArea.bottom - Self.margin - top)
        let half = Self.buttonDiameter / 2
        let footprints = Self.actions.map { action -> CGRect in
            let label = labelSizes[action.id] ?? .zero
            let circle = CGRect(x: -half, y: -half, width: Self.buttonDiameter, height: Self.buttonDiameter)
            let caption = CGRect(x: -label.width / 2, y: half + Self.labelGap, width: label.width, height: label.height)
            return circle.union(caption)
        }
        placement = RadialMenuGeometry.place(center: center, bounds: bounds, footprints: footprints,
                                             avoiding: home.spriteFrame)
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.4, bounce: 0.2)) {
            isShown = true
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

    /// The caption's text and padding; its size is the footprint used for layout.
    private func labelText(_ action: Action) -> some View {
        Text(action.title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
    }

    private func label(_ action: Action) -> some View {
        labelText(action)
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
