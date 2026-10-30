import QBankKit
import Testing
@testable import QBank

@MainActor
struct SignUpModelTests {
    private static let refused = "This email can't sign up here. If you already have an account, sign in. Otherwise, ask the owner to add your email."

    @Test func signUpStoresTheSessionAndOpensTheApp() async throws {
        let server = StubServer(["POST /api/sign-up": .ok(Bodies.signedIn())])
        let (app, store) = TestApp.make(server)
        let model = SignUpModel(app: app)
        model.email = "  student@example.com "
        model.password = "synthetic-pass-1"
        await model.signUp()
        #expect(app.route == .signedIn(.student()))
        #expect(try store.load()?.token == "synthetic-new-token")
        #expect(model.problem == nil)
        let request = try #require(server.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(String(decoding: try #require(request.httpBody), as: UTF8.self) == #"{"email":"student@example.com","password":"synthetic-pass-1"}"#)
    }

    @Test func refusedEmailIsSaidInTheServersWords() async {
        let server = StubServer(["POST /api/sign-up": .error(403, "sign_up_refused", Self.refused)])
        let (app, _) = TestApp.make(server)
        let model = SignUpModel(app: app)
        model.email = "stranger@example.com"
        model.password = "synthetic-pass-1"
        await model.signUp()
        #expect(app.route == .signedOut)
        #expect(model.problem == Self.refused)
        #expect(model.email == "stranger@example.com", "the email stays to fix a typo")
        #expect(model.password.isEmpty)
        #expect(model.madeButNotSignedIn == nil)
        #expect(model.isSigningUp == false)
    }

    @Test func lockedSignUpSaysHowLong() async {
        let server = StubServer(["POST /api/sign-up": .error(429, "too_many_attempts", "Too many tries. Try again in 15 minutes.")])
        let (app, _) = TestApp.make(server)
        let model = SignUpModel(app: app)
        model.email = "stranger@example.com"
        model.password = "synthetic-pass-1"
        await model.signUp()
        #expect(model.problem == "Too many tries. Try again in 15 minutes.")
    }

    @Test func madeButNotSignedInHandsOverToSignIn() async {
        let message = "Your account was made, but signing in failed. Sign in to continue."
        let server = StubServer(["POST /api/sign-up": .error(502, "auth_failed", message)])
        let (app, _) = TestApp.make(server)
        let model = SignUpModel(app: app)
        model.email = " student@example.com"
        model.password = "synthetic-pass-1"
        await model.signUp()
        #expect(app.route == .signedOut)
        #expect(model.madeButNotSignedIn == SignInHandoff(email: "student@example.com", problem: message))

        let signIn = SignInModel(app: app, handoff: model.madeButNotSignedIn)
        #expect(signIn.email == "student@example.com")
        #expect(signIn.problem == message)
        #expect(signIn.password.isEmpty)
    }

    @Test func noSignalIsSaidPlainly() async {
        let (app, _) = TestApp.make(StubServer(["POST /api/sign-up": .offline]))
        let model = SignUpModel(app: app)
        model.email = "student@example.com"
        model.password = "synthetic-pass-1"
        await model.signUp()
        #expect(model.problem == "No connection. Check Wi-Fi or cellular data and try again.")
    }

    @Test func needsBothFieldsBeforeSending() async {
        let server = StubServer()
        let (app, _) = TestApp.make(server)
        let model = SignUpModel(app: app)
        model.email = "  "
        model.password = "synthetic-pass-1"
        await model.signUp()
        #expect(model.problem == "Enter your email and a password.")
        #expect(server.requests.isEmpty)
    }

    @Test func tooShortIsCaughtBeforeSending() async {
        let server = StubServer()
        let (app, _) = TestApp.make(server)
        let model = SignUpModel(app: app)
        model.email = "student@example.com"
        model.password = "short"
        await model.signUp()
        #expect(model.problem == "Choose a password of at least 8 characters.")
        #expect(server.requests.isEmpty)
    }
}
