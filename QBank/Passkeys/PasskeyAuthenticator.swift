import AuthenticationServices
import OSLog
import QBankKit
import UIKit

/// Why the device gave no passkey.
enum PasskeyFailure: Error, Equatable {
    /// She closed the passkey sheet, or the system closed it.
    case cancelled
    /// The device already has one of the account's passkeys, and said so in its own sheet.
    case alreadySaved
    /// The device could not make or use a passkey: it has no passcode, or the web domain does not
    /// yet vouch for the app, for example.
    case failed
}

/// The device's passkeys: iCloud Keychain, or the passkey provider she chose in the Settings app.
protocol PasskeyAuthenticator {
    /// Asks her to pick one of the web domain's passkeys and signs the challenge with it.
    func signIn(_ options: PasskeySignInOptions) async throws(PasskeyFailure) -> PasskeyAssertion
    /// Asks her to save a new passkey for her account.
    func save(_ options: PasskeyRegistrationOptions) async throws(PasskeyFailure) -> PasskeyRegistration
}

/// `PasskeyAuthenticator` through AuthenticationServices. The passkeys belong to the web domain,
/// which names the app in its `apple-app-site-association` file, and the app names the domain in
/// its `webcredentials` entitlement. So a passkey saved on the web signs her in here, and one saved
/// here signs her in on the web.
struct SystemPasskeyAuthenticator: PasskeyAuthenticator {
    func signIn(_ options: PasskeySignInOptions) async throws(PasskeyFailure) -> PasskeyAssertion {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: options.relyingPartyID)
        let request = provider.createCredentialAssertionRequest(challenge: options.challenge)
        request.allowedCredentials = options.allowedCredentialIDs.map(ASAuthorizationPlatformPublicKeyCredentialDescriptor.init(credentialID:))
        request.userVerificationPreference = Self.preference(options.userVerification)
        guard case .assertion(let assertion) = try await PasskeySheet().perform(request) else { throw .failed }
        return assertion
    }

    func save(_ options: PasskeyRegistrationOptions) async throws(PasskeyFailure) -> PasskeyRegistration {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: options.relyingPartyID)
        let request = provider.createCredentialRegistrationRequest(challenge: options.challenge, name: options.userName, userID: options.userID)
        request.excludedCredentials = options.excludedCredentialIDs.map(ASAuthorizationPlatformPublicKeyCredentialDescriptor.init(credentialID:))
        request.userVerificationPreference = Self.preference(options.userVerification)
        request.attestationPreference = .none
        guard case .registration(let registration) = try await PasskeySheet().perform(request) else { throw .failed }
        return registration
    }

    private static func preference(_ text: String?) -> ASAuthorizationPublicKeyCredentialUserVerificationPreference {
        switch text {
        case "required": .required
        case "discouraged": .discouraged
        default: .preferred
        }
    }
}

/// One passkey sheet from the system, over the window she is using, and her answer.
private final class PasskeySheet: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    enum Answer {
        case assertion(PasskeyAssertion)
        case registration(PasskeyRegistration)
    }

    private static let log = Logger(subsystem: "com.dimitrygallego.qbank", category: "passkeys")
    private var continuation: CheckedContinuation<Result<Answer, PasskeyFailure>, Never>?
    /// Kept until she answers: the system does not keep the controller alive by itself.
    private var controller: ASAuthorizationController?

    func perform(_ request: ASAuthorizationRequest) async throws(PasskeyFailure) -> Answer {
        let result = await withCheckedContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            self.controller = controller
            controller.performRequests()
        }
        return try result.get()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        switch authorization.credential {
        case let assertion as ASAuthorizationPlatformPublicKeyCredentialAssertion:
            finish(.success(.assertion(PasskeyAssertion(
                credentialID: assertion.credentialID,
                clientDataJSON: assertion.rawClientDataJSON,
                authenticatorData: assertion.rawAuthenticatorData,
                signature: assertion.signature,
                userID: assertion.userID
            ))))
        case let registration as ASAuthorizationPlatformPublicKeyCredentialRegistration:
            guard let attestationObject = registration.rawAttestationObject else {
                Self.log.error("The new passkey came without its attestation object")
                finish(.failure(.failed))
                return
            }
            finish(.success(.registration(PasskeyRegistration(
                credentialID: registration.credentialID,
                clientDataJSON: registration.rawClientDataJSON,
                attestationObject: attestationObject
            ))))
        default:
            Self.log.error("The passkey sheet answered with \(type(of: authorization.credential))")
            finish(.failure(.failed))
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
        let code = (error as? ASAuthorizationError)?.code
        switch code {
        case .canceled:
            finish(.failure(.cancelled))
        case .matchedExcludedCredential:
            finish(.failure(.alreadySaved))
        default:
            // Kept in the device's log for a run on a real device, such as when the domain's
            // association file does not name this app yet.
            Self.log.error("The passkey sheet failed: \(error.localizedDescription, privacy: .public)")
            finish(.failure(.failed))
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.keyWindow ?? scene?.windows.first ?? ASPresentationAnchor()
    }

    private func finish(_ result: Result<Answer, PasskeyFailure>) {
        continuation?.resume(returning: result)
        continuation = nil
        controller = nil
    }
}
