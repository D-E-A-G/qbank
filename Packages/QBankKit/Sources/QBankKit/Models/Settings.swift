import Foundation

/// A passkey saved on her account, as Settings lists it. No key material.
public struct Passkey: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String?
    public let createdAt: Date?
    public let deviceType: String
}

// Request and response bodies the client sends or unwraps; screens never see these.

struct PasswordSignInRequest: Encodable {
    let email: String
    let password: String
}

struct ChangePasswordRequest: Encodable {
    let currentPassword: String
    let newPassword: String
}

struct StudyPlaceBody: Codable {
    let courseId: String?
}

struct ClearReviewRequest: Encodable {
    let confirmed: Bool
}

struct ClearReviewResponse: Decodable {
    let cleared: Int
}

struct SemestersResponse: Decodable {
    let semesters: [Semester]
}

struct TermsResponse: Decodable {
    let terms: [Term]
}

struct PasskeysResponse: Decodable {
    let passkeys: [Passkey]
}

struct StatusResponse: Decodable {
    let status: String
}

struct ErrorBody: Decodable {
    let error: String
    let message: String
    let retryAfterSeconds: Int?
}
