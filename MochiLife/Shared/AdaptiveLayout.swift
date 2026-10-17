import SwiftUI

/// Layout rules shared by every screen, so the app reads well on any iPhone, including both
/// displays of iPhone Duo. Screens branch on the horizontal size class and the width they
/// actually get, never on the device model or `UIScreen`.
enum AdaptiveLayout {
    /// Forms and single-column lists are no wider than this, centred.
    static let readableWidth: CGFloat = 640
    /// The side margin kept when content is narrowed (the inset-grouped list's own margin).
    static let minimumMargin: CGFloat = 20
    /// Regular width at least this wide shows two columns.
    static let twoColumnMinimumWidth: CGFloat = 800

    /// How a screen lays itself out at a given size.
    enum Columns: Equatable {
        /// One column: the iPhone layout, limited to the readable width when there's more room.
        case single
        /// Two columns side by side (regular width, at least 800 pt).
        case two

        init(sizeClass: UserInterfaceSizeClass?, width: CGFloat) {
            self = sizeClass == .regular && width >= AdaptiveLayout.twoColumnMinimumWidth ? .two : .single
        }
    }

    /// The width a view's content can use: the proxy's own width.
    ///
    /// On a `List` (and other views that extend under the safe area), the proxy's frame already
    /// leaves out the safe area, including a toolbar placed vertically at the side, while
    /// `safeAreaInsets` reports the safe-area strips around it: the regions the list extends
    /// into, which its content margins are measured across. So the width is never reduced by the
    /// insets again.
    ///
    /// *Why (2026-10-16):* subtracting the insets counted iPhone Duo's 84 pt vertical action bar
    /// twice (783 pt instead of 867 pt), so the Calories screen never split into two panes, and
    /// its margins were worked out for the wrong area, leaving one column about two thirds of
    /// the window wide and across the fold.
    nonisolated static func contentWidth(in proxy: GeometryProxy) -> CGFloat {
        proxy.size.width
    }

    /// What's left of `content` after cutting away every reserved area that reaches into it.
    /// Each area is cut along the side that keeps the most room, so a band across the middle
    /// leaves the larger half and a cutout near an edge trims just that edge.
    nonisolated static func freeRect(_ content: CGRect, avoiding areas: [CGRect]) -> CGRect {
        var free = content
        for area in areas where area.intersects(free) {
            let sides = [
                CGRect(x: free.minX, y: free.minY, width: area.minX - free.minX, height: free.height),
                CGRect(x: area.maxX, y: free.minY, width: free.maxX - area.maxX, height: free.height),
                CGRect(x: free.minX, y: free.minY, width: free.width, height: area.minY - free.minY),
                CGRect(x: free.minX, y: area.maxY, width: free.width, height: free.maxY - area.maxY),
            ].filter { $0.width > 0 && $0.height > 0 }
            free = sides.max { $0.width * $0.height < $1.width * $1.height } ?? free
        }
        return free
    }
}

/// The active reserved regions of a view (iOS 27.1): the division band between the halves of
/// iPhone Duo's inner display (active in Book pose) and occlusions such as the camera and the
/// status column on its outer display. Always empty before iOS 27.1 and on other iPhones.
///
/// Regions can still be empty during the first layout passes, so they're read on every geometry
/// change, never once.
struct ReservedAreas: Equatable, Sendable {
    var divisions: [CGRect] = []
    var occlusions: [CGRect] = []

    var all: [CGRect] { divisions + occlusions }

    /// A division band running across the view (wider than tall), as on the open display turned.
    var hasHorizontalDivision: Bool { divisions.contains { $0.width > $0.height } }

    /// The active regions, in the proxy's own coordinate space.
    nonisolated static func active(in proxy: GeometryProxy) -> ReservedAreas {
        guard #available(iOS 27.1, *) else { return ReservedAreas() }
        return ReservedAreas(
            divisions: proxy.reservedRegions(kind: .division).filter(\.isActive).map(\.frame),
            occlusions: proxy.reservedRegions(kind: .occlusion).filter(\.isActive).map(\.frame)
        )
    }
}

extension View {
    /// Keeps content to a readable width (about 640 pt, centred) and out of any active reserved
    /// region that reaches past the safe area. For a scrolling `List` or `Form`, the margins go on
    /// the scroll content, so the list's background still fills the screen; otherwise the view is
    /// padded. On an ordinary iPhone in portrait nothing changes.
    func readableContent(scrolls: Bool = true) -> some View {
        modifier(ReadableContentModifier(scrolls: scrolls, limitsWidth: true))
    }

