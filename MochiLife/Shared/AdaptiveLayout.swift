import SwiftUI

/// Layout rules shared by every screen, so the app reads well on any iPhone, including both
/// displays of iPhone Duo. Screens branch on the fold (`FoldLayout`), the horizontal size class
/// and the size they actually get, never on the device model or `UIScreen`.
enum AdaptiveLayout {
    /// Forms and single-column lists are no wider than this, centred.
    static let readableWidth: CGFloat = 640
    /// The standard horizontal content margin (the inset-grouped list's own margin).
    static let minimumMargin: CGFloat = 20

    /// What's left of `content` after cutting away every reserved area that reaches into it.
    /// Each area is cut along the side that keeps the most room, so a cutout near an edge trims
    /// just that edge. (The fold is handled by `FoldLayout`, never by this.)
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

    /// The active regions, in the proxy's own coordinate space.
    nonisolated static func active(in proxy: GeometryProxy) -> ReservedAreas {
        guard #available(iOS 27.1, *) else { return ReservedAreas() }
        return ReservedAreas(
            divisions: proxy.reservedRegions(kind: .division).filter(\.isActive).map(\.frame),
            occlusions: proxy.reservedRegions(kind: .occlusion).filter(\.isActive).map(\.frame)
        )
    }
}

/// The root of a fold-aware screen or sheet: measures its area and the fold (`FoldGeometry`) and
/// hands the layout to its content.
///
/// - **One background:** a single layer fills the whole area and ignores the safe areas; every
///   list and form inside hides its own background (`.scrollContentBackground(.hidden)`; cards and
///   rows keep their styling), so nothing shows at the fold in light or dark mode.
/// - **Keyboard:** the panes come from the whole area and the fold, never from the safe part, so
///   the keyboard can't move them: with the fold side to side, the top pane stays put and the
///   keyboard has the bottom pane, where only the background is. Keyboard avoidance itself is
///   left alone (ignoring the keyboard's safe area let lists draw and scroll behind it).
struct FoldAwareContainer<Content: View>: View {
    var background = Color(uiColor: .systemGroupedBackground)
    @ViewBuilder var content: (FoldLayout) -> Content

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var geometry = FoldGeometry()

    var body: some View {
        let layout = geometry.layout(isRegularWidth: sizeClass == .regular)
        content(layout)
            .scrollContentBackground(.hidden)
            .background {
                background.ignoresSafeArea()
            }
            .onGeometryChange(for: FoldGeometry.self) { FoldGeometry.read($0) } action: { geometry in
                FoldMemory.shared.remember(geometry)
                self.geometry = geometry
            }
    }
}

/// Two panes meeting exactly at the fold: leading and trailing side by side, top and bottom when
/// stacked. The band between them is empty and transparent. Use inside `FoldAwareContainer` with a
/// split layout; each pane gets its `FoldLayout.Pane` (for `paneMargins`).
struct FoldPanes<Primary: View, Secondary: View>: View {
    let layout: FoldLayout
    @ViewBuilder var primary: (FoldLayout.Pane) -> Primary
    @ViewBuilder var secondary: (FoldLayout.Pane) -> Secondary

    var body: some View {
        // The view's origin is the safe area's top-left corner, as in the layout's rects.
        if let band = layout.band, let second = layout.secondary {
            if layout.isStacked {
                VStack(spacing: 0) {
                    primary(layout.primary)
                        .frame(height: max(0, band.minY - layout.content.minY))
                        // A list draws rows past its bottom edge while the keyboard is up; nothing
                        // may show in the band or behind the keyboard.
                        .clipShape(ClipBelow())
                    Color.clear
                        .frame(height: band.height)
                        .accessibilityHidden(true)
                    secondary(second)
                        .frame(maxHeight: .infinity)
                }
            } else {
                HStack(spacing: 0) {
                    primary(layout.primary)
                        .frame(width: max(0, band.minX - layout.content.minX))
                    Color.clear
                        .frame(width: band.width)
                        .accessibilityHidden(true)
                    secondary(second)
                        .frame(maxWidth: .infinity)
                }
            }
        } else {
            primary(layout.primary)
        }
    }
}

extension View {
    /// Sets a list's horizontal content margins for a pane of a split: the pane's safe-area strip
    /// (the action bar, on the trailing side) plus the standard margin, or more for a readable
    /// width. Margins are measured from the scroll view's edges, which reach the window's edges
    /// where the pane does.
    func paneMargins(_ pane: FoldLayout.Pane, readableWidth: CGFloat? = AdaptiveLayout.readableWidth) -> some View {
        let margins = pane.listMargins(readableWidth: readableWidth)
        return contentMargins(.leading, margins.leading, for: .scrollContent)
            .contentMargins(.trailing, margins.trailing, for: .scrollContent)
    }

