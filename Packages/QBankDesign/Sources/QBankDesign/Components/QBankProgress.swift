#if canImport(SwiftUI)
import SwiftUI

/// A thin pill-shaped progress track: course progress, the runner's question count.
public struct QBankProgressBar: View {
    public enum Tone: String, CaseIterable, Sendable {
        case tint
        case correct
        case partial
        case wrong
        case neutral

        var fill: QBankColorToken {
            switch self {
            case .tint: .progressFill
            case .correct: .correct
            case .partial: .partial
            case .wrong: .wrong
            case .neutral: .text3
            }
        }
    }

    private let value: Double
    private let tone: Tone
    private let height: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameter value: From 0 to 1; values outside are clamped.
    public init(value: Double, tone: Tone = .tint, height: CGFloat = 4) {
        self.value = value
        self.tone = tone
        self.height = height
    }

    /// The value clamped to 0...1, with NaN as 0.
    nonisolated public static func clamped(_ value: Double) -> Double {
        value.isNaN ? 0 : min(max(value, 0), 1)
    }

    public var body: some View {
        let fraction = Self.clamped(value)
        Capsule()
            .fill(.qbank(.progressTrack))
            .frame(height: height)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(.qbank(tone.fill))
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .clipShape(Capsule())
            .animation(reduceMotion ? nil : QBankMotion.reveal, value: fraction)
            .accessibilityElement()
            .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
    }
}

/// The progress pill from the course cards: a track with the percentage beside it.
public struct QBankProgressPill: View {
    private let value: Double
    private let tone: QBankProgressBar.Tone
    private let accessibilityTitle: String

    /// - Parameters:
    ///   - value: From 0 to 1; values outside are clamped.
    ///   - accessibilityTitle: What the percentage measures, read by VoiceOver.
    public init(value: Double, tone: QBankProgressBar.Tone = .tint, accessibilityTitle: String = "Answered") {
        self.value = value
        self.tone = tone
        self.accessibilityTitle = accessibilityTitle
    }

    /// The whole percentage shown, for example "41%".
    nonisolated public static func percentText(_ value: Double) -> String {
        "\(Int((QBankProgressBar.clamped(value) * 100).rounded()))%"
    }

    public var body: some View {
        HStack(spacing: 10) {
            QBankProgressBar(value: value, tone: tone)
            Text(Self.percentText(value))
                .qbankFont(.caption1, weight: .medium)
                .monospacedDigit()
                .foregroundStyle(.qbank(.text3))
                .frame(minWidth: 32, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue(Self.percentText(value))
    }
}

#Preview("Progress") {
    VStack(spacing: QBankSpacing.space5) {
        QBankProgressPill(value: 0)
        QBankProgressPill(value: 0.41)
        QBankProgressPill(value: 1)
        QBankProgressBar(value: 3.0 / 17)
        ForEach(QBankProgressBar.Tone.allCases, id: \.self) { tone in
            QBankProgressBar(value: 0.6, tone: tone)
        }
    }
    .padding(QBankSpacing.gutterPhone)
    .qbankScreenBackground()
}
#endif
