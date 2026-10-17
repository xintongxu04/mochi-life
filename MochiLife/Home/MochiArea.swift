import SwiftUI

/// Where the Calories screen's toolbar sits, measured inside the navigation stack and shared
/// with Mochi's layer (which is outside it). Window points.
struct ToolbarPlacement: Equatable, Sendable {
    /// The Calories content's left and right safe-area insets. A toolbar placed vertically at the
    /// side (iPhone Duo's outer display, turned) makes one larger than the window's own. Insets,
    /// not positions, so a push or pop animation can't change them.
    var leadingInset: CGFloat = 0
    var trailingInset: CGFloat = 0
    /// The bars are vertical (iOS 27.1 `toolbarVerticalEdge`), so there's no button row on top.
    var isVertical = false
}

/// The part of the window Mochi and her ring may use. Pure geometry in window points (the
/// full-screen root layer), no views.
///
/// It's the window inside the safe area, minus the toolbar (the button row on top, or the strip
/// at the side when bars are vertical); Mochi and her ring also keep out of every active reserved
/// region (iPhone Duo's division band and its camera and status occlusions). It depends only on
/// the window, its configuration and the toolbar's place, never on scrolling.
struct MochiArea: Equatable, Sendable {
    /// Inside the safe area and outside the toolbar.
    var usable: CGRect
    /// Active reserved regions that reach into `usable`.
    var obstacles: [CGRect]
    var spriteSize: CGSize

    /// Height of the standard inline navigation bar: the row holding the toolbar buttons.
    static let toolbarRowHeight: CGFloat = 44
    /// Gap below the toolbar button row (or the safe area, when bars are vertical).
    static let toolbarRowGap: CGFloat = 4
    /// Mochi stays this far inside the sides and bottom; the ring uses `menuMargin`.
    static let spriteInset: CGFloat = 8
    static let menuMargin: CGFloat = 4
    static let defaultEdgeDistance: CGFloat = 16

    /// `foldBand` is the Calories layout's fold band (`MochiHome.calorieFoldBand`), which she
    /// avoids even when the system marks the fold inactive (iPhone Duo open flat) or the layout
    /// falls back to the midpoint.
    init(window: CGSize, safeArea: EdgeInsets, toolbar: ToolbarPlacement, reserved: [CGRect], foldBand: CGRect? = nil,
         spriteSize: CGSize) {
        // The top is a constant: just below the toolbar button row, or the safe area when the
        // bars are at the side. It never follows the large title as it collapses.
        let top = safeArea.top + (toolbar.isVertical ? 0 : Self.toolbarRowHeight) + Self.toolbarRowGap
        let minX = max(safeArea.leading, toolbar.leadingInset)
        let maxX = window.width - max(safeArea.trailing, toolbar.trailingInset)
        let bottom = window.height - safeArea.bottom
        let usable = CGRect(x: minX, y: top, width: max(0, maxX - minX), height: max(0, bottom - top))
        self.usable = usable
        self.obstacles = (reserved + [foldBand].compactMap(\.self)).filter { $0.intersects(usable) }
        self.spriteSize = spriteSize
    }

    /// Where her top-left corner may go, before obstacles.
    var spriteRegion: CGRect {
        let minX = usable.minX + Self.spriteInset
        let minY = usable.minY
        let maxX = max(minX, usable.maxX - Self.spriteInset - spriteSize.width)
        let maxY = max(minY, usable.maxY - Self.spriteInset - spriteSize.height)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Her top-left corner moved inside the region and clear of every obstacle. If an obstacle
    /// is in the way (the division band, say) she moves to its nearer side.
    func resolve(_ point: CGPoint) -> CGPoint {
        let region = spriteRegion
        var point = clamp(point, in: region)
        // A few passes settle the rare case where moving off one obstacle lands on another.
        for _ in 0..<4 {
            guard let obstacle = obstacles.first(where: { $0.intersects(rect(at: point)) }) else { break }
            let moves = [
                CGPoint(x: obstacle.minX - spriteSize.width, y: point.y),
                CGPoint(x: obstacle.maxX, y: point.y),
                CGPoint(x: point.x, y: obstacle.minY - spriteSize.height),
                CGPoint(x: point.x, y: obstacle.maxY),
            ].filter { isInside($0, region) }
            guard let nearest = moves.min(by: { distance($0, point) < distance($1, point) }) else { break }
            point = nearest
        }
        return point
    }

    /// Bottom-trailing, 16 pt from the edges, outside reserved regions.
    var defaultOrigin: CGPoint {
        let region = spriteRegion
        let edgeShift = Self.defaultEdgeDistance - Self.spriteInset
        return resolve(CGPoint(x: region.maxX - edgeShift, y: region.maxY - edgeShift))
    }

    /// Her position as fractions (0…1) of the region, saved per display configuration.
    func fraction(of point: CGPoint) -> CGPoint {
        let region = spriteRegion
        return CGPoint(x: region.width > 0 ? (point.x - region.minX) / region.width : 0,
                       y: region.height > 0 ? (point.y - region.minY) / region.height : 0)
    }

    func point(fromFraction fraction: CGPoint) -> CGPoint {
        let region = spriteRegion
        return resolve(CGPoint(x: region.minX + min(max(fraction.x, 0), 1) * region.width,
                               y: region.minY + min(max(fraction.y, 0), 1) * region.height))
    }

    /// The ring's bounds around Mochi's centre: the usable area with a 4 pt margin (the top stays
    /// just below the toolbar), trimmed to her side of any band that runs right across it, so the
    /// division band counts as an edge for the near-edge test.
    func menuBounds(around center: CGPoint) -> CGRect {
        var bounds = CGRect(x: usable.minX + Self.menuMargin, y: usable.minY,
                            width: max(0, usable.width - 2 * Self.menuMargin),
                            height: max(0, usable.height - Self.menuMargin))
        for obstacle in obstacles {
            if obstacle.minY <= bounds.minY, obstacle.maxY >= bounds.maxY {
                if center.x < obstacle.midX {
                    bounds.size.width = max(0, min(bounds.maxX, obstacle.minX) - bounds.minX)
                } else {
                    let minX = max(bounds.minX, obstacle.maxX)
                    bounds = CGRect(x: minX, y: bounds.minY, width: max(0, bounds.maxX - minX), height: bounds.height)
                }
            } else if obstacle.minX <= bounds.minX, obstacle.maxX >= bounds.maxX {
                if center.y < obstacle.midY {
                    bounds.size.height = max(0, min(bounds.maxY, obstacle.minY) - bounds.minY)
                } else {
                    let minY = max(bounds.minY, obstacle.maxY)
                    bounds = CGRect(x: bounds.minX, y: minY, width: bounds.width, height: max(0, bounds.maxY - minY))
                }
            }
        }
        return bounds
    }

    // MARK: - Helpers

    private func rect(at origin: CGPoint) -> CGRect {
        CGRect(origin: origin, size: spriteSize)
    }

    /// Inclusive of the right and bottom edges (unlike `CGRect.contains`).
    private func isInside(_ point: CGPoint, _ region: CGRect) -> Bool {
        point.x >= region.minX && point.x <= region.maxX && point.y >= region.minY && point.y <= region.maxY
    }

    private func clamp(_ point: CGPoint, in region: CGRect) -> CGPoint {
        CGPoint(x: min(max(point.x, region.minX), region.maxX), y: min(max(point.y, region.minY), region.maxY))
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
