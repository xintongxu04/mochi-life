import SwiftUI

extension View {
    /// Sets a List/Form row's separator explicitly instead of letting SwiftUI infer it from the
    /// row's text. Inference goes wrong when a row starts with a non-text element: a row that
    /// starts with a `TextField` takes its separator start from the next `Text` (a unit or hint
    /// partway across), and an icon `Label` inside a row moves it past the icon. Either way that
    /// row's separator doesn't line up with the others.
    ///
    /// - Parameter leading: where the separator starts, from the row content's leading edge: 0
    ///   for plain rows, or the text column (e.g. after a thumbnail) for rows with a picture.
    ///   It runs to the row's trailing edge.
    func rowSeparatorAligned(leading: CGFloat = 0) -> some View {
        alignmentGuide(.listRowSeparatorLeading) { _ in leading }
            .alignmentGuide(.listRowSeparatorTrailing) { dimensions in dimensions[.trailing] }
    }
}

/// Separator start for rows with a 44 pt thumbnail and 12 pt spacing before their text.
let thumbnailRowSeparatorLeading: CGFloat = 44 + 12
