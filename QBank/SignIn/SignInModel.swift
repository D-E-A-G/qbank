import Foundation
import Observation
import QBankKit

/// The sign-in screen: her QBank email and password, or a passkey, the same as on the web.
@Observable
final class SignInModel {
    var email = ""
    var password = ""
    private(set) var isSigningIn = false
    private(set) var isUsingPasskey = false
    private(set) var problem: String?

    /// True while either way of signing in is under way; both buttons wait for it.
    var isBusy: Bool {
        isSigningIn || isUsingPasskey
    }

    private let app: AppModel

    init(app: AppModel, handoff: SignInHandoff? = nil) {
        self.app = app
        email = handoff?.email ?? ""
        problem = handoff?.problem ?? app.signedOutReason
    }

    func signIn() async {
        guard !isBusy else { return }
        guard !trimmedEmail.isEmpty, !password.isEmpty else {
            problem = "Enter your email and password."
            return
        }
        isSigningIn = true
        problem = nil
        defer { isSigningIn = false }
        do {
            let signedIn = try await app.client.signIn(email: trimmedEmail, password: password)
            app.signedIn(signedIn, password: password)
        } catch {
            problem = Wording.problem(error)
            password = ""
        }
    }

    /// Signs in with one of the web domain's passkeys, which needs neither field. Closing the
    /// passkey sheet says nothing.
    func signInWithPasskey() async {
        guard !isBusy else { return }
        isUsingPasskey = true
        problem = nil
        defer { isUsingPasskey = false }
        do {
            let options = try await app.client.passkeySignInOptions()
            let assertion = try await app.passkeys.signIn(options)
            let signedIn = try await app.client.signIn(with: assertion, answering: options)
            app.signedIn(signedIn, password: nil)
        } catch {
            problem = Wording.passkeyProblem(error)
        }
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
