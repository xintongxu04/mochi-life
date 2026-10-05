import SwiftUI

/// Five round buttons in a ring around Mochi: Eat, Play, Settings, Weight, Profile, clockwise
/// from the top (−90°, −18°, 54°, 126°, 198°). Drawn over everything, above a dimmed scrim;
/// tapping the scrim (or Mochi, under it) closes it. One flat level, no submenus.
struct RadialActionMenu: View {
    let home: MochiHome

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    /// Room for the caption under each button.
    static let labelHeight: CGFloat = 18
    static let margin: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            let layout = Self.layout(around: CGPoint(x: home.spriteFrame.midX, y: home.spriteFrame.midY),
                                     in: proxy.size, safeArea: proxy.safeAreaInsets)
            ZStack {
                Color.black.opacity(isShown ? 0.35 : 0)
                    .contentShape(Rectangle())
                    .onTapGesture { close() }
                    .accessibilityHidden(true)
                ForEach(Self.actions) { action in
                    button(action)
                        .position(isShown ? layout.position(for: action.angle) : layout.center)
                        .scaleEffect(isShown || reduceMotion ? 1 : 0.2)
                        .opacity(isShown ? 1 : 0)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape) { close() }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.3, bounce: 0.25)) {
                isShown = true
            }
        }
    }

    private func button(_ action: Action) -> some View {
        Button {
            perform(action)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: action.symbol)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: Self.buttonDiameter, height: Self.buttonDiameter)
                    .background(Circle().fill(Color.accentColor))
                    .shadow(radius: 3, y: 1)
                Text(action.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
            }
            // Centered on the circle, with the caption hanging below.
            .offset(y: Self.labelHeight / 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.title)
    }

    private func close(then work: (@MainActor () -> Void)? = nil) {
        withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(duration: 0.22, bounce: 0)) {
            isShown = false
        }
        Task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 120 : 200))
            home.isMenuOpen = false
            work?()
        }
    }

    private func perform(_ action: Action) {
        close {
            switch action.title {
            case "Eat": home.openLogFood()
            case "Play": home.animator.play(.playing, loops: 2)
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

    /// The ring around `sprite`, moved (or made smaller) so every button and caption is inside
    /// the safe area.
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
            let maxY = (points.map(\.y).max() ?? 0) + half + labelHeight
            let xRange = (safe.minX - minX)...max(safe.minX - minX, safe.maxX - maxX)
            let yRange = (safe.minY - minY)...max(safe.minY - minY, safe.maxY - maxY)
            let fits = safe.maxX - maxX >= safe.minX - minX && safe.maxY - maxY >= safe.minY - minY
            if fits || radius <= minimumRadius {
                let center = CGPoint(x: min(max(sprite.x, xRange.lowerBound), xRange.upperBound),
                                     y: min(max(sprite.y, yRange.lowerBound), yRange.upperBound))
                return Layout(center: center, radius: radius)
            }
            radius -= 4
        }
    }
}
