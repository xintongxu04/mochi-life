import CryptoKit
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Photos the app saves for foods (from "Add with AI" or chosen by the owner), stored as small
/// JPEG files in Application Support/FoodThumbnails. They use the same size and format as the
/// bundled product photos: at most 200 px on the long edge, JPEG.
///
/// Each food has one file, named from the food's stable identifier, and the food stores only the
/// relative key "user/<name>" (never a path). Replacing a photo overwrites that file, so log
/// entries for the food show its current photo; removing the photo or deleting the food deletes
/// the file. Bundled photos are never touched.
enum FoodThumbnailStore {
    static let keyPrefix = "user/"
    /// Stored in `Food.thumbnailKey` when the owner removed the photo: show the placeholder,
    /// even for a seeded food that has a bundled photo.
    static let noPhotoKey = "none"
    static let longEdge = 200
    static let jpegQuality = 0.72

    static let directory = URL.applicationSupportDirectory.appending(path: "FoodThumbnails", directoryHint: .isDirectory)
    nonisolated(unsafe) private static let cache = NSCache<NSString, UIImage>()

    static func isStoredKey(_ key: String) -> Bool { key.hasPrefix(keyPrefix) }

    /// "food-abc.jpg" for "user/food-abc"; nil for bundled keys or unsafe names.
    static func fileName(forKey key: String) -> String? {
        fileURL(forKey: key)?.lastPathComponent
    }

    /// Forgets cached images after files change outside `setPhoto` (a restore).
    @MainActor
    static func invalidateCache() {
        cache.removeAllObjects()
        ThumbnailRevision.shared.bump()
    }

    static func image(forKey key: String) -> UIImage? {
        if let cached = cache.object(forKey: key as NSString) { return cached }
        guard let url = fileURL(forKey: key), let image = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(image, forKey: key as NSString)
        return image
    }

    /// Writes the photo (already shrunk JPEG) to the food's own file, atomically, and points the
    /// food at it. Deletes the food's previous photo file if it had a different name.
    @MainActor
    static func setPhoto(_ jpegData: Data, for food: Food) throws {
        let key = keyPrefix + stableName(for: food)
        guard let url = fileURL(forKey: key) else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try jpegData.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        if let old = food.thumbnailKey, old != key { deleteFile(forKey: old) }
        food.thumbnailKey = key
        cache.removeObject(forKey: key as NSString)
        ThumbnailRevision.shared.bump()
    }

    /// Removes the food's photo file. `showPlaceholder` hides a bundled photo too (used by
    /// Remove); otherwise a seeded food goes back to its bundled photo (Reset to original).
    @MainActor
    static func removePhoto(for food: Food, showPlaceholder: Bool) {
        if let key = food.thumbnailKey { deleteFile(forKey: key) }
        food.thumbnailKey = showPlaceholder && food.seedID != nil ? noPhotoKey : nil
        ThumbnailRevision.shared.bump()
    }

    /// Deletes a saved photo file (never a bundled photo).
    static func deleteFile(forKey key: String) {
        guard let url = fileURL(forKey: key) else { return }
        try? FileManager.default.removeItem(at: url)
        cache.removeObject(forKey: key as NSString)
    }

    /// A file name derived from the food's stable identifier: its seed ID for seeded foods,
    /// otherwise a hash of SwiftData's persistent identifier (stable once the food is saved).
    @MainActor
    static func stableName(for food: Food) -> String {
        if let seedID = food.seedID {
            let safe = seedID.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || $0 == "-" ? String($0) : "_" }.joined()
            return "seed-\(safe)"
        }
        let encoded = (try? JSONEncoder().encode(food.persistentModelID)) ?? Data(UUID().uuidString.utf8)
        let digest = SHA256.hash(data: encoded).map { String(format: "%02x", $0) }.joined()
        return "food-\(digest.prefix(24))"
    }

    private static func fileURL(forKey key: String) -> URL? {
        guard isStoredKey(key) else { return nil }
        let name = key.dropFirst(keyPrefix.count)
        guard !name.isEmpty, !name.contains("/"), !name.contains("..") else { return nil }
        return directory.appending(path: "\(name).jpg")
    }

    /// Shrinks any image data to the thumbnail size and format. Runs on the caller's thread;
    /// call it off the main actor for large images.
    static func thumbnailJPEG(from imageData: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longEdge,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}

/// Bumped whenever a saved photo changes, so thumbnails redraw even when the key is the same.
@MainActor
@Observable
final class ThumbnailRevision {
    static let shared = ThumbnailRevision()
    private(set) var value = 0

    func bump() { value += 1 }
}
