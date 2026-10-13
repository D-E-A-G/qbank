import QBankDesign
import SwiftUI

struct ChoosePasswordView: View {
    @State private var model: ChoosePasswordModel
    @FocusState private var focus: Field?

    private enum Field {
        case temporary
        case new
    }

    init(app: AppModel) {
        _model = State(initialValue: ChoosePasswordModel(app: app))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: QBankSpacing.space4) {
                    // In the content rather than the navigation bar, so the long title wraps
                    // instead of being cut off.
                    Text("Choose a new password")
                        .qbankFont(.largeTitle)
                        .foregroundStyle(.qbank(.text1))
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("choosePassword.title")
                    Text("Choose a new password to continue.")
                        .qbankFont(.subheadline)
                        .foregroundStyle(.qbank(.text2))
                    LabeledField(label: "Temporary password") {
                        SecureField("Temporary password", text: $model.temporaryPassword)
                            .textContentType(.password)
                            .submitLabel(.next)
                            .focused($focus, equals: .temporary)
                            .onSubmit { focus = .new }
                            .accessibilityIdentifier("choosePassword.temporary")
                    }
                    LabeledField(label: "New password", hint: "At least 8 characters, and different from the temporary one.") {
                        SecureField("New password", text: $model.newPassword)
                            .textContentType(.newPassword)
                            .submitLabel(.done)
                            .focused($focus, equals: .new)
                            .onSubmit(save)
                            .accessibilityIdentifier("choosePassword.new")
                    }
                    if let problem = model.problem {
                        ProblemText(text: problem)
                    }
                    Button(action: save) {
                        if model.isSaving {
                            ProgressView()
                                .tint(QBankColor(.textOnTint))
                                .accessibilityLabel("Saving")
                        } else {
                            Text("Save password")
                        }
                    }
                    .buttonStyle(.qbank(.primary, size: .large, fullWidth: true))
                    .disabled(model.isSaving)
                    .accessibilityIdentifier("choosePassword.save")
                    .padding(.top, 2)
                }
                .padding(.horizontal, QBankSpacing.gutterPhone)
                .padding(.top, QBankSpacing.space2)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .qbankScreenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await model.cancel() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.backward")
                                .fontWeight(.semibold)
                            Text("Sign in")
                        }
                    }
                    .accessibilityLabel("Back to sign in")
                    .accessibilityIdentifier("choosePassword.back")
                }
            }
            .onAppear {
                focus = model.temporaryPassword.isEmpty ? .temporary : .new
            }
        }
    }

    private func save() {
        focus = nil
        Task { await model.save() }
    }
}
