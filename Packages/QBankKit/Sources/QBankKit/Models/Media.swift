import Foundation

// Tables and images a question carries in its body, read with the same rules as the server's
// `packages/questions/src/media.ts`: a table or image that cannot be drawn is left out, never an error.

/// A table of readings under the stem, such as vital signs or labs.
public struct QuestionTable: Sendable, Equatable {
    public let caption: String?
    /// The header row. Empty when the file gave none.
    public let head: [String]
    /// Every row has as many cells as the widest row or the header.
    public let rows: [[String]]

    public init(caption: String?, head: [String], rows: [[String]]) {
        self.caption = caption
        self.head = head
        self.rows = rows
    }

    /// Reads `{ caption?, head?, rows }`. Nil when there is no table or it cannot be drawn.
    public init?(json: JSONValue?) {
        guard case .object(let object)? = json else { return nil }
        let caption = object["caption"] ?? .null
        let head = object["head"] ?? .null
        if !caption.isNull, caption.stringValue == nil { return nil }
        var headCells: [String] = []
        if !head.isNull {
            guard let cells = Self.cells(head) else { return nil }
            headCells = cells
        }
        guard let rawRows = object["rows"]?.arrayValue, !rawRows.isEmpty else { return nil }
        var bodyRows: [[String]] = []
        for row in rawRows {
            guard let cells = Self.cells(row) else { return nil }
            bodyRows.append(cells)
        }
        let width = max(headCells.count, bodyRows.map(\.count).max() ?? 0)
        guard width > 0 else { return nil }
        func pad(_ cells: [String]) -> [String] {
            cells.count < width ? cells + Array(repeating: "", count: width - cells.count) : cells
        }
        let trimmedCaption = caption.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.caption = trimmedCaption?.isEmpty == false ? trimmedCaption : nil
        self.head = headCells.isEmpty ? [] : pad(headCells)
        self.rows = bodyRows.map(pad)
    }

    private static func cells(_ value: JSONValue) -> [String]? {
        guard let items = value.arrayValue else { return nil }
        var cells: [String] = []
        for item in items {
            switch item {
            case .null: cells.append("")
            case .string(let text): cells.append(text.trimmingCharacters(in: .whitespacesAndNewlines))
            case .number(let number): cells.append(Self.format(number))
            case .bool(let flag): cells.append(flag ? "true" : "false")
            case .array, .object: return nil
            }
        }
        return cells
    }

    /// Writes a number the way JavaScript's String() does for the values tables hold: 82, 37.5.
    private static func format(_ number: Double) -> String {
        if number.rounded() == number, abs(number) < 1e15 { return String(Int64(number)) }
        return String(number)
    }
}

/// An image a question shows under its stem or with its rationale.
public struct QuestionImage: Sendable, Equatable {
    public enum Placement: String, Sendable {
        /// Under the stem and any table.
        case stem
        /// With the rationale, after she checks her answer.
        case rationale
    }

    public enum Source: Sendable, Equatable {
        /// A base64 data URL of a PNG, JPEG, WebP, or SVG image.
        case dataURL(String)
        /// SVG markup.
        case svg(String)
    }

    /// The most images a question may carry.
    public static let limit = 4
    /// The largest image, after base64 decoding.
    public static let maxBytes = 300 * 1024

    public let source: Source
    public let alt: String
    public let caption: String?
    public let placement: Placement

    /// The image file's bytes and media type, for a data URL source. SVG markup returns its UTF-8 bytes.
    public var file: (mediaType: String, data: Data)? {
        switch source {
        case .svg(let markup):
            return ("image/svg+xml", Data(markup.utf8))
        case .dataURL(let url):
            guard let parsed = DataURL(url), let data = parsed.decoded else { return nil }
            return (parsed.mediaType, data)
        }
    }

    /// The images in a question body that are safe to draw, in order, at most four.
    public static func read(_ json: JSONValue?) -> [QuestionImage] {
        guard let items = json?.arrayValue else { return [] }
        var images: [QuestionImage] = []
        for item in items {
            if images.count == limit { break }
            if let image = QuestionImage(json: item) { images.append(image) }
        }
        return images
    }

