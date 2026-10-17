import Foundation
import QBankKit
import Testing
@testable import QBank

/// A device whose passkey sheet fails, as one without the web domain's association does.
private struct FailingPasskeys: PasskeyAuthenticator {
    func signIn(_ options: PasskeySignInOptions) async throws(PasskeyFailure) -> PasskeyAssertion {
        throw .failed
    }

    func save(_ options: PasskeyRegistrationOptions) async throws(PasskeyFailure) -> PasskeyRegistration {
        throw .failed
    }
}

private func json(_ request: URLRequest?) throws -> [String: Any] {
    let body = try #require(request?.httpBody)
    return try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
}

@MainActor
struct PasskeySignInTests {
    private static let cookie = "__Secure-better-auth.better-auth-passkey=synthetic-ticket.c2lnbmVk%3D"

    private func server(answer: StubServer.Reply = .ok(Bodies.signedIn(token: "synthetic-passkey-token"))) -> StubServer {
        StubServer([
            "GET /api/sign-in/passkey/options": .ok(Bodies.passkeySignInOptions(), headers: Bodies.passkeyCookie),
            "POST /api/sign-in/passkey": answer,
        ])
    }

    @Test func signsInWithThePasskeyOnTheDevice() async throws {
        let server = server()
        let (app, store) = TestApp.make(server, passkeys: DebugPasskeyAuthenticator(.synced))
        let model = SignInModel(app: app)
        await model.signInWithPasskey()
        #expect(app.route == .signedIn(.student()))
        #expect(try store.load()?.token == "synthetic-passkey-token")
        #expect(model.problem == nil)
        #expect(model.isBusy == false)
        #expect(server.calls == ["GET /api/sign-in/passkey/options", "POST /api/sign-in/passkey"])
        let answer = try #require(server.requests.last)
        #expect(answer.value(forHTTPHeaderField: "Cookie") == Self.cookie, "the challenge cookie goes back with the answer")
        #expect(answer.value(forHTTPHeaderField: "Authorization") == nil)
        let credential = try #require(try json(answer)["response"] as? [String: Any])
        #expect(credential["id"] as? String == Base64URL.encode(FakePasskeys.syncedCredentialID))
        #expect(app.passkeyOffer.isOpen == false, "a passkey sign-in offers no passkey")
    }

    @Test func closingThePasskeySheetSaysNothing() async {
        let server = server()
        let (app, _) = TestApp.make(server, passkeys: DebugPasskeyAuthenticator(.cancels))
        let model = SignInModel(app: app)
        await model.signInWithPasskey()
        #expect(app.route == .signedOut)
        #expect(model.problem == nil)
        #expect(server.calls == ["GET /api/sign-in/passkey/options"])
    }

    @Test func aPasskeyTheServerRefusesIsSaidAsTheWebSaysIt() async throws {
        let (app, store) = TestApp.make(
            server(answer: .error(401, "invalid_passkey", "That passkey was not accepted.")), passkeys: DebugPasskeyAuthenticator(.synced)
        )
        let model = SignInModel(app: app)
        await model.signInWithPasskey()
        #expect(app.route == .signedOut)
        #expect(model.problem == "That passkey was not accepted.")
        #expect(try store.load() == nil)
    }

    @Test func aDeviceThatCannotUsePasskeysSaysSo() async {
        let (app, _) = TestApp.make(server(), passkeys: FailingPasskeys())
        let model = SignInModel(app: app)
        await model.signInWithPasskey()
        #expect(model.problem == "That passkey was not accepted.")
    }

    @Test func noSignalIsSaidPlainly() async {
        let (app, _) = TestApp.make(StubServer(["GET /api/sign-in/passkey/options": .offline]), passkeys: DebugPasskeyAuthenticator(.synced))
        let model = SignInModel(app: app)
        await model.signInWithPasskey()
        #expect(model.problem == "No connection. Check Wi-Fi or cellular data and try again.")
    }

