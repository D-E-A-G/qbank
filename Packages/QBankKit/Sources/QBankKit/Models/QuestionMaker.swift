import Foundation

// Make questions (phase Q). The server writes them with its own Claude key, for the accounts it
// allows; the app only sends her material and her picks, and never holds a key.

/// How hard the questions are, as her nclex-questions recipe names the levels.
public enum QuestionLevel: String, Codable, Sendable, CaseIterable {
    /// Short four-option questions like her class exam. The recipe's default.
    case exam
    /// NCLEX formats one step below the board.
    case course
    /// Hard NCLEX board items.
    case board
}

/// What her material holds.
public enum MaterialKind: String, Codable, Sendable {
    /// Notes or slides: QBank writes new questions from them, five samples first.
    case notes
    /// Practice questions already on paper: QBank copies them in, each one checked by her.
    case questions
}

/// `GET /api/question-maker`: whether she may start a set now, and the choices. Every signed-in
/// account may ask; whether the account may make questions at all is told by
/// `QBankClient.questionJobs()`, which refuses an account the server does not allow.
public struct QuestionMakerStatus: Codable, Sendable, Equatable {
    /// How many questions a set at a level may have.
    public struct LevelRange: Codable, Sendable, Equatable {
        public let level: QuestionLevel
        public let minCount: Int
        public let maxCount: Int
        public let defaultCount: Int

        public init(level: QuestionLevel, minCount: Int, maxCount: Int, defaultCount: Int) {
            self.level = level
            self.minCount = minCount
            self.maxCount = maxCount
            self.defaultCount = defaultCount
        }
    }

    /// The most material one set takes.
    public struct Limits: Codable, Sendable, Equatable {
        public let photos: Int
        /// Per photo, before base64.
        public let photoBytes: Int
        public let fileBytes: Int
        public let textCharacters: Int

        public init(photos: Int, photoBytes: Int, fileBytes: Int, textCharacters: Int) {
            self.photos = photos
            self.photoBytes = photoBytes
            self.fileBytes = fileBytes
            self.textCharacters = textCharacters
        }
    }

    /// True when she may start a set now.
    public let available: Bool
    /// Why not, as a sentence to show her as it is: not on this account, not set up yet, or the
    /// daily limit.
    public let reason: String?
    public let dailyLimit: Int
    /// Sets she started in the last 24 hours.
    public let startedToday: Int
    /// At the daily limit: when she can start another.
    public let nextAvailableAt: Date?
    public let levels: [LevelRange]
    public let defaultLevel: QuestionLevel
    /// The samples she checks before the rest is written.
    public let sampleSize: Int
    public let limits: Limits
    public let imageTypes: [String]
    public let fileTypes: [String]

    public init(
        available: Bool, reason: String?, dailyLimit: Int, startedToday: Int, nextAvailableAt: Date?, levels: [LevelRange],
        defaultLevel: QuestionLevel, sampleSize: Int, limits: Limits, imageTypes: [String], fileTypes: [String]
    ) {
        self.available = available
        self.reason = reason
        self.dailyLimit = dailyLimit
        self.startedToday = startedToday
        self.nextAvailableAt = nextAvailableAt
        self.levels = levels
        self.defaultLevel = defaultLevel
        self.sampleSize = sampleSize
        self.limits = limits
        self.imageTypes = imageTypes
        self.fileTypes = fileTypes
    }

    /// The range of a level, or the server's own rules for exam level when it sends none.
    public func range(of level: QuestionLevel) -> LevelRange {
        levels.first { $0.level == level } ?? LevelRange(level: level, minCount: 10, maxCount: 15, defaultCount: 15)
    }
}

/// What `QBankClient.startQuestionJob` sends: her material, where the set goes, and for notes, the
/// level, how many, and the reference set.
public struct NewQuestionJob: Sendable, Equatable {
    /// A photo, as the image data the server reads.
    public struct Image: Sendable, Equatable {
        public let mediaType: String
        public let data: Data

