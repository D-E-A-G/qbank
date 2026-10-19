import QBankKit
import Testing
@testable import QBank

/// A new account on a server where every library is the account's own: no semesters, no courses,
/// no topics, and no study place. Every screen that lists her courses still works and says so.
@MainActor
struct EmptyLibraryTests {
    /// Home's answer for a fresh account once content is per account, with the topics list beside it.
    static let emptyLibrary = #"{"semesters":[],"topics":[]}"#

    @Test func homeLoadsAnEmptyLibraryAndLandsNowhere() async {
        let server = StubServer([
            "GET /api/semesters": .ok(Self.emptyLibrary),
            "GET /api/me/place": .ok(Bodies.place(nil)),
        ])
        let (app, _) = TestApp.make(server, account: .student())
        let model = HomeModel(app: app)
        await model.load()
        #expect(model.semesters == [])
        #expect(model.problem == nil)
        #expect(await model.landingCourse() == nil)
    }

    @Test func homeLoadsASemesterWithNoCourses() async throws {
        let server = StubServer(["GET /api/semesters": .ok(Bodies.semesters([]))])
        let (app, _) = TestApp.make(server, account: .student())
        let model = HomeModel(app: app)
        await model.load()
        let semester = try #require(model.semesters?.first)
        #expect(model.courses(in: semester).isEmpty)
        #expect(model.problem == nil)
    }

    @Test func importOnAnEmptyLibraryMakesANewCourse() async {
        let server = StubServer(["GET /api/semesters": .ok(Self.emptyLibrary)])
        let (app, _) = TestApp.make(server, account: .student())
        let model = ImportModel(app: app)
        await model.load()
        #expect(model.problem == nil)
        #expect(model.destination.courses == [])
        #expect(model.destination.course == .new)
        #expect(model.destination.courseLabel == "New course")
        #expect(server.calls == ["GET /api/semesters"], "no study place or course to read")
    }

    @Test func makeQuestionsOnAnEmptyLibrarySaysThereAreNoCourses() async {
        let server = StubServer(["GET /api/semesters": .ok(Self.emptyLibrary)])
        let (app, _) = TestApp.make(server, account: .student())
        let model = MakeModel(app: app, status: nil)
        await model.load()
        model.source = .paste
        model.text = "Invented notes on fluid balance."
        #expect(model.hasMaterial)
        #expect(model.problem == nil)
        #expect(model.destination.courseLabel == "No courses yet")
        #expect(!model.canGoOn)
    }

    @Test func settingsOnAnEmptyLibraryOffersSemesterOne() async {
        let server = StubServer(["GET /api/semesters": .ok(Self.emptyLibrary)])
        let (app, _) = TestApp.make(server, account: .student())
        let catalog = CatalogModel(app: app)
        await catalog.load()
        #expect(catalog.semesters == [])
        #expect(catalog.nextSemesterNumber == 1)
    }
}
