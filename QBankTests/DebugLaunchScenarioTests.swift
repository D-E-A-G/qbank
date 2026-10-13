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

    @Test func fakeServerEditsTheCatalogAsTheServerDoes() async throws {
        let app = try #require(DebugLaunchScenario.makeModel(environment: [DebugLaunchScenario.scenarioKey: "signed-in"]))
        let catalog = CatalogModel(app: app)
        await catalog.load()
        #expect(catalog.nextSemesterNumber == 3)
        await catalog.addSemester()
        #expect(catalog.semesters?.map(\.name) == ["Semester 1", "Semester 2", "Semester 3"])

        let semester = SemesterModel(catalog: catalog, id: FakeQBankServer.semester2ID)
        semester.newCode = "nurs 310"
        semester.newTitle = "Pediatrics"
        await semester.addCourse()
        #expect(semester.addProblem == nil)

        let course = CourseEditModel(catalog: catalog, id: FakeQBankServer.mentalHealthID)
        course.semesterID = FakeQBankServer.semester2ID
        await course.save()
        #expect(course.problem == "This semester already has a course with the code NURS 310.")
        course.code = "NURS 311"
        await course.save()
        #expect(course.problem == nil)
        await course.toggleArchived()
        #expect(course.isArchived)

        let home = HomeModel(app: app)
        await home.load()
        let second = try #require(home.semesters?.first { $0.id == FakeQBankServer.semester2ID })
        #expect(home.courses(in: second).map(\.code) == ["nurs 310"])
        let detail = CourseModel(app: app, id: FakeQBankServer.mentalHealthID)
        await detail.load()
        #expect(detail.course?.code == "NURS 311")
        #expect(detail.course?.semester.number == 2)
    }

    @Test func fakeServerRefusesPasswordsAsTheServerDoes() async throws {
        let app = try #require(DebugLaunchScenario.makeModel(environment: [DebugLaunchScenario.scenarioKey: "signed-in"]))
        let wrong = await #expect(throws: QBankError.self) {
            try await app.client.changePassword(current: "not-it", new: "synthetic-pass-9")
        }
        #expect(wrong?.serverCode == .invalidCredentials)
        let same = await #expect(throws: QBankError.self) {
            try await app.client.changePassword(current: FakeQBankServer.student.password, new: FakeQBankServer.student.password)
        }
        #expect(same?.serverCode == .samePassword)
        let short = await #expect(throws: QBankError.self) {
            try await app.client.changePassword(current: FakeQBankServer.student.password, new: "short")
        }
        #expect(short?.serverCode == .invalidRequest)
        let changed = try await app.client.changePassword(current: FakeQBankServer.student.password, new: "synthetic-pass-9")
        #expect(changed.user.email == FakeQBankServer.student.email)
    }

    @Test func phoneSettingsStartEmptyUnlessKept() throws {
        let environment = [DebugLaunchScenario.scenarioKey: "signed-in"]
        let first = try #require(DebugLaunchScenario.makeModel(environment: environment))
        #expect(first.look.look == .matchDevice)
        first.look.look = .dark
        var keep = environment
        keep[DebugLaunchScenario.keepPhoneSettingsKey] = "1"
        #expect(DebugLaunchScenario.makeModel(environment: keep)?.look.look == .dark)
        #expect(DebugLaunchScenario.makeModel(environment: environment)?.look.look == .matchDevice)
    }

    @Test func fakeServerServesEveryFormatAndScoresWithTheServersRules() async throws {
        let app = try #require(DebugLaunchScenario.makeModel(environment: [DebugLaunchScenario.scenarioKey: "signed-in"]))
        let set = try await app.client.practiceSet(id: "mixed-v1")
        #expect(set.courseID == FakeQBankServer.mentalHealthID)
        #expect(set.questions.compactMap(\.type) == QuestionType.allCases)
        #expect(set.questions.allSatisfy { !$0.rationale.isEmpty && !$0.takeaway.isEmpty })
        #expect(set.questions[1].table != nil)
        #expect(set.questions[0].images.first?.placement == .rationale)

        let sata = set.questions[2]
        let submission = AttemptSubmission(clientAttemptID: "fake-1", questionID: sata.id, response: .sata(picks: [0, 1, 3]), guessed: true)
        let saved = try await app.client.recordAttempt(submission)
        #expect(saved.status == .partial)
        #expect(saved.points == 1)
        #expect(saved.maxPoints == 3)
        #expect(saved.label == "Partly correct")
        #expect(saved.inReview)
        #expect(!saved.replayed)
        #expect(try await app.client.recordAttempt(submission).replayed, "a repeated id is answered with the saved attempt")

        let course = try await app.client.course(id: FakeQBankServer.mentalHealthID)
        let mixed = try #require(course.weeks.last?.sets.first)
        #expect(mixed.answeredCount == 1)
        #expect(mixed.fullyRightCount == 0)
    }

    @Test func unknownScenarioIsRejected() {
        let environment = [DebugLaunchScenario.scenarioKey: "welcome"]
        #expect(throws: DebugLaunchScenario.UnknownScenario.self) {
            try DebugLaunchScenario.scenario(in: environment)
        }
    }
}
