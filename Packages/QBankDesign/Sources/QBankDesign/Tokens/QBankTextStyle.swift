/// The type scale. Sizes are Apple's Dynamic Type "Large" sizes, so each style maps
/// to a `Font.TextStyle` and scales with the reader's text size setting.
/// Footnote and captions are SF Mono, as on the web; everything else is SF Pro.
public enum QBankTextStyle: String, CaseIterable, Sendable {
    case largeTitle
    case title1
    case title2
    case title3
    case headline
    case body
    case callout
    case subheadline
    case footnote
    case caption1
    case caption2
    /// Question stems on iPhone.
    case reading
    /// Question stems on iPad and Mac.
    case readingLarge
    /// Rationales and per-option reasons.
    case readingSmall

    public enum Weight: String, Sendable {
        case regular, medium, semibold, bold

        /// The CSS `font-weight` number.
        public var cssValue: Int {
            switch self {
            case .regular: 400
            case .medium: 500
            case .semibold: 600
            case .bold: 700
            }
        }
    }

    public enum Design: String, Sendable {
        /// SF Pro.
        case `default`
        /// SF Mono, for small labels and numbers.
        case monospaced
    }

    /// The point size at the default ("Large") text size.
    public var size: Double {
        switch self {
        case .largeTitle: 34
        case .title1: 28
        case .title2: 22
        case .title3: 20
        case .headline: 17
        case .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption1: 12
        case .caption2: 11
        case .reading: 18
        case .readingLarge: 20
        case .readingSmall: 16
        }
    }

    /// The line height at the default text size. Reading styles get generous
    /// leading for long study sessions.
    public var lineHeight: Double {
        switch self {
        case .largeTitle: 41
        case .title1: 34
        case .title2: 28
        case .title3: 25
        case .headline: 22
        case .body: 22
        case .callout: 21
        case .subheadline: 20
        case .footnote: 18
        case .caption1: 16
        case .caption2: 13
        case .reading: 28
        case .readingLarge: 31
        case .readingSmall: 25
        }
    }

    public var weight: Weight {
        switch self {
        case .largeTitle, .title1, .title2: .bold
        case .title3, .headline: .semibold
        default: .regular
        }
    }

    public var design: Design {
        switch self {
        case .footnote, .caption1, .caption2: .monospaced
        default: .default
        }
    }

    /// Letter spacing in points; large titles are set slightly tight.
    public var tracking: Double {
        switch self {
        case .largeTitle, .title1: -0.4
        default: 0
        }
    }

    /// Letter spacing for small uppercase labels (list headers, option state tags), in em.
    public static let capsTrackingEm = 0.06
}
