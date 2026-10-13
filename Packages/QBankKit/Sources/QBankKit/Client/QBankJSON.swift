import Foundation

/// The JSON coders every part of QBankKit shares: the client, the offline queue, and the cache.
/// Timestamps travel as ISO 8601 text with milliseconds, as the server writes them.
public enum QBankJSON {
    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = parseDate(text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an ISO 8601 timestamp: \(text)")
            }
            return date
        }
        return decoder
    }

    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(formatDate(date))
        }
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    /// Reads `2026-10-13T00:02:35.395Z`, with or without the fraction.
    public static func parseDate(_ text: String) -> Date? {
        if let date = try? Date(text, strategy: withFraction) { return date }
        return try? Date(text, strategy: withoutFraction)
    }

    /// Writes `2026-10-13T00:02:35.395Z`. Rounds to the millisecond, so a timestamp read from the
    /// server is written back exactly as it came, however the fraction landed in floating point.
    public static func formatDate(_ date: Date) -> String {
        let milliseconds = Int64((date.timeIntervalSince1970 * 1000).rounded())
        let (seconds, fraction) = milliseconds.quotientAndRemainder(dividingBy: 1000)
        let whole = fraction < 0 ? (seconds - 1, fraction + 1000) : (seconds, fraction)
        let text = Date(timeIntervalSince1970: TimeInterval(whole.0)).formatted(withoutFraction)
        let digits = String(whole.1)
        return "\(text.dropLast()).\(String(repeating: "0", count: 3 - digits.count))\(digits)Z"
    }

    private static let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let withoutFraction = Date.ISO8601FormatStyle()
}
