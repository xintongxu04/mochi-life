import SwiftUI

/// How a screen is divided by iPhone Duo's fold. Pure, no views; unit-tested.
///
/// - **Side by side:** the fold runs top to bottom (Book, or Open flat), so there's a leading and a
///   trailing pane.
/// - **Stacked:** the fold runs side to side (the phone turned, half open or flat), so there's a
///   top and a bottom pane. In Book pose the keyboard takes the bottom half.
/// - **Single:** no fold (an ordinary iPhone, iPhone Duo closed), or one that doesn't cross the
///   view.
///
/// Every rect, input and output, is in one coordinate space: the measured view's own, with its
/// origin at the safe area's top-left corner. That's where SwiftUI reports the fold.
enum FoldLayoutResolver {
    /// The fold band's width when no fold position is known.
    static let fallbackFoldBandWidth: CGFloat = 40

    /// The display fold, as reported by the system (iOS 27.1 division region, margins included).
    struct Fold: Equatable, Sendable {
        var rect: CGRect
        /// True in the half-open (Book) pose.
        var isActive: Bool

        /// Runs top to bottom, so the screen is two halves side by side.
        var isVertical: Bool { rect.height > rect.width }
    }

    struct Input: Equatable, Sendable {
        /// The whole area the view covers, safe-area strips included (the window for a screen).
        var containerFrame: CGRect
        /// The part inside the safe area: the view's own bounds. It shrinks with the keyboard,
        /// which never moves a fold pane.
        var contentFrame: CGRect
        /// Nil when there's no fold information.
        var fold: Fold?
        var isRegularWidth: Bool
    }

    static func resolve(_ input: Input) -> FoldLayout {
        let container = input.containerFrame
        let insets = Insets(
            leading: max(0, input.contentFrame.minX - container.minX),
            trailing: max(0, container.maxX - input.contentFrame.maxX),
            top: max(0, input.contentFrame.minY - container.minY),
            bottom: max(0, container.maxY - input.contentFrame.maxY)
        )
        let whole = FoldLayout.Pane(frame: container, insets: insets)
        let content = input.contentFrame
        let single = FoldLayout(arrangement: .single, container: container, content: content, panes: [whole], band: nil, fold: nil)

        // An inactive fold only counts with regular width: closed, the inner display's fold can
        // still be reported, and must not split the outer screen.
        if let fold = input.fold, fold.isActive || input.isRegularWidth {
            if fold.isVertical {
                let minX = min(max(fold.rect.minX, container.minX), container.maxX)
                let maxX = min(max(fold.rect.maxX, minX), container.maxX)
                guard minX > container.minX, maxX < container.maxX else { return single.with(fold: fold) }
                return sideBySide(container: container, content: content, insets: insets, bandMinX: minX, bandMaxX: maxX, fold: fold)
            }
            let minY = min(max(fold.rect.minY, container.minY), container.maxY)
            let maxY = min(max(fold.rect.maxY, minY), container.maxY)
            guard minY > container.minY, maxY < container.maxY else { return single.with(fold: fold) }
            let band = CGRect(x: container.minX, y: minY, width: container.width, height: maxY - minY)
            let top = FoldLayout.Pane(
                frame: CGRect(x: container.minX, y: container.minY, width: container.width, height: minY - container.minY),
                insets: Insets(leading: insets.leading, trailing: insets.trailing, top: insets.top, bottom: 0))
            let bottom = FoldLayout.Pane(
                frame: CGRect(x: container.minX, y: maxY, width: container.width, height: container.maxY - maxY),
                insets: Insets(leading: insets.leading, trailing: insets.trailing, top: 0, bottom: insets.bottom))
            return FoldLayout(arrangement: .stacked, container: container, content: content, panes: [top, bottom], band: band, fold: fold)
        }
        guard input.fold == nil else { return single }
        // No fold information: a regular-width window that's wider than tall splits at the centre
        // of the whole window (the screen), never of its safe area.
        guard input.isRegularWidth, container.width > container.height else { return single }
        let half = fallbackFoldBandWidth / 2
        return sideBySide(container: container, content: content, insets: insets,
                          bandMinX: container.midX - half, bandMaxX: container.midX + half, fold: nil)
    }

