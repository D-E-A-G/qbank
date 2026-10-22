import Foundation
import Observation
import QBankKit

/// The sign-up screen: a user account for an email the owner added to the sign-up list, the same
/// as on the web. The new account is signed in at once, and offered a passkey as after a password
/// sign-in.
@Observable
final class SignUpModel {
    var email = ""
    var password = ""
    private(set) var isSigningUp = false
    private(set) var problem: String?
    /// Set when the account was made but its sign-in failed: the Sign in screen takes over, with
    /// this email and the server's sentence.
    private(set) var madeButNotSignedIn: SignInHandoff?

    private let app: AppModel

    init(app: AppModel) {
        self.app = app
    }

    func signUp() async {
        guard !isSigningUp else { return }
        guard !trimmedEmail.isEmpty, !password.isEmpty else {
            problem = "Enter your email and a password."
            return
        }
        if let rule = PasswordRules.problem(newPassword: password) {
            problem = rule
            return
        }
        isSigningUp = true
        problem = nil
        defer { isSigningUp = false }
        do {
            let signedIn = try await app.client.signUp(email: trimmedEmail, password: password)
            app.signedIn(signedIn, password: password)
        } catch {
            // A refused email (403) or a locked one (429) is said in the server's words, which
            // already say what to do next. The password goes, as after a wrong sign-in, so iOS
            // does not offer to save it for an account that was not made.
            if error.serverCode == .authFailed {
                madeButNotSignedIn = SignInHandoff(email: trimmedEmail, problem: Wording.problem(error))
            } else {
                problem = Wording.problem(error)
                password = ""
            }
        }
    }

    /// Back to Sign in without an account: the password typed here goes, so iOS does not offer to
    /// save it.
    func leave() {
        password = ""
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// What the Sign in screen opens with when sign-up hands over to it.
struct SignInHandoff: Equatable {
    let email: String
    let problem: String?
}
