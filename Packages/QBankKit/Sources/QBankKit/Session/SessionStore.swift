import Foundation
import Synchronization

/// What the device keeps after sign-in.
public struct StoredSession: Codable, Sendable, Equatable {
    /// The bearer token from sign-in. Sent as `Authorization: Bearer`.
    public let token: String
    public let expiresAt: Date?
    /// The account as of the last sign-in or session check, so the app can open offline.
    public let account: Account?

    public init(token: String, expiresAt: Date? = nil, account: Account? = nil) {
        self.token = token
        self.expiresAt = expiresAt
        self.account = account
    }
}

/// Where the session lives between launches.
public protocol SessionStore: Sendable {
    func load() throws(StorageError) -> StoredSession?
    func save(_ session: StoredSession) throws(StorageError)
    func clear() throws(StorageError)
}

/// A session store in memory, for tests and previews.
public final class InMemorySessionStore: SessionStore {
    private let session: Mutex<StoredSession?>

    public init(_ session: StoredSession? = nil) {
        self.session = Mutex(session)
    }

    public func load() throws(StorageError) -> StoredSession? {
        session.withLock { $0 }
    }

    public func save(_ session: StoredSession) throws(StorageError) {
        self.session.withLock { $0 = session }
    }

    public func clear() throws(StorageError) {
        session.withLock { $0 = nil }
    }
}
