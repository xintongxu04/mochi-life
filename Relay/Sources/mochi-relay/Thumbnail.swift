import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Downloads a product photo and shrinks it to a small JPEG. Only https, 10-second timeout,
/// at most 5 MB, and only image/* responses.
enum Thumbnail {
    static let maximumBytes = 5 * 1024 * 1024
    static let longEdge = 400

    struct Failure: Error, CustomStringConvertible {
        var description: String
    }

    static func make(from urlString: String) async throws -> String {
        guard let url = URL(string: urlString), url.scheme?.lowercased() == "https" else {
            throw Failure(description: "the image address isn't https")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 10
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        let (bytes, response) = try await session.bytes(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw Failure(description: "the image server didn't return the image")
        }
        guard http.url?.scheme?.lowercased() == "https" else {
            throw Failure(description: "the image was redirected away from https")
        }
        guard http.mimeType?.lowercased().hasPrefix("image/") == true else {
            throw Failure(description: "the address isn't an image")
        }
        if http.expectedContentLength > Int64(maximumBytes) {
            throw Failure(description: "the image is larger than 5 MB")
        }
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count > maximumBytes {
                throw Failure(description: "the image is larger than 5 MB")
            }
        }
        return try jpegBase64(from: data)
    }

    static func jpegBase64(from data: Data) throws -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw Failure(description: "the image couldn't be read")
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longEdge,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw Failure(description: "the image couldn't be resized")
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw Failure(description: "the JPEG couldn't be created")
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw Failure(description: "the JPEG couldn't be created")
        }
        return (output as Data).base64EncodedString()
    }
}
