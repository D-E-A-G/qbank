import QBankDesign
import QBankKit
import SwiftUI

/// A notice that a screen works from what is saved on the phone: "No connection", "Saved on this
/// phone", "Exams need a connection". A dashed card, the way the design draws something that is
/// not there yet.
struct OfflineBanner: View {
    let title: String
    let message: String
    var systemImage = "wifi.slash"

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: QBankSpacing.space4) {
            Image(systemName: systemImage)
                .qbankFont(.subheadline, weight: .semibold)
                .foregroundStyle(.qbank(.tint))
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .qbankFont(.subheadline, weight: .semibold)
                    .foregroundStyle(.qbank(.text1))
                Text(message)
                    .qbankFont(.subheadline)
                    .foregroundStyle(.qbank(.text2))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, QBankSpacing.space4)
        .padding(.horizontal, 14)
        .background(.qbank(.surface), in: .rect(cornerRadius: QBankRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: QBankRadius.md, style: .continuous)
                .strokeBorder(.qbank(.separatorStrong), style: StrokeStyle(lineWidth: QBankBorder.regular, dash: [4, 3]))
        }
        .accessibilityElement(children: .combine)
    }
}

extension OfflineBanner {
    /// Home and Course while they show the phone's copy: the phone has no network, or it has one
    /// but QBank does not answer.
    static func showingSaved(phoneIsOnline: Bool) -> OfflineBanner {
        OfflineBanner(
            title: phoneIsOnline ? "QBank cannot be reached" : "No connection",
            message: "Showing what is saved on this \(Device.noun). Your answers send when you are back online."
        )
    }

    /// An answer checked without a connection, under the question.
    static var answerSaved: OfflineBanner {
        OfflineBanner(
            title: "Saved on this \(Device.noun)",
            message: "It will send when you are back online. Your score is the same either way.",
            systemImage: Device.symbol
        )
    }

    /// An answer checked without a connection when the phone cannot keep answers in a file.
    static var answerNotKept: OfflineBanner {
        OfflineBanner(
            title: "Not saved on this \(Device.noun)",
            message: "It sends if the connection comes back before the app closes. Your score is the same either way.",
            systemImage: "exclamationmark.triangle"
        )
    }

    /// Deleting and bringing back happen on the server, so they need a connection.
    static let deletingNeedsConnection = OfflineBanner(
        title: "No connection",
        message: "Bringing back what you deleted happens on the server. Try again when you are back online."
    )

    /// Exams start and end on the server, so they need a connection.
    static let examsNeedConnection = OfflineBanner(
        title: "Exams need a connection",
        message: "An exam starts and ends on the server, so the timer is fair and the questions stay unseen. Practice works offline."
    )
}

/// How old the copy on the phone is: "Saved 7:40 AM", on a course shown without a connection.
struct SavedBadge: View {
    let date: Date

    var body: some View {
        QBankTintedLabel(Wording.saved(date), tone: .neutral, style: .dashed, size: .small)
    }
}

/// "3 waiting to send": answers on the phone that QBank does not have yet. One text with the
/// arrow inside it, so a toolbar shows the words and not only the icon.
struct WaitingLabel: View {
    let count: Int

    var body: some View {
        Text("\(Image(systemName: "arrow.up.circle")) \(Wording.waitingToSend(count))")
            .accessibilityLabel(Wording.waitingToSend(count))
    }
}

extension View {
    /// Reloads when the phone's connection comes or goes, when waiting answers reach QBank, and when
    /// the app comes back to the front, so a screen shows the saved copy without signal and the
    /// server's counts once QBank answers again.
    func reloadsWithConnection(_ app: AppModel, reload: @escaping () async -> Void) -> some View {
        modifier(ReloadsWithConnection(app: app, reload: reload))
    }
}

private struct ReloadsWithConnection: ViewModifier {
    let app: AppModel
    let reload: () async -> Void
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onChange(of: app.connection.isOnline) {
                Task { await reload() }
            }
            .onChange(of: app.offline?.deliveries) {
                Task { await reload() }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await reload() }
            }
    }
}
