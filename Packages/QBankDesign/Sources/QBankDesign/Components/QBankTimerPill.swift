#if canImport(SwiftUI)
import SwiftUI

/// The exam countdown pill. At five minutes or less it switches to an alert icon,
/// brick text, a brick-soft fill and a brick border, and always says "left", so
/// the low state never relies on color alone.
public struct QBankTimerPill: View {
    private let secondsRemaining: Int
    private let lowAt: Int
    private let compact: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - lowAt: Seconds at or below which the pill shows the low state.
    ///   - compact: Hides the word "left" until the low state.
    public init(secondsRemaining: Int, lowAt: Int = 300, compact: Bool = false) {
        self.secondsRemaining = secondsRemaining
        self.lowAt = lowAt
        self.compact = compact
    }

    /// `m:ss`, never negative: 758 is "12:38".
    nonisolated public static func clockText(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        let rest = clamped % 60
        return "\(clamped / 60):\(rest < 10 ? "0" : "")\(rest)"
    }

    private var isLow: Bool { secondsRemaining <= lowAt }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isLow ? "exclamationmark.triangle" : "timer")
                .fontWeight(.semibold)
                .imageScale(.small)
                .accessibilityHidden(true)
            Group {
                if isLow || !compact {
                    Text("\(Self.clockText(secondsRemaining)) \(Text("left").fontWeight(.medium))")
                } else {
                    Text(Self.clockText(secondsRemaining))
                }
            }
            .monospacedDigit()
        }
        .qbankFont(.subheadline, weight: .semibold)
        .lineLimit(1)
        .foregroundStyle(.qbank(isLow ? .timerLow : .timerNormal))
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .frame(minHeight: 30)
        .background {
            Capsule().fill(.qbank(isLow ? .timerLowSoft : .surfaceSunken))
            if isLow {
                Capsule().strokeBorder(.qbank(.wrongBorder), lineWidth: QBankBorder.regular)
            }
        }
        .fixedSize()
        .animation(reduceMotion ? nil : QBankMotion.reveal, value: isLow)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Time left")
        .accessibilityValue(Self.clockText(secondsRemaining))
        .accessibilityAddTraits(.updatesFrequently)
    }
}

#Preview("Timer pill") {
    VStack(spacing: QBankSpacing.space4) {
        QBankTimerPill(secondsRemaining: 758)
        QBankTimerPill(secondsRemaining: 758, compact: true)
        QBankTimerPill(secondsRemaining: 245)
        QBankTimerPill(secondsRemaining: 0)
    }
    .padding(QBankSpacing.gutterPhone)
    .qbankScreenBackground()
}
#endif
