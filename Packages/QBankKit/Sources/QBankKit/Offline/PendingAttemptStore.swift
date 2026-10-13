import Foundation
import Synchronization

/// An answer saved on the phone, waiting to be sent.
public struct PendingAttempt: Codable, Sendable, Equatable, Identifiable {
    public let submission: AttemptSubmission
    /// The course the question belongs to, so screens can say "3 waiting to send" per course.
    public let courseID: String?
    public let queuedAt: Date

    public var id: String { submission.clientAttemptID }

    public init(submission: AttemptSubmission, courseID: String?, queuedAt: Date) {
        self.submission = submission
        self.courseID = courseID
        self.queuedAt = queuedAt
    }
}

/// Where unsent answers live between launches. The whole list is read and written at once:
/// it is small, and a write is atomic, so a crash never leaves half a list.
public protocol PendingAttemptStore: Sendable {
    func load() throws(StorageError) -> [PendingAttempt]
    func save(_ attempts: [PendingAttempt]) throws(StorageError)
}

/// Unsent answers in one JSON file. Kept in backups: they are her answers until the server has them.
public struct FilePendingAttemptStore: PendingAttemptStore {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// `Application Support/QBankKit/pending-attempts.json`.
    public static func standard() throws(StorageError) -> FilePendingAttemptStore {
        FilePendingAttemptStore(fileURL: try FileLocations.applicationSupport().appendingPathComponent("pending-attempts.json"))
    }

    public func load() throws(StorageError) -> [PendingAttempt] {
        guard let data = try FileLocations.read(fileURL, operation: "read unsent answers") else { return [] }
        do {
            return try QBankJSON.decoder.decode([PendingAttempt].self, from: data)
        } catch {
            throw StorageError(operation: "read unsent answers", reason: "the file cannot be read: \(error)")
        }
    }

    public func save(_ attempts: [PendingAttempt]) throws(StorageError) {
        try FileLocations.ensureDirectory(fileURL.deletingLastPathComponent(), excludedFromBackup: false)
        let data: Data
        do {
            data = try QBankJSON.encoder.encode(attempts)
        } catch {
            throw StorageError(operation: "save unsent answers", reason: "\(error)")
        }
        try FileLocations.write(data, to: fileURL, operation: "save unsent answers")
    }
}

/// Unsent answers in memory, for tests and previews.
public final class InMemoryPendingAttemptStore: PendingAttemptStore {
    private let attempts: Mutex<[PendingAttempt]>

    public init(_ attempts: [PendingAttempt] = []) {
        self.attempts = Mutex(attempts)
    }

    public func load() throws(StorageError) -> [PendingAttempt] {
        attempts.withLock { $0 }
    }

    public func save(_ attempts: [PendingAttempt]) throws(StorageError) {
        self.attempts.withLock { $0 = attempts }
    }
}
