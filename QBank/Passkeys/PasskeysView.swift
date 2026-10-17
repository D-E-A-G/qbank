import QBankDesign
import QBankKit
import SwiftUI

/// Settings' Passkeys: the account's passkeys, wherever she saved them, each with Remove, and
/// saving one on this device.
struct PasskeysView: View {
    let model: PasskeysModel
    let lock: AppLock
    /// The passkey the sheet asks about. It outlives the sheet, which closes before its action runs.
    @State private var toRemove: Passkey?
    @State private var asksToRemove = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: QBankSpacing.space4) {
                QBankListGroup(footer: "Passkeys let you sign in with \(Wording.passkeyCheck(lock.method)) instead of your password.") {
                    if let passkeys = model.passkeys {
                        ForEach(passkeys) { passkey in
                            row(passkey)
                        }
                        save
                    } else if let problem = model.loadProblem {
                        QBankListRow(problem, accessibilityChildren: .contain) {
                            Button("Try again") {
                                Task { await model.load() }
                            }
                            .buttonStyle(.qbank(.secondary, size: .small))
                            .accessibilityIdentifier("passkeys.retry")
                        }
                    } else {
                        QBankListRow("Loading your passkeys") {
                            ProgressView()
                        }
                    }
                }
                if let problem = model.problem {
                    ProblemText(text: problem)
                        .padding(.horizontal, QBankSpacing.space5)
                }
                if model.isSaved {
                    SavedText(text: "Passkey saved on this \(Device.model).")
                        .padding(.horizontal, QBankSpacing.space5)
                }
            }
            .screenColumn()
            .padding(.top, QBankSpacing.space3)
            .padding(.bottom, QBankSpacing.space7)
        }
        .qbankScreenBackground()
        .navigationTitle("Passkeys")
        .screenColumnTitle()
        .refreshable { await model.load() }
        .confirmSheet(
            isPresented: $asksToRemove,
            title: "Remove the passkey “\(toRemove.map(Self.name) ?? "")”?",
            message: "You won't be able to sign in with it anymore. Your password still works.",
            confirm: "Remove",
            identifier: "passkeys.removeSheet"
        ) {
            guard let passkey = toRemove else { return }
            Task { await model.remove(passkey) }
        }
    }

    private func row(_ passkey: Passkey) -> some View {
        QBankListRow(
            Self.name(passkey),
            detail: passkey.createdAt.map { "Added \(Wording.when($0))" },
            systemImage: "key",
            accessibilityChildren: .contain
        ) {
            if model.removingID == passkey.id {
                ProgressView()
            } else {
                Button("Remove") {
                    toRemove = passkey
                    asksToRemove = true
                }
                .buttonStyle(.qbank(.destructive, size: .small))
                .disabled(model.isSaving || model.removingID != nil)
                .accessibilityLabel("Remove \(Self.name(passkey))")
                .accessibilityIdentifier("passkeys.remove.\(Self.name(passkey))")
            }
        }
    }

    private var save: some View {
        Button {
            Task { await model.save() }
        } label: {
            QBankListRow("Save a passkey", systemImage: "plus") {
                if model.isSaving {
                    ProgressView()
                }
            }
        }
        .buttonStyle(.qbankRow)
        .disabled(model.isSaving || model.removingID != nil)
        .accessibilityIdentifier("passkeys.save")
    }

    /// The name she gave it on the web or the device it was saved on; "Passkey" without one.
    private static func name(_ passkey: Passkey) -> String {
        passkey.name ?? "Passkey"
    }
}
