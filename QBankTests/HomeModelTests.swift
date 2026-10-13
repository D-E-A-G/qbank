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

    @Test func failedReloadKeepsTheCoursesOnScreen() async {
        let server = StubServer(["GET /api/semesters": .ok(Bodies.semesters())])
        let (app, _) = TestApp.make(server, account: .student())
        let model = HomeModel(app: app)
        await model.load()
        server["GET /api/semesters"] = .offline
        await model.load()
        #expect(model.semesters?.first?.courses.count == 1)
        #expect(model.problem == "No connection. Check Wi-Fi or cellular data and try again.")
        #expect(model.isLoading == false)
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
        #expect(await model.landingCourse() == CourseRoute(id: "c1", code: "NURS 101"))
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
