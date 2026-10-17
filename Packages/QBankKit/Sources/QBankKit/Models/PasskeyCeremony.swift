import Foundation

// Signing in with a passkey and saving one take two calls each: the server's WebAuthn options,
// which the device's passkey sheet answers, then that answer. The server keeps the challenge
// under a cookie it sets with the options; the client keeps no cookies, so the options carry it
// as a ticket and the answer sends it back.

/// The server's challenge for signing in with a passkey (`GET /api/sign-in/passkey/options`).
public struct PasskeySignInOptions: Sendable, Equatable {
    /// The bytes the passkey signs.
    public let challenge: Data
    /// The web domain the passkeys belong to, such as `qbank.dimitrygallego.com`.
    public let relyingPartyID: String
    /// The passkeys the server accepts; empty for any of the domain's, which is how sign-in asks.
    public let allowedCredentialIDs: [Data]
    /// `required`, `preferred`, or `discouraged`.
    public let userVerification: String?
    /// The challenge's cookie, as a `Cookie` header to send with the answer.
    let ticket: String

    init(challenge: Data, relyingPartyID: String, allowedCredentialIDs: [Data], userVerification: String?, ticket: String) {
        self.challenge = challenge
        self.relyingPartyID = relyingPartyID
        self.allowedCredentialIDs = allowedCredentialIDs
        self.userVerification = userVerification
        self.ticket = ticket
    }
}

/// The server's challenge for saving a new passkey on the signed-in account (`GET /api/passkeys/options`).
public struct PasskeyRegistrationOptions: Sendable, Equatable {
    /// The bytes the new passkey signs.
    public let challenge: Data
    /// The web domain the passkey belongs to, such as `qbank.dimitrygallego.com`.
    public let relyingPartyID: String
    /// The account's handle in the new passkey.
    public let userID: Data
    /// The name the passkey is saved under, as the Passwords app shows it.
    public let userName: String
    /// The account's passkeys, which the device must not save a second time.
    public let excludedCredentialIDs: [Data]
    /// `required`, `preferred`, or `discouraged`.
    public let userVerification: String?
    /// The challenge's cookie, as a `Cookie` header to send with the answer.
    let ticket: String

    init(
        challenge: Data, relyingPartyID: String, userID: Data, userName: String, excludedCredentialIDs: [Data],
        userVerification: String?, ticket: String
    ) {
        self.challenge = challenge
        self.relyingPartyID = relyingPartyID
        self.userID = userID
        self.userName = userName
        self.excludedCredentialIDs = excludedCredentialIDs
        self.userVerification = userVerification
        self.ticket = ticket
    }
}

/// A passkey's answer to a sign-in challenge (a WebAuthn assertion), as the device gives it.
public struct PasskeyAssertion: Sendable, Equatable {
    public let credentialID: Data
    public let clientDataJSON: Data
    public let authenticatorData: Data
    public let signature: Data
    /// The account's handle saved in the passkey, when the device returns it.
    public let userID: Data?

    public init(credentialID: Data, clientDataJSON: Data, authenticatorData: Data, signature: Data, userID: Data?) {
        self.credentialID = credentialID
        self.clientDataJSON = clientDataJSON
        self.authenticatorData = authenticatorData
        self.signature = signature
        self.userID = userID
    }
}

/// A new passkey (a WebAuthn attestation), as the device made it.
public struct PasskeyRegistration: Sendable, Equatable {
    public let credentialID: Data
    public let clientDataJSON: Data
    public let attestationObject: Data

    public init(credentialID: Data, clientDataJSON: Data, attestationObject: Data) {
        self.credentialID = credentialID
        self.clientDataJSON = clientDataJSON
        self.attestationObject = attestationObject
    }
}

/// Base64url without padding, WebAuthn's text for bytes.
public enum Base64URL {
    public static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Nil for text that is not base64url. Padding is accepted.
    public static func decode(_ text: String) -> Data? {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.hasSuffix("=") { base64.removeLast() }
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }
}

// MARK: Bodies

