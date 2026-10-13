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
    /// The course's exams, such as Exam 1, each with the weeks it covers, in the order they were
    /// added. Empty until one is made, and from a server older than course exams.
    public let exams: [CourseExam]

    public init(
        id: String, code: String, title: String, archivedAt: Date?, semester: SemesterRef,
        questionCount: Int, examQuestionCount: Int, weekCount: Int, termCount: Int, reviewCount: Int,
        answeredCount: Int, fullyRightCount: Int, points: Int, maxPoints: Int, weeks: [Week], exams: [CourseExam] = []
    ) {
        self.id = id
        self.code = code
        self.title = title
        self.archivedAt = archivedAt
        self.semester = semester
        self.questionCount = questionCount
        self.examQuestionCount = examQuestionCount
        self.weekCount = weekCount
        self.termCount = termCount
        self.reviewCount = reviewCount
        self.answeredCount = answeredCount
        self.fullyRightCount = fullyRightCount
        self.points = points
        self.maxPoints = maxPoints
        self.weeks = weeks
        self.exams = exams
    }

    enum CodingKeys: String, CodingKey {
        case id, code, title, archivedAt, semester, questionCount, examQuestionCount, weekCount, termCount
        case reviewCount, answeredCount, fullyRightCount, points, maxPoints, weeks, exams
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        code = try container.decode(String.self, forKey: .code)
        title = try container.decode(String.self, forKey: .title)
        archivedAt = try container.decodeIfPresent(Date.self, forKey: .archivedAt)
        semester = try container.decode(SemesterRef.self, forKey: .semester)
        questionCount = try container.decode(Int.self, forKey: .questionCount)
        examQuestionCount = try container.decode(Int.self, forKey: .examQuestionCount)
        weekCount = try container.decode(Int.self, forKey: .weekCount)
        termCount = try container.decode(Int.self, forKey: .termCount)
        reviewCount = try container.decode(Int.self, forKey: .reviewCount)
        answeredCount = try container.decode(Int.self, forKey: .answeredCount)
        fullyRightCount = try container.decode(Int.self, forKey: .fullyRightCount)
        points = try container.decode(Int.self, forKey: .points)
        maxPoints = try container.decode(Int.self, forKey: .maxPoints)
        weeks = try container.decode([Week].self, forKey: .weeks)
        // Added with course exams; a server from before them leaves it out, which reads as none.
        exams = try container.decodeIfPresent([CourseExam].self, forKey: .exams) ?? []
    }
}

/// An exam of a course, such as "Exam 1", and the weeks it covers. Shared by everyone, like the
/// weeks. A week is in one exam of its course at most.
public struct CourseExam: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let sortOrder: Int
    /// Its weeks, in week order. A week whose sets were all moved away stays until it is taken out.
    public let weekLabels: [String]

    public init(id: String, name: String, sortOrder: Int, weekLabels: [String]) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.weekLabels = weekLabels
    }
}

/// The body of `POST /api/courses/{id}/course-exams` and `PUT /api/course-exams/{id}`.
struct CourseExamRequest: Encodable {
    let name: String
    let weekLabels: [String]
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