    init?(json: JSONValue) {
        guard case .object(let object) = json else { return nil }
        guard let alt = object["alt"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !alt.isEmpty else { return nil }
        let caption = object["caption"] ?? .null
        if !caption.isNull, caption.stringValue == nil { return nil }
        let at = object["at"] ?? .null
        let placement: Placement
        if at.isNull {
            placement = .stem
        } else if let value = at.stringValue, let parsed = Placement(rawValue: value) {
            placement = parsed
        } else {
            return nil
        }
        let src = object["src"] ?? .null
        let svg = object["svg"] ?? .null
        guard src.isNull != svg.isNull else { return nil }
        if let markup = svg.stringValue {
            guard Self.svgIsSafe(markup, bytes: markup.utf8.count) else { return nil }
            source = .svg(markup.trimmingCharacters(in: .whitespacesAndNewlines))
        } else if let url = src.stringValue {
            let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard Self.dataURLIsSafe(trimmed) else { return nil }
            source = .dataURL(trimmed)
        } else {
            return nil
        }
        self.alt = alt
        let trimmedCaption = caption.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.caption = trimmedCaption?.isEmpty == false ? trimmedCaption : nil
        self.placement = placement
    }

    private static let imageTypes: Set<String> = ["image/png", "image/jpeg", "image/webp", "image/svg+xml"]

    private static func dataURLIsSafe(_ url: String) -> Bool {
        guard let parsed = DataURL(url), imageTypes.contains(parsed.mediaType), parsed.isBase64 else { return false }
        let payload = parsed.payload
        guard !payload.isEmpty, payload.count % 4 != 1, payload.wholeMatch(of: /[A-Za-z0-9+\/]+={0,2}/) != nil else { return false }
        guard let data = parsed.decoded, data.count <= maxBytes else { return false }
        if parsed.mediaType == "image/svg+xml" {
            return svgIsSafe(String(decoding: data, as: UTF8.self), bytes: data.count)
        }
        return startsLike(parsed.mediaType, data)
    }

    // The checks the server runs on stored markup: no scripts, event handlers, or outside links.
    private static func svgIsSafe(_ svg: String, bytes: Int) -> Bool {
        guard bytes <= maxBytes else { return false }
        let text = svg.lowercased()
        guard text.contains("<svg") else { return false }
        let banned = ["<script", "<foreignobject", "<!entity", "javascript:", "@import"]
        if banned.contains(where: text.contains) { return false }
        let patterns = [
            #"<[^>]*\son[a-z]+\s*="#,
            #"<[^>]*\s(?:xlink:)?(?:href|src)\s*=\s*["']?\s*(?!#|data:image/)[^\s"'>]"#,
            #"url\(\s*["']?\s*(?!#|data:image/)[^\s"')]"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
            if regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil { return false }
        }
        return true
    }

    private static func startsLike(_ type: String, _ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(12))
        func at(_ index: Int) -> Int { index < bytes.count ? Int(bytes[index]) : -1 }
        switch type {
        case "image/png": return at(0) == 0x89 && at(1) == 0x50 && at(2) == 0x4E && at(3) == 0x47
        case "image/jpeg": return at(0) == 0xFF && at(1) == 0xD8 && at(2) == 0xFF
        default:
            // RIFF....WEBP
            return at(0) == 0x52 && at(1) == 0x49 && at(2) == 0x46 && at(3) == 0x46
                && at(8) == 0x57 && at(9) == 0x45 && at(10) == 0x42 && at(11) == 0x50
        }
    }
}

/// `data:<type>[;param]*,<payload>`
private struct DataURL {
    let mediaType: String
    let isBase64: Bool
    let payload: String

    init?(_ url: String) {
        guard url.hasPrefix("data:"), let comma = url.firstIndex(of: ",") else { return nil }
        let header = url[url.index(url.startIndex, offsetBy: 5)..<comma].lowercased()
        let parts = header.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
        guard let type = parts.first, !type.isEmpty else { return nil }
        mediaType = type
        isBase64 = parts.dropFirst().contains("base64")
        payload = String(url[url.index(after: comma)...])
    }

    /// The payload's bytes. Base64 without its trailing padding is accepted, as the server accepts it.
    var decoded: Data? {
        guard isBase64 else { return nil }
        let remainder = payload.count % 4
        return Data(base64Encoded: remainder == 0 ? payload : payload + String(repeating: "=", count: 4 - remainder))
    }
}
