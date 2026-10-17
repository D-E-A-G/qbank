#if DEBUG
import Foundation
import QBankKit

/// A device's passkeys as a UI test sets them up, so signing in with a passkey and saving one run
/// end to end against `FakeQBankServer`. The system's passkey sheet needs the real web domain to
/// vouch for the app, which no test reaches; this answers at once, as the sheet does once Face ID
/// has seen her, and writes what the sheet writes. Compiled only into Debug builds.
final class DebugPasskeyAuthenticator: PasskeyAuthenticator {
    enum Kind: String {
        /// No passkey for QBank on the device yet. Saving one works; signing in with one finds
        /// none, and she closes the sheet.
        case none
        /// The passkey she saved on her Mac, which iCloud Keychain brought to this device.
        case synced
        /// She closes every passkey sheet.
        case cancels
    }

    private struct Credential {
        let id: Data
        let userID: Data
    }

    private let kind: Kind
    private var credentials: [Credential]
    /// How many times the app showed a passkey sheet.
    private(set) var asked = 0

    init(_ kind: Kind) {
        self.kind = kind
        credentials = kind == .synced ? [Credential(id: FakePasskeys.syncedCredentialID, userID: FakePasskeys.syncedUserID)] : []
    }

    func signIn(_ options: PasskeySignInOptions) async throws(PasskeyFailure) -> PasskeyAssertion {
        asked += 1
        let usable = credentials.filter { options.allowedCredentialIDs.isEmpty || options.allowedCredentialIDs.contains($0.id) }
        guard kind != .cancels, let credential = usable.last else { throw .cancelled }
        return PasskeyAssertion(
            credentialID: credential.id,
            clientDataJSON: Self.clientData("webauthn.get", options.challenge, options.relyingPartyID),
            authenticatorData: Data("synthetic-authenticator-data".utf8),
            signature: Data("synthetic-signature".utf8),
            userID: credential.userID
        )
    }

    func save(_ options: PasskeyRegistrationOptions) async throws(PasskeyFailure) -> PasskeyRegistration {
        asked += 1
        guard kind != .cancels else { throw .cancelled }
        guard !credentials.contains(where: { options.excludedCredentialIDs.contains($0.id) }) else { throw .alreadySaved }
        let credential = Credential(id: Data("synthetic-device-passkey-\(credentials.count + 1)".utf8), userID: options.userID)
        credentials.append(credential)
        return PasskeyRegistration(
            credentialID: credential.id,
            clientDataJSON: Self.clientData("webauthn.create", options.challenge, options.relyingPartyID),
            attestationObject: Data("synthetic-attestation".utf8)
        )
    }

    /// What iOS writes for an app with the web domain's passkeys: the origin is the domain's.
    private static func clientData(_ type: String, _ challenge: Data, _ relyingPartyID: String) -> Data {
        Data(#"{"type":"\#(type)","challenge":"\#(Base64URL.encode(challenge))","origin":"https://\#(relyingPartyID)"}"#.utf8)
    }
}
#endif