    private static func sideBySide(container: CGRect, content: CGRect, insets: Insets, bandMinX: CGFloat,
                                   bandMaxX: CGFloat, fold: Fold?) -> FoldLayout {
        let band = CGRect(x: bandMinX, y: container.minY, width: bandMaxX - bandMinX, height: container.height)
        let leading = FoldLayout.Pane(
            frame: CGRect(x: container.minX, y: container.minY, width: bandMinX - container.minX, height: container.height),
            insets: Insets(leading: insets.leading, trailing: 0, top: insets.top, bottom: insets.bottom))
        let trailing = FoldLayout.Pane(
            frame: CGRect(x: bandMaxX, y: container.minY, width: container.maxX - bandMaxX, height: container.height),
            insets: Insets(leading: 0, trailing: insets.trailing, top: insets.top, bottom: insets.bottom))
        return FoldLayout(arrangement: .sideBySide, container: container, content: content, panes: [leading, trailing],
                          band: band, fold: fold)
    }

    /// Safe-area strips inside a pane (the vertical action bar is the trailing strip).
    struct Insets: Equatable, Sendable {
        var leading: CGFloat = 0
        var trailing: CGFloat = 0
        var top: CGFloat = 0
        var bottom: CGFloat = 0
    }
}

/// A screen's division by the fold (`FoldLayoutResolver`).
struct FoldLayout: Equatable, Sendable {
    enum Arrangement: Equatable, Sendable {
        case single
        case sideBySide
        case stacked
    }

    /// One part of the screen. Its frame reaches the window's edges where it touches them; the
    /// safe-area strips inside it are its insets.
    struct Pane: Equatable, Sendable {
        var frame: CGRect
        var insets: FoldLayoutResolver.Insets

        /// The part content may use: the frame minus its safe-area strips.
        var safeFrame: CGRect {
            CGRect(x: frame.minX + insets.leading, y: frame.minY + insets.top,
                   width: max(0, frame.width - insets.leading - insets.trailing),
                   height: max(0, frame.height - insets.top - insets.bottom))
        }

        /// Horizontal content margins for a list filling this pane, measured from the pane's edges:
        /// the safe-area strip (action bar included) plus the standard margin, or more to keep a
        /// readable width.
        func listMargins(margin: CGFloat = AdaptiveLayout.minimumMargin, readableWidth: CGFloat? = AdaptiveLayout.readableWidth)
            -> (leading: CGFloat, trailing: CGFloat) {
            var side = margin
            if let readableWidth {
                side = max(margin, (safeFrame.width - readableWidth) / 2)
            }
            return (insets.leading + side, insets.trailing + side)
        }

        /// Where a list's cards and rows go with `listMargins`.
        func contentFrame(margin: CGFloat = AdaptiveLayout.minimumMargin, readableWidth: CGFloat? = AdaptiveLayout.readableWidth) -> CGRect {
            let margins = listMargins(margin: margin, readableWidth: readableWidth)
            return CGRect(x: frame.minX + margins.leading, y: safeFrame.minY,
                          width: max(0, frame.width - margins.leading - margins.trailing), height: safeFrame.height)
        }
    }

    var arrangement: Arrangement
    /// The whole area, in the measured view's coordinates.
    var container: CGRect
    /// The measured view's own bounds (inside the safe area).
    var content: CGRect
    /// `[whole]`, `[leading, trailing]` or `[top, bottom]`.
    var panes: [Pane]
    /// Where nothing but the background goes. Nil when nothing splits the view.
    var band: CGRect?
    /// The fold this layout is based on, if any (it may not split the view).
    var fold: FoldLayoutResolver.Fold?

    /// The leading, top or only pane.
    var primary: Pane { panes[0] }
    /// The trailing or bottom pane.
    var secondary: Pane? { panes.count > 1 ? panes[1] : nil }
    var isSplit: Bool { arrangement != .single }
    var isStacked: Bool { arrangement == .stacked }

