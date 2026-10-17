import CoreGraphics
import Testing
@testable import MochiLife

/// The Calories screen's layout decision for iPhone Duo's poses and ordinary iPhones. Rects are in
/// the screen root's coordinate space (origin at the safe area's top-left corner), as the app
/// measures them. The sizes are the iPhone Duo simulator's (iOS 27.1) as measured on 2026-10-16;
/// the app itself only uses sizes measured at runtime.
struct CaloriesLayoutResolverTests {
    private let margin: CGFloat = 20

    /// iPhone Duo open: a 951 × 669 window with the 84 pt action bar at the trailing edge, 82 pt
    /// of bars at the top and 34 pt at the bottom.
    private let open = Geometry(window: CGSize(width: 951, height: 669), leading: 0, top: 82, trailing: 84, bottom: 34)
    /// The division region as reported in Book pose (margins included), in root coordinates.
    private let bookFold = CGRect(x: 455.5, y: -82, width: 40, height: 669)

    /// A window and its safe-area insets, as the root sees them.
    struct Geometry {
        var window: CGSize
        var leading: CGFloat
        var top: CGFloat
        var trailing: CGFloat
        var bottom: CGFloat

        var container: CGRect { CGRect(x: -leading, y: -top, width: window.width, height: window.height) }
        var content: CGRect {
            CGRect(x: 0, y: 0, width: window.width - leading - trailing, height: window.height - top - bottom)
        }
    }

    private func resolve(_ geometry: Geometry, fold: CaloriesLayoutResolver.Fold?, regular: Bool) -> CaloriesLayout {
        CaloriesLayoutResolver.resolve(.init(containerFrame: geometry.container, contentFrame: geometry.content,
                                             fold: fold, isRegularWidth: regular, margin: margin))
    }

