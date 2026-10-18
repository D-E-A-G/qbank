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
    /// Folder names that hold sets, counted once each: what an app from before folders shows.
    public let weekCount: Int
    /// Her folders in the course, empty ones included: the card's "N folders".
    public let folderCount: Int
    public let reviewCount: Int
    public let answeredCount: Int
    public let fullyRightCount: Int
    public let points: Int
    public let maxPoints: Int

    public init(
        id: String, code: String, title: String, sortOrder: Int, archivedAt: Date?, questionCount: Int, weekCount: Int,
        folderCount: Int? = nil, reviewCount: Int, answeredCount: Int, fullyRightCount: Int, points: Int, maxPoints: Int
    ) {
        self.id = id
        self.code = code
        self.title = title
        self.sortOrder = sortOrder
        self.archivedAt = archivedAt
        self.questionCount = questionCount
        self.weekCount = weekCount
        self.folderCount = folderCount ?? weekCount
        self.reviewCount = reviewCount
        self.answeredCount = answeredCount
        self.fullyRightCount = fullyRightCount
        self.points = points
        self.maxPoints = maxPoints
    }

    enum CodingKeys: String, CodingKey {
        case id, code, title, sortOrder, archivedAt, questionCount, weekCount, folderCount
        case reviewCount, answeredCount, fullyRightCount, points, maxPoints
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        code = try container.decode(String.self, forKey: .code)
        title = try container.decode(String.self, forKey: .title)
        sortOrder = try container.decode(Int.self, forKey: .sortOrder)
        archivedAt = try container.decodeIfPresent(Date.self, forKey: .archivedAt)
        questionCount = try container.decode(Int.self, forKey: .questionCount)
        weekCount = try container.decode(Int.self, forKey: .weekCount)
        // Added with folders; a server or a saved copy from before them had one folder per week.
        folderCount = try container.decodeIfPresent(Int.self, forKey: .folderCount) ?? weekCount
        reviewCount = try container.decode(Int.self, forKey: .reviewCount)
        answeredCount = try container.decode(Int.self, forKey: .answeredCount)
        fullyRightCount = try container.decode(Int.self, forKey: .fullyRightCount)
        points = try container.decode(Int.self, forKey: .points)
        maxPoints = try container.decode(Int.self, forKey: .maxPoints)
    }
}

/// `GET /api/courses/{id}`: a course, its folders and exam pages, and its practice sets.
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
    /// Practice questions. Exam-bank questions are counted per folder.
    public let questionCount: Int
    /// How many questions an exam over every folder draws from.
    public let examQuestionCount: Int
    /// Folder names that hold sets, counted once each: what an app from before folders shows.
    public let weekCount: Int
    /// Her folders in the course, empty ones included.
    public let folderCount: Int
    public let termCount: Int
    public let reviewCount: Int
    public let answeredCount: Int
    public let fullyRightCount: Int
    public let points: Int
    public let maxPoints: Int
    /// The folders by name, as an app from before folders reads them: two folders that share a
    /// name on different exam pages show as one week here. `folders` is what the app uses.
    public let weeks: [Week]
    /// The course's exam pages, such as Exam 1, in the order they were added. Empty until one is
    /// made, and from a server older than course exams.
    public let exams: [CourseExam]
    /// Every folder of the course, empty ones included, in the course's order: each exam page's
    /// folders, pages in the order of `exams`, then the folders on no exam page; each list in her
    /// order. From a server older than folders, each week reads as a folder named and identified by
    /// its label.
    public let folders: [Folder]

    public init(
        id: String, code: String, title: String, archivedAt: Date?, semester: SemesterRef,
        questionCount: Int, examQuestionCount: Int, weekCount: Int, termCount: Int, reviewCount: Int,
        answeredCount: Int, fullyRightCount: Int, points: Int, maxPoints: Int, weeks: [Week], exams: [CourseExam] = [],
        folders: [Folder]? = nil, folderCount: Int? = nil
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
        self.folders = folders ?? Folder.legacy(weeks: weeks, exams: exams)
        self.folderCount = folderCount ?? self.folders.count
    }

    enum CodingKeys: String, CodingKey {
        case id, code, title, archivedAt, semester, questionCount, examQuestionCount, weekCount, folderCount, termCount
        case reviewCount, answeredCount, fullyRightCount, points, maxPoints, weeks, exams, folders
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
        // Added with folders; a server or a saved copy from before them reads each week as a folder.
        folders = try container.decodeIfPresent([Folder].self, forKey: .folders) ?? Folder.legacy(weeks: weeks, exams: exams)
        folderCount = try container.decodeIfPresent(Int.self, forKey: .folderCount) ?? folders.count
    }
}

/// An exam page of a course, such as "Exam 1", and the folders on it. A folder is on one exam
/// page of its course at most.
public struct CourseExam: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let sortOrder: Int
    /// The names of its folders, for an app from before folders.
    public let weekLabels: [String]
    /// Its folders (`CourseDetail.folders` with this `examPageID`), in her order on the page.
    /// Empty from a server older than folders.
    public let folderIDs: [String]

    public init(id: String, name: String, sortOrder: Int, weekLabels: [String], folderIDs: [String] = []) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.weekLabels = weekLabels
        self.folderIDs = folderIDs
    }

    enum CodingKeys: String, CodingKey {
        case id, name, sortOrder, weekLabels
        case folderIDs = "folderIds"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        sortOrder = try container.decode(Int.self, forKey: .sortOrder)
        weekLabels = try container.decode([String].self, forKey: .weekLabels)
        folderIDs = try container.decodeIfPresent([String].self, forKey: .folderIDs) ?? []
    }
}

