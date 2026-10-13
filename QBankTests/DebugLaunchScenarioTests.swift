import Testing
@testable import QBank

@MainActor
struct DebugLaunchScenarioTests {
    @Test func normalLaunchHasNoScenario() throws {
        #expect(try DebugLaunchScenario.scenario(in: [:]) == nil)
        #expect(DebugLaunchScenario.makeModel(environment: [:]) == nil)
    }

    @Test func welcomeScenarioStartsOnWelcome() throws {
        let environment = [DebugLaunchScenario.scenarioKey: "welcome"]
        #expect(try DebugLaunchScenario.scenario(in: environment) == .welcome)
        #expect(DebugLaunchScenario.makeModel(environment: environment)?.route == .welcome)
    }

    @Test func unknownScenarioIsRejected() {
        let environment = [DebugLaunchScenario.scenarioKey: "signed-in"]
        #expect(throws: DebugLaunchScenario.UnknownScenario.self) {
            try DebugLaunchScenario.scenario(in: environment)
        }
    }
}