        public init(mediaType: String, data: Data) {
            self.mediaType = mediaType
            self.data = data
        }
    }

    /// A PDF or a text file.
    public struct File: Sendable, Equatable {
        public let name: String
        public let mediaType: String
        public let data: Data

        public init(name: String, mediaType: String, data: Data) {
            self.name = name
            self.mediaType = mediaType
            self.data = data
        }
    }

    public let courseID: String
    /// One of the course's folders, or nil for the folder named by `folderName`, or for Unsorted.
    public let folderID: String?
    /// A folder by name: the course's folder of that name, or a new one.
    public let folderName: String?
    public let materialKind: MaterialKind
    public let text: String?
    public let images: [Image]
    public let file: File?
    /// Notes only: the level, how many, and at exam level the set to measure against.
    public let level: QuestionLevel?
    public let count: Int?
    public let referenceSetID: String?
    public let examTwins: Bool
    /// A set name, or nil for the writer's.
    public let title: String?

    public init(
        courseID: String, folderID: String? = nil, folderName: String? = nil, materialKind: MaterialKind,
        text: String? = nil, images: [Image] = [], file: File? = nil,
        level: QuestionLevel? = nil, count: Int? = nil, referenceSetID: String? = nil, examTwins: Bool, title: String? = nil
    ) {
        self.courseID = courseID
        self.folderID = folderID
        self.folderName = folderName
        self.materialKind = materialKind
        self.text = text
        self.images = images
        self.file = file
        self.level = level
        self.count = count
        self.referenceSetID = referenceSetID
        self.examTwins = examTwins
        self.title = title
    }
}

/// A set being made on the server, from her notes or copied from her photos.
public struct QuestionJob: Codable, Sendable, Equatable, Identifiable {
    public enum Status: String, Codable, Sendable {
        /// QBank is working on it.
        case running
        /// It waits for her: see `waitingFor`.
        case waiting
        /// Filed: see `sets`.
        case done
        /// Stopped: `failure` says why.
        case failed
        case cancelled
    }

    public enum Step: String, Codable, Sendable {
        case read, samples, review, write, check, twins, file, done
    }

    /// What it waits for her to check.
    public enum Waiting: String, Codable, Sendable {
        case samples
        case copies
    }

    /// One of the steps this set goes through, as the server names it.
    public struct StepProgress: Codable, Sendable, Equatable {
        public enum State: String, Codable, Sendable {
            case done, current, waiting, failed, cancelled, todo
        }

        public let key: Step
        public let label: String
        public let state: State
        /// How far the current step has got, when it counts something: questions written, photos read.
        public let done: Int?
        public let total: Int?

        public init(key: Step, label: String, state: State, done: Int? = nil, total: Int? = nil) {
            self.key = key
            self.label = label
            self.state = state
            self.done = done
            self.total = total
        }
    }

    public struct Course: Codable, Sendable, Equatable {
        public let id: String
        public let code: String
        public let title: String

        public init(id: String, code: String, title: String) {
            self.id = id
            self.code = code
            self.title = title
        }
    }

    /// The folder the set goes into, or once filed, the folder it is in. `id` is nil for a folder
    /// named but not made yet, and for Unsorted before it exists.
    public struct Folder: Codable, Sendable, Equatable {
        public let id: String?
        public let name: String

        public init(id: String?, name: String) {
            self.id = id
            self.name = name
        }
    }

    public struct Reference: Codable, Sendable, Equatable {
        public let id: String
        public let title: String

        public init(id: String, title: String) {
            self.id = id
            self.title = title
        }
    }

    /// A set filed so far: the practice set, then its exam twins.
    public struct FiledSet: Codable, Sendable, Equatable {
        public let id: String
        public let title: String
        public let kind: PracticeSet.Kind

