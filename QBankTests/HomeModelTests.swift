import QBankKit
import Testing
@testable import QBank

@MainActor
struct HomeModelTests {
    @Test func loadsSemestersWithoutArchivedCoursesInTheOwnersOrder() async throws {
        let server = StubServer(["GET /api/semesters": .ok(Bodies.semesters([
            Bodies.course(id: "c2", code: "NURS 220", order: 2),
            Bodies.course(id: "c3", code: "NURS 330", order: 3, archived: true),
            Bodies.course(id: "c1", code: "NURS 101", order: 1),
        ]))])
        let (app, _) = TestApp.make(server, account: .student())
        let model = HomeModel(app: app)
        await model.load()
        let semester = try #require(model.semesters?.first)
        #expect(model.courses(in: semester).map(\.code) == ["NURS 101", "NURS 220"])
        #expect(model.problem == nil)
    }

    @Test func withoutSignalHomeShowsTheSavedCoursesAndHowOldTheyAre() async throws {
        let server = StubServer([
            "GET /api/semesters": .ok(Bodies.semesters([Bodies.course(id: "c1", code: "NURS 101"), Bodies.course(id: "c2", code: "NURS 220", order: 2)])),
            "GET /api/courses/c1": .ok(Bodies.courseDetail()),
        ])
        let (app, _) = TestApp.make(server, account: .student())
        let model = HomeModel(app: app)
        await model.load()
        #expect(model.savedAt == nil)
        await CourseModel(app: app, id: "c1").load()

        server["GET /api/semesters"] = .offline
        await model.load()
        let semester = try #require(model.semesters?.first)
        #expect(model.courses(in: semester).map(\.code) == ["NURS 101", "NURS 220"])
        #expect(model.problem == nil, "a banner says it, not a problem")
        let listSaved = try #require(model.savedAt)
        let courses = model.courses(in: semester)
        let courseSaved = try #require(await app.offline?.saved(.course("c1"))?.savedAt)
        #expect(model.savedAt(courses[0]) == courseSaved, "a course opened later shows its own time")
        #expect(model.savedAt(courses[1]) == listSaved)
        #expect(model.isLoading == false)

        server["GET /api/semesters"] = .ok(Bodies.semesters())
        await model.load()
        #expect(model.savedAt == nil, "back online, the badges go")
        #expect(model.savedAt(courses[0]) == nil)
    }

    @Test func noSignalAndNothingSavedSaysSo() async {
        let server = StubServer(["GET /api/semesters": .offline])
        let (app, _) = TestApp.make(server, account: .student())
        let model = HomeModel(app: app)
        await model.load()
        #expect(model.semesters == nil)
        #expect(model.problem == "No connection. Check Wi-Fi or cellular data and try again.")
    }

    @Test func waitingAnswersCountIntoTheCourseCards() async throws {
        let server = StubServer([
            "GET /api/semesters": .ok(Bodies.semesters([Bodies.course(id: "c1", code: "NURS 101", answered: 3)])),
            "GET /api/courses/c1": .ok(Bodies.courseDetail(sets: [Bodies.set(id: "set1", questionIDs: ["q-sata", "q-single"])])),
            "GET /api/practice-sets/set1": .ok(PracticeModelTests.practiceSet()),
        ])
        let connection = Connection()
        let (app, _) = TestApp.make(server, account: .student(), connection: connection)
        await CourseModel(app: app, id: "c1").load()
        let practice = PracticeModel(app: app, source: .set(id: "set1"), courseID: "c1", title: "Invented set")
        await practice.load()
        connection.update(isOnline: false)
        practice.update(.sata([0, 2]))
        await practice.check()
        #expect(app.offline?.waiting.count == 1)

        let model = HomeModel(app: app)
        await model.load()
        let semester = try #require(model.semesters?.first)
        #expect(model.courses(in: semester).first?.answeredCount == 4)
        #expect(Wording.answeredPercent(try #require(model.courses(in: semester).first)) == 40)
    }

    @Test func savingForOfflineWaitsForTheServersCopy() async throws {
        let server = StubServer([
            "GET /api/semesters": .ok(Bodies.semesters()),
            "GET /api/courses/c1": .ok(Bodies.courseDetail()),
            "GET /api/practice-sets/set1": .ok(PracticeModelTests.practiceSet()),
        ])
        let (app, _) = TestApp.make(server, account: .student())
        let model = HomeModel(app: app)
        await model.load()
        model.saveForOffline()
        await app.offline?.finishSavingCourses()
        #expect(server.calls.contains("GET /api/practice-sets/set1"))
        #expect(await app.offline?.saved(.practiceSet("set1")) != nil)
    }

    @Test func endedSessionSignsOut() async {
        let server = StubServer(["GET /api/semesters": .error(401, "unauthenticated", "Sign in to continue.")])
        let (app, _) = TestApp.make(server, account: .student())
        let model = HomeModel(app: app)
        await model.load()
        #expect(app.route == .signedOut)
        #expect(model.problem == nil)
    }

    @Test func landsOnTheLastCourseOncePerSignIn() async {
        let server = StubServer([
            "GET /api/semesters": .ok(Bodies.semesters()),
            "GET /api/me/place": .ok(Bodies.place("c1")),
        ])
        let (app, _) = TestApp.make(server, account: .student())
        let model = HomeModel(app: app)
        await model.load()
        #expect(await model.landingCourse() == CourseRoute(id: "c1", name: "NURS 101"))
        #expect(await model.landingCourse() == nil)
        #expect(server.calls.filter { $0 == "GET /api/me/place" }.count == 1)
    }

    @Test func noPlaceStaysOnHome() async {
        let server = StubServer(["GET /api/me/place": .ok(Bodies.place(nil))])
        let (app, _) = TestApp.make(server, account: .student())
        #expect(await HomeModel(app: app).landingCourse() == nil)
    }

    @Test func adminHasNoStudyPlace() async {
        let server = StubServer()
        let (app, _) = TestApp.make(server, account: .admin)
        #expect(await HomeModel(app: app).landingCourse() == nil)
        #expect(server.requests.isEmpty)
    }
}
