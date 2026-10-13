#if canImport(SwiftUI)
import Testing
@testable import QBankDesign

@Suite("Component logic")
struct ComponentTests {
    @Test("Timer clock text", arguments: [(758, "12:38"), (300, "5:00"), (59, "0:59"), (5, "0:05"), (0, "0:00"), (-12, "0:00"), (3600, "60:00")])
    func clockText(seconds: Int, text: String) {
        #expect(QBankTimerPill.clockText(seconds) == text)
    }

    @Test("Progress is clamped and rounded", arguments: [(0.41, "41%"), (0.005, "1%"), (0, "0%"), (1, "100%"), (1.7, "100%"), (-0.3, "0%"), (Double.nan, "0%")])
    func percentText(value: Double, text: String) {
        #expect(QBankProgressPill.percentText(value) == text)
        #expect((0...1).contains(QBankProgressBar.clamped(value)))
    }

    @Test("Every answer status has an icon and a word")
    func statusesNeverRelyOnColor() {
        #expect(QBankAnswerStatus.allCases.map(\.word) == ["Correct", "Partly right", "Missed", "Guessed", "Not answered"])
        #expect(Set(QBankAnswerStatus.allCases.map(\.systemImage)).count == QBankAnswerStatus.allCases.count)
    }

    @Test("Button sizes keep the web heights")
    func buttonSizes() {
        #expect(QBankButtonStyle.Size.large.minHeight == 50)
        #expect(QBankButtonStyle.Size.medium.minHeight == QBankSpacing.rowMin)
        #expect(QBankButtonStyle.Size.small.minHeight == 32)
        #expect(QBankButtonStyle.Size.large.cornerRadius == QBankRadius.sm)
    }
}
#endif
