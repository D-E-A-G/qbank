import Foundation

/// The Review list's filter chips.
public enum ReviewFilter: String, Codable, Sendable, CaseIterable {
    case all
    case missed
    case partial
    case guessed
}

/// `GET /api/courses/{id}/review`.
public struct ReviewList: Codable, Sendable, Equatable {
    public struct Counts: Codable, Sendable, Equatable {
        public let all: Int
        public let missed: Int
        public let partial: Int
        public let guessed: Int
    }

    public let filter: ReviewFilter
    public let counts: Counts
    public let questions: [ReviewQuestion]
}

/// A row of the Review list.
public struct ReviewQuestion: Codable, Sendable, Equatable, Identifiable {
    public let questionID: String
    public let topic: String
    /// The question's own week, from its file, for an app from before folders.
    public let weekLabel: String
    /// The folder its set is in. Nil from a server older than folders.
    public let folderID: String?
    /// That folder's name, or the week label from a server older than folders.
    public let folderName: String
    /// The format's display name, such as "Select all".
    public let format: String
    public let status: ScoreStatus
    public let guessed: Bool
    public let answeredAt: Date
    public let setTitle: String

    public var id: String { questionID }

    enum CodingKeys: String, CodingKey {
        case topic, weekLabel, folderName, format, status, guessed, answeredAt, setTitle
        case questionID = "questionId"
        case folderID = "folderId"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        questionID = try container.decode(String.self, forKey: .questionID)
        topic = try container.decode(String.self, forKey: .topic)
        weekLabel = try container.decode(String.self, forKey: .weekLabel)
        folderID = try container.decodeIfPresent(String.self, forKey: .folderID)
        folderName = try container.decodeIfPresent(String.self, forKey: .folderName) ?? weekLabel
        format = try container.decode(String.self, forKey: .format)
        status = try container.decode(ScoreStatus.self, forKey: .status)
        guessed = try container.decode(Bool.self, forKey: .guessed)
        answeredAt = try container.decode(Date.self, forKey: .answeredAt)
        setTitle = try container.decode(String.self, forKey: .setTitle)
    }
}
