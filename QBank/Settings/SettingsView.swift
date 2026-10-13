import QBankDesign
import QBankKit
import SwiftUI

/// The Settings tab. Slice 1a has the account and sign-out; the rest of Settings comes in 1d.
struct SettingsView: View {
    let app: AppModel
    @State private var isSigningOut = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: QBankSpacing.space7) {
                    QBankListGroup(header: "Account") {
                        QBankListRow("Signed in as", detail: app.account?.email)
                            .accessibilityIdentifier("settings.account")
                        Button {
                            isSigningOut = true
                            Task { await app.signOut() }
                        } label: {
                            QBankListRow("Sign out", isDestructive: true) {
                                if isSigningOut {
                                    ProgressView()
                                }
                            }
                        }
                        .buttonStyle(.qbankRow)
                        .disabled(isSigningOut)
                        .accessibilityIdentifier("settings.signOut")
                    }
                    Text(Self.version)
                        .qbankFont(.footnote)
                        .foregroundStyle(.qbank(.text3))
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("settings.version")
                }
                .padding(.horizontal, QBankSpacing.gutterPhone)
                .padding(.top, QBankSpacing.space3)
                .padding(.bottom, QBankSpacing.space7)
            }
            .qbankScreenBackground()
            .navigationTitle("Settings")
        }
    }

    /// "QBank 0.1.0 (1)": the version and build, as Settings shows it.
    static var version: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "QBank \(version) (\(build))"
    }
}
