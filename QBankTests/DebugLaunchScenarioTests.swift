import Foundation
import QBankKit
import Testing
@testable import QBank

/// Serialized: the network notifications reach every scenario model alive in the process.
@MainActor
@Suite(.serialized)
struct DebugLaunchScenarioTests {
    /// A scenario's model with a phone folder of its own, so tests running side by side never share one.
    static func launch(_ environment: [String: String], folder: URL = OfflineStoreTests.temporaryFolder()) -> AppModel? {
        DebugLaunchScenario.makeModel(environment: environment, phoneFolder: folder)
    }

    static func launch(_ scenario: String) -> AppModel? {
        launch([DebugLaunchScenario.scenarioKey: scenario])
    }
    @Test func normalLaunchHasNoScenario() throws {
        #expect(try DebugLaunchScenario.scenario(in: [:]) == nil)
        #expect(Self.launch([:]) == nil)
    }

    @Test func signedOutScenarioStartsOnSignIn() throws {
        let environment = [DebugLaunchScenario.scenarioKey: "signed-out"]
        #expect(try DebugLaunchScenario.scenario(in: environment) == .signedOut)
        #expect(Self.launch(environment)?.route == .signedOut)
    }

    @Test func signedInScenarioStartsOnHomeAndLandsOnMentalHealth() async throws {
        let app = try #require(Self.launch("signed-in"))
        #expect(app.account?.email == FakeQBankServer.student.email)
        await app.refreshSession()
        let home = HomeModel(app: app)
        await home.load()
        #expect(home.semesters?.map(\.name) == ["Semester 1", "Semester 2"])
        #expect(await home.landingCourse() == CourseRoute(id: FakeQBankServer.mentalHealthID, code: "NURS 310"))
    }

    @Test func fakeServerSignsInAndRefusesWrongPasswords() async throws {
        let app = try #require(Self.launch("signed-out"))
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
        let app = try #require(Self.launch("signed-in"))
        let course = CourseModel(app: app, id: FakeQBankServer.mentalHealthID)
        await course.load()
        let replaced = try #require(course.course?.weeks[1].sets.last)
        #expect(replaced.status == .replaced)
        await course.restore(replaced)
        #expect(course.course?.weeks[1].sets.last?.status == .restored)
        #expect(course.problem == nil)
    }

    @Test func fakeServerEditsTheCatalogAsTheServerDoes() async throws {
        let app = try #require(Self.launch("signed-in"))
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
        let app = try #require(Self.launch("signed-in"))
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
        let first = try #require(Self.launch(environment))
        #expect(first.look.look == .matchDevice)
        first.look.look = .dark
        var keep = environment
        keep[DebugLaunchScenario.keepPhoneSettingsKey] = "1"
        #expect(Self.launch(keep)?.look.look == .dark)
        #expect(Self.launch(environment)?.look.look == .matchDevice)
    }

    @Test func fakeServerServesEveryFormatAndScoresWithTheServersRules() async throws {
        let app = try #require(Self.launch("signed-in"))
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

    @Test func phoneDataIsEmptiedUnlessKept() async throws {
        let folder = OfflineStoreTests.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let offline = [DebugLaunchScenario.scenarioKey: "signed-in", DebugLaunchScenario.networkKey: "offline"]
        let first = try #require(Self.launch(offline, folder: folder))
        let submission = AttemptSubmission(clientAttemptID: AttemptSubmission.newID(), questionID: "mixed-v1-q0", response: .single(choice: 0))
        #expect(try await first.submit(submission, courseID: FakeQBankServer.mentalHealthID) == .waiting(reason: .transport(.notConnectedToInternet)))

        var keep = offline
        keep[DebugLaunchScenario.keepPhoneDataKey] = "1"
        #expect(Self.launch(keep, folder: folder)?.offline?.waiting.map(\.id) == [submission.clientAttemptID])
        #expect(Self.launch(offline, folder: folder)?.offline?.waiting.isEmpty == true)
    }

    @Test func theNetworkCanStartOffAndTheTestTurnsItOn() async throws {
        let environment = [DebugLaunchScenario.scenarioKey: "signed-in", DebugLaunchScenario.networkKey: "offline"]
        let app = try #require(Self.launch(environment))
        #expect(!app.connection.isOnline)
        await #expect(throws: QBankError.transport(.notConnectedToInternet)) {
            _ = try await app.client.semesters()
        }

        // As a UI test does from its own process.
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(center, CFNotificationName(DebugLaunchScenario.networkOnlineNotification as CFString), nil, nil, true)
        try await waitUntil { app.connection.isOnline }
        #expect(try await app.client.semesters().count == 2)

        CFNotificationCenterPostNotification(center, CFNotificationName(DebugLaunchScenario.networkOfflineNotification as CFString), nil, nil, true)
        try await waitUntil { !app.connection.isOnline }
    }

