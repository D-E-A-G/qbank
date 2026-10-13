import Foundation
import Observation
import QBankKit

/// One run through a practice set: the questions in order, her answer to each, and the score the
/// server gave it. Works like the web runner (`apps/web/src/practice/PracticeScreen.tsx`): every
/// opening shuffles the choices, Check answer sends the answer and shows the server's score, and
/// after the last question the set result.
@Observable
final class PracticeModel {
    /// Her work on one question during this run.
    struct Attempt: Equatable {
        /// The order she sees the choices in, made once per opening and saved with the answer.
        let layout: Layout
        var draft: AnswerDraft
        var guessed = false
        /// Made once per opening, so a retried send is never counted twice.
        let clientAttemptID: String
        /// The server's score, once she has checked.
        var score: Score?
    }

    enum Phase: Equatable {
        case loading
        /// The set could not be opened, said in words for her.
        case failed(String)
        /// Someone other than the student: the owner can look at her progress but not answer.
        case readOnly
        case answering
        case finished
    }

    let setID: String
    let courseID: String
    /// The set's title from the Course screen, shown while it loads.
    let initialTitle: String

    private(set) var phase: Phase = .loading
    private(set) var practiceSet: PracticeSet?
    /// The set's questions in the order she practices them.
    private(set) var questions: [Question] = []
    private(set) var attempts: [Attempt] = []
    private(set) var index = 0
    /// True while Check answer is sending.
    private(set) var isChecking = false
    /// True while a send waits for the connection to come back.
    private(set) var isWaiting = false
    /// Why the last Check answer did not go through.
    private(set) var problem: String?
    private(set) var startedAt: Date?
    private(set) var finishedAt: Date?

    private let app: AppModel
    private let now: () -> Date
    private let sleep: (Duration) async throws -> Void
    private let makeLayout: (QuestionBody) -> Layout
    private let newAttemptID: () -> String

    init(
        app: AppModel,
        setID: String,
        courseID: String,
        title: String,
        now: @escaping () -> Date = { .now },
        sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        makeLayout: @escaping (QuestionBody) -> Layout = { Layout.make(for: $0) },
        newAttemptID: @escaping () -> String = { AttemptSubmission.newID() }
    ) {
        self.app = app
        self.setID = setID
        self.courseID = courseID
        self.initialTitle = title
        self.now = now
        self.sleep = sleep
        self.makeLayout = makeLayout
        self.newAttemptID = newAttemptID
    }

    var title: String { practiceSet?.title ?? initialTitle }

    var question: Question? {
        questions.indices.contains(index) ? questions[index] : nil
    }

    var attempt: Attempt? {
        attempts.indices.contains(index) ? attempts[index] : nil
    }

    var isRevealed: Bool { attempt?.score != nil }
    var isLast: Bool { index == questions.count - 1 }

    /// "3 of 17".
    var countText: String { "\(index + 1) of \(questions.count)" }

    /// Questions done, counting this one once it is checked.
    var progress: Double {
        guard !questions.isEmpty else { return 0 }
        return Double(index + (isRevealed ? 1 : 0)) / Double(questions.count)
    }

    /// Whether Check answer can be pressed: every required part is filled in and nothing is sending.
    var canCheck: Bool {
        guard let attempt, attempt.score == nil, !isChecking else { return false }
        return attempt.draft.response != nil
    }

    var result: PracticeResult? {
        guard phase == .finished, let startedAt else { return nil }
        return PracticeResult(
            title: title,
            questions: questions,
            attempts: attempts,
            elapsed: (finishedAt ?? startedAt).timeIntervalSince(startedAt)
        )
    }

    // MARK: Loading

    func load() async {
        guard app.account?.role == .student else {
            phase = .readOnly
            return
        }
        do {
            let loaded = try await app.client.practiceSet(id: setID)
            if loaded.kind == .exam {
                phase = .failed("This set’s questions are asked only on exams.")
                return
            }
            guard loaded.courseID == courseID else {
                phase = .failed("That set is not in this course.")
                return
            }
            begin(loaded)
        } catch {
            if app.handle(error) { return }
            if let words = Wording.problem(error) {
                phase = .failed(words)
            }
        }
    }

    private func begin(_ loaded: PracticeSet) {
        practiceSet = loaded
        questions = loaded.questions.sorted { $0.position < $1.position }
        attempts = questions.map { question in
            let layout = makeLayout(question.body)
            return Attempt(layout: layout, draft: AnswerDraft(body: question.body, layout: layout), clientAttemptID: newAttemptID())
        }
        index = 0
        startedAt = now()
        finishedAt = nil
        phase = .answering
    }

    // MARK: Answering

    /// Replaces her answer to the current question while it is still open.
    func update(_ draft: AnswerDraft) {
        guard attempts.indices.contains(index), attempts[index].score == nil, !isChecking else { return }
        attempts[index].draft = draft
    }

    func setGuessed(_ guessed: Bool) {
        guard attempts.indices.contains(index), attempts[index].score == nil, !isChecking else { return }
        attempts[index].guessed = guessed
    }

    /// Sends the answer and shows the score the server gave it. A dropped connection is retried
    /// with the same answer id until the server answers, so an answer that arrived before the
    /// connection dropped is never counted twice. A refusal is said in her words.
    func check() async {
        guard canCheck, let question, let attempt, let response = attempt.draft.response else { return }
        problem = nil
        do {
            // Catches an answer the question cannot take before it leaves the phone.
            _ = try Scoring.score(question.body, response: response)
        } catch {
            problem = error.message
            return
        }
        let checking = index
        isChecking = true
        defer {
            isChecking = false
            isWaiting = false
        }
        let submission = AttemptSubmission(
            clientAttemptID: attempt.clientAttemptID,
            questionID: question.id,
            response: response,
            guessed: attempt.guessed,
            shuffle: attempt.layout
        )
        do {
            let saved = try await send(submission)
            guard attempts.indices.contains(checking), attempts[checking].score == nil else { return }
            attempts[checking].score = Score(saved)
        } catch {
            if error == .cancelled || app.handle(error) { return }
            problem = Wording.problem(error)
        }
    }

    /// The next question, or the set result after the last one.
    func next() {
        guard isRevealed else { return }
        if index < questions.count - 1 {
            problem = nil
            index += 1
        } else if phase == .answering {
            finishedAt = now()
            phase = .finished
        }
    }

    private func send(_ submission: AttemptSubmission) async throws(QBankError) -> SavedAttempt {
        var delay = Self.firstRetryDelay
        while true {
            do {
                return try await app.client.recordAttempt(submission)
            } catch where Self.isTransient(error) {
                isWaiting = true
            }
            do {
                try await sleep(delay)
            } catch {
                throw .cancelled
            }
            delay = min(delay * 2, Self.longestRetryDelay)
        }
    }

    static let firstRetryDelay = Duration.seconds(1)
    static let longestRetryDelay = Duration.seconds(15)

    /// A failed connection, or a proxy or a restarting server in front of the API: worth sending
    /// again with the same id. A refusal from the API itself is final.
    nonisolated static func isTransient(_ error: QBankError) -> Bool {
        switch error {
        case .transport:
            return true
        case .server(let server):
            return server.status == 502 || server.status == 504
        case .unexpectedResponse(let status, _):
            return status == 502 || status == 503 || status == 504
        case .cancelled, .notSignedIn, .storage, .invalidRequest:
            return false
        }
    }
}