    @Test func aTemporaryPasswordIsReplacedFirst() async {
        let (app, _) = TestApp.make(server(answer: .ok(Bodies.signedIn(mustChangePassword: true))), passkeys: DebugPasskeyAuthenticator(.synced))
        await SignInModel(app: app).signInWithPasskey()
        #expect(app.route == .choosingPassword(.student(mustChangePassword: true)))
        #expect(app.temporaryPassword == nil, "she typed no password to offer back")
    }
}

@MainActor
struct PasskeyOfferTests {
    private func signInWithPassword(_ app: AppModel, password: String = "synthetic-pass-1") async {
        let model = SignInModel(app: app)
        model.email = "student@example.com"
        model.password = password
        await model.signIn()
    }

    private func server() -> StubServer {
        StubServer([
            "POST /api/sign-in/password": .ok(Bodies.signedIn()),
            "POST /api/sign-out": .ok(#"{"status":"signed_out"}"#),
            "GET /api/passkeys/options": .ok(Bodies.passkeyRegistrationOptions(), headers: Bodies.passkeyCookie),
            "POST /api/passkeys": .ok(Bodies.passkey(id: "p2", name: Device.model)),
        ])
    }

    @Test func aPasswordSignInOffersAPasskeyUntilSheAnswers() async {
        let defaults = TestApp.freshDefaults()
        let (app, _) = TestApp.make(server(), defaults: defaults)
        await signInWithPassword(app)
        #expect(app.passkeyOffer.isOpen)

        app.passkeyOffer.decline()
        #expect(app.passkeyOffer.isOpen == false)
        #expect(defaults.string(forKey: PasskeyOffer.key(for: "a1")) == "dismissed")

        await app.signOut()
        await signInWithPassword(app)
        #expect(app.passkeyOffer.isOpen == false, "Not now is kept on the device")
    }

    @Test func savingNamesThePasskeyForTheDeviceAndCloses() async throws {
        let server = server()
        let defaults = TestApp.freshDefaults()
        let (app, _) = TestApp.make(server, defaults: defaults)
        await signInWithPassword(app)
        await app.passkeyOffer.save(with: app)
        #expect(app.passkeyOffer.isOpen == false)
        #expect(defaults.string(forKey: PasskeyOffer.key(for: "a1")) == "saved")
        #expect(server.calls == ["POST /api/sign-in/password", "GET /api/passkeys/options", "POST /api/passkeys"])
        let saved = try #require(server.requests.last)
        #expect(saved.value(forHTTPHeaderField: "Cookie") == "__Secure-better-auth.better-auth-passkey=synthetic-ticket.c2lnbmVk%3D")
        #expect(saved.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-new-token")
        let body = try json(saved)
        #expect(body["name"] as? String == Device.model)
        let response = try #require((body["response"] as? [String: Any])?["response"] as? [String: Any])
        #expect(response["attestationObject"] as? String == Base64URL.encode(Data("synthetic-attestation".utf8)))
        #expect(response["transports"] as? [String] == ["hybrid", "internal"])
    }

    @Test func closingThePasskeySheetKeepsTheOfferOpen() async {
        let (app, _) = TestApp.make(server(), passkeys: DebugPasskeyAuthenticator(.cancels))
        await signInWithPassword(app)
        await app.passkeyOffer.save(with: app)
        #expect(app.passkeyOffer.isOpen)
        #expect(app.passkeyOffer.problem == nil)
    }

    @Test func aDeviceThatAlreadyHasOneClosesTheOffer() async {
        let server = server()
        server["GET /api/passkeys/options"] = .ok(Bodies.passkeyRegistrationOptions(excluding: ["synthetic-passkey-mac"]), headers: Bodies.passkeyCookie)
        let defaults = TestApp.freshDefaults()
        let (app, _) = TestApp.make(server, passkeys: DebugPasskeyAuthenticator(.synced), defaults: defaults)
        await signInWithPassword(app)
        await app.passkeyOffer.save(with: app)
        #expect(app.passkeyOffer.isOpen == false)
        #expect(defaults.string(forKey: PasskeyOffer.key(for: "a1")) == "saved")
        #expect(!server.calls.contains("POST /api/passkeys"))
    }

    @Test func aRefusedPasskeyIsSaidInTheOffer() async {
        let server = server()
        server["POST /api/passkeys"] = .error(400, "invalid_passkey", "That passkey was not accepted.")
        let (app, _) = TestApp.make(server)
        await signInWithPassword(app)
        await app.passkeyOffer.save(with: app)
        #expect(app.passkeyOffer.isOpen)
        #expect(app.passkeyOffer.problem == "That passkey was not accepted.")
        #expect(app.passkeyOffer.isSaving == false)
    }

    @Test func aDeviceWithoutAPasscodeIsNotOffered() async {
        let defaults = TestApp.freshDefaults()
        let lock = AppLock(defaults: defaults, owner: DebugDeviceOwner(.noPasscode))
        let (app, _) = TestApp.make(server(), lock: lock, defaults: defaults)
        await signInWithPassword(app)
        #expect(app.route == .signedIn(.student()))
        #expect(app.passkeyOffer.isOpen == false)
    }

    @Test func aTemporaryPasswordIsOfferedOnceItIsReplaced() async {
        let server = server()
        server["POST /api/sign-in/password"] = .ok(Bodies.signedIn(mustChangePassword: true))
        server["POST /api/account/password"] = .ok(Bodies.signedIn(token: "synthetic-fresh-token"))
        let (app, _) = TestApp.make(server)
        await signInWithPassword(app, password: "synthetic-temp-1")
        #expect(app.passkeyOffer.isOpen == false, "not before she has her own password")
        let choose = ChoosePasswordModel(app: app)
        choose.newPassword = "a-new-password"
        await choose.save()
        #expect(app.route == .signedIn(.student()))
        #expect(app.passkeyOffer.isOpen)
    }

    @Test func changingThePasswordInSettingsOffersNothing() async {
        let server = server()
        server["POST /api/account/password"] = .ok(Bodies.signedIn(token: "synthetic-fresh-token"))
        let (app, _) = TestApp.make(server, account: .student())
        let model = ChangePasswordModel(app: app)
        model.currentPassword = "synthetic-pass-1"
        model.newPassword = "a-new-password"
        await model.save()
        #expect(model.isSaved)
        #expect(app.passkeyOffer.isOpen == false)
    }

    @Test func signingOutClosesTheOfferWithoutAnAnswer() async {
        let defaults = TestApp.freshDefaults()
        let (app, _) = TestApp.make(server(), defaults: defaults)
        await signInWithPassword(app)
        await app.signOut()
        #expect(app.passkeyOffer.isOpen == false)
        #expect(defaults.string(forKey: PasskeyOffer.key(for: "a1")) == nil)
        await signInWithPassword(app)
        #expect(app.passkeyOffer.isOpen, "asked again at the next password sign-in")
    }
}

@MainActor
struct PasskeysModelTests {
    @Test func listsHerPasskeysAndCountsThem() async {
        let server = StubServer(["GET /api/passkeys": .ok(Bodies.passkeys([Bodies.passkey(id: "p1", name: "MacBook Air"), Bodies.passkey(id: "p2", name: nil)]))])
        let (app, _) = TestApp.make(server, account: .student())
        let model = PasskeysModel(app: app)
        #expect(model.count == nil)
        await model.load()
        #expect(model.passkeys?.map(\.name) == ["MacBook Air", nil])
        #expect(model.count == "2")
        server["GET /api/passkeys"] = .ok(Bodies.passkeys([]))
        await model.load()
        #expect(model.count == "None")
    }

