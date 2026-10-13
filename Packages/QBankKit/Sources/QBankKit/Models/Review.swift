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
    public let weekLabel: String
    /// The format's display name, such as "Select all".
    public let format: String
    public let status: ScoreStatus
    public let guessed: Bool
    public let answeredAt: Date
    public let setTitle: String

    public var id: String { questionID }

    enum CodingKeys: String, CodingKey {
        case topic, weekLabel, format, status, guessed, answeredAt, setTitle
        case questionID = "questionId"
    }
}
