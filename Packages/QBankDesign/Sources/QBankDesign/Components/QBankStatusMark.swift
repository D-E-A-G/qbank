#if canImport(SwiftUI)
import SwiftUI

/// How a question was answered. Shared by Review rows, results lists and exam marks.
public enum QBankAnswerStatus: String, CaseIterable, Sendable {
    case correct
    case partial
    case wrong
    case guessed
    case unanswered

    /// The word shown with the icon, so a status never relies on color alone.
    public var word: String {
        switch self {
        case .correct: "Correct"
        case .partial: "Partly right"
        case .wrong: "Missed"
        case .guessed: "Guessed"
        case .unanswered: "Not answered"
        }
    }

    /// The SF Symbol. Meanings are fixed across the app.
    public var systemImage: String {
        switch self {
        case .correct: "checkmark.circle"
        case .partial: "minus.circle"
        case .wrong: "xmark.circle"
        case .guessed: "flag"
        case .unanswered: "circle"
        }
    }

    public var tone: QBankTintedLabel.Tone {
        switch self {
        case .correct: .correct
        case .partial: .partial
        case .wrong: .wrong
        case .guessed: .guess
        case .unanswered: .neutral
        }
    }
}

/// Icon plus word for an answer status: "Correct", "Partly right", "Missed".
public struct QBankStatusMark: View {
    public enum Variant: String, CaseIterable, Sendable {
        /// Colored icon and word, no background.
        case plain
        /// On a soft pill.
        case pill
    }

    private let status: QBankAnswerStatus
    private let label: String?
    private let variant: Variant
    private let size: QBankTintedLabel.Size

    /// - Parameter label: Replaces the status word, for example "Missed, guessed".
    public init(
        _ status: QBankAnswerStatus,
        label: String? = nil,
        variant: Variant = .plain,
        size: QBankTintedLabel.Size = .regular
    ) {
        self.status = status
        self.label = label
        self.variant = variant
        self.size = size
    }

    public var body: some View {
        switch variant {
        case .pill:
            QBankTintedLabel(
                label ?? status.word,
                systemImage: status.systemImage,
                tone: status.tone,
                style: .soft,
                size: size
            )
        case .plain:
            HStack(spacing: size == .small ? QBankSpacing.space2 : 6) {
                Image(systemName: status.systemImage)
                    .fontWeight(.semibold)
                    .accessibilityHidden(true)
                Text(label ?? status.word)
            }
            .qbankFont(size == .small ? .caption1 : .footnote, weight: .semibold, design: .default)
            .foregroundStyle(.qbank(status == .unanswered ? .text3 : status.tone.foreground))
            // Wraps rather than truncates when the text is too long or very large.
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview("Status marks") {
    VStack(alignment: .leading, spacing: QBankSpacing.space4) {
        ForEach(QBankAnswerStatus.allCases, id: \.self) { status in
            HStack(spacing: QBankSpacing.space5) {
                QBankStatusMark(status)
                QBankStatusMark(status, variant: .pill)
                QBankStatusMark(status, variant: .pill, size: .small)
            }
        }
    }
    .padding(QBankSpacing.gutterPhone)
    .qbankScreenBackground()
}
#endif