    @Test func savingAddsThePasskeyForThisDevice() async throws {
        let server = StubServer([
            "GET /api/passkeys": .ok(Bodies.passkeys([Bodies.passkey(id: "p1", name: "MacBook Air")])),
            "GET /api/passkeys/options": .ok(Bodies.passkeyRegistrationOptions(), headers: Bodies.passkeyCookie),
            "POST /api/passkeys": .ok(Bodies.passkey(id: "p2", name: Device.model)),
        ])
        let (app, _) = TestApp.make(server, account: .student())
        let model = PasskeysModel(app: app)
        await model.load()
        await model.save()
        #expect(model.passkeys?.map(\.name) == ["MacBook Air", Device.model])
        #expect(model.isSaved)
        #expect(model.problem == nil)
        #expect(try json(server.requests.last)["name"] as? String == Device.model)
    }

    @Test func aDeviceThatAlreadyHasOneSaysSo() async {
        let server = StubServer([
            "GET /api/passkeys/options": .ok(Bodies.passkeyRegistrationOptions(excluding: ["synthetic-passkey-mac"]), headers: Bodies.passkeyCookie),
        ])
        let (app, _) = TestApp.make(server, account: .student(), passkeys: DebugPasskeyAuthenticator(.synced))
        let model = PasskeysModel(app: app)
        await model.save()
        #expect(model.problem == "This \(Device.model) already has a passkey for your account.")
        #expect(model.isSaved == false)
    }

