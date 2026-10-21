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

struct AddSemesterRequest: Encodable {
    let number: Int
}

/// Sends every field: a nil date is sent as null, which clears it, where a missing one would keep it.
struct UpdateSemesterRequest: Encodable {
    let name: String
    let startsOn: String?
    let endsOn: String?

    private enum CodingKeys: String, CodingKey {
        case name, startsOn, endsOn
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(startsOn, forKey: .startsOn)
        try container.encode(endsOn, forKey: .endsOn)
    }
}

/// Archives a semester by hand, or brings it back; nothing else of it changes.
struct ArchiveSemesterRequest: Encodable {
    let archived: Bool
}

struct AddCourseRequest: Encodable {
    let semesterId: String
    let code: String
    let title: String
}

/// Only the fields that are set are sent; the server keeps the rest.
struct UpdateCourseRequest: Encodable {
    let code: String?
    let title: String?
    let semesterId: String?
    let archived: Bool?
}

struct AddTopicRequest: Encodable {
    let title: String
}

struct TopicOrderRequest: Encodable {
    let topicIds: [String]
}

struct TopicsResponse: Decodable {
    let topics: [CourseSummary]
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
