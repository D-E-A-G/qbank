import QBankDesign
import SwiftUI

/// Settings' Delete account: what goes, in plain words, her current password, and the delete.
struct DeleteAccountView: View {
    @State private var model: DeleteAccountModel
    @FocusState private var isFocused: Bool

    init(app: AppModel) {
        _model = State(initialValue: DeleteAccountModel(app: app))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: QBankSpacing.space4) {
                Text("Your user account and everything in it are deleted for good: your courses and study topics, their sets, your answers, progress and past exams. You are signed out on every device. Nothing goes to Recently deleted, and there is no Undo.")
                    .qbankFont(.body)
                    .foregroundStyle(.qbank(.text1))
                    .accessibilityIdentifier("deleteAccount.message")
                if model.waitingCount > 0 {
                    let waiting = model.waitingCount
                    Text("\(Wording.count(waiting, "answer")) on this \(Device.noun) \(waiting == 1 ? "has" : "have") not reached QBank yet and \(waiting == 1 ? "is" : "are") deleted too.")
                        .qbankFont(.subheadline)
                        .foregroundStyle(.qbank(.text2))
                        .accessibilityIdentifier("deleteAccount.waiting")
                }
                LabeledField(label: "Current password") {
                    SecureField("Current password", text: $model.password)
                        .textContentType(.password)
                        .submitLabel(.done)
                        .focused($isFocused)
                        .onSubmit(delete)
                        .accessibilityIdentifier("deleteAccount.password")
                }
                if let problem = model.problem {
                    ProblemText(text: problem)
                }
                Button(action: delete) {
                    if model.isDeleting {
                        ProgressView()
                            .tint(QBankColor(.wrong))
                            .accessibilityLabel("Deleting")
                    } else {
                        Text("Delete account")
                    }
                }
                .buttonStyle(.qbank(.destructive, size: .large, fullWidth: true))
                .disabled(!model.canDelete)
                .accessibilityIdentifier("deleteAccount.delete")
                .padding(.top, 2)
            }
            .screenColumn()
            .padding(.top, QBankSpacing.space3)
            .padding(.bottom, QBankSpacing.space7)
        }
        .scrollDismissesKeyboard(.interactively)
        .qbankScreenBackground()
        .navigationTitle("Delete account")
        .screenColumnTitle()
        .task(id: model.lockedUntil) {
            guard let lockedUntil = model.lockedUntil else { return }
            try? await Task.sleep(for: .seconds(max(0, lockedUntil.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            model.lockEnded()
        }
    }

    private func delete() {
        isFocused = false
        Task { await model.delete() }
    }
}
