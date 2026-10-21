import Foundation
import QBankKit
import Testing
@testable import QBank

@MainActor
struct AppModelTests {
    @Test func noStoredSessionStartsSignedOut() {
        let (app, _) = TestApp.make(StubServer())
        #expect(app.route == .signedOut)
        #expect(app.account == nil)
    }

    @Test func storedSessionStartsSignedInWithoutAskingTheServer() {
        let server = StubServer()
        let (app, _) = TestApp.make(server, account: .student())
        #expect(app.route == .signedIn(.student()))
        #expect(server.requests.isEmpty)
    }

    @Test func storedTemporaryPasswordStartsOnChoosePassword() {
        let (app, _) = TestApp.make(StubServer(), account: .student(mustChangePassword: true))
        #expect(app.route == .choosingPassword(.student(mustChangePassword: true)))
    }

    @Test func endedSessionSignsOutAndSaysWhy() async throws {
        let server = StubServer(["GET /api/session": .error(401, "unauthenticated", "Sign in to continue.")])
        let (app, store) = TestApp.make(server, account: .student())
        await app.refreshSession()
        #expect(app.route == .signedOut)
        #expect(app.signedOutReason == "Your session ended. Sign in again.")
        #expect(try store.load() == nil)
    }

    @Test func noSignalKeepsHerSignedIn() async throws {
        let server = StubServer(["GET /api/session": .offline])
        let (app, store) = TestApp.make(server, account: .student())
        await app.refreshSession()
        #expect(app.route == .signedIn(.student()))
        #expect(try store.load() != nil)
    }

    @Test func sessionCheckPicksUpAPasswordReset() async {
        let server = StubServer(["GET /api/session": .ok(Bodies.session(mustChangePassword: true))])
        let (app, _) = TestApp.make(server, account: .student())
        await app.refreshSession()
        #expect(app.route == .choosingPassword(.student(mustChangePassword: true)))
    }

    @Test func signOutForgetsTheSessionEvenWithoutSignal() async throws {
        let server = StubServer(["POST /api/sign-out": .offline])
        let (app, store) = TestApp.make(server, account: .student())
        app.hasLanded = true
        await app.signOut()
        #expect(app.route == .signedOut)
        #expect(app.signedOutReason == nil)
        #expect(app.hasLanded == false)
        #expect(try store.load() == nil)
        #expect(server.calls == ["POST /api/sign-out"])
    }

    @Test func mustChangePasswordFromAnyCallOpensChoosePassword() {
        let (app, _) = TestApp.make(StubServer(), account: .student())
        let handled = app.handle(.server(ServerError(status: 403, code: .mustChangePassword, message: "Choose a new password to continue.")))
        #expect(handled)
        #expect(app.route == .choosingPassword(.student()))
    }

    @Test func otherFailuresAreLeftToTheScreen() {
        let (app, _) = TestApp.make(StubServer(), account: .student())
        #expect(app.handle(.transport(.notConnectedToInternet)) == false)
        #expect(app.handle(.server(ServerError(status: 404, code: .requestRefused, message: "Gone"))) == false)
        #expect(app.route == .signedIn(.student()))
    }

    static func waitingAnswer(_ app: AppModel) async throws {
        let submission = AttemptSubmission(clientAttemptID: "w1", questionID: "q1", response: .single(choice: 0))
        _ = try await app.submit(submission, courseID: "c1")
    }

    @Test func signedInSheGetsTheStoreForHerAccount() {
        let (app, _) = TestApp.make(StubServer(), account: .student())
        #expect(app.offline?.accountID == "a1")
        let (signedOut, _) = TestApp.make(StubServer())
        #expect(signedOut.offline == nil)
    }

