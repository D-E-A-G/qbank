#if canImport(SwiftUI)
import SwiftUI

/// A small pill label: "12 to review", "Exam bank · 17 questions", "Week 3",
/// "No exam bank yet". Never the only carrier of meaning: pair a state tone with
/// a word, and an icon where it helps.
public struct QBankTintedLabel: View {
    public enum Tone: String, CaseIterable, Sendable {
        case tint
        case neutral
        case correct
        case partial
        case wrong
        case guess

        var foreground: QBankColorToken {
            switch self {
            case .tint: .tint
            case .neutral: .text2
            case .correct: .correct
            case .partial: .partial
            case .wrong: .wrong
            case .guess: .guess
            }
        }

        var soft: QBankColorToken {
            switch self {
            case .tint: .tintSoft
            case .neutral: .surfaceSunken
            case .correct: .correctSoft
            case .partial: .partialSoft
            case .wrong: .wrongSoft
            case .guess: .guessSoft
            }
        }

        var border: QBankColorToken {
            switch self {
            case .tint: .tintSoftBorder
            case .neutral: .separatorStrong
            case .correct: .correctBorder
            case .partial: .partialBorder
            case .wrong: .wrongBorder
            case .guess: .guessBorder
            }
        }
    }

    public enum Style: String, CaseIterable, Sendable {
        /// Soft tone fill, tone text. The default.
        case soft
        /// Card fill with a 1pt tone border.
        case outline
        /// No fill, a dashed border: something missing or not yet there.
        case dashed
        /// Full tone fill. Use sparingly, for one strong label.
        case solid
    }

    public enum Size: String, CaseIterable, Sendable {
        case regular
        case small
    }

    private let title: Text
    private let systemImage: String?
    private let tone: Tone
    private let style: Style
    private let size: Size

    public init(
        _ titleKey: LocalizedStringKey,
        systemImage: String? = nil,
        tone: Tone = .tint,
        style: Style = .soft,
        size: Size = .regular
    ) {
        self.init(title: Text(titleKey), systemImage: systemImage, tone: tone, style: style, size: size)
    }

    @_disfavoredOverload
    public init<S: StringProtocol>(
        _ title: S,
        systemImage: String? = nil,
        tone: Tone = .tint,
        style: Style = .soft,
        size: Size = .regular
    ) {
        self.init(title: Text(title), systemImage: systemImage, tone: tone, style: style, size: size)
    }

    private init(title: Text, systemImage: String?, tone: Tone, style: Style, size: Size) {
        self.title = title
        self.systemImage = systemImage
        self.tone = tone
        self.style = style
        self.size = size
    }

    public var body: some View {
        HStack(spacing: size == .small ? QBankSpacing.space2 : 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .imageScale(.small)
                    .fontWeight(.semibold)
                    .accessibilityHidden(true)
            }
            title
        }
        .qbankFont(size == .small ? .caption1 : .footnote, weight: .semibold, design: .default)
        .foregroundStyle(.qbank(foreground))
        .padding(.leading, systemImage == nil ? horizontalPadding : horizontalPadding - 2)
        .padding(.trailing, horizontalPadding)
        .padding(.vertical, size == .small ? 2 : 4)
        .background { background }
        // Wraps rather than truncates when the text is too long or very large.
        .fixedSize(horizontal: false, vertical: true)
    }

    private var horizontalPadding: CGFloat {
        size == .small ? 8 : 10
    }

    private var foreground: QBankColorToken {
        switch style {
        case .soft, .outline: tone.foreground
        case .dashed: tone == .neutral ? .text2 : tone.foreground
        case .solid: tone == .tint ? .textOnTint : .surface
        }
    }

    @ViewBuilder private var background: some View {
        switch style {
        case .soft:
            Capsule().fill(.qbank(tone.soft))
        case .outline:
            Capsule().fill(.qbank(.surface))
                .overlay { Capsule().strokeBorder(.qbank(tone.border), lineWidth: QBankBorder.regular) }
        case .dashed:
            Capsule().strokeBorder(
                .qbank(tone == .neutral ? .separatorStrong : tone.border),
                style: StrokeStyle(lineWidth: QBankBorder.regular, dash: [3, 2.5])
            )
        case .solid:
            Capsule().fill(.qbank(tone.foreground))
        }
    }
}

#Preview("Tinted labels") {
    VStack(alignment: .leading, spacing: QBankSpacing.space4) {
        ForEach(QBankTintedLabel.Style.allCases, id: \.self) { style in
            HStack(spacing: QBankSpacing.space3) {
                ForEach(QBankTintedLabel.Tone.allCases, id: \.self) { tone in
                    QBankTintedLabel(tone.rawValue.capitalized, tone: tone, style: style, size: .small)
                }
            }
        }
        QBankTintedLabel("12 to review", systemImage: "tray")
        QBankTintedLabel("Exam bank · 17 questions", tone: .neutral, style: .outline)
        QBankTintedLabel("No exam bank yet · exams use practice questions", tone: .neutral, style: .dashed)
    }
    .padding(QBankSpacing.gutterPhone)
    .qbankScreenBackground()
}
#endif
