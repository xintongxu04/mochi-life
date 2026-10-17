import CoreGraphics
import Testing
@testable import MochiLife

/// The Calories screen's layout decision for iPhone Duo's poses and ordinary iPhones. The sizes
/// are the iPhone Duo simulator's (iOS 27.1) as measured on 2026-10-16; the app itself only uses
/// sizes measured at runtime.
struct CaloriesLayoutResolverTests {
    private let margin: CGFloat = 20
    /// The vertical action bar with its padding (the trailing safe-area inset).
    private let actionBar: CGFloat = 84
    private let openWindow = CGSize(width: 951, height: 669)
    /// The division region as reported in Book pose, margins included.
    private let verticalFold = CGRect(x: 455.5, y: 0, width: 40, height: 669)

    private func resolve(_ window: CGSize, fold: CaloriesLayoutResolver.Fold?, regular: Bool,
                         actionBar: CGFloat = 0) -> CaloriesLayout {
        CaloriesLayoutResolver.resolve(.init(windowSize: window, fold: fold, isRegularWidth: regular,
                                             leadingInset: 0, actionBarWidth: actionBar, margin: margin))
    }

    private func split(_ layout: CaloriesLayout) throws -> CaloriesLayout.Split {
        guard case let .split(split) = layout else { return try #require(nil as CaloriesLayout.Split?, "Expected a split, got \(layout)") }
        return split
    }

    @Test(arguments: [true, false])
    func bookAndOpenSplitAtTheFold(foldIsActive: Bool) throws {
        let fold = CaloriesLayoutResolver.Fold(rect: verticalFold, isActive: foldIsActive)
        let split = try split(resolve(openWindow, fold: fold, regular: true, actionBar: actionBar))

        // The panes meet the fold band exactly, and nothing is in it.
        #expect(split.leading.maxX == verticalFold.minX)
        #expect(split.trailing.minX == verticalFold.maxX)
        #expect(split.foldBand == verticalFold)
        #expect(split.leading.minX == 0)
        #expect(split.trailing.maxX == openWindow.width)
        // Margins: the standard margin from the band; the trailing pane's also clear the bar.
        #expect(split.leadingMargins == .init(leading: margin, trailing: margin))
        #expect(split.trailingMargins == .init(leading: margin, trailing: actionBar + margin))
        // The trailing cards are the pane minus the action bar minus the margins: narrower.
        #expect(split.trailingContentWidth == split.trailing.width - actionBar - 2 * margin)
        #expect(split.leadingContentWidth == split.leading.width - 2 * margin)
        #expect(split.trailingContentWidth < split.leadingContentWidth)
    }

    @Test func closedIsOneFullWidthColumn() {
        let layout = resolve(CGSize(width: 466, height: 678), fold: nil, regular: false, actionBar: actionBar)
        #expect(layout == .singleColumn(contentWidth: 466 - actionBar, fold: nil))
        #expect(layout.foldBand == nil)
    }

    @Test func ordinaryIPhoneIsOneFullWidthColumn() {
        #expect(resolve(CGSize(width: 402, height: 874), fold: nil, regular: false)
            == .singleColumn(contentWidth: 402, fold: nil))
    }

    @Test(arguments: [true, false])
    func rotatedIsOneFullWidthColumn(foldIsActive: Bool) {
        let window = CGSize(width: 669, height: 951)
        let fold = CaloriesLayoutResolver.Fold(rect: CGRect(x: 0, y: 455.5, width: 669, height: 40), isActive: foldIsActive)
        let layout = resolve(window, fold: fold, regular: true)

        #expect(layout == .singleColumn(contentWidth: 669, fold: fold))
        // Mochi still keeps out of the band; an active band keeps content above and below it.
        #expect(layout.foldBand == fold.rect)
        #expect(layout.stacksAroundFold == foldIsActive)
    }

    @Test func noFoldInformationSplitsAtTheMidpoint() throws {
        let split = try split(resolve(openWindow, fold: nil, regular: true, actionBar: actionBar))
        let band = CaloriesLayoutResolver.fallbackFoldBandWidth

        #expect(split.foldBand.width == band)
        #expect(split.foldBand.midX == openWindow.width / 2)
        #expect(split.leading.maxX == (openWindow.width - band) / 2)
        #expect(split.trailingContentWidth < split.leadingContentWidth)
    }

    @Test func noFoldInformationOnATallWindowStaysOneColumn() {
        #expect(resolve(CGSize(width: 669, height: 951), fold: nil, regular: true)
            == .singleColumn(contentWidth: 669, fold: nil))
    }

    @Test func compactWidthNeverSplits() {
        let fold = CaloriesLayoutResolver.Fold(rect: verticalFold, isActive: true)
        guard case .singleColumn = resolve(openWindow, fold: fold, regular: false) else {
            Issue.record("Compact width must stay one column")
            return
        }
    }
}