    @Test func signOutDeletesWhatThePhoneKeptForHer() async throws {
        let storage = PhoneStorage.memory()
        let server = StubServer(["GET /api/semesters": .ok(Bodies.semesters()), "POST /api/sign-out": .ok(#"{"status":"ok"}"#)])
        let (app, _) = TestApp.make(server, account: .student(), storage: storage, connection: Connection(isOnline: false))
        try await Self.waitingAnswer(app)
        _ = try await app.offline?.load(.catalog) { () async throws(QBankError) in try await app.client.catalog() }
        await app.signOut()
        #expect(app.offline == nil)

        let (again, _) = TestApp.make(server, account: .student(), storage: storage)
        #expect(again.offline?.waiting.isEmpty == true)
        #expect(await again.offline?.saved(.catalog) == nil)
    }

    @Test func signOutLeavesNoFilesOfHersOnThePhone() async throws {
        let folder = OfflineStoreTests.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let server = StubServer(["GET /api/semesters": .ok(Bodies.semesters()), "POST /api/sign-out": .ok(#"{"status":"ok"}"#)])
        let connection = Connection()
        let (app, _) = TestApp.make(server, account: .student(), storage: .files(root: folder), connection: connection)
        await HomeModel(app: app).load()
        connection.update(isOnline: false)
        try await Self.waitingAnswer(app)
        let account = folder.appendingPathComponent("Accounts/a1")
        #expect(FileManager.default.fileExists(atPath: account.appendingPathComponent("pending-attempts.json").path()))
        #expect(FileManager.default.fileExists(atPath: account.appendingPathComponent("Content").path()))

        await app.signOut()
        #expect(!FileManager.default.fileExists(atPath: account.path()))
    }

    @Test func anEndedSessionKeepsTheAnswersForHerNextSignIn() async throws {
        let storage = PhoneStorage.memory()
        let (app, _) = TestApp.make(StubServer(), account: .student(), storage: storage, connection: Connection(isOnline: false))
        try await Self.waitingAnswer(app)
        app.handle(.server(ServerError(status: 401, code: .unauthenticated, message: "Sign in to continue.")))
        #expect(app.offline == nil)

        let (again, _) = TestApp.make(StubServer(), account: .student(), storage: storage)
        #expect(again.offline?.waiting.map(\.id) == ["w1"])
    }

    @Test func eachAccountKeepsItsOwnAnswers() async throws {
        let storage = PhoneStorage.memory()
        let (app, _) = TestApp.make(StubServer(), account: .student(), storage: storage, connection: Connection(isOnline: false))
        try await Self.waitingAnswer(app)
        let other = Account(id: "a3", email: "other@example.com", name: "Other Student", role: .student, mustChangePassword: false)
        let (otherApp, _) = TestApp.make(StubServer(), account: other, storage: storage)
        #expect(otherApp.offline?.waiting.isEmpty == true)
    }

    @Test func theConnectionComingBackSendsTheWaitingAnswers() async throws {
        let server = StubServer()
        let connection = Connection(isOnline: false)
        let (app, _) = TestApp.make(server, account: .student(), connection: connection)
        try await Self.waitingAnswer(app)
        server["POST /api/attempts"] = StubServer.Reply(status: 201, body: PracticeModelTests.saved(id: "w1", question: "q1", status: "correct", points: 1, max: 1))
        connection.update(isOnline: true)
        try await waitUntil { app.offline?.waiting.isEmpty == true }
        #expect(server.sentAttemptIDs == ["w1"])
    }

    @Test func answersLeftWaitingGoAtLaunch() async throws {
        let storage = PhoneStorage.memory()
        let server = StubServer()
        let (app, _) = TestApp.make(server, account: .student(), storage: storage, connection: Connection(isOnline: false))
        try await Self.waitingAnswer(app)
        server["POST /api/attempts"] = StubServer.Reply(status: 201, body: PracticeModelTests.saved(id: "w1", question: "q1", status: "correct", points: 1, max: 1))
        let (relaunched, _) = TestApp.make(server, account: .student(), storage: storage)
        try await waitUntil { relaunched.offline?.waiting.isEmpty == true }
        #expect(server.sentAttemptIDs == ["w1"])
    }
}
