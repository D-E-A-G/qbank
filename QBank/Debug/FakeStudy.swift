#if DEBUG
import Foundation
import QBankKit
import Synchronization

/// The fake server's study side for slice 1c: Review, Terms, exams and the course's exams, with
/// the real server's rules and words (`apps/api/src/progress`, `exams`, `content/service.ts`).
/// Every question is one of `FakePracticeQuestions`' invented ones, scored with QBankKit's port of
/// the server's scoring. Nothing here comes from a real course.
nonisolated final class FakeStudy: Sendable {
    typealias Reply = (Int, [String: Any])

    /// A week as the exam setup counts it: the questions an exam over it draws from.
    struct ExamWeek {
        let label: String
        /// `exam` when the week has an exam bank, `practice` when its exams use practice questions.
        let source: String
        let pool: [String]
        /// The questions she last answered not fully right, before this run of the app.
        let wrongAtStart: [String]
    }

    struct CourseExam {
        let id: String
        var name: String
        let sortOrder: Int
        var weekLabels: [String]

        var json: [String: Any] {
            ["id": id, "name": name, "sortOrder": sortOrder, "weekLabels": weekLabels]
        }
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
        let weeks: [String]
        let pool: ExamPool
        let practiceWeeks: [String]?
        /// The questions in the order served, each with its week.
        let questions: [(id: String, week: String)]
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
        var courseExams: [String: [CourseExam]]
        var exams: [Exam] = []
        var review: [String: [ReviewEntry]]
        /// Her latest mark on each question she answered in this run, practice or exam.
        var latest: [String: ScoreStatus] = [:]
        var examCount = 0
        var courseExamCount = 0
    }

    static let mentalHealthWeeks = [
        ExamWeek(label: "Week 1", source: "exam", pool: ids("bank1", 17), wrongAtStart: ids("bank1", 4)),
        ExamWeek(label: "Week 2", source: "practice", pool: ids("communication-v1", 14) + ids("psychosocial-v2", 12),
                 wrongAtStart: ids("communication-v1", 5) + ids("psychosocial-v2", 2)),
        ExamWeek(label: "Week 3", source: "exam", pool: ids("bank3", 31), wrongAtStart: []),
        ExamWeek(label: "Weeks 1-3", source: "practice", pool: ids("mixed-v1", 8), wrongAtStart: ids("mixed-v1", 2)),
    ]

    static let fundamentalsWeeks = [
        ExamWeek(label: "Week 1", source: "practice", pool: ids("vitals-v1", 43), wrongAtStart: ids("vitals-v1", 6)),
        ExamWeek(label: "Week 2", source: "practice", pool: ids("safety-v1", 42), wrongAtStart: ids("safety-v1", 9)),
        ExamWeek(label: "Week 3", source: "practice", pool: ids("mobility-v1", 61), wrongAtStart: ids("mobility-v1", 2)),
    ]

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
        state = Mutex(State(
            courseExams: [
                FakeQBankServer.mentalHealthID: [
                    CourseExam(id: "c0e00000-0000-4000-8000-000000000001", name: "Exam 1", sortOrder: 1, weekLabels: ["Week 1", "Week 2"]),
                    CourseExam(id: "c0e00000-0000-4000-8000-000000000002", name: "Exam 2", sortOrder: 2, weekLabels: ["Week 3"]),
                ],
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
    /// ten days ago (Exam 1), and Weeks 1-3 across both exams a week ago (Other exams).
    private func seedPastExams() {
        let day: TimeInterval = 86_400
        let pasts: [(weeks: [String], startedDaysAgo: Double, minutes: Double, reason: ExamEndReason, pattern: (Int) -> String?)] = [
            (["Week 1", "Week 2"], 3, 52, .finished, { $0 % 5 == 4 ? "wrong" : "right" }),
            (["Week 1"], 10, 26, .timeout, { $0 >= 15 ? nil : ($0 % 7 == 6 ? "wrong" : "right") }),
            (["Week 1", "Week 2", "Week 3"], 7, 41, .finished, { $0 % 4 == 3 ? "partly" : "right" }),
        ]
        for past in pasts {
            let startedAt = now.addingTimeInterval(-past.startedDaysAgo * day)
            guard case .success(let id) = begin(
                courseID: FakeQBankServer.mentalHealthID, weeks: past.weeks, pool: .all, at: startedAt, endingRunning: false
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

    /// Answers the study routes; nil for any other route.
    func answer(method: String, path: String, query: [String: String], body: [String: Any]) -> Reply? {
        let parts = path.split(separator: "/").map(String.init)
        // /api/courses/{id}/...
        if parts.count >= 4, parts[0] == "api", parts[1] == "courses" {
            let courseID = parts[2]
            guard let weeks = Self.examWeeks(courseID) else { return nil }
            switch (method, parts.dropFirst(3).joined(separator: "/")) {
            case ("GET", "terms"): return (200, ["terms": termsJSON(courseID)])
            case ("GET", "review"): return review(courseID, filter: query["filter"] ?? "all")
            case ("GET", "review/practice"): return reviewPractice(courseID, filter: query["filter"] ?? "all", questionID: query["question"])
            case ("POST", "review/clear"): return clearReview(courseID, confirmed: body["confirmed"] as? Bool ?? false)
            case ("GET", "exams"): return (200, setup(courseID, weeks: weeks))
            case ("POST", "exams"): return start(courseID, body: body)
            case ("POST", "course-exams"): return saveCourseExam(courseID: courseID, id: nil, body: body)
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
        if parts.count >= 3, parts[0] == "api", parts[1] == "exams" {
            if parts.count == 3, method == "GET" { return examView(parts[2]) }
            if parts.count == 4, parts[3] == "finish", method == "POST" {
                let reason = (body["reason"] as? String).flatMap(ExamEndReason.init(rawValue:)) ?? .finished
                return finish(parts[2], reason: reason)
            }
        }
        return nil
    }

    /// The course's exams for `GET /api/courses/{id}`.
    func courseExamsJSON(_ courseID: String) -> [[String: Any]] {
        state.withLock { state in (state.courseExams[courseID] ?? []).map(\.json) }
    }

    func reviewCount(_ courseID: String) -> Int {
        state.withLock { $0.review[courseID]?.count ?? 0 }
    }

    func termCount(_ courseID: String) -> Int {
        courseID == FakeQBankServer.mentalHealthID ? Self.terms.count : 0
    }

    // MARK: Terms

    private func termsJSON(_ courseID: String) -> [[String: Any]] {
        guard courseID == FakeQBankServer.mentalHealthID else { return [] }
        return Self.terms.map { term in
            ["key": term.term.lowercased(), "term": term.term, "meaning": term.meaning, "weekLabel": term.week, "setTitle": term.set]
        }
    }

    // MARK: Review

    private func review(_ courseID: String, filter: String) -> Reply {
        let entries = state.withLock { $0.review[courseID] ?? [] }
        let counts: [String: Any] = [
            "all": entries.count,
            "missed": entries.count { $0.status == .incorrect },
            "partial": entries.count { $0.status == .partial },
            "guessed": entries.count(where: \.guessed),
        ]
        let shown = entries.filter { Self.matches($0, filter) }
        return (200, ["filter": filter, "counts": counts, "questions": shown.map(reviewJSON)])
    }

    private static func matches(_ entry: ReviewEntry, _ filter: String) -> Bool {
        switch filter {
        case "missed": entry.status == .incorrect
        case "partial": entry.status == .partial
        case "guessed": entry.guessed
        default: true
        }
    }

    private func reviewJSON(_ entry: ReviewEntry) -> [String: Any] {
        let template = FakePracticeQuestions.template(forQuestionID: entry.questionID) ?? [:]
        let type = (template["type"] as? String).flatMap(QuestionType.init(rawValue:))
        return [
            "questionId": entry.questionID, "topic": template["topic"] as? String ?? "",
            "weekLabel": entry.weekLabel, "format": Self.formatName(type),
            "status": entry.status.rawValue, "guessed": entry.guessed,
            "answeredAt": QBankJSON.formatDate(entry.answeredAt), "setTitle": entry.setTitle,
        ]
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
            "weekLabel": "", "kind": "practice", "questions": questions,
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

    static func examWeeks(_ courseID: String) -> [ExamWeek]? {
        switch courseID {
        case FakeQBankServer.mentalHealthID: mentalHealthWeeks
        case FakeQBankServer.fundamentalsID: fundamentalsWeeks
        default: nil
        }
    }

    private func wrongPool(_ week: ExamWeek, latest: [String: ScoreStatus]) -> [String] {
        week.pool.filter { id in latest[id].map { $0 != .correct } ?? week.wrongAtStart.contains(id) }
    }

    private func setup(_ courseID: String, weeks: [ExamWeek]) -> [String: Any] {
        settleExpired()
        return state.withLock { state in
            let exams = state.exams.filter { $0.courseID == courseID }.sorted { $0.startedAt > $1.startedAt }
            let courseExams = state.courseExams[courseID] ?? []
            let summaries = exams.map { summaryJSON($0, courseExams: courseExams) }
            return [
                "courseId": courseID,
                "weeks": weeks.map { week in
                    ["label": week.label, "questionCount": week.pool.count, "wrongCount": wrongPool(week, latest: state.latest).count, "source": week.source]
                },
                "inProgress": exams.firstIndex { $0.finishedAt == nil }.map { summaries[$0] } ?? NSNull(),
                "exams": exams.indices.filter { exams[$0].finishedAt != nil }.map { summaries[$0] },
            ]
        }
    }

    private func summaryJSON(_ exam: Exam, courseExams: [CourseExam]) -> [String: Any] {
        let result = exam.finishedAt == nil ? nil : score(exam)
        return [
            "id": exam.id, "courseId": exam.courseID, "weeks": exam.weeks,
            "courseExamId": Self.json(courseExams.first { course in exam.weeks.allSatisfy(course.weekLabels.contains) }?.id),
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
        let weeks = (body["weeks"] as? [String] ?? []).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let pool = (body["pool"] as? String).flatMap(ExamPool.init(rawValue:)) ?? .all
        switch begin(courseID: courseID, weeks: weeks, pool: pool, at: .now, endingRunning: true) {
        case .success(let id): return examView(id, status: 201)
        case .failure(let refusal): return Self.failure(400, refusal.code, refusal.message)
        }
    }

    struct Refusal: Error {
        let code: String
        let message: String
    }

    /// Draws an exam as the server does, in week order and without shuffling, so a test knows
    /// which question comes when.
    private func begin(courseID: String, weeks labels: [String], pool: ExamPool, at startedAt: Date, endingRunning: Bool) -> Result<String, Refusal> {
        guard let weeks = Self.examWeeks(courseID) else { return .failure(Refusal(code: "course_not_found", message: "That course is not in the app.")) }
        let ticked = Array(Set(labels)).sorted(by: EditExamsModel.weekOrder)
        guard !ticked.isEmpty else { return .failure(Refusal(code: "no_weeks", message: "Tick at least one week.")) }
        if let unknown = ticked.first(where: { label in !weeks.contains { $0.label == label } }) {
            return .failure(Refusal(code: "week_not_found", message: "\(unknown) has no questions in this course."))
        }
        let latest = state.withLock { $0.latest }
        let draw = { (label: String) -> [String] in
            guard let week = weeks.first(where: { $0.label == label }) else { return [] }
            return pool == .wrong ? self.wrongPool(week, latest: latest) : week.pool
        }
        let empty = ticked.filter { draw($0).isEmpty }
        if !empty.isEmpty {
            let one = empty.count == 1
            return .failure(Refusal(
                code: "no_wrong_questions",
                message: "\(Self.listText(empty)) \(one ? "has" : "have") no wrong questions. Untick \(one ? "it" : "them"), or turn off Wrong questions only."
            ))
        }
        let plan = ExamPlan(ticked.map { ExamPlan.Week(label: $0, questionCount: draw($0).count) })
        let questions = plan.weeks.flatMap { week in draw(week.label).prefix(week.drawn).map { (id: $0, week: week.label) } }
        let practiceWeeks = weeks.contains { $0.source == "exam" }
            ? ticked.filter { label in weeks.first { $0.label == label }?.source == "practice" }
            : nil
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
                id: id, courseID: courseID, weeks: ticked, pool: pool, practiceWeeks: practiceWeeks,
                questions: questions, timeLimitSeconds: plan.timeLimitSeconds, startedAt: startedAt
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
        return (status, [
            "id": exam.id, "courseId": exam.courseID, "courseCode": course.0, "courseTitle": course.1,
            "weeks": exam.weeks, "pool": exam.pool.rawValue, "practiceWeeks": exam.practiceWeeks.map { $0 as Any } ?? NSNull(),
            "timeLimitSeconds": exam.timeLimitSeconds, "startedAt": QBankJSON.formatDate(exam.startedAt),
            "endsAt": QBankJSON.formatDate(exam.endsAt), "finishedAt": Self.json(exam.finishedAt.map(QBankJSON.formatDate)),
            "endReason": Self.json(exam.endReason?.rawValue), "serverNow": QBankJSON.formatDate(.now),
            "questions": exam.questions.enumerated().map { Self.questionJSON($1.id, position: $0 + 1, week: $1.week) },
            "answeredQuestionIds": exam.questions.map(\.id).filter { exam.answers[$0] != nil },
            "result": exam.finishedAt == nil ? NSNull() : score(exam) as Any,
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
                    entries.insert(ReviewEntry(questionID: questionID, weekLabel: served.week, setTitle: "Exam", status: score.status, guessed: guessed, answeredAt: .now), at: 0)
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

    /// The result of an ended exam, counted as the server counts it.
    private func score(_ exam: Exam) -> [String: Any] {
        var items: [[String: Any]] = []
        var weeks = exam.weeks.map { (label: $0, right: 0, total: 0) }
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
            if let index = weeks.firstIndex(where: { $0.label == served.week }) {
                weeks[index].total += 1
                if right { weeks[index].right += 1 }
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
            "byStep": steps.sorted { rank($0.label) < rank($1.label) }.map { ["label": $0.label, "right": $0.right, "total": $0.total] },
            "items": items,
        ]
    }

    // MARK: Course exams

    private func saveCourseExam(courseID givenCourse: String?, id: String?, body: [String: Any]) -> Reply {
        state.withLock { state -> Reply in
            let courseID: String
            if let id {
                guard let course = state.courseExams.first(where: { $0.value.contains { $0.id == id } })?.key else {
                    return Self.failure(404, "request_refused", "That exam is not in the app.")
                }
                courseID = course
            } else {
                courseID = givenCourse ?? ""
            }
            guard let weeks = Self.examWeeks(courseID) else { return Self.failure(404, "request_refused", "That course is not in the app.") }
            let name = (body["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return Self.failure(400, "request_refused", "Exam name is required.") }
            guard name.count <= 80 else { return Self.failure(400, "request_refused", "Exam name is too long.") }
            let labels = Array(Set((body["weekLabels"] as? [String] ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }))
                .sorted(by: EditExamsModel.weekOrder)
            var exams = state.courseExams[courseID] ?? []
            let others = exams.filter { $0.id != id }
            if others.contains(where: { $0.name.lowercased() == name.lowercased() }) {
                return Self.failure(409, "request_refused", "This course already has an exam named \(name).")
            }
            let kept = Set(exams.first { $0.id == id }?.weekLabels ?? [])
            let unknown = labels.filter { label in !weeks.contains { $0.label == label } && !kept.contains(label) }
            if !unknown.isEmpty {
                return Self.failure(400, "request_refused", "\(Self.listText(unknown)) \(unknown.count == 1 ? "is not a week" : "are not weeks") in this course.")
            }
            let taken = others.compactMap { exam -> String? in
                let held = labels.filter(exam.weekLabels.contains)
                guard !held.isEmpty else { return nil }
                return "\(Self.listText(held)) \(held.count == 1 ? "is" : "are") in \(exam.name)."
            }
            if !taken.isEmpty { return Self.failure(409, "request_refused", taken.joined(separator: " ")) }
            if let id, let index = exams.firstIndex(where: { $0.id == id }) {
                exams[index].name = name
                exams[index].weekLabels = labels
                state.courseExams[courseID] = exams
                return (200, exams[index].json)
            }
            state.courseExamCount += 1
            let exam = CourseExam(
                id: String(format: "c0e00000-0000-4000-8000-%012d", 100 + state.courseExamCount), name: name,
                sortOrder: (exams.map(\.sortOrder).max() ?? 0) + 1, weekLabels: labels
            )
            exams.append(exam)
            state.courseExams[courseID] = exams
            return (201, exam.json)
        }
    }

    private func deleteCourseExam(id: String) -> Reply {
        state.withLock { state -> Reply in
            guard let course = state.courseExams.first(where: { $0.value.contains { $0.id == id } })?.key else {
                return Self.failure(404, "request_refused", "That exam is not in the app.")
            }
            state.courseExams[course]?.removeAll { $0.id == id }
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