    /// Pads the view out of any active reserved region that reaches past the safe area, at any
    /// width (for full-width content such as the camera preview).
    func avoidingReservedRegions() -> some View {
        modifier(ReadableContentModifier(scrolls: false, limitsWidth: false))
    }
}

private struct ReadableContentModifier: ViewModifier {
    let scrolls: Bool
    let limitsWidth: Bool

    @State private var insets = Insets()

    /// Horizontal margins (nil = the system's own) and vertical padding.
    struct Insets: Equatable, Sendable {
        var leading: CGFloat?
        var trailing: CGFloat?
        var top: CGFloat = 0
        var bottom: CGFloat = 0
    }

    func body(content: Content) -> some View {
        content
            .contentMargins(.leading, scrolls ? insets.leading : nil, for: .scrollContent)
            .contentMargins(.trailing, scrolls ? insets.trailing : nil, for: .scrollContent)
            .padding(.leading, scrolls ? 0 : insets.leading ?? 0)
            .padding(.trailing, scrolls ? 0 : insets.trailing ?? 0)
            .padding(.top, insets.top)
            .padding(.bottom, insets.bottom)
            // Measured outside the padding, so the result never feeds back into the measurement.
            .onGeometryChange(for: Insets.self) { [scrolls, limitsWidth] proxy in
                Self.insets(in: proxy, scrolls: scrolls, limitsWidth: limitsWidth)
            } action: { insets = $0 }
    }

    /// The proxy's frame is the content area (see `AdaptiveLayout.contentWidth`). Padding is
    /// measured from it; scroll-content margins are measured from the scroll view's edges, which
    /// lie beyond it by the safe-area insets, so those are added.
    nonisolated static func insets(in proxy: GeometryProxy, scrolls: Bool, limitsWidth: Bool) -> Insets {
        let safe = proxy.safeAreaInsets
        let content = CGRect(origin: .zero, size: proxy.size)
        let free = AdaptiveLayout.freeRect(content, avoiding: ReservedAreas.active(in: proxy).all)
        let extraWidth = free.width - AdaptiveLayout.readableWidth - 2 * AdaptiveLayout.minimumMargin
        let leadingCut = free.minX - content.minX
        let trailingCut = content.maxX - free.maxX
        // Where margins are measured from: the full area's edges for scroll content.
        let leadingBase = scrolls ? safe.leading : 0
        let trailingBase = scrolls ? safe.trailing : 0
        var insets = Insets(top: free.minY - content.minY, bottom: content.maxY - free.maxY)
        if !limitsWidth {
            insets.leading = leadingBase + leadingCut
            insets.trailing = trailingBase + trailingCut
        } else if extraWidth > 0 || leadingCut > 0 || trailingCut > 0 {
            // The system's own margins are left alone unless something needs narrowing.
            let centring = max(0, extraWidth / 2) + AdaptiveLayout.minimumMargin
            insets.leading = (leadingBase + leadingCut + centring).rounded()
            insets.trailing = (trailingBase + trailingCut + centring).rounded()
        }
        return insets
    }
}

/// Two panes side by side, or one above the other. On iOS 27.1 this is an `ArrangementView` with
/// the split style, which places the panes on either side of iPhone Duo's division band so
/// nothing is drawn underneath it. Before iOS 27.1, two equal panes in a stack.
struct SplitPanes<Primary: View, Secondary: View>: View {
    var axis: Axis = .horizontal
    @ViewBuilder var primary: Primary
    @ViewBuilder var secondary: Secondary

    var body: some View {
        if #available(iOS 27.1, *) {
            ArrangementView {
                primary
            } secondary: {
                secondary
            }
            .arrangementViewStyle(.split.axes(axis == .horizontal ? .horizontal : .vertical))
        } else if axis == .horizontal {
            HStack(spacing: 0) {
                primary.frame(maxWidth: .infinity)
                secondary.frame(maxWidth: .infinity)
            }
        } else {
            VStack(spacing: 0) {
                primary.frame(maxHeight: .infinity)
                secondary.frame(maxHeight: .infinity)
            }
        }
    }
}
