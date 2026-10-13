import QBankKit
import Testing
@testable import QBank

@MainActor
struct DebugLaunchScenarioTests {
    @Test func normalLaunchHasNoScenario() throws {
        #expect(try DebugLaunchScenario.scenario(in: [:]) == nil)
        #expect(DebugLaunchScenario.makeModel(environment: [:]) == nil)
    }

    @Test func signedOutScenarioStartsOnSignIn() throws {
        let environment = [DebugLaunchScenario.scenarioKey: "signed-out"]
        #expect(try DebugLaunchScenario.scenario(in: environment) == .signedOut)
        #expect(DebugLaunchScenario.makeModel(environment: environment)?.route == .signedOut)
    }

    @Test func signedInScenarioStartsOnHomeAndLandsOnMentalHealth() async throws {
        let app = try #require(DebugLaunchScenario.makeModel(environment: [DebugLaunchScenario.scenarioKey: "signed-in"]))
        #expect(app.account?.email == FakeQBankServer.student.email)
        await app.refreshSession()
        let home = HomeModel(app: app)
        await home.load()
        #expect(home.semesters?.map(\.name) == ["Semester 1", "Semester 2"])
        #expect(await home.landingCourse() == CourseRoute(id: FakeQBankServer.mentalHealthID, code: "NURS 310"))
    }

    @Test func fakeServerSignsInAndRefusesWrongPasswords() async throws {
        let app = try #require(DebugLaunchScenario.makeModel(environment: [DebugLaunchScenario.scenarioKey: "signed-out"]))
        let model = SignInModel(app: app)
        model.email = FakeQBankServer.student.email
        model.password = "wrong"
        await model.signIn()
        #expect(model.problem == "That email or password is not right.")
        model.password = FakeQBankServer.student.password
        await model.signIn()
        #expect(app.route == .signedIn(app.account!))
    }

    @Test func fakeServerRestoresOnce() async throws {
        let app = try #require(DebugLaunchScenario.makeModel(environment: [DebugLaunchScenario.scenarioKey: "signed-in"]))
        let course = CourseModel(app: app, id: FakeQBankServer.mentalHealthID)
        await course.load()
        let replaced = try #require(course.course?.weeks[1].sets.last)
        #expect(replaced.status == .replaced)
        await course.restore(replaced)
        #expect(course.course?.weeks[1].sets.last?.status == .restored)
        #expect(course.problem == nil)
    }

    @Test func unknownScenarioIsRejected() {
        let environment = [DebugLaunchScenario.scenarioKey: "welcome"]
        #expect(throws: DebugLaunchScenario.UnknownScenario.self) {
            try DebugLaunchScenario.scenario(in: environment)
        }
    }
}
