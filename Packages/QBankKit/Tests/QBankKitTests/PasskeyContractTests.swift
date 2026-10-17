import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import QBankKit

/// Passkeys against recordings of the server's real routes, answered by a software passkey that
/// writes what iOS writes for an app with the web domain's passkeys: each call sends what the
/// recorded request sent, the challenge cookie included, and each response decodes.
@Suite("Contract: passkeys")
struct PasskeyContractTests {
    static let relyingParty = "qbank.dimitrygallego.com"

    // MARK: Signing in

    /// Without the challenge cookie the server refuses any answer, so the options fail before the
    /// passkey sheet asks her for anything.
    @Test func optionsWithoutTheChallengeCookieFail() async throws {
        let body = #"{"rpId":"qbank.dimitrygallego.com","challenge":"c3ludGhldGlj","userVerification":"preferred"}"#
        let (client, _) = TestClient.make(FixtureTransport(status: 200, body: body), token: nil)
        let error = await #expect(throws: QBankError.self) { try await client.passkeySignInOptions() }
        guard case .unexpectedResponse(200, _)? = error else {
            Issue.record("expected an unexpected response, got \(String(describing: error))")
            return
        }
    }

    @Test func signInOptionsKeepTheChallengeCookie() async throws {
        let fixture = try Fixture.load("passkey-sign-in-options")
        let transport = try FixtureTransport([fixture])
        let (client, _) = TestClient.make(transport, token: nil)
        let options = try await client.passkeySignInOptions()
        try expectRequest(transport.requests.first, matches: fixture)
        #expect(options.challenge == Base64URL.decode(try #require(fixture.response.body["challenge"]?.stringValue)))
        #expect(options.relyingPartyID == Self.relyingParty)
        #expect(options.allowedCredentialIDs.isEmpty, "sign-in offers any of the domain's passkeys")
        #expect(options.userVerification == "preferred")
        let setCookie = try #require(fixture.response.headers["Set-Cookie"])
        #expect(options.ticket == String(setCookie.prefix { $0 != ";" }))
    }

    @Test func signInSendsTheAnswerWithItsCookieAndStoresTheSession() async throws {
        let fixture = try Fixture.load("passkey-sign-in")
        let transport = try FixtureTransport([Fixture.load("passkey-sign-in-options"), fixture])
        let (client, store) = TestClient.make(transport, token: nil)
        let options = try await client.passkeySignInOptions()
        let signedIn = try await client.signIn(with: try assertion(in: fixture), answering: options)
        try expectRequest(transport.requests.last, matches: fixture)
        #expect(signedIn.token == "synthetic-passkey-session-token")
        #expect(signedIn.user.email == "student@example.com")
        let stored = try #require(try store.load())
        #expect(stored.token == "synthetic-passkey-session-token")
        #expect(stored.account == signedIn.user)
    }

