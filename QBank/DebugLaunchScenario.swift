#if DEBUG
import Foundation
import QBankKit

/// Launch-environment seam for UI tests and local simulator review. Compiled
/// only into Debug builds; Release binaries contain none of it. Every scenario
/// composes synthetic data and in-process fakes, never a real account or the
/// production server: the app talks to `FakeQBankServer` and keeps its session
/// in memory, so the Keychain is never touched.
///
/// Supported environment variables:
/// - `QB_UITEST_SCENARIO`: the scenario to start in, one of `Scenario`'s raw
///   values. Absent means a normal launch.
nonisolated enum DebugLaunchScenario {
    static let scenarioKey = "QB_UITEST_SCENARIO"

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
    @MainActor
    static func makeModel(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AppModel? {
        let scenario: Scenario?
        do {
            scenario = try self.scenario(in: environment)
        } catch {
            fatalError(error.description)
        }
        switch scenario {
        case nil:
            return nil
        case .signedOut:
            return model(server: FakeQBankServer(signedIn: false), session: nil)
        case .signedIn:
            return model(server: FakeQBankServer(signedIn: true), session: FakeQBankServer.storedStudentSession())
        }
    }

    @MainActor
    private static func model(server: FakeQBankServer, session: StoredSession?) -> AppModel {
        AppModel(client: QBankClient(
            configuration: APIConfiguration(baseURL: URL(string: "https://fake-qbank.invalid")!),
            transport: server,
            sessionStore: InMemorySessionStore(session)
        ))
    }
}
#endif
