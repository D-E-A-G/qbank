import Foundation

/// Which questions an exam draws from inside the ticked weeks.
public enum ExamPool: String, Codable, Sendable, CaseIterable {
    /// Every question of the ticked weeks.
    case all
    /// Only the questions she last answered not fully right.
    case wrong
}

/// Why an exam ended.
public enum ExamEndReason: String, Codable, Sendable {
    /// She finished.
    case finished
    /// She left midway.
    case left
    /// Her time ran out.
    case timeout
}

/// `GET /api/courses/{id}/exams`: the week picker, her running exam, and her ended exams.
public struct ExamSetup: Codable, Sendable, Equatable {
    public struct Week: Codable, Sendable, Equatable, Identifiable {
        public enum Source: String, Codable, Sendable {
            /// The week has an exam bank.
            case exam
            /// The week's exams use its practice questions.
            case practice
        }

        public let label: String
        /// How many questions an exam over this week draws from.
        public let questionCount: Int
        /// Of those, the ones she last answered not fully right: what a wrong-questions exam draws from.
        public let wrongCount: Int
        public let source: Source

        public var id: String { label }
    }

    public let courseID: String
    public let weeks: [Week]
    public let inProgress: ExamSummary?
    /// Newest first.
    public let exams: [ExamSummary]

    enum CodingKeys: String, CodingKey {
        case weeks, inProgress, exams
        case courseID = "courseId"
    }
}

/// A row of her exam history.
public struct ExamSummary: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let courseID: String
    public let weeks: [String]
    public let pool: ExamPool
    /// The weeks that had no exam bank, so the exam drew their practice questions.
    /// Nil when the course had no exam bank at all.
    public let practiceWeeks: [String]?
    public let questionCount: Int
    public let timeLimitSeconds: Int
    public let startedAt: Date
    public let endsAt: Date
    public let finishedAt: Date?
    public let endReason: ExamEndReason?
    public let answeredCount: Int
    public let fullyRight: Int?
    public let points: Int?
    public let maxPoints: Int?
    public let minutesUsed: Int?

    enum CodingKeys: String, CodingKey {
        case id, weeks, pool, practiceWeeks, questionCount, timeLimitSeconds, startedAt, endsAt
        case finishedAt, endReason, answeredCount, fullyRight, points, maxPoints, minutesUsed
        case courseID = "courseId"
    }
}

/// One exam: its questions in the order served, what she answered, and, once ended, the result.
public struct Exam: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let courseID: String
    public let courseCode: String
    public let courseTitle: String
    public let weeks: [String]
    public let pool: ExamPool
    public let practiceWeeks: [String]?
    public let timeLimitSeconds: Int
    public let startedAt: Date
    public let endsAt: Date
    public let finishedAt: Date?
    public let endReason: ExamEndReason?
    /// The server's clock when it answered. The timer counts down from `endsAt - serverNow`,
    /// so a wrong phone clock does not change her time.
    public let serverNow: Date
    public let questions: [Question]
    public let answeredQuestionIDs: [String]
    public let result: ExamResult?

    public var isRunning: Bool { finishedAt == nil }

    /// Seconds left when the server answered.
    public var secondsLeftAtServerNow: TimeInterval { max(0, endsAt.timeIntervalSince(serverNow)) }

    enum CodingKeys: String, CodingKey {
        case id, courseCode, courseTitle, weeks, pool, practiceWeeks, timeLimitSeconds, startedAt, endsAt
        case finishedAt, endReason, serverNow, questions, result
        case courseID = "courseId"
        case answeredQuestionIDs = "answeredQuestionIds"
    }
}

/// The score of an ended exam.
public struct ExamResult: Codable, Sendable, Equatable {
    /// Right answers out of the total for one week or one clinical judgment step.
    public struct Breakdown: Codable, Sendable, Equatable, Identifiable {
        public let label: String
        public let right: Int
        public let total: Int

        public var id: String { label }
    }

    /// One question's mark.
    public struct Item: Codable, Sendable, Equatable, Identifiable {
        public enum Status: String, Codable, Sendable {
            case correct
            case partial
            case incorrect
            case unanswered
        }

        public let questionID: String
        public let status: Status
        public let points: Int
        public let maxPoints: Int
        public let guessed: Bool
        /// Her answer, or nil when she did not answer.
        public let response: AnswerResponse?
        /// The order she saw, or nil.
        public let shuffle: Layout?

        public var id: String { questionID }

        enum CodingKeys: String, CodingKey {
            case status, points, maxPoints, guessed, response, shuffle
            case questionID = "questionId"
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            questionID = try container.decode(String.self, forKey: .questionID)
            status = try container.decode(Status.self, forKey: .status)
            points = try container.decode(Int.self, forKey: .points)
            maxPoints = try container.decode(Int.self, forKey: .maxPoints)
            guessed = try container.decode(Bool.self, forKey: .guessed)
            // Stored as sent. One the app cannot read shows as not answered rather than failing the result.
            response = try? container.decodeIfPresent(AnswerResponse.self, forKey: .response)
            shuffle = try? container.decodeIfPresent(Layout.self, forKey: .shuffle)
        }
    }

    public let questionCount: Int
    public let answered: Int
    public let unanswered: Int
    public let fullyRight: Int
    public let partial: Int
    public let missed: Int
    public let guessed: Int
    public let points: Int
    public let maxPoints: Int
    public let minutesUsed: Int
    /// Practice questions this exam sent to Review.
    public let reviewCount: Int
    /// Exam-bank questions she got wrong. They stay out of Review.
    public let examBankWrong: Int
    public let byWeek: [Breakdown]
    public let byStep: [Breakdown]
    public let items: [Item]
}

/// The body of `POST /api/courses/{id}/exams`.
struct StartExamRequest: Encodable {
    let weeks: [String]
    let pool: ExamPool
}

/// The body of `POST /api/exams/{id}/finish`.
struct FinishExamRequest: Encodable {
    let reason: ExamEndReason
}
