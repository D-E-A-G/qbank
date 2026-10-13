import Foundation

/// A semester and its courses, as Home lists them.
public struct Semester: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let number: Int
    public let name: String
    /// A calendar date such as `2026-01-12`, or nil.
    public let startsOn: String?
    public let endsOn: String?
    public let courses: [CourseSummary]
}

/// A course card on Home.
public struct CourseSummary: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let code: String
    public let title: String
    public let sortOrder: Int
    public let archivedAt: Date?
    public let questionCount: Int
    public let weekCount: Int
    public let reviewCount: Int
    public let answeredCount: Int
    public let fullyRightCount: Int
    public let points: Int
    public let maxPoints: Int
}

/// `GET /api/courses/{id}`: a course, its weeks, and its practice sets.
public struct CourseDetail: Codable, Sendable, Equatable, Identifiable {
    public struct SemesterRef: Codable, Sendable, Equatable, Identifiable {
        public let id: String
        public let number: Int
        public let name: String
    }

    public let id: String
    public let code: String
    public let title: String
    public let archivedAt: Date?
    public let semester: SemesterRef
    /// Practice questions. Exam-bank questions are counted per week.
    public let questionCount: Int
    /// How many questions an exam over every week draws from.
    public let examQuestionCount: Int
    /// Weeks with practice sets.
    public let weekCount: Int
    public let termCount: Int
    public let reviewCount: Int
    public let answeredCount: Int
    public let fullyRightCount: Int
    public let points: Int
    public let maxPoints: Int
    public let weeks: [Week]
}

/// One week of a course.
public struct Week: Codable, Sendable, Equatable, Identifiable {
    public let label: String
    public let sets: [PracticeSetSummary]
    /// Exam-bank questions that count toward this week, asked only on exams. 0 without an exam bank.
    public let examBankCount: Int

    public var id: String { label }
}

/// A practice set row on the course screen.
public struct PracticeSetSummary: Codable, Sendable, Equatable, Identifiable {
    public enum Status: String, Codable, Sendable {
        case imported
        case replaced
        case restored
    }

    public let id: String
    public let title: String
    public let description: String
    public let questionCount: Int
    public let importedAt: Date
    public let activeSince: Date
    public let status: Status
    public let canRestore: Bool
    public let answeredCount: Int
    public let fullyRightCount: Int
    public let lastAnsweredAt: Date?
    public let questionIDs: [String]

    enum CodingKeys: String, CodingKey {
        case id, title, description, questionCount, importedAt, activeSince, status, canRestore
        case answeredCount, fullyRightCount, lastAnsweredAt
        case questionIDs = "questionIds"
    }
}

/// A row of the course's Terms screen.
public struct Term: Codable, Sendable, Equatable, Identifiable {
    public let key: String
    public let term: String
    public let meaning: String
    public let weekLabel: String
    public let setTitle: String

    public var id: String { "\(key)|\(weekLabel)|\(setTitle)" }
}