/// The body of `POST /api/courses/{id}/course-exams` and `PUT /api/course-exams/{id}`.
struct CourseExamRequest: Encodable {
    let name: String
    let folderIds: [String]
}

/// A folder of a course: her practice sets, on one exam page or none. Its id is its identity, so
/// two folders may share a name on different exam pages, and a rename changes nothing else.
public struct Folder: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    /// The exam page (`CourseDetail.exams`) it is on, or nil when it is on none.
    public let examPageID: String?
    /// Its place in its list: its exam page's folders, or the folders on no exam page.
    public let sortOrder: Int
    /// Its practice sets. Exam-bank sets are counted in `examBankCount` instead.
    public let sets: [PracticeSetSummary]
    /// Exam-bank questions in this folder, asked only on exams. 0 without an exam bank.
    public let examBankCount: Int
    /// Its exam sets (its exam bank), by title, each asked only on exams. Empty without an exam
    /// bank. One can be deleted on its own.
    public let examSets: [ExamSetSummary]

    public init(
        id: String, name: String, examPageID: String?, sortOrder: Int, sets: [PracticeSetSummary], examBankCount: Int,
        examSets: [ExamSetSummary] = []
    ) {
        self.id = id
        self.name = name
        self.examPageID = examPageID
        self.sortOrder = sortOrder
        self.sets = sets
        self.examBankCount = examBankCount
        self.examSets = examSets
    }

    enum CodingKeys: String, CodingKey {
        case id, name, sortOrder, sets, examBankCount, examSets
        case examPageID = "examPageId"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        examPageID = try container.decodeIfPresent(String.self, forKey: .examPageID)
        sortOrder = try container.decode(Int.self, forKey: .sortOrder)
        sets = try container.decode([PracticeSetSummary].self, forKey: .sets)
        examBankCount = try container.decode(Int.self, forKey: .examBankCount)
        // Added with deleting; a server or a saved copy from before it sent only the count.
        examSets = try container.decodeIfPresent([ExamSetSummary].self, forKey: .examSets) ?? []
    }

    /// The folders a course from before folders has: one per week, named and identified by its
    /// label, on the exam holding that label, in week order.
    static func legacy(weeks: [Week], exams: [CourseExam]) -> [Folder] {
        weeks.enumerated().map { index, week in
            Folder(
                id: week.label,
                name: week.label,
                examPageID: exams.first { $0.weekLabels.contains(week.label) }?.id,
                sortOrder: index + 1,
                sets: week.sets,
                examBankCount: week.examBankCount
            )
        }
    }
}

/// An exam set of a folder's exam bank, asked only on exams.
public struct ExamSetSummary: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let questionCount: Int

    public init(id: String, title: String, questionCount: Int) {
        self.id = id
        self.title = title
        self.questionCount = questionCount
    }
}

/// The body of `POST /api/courses/{id}/folders`, and of `PATCH /api/folders/{id}` for a rename.
struct FolderNameRequest: Encodable {
    let name: String
}

/// The body of `PATCH /api/folders/{id}` that puts a folder on an exam page or, with nil, on none.
struct FolderPageRequest: Encodable {
    let examPageId: String?

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Taking it off its page is sent as null; left out, the folder would keep its page.
        try container.encode(examPageId, forKey: .examPageId)
    }

    enum CodingKeys: String, CodingKey {
        case examPageId
    }
}

/// The body of `POST /api/practice-sets/{id}/move`: a folder of the course, or a new one by name.
struct MoveSetRequest: Encodable {
    let folderId: String?
    let newFolderName: String?

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(folderId, forKey: .folderId)
        try container.encodeIfPresent(newFolderName, forKey: .newFolderName)
    }

    enum CodingKeys: String, CodingKey {
        case folderId, newFolderName
    }
}

/// The body of `PUT /api/courses/{id}/folder-order`: one list's folders in her order.
struct FolderOrderRequest: Encodable {
    let examPageId: String?
    let folderIds: [String]

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // The folders on no exam page are sent as null, not left out.
        try container.encode(examPageId, forKey: .examPageId)
        try container.encode(folderIds, forKey: .folderIds)
    }

    enum CodingKeys: String, CodingKey {
        case examPageId, folderIds
    }
}

/// One week of a course: its sets under one folder name, as an app from before folders reads them.
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
    /// The name of its set's folder, for an app from before folders.
    public let weekLabel: String
    /// The folder of the set that defines it. Nil from a server older than folders.
    public let folderID: String?
    /// That folder's name, or the week label from a server older than folders.
    public let folderName: String
    public let setTitle: String

    public var id: String { "\(key)|\(folderID ?? weekLabel)|\(setTitle)" }

    public init(key: String, term: String, meaning: String, weekLabel: String, folderID: String? = nil, folderName: String? = nil, setTitle: String) {
        self.key = key
        self.term = term
        self.meaning = meaning
        self.weekLabel = weekLabel
        self.folderID = folderID
        self.folderName = folderName ?? weekLabel
        self.setTitle = setTitle
    }

    enum CodingKeys: String, CodingKey {
        case key, term, meaning, weekLabel, folderName, setTitle
        case folderID = "folderId"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        term = try container.decode(String.self, forKey: .term)
        meaning = try container.decode(String.self, forKey: .meaning)
        weekLabel = try container.decode(String.self, forKey: .weekLabel)
        folderID = try container.decodeIfPresent(String.self, forKey: .folderID)
        folderName = try container.decodeIfPresent(String.self, forKey: .folderName) ?? weekLabel
        setTitle = try container.decode(String.self, forKey: .setTitle)
    }
}
