import CoreGraphics

/// Decides how the Calories screen is laid out for a window. Pure, no views; unit-tested.
///
/// **Split** when the window has regular width and the fold runs vertically (iPhone Duo open,
/// flat or in Book pose), so the screen is two halves side by side. The panes meet the fold band
/// exactly; the leading pane holds the food list, the trailing pane the summary and chart, and the
/// vertical action bar sits inside the trailing pane at the window's trailing edge. With no fold
/// information (before iOS 27.1, or if the system reports none), a regular-width window that's
/// wider than tall splits at its horizontal midpoint, around a band `fallbackFoldBandWidth` wide.
///
/// **Single column** otherwise: compact width (an ordinary iPhone, iPhone Duo closed), or a fold
/// that runs horizontally (iPhone Duo open and turned). It uses the full available width.
///
/// All rects are in window points.
enum CaloriesLayoutResolver {
    /// The fold band's width when no fold position is known.
    static let fallbackFoldBandWidth: CGFloat = 40

    /// The display fold as reported by the system (iOS 27.1 division region, including its
    /// margins).
    struct Fold: Equatable, Sendable {
        var rect: CGRect
        var isActive: Bool

        /// Runs top to bottom, so the screen is two halves side by side.
        var isVertical: Bool { rect.height > rect.width }
    }

    struct Input: Equatable, Sendable {
        var windowSize: CGSize
        /// Nil when the system gives no fold information.
        var fold: Fold?
        var isRegularWidth: Bool
        /// The window's leading safe-area inset.
        var leadingInset: CGFloat = 0
        /// The width at the trailing edge that content must leave clear: the vertical action bar
        /// with its padding and the safe area (measured at runtime; the trailing safe-area inset).
        var actionBarWidth: CGFloat = 0
        /// The standard horizontal content margin.
        var margin: CGFloat
    }

    static func resolve(_ input: Input) -> CaloriesLayout {
        let size = input.windowSize
        let fullWidth = max(0, size.width - input.leadingInset - input.actionBarWidth)
        guard input.isRegularWidth, let band = splitBand(for: input) else {
            return .singleColumn(contentWidth: fullWidth, fold: input.fold)
        }
        let leading = CGRect(x: 0, y: 0, width: band.minX, height: size.height)
        let trailing = CGRect(x: band.maxX, y: 0, width: max(0, size.width - band.maxX), height: size.height)
        let leadingMargins = CaloriesLayout.Margins(leading: input.leadingInset + input.margin, trailing: input.margin)
        let trailingMargins = CaloriesLayout.Margins(leading: input.margin, trailing: input.actionBarWidth + input.margin)
        return .split(CaloriesLayout.Split(
            leading: leading,
            trailing: trailing,
            leadingMargins: leadingMargins,
            trailingMargins: trailingMargins,
            leadingContentWidth: max(0, leading.width - leadingMargins.leading - leadingMargins.trailing),
            trailingContentWidth: max(0, trailing.width - trailingMargins.leading - trailingMargins.trailing)
        ))
    }

    /// The vertical band the panes meet at: the reported fold if it runs vertically, the
    /// midpoint band if there's no fold information and the window is wider than tall, else nil.
    private static func splitBand(for input: Input) -> CGRect? {
        let size = input.windowSize
        if let fold = input.fold {
            guard fold.isVertical else { return nil }
            let minX = min(max(fold.rect.minX, 0), size.width)
            let maxX = min(max(fold.rect.maxX, minX), size.width)
            return CGRect(x: minX, y: 0, width: maxX - minX, height: size.height)
        }
        guard size.width > size.height else { return nil }
        return CGRect(x: (size.width - fallbackFoldBandWidth) / 2, y: 0, width: fallbackFoldBandWidth, height: size.height)
    }
}

/// The Calories screen's layout for the current window (`CaloriesLayoutResolver`).
enum CaloriesLayout: Equatable, Sendable {
    /// One column using the full available width. `fold` is a fold that doesn't split the screen
    /// (horizontal), if any.
    case singleColumn(contentWidth: CGFloat, fold: CaloriesLayoutResolver.Fold?)
    /// Two panes meeting at a vertical fold.
    case split(Split)

    /// Horizontal content margins, measured from a pane's own edges.
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
        var leadingContentWidth: CGFloat
        /// The trailing pane minus the action bar minus the margins: narrower than the food list.
        var trailingContentWidth: CGFloat

        /// The band between the panes, where nothing is drawn.
        var foldBand: CGRect {
            CGRect(x: leading.maxX, y: leading.minY, width: trailing.minX - leading.maxX, height: leading.height)
        }
    }

    /// The fold band floating Mochi keeps out of: the band between the panes, or a fold that
    /// doesn't split the screen.
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
