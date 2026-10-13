import Observation
import QBankKit

/// The app's top-level state: who is signed in, and the client every screen talks through.
@Observable
final class AppModel {
    enum Route: Equatable {
        /// No session on this phone: the sign-in screen.
        case signedOut
        /// The owner reset her password: she chooses a new one before anything else.
        case choosingPassword(Account)
        case signedIn(Account)
    }

    private(set) var route: Route
    /// Said on the sign-in screen after the server ended the session.
    private(set) var signedOutReason: String?
    /// The password she just signed in with, offered on the choose-a-new-password screen.
    private(set) var temporaryPassword: String?
    /// True once Home has opened the course she used last, so it happens once per sign-in.
    var hasLanded = false

    let client: QBankClient

    init(client: QBankClient) {
        self.client = client
        let stored = try? client.storedSession()
        route = stored?.account.map(Self.route(for:)) ?? .signedOut
    }

    var account: Account? {
        switch route {
        case .signedOut: nil
        case .choosingPassword(let account), .signedIn(let account): account
        }
    }

    /// Checks the stored session with the server. The phone stays signed in when the server
    /// cannot be reached; only a session the server has ended signs her out.
    func refreshSession() async {
        guard account != nil else { return }
        do {
            let session = try await client.session()
            route = Self.route(for: session.user)
        } catch {
            handle(error)
        }
    }

    /// After a password sign-in.
    func signedIn(_ signedIn: SignedIn, password: String) {
        signedOutReason = nil
        hasLanded = false
        temporaryPassword = signedIn.user.mustChangePassword ? password : nil
        route = Self.route(for: signedIn.user)
    }

    /// After she chose a new password.
    func passwordChosen(_ signedIn: SignedIn) {
        temporaryPassword = nil
        route = Self.route(for: signedIn.user)
    }

    /// Ends the session on the server and on this phone. The phone forgets it even without signal.
    func signOut() async {
        try? await client.signOut()
        forgetSession(reason: nil)
    }

    /// Reacts to a failure any screen ran into. Returns true when it changed the route, so the
    /// screen has nothing more to say.
    @discardableResult
    func handle(_ error: QBankError) -> Bool {
        if error.needsSignIn {
            try? client.sessionStore.clear()
            forgetSession(reason: "Your session ended. Sign in again.")
            return true
        }
        if error.serverCode == .mustChangePassword, let account {
            route = .choosingPassword(account)
            return true
        }
        return false
    }

    private func forgetSession(reason: String?) {
        signedOutReason = reason
        temporaryPassword = nil
        hasLanded = false
        route = .signedOut
    }

    private static func route(for account: Account) -> Route {
        account.mustChangePassword ? .choosingPassword(account) : .signedIn(account)
    }

    /// The model the app starts with. Debug builds let UI tests choose a scenario through
    /// `DebugLaunchScenario`; Release builds always talk to the live server.
    static func launch() -> AppModel {
        #if DEBUG
        if let model = DebugLaunchScenario.makeModel() {
            return model
        }
        #endif
        return AppModel(client: QBankClient(sessionStore: KeychainSessionStore()))
    }
}
