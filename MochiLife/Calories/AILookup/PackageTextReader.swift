import Foundation
import ImageIO
import Vision

/// Reads the text on a photo of a food package, on this iPhone, with Vision. The photo is never
/// uploaded.
enum PackageTextReader {
    /// A line of text and how tall its letters are (fraction of the image height), since brand,
    /// line and recipe names are the largest text on a package.
    struct Line: Sendable, Equatable {
        var text: String
        var height: Double
    }

    /// Recognized lines, top to bottom. Runs off the main actor.
    static func lines(in imageData: Data) async throws -> [String] {
        try await recognizedLines(in: imageData).map(\.text)
    }

    /// Recognized lines with their letter heights, top to bottom. Runs off the main actor; the
    /// image stays in memory and is never stored or uploaded.
    static func recognizedLines(in imageData: Data) async throws -> [Line] {
        try await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else { return [] }
            // Upright and at most 2,048 px, which is plenty for package text and keeps it quick.
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048,
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return [] }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
            try Task.checkCancellation()
            return (request.results ?? [])
                .sorted { $0.boundingBox.midY > $1.boundingBox.midY }
                .compactMap { observation -> Line? in
                    guard let text = observation.topCandidates(1).first?.string.trimmingCharacters(in: .whitespaces),
                          !text.isEmpty else { return nil }
                    return Line(text: text, height: Double(observation.boundingBox.height))
                }
        }.value
    }
}