    @Test func fakeServerServesTheSetsOfBothCourses() async throws {
        let app = try #require(Self.launch("signed-in"))
        let course = try await app.client.course(id: FakeQBankServer.fundamentalsID)
        for set in course.weeks.flatMap(\.sets) {
            let practice = try await app.client.practiceSet(id: set.id)
            #expect(practice.courseID == FakeQBankServer.fundamentalsID)
            #expect(practice.questions.count == set.questionCount)
        }
        let first = try #require(course.weeks.first?.sets.first)
        let saved = try await app.client.recordAttempt(AttemptSubmission(questionID: first.questionIDs[0], response: .single(choice: 0)))
        #expect(saved.courseID == FakeQBankServer.fundamentalsID)
    }

    // MARK: Slice 1c: the fake server keeps the server's study rules

    @Test func fakeServerRunsAWrongQuestionsExamAsTheServerDoes() async throws {
        let app = try #require(Self.launch("signed-in"))
        let course = CourseRef(id: FakeQBankServer.mentalHealthID, code: "NURS 310", title: "Mental Health")
        let setup = ExamSetupModel(app: app, route: ExamSetupRoute(course: course))
        await setup.load()
        #expect(setup.weeks.map(\.label) == ["Week 1", "Week 2", "Week 3", "Weeks 1-3"])
        #expect(setup.setup?.exams.count == 3)
        #expect(setup.setup?.exams.map(\.courseExamID) == ["c0e00000-0000-4000-8000-000000000001", nil, "c0e00000-0000-4000-8000-000000000001"])
        setup.wrongOnly = true
        for week in setup.weeks.prefix(2) { setup.toggle(week) }
        #expect(setup.summaryCount == "11 questions")
        let exam = try #require(await setup.start())
        #expect(exam.questions.count == 11)
        #expect(exam.practiceWeeks == ["Week 2"])
        #expect(exam.secondsLeftAtServerNow > 16 * 60)

        // A week with nothing wrong is refused, as the server words it.
        let wrongOnly = try await #require(throws: QBankError.self) {
            try await app.client.startExam(courseID: course.id, weeks: ["Week 3"], pool: .wrong)
        }
        #expect(wrongOnly.serverCode == .noWrongQuestions)
        #expect(Wording.problem(wrongOnly) == "Week 3 has no wrong questions. Untick it, or turn off Wrong questions only.")
    }

    @Test func fakeServerKeepsCourseExamRules() async throws {
        let app = try #require(Self.launch("signed-in"))
        let id = FakeQBankServer.mentalHealthID
        let taken = try await #require(throws: QBankError.self) {
            try await app.client.createCourseExam(courseID: id, name: "Exam 3", weekLabels: ["Week 2", "Week 3"])
        }
        #expect(Wording.problem(taken) == "Week 2 is in Exam 1. Week 3 is in Exam 2.")
        let unknown = try await #require(throws: QBankError.self) {
            try await app.client.createCourseExam(courseID: id, name: "Exam 3", weekLabels: ["Week 9"])
        }
        #expect(Wording.problem(unknown) == "Week 9 is not a week in this course.")
        let created = try await app.client.createCourseExam(courseID: id, name: " Exam 3 ", weekLabels: ["Weeks 1-3"])
        #expect(created.name == "Exam 3")
        #expect(created.sortOrder == 3)
        try await app.client.deleteCourseExam(id: created.id)
        let gone = try await #require(throws: QBankError.self) { try await app.client.deleteCourseExam(id: created.id) }
        #expect(Wording.problem(gone) == "That exam is not in the app.")
        let course = try await app.client.course(id: id)
        #expect(course.exams.map(\.name) == ["Exam 1", "Exam 2"])
    }

    @Test func fakeServerKeepsReviewAsTheServerDoes() async throws {
        let app = try #require(Self.launch("signed-in"))
        let id = FakeQBankServer.mentalHealthID
        let list = try await app.client.review(courseID: id)
        #expect(list.counts.all == 12)
        #expect(list.counts.missed == 6)
        #expect(list.counts.partial == 3)
        #expect(list.counts.guessed == 4)
        let times = list.questions.map(\.answeredAt)
        #expect(times == times.sorted { $0 > $1 }, "newest first")
        let practice = try await app.client.reviewPractice(courseID: id, filter: .missed)
        #expect(practice.questions.count == 6)
        #expect(practice.title == "Review")
        let right = AttemptSubmission(questionID: "rights-v1-q0", response: .single(choice: 0))
        _ = try await app.client.recordAttempt(right)
        #expect(try await app.client.review(courseID: id).counts.missed == 5, "answered fully right without guessing, it leaves")
        let unconfirmed = try await #require(throws: QBankError.self) { try await app.client.clearReview(courseID: id, confirmed: false) }
        #expect(Wording.problem(unconfirmed) == "Clear all 11 questions from this course's Review list?")
        #expect(try await app.client.clearReview(courseID: id) == 11)
        #expect(try await app.client.course(id: id).reviewCount == 0)
    }
}