    @Test func aPasskeyTheServerRefusesStoresNothing() async throws {
        let fixture = try Fixture.load("passkey-sign-in-rejected")
        let transport = try FixtureTransport([fixture])
        let (client, store) = TestClient.make(transport, token: nil)
        let options = PasskeySignInOptions(
            challenge: Data(), relyingPartyID: Self.relyingParty, allowedCredentialIDs: [], userVerification: nil,
            ticket: try #require(fixture.request.cookie)
        )
        let error = await #expect(throws: QBankError.self) {
            try await client.signIn(with: try assertion(in: fixture), answering: options)
        }
        try expectRequest(transport.requests.first, matches: fixture)
        #expect(error?.serverCode == .invalidPasskey)
        #expect(error?.needsSignIn == false)
        guard case .server(let server)? = error else {
            Issue.record("Expected a server error, got \(String(describing: error))")
            return
        }
        #expect(server.message == "That passkey was not accepted.")
        #expect(try store.load() == nil)
    }

    // MARK: Saving one

    @Test func registrationOptionsNameTheAccount() async throws {
        let fixture = try Fixture.load("passkey-register-options")
        let transport = try FixtureTransport([fixture])
        let (client, _) = TestClient.make(transport)
        let options = try await client.passkeyRegistrationOptions()
        try expectRequest(transport.requests.first, matches: fixture)
        let body = fixture.response.body
        #expect(options.challenge == Base64URL.decode(try #require(body["challenge"]?.stringValue)))
        #expect(options.relyingPartyID == Self.relyingParty)
        #expect(options.userID == Base64URL.decode(try #require(body["user"]?["id"]?.stringValue)))
        #expect(options.userName == "student@example.com")
        #expect(options.excludedCredentialIDs.isEmpty)
        #expect(options.userVerification == "preferred")
        #expect(options.ticket.hasPrefix("__Secure-better-auth.better-auth-passkey="))
    }

    @Test func registrationOptionsNameThePasskeysSheHas() async throws {
        let transport = try FixtureTransport("passkey-register-options-saved")
        let (client, _) = TestClient.make(transport)
        let options = try await client.passkeyRegistrationOptions()
        #expect(options.excludedCredentialIDs == [Data("synthetic-passkey-1".utf8)])
    }

    @Test func savingSendsTheNewPasskeyWithItsCookieAndName() async throws {
        let fixture = try Fixture.load("passkey-register")
        let transport = try FixtureTransport([Fixture.load("passkey-register-options"), fixture])
        let (client, _) = TestClient.make(transport)
        let options = try await client.passkeyRegistrationOptions()
        let passkey = try await client.savePasskey(try registration(in: fixture), answering: options, name: "iPhone")
        try expectRequest(transport.requests.last, matches: fixture)
        #expect(passkey.name == "iPhone")
        #expect(passkey.deviceType == "multiDevice")
        #expect(passkey.createdAt != nil)
    }

    // MARK: Settings' list

    @Test func noPasskeys() async throws {
        let transport = try FixtureTransport("passkeys")
        let (client, _) = TestClient.make(transport)
        #expect(try await client.passkeys().isEmpty)
        try expectRequest(transport.requests.first, matches: Fixture.load("passkeys"))
    }

    @Test func savedPasskeys() async throws {
        let fixture = try Fixture.load("passkeys-saved")
        let transport = try FixtureTransport([fixture])
        let (client, _) = TestClient.make(transport)
        let passkeys = try await client.passkeys()
        try expectRequest(transport.requests.first, matches: fixture)
        #expect(passkeys.map(\.name) == ["iPhone", "iPad"])
        #expect(passkeys.allSatisfy { $0.createdAt != nil })
    }

    @Test func remove() async throws {
        let fixture = try Fixture.load("passkey-remove")
        let transport = try FixtureTransport([fixture])
        let (client, _) = TestClient.make(transport)
        let id = String(fixture.request.path.dropFirst("/api/passkeys/".count))
        try await client.removePasskey(id: id)
        try expectRequest(transport.requests.first, matches: fixture)
    }

    // MARK: The recorded answers, as the device gave them

    private func assertion(in fixture: Fixture) throws -> PasskeyAssertion {
        let credential = try #require(fixture.request.body?["response"])
        let response = try #require(credential["response"])
        return PasskeyAssertion(
            credentialID: try bytes(credential["rawId"]),
            clientDataJSON: try bytes(response["clientDataJSON"]),
            authenticatorData: try bytes(response["authenticatorData"]),
            signature: try bytes(response["signature"]),
            userID: try response["userHandle"].map { try bytes($0) }
        )
    }

    private func registration(in fixture: Fixture) throws -> PasskeyRegistration {
        let credential = try #require(fixture.request.body?["response"])
        let response = try #require(credential["response"])
        return PasskeyRegistration(
            credentialID: try bytes(credential["rawId"]),
            clientDataJSON: try bytes(response["clientDataJSON"]),
            attestationObject: try bytes(response["attestationObject"])
        )
    }

    private func bytes(_ value: JSONValue?) throws -> Data {
        try #require(value?.stringValue.flatMap(Base64URL.decode))
    }
}

@Suite("Passkey plumbing")
struct PasskeyPlumbingTests {
    @Test func base64URLRoundTrips() {
        let bytes = Data([0xfb, 0xff, 0xbf, 0x00, 0x01])
        #expect(Base64URL.encode(bytes) == "-_-_AAE")
        #expect(Base64URL.decode("-_-_AAE") == bytes)
        #expect(Base64URL.decode("-_-_AAE=") == bytes, "padding is accepted")
        #expect(Base64URL.decode("not base64!") == nil)
    }

    @Test func theTicketIsEachCookiesNameAndValue() {
        #expect(ticket("a=1; Max-Age=300; Path=/; HttpOnly; Secure; SameSite=Lax") == "a=1")
        // Several Set-Cookie headers arrive joined by commas; an Expires date has one of its own.
        #expect(ticket("a=1; Expires=Wed, 21 Oct 2026 07:28:00 GMT; Path=/, __Secure-b=x%3D; Secure") == "a=1; __Secure-b=x%3D")
        // A cookie being deleted is not sent back.
        #expect(ticket("gone=; Max-Age=0, a=1") == "a=1")
        // A value may end in "=", as unescaped base64 padding does.
        #expect(ticket("a=YWI=; Path=/, b=YQ==; Secure") == "a=YWI=; b=YQ==")
        #expect(ticket("gone=; Max-Age=0") == nil)
        #expect(ticket(nil) == nil)
    }

    private func ticket(_ setCookie: String?) -> String? {
        let headers = setCookie.map { ["set-cookie": $0] } ?? [:]
        let response = HTTPURLResponse(url: TestClient.baseURL, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        return QBankClient.ticket(from: response)
    }
}
