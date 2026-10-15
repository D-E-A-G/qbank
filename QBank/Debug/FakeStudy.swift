#if DEBUG
import Foundation
import QBankKit
import Synchronization

/// The fake server's study side: her folders and exam pages, Review, Terms and exams, with the
/// real server's rules and words (`apps/api/src/progress`, `exams`, `content/service.ts`). Every
/// question is one of `FakePracticeQuestions`' invented ones, scored with QBankKit's port of the
/// server's scoring. Nothing here comes from a real course.
nonisolated final class FakeStudy: Sendable {
    typealias Reply = (Int, [String: Any])

    /// A folder of sets, on one exam page or none, in her order within its list.
    struct Folder {
        let id: String
        let courseID: String
        var name: String
        var examPageID: String?
        var sortOrder: Int
        /// Its sets, by the id of the version that is current.
        var sets: [String]
        /// Its exam-bank questions, asked only on exams.
        var bank: [String]
    }

    /// An exam page.
    struct CourseExam {
        let id: String
        let courseID: String
        var name: String
        let sortOrder: Int
    }

    struct Answer {
        let clientAttemptID: String
        let status: ScoreStatus
        let points: Int
        let maxPoints: Int
        let guessed: Bool
        let response: AnswerResponse
        let shuffle: Layout?
    }

    struct Exam {
        let id: String
        let courseID: String
        let folderIDs: [String]
        /// Its folders' names when it started.
        let names: [String]
        let pool: ExamPool
        let practiceWeeks: [String]?
        /// The questions in the order served, each with its folder and that folder's name then.
        let questions: [(id: String, folder: String, name: String)]
        let timeLimitSeconds: Int
        let startedAt: Date
        var finishedAt: Date?
        var endReason: ExamEndReason?
        var answers: [String: Answer] = [:]

        var endsAt: Date { startedAt.addingTimeInterval(TimeInterval(timeLimitSeconds)) }
    }

    /// A question in her Review list, from a practice answer.
    struct ReviewEntry {
        let questionID: String
        let weekLabel: String
        let setTitle: String
        var status: ScoreStatus
        var guessed: Bool
        var answeredAt: Date
    }

    struct State {
        var folders: [Folder]
        var courseExams: [CourseExam]
        var exams: [Exam] = []
        var review: [String: [ReviewEntry]]
        /// Her latest mark on each question she answered in this run, practice or exam.
        var latest: [String: ScoreStatus] = [:]
        var examCount = 0
        var courseExamCount = 0
        var folderCount = 0
    }

    static let week1 = "f0000000-0000-4000-8000-000000003101"
    static let week2 = "f0000000-0000-4000-8000-000000003102"
    static let week3 = "f0000000-0000-4000-8000-000000003103"
    static let weeks1to3 = "f0000000-0000-4000-8000-000000003104"
    static let exam1 = "c0e00000-0000-4000-8000-000000000001"
    static let exam2 = "c0e00000-0000-4000-8000-000000000002"

    /// How many questions each set has, by set id.
    static let setSizes: [String: Int] = [
        "rights-v1": 17, "communication-v1": 14, "psychosocial-v1": 12, "psychosocial-v2": 12, "depression-v1": 18,
        "anxiety-v1": 13, "mixed-v1": 8, "vitals-v1": 43, "safety-v1": 42, "mobility-v1": 61,
    ]

    /// The questions she had last answered not fully right before this run of the app.
    static let wrongAtStart = Set(
        ids("bank1", 4) + ids("communication-v1", 5) + ids("psychosocial-v2", 2) + ids("mixed-v1", 2)
            + ids("vitals-v1", 6) + ids("safety-v1", 9) + ids("mobility-v1", 2)
    )

    /// The courses' codes, for the refusals that name a course.
    static let codes = [FakeQBankServer.mentalHealthID: "NURS 310", FakeQBankServer.fundamentalsID: "NURS 220"]

    /// Invented terms: plain nursing words with plain meanings, written for this fake.
    static let terms: [(term: String, meaning: String, week: String, set: String)] = [
        ("Advocacy", "Speaking up for what the client needs and wants.", "Week 1", "Rights, Law, and Ethics"),
        ("Affect", "The feeling a person shows on the face and in the voice.", "Week 2", "Psychosocial Assessment and Safety Screening"),
        ("Autonomy", "The client's right to make informed choices about their own care.", "Week 1", "Rights, Law, and Ethics"),
        ("Beneficence", "The duty to do good for the client.", "Week 1", "Rights, Law, and Ethics"),
        ("Boundaries", "The limits that keep the nurse-client relationship about the client.", "Week 2", "Therapeutic Communication and the Relationship"),
        ("Clarifying", "Asking the client to say more so the nurse understands.", "Week 2", "Therapeutic Communication and the Relationship"),
        ("Competence", "Being able to understand a choice and its results.", "Week 1", "Rights, Law, and Ethics"),
        ("Least restrictive", "The step that limits the client's freedom the least.", "Week 1", "Rights, Law, and Ethics"),
        ("Rapport", "Trust and ease between the nurse and the client.", "Week 2", "Therapeutic Communication and the Relationship"),
        ("Restatement", "Repeating the client's main idea back in the nurse's words.", "Week 2", "Therapeutic Communication and the Relationship"),
        ("Serotonin", "A brain chemical linked to mood that many antidepressants act on.", "Week 3", "Depression and Antidepressants"),
        ("Veracity", "The duty to tell the truth.", "Week 1", "Rights, Law, and Ethics"),
    ]

    private let state: Mutex<State>
    private let now: Date

    init(now: Date) {
        self.now = now
        let day: TimeInterval = 86_400
        let mentalHealth = FakeQBankServer.mentalHealthID, fundamentals = FakeQBankServer.fundamentalsID
        state = Mutex(State(
            folders: [
                Folder(id: Self.week1, courseID: mentalHealth, name: "Week 1", examPageID: Self.exam1, sortOrder: 1, sets: ["rights-v1"], bank: Self.ids("bank1", 17)),
                Folder(id: Self.week2, courseID: mentalHealth, name: "Week 2", examPageID: Self.exam1, sortOrder: 2, sets: ["communication-v1", "psychosocial-v2"], bank: []),
                Folder(id: Self.week3, courseID: mentalHealth, name: "Week 3", examPageID: Self.exam2, sortOrder: 1, sets: ["depression-v1", "anxiety-v1"], bank: Self.ids("bank3", 31)),
                Folder(id: Self.weeks1to3, courseID: mentalHealth, name: "Weeks 1-3", examPageID: nil, sortOrder: 1, sets: ["mixed-v1"], bank: []),
                Folder(id: "f0000000-0000-4000-8000-000000002201", courseID: fundamentals, name: "Week 1", examPageID: nil, sortOrder: 1, sets: ["vitals-v1"], bank: []),
                Folder(id: "f0000000-0000-4000-8000-000000002202", courseID: fundamentals, name: "Week 2", examPageID: nil, sortOrder: 2, sets: ["safety-v1"], bank: []),
                Folder(id: "f0000000-0000-4000-8000-000000002203", courseID: fundamentals, name: "Week 3", examPageID: nil, sortOrder: 3, sets: ["mobility-v1"], bank: []),
            ],
            courseExams: [
                CourseExam(id: Self.exam1, courseID: mentalHealth, name: "Exam 1", sortOrder: 1),
                CourseExam(id: Self.exam2, courseID: mentalHealth, name: "Exam 2", sortOrder: 2),
            ],
            review: [
                FakeQBankServer.mentalHealthID: [
                    ReviewEntry(questionID: "rights-v1-q4", weekLabel: "Week 1", setTitle: "Rights, Law, and Ethics", status: .partial, guessed: false, answeredAt: now.addingTimeInterval(-9 * day - 60)),
                    ReviewEntry(questionID: "rights-v1-q2", weekLabel: "Week 1", setTitle: "Rights, Law, and Ethics", status: .partial, guessed: false, answeredAt: now.addingTimeInterval(-9 * day - 120)),
                    ReviewEntry(questionID: "rights-v1-q5", weekLabel: "Week 1", setTitle: "Rights, Law, and Ethics", status: .correct, guessed: true, answeredAt: now.addingTimeInterval(-9 * day - 180)),
                    ReviewEntry(questionID: "communication-v1-q6", weekLabel: "Week 2", setTitle: "Therapeutic Communication and the Relationship", status: .incorrect, guessed: true, answeredAt: now.addingTimeInterval(-3 * day - 240)),
                    ReviewEntry(questionID: "rights-v1-q7", weekLabel: "Week 1", setTitle: "Rights, Law, and Ethics", status: .incorrect, guessed: false, answeredAt: now.addingTimeInterval(-9 * day - 300)),
                    ReviewEntry(questionID: "rights-v1-q0", weekLabel: "Week 1", setTitle: "Rights, Law, and Ethics", status: .incorrect, guessed: false, answeredAt: now.addingTimeInterval(-10 * day - 360)),
                    ReviewEntry(questionID: "communication-v1-q1", weekLabel: "Week 2", setTitle: "Therapeutic Communication and the Relationship", status: .incorrect, guessed: false, answeredAt: now.addingTimeInterval(-3 * day - 420)),
                    ReviewEntry(questionID: "communication-v1-q3", weekLabel: "Week 2", setTitle: "Therapeutic Communication and the Relationship", status: .partial, guessed: false, answeredAt: now.addingTimeInterval(-3 * day - 480)),
                    ReviewEntry(questionID: "communication-v1-q8", weekLabel: "Week 2", setTitle: "Therapeutic Communication and the Relationship", status: .correct, guessed: true, answeredAt: now.addingTimeInterval(-4 * day - 540)),
                    ReviewEntry(questionID: "rights-v1-q9", weekLabel: "Week 1", setTitle: "Rights, Law, and Ethics", status: .incorrect, guessed: false, answeredAt: now.addingTimeInterval(-11 * day - 600)),
                    ReviewEntry(questionID: "rights-v1-q11", weekLabel: "Week 1", setTitle: "Rights, Law, and Ethics", status: .correct, guessed: true, answeredAt: now.addingTimeInterval(-11 * day - 660)),
                    ReviewEntry(questionID: "communication-v1-q9", weekLabel: "Week 2", setTitle: "Therapeutic Communication and the Relationship", status: .incorrect, guessed: false, answeredAt: now.addingTimeInterval(-5 * day - 720)),
                ].sorted { $0.answeredAt > $1.answeredAt },
            ]
        ))
        seedPastExams()
    }

    /// Her exams before this run: Weeks 1-2 three days ago (Exam 1), Week 1 when time ran out
    /// ten days ago (Exam 1), and Weeks 1-3 across both exam pages a week ago (on neither).
    private func seedPastExams() {
        let day: TimeInterval = 86_400
        let pasts: [(folders: [String], startedDaysAgo: Double, minutes: Double, reason: ExamEndReason, pattern: (Int) -> String?)] = [
            ([Self.week1, Self.week2], 3, 52, .finished, { $0 % 5 == 4 ? "wrong" : "right" }),
            ([Self.week1], 10, 26, .timeout, { $0 >= 15 ? nil : ($0 % 7 == 6 ? "wrong" : "right") }),
            ([Self.week1, Self.week2, Self.week3], 7, 41, .finished, { $0 % 4 == 3 ? "partly" : "right" }),
        ]
        for past in pasts {
            let startedAt = now.addingTimeInterval(-past.startedDaysAgo * day)
            guard case .success(let id) = begin(
                courseID: FakeQBankServer.mentalHealthID, folderIDs: past.folders, pool: .all, at: startedAt, endingRunning: false
            ) else { continue }
            state.withLock { state in
                guard let index = state.exams.firstIndex(where: { $0.id == id }) else { return }
                var exam = state.exams[index]
                for (position, question) in exam.questions.enumerated() {
                    guard let kind = past.pattern(position), let body = Self.question(question.id)?.body,
                          let response = kind == "right" ? FakeAnswers.right(body) : kind == "wrong" ? FakeAnswers.wrong(body) : FakeAnswers.partly(body),
                          let score = try? Scoring.score(body, response: response) else { continue }
                    exam.answers[question.id] = Answer(
                        clientAttemptID: "seed-\(id)-\(position)", status: score.status, points: score.points, maxPoints: score.maxPoints,
                        guessed: position == 2, response: response, shuffle: nil
                    )
                }
                let finishedAt = past.reason == .timeout ? exam.endsAt : startedAt.addingTimeInterval(past.minutes * 60)
                exam.finishedAt = min(finishedAt, exam.endsAt)
                exam.endReason = past.reason
                state.exams[index] = exam
            }
        }
    }

    // MARK: Routes

    /// Answers the study and folder routes; nil for any other route. A folder in a reply is drawn
    /// by `folderJSON`, which knows its sets.
    func answer(method: String, path: String, query: [String: String], body: [String: Any], folderJSON: (Folder) -> [String: Any]) -> Reply? {
        let parts = path.split(separator: "/").map(String.init)
        // /api/courses/{id}/...
        if parts.count >= 4, parts[0] == "api", parts[1] == "courses" {
            let courseID = parts[2]
            guard knows(courseID) else { return nil }
            switch (method, parts.dropFirst(3).joined(separator: "/")) {
            case ("GET", "terms"): return (200, ["terms": termsJSON(courseID)])
            case ("GET", "review"): return review(courseID, filter: query["filter"] ?? "all")
            case ("GET", "review/practice"): return reviewPractice(courseID, filter: query["filter"] ?? "all", questionID: query["question"])
            case ("POST", "review/clear"): return clearReview(courseID, confirmed: body["confirmed"] as? Bool ?? false)
            case ("GET", "exams"): return (200, setup(courseID))
            case ("POST", "exams"): return start(courseID, body: body)
            case ("POST", "course-exams"): return saveCourseExam(courseID: courseID, id: nil, body: body)
            case ("POST", "folders"): return Self.reply(createFolder(courseID: courseID, body: body), status: 201, folderJSON)
            case ("PUT", "folder-order"): return reorder(courseID: courseID, body: body, folderJSON)
            default: return nil
            }
        }
        if parts.count == 3, parts[0] == "api", parts[1] == "course-exams" {
            switch method {
            case "PUT": return saveCourseExam(courseID: nil, id: parts[2], body: body)
            case "DELETE": return deleteCourseExam(id: parts[2])
            default: return nil
            }
        }
        if parts.count == 3, parts[0] == "api", parts[1] == "folders", method == "PATCH" {
            return Self.reply(changeFolder(id: parts[2], body: body), status: 200, folderJSON)
        }
        if parts.count == 4, parts[0] == "api", parts[1] == "practice-sets", parts[3] == "move", method == "POST" {
            return Self.reply(moveSet(id: parts[2], body: body), status: 200, folderJSON)
        }
        if parts.count >= 3, parts[0] == "api", parts[1] == "exams" {
            if parts.count == 3, method == "GET" { return examView(parts[2]) }
            if parts.count == 4, parts[3] == "finish", method == "POST" {
                let reason = (body["reason"] as? String).flatMap(ExamEndReason.init(rawValue:)) ?? .finished
                return finish(parts[2], reason: reason)
            }
        }
        return nil
    }

    /// One of the two studied courses, or a course an import made folders in.
    func knows(_ courseID: String) -> Bool {
        Self.codes[courseID] != nil || state.withLock { state in state.folders.contains { $0.courseID == courseID } }
    }

    /// A course's folders in its page's order: each exam page's, then those on no page.
    func folders(_ courseID: String) -> [Folder] {
        state.withLock { state in Self.ordered(state, courseID: courseID) }
    }

    /// The course's exam pages for `GET /api/courses/{id}`.
    func courseExamsJSON(_ courseID: String) -> [[String: Any]] {
        state.withLock { state in
            state.courseExams.filter { $0.courseID == courseID }.map { Self.pageJSON($0, in: state) }
        }
    }

    /// The version that is current now takes the place of the one she restored from.
    func replace(set old: String, with new: String) {
        state.withLock { state in
            for index in state.folders.indices {
                state.folders[index].sets = state.folders[index].sets.map { $0 == old ? new : $0 }
            }
        }
    }

    private static func ordered(_ state: State, courseID: String) -> [Folder] {
        let pages = state.courseExams.filter { $0.courseID == courseID }.sorted { $0.sortOrder < $1.sortOrder }
        let folders = state.folders.filter { $0.courseID == courseID }.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
        return pages.flatMap { page in folders.filter { $0.examPageID == page.id } } + folders.filter { $0.examPageID == nil }
    }

    private static func pageJSON(_ page: CourseExam, in state: State) -> [String: Any] {
        let folders = ordered(state, courseID: page.courseID).filter { $0.examPageID == page.id }
        return [
            "id": page.id, "name": page.name, "sortOrder": page.sortOrder,
            "weekLabels": folders.map(\.name), "folderIds": folders.map(\.id),
        ]
    }

    func reviewCount(_ courseID: String) -> Int {
        state.withLock { $0.review[courseID]?.count ?? 0 }
    }

    func termCount(_ courseID: String) -> Int {
        courseID == FakeQBankServer.mentalHealthID ? Self.terms.count : 0
    }

    // MARK: Terms

    /// The set each term's set title names, by the start of its id.
    private static let termSets = [
        "Rights, Law, and Ethics": "rights", "Psychosocial Assessment and Safety Screening": "psychosocial",
        "Therapeutic Communication and the Relationship": "communication", "Depression and Antidepressants": "depression",
    ]

    private func termsJSON(_ courseID: String) -> [[String: Any]] {
        guard courseID == FakeQBankServer.mentalHealthID else { return [] }
        let folders = self.folders(courseID)
        return Self.terms.map { term in
            // A term belongs to its set's folder now, wherever she moved the set.
            let prefix = Self.termSets[term.set].map { "\($0)-v" } ?? "-"
            let folder = folders.first { $0.sets.contains { $0.hasPrefix(prefix) } }
            return [
                "key": term.term.lowercased(), "term": term.term, "meaning": term.meaning,
                "weekLabel": folder?.name ?? term.week, "folderId": folder?.id ?? "", "folderName": folder?.name ?? term.week,
                "setTitle": term.set,
            ]
        }
    }

    // MARK: Review

    private func review(_ courseID: String, filter: String) -> Reply {
        let (entries, folders) = state.withLock { ($0.review[courseID] ?? [], Self.ordered($0, courseID: courseID)) }
        let counts: [String: Any] = [
            "all": entries.count,
            "missed": entries.count { $0.status == .incorrect },
            "partial": entries.count { $0.status == .partial },
            "guessed": entries.count(where: \.guessed),
        ]
        let shown = entries.filter { Self.matches($0, filter) }
        return (200, ["filter": filter, "counts": counts, "questions": shown.map { reviewJSON($0, folders: folders) }])
    }

    private static func matches(_ entry: ReviewEntry, _ filter: String) -> Bool {
        switch filter {
        case "missed": entry.status == .incorrect
        case "partial": entry.status == .partial
        case "guessed": entry.guessed
        default: true
        }
    }

    private func reviewJSON(_ entry: ReviewEntry, folders: [Folder]) -> [String: Any] {
        let template = FakePracticeQuestions.template(forQuestionID: entry.questionID) ?? [:]
        let type = (template["type"] as? String).flatMap(QuestionType.init(rawValue:))
        let folder = Self.folder(of: entry.questionID, in: folders)
        return [
            "questionId": entry.questionID, "topic": template["topic"] as? String ?? "",
            "weekLabel": entry.weekLabel, "folderId": folder?.id ?? "", "folderName": folder?.name ?? entry.weekLabel,
            "format": Self.formatName(type),
            "status": entry.status.rawValue, "guessed": entry.guessed,
            "answeredAt": QBankJSON.formatDate(entry.answeredAt), "setTitle": entry.setTitle,
        ]
    }

    /// The folder a question's set is in now. Question ids are "<set id>-q<index>".
    static func folder(of questionID: String, in folders: [Folder]) -> Folder? {
        let setID = questionID.split(separator: "-").dropLast().joined(separator: "-")
        return folders.first { $0.sets.contains(setID) || $0.bank.contains(questionID) }
    }

    /// The server's format names on Review rows (`QUESTION_TYPE_LABELS`).
    private static func formatName(_ type: QuestionType?) -> String {
        switch type {
        case .single: "Single answer"
        case .priority: "Priority / first action"
        case .sata: "Select all that apply"
        case .highlight: "Highlight"
        case .order: "Ordered response"
        case .match: "Matching"
        case .matrix: "Matrix"
        case .cloze: "Drop-down cloze"
        case nil: "Question"
        }
    }

    private func reviewPractice(_ courseID: String, filter: String, questionID: String?) -> Reply {
        let entries = state.withLock { $0.review[courseID] ?? [] }
        let ids: [String]
        if let questionID {
            guard FakePracticeQuestions.template(forQuestionID: questionID) != nil else {
                return Self.failure(404, "question_not_found", "That question is not in this course.")
            }
            ids = [questionID]
        } else {
            // The server shuffles; the fake keeps the list's order so a test knows what comes next.
            ids = entries.filter { Self.matches($0, filter) }.map(\.questionID)
        }
        let questions = ids.enumerated().map { position, id in
            Self.questionJSON(id, position: position + 1, week: entries.first { $0.questionID == id }?.weekLabel ?? "")
        }
        return (200, [
            "id": courseID, "courseId": courseID, "title": questionID == nil ? "Review" : "Review question",
            "weekLabel": "", "folderId": NSNull(), "kind": "practice", "questions": questions,
        ])
    }

    private func clearReview(_ courseID: String, confirmed: Bool) -> Reply {
        let count = state.withLock { $0.review[courseID]?.count ?? 0 }
        guard confirmed else {
            return Self.failure(400, "confirmation_required", "Clear all \(Wording.count(count, "question")) from this course's Review list?")
        }
        state.withLock { $0.review[courseID] = [] }
        return (200, ["cleared": count])
    }

    /// A practice answer from the runner: it joins or leaves Review, and marks the question for
    /// Wrong questions only.
    func practiced(questionID: String, courseID: String, score: Score, guessed: Bool, at: Date, weekLabel: String, setTitle: String) {
        state.withLock { state in
            state.latest[questionID] = score.status
            var entries = state.review[courseID] ?? []
            entries.removeAll { $0.questionID == questionID }
            if score.staysInReview(guessed: guessed) {
                entries.insert(ReviewEntry(questionID: questionID, weekLabel: weekLabel, setTitle: setTitle, status: score.status, guessed: guessed, answeredAt: at), at: 0)
            }
            state.review[courseID] = entries
        }
    }

    // MARK: Exam setup and start

    /// What an exam over a folder draws from: its exam bank, or its sets' practice questions.
    private static func pool(_ folder: Folder) -> [String] {
        folder.bank.isEmpty ? folder.sets.flatMap { ids($0, setSizes[$0] ?? 0) } : folder.bank
    }

    private static func wrongPool(_ folder: Folder, latest: [String: ScoreStatus]) -> [String] {
        pool(folder).filter { id in latest[id].map { $0 != .correct } ?? wrongAtStart.contains(id) }
    }

    private func setup(_ courseID: String) -> [String: Any] {
        settleExpired()
        return state.withLock { state in
            let folders = Self.ordered(state, courseID: courseID).filter { !Self.pool($0).isEmpty }
            let exams = state.exams.filter { $0.courseID == courseID }.sorted { $0.startedAt > $1.startedAt }
            let summaries = exams.map { summaryJSON($0, in: state) }
            let pools = folders.map { folder -> [String: Any] in
                [
                    "id": folder.id, "name": folder.name, "examPageId": Self.json(folder.examPageID),
                    "questionCount": Self.pool(folder).count, "wrongCount": Self.wrongPool(folder, latest: state.latest).count,
                    "source": folder.bank.isEmpty ? "practice" : "exam",
                ]
            }
            // An app from before folders reads the same pools by name.
            var weeks: [[String: Any]] = []
            for folder in folders where !weeks.contains(where: { $0["label"] as? String == folder.name }) {
                let same = folders.filter { $0.name == folder.name }
                weeks.append([
                    "label": folder.name, "questionCount": same.reduce(0) { $0 + Self.pool($1).count },
                    "wrongCount": same.reduce(0) { $0 + Self.wrongPool($1, latest: state.latest).count },
                    "source": same.contains { !$0.bank.isEmpty } ? "exam" : "practice",
                ])
            }
            return [
                "courseId": courseID, "weeks": weeks, "folders": pools,
                "inProgress": exams.firstIndex { $0.finishedAt == nil }.map { summaries[$0] } ?? NSNull(),
                "exams": exams.indices.filter { exams[$0].finishedAt != nil }.map { summaries[$0] },
            ]
        }
    }

    /// The exam page holding every folder an exam covered, as the server's `courseExamOf` rules.
    private static func page(of exam: Exam, in state: State) -> String? {
        state.courseExams.filter { $0.courseID == exam.courseID }.sorted { $0.sortOrder < $1.sortOrder }.first { page in
            exam.folderIDs.allSatisfy { id in state.folders.contains { $0.id == id && $0.examPageID == page.id } }
        }?.id
    }

    private func summaryJSON(_ exam: Exam, in state: State) -> [String: Any] {
        let result = exam.finishedAt == nil ? nil : score(exam, in: state)
        return [
            "id": exam.id, "courseId": exam.courseID, "weeks": exam.names, "folderIds": exam.folderIDs,
            "courseExamId": Self.json(Self.page(of: exam, in: state)),
            "pool": exam.pool.rawValue, "practiceWeeks": exam.practiceWeeks.map { $0 as Any } ?? NSNull(),
            "questionCount": exam.questions.count, "timeLimitSeconds": exam.timeLimitSeconds,
            "startedAt": QBankJSON.formatDate(exam.startedAt), "endsAt": QBankJSON.formatDate(exam.endsAt),
            "finishedAt": Self.json(exam.finishedAt.map(QBankJSON.formatDate)), "endReason": Self.json(exam.endReason?.rawValue),
            "answeredCount": exam.answers.count,
            "fullyRight": result.map { $0["fullyRight"] as Any } ?? NSNull(),
            "points": result.map { $0["points"] as Any } ?? NSNull(),
            "maxPoints": result.map { $0["maxPoints"] as Any } ?? NSNull(),
            "minutesUsed": result.map { $0["minutesUsed"] as Any } ?? NSNull(),
        ]
    }

    private func start(_ courseID: String, body: [String: Any]) -> Reply {
        let folderIDs = body["folderIds"] as? [String] ?? []
        let pool = (body["pool"] as? String).flatMap(ExamPool.init(rawValue:)) ?? .all
        switch begin(courseID: courseID, folderIDs: folderIDs, pool: pool, at: .now, endingRunning: true) {
        case .success(let id): return examView(id, status: 201)
        case .failure(let refusal): return Self.failure(400, refusal.code, refusal.message)
        }
    }

    struct Refusal: Error {
        let code: String
        let message: String
    }

    /// Draws an exam as the server does, folder by folder in her order and without shuffling, so a
    /// test knows which question comes when.
    private func begin(courseID: String, folderIDs: [String], pool: ExamPool, at startedAt: Date, endingRunning: Bool) -> Result<String, Refusal> {
        let (course, latest) = state.withLock { (Self.ordered($0, courseID: courseID), $0.latest) }
        guard !folderIDs.isEmpty else { return .failure(Refusal(code: "no_folders", message: "Tick at least one folder.")) }
        if folderIDs.contains(where: { id in !course.contains { $0.id == id } }) {
            return .failure(Refusal(code: "folder_not_found", message: "That folder is not in this course."))
        }
        let ticked = course.filter { folderIDs.contains($0.id) }
        let draw = { (folder: Folder) -> [String] in pool == .wrong ? Self.wrongPool(folder, latest: latest) : Self.pool(folder) }
        let empty = ticked.filter { draw($0).isEmpty }.map(\.name)
        if !empty.isEmpty {
            let one = empty.count == 1
            return .failure(Refusal(
                code: pool == .wrong ? "no_wrong_questions" : "no_questions",
                message: pool == .wrong
                    ? "\(Self.listText(empty)) \(one ? "has" : "have") no wrong questions. Untick \(one ? "it" : "them"), or turn off Wrong questions only."
                    : "\(Self.listText(empty)) \(one ? "has" : "have") no questions."
            ))
        }
        let plan = ExamPlan(ticked.map { ExamPlan.Pool(id: $0.id, name: $0.name, questionCount: draw($0).count) })
        let questions = zip(ticked, plan.draws).flatMap { folder, row in
            draw(folder).prefix(row.drawn).map { (id: $0, folder: folder.id, name: folder.name) }
        }
        let practiceWeeks = course.contains { !$0.bank.isEmpty } ? ticked.filter(\.bank.isEmpty).map(\.name) : nil
        // A running exam of hers ends first, as if she had left it.
        if endingRunning {
            for exam in state.withLock({ $0.exams.filter { $0.finishedAt == nil } }) {
                close(exam.id, reason: .left)
            }
        }
        return state.withLock { state in
            state.examCount += 1
            let id = String(format: "e0000000-0000-4000-8000-%012d", state.examCount)
            state.exams.append(Exam(
                id: id, courseID: courseID, folderIDs: ticked.map(\.id), names: ticked.map(\.name), pool: pool,
                practiceWeeks: practiceWeeks, questions: questions, timeLimitSeconds: plan.timeLimitSeconds, startedAt: startedAt
            ))
            return .success(id)
        }
    }

    // MARK: One exam

    private func examView(_ id: String, status: Int = 200) -> Reply {
        settleExpired()
        guard let exam = state.withLock({ $0.exams.first { $0.id == id } }) else {
            return Self.failure(404, "exam_not_found", "That exam is not in the app.")
        }
        let course = exam.courseID == FakeQBankServer.mentalHealthID ? ("NURS 310", "Mental Health") : ("NURS 220", "Fundamentals")
        let result = exam.finishedAt == nil ? nil : state.withLock { score(exam, in: $0) }
        return (status, [
            "id": exam.id, "courseId": exam.courseID, "courseCode": course.0, "courseTitle": course.1,
            "weeks": exam.names, "folderIds": exam.folderIDs,
            "pool": exam.pool.rawValue, "practiceWeeks": exam.practiceWeeks.map { $0 as Any } ?? NSNull(),
            "timeLimitSeconds": exam.timeLimitSeconds, "startedAt": QBankJSON.formatDate(exam.startedAt),
            "endsAt": QBankJSON.formatDate(exam.endsAt), "finishedAt": Self.json(exam.finishedAt.map(QBankJSON.formatDate)),
            "endReason": Self.json(exam.endReason?.rawValue), "serverNow": QBankJSON.formatDate(.now),
            "questions": exam.questions.enumerated().map { Self.questionJSON($1.id, position: $0 + 1, week: $1.name) },
            "answeredQuestionIds": exam.questions.map(\.id).filter { exam.answers[$0] != nil },
            "result": result.map { $0 as Any } ?? NSNull(),
        ])
    }

    private func finish(_ id: String, reason: ExamEndReason) -> Reply {
        guard state.withLock({ $0.exams.contains { $0.id == id } }) else {
            return Self.failure(404, "exam_not_found", "That exam is not in the app.")
        }
        close(id, reason: reason)
        return examView(id)
    }

    /// Ends the running exam. After its time is up, the end is a timeout at the moment time ran out.
    private func close(_ id: String, reason: ExamEndReason) {
        state.withLock { state in
            guard let index = state.exams.firstIndex(where: { $0.id == id }), state.exams[index].finishedAt == nil else { return }
            let deadline = state.exams[index].endsAt
            let timedOut = Date.now >= deadline
            state.exams[index].finishedAt = timedOut ? deadline : .now
            state.exams[index].endReason = timedOut ? .timeout : reason
        }
    }

    private func settleExpired() {
        let expired = state.withLock { state in state.exams.filter { $0.finishedAt == nil && Date.now >= $0.endsAt }.map(\.id) }
        for id in expired { close(id, reason: .timeout) }
    }

    /// An answer on a running exam. Nil when the submission is not for an exam.
    func examAnswer(sessionID: String, clientAttemptID: String, questionID: String, response: AnswerResponse, guessed: Bool, shuffle: Layout?) -> Reply {
        settleExpired()
        return state.withLock { state -> Reply in
            guard let index = state.exams.firstIndex(where: { $0.id == sessionID }) else {
                return Self.failure(404, "exam_not_found", "That exam is not in the app.")
            }
            let exam = state.exams[index]
            guard exam.finishedAt == nil else {
                return Self.failure(409, "exam_finished", "This exam has ended. That answer was not saved.")
            }
            guard let served = exam.questions.first(where: { $0.id == questionID }), let question = Self.question(questionID) else {
                return Self.failure(400, "question_not_in_exam", "That question is not on this exam.")
            }
            guard exam.answers[questionID] == nil else {
                return Self.failure(409, "already_answered", "That question was already answered on this exam.")
            }
            let score: Score
            switch Result(catching: { () throws(ScoringError) -> Score in try Scoring.score(question.body, response: response) }) {
            case .success(let scored): score = scored
            case .failure(let error): return Self.failure(400, "invalid_request", error.message)
            }
            state.exams[index].answers[questionID] = Answer(
                clientAttemptID: clientAttemptID, status: score.status, points: score.points, maxPoints: score.maxPoints,
                guessed: guessed, response: response, shuffle: shuffle
            )
            state.latest[questionID] = score.status
            let bank = Self.isBank(questionID)
            var inReview = false
            if !bank, var entries = state.review[exam.courseID] {
                entries.removeAll { $0.questionID == questionID }
                inReview = score.staysInReview(guessed: guessed)
                if inReview {
                    entries.insert(ReviewEntry(questionID: questionID, weekLabel: served.name, setTitle: "Exam", status: score.status, guessed: guessed, answeredAt: .now), at: 0)
                }
                state.review[exam.courseID] = entries
            }
            return (201, [
                "clientAttemptId": clientAttemptID, "questionId": questionID, "courseId": exam.courseID,
                "status": score.status.rawValue, "points": score.points, "maxPoints": score.maxPoints,
                "guessed": guessed, "answeredAt": QBankJSON.formatDate(.now), "inReview": inReview,
                "label": score.label, "replayed": false,
            ])
        }
    }

    private static let stepOrder = ["Recognize cues", "Analyze cues", "Prioritize hypotheses", "Generate solutions", "Take action", "Take actions", "Evaluate outcomes"]

    /// The result of an ended exam, counted as the server counts it: by folder under each folder's
    /// name now, and by the names its folders had, for an app from before folders.
    private func score(_ exam: Exam, in state: State) -> [String: Any] {
        var items: [[String: Any]] = []
        var weeks = exam.names.map { (label: $0, right: 0, total: 0) }
        var folders = exam.folderIDs.map { id in
            (id: id, label: state.folders.first { $0.id == id }?.name ?? exam.names[exam.folderIDs.firstIndex(of: id) ?? 0], right: 0, total: 0)
        }
        var steps: [(label: String, right: Int, total: Int)] = []
        var counts = (fullyRight: 0, partial: 0, missed: 0, guessed: 0, answered: 0, points: 0, maxPoints: 0, review: 0, bankWrong: 0)
        for served in exam.questions {
            let answer = exam.answers[served.id]
            let question = Self.question(served.id)
            let maxPoints = answer?.maxPoints ?? question.flatMap(Self.maxPoints) ?? 1
            let right = answer?.status == .correct
            if let answer {
                counts.answered += 1
                counts.points += answer.points
                if answer.guessed { counts.guessed += 1 }
                switch answer.status {
                case .correct: counts.fullyRight += 1
                case .partial: counts.partial += 1
                case .incorrect: counts.missed += 1
                }
                let mark = Score(points: answer.points, maxPoints: answer.maxPoints, status: answer.status, answered: true)
                if Self.isBank(served.id) {
                    if !right { counts.bankWrong += 1 }
                } else if mark.staysInReview(guessed: answer.guessed) {
                    counts.review += 1
                }
            }
            counts.maxPoints += maxPoints
            if let index = weeks.firstIndex(where: { $0.label == served.name }) {
                weeks[index].total += 1
                if right { weeks[index].right += 1 }
            }
            if let index = folders.firstIndex(where: { $0.id == served.folder }) {
                folders[index].total += 1
                if right { folders[index].right += 1 }
            }
            let step = question?.clinicalJudgmentStep.flatMap { $0.isEmpty ? nil : $0 } ?? "Not labeled"
            if let index = steps.firstIndex(where: { $0.label == step }) {
                steps[index].total += 1
                if right { steps[index].right += 1 }
            } else {
                steps.append((step, right ? 1 : 0, 1))
            }
            var item: [String: Any] = [
                "questionId": served.id, "status": answer?.status.rawValue ?? "unanswered",
                "points": answer?.points ?? 0, "maxPoints": maxPoints, "guessed": answer?.guessed ?? false,
                "response": NSNull(), "shuffle": NSNull(),
            ]
            if let answer {
                item["response"] = Self.jsonObject(answer.response)
                item["shuffle"] = answer.shuffle.map { Self.jsonObject($0) } ?? NSNull()
            }
            items.append(item)
        }
        let rank = { (label: String) -> Int in
            Self.stepOrder.firstIndex { $0.lowercased() == label.lowercased() } ?? Self.stepOrder.count + (label == "Not labeled" ? 1 : 0)
        }
        let used = min(Double(exam.timeLimitSeconds), max(0, (exam.finishedAt ?? .now).timeIntervalSince(exam.startedAt)))
        return [
            "questionCount": items.count, "answered": counts.answered, "unanswered": items.count - counts.answered,
            "fullyRight": counts.fullyRight, "partial": counts.partial, "missed": counts.missed, "guessed": counts.guessed,
            "points": counts.points, "maxPoints": counts.maxPoints, "minutesUsed": max(1, Int((used / 60).rounded())),
            "reviewCount": counts.review, "examBankWrong": counts.bankWrong,
            "byWeek": weeks.filter { $0.total > 0 }.map { ["label": $0.label, "right": $0.right, "total": $0.total] },
            "byFolder": folders.filter { $0.total > 0 }.map { ["folderId": $0.id, "label": $0.label, "right": $0.right, "total": $0.total] },
            "byStep": steps.sorted { rank($0.label) < rank($1.label) }.map { ["label": $0.label, "right": $0.right, "total": $0.total] },
            "items": items,
        ]
    }

    // MARK: Import, with the rules of `content/service.ts` `commitImport`

    /// The folder holding a current practice set.
    func folder(holding setID: String) -> Folder? {
        state.withLock { state in state.folders.first { $0.sets.contains(setID) } }
    }

    /// The folder an import files a set under: the one she picked, the one she named (the course's
    /// folder of that name on no exam page, else its only folder of that name, else a new one at the
    /// end of its Folders list), or Unsorted, made at the top of the Folders list the first time.
    func importFolder(courseID: String, folderID: String?, folderName: String?) -> Result<Folder, Failure> {
        state.withLock { state in
            if let folderID {
                guard let folder = state.folders.first(where: { $0.id == folderID && $0.courseID == courseID }) else {
                    return .failure(Failure(status: 400, message: "That folder is not in this course."))
                }
                return .success(folder)
            }
            if let folderName {
                let named = state.folders.filter { $0.courseID == courseID && $0.name.lowercased() == folderName.lowercased() }
                if let loose = named.first(where: { $0.examPageID == nil }) { return .success(loose) }
                if named.count == 1 { return .success(named[0]) }
                return .success(Self.newFolder(folderName, courseID: courseID, page: nil, in: &state))
            }
            if let unsorted = state.folders.first(where: { $0.courseID == courseID && $0.examPageID == nil && $0.name == "Unsorted" }) {
                return .success(unsorted)
            }
            let top = (state.folders.filter { $0.courseID == courseID && $0.examPageID == nil }.map(\.sortOrder).min() ?? 1) - 1
            var unsorted = Self.newFolder("Unsorted", courseID: courseID, page: nil, in: &state)
            unsorted.sortOrder = top
            state.folders[state.folders.count - 1] = unsorted
            return .success(unsorted)
        }
    }

    /// Files a new practice set in a folder, or with `replacing`, in that set's place.
    func file(set id: String, in folderID: String, replacing old: String?) {
        state.withLock { state in
            if let old, let index = state.folders.firstIndex(where: { $0.sets.contains(old) }) {
                state.folders[index].sets = state.folders[index].sets.map { $0 == old ? id : $0 }
            } else if let index = state.folders.firstIndex(where: { $0.id == folderID }) {
                state.folders[index].sets.append(id)
            }
        }
    }

    /// Files an exam set's questions in a folder's exam bank.
    func file(bank questionIDs: [String], in folderID: String) {
        state.withLock { state in
            guard let index = state.folders.firstIndex(where: { $0.id == folderID }) else { return }
            state.folders[index].bank += questionIDs
        }
    }

    // MARK: Folders and exam pages, with the rules and words of `content/folders.ts`

    /// A refusal, in the server's words.
    struct Failure: Error {
        let status: Int
        let message: String

        var reply: Reply { FakeStudy.failure(status, "request_refused", message) }
    }

    private static func reply(_ result: Result<Folder, Failure>, status: Int, _ folderJSON: (Folder) -> [String: Any]) -> Reply {
        switch result {
        case .success(let folder): (status, folderJSON(folder))
        case .failure(let failure): failure.reply
        }
    }

    /// A required name, trimmed: refused when blank or longer than 80 characters.
    private static func requiredText(_ value: Any?, label: String) -> Result<String, Failure> {
        let text = (value as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return .failure(Failure(status: 400, message: "\(label) is required.")) }
        if text.count > 80 { return .failure(Failure(status: 400, message: "\(label) is too long.")) }
        return .success(text)
    }

    /// A list as a refusal names it: the exam page, or the course for its Folders list.
    private static func listLabel(_ page: String?, courseID: String, in state: State) -> String {
        page.flatMap { page in state.courseExams.first { $0.id == page }?.name } ?? codes[courseID] ?? "This course"
    }

    /// Refuses a name another folder of the list already has, ignoring case.
    private static func nameTaken(_ name: String, courseID: String, page: String?, except ids: Set<String>, in state: State) -> Failure? {
        let clash = state.folders.first {
            $0.courseID == courseID && $0.examPageID == page && !ids.contains($0.id) && $0.name.lowercased() == name.lowercased()
        }
        return clash.map { Failure(status: 409, message: "\(listLabel(page, courseID: courseID, in: state)) already has a folder named \($0.name).") }
    }

    /// The exam page a folder may go on: one of its course's.
    private static func page(_ id: String, courseID: String, in state: State) -> Failure? {
        state.courseExams.contains { $0.id == id && $0.courseID == courseID } ? nil : Failure(status: 400, message: "That exam page is not in this course.")
    }

    /// The next place at the end of a list.
    private static func end(of page: String?, courseID: String, in state: State) -> Int {
        (state.folders.filter { $0.courseID == courseID && $0.examPageID == page }.map(\.sortOrder).max() ?? 0) + 1
    }

    private static func newFolder(_ name: String, courseID: String, page: String?, in state: inout State) -> Folder {
        state.folderCount += 1
        let folder = Folder(
            id: String(format: "f0000000-0000-4000-8000-%012d", 9000 + state.folderCount), courseID: courseID, name: name,
            examPageID: page, sortOrder: end(of: page, courseID: courseID, in: state), sets: [], bank: []
        )
        state.folders.append(folder)
        return folder
    }

    private func createFolder(courseID: String, body: [String: Any]) -> Result<Folder, Failure> {
        state.withLock { state in
            let name: String
            switch Self.requiredText(body["name"], label: "Folder name") {
            case .success(let text): name = text
            case .failure(let failure): return .failure(failure)
            }
            let page = body["examPageId"] as? String
            if let page, let failure = Self.page(page, courseID: courseID, in: state) { return .failure(failure) }
            if let failure = Self.nameTaken(name, courseID: courseID, page: page, except: [], in: state) { return .failure(failure) }
            return .success(Self.newFolder(name, courseID: courseID, page: page, in: &state))
        }
    }

    /// Renames a folder, puts it on an exam page, or takes it off one. A folder that changes list
    /// goes to the end of its new list.
    private func changeFolder(id: String, body: [String: Any]) -> Result<Folder, Failure> {
        state.withLock { state in
            guard let index = state.folders.firstIndex(where: { $0.id == id }) else {
                return .failure(Failure(status: 404, message: "That folder is not in the app."))
            }
            let folder = state.folders[index]
            var name = folder.name
            if body.keys.contains("name") {
                switch Self.requiredText(body["name"], label: "Folder name") {
                case .success(let text): name = text
                case .failure(let failure): return .failure(failure)
                }
            }
            let page = body.keys.contains("examPageId") ? body["examPageId"] as? String : folder.examPageID
            if let page, let failure = Self.page(page, courseID: folder.courseID, in: state) { return .failure(failure) }
            if let failure = Self.nameTaken(name, courseID: folder.courseID, page: page, except: [id], in: state) { return .failure(failure) }
            if page != folder.examPageID {
                state.folders[index].sortOrder = Self.end(of: page, courseID: folder.courseID, in: state)
                state.folders[index].examPageID = page
            }
            state.folders[index].name = name
            return .success(state.folders[index])
        }
    }

    /// Moves a set to a folder of its course, or to a new one at the end of the Folders list.
    private func moveSet(id: String, body: [String: Any]) -> Result<Folder, Failure> {
        state.withLock { state in
            guard let from = state.folders.firstIndex(where: { $0.sets.contains(id) }) else {
                return .failure(Failure(status: 404, message: "That set is not in the app."))
            }
            let courseID = state.folders[from].courseID
            let folderID = body["folderId"] as? String, newName = body["newFolderName"]
            if folderID != nil, newName != nil { return .failure(Failure(status: 400, message: "Choose a folder or a new folder name, not both.")) }
            let to: Int
            if let folderID {
                guard let index = state.folders.firstIndex(where: { $0.id == folderID && $0.courseID == courseID }) else {
                    return .failure(Failure(status: 400, message: "That folder is not in this course."))
                }
                to = index
            } else if newName != nil {
                let name: String
                switch Self.requiredText(newName, label: "Folder name") {
                case .success(let text): name = text
                case .failure(let failure): return .failure(failure)
                }
                if let failure = Self.nameTaken(name, courseID: courseID, page: nil, except: [], in: state) { return .failure(failure) }
                _ = Self.newFolder(name, courseID: courseID, page: nil, in: &state)
                to = state.folders.count - 1
            } else {
                return .failure(Failure(status: 400, message: "Choose a folder to move it to."))
            }
            if to != from {
                state.folders[from].sets.removeAll { $0 == id }
                state.folders[to].sets.append(id)
            }
            return .success(state.folders[to])
        }
    }

    /// Saves her order of one list. A list that does not name exactly its folders is refused.
    private func reorder(courseID: String, body: [String: Any], _ folderJSON: (Folder) -> [String: Any]) -> Reply {
        let result = state.withLock { state -> Result<[Folder], Failure> in
            let page = body["examPageId"] as? String
            if let page, let failure = Self.page(page, courseID: courseID, in: state) { return .failure(failure) }
            let ids = body["folderIds"] as? [String] ?? []
            let list = state.folders.filter { $0.courseID == courseID && $0.examPageID == page }.map(\.id)
            guard ids.count == list.count, Set(ids) == Set(list) else {
                return .failure(Failure(status: 409, message: "The folders changed since this list was shown. Reload and try again."))
            }
            for (position, id) in ids.enumerated() {
                if let index = state.folders.firstIndex(where: { $0.id == id }) { state.folders[index].sortOrder = position + 1 }
            }
            return .success(ids.compactMap { id in state.folders.first { $0.id == id } })
        }
        switch result {
        case .success(let folders): return (200, ["folders": folders.map(folderJSON)])
        case .failure(let failure): return failure.reply
        }
    }

    /// Adds an exam page or renames one and sets its folders, in the order sent. Folders it gives
    /// up go to the end of the Folders list.
    private func saveCourseExam(courseID givenCourse: String?, id: String?, body: [String: Any]) -> Reply {
        state.withLock { state -> Reply in
            let courseID: String
            if let id {
                guard let page = state.courseExams.first(where: { $0.id == id }) else {
                    return Self.failure(404, "request_refused", "That exam is not in the app.")
                }
                courseID = page.courseID
            } else {
                courseID = givenCourse ?? ""
            }
            let name: String
            switch Self.requiredText(body["name"], label: "Exam name") {
            case .success(let text): name = text
            case .failure(let failure): return failure.reply
            }
            if state.courseExams.contains(where: { $0.courseID == courseID && $0.id != id && $0.name.lowercased() == name.lowercased() }) {
                return Self.failure(409, "request_refused", "This course already has an exam named \(name).")
            }
            let sent = body["folderIds"] as? [String]
            var target: [Folder] = []
            for folderID in sent ?? [] where !target.contains(where: { $0.id == folderID }) {
                guard let folder = state.folders.first(where: { $0.id == folderID && $0.courseID == courseID }) else {
                    let missing = Set(sent ?? []).count { folderID in !state.folders.contains { $0.id == folderID && $0.courseID == courseID } }
                    return Self.failure(400, "request_refused", missing == 1 ? "That folder is not in this course." : "Those folders are not in this course.")
                }
                target.append(folder)
            }
            // A folder of another page is refused, naming the page that has it.
            var held: [(page: String, names: [String])] = []
            for folder in target {
                guard let holder = folder.examPageID, holder != id else { continue }
                let pageName = state.courseExams.first { $0.id == holder }?.name ?? "another exam page"
                if let index = held.firstIndex(where: { $0.page == pageName }) { held[index].names.append(folder.name) } else { held.append((pageName, [folder.name])) }
            }
            if !held.isEmpty {
                return Self.failure(409, "request_refused", held.map { "\(Self.listText($0.names)) \($0.names.count == 1 ? "is" : "are") in \($0.page)." }.joined(separator: " "))
            }
            for (index, folder) in target.enumerated() {
                if let clash = target.prefix(index).first(where: { $0.name.lowercased() == folder.name.lowercased() }) {
                    return Self.failure(409, "request_refused", "\(name) already has a folder named \(clash.name).")
                }
            }
            let keep = Set(target.map(\.id))
            let leaving = id.map { id in Self.ordered(state, courseID: courseID).filter { $0.examPageID == id && !keep.contains($0.id) } } ?? []
            if sent != nil {
                for folder in leaving {
                    if let failure = Self.nameTaken(folder.name, courseID: courseID, page: nil, except: keep.union([folder.id]), in: state) { return failure.reply }
                }
            }
            let page: CourseExam
            if let id, let index = state.courseExams.firstIndex(where: { $0.id == id }) {
                state.courseExams[index].name = name
                page = state.courseExams[index]
            } else {
                state.courseExamCount += 1
                page = CourseExam(
                    id: String(format: "c0e00000-0000-4000-8000-%012d", 100 + state.courseExamCount), courseID: courseID, name: name,
                    sortOrder: (state.courseExams.filter { $0.courseID == courseID }.map(\.sortOrder).max() ?? 0) + 1
                )
                state.courseExams.append(page)
            }
            // Without folderIds a page keeps its folders.
            if sent != nil {
                for folder in leaving {
                    guard let index = state.folders.firstIndex(where: { $0.id == folder.id }) else { continue }
                    state.folders[index].sortOrder = Self.end(of: nil, courseID: courseID, in: state)
                    state.folders[index].examPageID = nil
                }
                for (position, folder) in target.enumerated() {
                    guard let index = state.folders.firstIndex(where: { $0.id == folder.id }) else { continue }
                    state.folders[index].examPageID = page.id
                    state.folders[index].sortOrder = position + 1
                }
            }
            return (id == nil ? 201 : 200, Self.pageJSON(page, in: state))
        }
    }

    /// Removes an exam page. Its folders go to the end of the Folders list, unless one has the name
    /// of a folder already there.
    private func deleteCourseExam(id: String) -> Reply {
        state.withLock { state -> Reply in
            guard let page = state.courseExams.first(where: { $0.id == id }) else {
                return Self.failure(404, "request_refused", "That exam is not in the app.")
            }
            let own = Self.ordered(state, courseID: page.courseID).filter { $0.examPageID == id }
            for folder in own {
                if let clash = state.folders.first(where: { $0.courseID == page.courseID && $0.examPageID == nil && $0.name.lowercased() == folder.name.lowercased() }) {
                    let code = Self.codes[page.courseID] ?? "This course"
                    return Self.failure(409, "request_refused", "\(code) already has a folder named \(clash.name) in its Folders list. Rename one of them before removing \(page.name).")
                }
            }
            for folder in own {
                guard let index = state.folders.firstIndex(where: { $0.id == folder.id }) else { continue }
                state.folders[index].sortOrder = Self.end(of: nil, courseID: page.courseID, in: state)
                state.folders[index].examPageID = nil
            }
            state.courseExams.removeAll { $0.id == id }
            return (204, [:])
        }
    }

    // MARK: Plumbing

    /// The most a question can score: what its own key scores.
    static func maxPoints(_ question: Question) -> Int? {
        guard let right = FakeAnswers.right(question.body) else { return nil }
        return (try? Scoring.score(question.body, response: right))?.maxPoints
    }

    static func ids(_ prefix: String, _ count: Int) -> [String] {
        (0..<count).map { "\(prefix)-q\($0)" }
    }

    /// Exam-bank questions are asked only on exams and stay out of Review.
    static func isBank(_ id: String) -> Bool {
        id.hasPrefix("bank")
    }

    static func questionJSON(_ id: String, position: Int, week: String) -> [String: Any] {
        var question = FakePracticeQuestions.template(forQuestionID: id) ?? [:]
        question["id"] = id
        question["publicId"] = "Q\(position)"
        question["position"] = position
        question["weekLabel"] = week
        return question
    }

    static func question(_ id: String) -> Question? {
        guard let data = try? JSONSerialization.data(withJSONObject: questionJSON(id, position: 1, week: "")) else { return nil }
        return try? QBankJSON.decoder.decode(Question.self, from: data)
    }

    private static func jsonObject(_ value: some Encodable) -> Any {
        (try? QBankJSON.encoder.encode(value)).flatMap { try? JSONSerialization.jsonObject(with: $0) } ?? NSNull()
    }

    /// "Week 3", "Week 3 and Week 4", "Week 2, Week 3 and Week 4".
    static func listText(_ labels: [String]) -> String {
        guard labels.count > 1, let last = labels.last else { return labels.joined() }
        return "\(labels.dropLast().joined(separator: ", ")) and \(last)"
    }

    private static func json(_ value: String?) -> Any {
        value.map { $0 as Any } ?? NSNull()
    }

    private static func failure(_ status: Int, _ code: String, _ message: String) -> Reply {
        (status, ["error": code, "message": message])
    }
}

