#if DEBUG
import Foundation
import QBankKit
import Synchronization

/// The fake server's passkeys, kept the way the real server's sign-in library keeps them: the
/// options set a cookie naming their challenge, and an answer counts only with that cookie, its
/// challenge used once, and the web domain's origin in what the passkey signed. The signature is
/// not checked here; QBankKit's contract tests replay answers the real server verified.
nonisolated final class FakePasskeys: Sendable {
    static let relyingPartyID = "qbank.dimitrygallego.com"
    static let cookieName = "__Secure-fake.passkey-challenge"
    /// The passkey the student saved on her Mac. `DebugPasskeyAuthenticator.Kind.synced` puts it
    /// on the device, as iCloud Keychain does.
    static let syncedCredentialID = Data("synthetic-passkey-mac".utf8)
    static let syncedUserID = Data("synthetic-user-handle".utf8)

    enum Answer {
        case reply(status: Int, body: [String: Any], headers: [String: String] = [:])
        /// The passkey was accepted: the server signs this account in.
        case signIn(email: String)
    }

    private struct Stored {
        let id: String
        let credentialID: String
        let email: String
        let name: String?
        let createdAt: Date
    }

    private struct Challenge {
        let value: String
        let ceremony: String
        let email: String?
    }

    private struct State {
        var passkeys: [Stored]
        /// By the ticket in the challenge cookie.
        var challenges: [String: Challenge] = [:]
        var count = 0
    }

    private let state: Mutex<State>

    init(studentEmail: String, now: Date) {
        state = Mutex(State(passkeys: [
            Stored(
                id: "fake-passkey-mac", credentialID: Base64URL.encode(Self.syncedCredentialID), email: studentEmail,
                name: "MacBook Air", createdAt: now.addingTimeInterval(-45 * 86_400)
            ),
        ]))
    }

    static func handles(_ path: String) -> Bool {
        path.hasPrefix("/api/sign-in/passkey") || path.hasPrefix("/api/passkeys")
    }

    /// - Parameters:
    ///   - email: The signed-in account, or nil without a session.
    ///   - mustChangePassword: True while that account has the owner's temporary password.
    func answer(method: String, path: String, email: String?, mustChangePassword: Bool, cookie: String?, body: [String: Any]) -> Answer {
        switch (method, path) {
        case ("GET", "/api/sign-in/passkey/options"):
            return options(["rpId": Self.relyingPartyID, "timeout": 60_000, "userVerification": "preferred"], ceremony: "authentication", email: nil)
        case ("POST", "/api/sign-in/passkey"):
            return signIn(cookie: cookie, body: body)
        default:
            break
        }
        guard let email else { return failure(401, "unauthenticated", "Sign in to continue.") }
        if method == "GET", path == "/api/passkeys" {
            return .reply(status: 200, body: ["passkeys": list(email)])
        }
        if mustChangePassword {
            return failure(403, "must_change_password", "Choose a new password to continue.")
        }
        switch (method, path) {
        case ("GET", "/api/passkeys/options"):
            let saved = state.withLock { $0.passkeys.filter { $0.email == email } }
            return options([
                "rp": ["name": "Qbank", "id": Self.relyingPartyID],
                "user": ["id": Base64URL.encode(Self.syncedUserID), "name": email, "displayName": email],
                "pubKeyCredParams": [["alg": -7, "type": "public-key"]],
                "timeout": 60_000,
                "attestation": "none",
                "excludeCredentials": saved.map { ["id": $0.credentialID, "type": "public-key", "transports": ["hybrid", "internal"]] },
                "authenticatorSelection": ["residentKey": "preferred", "userVerification": "preferred", "requireResidentKey": false],
            ], ceremony: "registration", email: email)
        case ("POST", "/api/passkeys"):
            return register(email: email, cookie: cookie, body: body)
        case ("DELETE", _) where path.hasPrefix("/api/passkeys/"):
            let id = String(path.dropFirst("/api/passkeys/".count))
            let removed = state.withLock { state in
                guard let index = state.passkeys.firstIndex(where: { $0.id == id && $0.email == email }) else { return false }
                state.passkeys.remove(at: index)
                return true
            }
            return removed ? .reply(status: 200, body: ["status": "removed"]) : failure(400, "invalid_passkey", "That passkey could not be removed.")
        default:
            return failure(404, "request_refused", "That is not in the app.")
        }
    }

    private func options(_ fields: [String: Any], ceremony: String, email: String?) -> Answer {
        let (ticket, challenge) = state.withLock { state in
            state.count += 1
            let ticket = "fake-ticket-\(state.count)"
            let challenge = Base64URL.encode(Data("fake-challenge-\(state.count)".utf8))
            state.challenges[ticket] = Challenge(value: challenge, ceremony: ceremony, email: email)
            return (ticket, challenge)
        }
        return .reply(
            status: 200,
            body: fields.merging(["challenge": challenge]) { _, new in new },
            headers: ["Set-Cookie": "\(Self.cookieName)=\(ticket); Max-Age=300; Path=/; HttpOnly; Secure; SameSite=Lax"]
        )
    }

    /// The challenge the answer's cookie names, used up whatever comes of it, if what the passkey
    /// signed is that challenge, for this ceremony, from the web domain.
    private func challenge(cookie: String?, ceremony: String, credential: [String: Any]) -> Challenge? {
        let pairs = (cookie ?? "").split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let ticket = pairs.first(where: { $0.hasPrefix("\(Self.cookieName)=") })?.dropFirst(Self.cookieName.count + 1) else { return nil }
        guard let challenge = state.withLock({ $0.challenges.removeValue(forKey: String(ticket)) }), challenge.ceremony == ceremony else { return nil }
        let response = credential["response"] as? [String: Any]
        guard
            let text = response?["clientDataJSON"] as? String, let data = Base64URL.decode(text),
            let clientData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            clientData["type"] as? String == (ceremony == "authentication" ? "webauthn.get" : "webauthn.create"),
            clientData["challenge"] as? String == challenge.value,
            clientData["origin"] as? String == "https://\(Self.relyingPartyID)",
            credential["id"] as? String != nil, credential["id"] as? String == credential["rawId"] as? String,
            credential["type"] as? String == "public-key"
        else { return nil }
        return challenge
    }

    private func signIn(cookie: String?, body: [String: Any]) -> Answer {
        let credential = body["response"] as? [String: Any] ?? [:]
        guard challenge(cookie: cookie, ceremony: "authentication", credential: credential) != nil,
              let id = credential["id"] as? String,
              let email = state.withLock({ $0.passkeys.first { $0.credentialID == id }?.email })
        else { return failure(401, "invalid_passkey", "That passkey was not accepted.") }
        return .signIn(email: email)
    }

    private func register(email: String, cookie: String?, body: [String: Any]) -> Answer {
        let credential = body["response"] as? [String: Any] ?? [:]
        guard let challenge = challenge(cookie: cookie, ceremony: "registration", credential: credential), challenge.email == email,
              let id = credential["id"] as? String,
              (credential["response"] as? [String: Any])?["attestationObject"] is String
        else { return failure(400, "invalid_passkey", "That passkey was not accepted.") }
        let stored = state.withLock { state -> Stored? in
            guard !state.passkeys.contains(where: { $0.credentialID == id }) else { return nil }
            state.count += 1
            let stored = Stored(id: "fake-passkey-\(state.count)", credentialID: id, email: email, name: body["name"] as? String, createdAt: .now)
            state.passkeys.append(stored)
            return stored
        }
        guard let stored else { return failure(400, "invalid_passkey", "That passkey was not accepted.") }
        return .reply(status: 200, body: json(stored))
    }

    private func list(_ email: String) -> [[String: Any]] {
        state.withLock { state in state.passkeys.filter { $0.email == email }.map(json) }
    }

    private func json(_ passkey: Stored) -> [String: Any] {
        [
            "id": passkey.id, "name": passkey.name.map { $0 as Any } ?? NSNull(),
            "createdAt": QBankJSON.formatDate(passkey.createdAt), "deviceType": "multiDevice",
        ]
    }

    private func failure(_ status: Int, _ code: String, _ message: String) -> Answer {
        .reply(status: status, body: ["error": code, "message": message])
    }
}
#endif
