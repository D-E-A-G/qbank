import Foundation

/// The signed-in person.
public struct Account: Codable, Sendable, Equatable, Identifiable {
    public enum Role: String, Codable, Sendable {
        case student
        case admin
    }

    public let id: String
    public let email: String
    public let name: String
    public let role: Role
    /// True after the admin set a temporary password: most calls answer 403 `must_change_password`
    /// until she chooses a new one with `QBankClient.changePassword`.
    public let mustChangePassword: Bool

    public init(id: String, email: String, name: String, role: Role, mustChangePassword: Bool) {
        self.id = id
        self.email = email
        self.name = name
        self.role = role
        self.mustChangePassword = mustChangePassword
    }
}

/// The answer to a password sign-in or a password change: a fresh bearer token.
public struct SignedIn: Codable, Sendable, Equatable {
    public let token: String
    public let user: Account
    public let expiresAt: Date
}

/// `GET /api/session`.
public struct Session: Codable, Sendable, Equatable {
    public let user: Account
    public let expiresAt: Date
}

/// `GET /health`.
public struct Health: Codable, Sendable, Equatable {
    public let status: String
    /// The commit the server runs.
    public let version: String
}