/// Answers to the invented questions, made from each question's own key: the right one, a wrong
/// one, and a partly right one where the format allows it.
nonisolated enum FakeAnswers {
    static func right(_ body: QuestionBody) -> AnswerResponse? {
        switch body {
        case .single(let options): options.firstIndex(where: \.isCorrect).map { .single(choice: $0) }
        case .priority(let options): options.firstIndex(where: \.isCorrect).map { .priority(choice: $0) }
        case .sata(let options): .sata(picks: options.indices.filter { options[$0].isCorrect })
        case .highlight(let segments): .highlight(picks: segments.indices.filter { segments[$0].isCorrect })
        case .order(let items): .order(positions: Array(items.indices))
        case .match(let pairs, _): .match(choices: pairs.map(\.right))
        case .matrix(_, let rows): .matrix(choices: rows.map(\.answer))
        case .cloze(let cloze): .cloze(choices: cloze.blanks.map(\.answer))
        case .unsupported: nil
        }
    }

    static func wrong(_ body: QuestionBody) -> AnswerResponse? {
        switch body {
        case .single(let options): options.firstIndex { !$0.isCorrect }.map { .single(choice: $0) }
        case .priority(let options): options.firstIndex { !$0.isCorrect }.map { .priority(choice: $0) }
        case .sata(let options): options.firstIndex { !$0.isCorrect }.map { .sata(picks: [$0]) }
        case .highlight(let segments): segments.firstIndex { !$0.isCorrect }.map { .highlight(picks: [$0]) }
        case .order(let items): .order(positions: Array(items.indices.reversed()))
        case .match(let pairs, _): .match(choices: pairs.indices.map { pairs[(($0 + 1) % pairs.count)].right })
        case .matrix(let columns, let rows): .matrix(choices: rows.map { row in columns.first { $0 != row.answer } ?? row.answer })
        case .cloze(let cloze): .cloze(choices: cloze.blanks.map { ($0.answer + 1) % max(1, $0.options.count) })
        case .unsupported: nil
        }
    }

    /// Partly right where the format gives points per part; a wrong answer otherwise.
    static func partly(_ body: QuestionBody) -> AnswerResponse? {
        switch body {
        case .sata(let options):
            let right = options.indices.filter { options[$0].isCorrect }
            return .sata(picks: Array(right.dropLast()))
        case .matrix(let columns, let rows):
            return .matrix(choices: rows.enumerated().map { index, row in index == 0 ? (columns.first { $0 != row.answer } ?? row.answer) : row.answer })
        default:
            return wrong(body)
        }
    }
}
#endif
