import Foundation
import QBankKit
import Testing
import UIKit
@testable import QBank

@MainActor
struct LookStoreTests {
    @Test func startsOnMatchDevice() {
        #expect(LookStore(defaults: TestApp.freshDefaults()).look == .matchDevice)
    }

    @Test func choiceIsKeptOnThePhone() {
        let defaults = TestApp.freshDefaults()
        LookStore(defaults: defaults).look = .dark
        #expect(LookStore(defaults: defaults).look == .dark)
        #expect(defaults.string(forKey: LookStore.key) == "dark")
    }

    @Test func storesTheWebsWords() {
        #expect(Look.allCases.map(\.rawValue) == ["auto", "light", "dark"])
        #expect(Look.allCases.map(\.label) == ["Match device", "Light", "Dark"])
    }

    @Test func unknownStoredValueMatchesTheDevice() {
        let defaults = TestApp.freshDefaults()
        defaults.set("sepia", forKey: LookStore.key)
        #expect(LookStore(defaults: defaults).look == .matchDevice)
    }

    @Test func matchDeviceHandsTheChoiceToTheSystem() {
        #expect(Look.matchDevice.userInterfaceStyle == .unspecified)
        #expect(Look.light.userInterfaceStyle == .light)
        #expect(Look.dark.userInterfaceStyle == .dark)
    }