/// `PublicKeyCredentialRequestOptionsJSON`, as far as the device needs it.
struct PasskeyRequestOptionsBody: Decodable {
    struct Credential: Decodable {
        let id: String
    }

    let challenge: String
    let rpId: String
    let allowCredentials: [Credential]?
    let userVerification: String?

    func options(ticket: String) -> PasskeySignInOptions? {
        guard let challenge = Base64URL.decode(challenge) else { return nil }
        let allowed = (allowCredentials ?? []).map(\.id).map(Base64URL.decode)
        guard !allowed.contains(nil) else { return nil }
        return PasskeySignInOptions(
            challenge: challenge,
            relyingPartyID: rpId,
            allowedCredentialIDs: allowed.compactMap(\.self),
            userVerification: userVerification,
            ticket: ticket
        )
    }
}

/// `PublicKeyCredentialCreationOptionsJSON`, as far as the device needs it.
struct PasskeyCreationOptionsBody: Decodable {
    struct RelyingParty: Decodable {
        let id: String
    }

    struct User: Decodable {
        let id: String
        let name: String
    }

    struct Credential: Decodable {
        let id: String
    }

    struct Selection: Decodable {
        let userVerification: String?
    }

    let challenge: String
    let rp: RelyingParty
    let user: User
    let excludeCredentials: [Credential]?
    let authenticatorSelection: Selection?

    func options(ticket: String) -> PasskeyRegistrationOptions? {
        guard let challenge = Base64URL.decode(challenge), let userID = Base64URL.decode(user.id) else { return nil }
        let excluded = (excludeCredentials ?? []).map(\.id).map(Base64URL.decode)
        guard !excluded.contains(nil) else { return nil }
        return PasskeyRegistrationOptions(
            challenge: challenge,
            relyingPartyID: rp.id,
            userID: userID,
            userName: user.name,
            excludedCredentialIDs: excluded.compactMap(\.self),
            userVerification: authenticatorSelection?.userVerification,
            ticket: ticket
        )
    }
}

/// `POST /api/sign-in/passkey`: the assertion as `AuthenticationResponseJSON`, the shape a browser
/// sends for a passkey on the device itself.
struct PasskeySignInRequest: Encodable {
    struct Credential: Encodable {
        struct Response: Encodable {
            let clientDataJSON: String
            let authenticatorData: String
            let signature: String
            let userHandle: String?
        }

        let id: String
        let rawId: String
        let type = "public-key"
        let authenticatorAttachment = "platform"
        let clientExtensionResults = [String: String]()
        let response: Response
    }

    let response: Credential

    init(_ assertion: PasskeyAssertion) {
        let id = Base64URL.encode(assertion.credentialID)
        response = Credential(
            id: id,
            rawId: id,
            response: .init(
                clientDataJSON: Base64URL.encode(assertion.clientDataJSON),
                authenticatorData: Base64URL.encode(assertion.authenticatorData),
                signature: Base64URL.encode(assertion.signature),
                userHandle: assertion.userID.flatMap { $0.isEmpty ? nil : Base64URL.encode($0) }
            )
        )
    }
}

/// `POST /api/passkeys`: the new passkey as `RegistrationResponseJSON`, and its name in Settings.
struct PasskeyRegistrationRequest: Encodable {
    struct Credential: Encodable {
        struct Response: Encodable {
            let clientDataJSON: String
            let attestationObject: String
            /// What a browser reports for a passkey in iCloud Keychain: on this device, and on a
            /// phone nearby through a QR code.
            let transports = ["hybrid", "internal"]
        }

        let id: String
        let rawId: String
        let type = "public-key"
        let authenticatorAttachment = "platform"
        let clientExtensionResults = [String: String]()
        let response: Response
    }

    let response: Credential
    let name: String

    init(_ registration: PasskeyRegistration, name: String) {
        let id = Base64URL.encode(registration.credentialID)
        response = Credential(
            id: id,
            rawId: id,
            response: .init(
                clientDataJSON: Base64URL.encode(registration.clientDataJSON),
                attestationObject: Base64URL.encode(registration.attestationObject)
            )
        )
        self.name = name
    }
}
