import QBankDesign
import SwiftUI

/// Settings' Change password: the web's two fields on their own screen.
struct ChangePasswordView: View {
    @State private var model: ChangePasswordModel
    @FocusState private var focus: Field?

    private enum Field {
        case current
        case new
    }

    init(app: AppModel) {
        _model = State(initialValue: ChangePasswordModel(app: app))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: QBankSpacing.space4) {
                LabeledField(label: "Current password") {
                    SecureField("Current password", text: $model.currentPassword)
                        .textContentType(.password)
                        .submitLabel(.next)
                        .focused($focus, equals: .current)
                        .onSubmit { focus = .new }
                        .accessibilityIdentifier("changePassword.current")
                }
                LabeledField(label: "New password", hint: "At least 8 characters. Changing it signs you out on your other devices.") {
                    SecureField("New password", text: $model.newPassword)
                        .textContentType(.newPassword)
                        .submitLabel(.done)
                        .focused($focus, equals: .new)
                        .onSubmit(save)
                        .accessibilityIdentifier("changePassword.new")
                }
                if let problem = model.problem {
                    ProblemText(text: problem)
                }
                if model.isSaved {
                    SavedText(text: "Password saved.")
                }
                Button(action: save) {
                    if model.isSaving {
                        ProgressView()
                            .tint(QBankColor(.textOnTint))
                            .accessibilityLabel("Saving")
                    } else {
                        Text("Change password")
                    }
                }
                .buttonStyle(.qbank(.primary, size: .large, fullWidth: true))
                .disabled(model.isSaving)
                .accessibilityIdentifier("changePassword.save")
                .padding(.top, 2)
            }
            .screenColumn()
            .padding(.top, QBankSpacing.space3)
            .padding(.bottom, QBankSpacing.space7)
        }
        .scrollDismissesKeyboard(.interactively)
        .qbankScreenBackground()
        .navigationTitle("Change password")
        .screenColumnTitle()
    }

    private func save() {
        focus = nil
        Task { await model.save() }
    }
}
