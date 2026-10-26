import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import QBankKit

/// Deleting her own user account from Settings, against recordings of the server's real
/// `DELETE /api/me`: the call sends only her password, a delete forgets the session here, and
/// every refusal keeps her signed in with the server's sentence to show.
@Suite("Contract: deleting the account")
struct AccountDeletionContractTests {
    @Test func aDeleteSendsOnlyHerPasswordAndForgetsTheSession() async throws {
        let fixture = try Fixture.load("account-delete")
        let transport = try FixtureTransport([fixture])
        let (client, store) = TestClient.make(transport)
        try await client.deleteAccount(password: "synthetic-pass-2")
        try expectRequest(transport.requests.first, matches: fixture)
        #expect(fixture.request.body == .object(["password": .string("synthetic-pass-2")]), "nothing in the request names an account")
        #expect(try store.load() == nil)
    }

    /// The account's sessions ended with it: her other device's, and this one's if it tries again.
    @Test(arguments: ["session-after-account-delete", "account-delete-signed-out"])
    func afterADeleteEverySessionNeedsSignIn(name: String) async throws {
        let fixture = try Fixture.load(name)
        let transport = try FixtureTransport([fixture])
        let token = try #require(fixture.request.authorization?.replacingOccurrences(of: "Bearer ", with: ""))
        let (client, _) = TestClient.make(transport, token: token)
        let error = await #expect(throws: QBankError.self) {
            if fixture.request.method == "GET" {
                _ = try await client.session()
            } else {
                try await client.deleteAccount(password: "synthetic-pass-2")
            }
        }
        try expectRequest(transport.requests.first, matches: fixture)
        #expect(error?.needsSignIn == true)
    }

    @Test(arguments: [
        ("account-delete-wrong-password", ServerError.Code.invalidCredentials),
        ("account-delete-temporary-password", ServerError.Code.mustChangePassword),
        ("account-delete-admin", ServerError.Code.adminCannotDeleteAccount),
        ("account-delete-in-use", ServerError.Code.inUse),
        ("account-delete-unavailable", ServerError.Code.authUnavailable),
    ])
    func aRefusalDeletesNothingAndKeepsHerSignedIn(name: String, code: ServerError.Code) async throws {
        let fixture = try Fixture.load(name)
        let transport = try FixtureTransport([fixture])
        let (client, store) = TestClient.make(transport)
        let password = try #require(fixture.request.body?["password"]?.stringValue)
        let error = await #expect(throws: QBankError.self) {
            try await client.deleteAccount(password: password)
        }
        try expectRequest(transport.requests.first, matches: fixture)
        try MakeQuestionsContractTests.expect(error, is: fixture, code: code)
        #expect(error?.needsSignIn == false)
        #expect(try store.load()?.token == "synthetic-session-token")
    }

    @Test func aRunningJobIsNamedInTheRefusal() throws {
        let fixture = try Fixture.load("account-delete-in-use")
        #expect(fixture.response.body["message"]?.stringValue == "QBank is still making a set in NURS 101. Wait until it is filed, or cancel it, then delete your account.")
    }

    /// The fifth wrong password locks deleting and sign-in alike, and says for how long.
    @Test func theFifthWrongPasswordLocksForAWhile() async throws {
        let fixture = try Fixture.load("account-delete-locked")
        let transport = try FixtureTransport([fixture])
        let (client, store) = TestClient.make(transport)
        let error = await #expect(throws: QBankError.self) {
            try await client.deleteAccount(password: "not-it")
        }
        try expectRequest(transport.requests.first, matches: fixture)
        try MakeQuestionsContractTests.expect(error, is: fixture, code: .tooManyAttempts)
        guard case .server(let server)? = error else { return }
        #expect(server.retryAfterSeconds == 900)
        #expect(fixture.response.headers["retry-after"] == "900")
        #expect(error?.isTemporary == true)
        #expect(try store.load()?.token == "synthetic-session-token")
    }

    /// An agent key can never delete the account it belongs to, whatever its scopes.
    @Test func anAgentKeyIsRefused() async throws {
        let fixture = try Fixture.load("account-delete-agent-key")
        let transport = try FixtureTransport([fixture])
        let (client, store) = TestClient.make(transport, token: "synthetic-agent-key")
        let error = await #expect(throws: QBankError.self) {
            try await client.deleteAccount(password: "synthetic-pass-2")
        }
        try expectRequest(transport.requests.first, matches: fixture)
        try MakeQuestionsContractTests.expect(error, is: fixture, code: .agentKeyNotAllowed)
        #expect(try store.load()?.token == "synthetic-agent-key")
    }

    /// The app always sends a password; without one the server refuses and deletes nothing.
    @Test func noPasswordIsRefused() throws {
        let fixture = try Fixture.load("account-delete-no-password")
        #expect(fixture.request.body == .object([:]))
        let response = try #require(HTTPURLResponse(url: TestClient.baseURL, statusCode: fixture.response.status, httpVersion: "HTTP/1.1", headerFields: nil))
        let error = QBankClient.failure(status: fixture.response.status, data: try fixture.responseData, response: response)
        try MakeQuestionsContractTests.expect(error, is: fixture, code: .invalidRequest)
    }
}
