import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Everything a QBankKit call can fail with.
public enum QBankError: Error, Sendable, Equatable {
    /// No session is stored on this device. Nothing was sent.
    case notSignedIn
    /// The request never got an answer: no signal, a timeout, DNS, TLS, or a dropped connection.
    case transport(URLError.Code)
    /// The task was cancelled before an answer came.
    case cancelled
    /// The server answered with an error the API documents: `{ "error": code, "message": text }`.
    case server(ServerError)
    /// The server answered with something the API does not document, such as a proxy's HTML page
    /// or a body that does not match the model. `status` is the HTTP status.
    case unexpectedResponse(status: Int, detail: String)
    /// The device could not read or write its own storage (Keychain or files).
    case storage(StorageError)
    /// The request could not be built. Nothing was sent.
    case invalidRequest(String)

    /// True when the request may succeed later without anything changing on the device:
    /// no connection, a server or proxy failure, or a rate limit.
    public var isTemporary: Bool {
        switch self {
        case .transport, .cancelled:
            return true
        case .server(let error):
            return error.status >= 500 || error.status == 429
        case .unexpectedResponse(let status, _):
            return status >= 500 || status == 429
        case .notSignedIn, .storage, .invalidRequest:
            return false
        }
    }

    /// True when the stored session is missing or the server no longer accepts it.
    public var needsSignIn: Bool {
        switch self {
        case .notSignedIn:
            return true
        case .server(let error):
            return error.status == 401 && error.code == .unauthenticated
        default:
            return false
        }
    }

    /// The server code, when the server sent one.
    public var serverCode: ServerError.Code? {
        if case .server(let error) = self { return error.code }
        return nil
    }
}

/// An error body from the server.
public struct ServerError: Error, Sendable, Equatable {
    public let status: Int
    public let code: Code
    /// A sentence written for her. Screens can show it as is.
    public let message: String
    /// How long sign-in stays locked, from the body or the Retry-After header.
    public let retryAfterSeconds: Int?

    public init(status: Int, code: Code, message: String, retryAfterSeconds: Int? = nil) {
        self.status = status
        self.code = code
        self.message = message
        self.retryAfterSeconds = retryAfterSeconds
    }

    /// The machine-readable `error` field. Open, so a code the server adds later still decodes.
    public struct Code: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(stringLiteral value: String) { self.rawValue = value }
        public var description: String { rawValue }

        // Sign-in and session.
        public static let unauthenticated: Code = "unauthenticated"
        public static let invalidCredentials: Code = "invalid_credentials"
        public static let tooManyAttempts: Code = "too_many_attempts"
        public static let mustChangePassword: Code = "must_change_password"
        public static let samePassword: Code = "same_password"
        public static let authFailed: Code = "auth_failed"
        public static let authUnavailable: Code = "auth_unavailable"
        // Content.
        public static let requestRefused: Code = "request_refused"
        // Answers.
        public static let invalidResponse: Code = "invalid_response"
        public static let attemptConflict: Code = "attempt_conflict"
        public static let adminCannotRecordAnswer: Code = "admin_cannot_record_answer"
        public static let examOnly: Code = "exam_only"
        public static let questionNotFound: Code = "question_not_found"
        // Review.
        public static let confirmationRequired: Code = "confirmation_required"
        // Exams.
        public static let noWeeks: Code = "no_weeks"
        public static let weekNotFound: Code = "week_not_found"
        public static let noWrongQuestions: Code = "no_wrong_questions"
        public static let examNotFound: Code = "exam_not_found"
        public static let examFinished: Code = "exam_finished"
        public static let alreadyAnswered: Code = "already_answered"
        public static let questionNotInExam: Code = "question_not_in_exam"
        public static let courseNotFound: Code = "course_not_found"
    }
}

/// A failure of the device's own storage.
public struct StorageError: Error, Sendable, Equatable, CustomStringConvertible {
    /// What was being done, such as "save session" or "read pending answers".
    public let operation: String
    public let reason: String
    /// The Keychain status, when the Keychain failed.
    public let status: Int32?

    public init(operation: String, reason: String, status: Int32? = nil) {
        self.operation = operation
        self.reason = reason
        self.status = status
    }

    public var description: String {
        status.map { "\(operation) failed: \(reason) (\($0))" } ?? "\(operation) failed: \(reason)"
    }
}