    /// Where a screen without a two-pane design puts its one column: the leading pane side by
    /// side, the top pane stacked (the keyboard has the bottom), otherwise the whole view.
    var columnPane: Pane { primary }

    /// Where the search field and the results go: with the fold side to side, the top pane, so
    /// the keyboard has the bottom one. Its size comes from the window and the fold only, never
    /// from the keyboard.
    func searchPane(isSearching: Bool) -> Pane {
        columnPane
    }

    /// The band in window points (relative to the container's corner), e.g. for floating Mochi.
    var bandInContainer: CGRect? {
        band?.offsetBy(dx: -container.minX, dy: -container.minY)
    }

    fileprivate func with(fold: FoldLayoutResolver.Fold) -> FoldLayout {
        var layout = self
        layout.fold = fold
        return layout
    }
}

/// What a fold-aware view measures about itself: its full area, the safe part and the fold, in its
/// own coordinate space (origin at the safe area's top-left corner).
struct FoldGeometry: Equatable, Sendable {
    /// The whole area the view covers, safe-area strips included.
    var containerFrame = CGRect.zero
    /// The view's own bounds (inside the safe area).
    var contentFrame = CGRect.zero
    /// iOS 27.1's division region, used as reported: it's already in this coordinate space.
    var fold: FoldLayoutResolver.Fold?

    var sizeKey: FoldMemory.SizeKey { .init(width: containerFrame.width, height: containerFrame.height) }

    /// A view whose content extends under the safe area (a `List`, or a container of lists)
    /// reports a frame that's already inside the safe area, plus the strips around it as insets
    /// (`AdaptiveLayout.contentWidth`), so its full area is its bounds grown by the insets: never
    /// the midpoint of the safe area. Insets, not positions, so push and pop animations can't
    /// change it. The fold is read even while inactive (Open flat) and on every geometry change,
    /// because it can arrive a few layout passes late.
    nonisolated static func read(_ proxy: GeometryProxy) -> FoldGeometry {
        let insets = proxy.safeAreaInsets
        var geometry = FoldGeometry(
            containerFrame: CGRect(x: -insets.leading, y: -insets.top,
                                   width: proxy.size.width + insets.leading + insets.trailing,
                                   height: proxy.size.height + insets.top + insets.bottom),
            contentFrame: CGRect(origin: .zero, size: proxy.size)
        )
        if #available(iOS 27.1, *),
           let region = proxy.reservedRegions(kind: .division, options: .includeInactive).first {
            geometry.fold = FoldLayoutResolver.Fold(rect: region.frame, isActive: region.isActive)
        }
        return geometry
    }

    /// The layout, using the fold remembered for this size when none is reported now.
    @MainActor
    func layout(isRegularWidth: Bool) -> FoldLayout {
        FoldLayoutResolver.resolve(.init(containerFrame: containerFrame, contentFrame: contentFrame,
                                         fold: fold ?? FoldMemory.shared.fold(for: self), isRegularWidth: isRegularWidth))
    }
}

/// The fold last reported for each window (or sheet) size, relative to its corner, so a pose that
/// reports none for that size (possibly Open flat) keeps the split where the fold really is.
/// Memory only.
@MainActor
final class FoldMemory {
    static let shared = FoldMemory()

    struct SizeKey: Hashable, Sendable {
        var width: CGFloat
        var height: CGFloat
    }

    private var folds: [SizeKey: CGRect] = [:]

    func remember(_ geometry: FoldGeometry) {
        guard let fold = geometry.fold else { return }
        let corner = geometry.containerFrame.origin
        folds[geometry.sizeKey] = fold.rect.offsetBy(dx: -corner.x, dy: -corner.y)
    }

    func fold(for geometry: FoldGeometry) -> FoldLayoutResolver.Fold? {
        guard let rect = folds[geometry.sizeKey] else { return nil }
        let corner = geometry.containerFrame.origin
        return .init(rect: rect.offsetBy(dx: corner.x, dy: corner.y), isActive: false)
    }
}
