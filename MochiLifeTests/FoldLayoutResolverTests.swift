import CoreGraphics
import Testing
@testable import MochiLife

/// The shared fold layout for every screen. Rects are in the measured view's coordinate space
/// (origin at the safe area's top-left corner). Sizes are the iPhone Duo simulator's (iOS 27.1) as
/// measured on 2026-10-16; the app itself only uses sizes measured at runtime.
struct FoldLayoutResolverTests {
    /// iPhone Duo open, fold top to bottom: 951 × 669 with the 84 pt action bar at the trailing
    /// edge, 82 pt of bars at the top and 34 pt at the bottom.
    private let open = Geometry(window: CGSize(width: 951, height: 669), leading: 0, top: 82, trailing: 84, bottom: 34)
    private let verticalFold = CGRect(x: 455.5, y: -82, width: 40, height: 669)

    /// iPhone Duo open and turned, fold side to side: 669 × 951.
    private let turned = Geometry(window: CGSize(width: 669, height: 951), leading: 0, top: 116, trailing: 0, bottom: 34)
    private var horizontalFold: CGRect { CGRect(x: 0, y: 455.5 - turned.top, width: 669, height: 40) }

    struct Geometry {
        var window: CGSize
        var leading: CGFloat
        var top: CGFloat
        var trailing: CGFloat
        var bottom: CGFloat
        /// Extra bottom inset from the keyboard (it shrinks the safe part, never the window).
        var keyboard: CGFloat = 0

        var container: CGRect { CGRect(x: -leading, y: -top, width: window.width, height: window.height) }
        var content: CGRect {
            CGRect(x: 0, y: 0, width: window.width - leading - trailing,
                   height: window.height - top - bottom - keyboard)
        }
    }

    private func resolve(_ geometry: Geometry, fold: FoldLayoutResolver.Fold?, regular: Bool = true) -> FoldLayout {
        FoldLayoutResolver.resolve(.init(containerFrame: geometry.container, contentFrame: geometry.content,
                                         fold: fold, isRegularWidth: regular))
    }

    /// No content (cards, rows, search field) can reach into the band.
    private func expectNothingInBand(_ layout: FoldLayout) throws {
        let band = try #require(layout.band)
        for pane in layout.panes {
            #expect(!pane.safeFrame.intersects(band))
            #expect(!pane.contentFrame().intersects(band))
        }
    }

    @Test(arguments: [true, false])
    func sideBySidePanesMeetAtTheFold(foldIsActive: Bool) throws {
        let layout = resolve(open, fold: .init(rect: verticalFold, isActive: foldIsActive))
        let trailing = try #require(layout.secondary)

        #expect(layout.arrangement == .sideBySide)
        #expect(layout.primary.frame.minX == open.container.minX)
        #expect(layout.primary.frame.maxX == verticalFold.minX)
        #expect(trailing.frame.minX == verticalFold.maxX)
        #expect(trailing.frame.maxX == open.container.maxX)
        #expect(layout.band?.minX == verticalFold.minX)
        #expect(layout.band?.width == verticalFold.width)
        // The trailing pane holds the action bar; its content stays clear of it.
        #expect(trailing.insets.trailing == open.trailing)
        #expect(layout.primary.insets.trailing == 0)
        #expect(trailing.contentFrame().maxX == open.container.maxX - open.trailing - AdaptiveLayout.minimumMargin)
        // One column (Settings, forms, Log Food) goes in the leading pane.
        #expect(layout.columnPane == layout.primary)
        try expectNothingInBand(layout)
    }

    @Test(arguments: [true, false])
    func stackedPanesMeetAtTheFold(foldIsActive: Bool) throws {
        let layout = resolve(turned, fold: .init(rect: horizontalFold, isActive: foldIsActive))
        let bottom = try #require(layout.secondary)

        #expect(layout.arrangement == .stacked)
        #expect(layout.primary.frame.minY == turned.container.minY)
        #expect(layout.primary.frame.maxY == horizontalFold.minY)
        #expect(bottom.frame.minY == horizontalFold.maxY)
        #expect(bottom.frame.maxY == turned.container.maxY)
        #expect(layout.primary.frame.width == turned.window.width)
        #expect(bottom.frame.width == turned.window.width)
        #expect(layout.columnPane == layout.primary)
        try expectNothingInBand(layout)
    }

    @Test func searchingWithTheFoldSideToSideUsesTheTopPaneWhateverTheKeyboard() throws {
        let fold = FoldLayoutResolver.Fold(rect: horizontalFold, isActive: true)
        let withoutKeyboard = resolve(turned, fold: fold)
        var typing = turned
        typing.keyboard = 380
        let withKeyboard = resolve(typing, fold: fold)

        let searchPane = withKeyboard.searchPane(isSearching: true)
        // The search field and the results go above the fold band…
        #expect(searchPane == withKeyboard.primary)
        let band = try #require(withKeyboard.band)
        #expect(searchPane.frame.maxY <= band.minY)
        // …and the top pane is the same with or without the keyboard, so nothing jumps.
        #expect(searchPane == withoutKeyboard.searchPane(isSearching: true))
        #expect(withKeyboard.band == withoutKeyboard.band)
        try expectNothingInBand(withKeyboard)
    }

    @Test func noFoldInformationSplitsAtTheWindowCentre() throws {
        // A leading inset too, so the window's centre and the safe area's differ.
        let geometry = Geometry(window: CGSize(width: 951, height: 669), leading: 30, top: 82, trailing: 84, bottom: 34)
        let layout = resolve(geometry, fold: nil)
        let band = try #require(layout.band)

        #expect(layout.arrangement == .sideBySide)
        #expect(band.midX == geometry.container.midX)
        #expect(band.midX != geometry.content.midX)
        #expect(band.width == FoldLayoutResolver.fallbackFoldBandWidth)
        try expectNothingInBand(layout)
    }

    @Test func noFoldInformationOnATallOrCompactWindowIsOneColumn() {
        #expect(resolve(turned, fold: nil).arrangement == .single)
        let phone = Geometry(window: CGSize(width: 402, height: 874), leading: 0, top: 62, trailing: 0, bottom: 34)
        let layout = resolve(phone, fold: nil, regular: false)
        #expect(layout.arrangement == .single)
        #expect(layout.band == nil)
        #expect(layout.primary.safeFrame == phone.content)
    }

    @Test func anInactiveFoldDoesNotSplitACompactWindow() {
        // Closed, the inner display's fold may still be reported; it must not split the outer screen.
        let closed = Geometry(window: CGSize(width: 466, height: 678), leading: 0, top: 62, trailing: 84, bottom: 34)
        let layout = resolve(closed, fold: .init(rect: CGRect(x: 213, y: -62, width: 40, height: 678), isActive: false),
                             regular: false)
        #expect(layout.arrangement == .single)
    }

    @Test func aFoldOutsideTheViewDoesNotSplitIt() {
        // A sheet beside the fold: the fold is reported, but doesn't cross it.
        let sheet = Geometry(window: CGSize(width: 400, height: 600), leading: 0, top: 56, trailing: 0, bottom: 20)
        let layout = resolve(sheet, fold: .init(rect: CGRect(x: 420, y: -56, width: 40, height: 669), isActive: true))
        #expect(layout.arrangement == .single)
        #expect(layout.fold != nil)
    }
}
