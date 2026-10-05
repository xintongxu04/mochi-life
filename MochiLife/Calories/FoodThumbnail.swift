import SwiftUI
import UIKit

/// The one thumbnail for foods, log entries and schedules everywhere: the product photo
/// (bundled or saved by the app) on a white rounded tile, or else the pixel-art picture for its
/// kind with no box at all (the row shows through its transparent pixels), in the same frame so
/// text columns line up.
struct FoodThumbnail: View {
    /// The library food the photo belongs to; nil for foods without one.
    let libraryIdentifier: String?
    let size: CGFloat
    /// Picks the default picture when there's no photo.
    let kind: FoodKind

    /// Padding around the default picture, as a fraction of the size.
    static let defaultImageInset: CGFloat = 0.04

    /// Set when showing a saved food, so its photo is resolved fresh on every draw.
    private var food: Food?

    init(food: Food, size: CGFloat) {
        self.libraryIdentifier = food.photoKey
        self.size = size
        self.kind = food.kind
        self.food = food
    }

    /// - Parameter libraryIdentifier: A seed ID, or an older "<library>/<name>" identifier
    ///   (log entries saved before seed IDs existed keep that form).
    init(libraryIdentifier: String?, kind: FoodKind, size: CGFloat) {
        self.libraryIdentifier = libraryIdentifier
        self.kind = kind
        self.size = size
    }

    var body: some View {
        Group {
            if let image = resolvedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .background(.white)
                    .frame(width: size, height: size)
                    .clipShape(.rect(cornerRadius: size * 0.18))
            } else {
                FoodKindImage(kind: kind, size: size)
            }
        }
        .accessibilityHidden(true)
    }

    private var resolvedImage: UIImage? {
        // Reading the revision redraws this view when a saved photo is replaced in place.
        _ = ThumbnailRevision.shared.value
        if let food { return FoodThumbnails.image(for: food) }
        return FoodThumbnails.image(forLibraryIdentifier: libraryIdentifier)
    }
}

/// A kind's pixel-art default picture with no background, border or clipping: crisp pixels
/// (`.interpolation(.none)`), scaled to fit `size` with 4% padding.
struct FoodKindImage: View {
    let kind: FoodKind
    let size: CGFloat

    var body: some View {
        Image(kind.defaultImageName)
            .resizable()
            .interpolation(.none)
            .scaledToFit()
            .padding(size * FoodThumbnail.defaultImageInset)
            .frame(width: size, height: size)
    }
}

/// Looks up bundled product photos. A small file maps each product's seed ID (and its older
/// "<library>/<name>" identifier) to its picture, so a food keeps its photo even if renamed.
enum FoodThumbnails {
    private static let bundledLists = ["tiki-cat-thumbnails"]

    private static let fileNames: [String: String] = {
        var names: [String: String] = [:]
        for list in bundledLists {
            guard let url = Bundle.main.url(forResource: list, withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let entries = try? JSONDecoder().decode([String: String].self, from: data)
            else { continue }
            names.merge(entries) { current, _ in current }
        }
        return names
    }()

    /// Resolution order: the food's saved photo file, else its bundled photo, else nil
    /// (placeholder). A food whose photo was removed shows the placeholder.
    static func image(for food: Food) -> UIImage? {
        if food.thumbnailKey == FoodThumbnailStore.noPhotoKey { return nil }
        if let key = food.thumbnailKey, let image = FoodThumbnailStore.image(forKey: key) { return image }
        return [food.seedID, food.libraryIdentifier].lazy.compactMap { $0 }
            .compactMap { image(forLibraryIdentifier: $0) }.first
    }

    /// The bundled photo for a seeded food, ignoring any saved replacement.
    static func bundledImage(for food: Food) -> UIImage? {
        [food.seedID, food.libraryIdentifier].lazy.compactMap { $0 }
            .compactMap { image(forLibraryIdentifier: $0) }.first
    }

    static func image(forLibraryIdentifier identifier: String?) -> UIImage? {
        guard let identifier, identifier != FoodThumbnailStore.noPhotoKey else { return nil }
        if FoodThumbnailStore.isStoredKey(identifier) {
            return FoodThumbnailStore.image(forKey: identifier)
        }
        guard let fileName = fileNames[identifier] else { return nil }
        return UIImage(named: fileName)
    }
}
