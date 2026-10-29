import Foundation

// Connect an agent: her own AI agent asks to pair and shows her a short code; she looks it up in
// Settings, sees the agent's name and what its key would do, and approves or denies it. The agent
// picks its key up itself, so no key ever reaches the app. Her keys are listed, each revocable.

/// What an agent key may do. Open, so a scope the server adds later still decodes, and shows by its
/// name.
public struct AgentScope: RawRepresentable, Hashable, Sendable, Codable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    /// Check and import question files, reading her courses and sets to file them.
    public static let `import`: AgentScope = "import"
    /// Read how she answered, and change nothing.
    public static let read: AgentScope = "read"
    /// Add, change and delete her content as she can, every delete with Undo.
    public static let manage: AgentScope = "manage"
}

/// The agent waiting under a code: the name it asked with and what its key would be able to do.
public struct AgentPairing: Codable, Sendable, Equatable {
    /// `pending` until she answers. Open, so a status the server adds later still decodes.
    public struct Status: RawRepresentable, Hashable, Sendable, Codable, ExpressibleByStringLiteral {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(stringLiteral value: String) { self.rawValue = value }

        public static let pending: Status = "pending"
        public static let approved: Status = "approved"
        public static let denied: Status = "denied"
    }

    /// One scope in the server's plain words, to show beside the agent's name.
    public struct ScopeText: Codable, Sendable, Equatable {
        public let scope: AgentScope
        public let text: String

        public init(scope: AgentScope, text: String) {
            self.scope = scope
            self.text = text
        }
    }

    public let name: String
    public let scopes: [AgentScope]
    /// Each of `scopes`, in the same order, in plain words.
    public let scopeTexts: [ScopeText]
    public let status: Status
    public let createdAt: Date
    /// When the code stops working, approved or not, if the agent has not picked up its key.
    public let expiresAt: Date

    public init(name: String, scopes: [AgentScope], scopeTexts: [ScopeText], status: Status, createdAt: Date, expiresAt: Date) {
        self.name = name
        self.scopes = scopes
        self.scopeTexts = scopeTexts
        self.status = status
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }
}

/// One of the account's agent keys, as listed: never the key itself.
public struct AgentKey: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    /// The name the agent paired with.
    public let name: String
    public let scopes: [AgentScope]
    /// When the agent picked it up.
    public let createdAt: Date
    /// When it last let the agent in, or nil when it never has.
    public let lastUsedAt: Date?
    /// When she revoked it, or nil while it works. A revoked key stays listed and never works again.
    public let revokedAt: Date?

    public init(id: String, name: String, scopes: [AgentScope], createdAt: Date, lastUsedAt: Date?, revokedAt: Date?) {
        self.id = id
        self.name = name
        self.scopes = scopes
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.revokedAt = revokedAt
    }

    public var isRevoked: Bool { revokedAt != nil }
}

/// The agent key that imported a set: its id, as `agentKeys()` lists it, and the name it paired with.
/// It stays after the key is revoked.
public struct ImportingAgent: Codable, Sendable, Equatable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

// Request and response bodies the client sends or unwraps; screens never see these.

struct AgentPairingCodeRequest: Encodable {
    let userCode: String
}

struct AgentKeysResponse: Decodable {
    let keys: [AgentKey]
}