        public init(id: String, title: String, kind: PracticeSet.Kind) {
            self.id = id
            self.title = title
            self.kind = kind
        }
    }

    public let id: String
    public let status: Status
    public let step: Step
    public let waitingFor: Waiting?
    public let steps: [StepProgress]
    public let course: Course
    public let folder: Folder
    public let materialKind: MaterialKind
    public let level: QuestionLevel
    public let reference: Reference?
    /// Questions in the practice set (notes), or nil when copying, which copies every question.
    public let count: Int?
    public let examTwins: Bool
    /// The set name she typed, or nil for the writer's.
    public let title: String?
    public let photoCount: Int
    public let sets: [FiledSet]
    public let createdAt: Date
    public let updatedAt: Date
    public let finishedAt: Date?
    /// Why it failed, as a sentence to show her.
    public let failure: String?
    public let warnings: [String]

    public init(
        id: String, status: Status, step: Step, waitingFor: Waiting?, steps: [StepProgress], course: Course, folder: Folder,
        materialKind: MaterialKind, level: QuestionLevel, reference: Reference? = nil, count: Int?, examTwins: Bool,
        title: String? = nil, photoCount: Int, sets: [FiledSet] = [], createdAt: Date, updatedAt: Date, finishedAt: Date? = nil,
        failure: String? = nil, warnings: [String] = []
    ) {
        self.id = id
        self.status = status
        self.step = step
        self.waitingFor = waitingFor
        self.steps = steps
        self.course = course
        self.folder = folder
        self.materialKind = materialKind
        self.level = level
        self.reference = reference
        self.count = count
        self.examTwins = examTwins
        self.title = title
        self.photoCount = photoCount
        self.sets = sets
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.finishedAt = finishedAt
        self.failure = failure
        self.warnings = warnings
    }

    /// The step QBank is on or waits at.
    public var currentStep: StepProgress? {
        steps.first { $0.state != .done && $0.state != .todo }
    }
}

/// `GET /api/question-jobs/{id}/samples`: the samples she checks, as she will see them.
public struct QuestionSamples: Decodable, Sendable, Equatable {
    /// 1 for the first samples, 2 after her first notes, and so on.
    public let round: Int
    /// What the writer said when it wrote them again from her notes.
    public let note: String?
    /// False once they were written again as many times as the server allows.
    public let canRevise: Bool
    /// In order, each with its id in the set file (A01...) as both its id and public id.
    public let questions: [Question]

    public init(round: Int, note: String?, canRevise: Bool, questions: [Question]) {
        self.round = round
        self.note = note
        self.canRevise = canRevise
        self.questions = questions
    }

    enum CodingKeys: String, CodingKey {
        case round, note, canRevise, questions
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        round = try container.decode(Int.self, forKey: .round)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        canRevise = try container.decode(Bool.self, forKey: .canRevise)
        let drafts = try container.decode([JSONValue].self, forKey: .questions)
        questions = try drafts.enumerated().map { try Question(draft: $1, position: $0 + 1) }
    }
}

/// `GET /api/question-jobs/{id}/copies`: the questions copied from her photos, for her check.
public struct QuestionCopies: Decodable, Sendable, Equatable {
    public struct Copy: Sendable, Equatable, Identifiable {
        public enum AnswerSource: String, Codable, Sendable {
            /// Marked on the photo.
            case photo
            /// The photo marks none, so QBank suggests one, labelled "check it".
            case suggested
        }

        public enum ExplanationSource: String, Codable, Sendable {
            case photo
            /// The photo has none, so QBank wrote them.
            case qbank
        }

        /// Its id in the set file (P01...).
        public let id: String
        /// The photo it is on, from 1, or nil for pasted text or a file.
        public let photo: Int?
        public let answerFrom: AnswerSource
        public let explanationsFrom: ExplanationSource
        public let question: Question
        /// The question in the set file format, to change and send back when she fixes it.
        public let file: JSONValue

