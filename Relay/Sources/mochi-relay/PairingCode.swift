import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import RelayCore

/// Shows the pairing secret as Base32 and as a QR code drawn with Unicode block characters.
enum PairingCode {
    /// What the QR code contains: a prefix the app can check, then the Base32 secret.
    static func qrPayload(for secret: Data) -> String {
        "mochirelay:v1:\(Base32.encode(secret))"
    }

    static func printPairing(secret: Data) {
        print("Pairing code (keep it private; anyone with it can use this relay):")
        print("")
        print("    \(Base32.grouped(Base32.encode(secret)))")
        print("")
        if let qr = terminalQR(for: qrPayload(for: secret)) {
            print(qr)
        } else {
            print("(The QR code couldn't be drawn; type the code above instead.)")
        }
    }

    /// A QR code as text: two modules per character cell using ▀ ▄ █, black on white.
    static func terminalQR(for text: String) -> String? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let image = filter.outputImage,
              let cgImage = CIContext().createCGImage(image, from: image.extent)
        else { return nil }

        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 255, count: width * height)
        guard let context = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let quietZone = 2
        let size = width + quietZone * 2
        func isDark(_ x: Int, _ y: Int) -> Bool {
            let px = x - quietZone
            let py = y - quietZone
            guard px >= 0, py >= 0, px < width, py < height else { return false }
            return pixels[py * width + px] < 128
        }
        let colors = "\u{1B}[30;107m"
        let reset = "\u{1B}[0m"
        var lines: [String] = []
        for y in stride(from: 0, to: size + (size % 2), by: 2) {
            var line = colors
            for x in 0..<size {
                switch (isDark(x, y), isDark(x, y + 1)) {
                case (true, true): line += "█"
                case (true, false): line += "▀"
                case (false, true): line += "▄"
                case (false, false): line += " "
                }
            }
            lines.append(line + reset)
        }
        return lines.joined(separator: "\n")
    }
}
