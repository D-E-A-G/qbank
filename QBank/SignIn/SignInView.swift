import QBankDesign
import SwiftUI

struct SignInView: View {
    @State private var model: SignInModel
    @State private var showsForgotPassword = false
    @FocusState private var focus: Field?

    private enum Field {
        case email
        case password
    }

    init(app: AppModel) {
        _model = State(initialValue: SignInModel(app: app))
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
    }

    private var header: some View {
        VStack(spacing: 8) {
            QBankMark()
                .padding(.bottom, QBankSpacing.space2)
            Text("QBank")
                .qbankFont(.largeTitle)
                .foregroundStyle(.qbank(.text1))
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("signIn.title")
            Text("NCLEX practice, synced across your devices.")
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
                    .accessibilityIdentifier("signIn.email")
            }
            LabeledField(label: "Password") {
                SecureField("Password", text: $model.password)
                    .textContentType(.password)
                    .submitLabel(.go)
                    .focused($focus, equals: .password)
                    .onSubmit(signIn)
                    .accessibilityIdentifier("signIn.password")
            }
            if let problem = model.problem {
                ProblemText(text: problem)
            }
            Button(action: signIn) {
                if model.isSigningIn {
                    ProgressView()
                        .tint(QBankColor(.textOnTint))
                        .accessibilityLabel("Signing in")
                } else {
                    Text("Sign in")
                }
            }
            .buttonStyle(.qbank(.primary, size: .large, fullWidth: true))
            .disabled(model.isBusy)
            .accessibilityIdentifier("signIn.submit")
            .padding(.top, 2)

            Button(action: signInWithPasskey) {
                if model.isUsingPasskey {
                    ProgressView()
                        .accessibilityLabel("Signing in with a passkey")
                } else {
                    Label("Sign in with a passkey", systemImage: "faceid")
                }
            }
            .buttonStyle(.qbank(.secondary, size: .large, fullWidth: true))
            .disabled(model.isBusy)
            .accessibilityIdentifier("signIn.passkey")

            forgotPassword
        }
    }

    private var forgotPassword: some View {
        VStack(spacing: QBankSpacing.space2) {
            Button("Forgot password?") {
                withAnimation(QBankMotion.reveal) { showsForgotPassword.toggle() }
            }
            .buttonStyle(.qbank(.plain))
            .accessibilityIdentifier("signIn.forgot")
            if showsForgotPassword {
                Text("This app doesn't send email. Ask the owner to reset your password from his admin account. He'll give you a temporary password, and you'll choose your own the next time you sign in.")
                    .qbankFont(.subheadline)
                    .foregroundStyle(.qbank(.text2))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, QBankSpacing.space3)
                    .transition(.opacity)
            }
        }
    }

    private func signIn() {
        focus = nil
        Task { await model.signIn() }
    }

    private func signInWithPasskey() {
        focus = nil
        Task { await model.signInWithPasskey() }
    }
}

/// The app's "Q" mark, over the sign-in form and the lock screen.
struct QBankMark: View {
    var body: some View {
        Text("Q")
            .font(.system(size: 30, weight: .black, design: .rounded))
            .foregroundStyle(.qbank(.textOnTint))
            .frame(width: 64, height: 64)
            .background(.qbank(.tint), in: .rect(cornerRadius: 16, style: .continuous))
            .accessibilityHidden(true)
    }
}