    /// A screen (or sheet) without a two-pane design: one column, in the leading pane with the
    /// fold top to bottom and in the top pane with the fold side to side, so it never crosses the
    /// fold; otherwise the whole view. Limited to a readable width (about 640 pt, centred), with
    /// the one continuous background of `FoldAwareContainer`.
    ///
    /// For a scrolling `List` or `Form`, the width goes on its content margins; otherwise the view
    /// is padded. On an ordinary iPhone in portrait nothing changes: the system's own margins stay.
    func foldAwareColumn(scrolls: Bool = true, limitsWidth: Bool = true,
                         background: Color = Color(uiColor: .systemGroupedBackground)) -> some View {
        FoldAwareContainer(background: background) { layout in
            modifier(FoldColumnPlacement(layout: layout, scrolls: scrolls, limitsWidth: limitsWidth))
        }
    }

    /// Places a view in a layout's column pane (as `foldAwareColumn` does), for screens that use
    /// `FoldAwareContainer` themselves and show one column when nothing splits them.
    func placedInColumn(of layout: FoldLayout, scrolls: Bool = true, limitsWidth: Bool = true) -> some View {
        modifier(FoldColumnPlacement(layout: layout, scrolls: scrolls, limitsWidth: limitsWidth))
    }

    /// A progress, message or empty state filling a screen or sheet: a fold-aware column (so it's
    /// never centred on the fold) on the plain background.
    func foldAwareMessage() -> some View {
        foldAwareColumn(scrolls: false, background: Color(uiColor: .systemBackground))
    }
}

/// Places a view in `layout.columnPane`. The view's own bounds are the layout's content frame;
/// padding moves its edges to the pane's (to its full frame for a list, which extends under the
/// safe area by itself; to its safe frame otherwise), and margins centre a readable width.
private struct FoldColumnPlacement: ViewModifier {
    let layout: FoldLayout
    let scrolls: Bool
    let limitsWidth: Bool

    @State private var occlusions: [CGRect] = []

    func body(content: Content) -> some View {
        let placement = placement
        content
            // With the fold side to side the column ends at the band; a list draws rows past its
            // bottom edge while the keyboard is up, so clip there (and only there).
            .clipShape(ClipBelow(isActive: layout.isStacked))
            .contentMargins(.leading, placement.leadingMargin, for: .scrollContent)
            .contentMargins(.trailing, placement.trailingMargin, for: .scrollContent)
            .padding(.leading, placement.padding.leading)
            .padding(.trailing, placement.padding.trailing)
            .padding(.top, placement.padding.top)
            .padding(.bottom, placement.padding.bottom)
            // Occlusions (camera, status column) that reach past the safe area, read on every
            // geometry change. Measured outside the padding, so the result never feeds back.
            .onGeometryChange(for: [CGRect].self) { ReservedAreas.active(in: $0).occlusions } action: { occlusions = $0 }
    }

    private struct Placement {
        var padding = FoldLayoutResolver.Insets()
        var leadingMargin: CGFloat?
        var trailingMargin: CGFloat?
    }

    private var placement: Placement {
        let pane = layout.columnPane
        let content = layout.content
        let free = AdaptiveLayout.freeRect(pane.safeFrame, avoiding: occlusions)
        let edges = scrolls ? pane.frame : free
        var result = Placement(padding: .init(
            leading: max(0, edges.minX - content.minX),
            trailing: max(0, content.maxX - edges.maxX),
            top: max(0, edges.minY - content.minY),
            bottom: max(0, content.maxY - edges.maxY)
        ))
        let readable = limitsWidth ? AdaptiveLayout.readableWidth : CGFloat.infinity
        let extra = free.width - readable - 2 * AdaptiveLayout.minimumMargin
        if scrolls {
            let cutLeading = free.minX - pane.safeFrame.minX
            let cutTrailing = pane.safeFrame.maxX - free.maxX
            // The system's own margins stay unless the column needs narrowing or meets the fold.
            if layout.isSplit || extra > 0 || cutLeading > 0 || cutTrailing > 0 {
                let side = max(0, extra / 2) + AdaptiveLayout.minimumMargin
                result.leadingMargin = (pane.insets.leading + cutLeading + side).rounded()
                result.trailingMargin = (pane.insets.trailing + cutTrailing + side).rounded()
            }
        } else if extra > 0 {
            result.padding.leading += (extra / 2).rounded()
            result.padding.trailing += (extra / 2).rounded()
        }
        return result
    }
}

/// Clips only what's drawn below a view's bottom edge (and leaves its top and sides open, so a list
/// still scrolls under the navigation bar). Inactive, it clips nothing.
private struct ClipBelow: Shape {
    var isActive = true

    func path(in rect: CGRect) -> Path {
        let reach: CGFloat = 100_000
        guard isActive else { return Path(rect.insetBy(dx: -reach, dy: -reach)) }
        return Path(CGRect(x: rect.minX - reach, y: rect.minY - reach, width: rect.width + 2 * reach, height: rect.height + reach))
    }
}