        public init(id: String, photo: Int?, answerFrom: AnswerSource, explanationsFrom: ExplanationSource, question: Question, file: JSONValue) {
            self.id = id
            self.photo = photo
            self.answerFrom = answerFrom
            self.explanationsFrom = explanationsFrom
            self.question = question
            self.file = file
        }
    }

    /// A question it could not copy in full: "The bottom of photo 2 is blurry."
    public struct Unreadable: Codable, Sendable, Equatable {
        public let photo: Int?
        public let reason: String

        public init(photo: Int?, reason: String) {
            self.photo = photo
            self.reason = reason
        }
    }

    public let title: String
    public let photoCount: Int
    public let questions: [Copy]
    public let unreadable: [Unreadable]

    public init(title: String, photoCount: Int, questions: [Copy], unreadable: [Unreadable]) {
        self.title = title
        self.photoCount = photoCount
        self.questions = questions
        self.unreadable = unreadable
    }

    private struct RawCopy: Decodable {
        let id: String
        let photo: Int?
        let answerFrom: Copy.AnswerSource
        let explanationsFrom: Copy.ExplanationSource
        let question: JSONValue
        let file: JSONValue
    }

    enum CodingKeys: String, CodingKey {
        case title, photoCount, questions, unreadable
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        photoCount = try container.decode(Int.self, forKey: .photoCount)
        unreadable = try container.decode([Unreadable].self, forKey: .unreadable)
        questions = try container.decode([RawCopy].self, forKey: .questions).enumerated().map { index, raw in
            Copy(
                id: raw.id, photo: raw.photo, answerFrom: raw.answerFrom, explanationsFrom: raw.explanationsFrom,
                question: try Question(draft: raw.question, position: index + 1), file: raw.file
            )
        }
    }
}

/// A copy she keeps, with her fixed question in the set file format when she fixed it.
public struct KeptCopy: Sendable, Equatable {
    public let id: String
    public let question: JSONValue?

    public init(id: String, question: JSONValue? = nil) {
        self.id = id
        self.question = question
    }
}

/// Her note on one sample, for `QBankClient.reviseSamples`.
public struct SampleChange: Sendable, Equatable {
    public let questionID: String
    public let note: String

    public init(questionID: String, note: String) {
        self.questionID = questionID
        self.note = note
    }
}

/// `GET /api/question-jobs/{id}/result`: the finished set, its exam twins, and the blind check.
public struct QuestionResult: Codable, Sendable, Equatable {
    public struct FiledSet: Codable, Sendable, Equatable {
        public let setID: String
        public let title: String
        public let folderID: String
        public let folderName: String
        public let examPageID: String?
        public let questionCount: Int
        public let termCount: Int

        public init(setID: String, title: String, folderID: String, folderName: String, examPageID: String?, questionCount: Int, termCount: Int) {
            self.setID = setID
            self.title = title
            self.folderID = folderID
            self.folderName = folderName
            self.examPageID = examPageID
            self.questionCount = questionCount
            self.termCount = termCount
        }

        enum CodingKeys: String, CodingKey {
            case title, folderName, questionCount, termCount
            case setID = "setId"
            case folderID = "folderId"
            case examPageID = "examPageId"
        }
    }

    /// What the blind check, a fresh pass that answers each question before it sees the key, did.
    public struct BlindCheck: Codable, Sendable, Equatable {
        public struct Outcome: Codable, Sendable, Equatable {
            public enum Kind: String, Codable, Sendable {
                case passed, fixed, removed
            }

            public let id: String
            public let topic: String
            public let outcome: Kind
            /// WRONG, AMBIGUOUS, EXTRA, and the level's flags.
            public let flags: [String]

            public init(id: String, topic: String, outcome: Kind, flags: [String]) {
                self.id = id
                self.topic = topic
                self.outcome = outcome
                self.flags = flags
            }
        }

