import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Photos the app saves for foods (from "Add with AI" or chosen by the owner), stored as small
/// JPEG files in Application Support/FoodThumbnails. They use the same size and format as the
/// bundled product photos: at most 200 px on the long edge, JPEG.
///
/// Files are never deleted when a food is, because food log entries keep pointing at them.
enum FoodThumbnailStore {
    static let keyPrefix = "user/"
    static let longEdge = 200
    static let jpegQuality = 0.72

    private static let directory = URL.applicationSupportDirectory.appending(path: "FoodThumbnails", directoryHint: .isDirectory)
    nonisolated(unsafe) private static let cache = NSCache<NSString, UIImage>()

    static func isStoredKey(_ key: String) -> Bool { key.hasPrefix(keyPrefix) }

    /// Saves JPEG data (already shrunk) and returns its key.
    static func save(_ jpegData: Data) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = UUID().uuidString
        try jpegData.write(to: directory.appending(path: "\(name).jpg"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return keyPrefix + name
    }

    static func image(forKey key: String) -> UIImage? {
        if let cached = cache.object(forKey: key as NSString) { return cached }
        let name = key.dropFirst(keyPrefix.count)
        guard !name.contains("/"), !name.contains(".."),
              let image = UIImage(contentsOfFile: directory.appending(path: "\(name).jpg").path)
        else { return nil }
        cache.setObject(image, forKey: key as NSString)
        return image
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
