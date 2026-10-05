import Foundation

/// RFC 4648 Base32 (A–Z, 2–7) without padding, for showing and typing the pairing secret.
public enum Base32 {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    public static func encode(_ data: Data) -> String {
        var output = ""
        var buffer = 0
        var bits = 0
        for byte in data {
            buffer = (buffer << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                output.append(alphabet[(buffer >> (bits - 5)) & 31])
                bits -= 5
            }
        }
        if bits > 0 {
            output.append(alphabet[(buffer << (5 - bits)) & 31])
        }
        return output
    }

    /// Decodes Base32, ignoring spaces, dashes and letter case.
    public static func decode(_ text: String) -> Data? {
        var output = Data()
        var buffer = 0
        var bits = 0
        for character in text.uppercased() where character != " " && character != "-" {
            guard let value = alphabet.firstIndex(of: character) else { return nil }
            buffer = (buffer << 5) | value
            bits += 5
            if bits >= 8 {
                output.append(UInt8((buffer >> (bits - 8)) & 0xFF))
                bits -= 8
            }
        }
        return output
    }

    /// Groups of four characters separated by spaces, e.g. "ABCD EFGH IJ".
    public static func grouped(_ text: String) -> String {
        stride(from: 0, to: text.count, by: 4).map { start in
            let lower = text.index(text.startIndex, offsetBy: start)
            let upper = text.index(lower, offsetBy: 4, limitedBy: text.endIndex) ?? text.endIndex
            return String(text[lower..<upper])
        }.joined(separator: " ")
    }
}
