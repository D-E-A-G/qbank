import QBankDesign
import SwiftUI

struct SignUpView: View {
    @State private var model: SignUpModel
    @FocusState private var focus: Field?
    /// Back to Sign in: with nothing when she has an account, or with the new account's email when
    /// it was made but not signed in.
    private let signIn: (SignInHandoff?) -> Void

    private enum Field {
        case email
        case password
    }

    init(app: AppModel, signIn: @escaping (SignInHandoff?) -> Void) {
        _model = State(initialValue: SignUpModel(app: app))
        self.signIn = signIn
    }

    var body: some View {
        ScrollView {
            VStack(spacing: QBankSpacing.space7) {
                header
                form
            }
            .padding(.horizontal, QBankSpacing.gutterPhone)
            .padding(.vertical, QBankSpacing.space7)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.center)
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .qbankScreenBackground()
        .onChange(of: model.madeButNotSignedIn) { _, handoff in
            if let handoff { signIn(handoff) }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            QBankMark()
                .padding(.bottom, QBankSpacing.space2)
            Text("Sign up")
                .qbankFont(.largeTitle)
                .foregroundStyle(.qbank(.text1))
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("signUp.title")
            Text("Make a user account with an email the owner has added.")
                .qbankFont(.subheadline)
                .foregroundStyle(.qbank(.text2))
                .multilineTextAlignment(.center)
        }
    }

    private var form: some View {
        VStack(spacing: QBankSpacing.space4) {
            LabeledField(label: "Email") {
                TextField("Email", text: $model.email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focus, equals: .email)
                    .onSubmit { focus = .password }
                    .accessibilityIdentifier("signUp.email")
            }
            LabeledField(label: "Password", hint: "At least 8 characters.") {
                SecureField("Password", text: $model.password)
                    .textContentType(.newPassword)
                    .submitLabel(.go)
                    .focused($focus, equals: .password)
                    .onSubmit(signUp)
                    .accessibilityIdentifier("signUp.password")
            }
            if let problem = model.problem {
                ProblemText(text: problem)
            }
            Button(action: signUp) {
                if model.isSigningUp {
                    ProgressView()
                        .tint(QBankColor(.textOnTint))
                        .accessibilityLabel("Signing up")
                } else {
                    Text("Sign up")
                }
            }
            .buttonStyle(.qbank(.primary, size: .large, fullWidth: true))
            .disabled(model.isSigningUp)
            .accessibilityIdentifier("signUp.submit")
            .padding(.top, 2)

            Button("I have an account") {
                focus = nil
                model.leave()
                signIn(nil)
            }
            .buttonStyle(.qbank(.plain))
            .disabled(model.isSigningUp)
            .accessibilityIdentifier("signUp.signIn")
        }
    }

    private func signUp() {
        focus = nil
        Task { await model.signUp() }
    }
}