    @Test func closingThePasskeySheetSaysNothing() async {
        let server = StubServer(["GET /api/passkeys/options": .ok(Bodies.passkeyRegistrationOptions(), headers: Bodies.passkeyCookie)])
        let (app, _) = TestApp.make(server, account: .student(), passkeys: DebugPasskeyAuthenticator(.cancels))
        let model = PasskeysModel(app: app)
        await model.save()
        #expect(model.problem == nil)
        #expect(model.isSaved == false)
    }

    @Test func removingDropsTheRow() async throws {
        let server = StubServer([
            "GET /api/passkeys": .ok(Bodies.passkeys([Bodies.passkey(id: "p1", name: "MacBook Air"), Bodies.passkey(id: "p2")])),
            "DELETE /api/passkeys/p1": .ok(#"{"status":"removed"}"#),
        ])
        let (app, _) = TestApp.make(server, account: .student())
        let model = PasskeysModel(app: app)
        await model.load()
        await model.remove(try #require(model.passkeys?.first))
        #expect(model.passkeys?.map(\.id) == ["p2"])
        #expect(model.removingID == nil)
    }

    @Test func aRemovalTheServerRefusesKeepsTheRowAndSaysWhy() async throws {
        let server = StubServer([
            "GET /api/passkeys": .ok(Bodies.passkeys([Bodies.passkey(id: "p1")])),
            "DELETE /api/passkeys/p1": .error(400, "invalid_passkey", "That passkey could not be removed."),
        ])
        let (app, _) = TestApp.make(server, account: .student())
        let model = PasskeysModel(app: app)
        await model.load()
        await model.remove(try #require(model.passkeys?.first))
        #expect(model.passkeys?.map(\.id) == ["p1"])
        #expect(model.problem == "That passkey could not be removed.")
    }

    @Test func aFirstLoadWithoutSignalSaysSo() async {
        let (app, _) = TestApp.make(StubServer(["GET /api/passkeys": .offline]), account: .student())
        let model = PasskeysModel(app: app)
        await model.load()
        #expect(model.passkeys == nil)
        #expect(model.loadProblem == "No connection. Check Wi-Fi or cellular data and try again.")
    }

    @Test func anEndedSessionSignsOut() async {
        let (app, _) = TestApp.make(StubServer(["GET /api/passkeys": .error(401, "unauthenticated", "Sign in to continue.")]), account: .student())
        let model = PasskeysModel(app: app)
        await model.load()
        #expect(app.route == .signedOut)
        #expect(model.loadProblem == nil)
    }
}