        public let passed: Int
        public let fixed: Int
        public let removed: Int
        public let questions: [Outcome]
        public let changeList: String

        public init(passed: Int, fixed: Int, removed: Int, questions: [Outcome], changeList: String) {
            self.passed = passed
            self.fixed = fixed
            self.removed = removed
            self.questions = questions
            self.changeList = changeList
        }
    }

    public let set: FiledSet
    public let examSet: FiledSet?
    /// Nil for copied questions, which she checked herself.
    public let blindCheck: BlindCheck?
    public let examBlindCheck: BlindCheck?
    /// Copied questions she kept whose answer QBank suggested.
    public let suggestedAnswers: [String]
    public let warnings: [String]

    public init(set: FiledSet, examSet: FiledSet?, blindCheck: BlindCheck?, examBlindCheck: BlindCheck?, suggestedAnswers: [String], warnings: [String]) {
        self.set = set
        self.examSet = examSet
        self.blindCheck = blindCheck
        self.examBlindCheck = examBlindCheck
        self.suggestedAnswers = suggestedAnswers
        self.warnings = warnings
    }
}

extension Question {
    /// A question not in QBank yet, as the server sends a sample or a copy: its id in the set file
    /// stands for both ids, and its place in the list for its position.
    init(draft: JSONValue, position: Int) throws {
        guard case .object(var object) = draft, let id = object["id"] else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "A draft question is not an object with an id"))
        }
        object["publicId"] = id
        object["position"] = .number(Double(position))
        self = try JSONValue.object(object).decode(Question.self)
    }
}

// MARK: Request bodies

struct NewQuestionJobBody: Encodable {
    let job: NewQuestionJob

    private enum CodingKeys: String, CodingKey {
        case courseId, folderId, folderName, materialKind, material, level, referenceSetId, count, examTwins, title
    }

    private struct Material: Encodable {
        struct Image: Encodable {
            let mediaType: String
            let data: String
        }

        struct File: Encodable {
            let name: String
            let mediaType: String
            let data: String
        }

        let text: String?
        let images: [Image]?
        let file: File?
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(job.courseID, forKey: .courseId)
        try container.encodeIfPresent(job.folderID, forKey: .folderId)
        try container.encodeIfPresent(job.folderName, forKey: .folderName)
        try container.encode(job.materialKind, forKey: .materialKind)
        try container.encode(
            Material(
                text: job.text,
                images: job.images.isEmpty ? nil : job.images.map { Material.Image(mediaType: $0.mediaType, data: $0.data.base64EncodedString()) },
                file: job.file.map { Material.File(name: $0.name, mediaType: $0.mediaType, data: $0.data.base64EncodedString()) }
            ),
            forKey: .material
        )
        try container.encodeIfPresent(job.level, forKey: .level)
        try container.encodeIfPresent(job.referenceSetID, forKey: .referenceSetId)
        try container.encodeIfPresent(job.count, forKey: .count)
        try container.encode(job.examTwins, forKey: .examTwins)
        try container.encodeIfPresent(job.title, forKey: .title)
    }
}

struct AcceptSamplesBody: Encodable {
    let words: String?
}

struct ReviseSamplesBody: Encodable {
    struct Change: Encodable {
        let questionId: String
        let note: String
    }

    let changes: [Change]?
    let note: String?

    init(changes: [SampleChange], note: String?) {
        self.changes = changes.isEmpty ? nil : changes.map { Change(questionId: $0.questionID, note: $0.note) }
        self.note = note
    }
}

struct AcceptCopiesBody: Encodable {
    struct Keep: Encodable {
        let id: String
        let question: JSONValue?
    }

    let keep: [Keep]

    init(_ kept: [KeptCopy]) {
        keep = kept.map { Keep(id: $0.id, question: $0.question) }
    }
}

struct QuestionJobList: Decodable {
    let jobs: [QuestionJob]
}