    @Test func signingOutKeepsTheLook() async {
        let (app, _) = TestApp.make(StubServer(["POST /api/sign-out": .ok(#"{"status":"ok"}"#)]), account: .student())
        app.look.look = .light
        await app.signOut()
        #expect(app.route == .signedOut)
        #expect(app.look.look == .light)
    }
}

@MainActor
struct ChangePasswordModelTests {
    private func model(_ server: StubServer) -> (ChangePasswordModel, AppModel) {
        let (app, _) = TestApp.make(server, account: .student())
        let model = ChangePasswordModel(app: app)
        model.currentPassword = "synthetic-pass-1"
        model.newPassword = "synthetic-pass-3"
        return (model, app)
    }

    @Test func changeKeepsHerSignedInWithTheFreshToken() async throws {
        let server = StubServer(["POST /api/account/password": .ok(Bodies.signedIn(token: "synthetic-fresh-token"))])
        let (model, app) = model(server)
        await model.save()
        #expect(model.isSaved)
        #expect(model.problem == nil)
        #expect(model.currentPassword.isEmpty && model.newPassword.isEmpty)
        #expect(app.route == .signedIn(.student()))
        #expect(try app.client.storedSession()?.token == "synthetic-fresh-token")
        let body = try #require(server.requests.last?.httpBody)
        #expect(String(decoding: body, as: UTF8.self) == #"{"currentPassword":"synthetic-pass-1","newPassword":"synthetic-pass-3"}"#)
    }

    @Test func typingAgainClearsTheSavedLine() async {
        let (model, _) = model(StubServer(["POST /api/account/password": .ok(Bodies.signedIn())]))
        await model.save()
        #expect(model.isSaved)
        model.newPassword = "s"
        #expect(model.isSaved == false)
    }

    @Test(arguments: [
        ("", "synthetic-pass-3", "Enter your current password and a new one."),
        ("synthetic-pass-1", "", "Enter your current password and a new one."),
        ("synthetic-pass-1", "short", "Choose a password of at least 8 characters."),
        ("synthetic-pass-1", String(repeating: "x", count: 129), "Choose a password of at most 128 characters."),
        ("synthetic-pass-1", "synthetic-pass-1", "Choose a new password that is different from your current one."),
    ])
    func rulesAreCheckedBeforeSending(current: String, new: String, problem: String) async {
        let server = StubServer()
        let (model, _) = model(server)
        model.currentPassword = current
        model.newPassword = new
        await model.save()
        #expect(model.problem == problem)
        #expect(server.requests.isEmpty)
    }

    @Test func wrongCurrentPasswordSaysSoAndKeepsHerSignedIn() async {
        let server = StubServer(["POST /api/account/password": .error(401, "invalid_credentials", "That password is not right.")])
        let (model, app) = model(server)
        await model.save()
        #expect(model.problem == "That password is not right.")
        #expect(model.currentPassword.isEmpty)
        #expect(model.newPassword == "synthetic-pass-3")
        #expect(app.route == .signedIn(.student()))
        #expect(model.isSaved == false)
    }

    /// The server's own sentence speaks of a temporary password; Settings says it her way.
    @Test func samePasswordFromTheServerIsWordedForSettings() async {
        let server = StubServer(["POST /api/account/password": .error(400, "same_password", "Choose a password that is different from the temporary one.")])
        let (model, _) = model(server)
        await model.save()
        #expect(model.problem == "Choose a new password that is different from your current one.")
    }

    @Test func endedSessionSignsHerOut() async {
        let server = StubServer(["POST /api/account/password": .error(401, "unauthenticated", "Sign in to continue.")])
        let (model, app) = model(server)
        await model.save()
        #expect(app.route == .signedOut)
        #expect(model.problem == nil)
    }

    @Test func sessionThatCouldNotBeRefreshedSaysSo() async {
        let server = StubServer(["POST /api/account/password": .error(502, "auth_failed", "The password was changed, but the session could not be refreshed.")])
        let (model, _) = model(server)
        await model.save()
        #expect(model.problem == "The password was changed, but the session could not be refreshed.")
    }

    @Test func noSignalIsSaidPlainly() async {
        let (model, app) = model(StubServer(["POST /api/account/password": .offline]))
        await model.save()
        #expect(model.problem == "No connection. Check Wi-Fi or cellular data and try again.")
        #expect(app.route == .signedIn(.student()))
        #expect(model.currentPassword == "synthetic-pass-1")
    }
}

@MainActor
struct CatalogModelTests {
    static let twoSemesters = Bodies.catalog([
        Bodies.semester(id: "s1", number: 1, courses: [
            Bodies.course(id: "c2", code: "NURS 402", order: 2),
            Bodies.course(id: "c1", code: "NURS 406", order: 1),
            Bodies.course(id: "c3", code: "NURS 300", order: 3, archived: true),
        ]),
        Bodies.semester(id: "s2", number: 2),
    ])

    @Test func loadsHerSemesters() async throws {
        let (app, _) = TestApp.make(StubServer(["GET /api/semesters": .ok(Self.twoSemesters)]), account: .student())
        let catalog = CatalogModel(app: app)
        await catalog.load()
        let semesters = try #require(catalog.semesters)
        #expect(semesters.map(\.name) == ["Semester 1", "Semester 2"])
        #expect(CatalogModel.summary(of: semesters[0]) == "NURS 406, NURS 402 · 1 archived")
        #expect(CatalogModel.summary(of: semesters[1]) == "No courses yet")
        #expect(CatalogModel.nextSemesterNumber(after: semesters) == 3)
    }

    @Test func aCourseSheetStartsFromTheListItWasOpenedWith() throws {
        let server = StubServer()
        let (app, _) = TestApp.make(server, account: .student())
        let catalog = CatalogModel(app: app, catalog: try Bodies.decodeCatalog(Self.twoSemesters))
        #expect(CourseEditModel(catalog: catalog, id: "c1").code == "NURS 406")
        #expect(SemesterModel(catalog: catalog, id: "s2").name == "Semester 2")
        #expect(server.requests.isEmpty, "nothing is read before she saves")
    }

    @Test func onlyStudentsEditTheCatalog() {
        #expect(CatalogModel(app: TestApp.make(StubServer(), account: .student()).0).isEditable)
        #expect(CatalogModel(app: TestApp.make(StubServer(), account: .admin).0).isEditable == false)
    }

    @Test func failedFirstLoadSaysWhyAndAFailedReloadKeepsTheList() async {
        let server = StubServer(["GET /api/semesters": .offline])
        let (app, _) = TestApp.make(server, account: .student())
        let catalog = CatalogModel(app: app)
        await catalog.load()
        #expect(catalog.semesters == nil)
        #expect(catalog.loadProblem == "No connection. Check Wi-Fi or cellular data and try again.")
        server["GET /api/semesters"] = .ok(Self.twoSemesters)
        await catalog.load()
        #expect(catalog.loadProblem == nil)
        server["GET /api/semesters"] = .offline
        await catalog.load()
        #expect(catalog.semesters?.count == 2)
        #expect(catalog.loadProblem == nil)
    }

    @Test func endedSessionSignsHerOut() async {
        let server = StubServer(["GET /api/semesters": .error(401, "unauthenticated", "Sign in to continue.")])
        let (app, _) = TestApp.make(server, account: .student())
        await CatalogModel(app: app).load()
        #expect(app.route == .signedOut)
    }
}

@MainActor
struct SemesterModelTests {
    private func loaded(_ server: StubServer) async -> CatalogModel {
        let (app, _) = TestApp.make(server, account: .student())
        let catalog = CatalogModel(app: app)
        await catalog.load()
        return catalog
    }

    @Test func startsFromWhatTheServerHas() async {
        let server = StubServer(["GET /api/semesters": .ok(Bodies.catalog([Bodies.semester(id: "s1", number: 1, name: "Fall", startsOn: "2026-09-01")]))])
        let model = SemesterModel(catalog: await loaded(server), id: "s1")
        #expect(model.name == "Fall")
        #expect(CalendarDay.text(from: model.startsOn) == "2026-09-01")
        #expect(model.endsOn == nil)
    }

    @Test func saveSendsTheNameAndDatesAndAClearedDateAsNull() async throws {
        let server = StubServer(["GET /api/semesters": .ok(Bodies.catalog([Bodies.semester(id: "s1", number: 1, endsOn: "2026-12-18")]))])
        let catalog = await loaded(server)
        let model = SemesterModel(catalog: catalog, id: "s1")
        model.name = "  Fall 2026 "
        model.startsOn = CalendarDay.date(from: "2026-09-01")
        model.endsOn = nil
        server["PATCH /api/semesters/s1"] = .ok(Bodies.semester(id: "s1", number: 1, name: "Fall 2026", startsOn: "2026-09-01"))
        server["GET /api/semesters"] = .ok(Bodies.catalog([Bodies.semester(id: "s1", number: 1, name: "Fall 2026", startsOn: "2026-09-01")]))
        await model.save()
        let patch = try #require(server.requests.first { $0.httpMethod == "PATCH" })
        let body = try #require(patch.httpBody)
        #expect(String(decoding: body, as: UTF8.self) == #"{"endsOn":null,"name":"  Fall 2026 ","startsOn":"2026-09-01"}"#)
        #expect(model.isSaved)
        #expect(model.name == "Fall 2026")
        #expect(catalog.semester(id: "s1")?.name == "Fall 2026")
        model.name = "Fall"
        #expect(model.isSaved == false)
    }

    @Test func blankNameIsCaughtBeforeSending() async {
        let server = StubServer(["GET /api/semesters": .ok(Bodies.catalog([Bodies.semester(id: "s1", number: 1)]))])
        let model = SemesterModel(catalog: await loaded(server), id: "s1")
        model.name = "   "
        await model.save()
        #expect(model.saveProblem == "Semester name is required.")
        #expect(server.calls == ["GET /api/semesters"])
    }

    @Test func addsACourseAndEmptiesTheFields() async throws {
        let server = StubServer(["GET /api/semesters": .ok(Bodies.catalog([Bodies.semester(id: "s1", number: 1)]))])
        let catalog = await loaded(server)
        let model = SemesterModel(catalog: catalog, id: "s1")
        model.newCode = "NURS 406"
        model.newTitle = "Mental Health"
        server["POST /api/courses"] = StubServer.Reply(status: 201, body: Bodies.course(id: "c9", code: "NURS 406"))
        server["GET /api/semesters"] = .ok(Bodies.catalog([Bodies.semester(id: "s1", number: 1, courses: [Bodies.course(id: "c9", code: "NURS 406")])]))
        let added = await model.addCourse()
        let body = try #require(server.requests.first { $0.httpMethod == "POST" }?.httpBody)
        #expect(String(decoding: body, as: UTF8.self) == #"{"code":"NURS 406","semesterId":"s1","title":"Mental Health"}"#)
        #expect(model.addProblem == nil)
        #expect(added?.id == "c9")
        #expect(model.newCode.isEmpty && model.newTitle.isEmpty)
        #expect(model.semester?.courses.map(\.code) == ["NURS 406"])
    }

    @Test(arguments: [("", "Mental Health", "Course code is required."), ("NURS 406", " ", "Course name is required.")])
    func courseNeedsACodeAndAName(code: String, title: String, problem: String) async {
        let server = StubServer(["GET /api/semesters": .ok(Bodies.catalog([Bodies.semester(id: "s1", number: 1)]))])
        let model = SemesterModel(catalog: await loaded(server), id: "s1")
        model.newCode = code
        model.newTitle = title
        #expect(await model.addCourse() == nil)
        #expect(model.addProblem == problem)
        #expect(server.calls == ["GET /api/semesters"])
    }

    @Test func takenCodeSaysWhyAndKeepsTheFields() async {
        let server = StubServer([
            "GET /api/semesters": .ok(Bodies.catalog([Bodies.semester(id: "s1", number: 1)])),
            "POST /api/courses": .error(409, "request_refused", "This semester already has a course with the code NURS 406."),
        ])
        let model = SemesterModel(catalog: await loaded(server), id: "s1")
        model.newCode = "NURS 406"
        model.newTitle = "Mental Health"
        #expect(await model.addCourse() == nil)
        #expect(model.addProblem == "This semester already has a course with the code NURS 406.")
        #expect(model.newCode == "NURS 406")
    }
}

@MainActor
struct CourseEditModelTests {
    private static let catalog = Bodies.catalog([
        Bodies.semester(id: "s1", number: 1, courses: [Bodies.course(id: "c1", code: "NURS 406")]),
        Bodies.semester(id: "s2", number: 2),
    ])
    private static let renamed = Bodies.catalog([
        Bodies.semester(id: "s1", number: 1, courses: [Bodies.course(id: "c1", code: "NURS 410")]),
        Bodies.semester(id: "s2", number: 2),
    ])

    private func model(_ server: StubServer) async -> CourseEditModel {
        let (app, _) = TestApp.make(server, account: .student())
        let catalog = CatalogModel(app: app)
        await catalog.load()
        return CourseEditModel(catalog: catalog, id: "c1")
    }

    @Test func renamesInItsOwnSemester() async throws {
        let server = StubServer(["GET /api/semesters": .ok(Self.catalog)])
        let model = await model(server)
        #expect(model.semesterID == "s1")
        #expect(!model.hasChanges)
        model.code = "NURS 410"
        #expect(model.hasChanges)
        server["PATCH /api/courses/c1"] = .ok(Bodies.course(id: "c1", code: "NURS 410"))
        server["GET /api/semesters"] = .ok(Self.renamed)
        await model.save()
        let body = try #require(server.requests.first { $0.httpMethod == "PATCH" }?.httpBody)
        #expect(String(decoding: body, as: UTF8.self) == #"{"code":"NURS 410","semesterId":"s1","title":"Invented NURS 406"}"#)
        #expect(model.note == "Saved.")
        #expect(model.problem == nil)
        #expect(model.catalog.semester(id: "s1")?.courses.map(\.code) == ["NURS 410"])
    }

    @Test func blankNameIsCaughtBeforeSending() async {
        let server = StubServer(["GET /api/semesters": .ok(Self.catalog)])
        let model = await model(server)
        model.title = ""
        await model.save()
        #expect(model.problem == "Course name is required.")
        #expect(server.calls == ["GET /api/semesters"])
    }

    @Test func refusalSaysWhy() async {
        let server = StubServer([
            "GET /api/semesters": .ok(Self.catalog),
            "PATCH /api/courses/c1": .error(409, "request_refused", "This semester already has a course with the code NURS 402."),
        ])
        let model = await model(server)
        model.code = "NURS 402"
        await model.save()
        #expect(model.problem == "This semester already has a course with the code NURS 402.")
        #expect(model.note == nil)
        #expect(model.code == "NURS 402")
    }

    @Test func editingClearsTheNote() async {
        let server = StubServer(["GET /api/semesters": .ok(Self.catalog), "PATCH /api/courses/c1": .ok(Bodies.course(id: "c1", code: "NURS 406"))])
        let model = await model(server)
        await model.save()
        #expect(model.note == "Saved.")
        model.title = "Psych"
        #expect(model.note == nil)
    }
}

struct CalendarDayTests {
    @Test(arguments: ["2026-09-01", "2027-02-28", "2028-02-29", "2026-12-31"])
    func roundTrips(day: String) throws {
        let date = try #require(CalendarDay.date(from: day))
        #expect(CalendarDay.text(from: date) == day)
    }

    @Test func roundTripsInAnyTimeZone() throws {
        for zone in ["Pacific/Kiritimati", "America/Los_Angeles", "UTC", "Pacific/Pago_Pago"] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try #require(TimeZone(identifier: zone))
            let date = try #require(CalendarDay.date(from: "2026-09-01", calendar: calendar))
            #expect(CalendarDay.text(from: date, calendar: calendar) == "2026-09-01", "\(zone)")
        }
    }

    @Test(arguments: [nil, "", "2026-13-01", "2026-02-30", "next week"])
    func notADay(text: String?) {
        #expect(CalendarDay.date(from: text) == nil)
    }
}
