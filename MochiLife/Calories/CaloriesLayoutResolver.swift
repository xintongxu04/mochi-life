import CoreGraphics

/// Decides how the Calories screen is laid out for a window. Pure, no views; unit-tested.
///
/// **Split** when the window has regular width and the fold runs vertically (iPhone Duo open,
/// flat or in Book pose), so the screen is two halves side by side. The panes meet the fold band
/// exactly; the leading pane holds the food list, the trailing pane the summary and chart, and the
/// vertical action bar sits inside the trailing pane at the window's trailing edge. With no fold
/// information, a regular-width window that's wider than tall splits at the centre of the full
/// window (the screen), never of its safe area, around a band `fallbackFoldBandWidth` wide.
///
/// **Single column** otherwise: compact width (an ordinary iPhone, iPhone Duo closed), or a fold
/// that runs horizontally (iPhone Duo open and turned). It uses the full available width.
///
/// Every rect, input and output, is in one coordinate space: the screen root's own, where
/// SwiftUI reports the fold (iOS 27.1 reserved regions), with its origin at the safe area's
/// top-left corner.
enum CaloriesLayoutResolver {
    /// The fold band's width when no fold position is known.
    static let fallbackFoldBandWidth: CGFloat = 40

    /// The display fold, as reported by the system (iOS 27.1 division region, margins included).
    struct Fold: Equatable, Sendable {
        var rect: CGRect
        var isActive: Bool

        /// Runs top to bottom, so the screen is two halves side by side.
        var isVertical: Bool { rect.height > rect.width }
    }

    struct Input: Equatable, Sendable {
        /// The whole window the screen covers (the screen on iPhone), safe-area strips included.
        var containerFrame: CGRect
        /// The part inside the safe area. The strip between its trailing edge and the container's
        /// is the vertical action bar with its padding and the safe area (measured at runtime).
        var contentFrame: CGRect
        /// Nil when there's no fold information.
        var fold: Fold?
        var isRegularWidth: Bool
        /// The standard horizontal content margin.
        var margin: CGFloat

        var leadingInset: CGFloat { max(0, contentFrame.minX - containerFrame.minX) }
        var actionBarWidth: CGFloat { max(0, containerFrame.maxX - contentFrame.maxX) }
    }

    static func resolve(_ input: Input) -> CaloriesLayout {
        guard input.isRegularWidth, let band = splitBand(for: input) else {
            return .singleColumn(contentWidth: input.contentFrame.width, fold: input.fold)
        }
        let container = input.containerFrame
        let leading = CGRect(x: container.minX, y: container.minY,
                             width: max(0, band.minX - container.minX), height: container.height)
        let trailing = CGRect(x: band.maxX, y: container.minY,
                              width: max(0, container.maxX - band.maxX), height: container.height)
        return .split(CaloriesLayout.Split(
            leading: leading,
            trailing: trailing,
            leadingMargins: .init(leading: input.leadingInset + input.margin, trailing: input.margin),
            trailingMargins: .init(leading: input.margin, trailing: input.actionBarWidth + input.margin)
        ))
    }

    /// The vertical band the panes meet at: the reported fold if it runs vertically; the centre
    /// of the full window if there's no fold information and the window is wider than tall;
    /// otherwise nil.
    private static func splitBand(for input: Input) -> CGRect? {
        let container = input.containerFrame
        if let fold = input.fold {
            guard fold.isVertical else { return nil }
            let minX = min(max(fold.rect.minX, container.minX), container.maxX)
            let maxX = min(max(fold.rect.maxX, minX), container.maxX)
            return CGRect(x: minX, y: container.minY, width: maxX - minX, height: container.height)
        }
        guard container.width > container.height else { return nil }
        return CGRect(x: container.midX - fallbackFoldBandWidth / 2, y: container.minY,
                      width: fallbackFoldBandWidth, height: container.height)
    }
}

/// The Calories screen's layout for the current window (`CaloriesLayoutResolver`).
enum CaloriesLayout: Equatable, Sendable {
    /// One column using the full available width. `fold` is a fold that doesn't split the screen
    /// (horizontal), if any.
    case singleColumn(contentWidth: CGFloat, fold: CaloriesLayoutResolver.Fold?)
    /// Two panes meeting at a vertical fold.
    case split(Split)

    /// Horizontal content margins, measured from a pane's own edges (a list's content margins).
    struct Margins: Equatable, Sendable {
        var leading: CGFloat
        var trailing: CGFloat
    }

    struct Split: Equatable, Sendable {
        /// From the window's leading edge to the fold band: the food list.
        var leading: CGRect
        /// From the fold band to the window's trailing edge (action bar included): the summary
        /// and the chart.
        var trailing: CGRect
        var leadingMargins: Margins
        /// The trailing margin includes the action bar, so the cards stay clear of it.
        var trailingMargins: Margins

        /// The band between the panes. Only the screen's background is under it.
        var foldBand: CGRect {
            CGRect(x: leading.maxX, y: leading.minY, width: trailing.minX - leading.maxX, height: leading.height)
        }

        /// Where the food list's cards and rows go.
        var leadingContent: CGRect { Self.inset(leading, by: leadingMargins) }
        /// Where the summary and chart cards go.
        var trailingContent: CGRect { Self.inset(trailing, by: trailingMargins) }

        var leadingContentWidth: CGFloat { leadingContent.width }
        /// The trailing pane minus the action bar minus the margins: narrower than the food list.
        var trailingContentWidth: CGFloat { trailingContent.width }

        private static func inset(_ pane: CGRect, by margins: Margins) -> CGRect {
            CGRect(x: pane.minX + margins.leading, y: pane.minY,
                   width: max(0, pane.width - margins.leading - margins.trailing), height: pane.height)
        }
    }

    /// The fold band content keeps out of (floating Mochi too): the band between the panes, or a
    /// fold that doesn't split the screen. In the resolver's coordinate space.
    var foldBand: CGRect? {
        switch self {
        case let .split(split): split.foldBand
        case let .singleColumn(_, fold): fold?.rect
        }
    }

    /// One column with an active fold running across it (iPhone Duo open, turned and partly
    /// folded): the content is kept above and below the band.
    var stacksAroundFold: Bool {
        guard case let .singleColumn(_, fold?) = self else { return false }
        return fold.isActive && !fold.isVertical
    }
}
