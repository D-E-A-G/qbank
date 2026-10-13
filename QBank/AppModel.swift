import Observation
import QBankKit

/// The app's top-level state: who is signed in, the client every screen talks through, and what
/// the phone keeps for her account to study without signal.
@Observable
final class AppModel {
    enum Route: Equatable {
        /// No session on this phone: the sign-in screen.
        case signedOut
        /// The owner reset her password: she chooses a new one before anything else.
        case choosingPassword(Account)
        case signedIn(Account)
    }

    private(set) var route: Route {
        didSet { openOffline() }
    }
    /// Said on the sign-in screen after the server ended the session.
    private(set) var signedOutReason: String?
    /// The password she just signed in with, offered on the choose-a-new-password screen.
    private(set) var temporaryPassword: String?
    /// True once Home has opened the course she used last, so it happens once per sign-in.
    var hasLanded = false

    let client: QBankClient
    /// Light or dark, chosen in Settings and kept on this phone.
    let look: LookStore
    /// How she left each course page on this phone: open folders, by week or by exam.
    let courseMemory: CourseMemory
    /// Whether the phone has a network path.
    let connection: Connection
    /// Saved courses and unsent answers for the account on this phone. Nil when signed out.
    private(set) var offline: OfflineStore?

    private let storage: PhoneStorage
    private let networkWatcher: NetworkWatcher?

    init(
        client: QBankClient,
        look: LookStore = LookStore(),
        courseMemory: CourseMemory = CourseMemory(),
        storage: PhoneStorage,
        connection: Connection = Connection(),
        networkWatcher: NetworkWatcher? = nil
    ) {
        self.client = client
        self.look = look
        self.courseMemory = courseMemory
        self.storage = storage
        self.connection = connection
        self.networkWatcher = networkWatcher
        let stored = try? client.storedSession()
        route = stored?.account.map(Self.route(for:)) ?? .signedOut
        openOffline()
        connection.onChange = { [weak self] isOnline in
            self?.offline?.connectionChanged(isOnline: isOnline)
        }
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

    /// Ends the session on the server and on this phone. The phone forgets it even without signal,
    /// with the courses it saved and any answers still waiting to be sent.
    func signOut() async {
        try? await client.signOut()
        if let account {
            await offline?.close()
            offline = nil
            storage.erase(account.id)
        }
        forgetSession(reason: nil)
    }

    /// Reads from the server and keeps a copy on the phone; without a connection, the copy saved last.
    func load<Value: Codable & Sendable>(
        _ key: CacheKey<Value>,
        from fetch: () async throws(QBankError) -> Value
    ) async throws(QBankError) -> Loaded<Value> {
        guard let offline else { return Loaded(value: try await fetch(), savedAt: nil) }
        return try await offline.load(key, from: fetch)
    }

    /// Sends a practice answer, or keeps it on the phone to send when QBank can be reached.
    func submit(_ submission: AttemptSubmission, courseID: String) async throws(QBankError) -> Delivery {
        guard let offline else { return .sent(try await client.recordAttempt(submission)) }
        return try await offline.submit(submission, courseID: courseID)
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

    /// Opens the phone's store for the account signed in, keeping it while the account stays. An
    /// ended session closes it but leaves its files, so waiting answers go once she signs in again.
    private func openOffline() {
        guard let account else {
            offline?.stop()
            offline = nil
            return
        }
        guard offline?.accountID != account.id else { return }
        offline?.stop()
        let store = OfflineStore(accountID: account.id, client: client, connection: connection, storage: storage.open(account.id))
        offline = store
        store.sendIfWaiting()
    }

    /// The model the app starts with. Debug builds let UI tests choose a scenario through
    /// `DebugLaunchScenario`; Release builds always talk to the live server.
    static func launch() -> AppModel {
        #if DEBUG
        if let model = DebugLaunchScenario.makeModel() {
            return model
        }
        #endif
        let connection = Connection()
        return AppModel(
            client: QBankClient(sessionStore: KeychainSessionStore()),
            storage: .standard(),
            connection: connection,
            networkWatcher: NetworkWatcher(connection: connection)
        )
    }
}
