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
}