    private func split(_ layout: CaloriesLayout) throws -> CaloriesLayout.Split {
        guard case let .split(split) = layout else { return try #require(nil as CaloriesLayout.Split?, "Expected a split, got \(layout)") }
        return split
    }

    /// Nothing that holds content reaches into the fold band.
    private func expectNothingInBand(_ split: CaloriesLayout.Split) {
        #expect(split.leadingContent.maxX <= split.foldBand.minX)
        #expect(split.trailingContent.minX >= split.foldBand.maxX)
        #expect(!split.leadingContent.intersects(split.foldBand))
        #expect(!split.trailingContent.intersects(split.foldBand))
    }

    @Test(arguments: [true, false])
    func bookAndOpenSplitAtTheFold(foldIsActive: Bool) throws {
        let split = try split(resolve(open, fold: .init(rect: bookFold, isActive: foldIsActive), regular: true))

        // The panes meet the fold band exactly and span the whole window.
        #expect(split.leading.maxX == bookFold.minX)
        #expect(split.trailing.minX == bookFold.maxX)
        #expect(split.foldBand.minX == bookFold.minX)
        #expect(split.foldBand.width == bookFold.width)
        #expect(split.leading.minX == open.container.minX)
        #expect(split.trailing.maxX == open.container.maxX)
        expectNothingInBand(split)
        // The standard margin from the band; the trailing pane's margins also clear the bar.
        #expect(split.leadingMargins == .init(leading: margin, trailing: margin))
        #expect(split.trailingMargins == .init(leading: margin, trailing: open.trailing + margin))
        // The trailing cards are the pane minus the action bar minus the margins: narrower.
        #expect(split.trailingContentWidth == split.trailing.width - open.trailing - 2 * margin)
        #expect(split.trailingContentWidth < split.leadingContentWidth)
    }

    @Test func splitFollowsTheFoldNotTheMidpointWithUnequalInsets() throws {
        // A 30 pt leading inset as well as the action bar: the safe area's midpoint is far from
        // the window's, and the fold here is off both.
        let geometry = Geometry(window: CGSize(width: 951, height: 669), leading: 30, top: 82, trailing: 84, bottom: 34)
        let fold = CGRect(x: 420, y: -82, width: 40, height: 669)
        #expect(fold.midX != geometry.content.midX)
        #expect(fold.midX != geometry.container.midX)

        let split = try split(resolve(geometry, fold: .init(rect: fold, isActive: true), regular: true))
        #expect(split.foldBand.minX == fold.minX)
        #expect(split.foldBand.maxX == fold.maxX)
        #expect(split.leadingMargins.leading == geometry.leading + margin)
        expectNothingInBand(split)
    }

    @Test func bookAndOpenGiveTheSameSplitForTheSameScreen() throws {
        // Book reports an active fold; Open may report it inactive, or (with the root's memory of
        // the last fold for this size) the same rect; with nothing at all the full-window centre
        // is used, which is where iPhone Duo's fold is.
        let book = try split(resolve(open, fold: .init(rect: bookFold, isActive: true), regular: true))
        let openInactive = try split(resolve(open, fold: .init(rect: bookFold, isActive: false), regular: true))
        let openNoFold = try split(resolve(open, fold: nil, regular: true))

        #expect(openInactive == book)
        #expect(openNoFold.foldBand.midX == book.foldBand.midX)
        #expect(openNoFold.leading.maxX == book.leading.maxX)
        #expect(openNoFold.trailing.minX == book.trailing.minX)
    }

    @Test func fallbackUsesTheFullWindowCentreInRootCoordinates() throws {
        let geometry = Geometry(window: CGSize(width: 951, height: 669), leading: 30, top: 82, trailing: 84, bottom: 34)
        let split = try split(resolve(geometry, fold: nil, regular: true))
        let band = CaloriesLayoutResolver.fallbackFoldBandWidth

        // The window's centre (475.5 from its leading edge) in root coordinates, not the safe
        // area's centre.
        #expect(split.foldBand.midX == geometry.container.midX)
        #expect(split.foldBand.midX == 475.5 - geometry.leading)
        #expect(split.foldBand.midX != geometry.content.midX)
        #expect(split.foldBand.width == band)
        expectNothingInBand(split)
    }

    @Test func closedIsOneFullWidthColumn() {
        let closed = Geometry(window: CGSize(width: 466, height: 678), leading: 0, top: 62, trailing: 84, bottom: 34)
        let layout = resolve(closed, fold: nil, regular: false)
        #expect(layout == .singleColumn(contentWidth: 466 - 84, fold: nil))
        #expect(layout.foldBand == nil)
    }

    @Test func ordinaryIPhoneIsOneFullWidthColumn() {
        let phone = Geometry(window: CGSize(width: 402, height: 874), leading: 0, top: 62, trailing: 0, bottom: 34)
        #expect(resolve(phone, fold: nil, regular: false) == .singleColumn(contentWidth: 402, fold: nil))
    }

    @Test(arguments: [true, false])
    func rotatedIsOneFullWidthColumn(foldIsActive: Bool) {
        let rotated = Geometry(window: CGSize(width: 669, height: 951), leading: 0, top: 62, trailing: 0, bottom: 34)
        let fold = CaloriesLayoutResolver.Fold(rect: CGRect(x: 0, y: 393.5, width: 669, height: 40), isActive: foldIsActive)
        let layout = resolve(rotated, fold: fold, regular: true)

        #expect(layout == .singleColumn(contentWidth: 669, fold: fold))
        // Mochi still keeps out of the band; an active band keeps content above and below it.
        #expect(layout.foldBand == fold.rect)
        #expect(layout.stacksAroundFold == foldIsActive)
    }

    @Test func noFoldInformationOnATallWindowStaysOneColumn() {
        let rotated = Geometry(window: CGSize(width: 669, height: 951), leading: 0, top: 62, trailing: 0, bottom: 34)
        #expect(resolve(rotated, fold: nil, regular: true) == .singleColumn(contentWidth: 669, fold: nil))
    }

    @Test func compactWidthNeverSplits() {
        guard case .singleColumn = resolve(open, fold: .init(rect: bookFold, isActive: true), regular: false) else {
            Issue.record("Compact width must stay one column")
            return
        }
    }
}
