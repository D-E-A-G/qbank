#if DEBUG
import Foundation
import QBankKit

/// Launch-environment seam for UI tests and local simulator review. Compiled
/// only into Debug builds; Release binaries contain none of it. Every scenario
/// composes synthetic data and in-process fakes, never a real account or the
/// production server: the app talks to `FakeQBankServer` and keeps its session
/// in memory, so the Keychain is never touched. Settings kept on the phone, such
/// as Look and the course page's open folders, live in their own defaults
/// suite, and saved courses and unsent answers in their own folder,
/// `Application Support/QBankUITest`; both are emptied at launch.
///
/// Supported environment variables:
/// - `QB_UITEST_SCENARIO`: the scenario to start in, one of `Scenario`'s raw
///   values. Absent means a normal launch.
/// - `QB_UITEST_KEEP_PHONE_SETTINGS`: `1` keeps the suite from the previous
///   launch, to check that a setting survives a relaunch.
/// - `QB_UITEST_KEEP_PHONE_DATA`: `1` keeps the courses saved and the answers
///   left waiting by the previous launch, to check that they survive a relaunch.
///   The fake server starts afresh either way.
/// - `QB_UITEST_NETWORK`: `offline` starts without a network; absent or
///   `online` starts with one.
///
/// While the app runs, a test turns the network off and on by posting the
/// Darwin notifications `networkOfflineNotification` and
/// `networkOnlineNotification` (see `DebugNetwork`).
nonisolated enum DebugLaunchScenario {
    static let scenarioKey = "QB_UITEST_SCENARIO"
    static let keepPhoneSettingsKey = "QB_UITEST_KEEP_PHONE_SETTINGS"
    static let keepPhoneDataKey = "QB_UITEST_KEEP_PHONE_DATA"
    static let networkKey = "QB_UITEST_NETWORK"
    static let defaultsSuite = "com.dimitrygallego.qbank.uitest"
    static let networkOfflineNotification = "com.dimitrygallego.qbank.uitest.network.offline"
    static let networkOnlineNotification = "com.dimitrygallego.qbank.uitest.network.online"

    /// The network of the app's scenario, kept while the app runs.
    @MainActor private static var network: DebugNetwork?

    enum Scenario: String, CaseIterable {
        /// No session on the phone: the sign-in screen. `FakeQBankServer.student`
        /// signs in normally; `FakeQBankServer.resetStudent` must choose a new password.
        case signedOut = "signed-out"
        /// `FakeQBankServer.student` is signed in from an earlier launch and last
        /// used the Mental Health course.
        case signedIn = "signed-in"
    }

    struct UnknownScenario: Error, CustomStringConvertible {
        let name: String

        var description: String {
            let known = Scenario.allCases.map(\.rawValue).joined(separator: ", ")
            return "Unknown \(DebugLaunchScenario.scenarioKey) \"\(name)\"; known scenarios: \(known)"
        }
    }

    /// The scenario the environment asks for, or nil for a normal launch.
    static func scenario(in environment: [String: String]) throws(UnknownScenario) -> Scenario? {
        guard let name = environment[scenarioKey] else { return nil }
        guard let scenario = Scenario(rawValue: name) else { throw UnknownScenario(name: name) }
        return scenario
    }

    /// The model for the requested scenario, or nil for a normal launch. An
    /// unknown scenario stops the app so a test never silently runs against
    /// the default state.
    ///
    /// - Parameter phoneFolder: Where saved courses and unsent answers go; unit
    ///   tests give each model its own.
    @MainActor
    static func makeModel(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        phoneFolder: URL? = nil
    ) -> AppModel? {
        let scenario: Scenario?
        do {
            scenario = try self.scenario(in: environment)
        } catch {
            fatalError(error.description)
        }
        guard let scenario else { return nil }
        let defaults = phoneSettings(keep: environment[keepPhoneSettingsKey] == "1")
        let storage = phoneData(in: phoneFolder ?? defaultPhoneFolder, keep: environment[keepPhoneDataKey] == "1")
        let isOnline = environment[networkKey] != "offline"
        switch scenario {
        case .signedOut:
            return model(server: FakeQBankServer(signedIn: false), session: nil, defaults: defaults, storage: storage, isOnline: isOnline)
        case .signedIn:
            return model(
                server: FakeQBankServer(signedIn: true), session: FakeQBankServer.storedStudentSession(),
                defaults: defaults, storage: storage, isOnline: isOnline
            )
        }
    }

    static var defaultPhoneFolder: URL {
        URL.applicationSupportDirectory.appendingPathComponent("QBankUITest", isDirectory: true)
    }

    /// The scenario's own folder for saved courses and unsent answers, emptied unless kept.
    static func phoneData(in folder: URL, keep: Bool) -> PhoneStorage {
        if !keep {
            try? FileManager.default.removeItem(at: folder)
        }
        return .files(root: folder)
    }

    /// The scenario's own defaults suite, so a test never sees the developer's settings or
    /// another test's.
    static func phoneSettings(keep: Bool) -> UserDefaults {
        let defaults = UserDefaults(suiteName: defaultsSuite)!
        if !keep {
            defaults.removePersistentDomain(forName: defaultsSuite)
        }
        return defaults
    }

    @MainActor
    private static func model(
        server: FakeQBankServer, session: StoredSession?, defaults: UserDefaults, storage: PhoneStorage, isOnline: Bool
    ) -> AppModel {
        let connection = Connection(isOnline: isOnline)
        let network = DebugNetwork(server: server, connection: connection, isOnline: isOnline)
        network.listen()
        self.network = network
        return AppModel(
            client: QBankClient(
                configuration: APIConfiguration(baseURL: URL(string: "https://fake-qbank.invalid")!),
                transport: server,
                sessionStore: InMemorySessionStore(session)
            ),
            look: LookStore(defaults: defaults),
            courseMemory: CourseMemory(defaults: defaults),
            storage: storage,
            connection: connection
        )
    }
}
#endif
