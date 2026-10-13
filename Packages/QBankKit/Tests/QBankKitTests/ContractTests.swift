import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import QBankKit

/// Each test drives the client through one recorded exchange with the real server routes and
/// checks both directions: the request the client builds matches the recorded one, and the
/// recorded response decodes into the models.
@Suite("Contract: sign-in and session")
struct SessionContractTests {
    @Test func health() async throws {
        let transport = try FixtureTransport("health")
        let (client, _) = TestClient.make(transport, token: nil)
        let health = try await client.health()
        #expect(health.status == "ok")
        try expectRequest(transport.requests.first, matches: Fixture.load("health"))
    }

    @Test func signInStoresTheBearerToken() async throws {
        let transport = try FixtureTransport("sign-in")
        let (client, store) = TestClient.make(transport, token: nil)
        let signedIn = try await client.signIn(email: "student@example.com", password: "synthetic-pass-1")
        try expectRequest(transport.requests.first, matches: Fixture.load("sign-in"))
        #expect(signedIn.token == "synthetic-session-token")
        #expect(signedIn.user.role == .student)
        #expect(signedIn.user.mustChangePassword == false)
        let stored = try #require(try store.load())
        #expect(stored.token == "synthetic-session-token")
        #expect(stored.account == signedIn.user)
        #expect(stored.expiresAt == signedIn.expiresAt)
    }

    @Test func wrongPasswordStoresNothing() async throws {
        let transport = try FixtureTransport("sign-in-wrong-password")
        let (client, store) = TestClient.make(transport, token: nil)
        let error = await #expect(throws: QBankError.self) {
            try await client.signIn(email: "student@example.com", password: "not-the-password")
        }
        #expect(error?.serverCode == .invalidCredentials)
        #expect(error?.needsSignIn == false)
        #expect(try store.load() == nil)
    }

    @Test func lockedSignInSaysHowLong() async throws {
        let transport = try FixtureTransport("sign-in-locked")
        let (client, _) = TestClient.make(transport, token: nil)
        let error = await #expect(throws: QBankError.self) {
            try await client.signIn(email: "locked@example.com", password: "wrong")
        }
        guard case .server(let server)? = error else {
            Issue.record("Expected a server error, got \(String(describing: error))")
            return
        }
        #expect(server.status == 429)
        #expect(server.code == .tooManyAttempts)
        #expect(server.retryAfterSeconds == 900)
        #expect(error?.isTemporary == true)
    }

    @Test func sessionRefreshesTheStoredAccount() async throws {
        let transport = try FixtureTransport("session")
        let (client, store) = TestClient.make(transport)
        let session = try await client.session()
        try expectRequest(transport.requests.first, matches: Fixture.load("session"))
        #expect(session.user.email == "student@example.com")
        let stored = try #require(try store.load())
        #expect(stored.token == "synthetic-session-token")
        #expect(stored.account == session.user)
    }

    @Test func endedSessionNeedsSignIn() async throws {
        let transport = try FixtureTransport("session-after-sign-out")
        let (client, _) = TestClient.make(transport, token: "synthetic-session-token-2")
        let error = await #expect(throws: QBankError.self) { try await client.session() }
        #expect(error?.needsSignIn == true)
        try expectRequest(transport.requests.first, matches: Fixture.load("session-after-sign-out"))
    }

    @Test func changePasswordStoresTheNewToken() async throws {
        let transport = try FixtureTransport("change-password")
        let (client, store) = TestClient.make(transport)
        let signedIn = try await client.changePassword(current: "synthetic-pass-1", new: "synthetic-pass-3")
        try expectRequest(transport.requests.first, matches: Fixture.load("change-password"))
        #expect(signedIn.token == "synthetic-session-token-2")
        #expect(try store.load()?.token == "synthetic-session-token-2")
    }

    @Test func wrongCurrentPasswordKeepsTheSession() async throws {
        let transport = try FixtureTransport("change-password-wrong")
        let (client, store) = TestClient.make(transport)
        let error = await #expect(throws: QBankError.self) {
            try await client.changePassword(current: "not-it", new: "synthetic-pass-3")
        }
        #expect(error?.serverCode == .invalidCredentials)
        #expect(error?.needsSignIn == false)
        #expect(try store.load()?.token == "synthetic-session-token")
        try expectRequest(transport.requests.first, matches: Fixture.load("change-password-wrong"))
    }

    @Test func signOutEndsTheSessionHereAndThere() async throws {
        let transport = try FixtureTransport("sign-out")
        let (client, store) = TestClient.make(transport, token: "synthetic-session-token-2")
        try await client.signOut()
        try expectRequest(transport.requests.first, matches: Fixture.load("sign-out"))
        #expect(try store.load() == nil)
    }
}

@Suite("Contract: courses and practice")
struct ContentContractTests {
    @Test func semesters() async throws {
        let transport = try FixtureTransport("semesters")
        let (client, _) = TestClient.make(transport)
        let semesters = try await client.semesters()
        try expectRequest(transport.requests.first, matches: Fixture.load("semesters"))
        let course = try #require(semesters.first?.courses.first)
        #expect(semesters.first?.number == 1)
        #expect(semesters.first?.startsOn == nil)
        #expect(course.code == "NURS 101")
        #expect(course.questionCount == 10)
        #expect(course.weekCount == 2)
        #expect(course.archivedAt == nil)
    }

    @Test func course() async throws {
        let fixture = try Fixture.load("course")
        let transport = try FixtureTransport([fixture])
        let (client, _) = TestClient.make(transport)
        let id = String(fixture.request.path.split(separator: "/").last!)
        let course = try await client.course(id: id)
        try expectRequest(transport.requests.first, matches: fixture)
        #expect(course.id == id)
        #expect(course.weeks.map(\.label) == ["Week 1", "Week 2"])
        #expect(course.weeks.map(\.examBankCount) == [2, 0])
        #expect(course.examQuestionCount == 4)
        let set = try #require(course.weeks.first?.sets.first)
        #expect(set.questionIDs.count == 8)
        #expect(set.status == .imported)
        #expect(set.lastAnsweredAt == nil)
        #expect(QBankJSON.formatDate(set.importedAt) == "2026-10-13T00:02:35.395Z")
    }

    @Test func missingCourse() async throws {
        let fixture = try Fixture.load("course-not-found")
        let transport = try FixtureTransport([fixture])
        let (client, _) = TestClient.make(transport)
        let error = await #expect(throws: QBankError.self) {
            try await client.course(id: "00000000-0000-4000-8000-000000000000")
        }
        guard case .server(let server)? = error else {
            Issue.record("Expected a server error")
            return
        }
        #expect(server.status == 404)
        #expect(server.code == .requestRefused)
        #expect(server.message == "That course is not in the app.")
    }

    @Test func terms() async throws {
        let fixture = try Fixture.load("terms")
        let transport = try FixtureTransport([fixture])
        let (client, _) = TestClient.make(transport)
        let terms = try await client.terms(courseID: courseID(of: fixture))
        try expectRequest(transport.requests.first, matches: fixture)
        #expect(terms.map(\.term) == ["Tachycardia"])
        #expect(terms.first?.weekLabel == "Week 1")
    }

    @Test func practiceSetReadsEveryFormat() async throws {
        let fixture = try Fixture.load("practice-set")
        let transport = try FixtureTransport([fixture])
        let (client, _) = TestClient.make(transport)
        let id = String(fixture.request.path.split(separator: "/").last!)
        let set = try await client.practiceSet(id: id)
        try expectRequest(transport.requests.first, matches: fixture)
        #expect(set.kind == .practice)
        #expect(set.weekLabel == "Week 1")
        #expect(set.questions.compactMap(\.type) == QuestionType.allCases)
        #expect(set.questions.map(\.publicID) == ["Q1", "Q2", "Q3", "Q4", "Q5", "Q6", "Q7", "Q8"])

        let single = set.questions[0]
        #expect(single.clinicalJudgmentStep == "Analyze cues")
        #expect(single.terms == [QuestionTerm(key: "tachy", term: "Tachycardia", meaning: "An invented definition of a fast heart rate.")])
        #expect(single.body == .single(options: [
            QuestionOption(text: "The useful action", isCorrect: true, why: "It addresses the finding."),
            QuestionOption(text: "A distractor", isCorrect: false, why: "It does not change the finding."),
            QuestionOption(text: "Another distractor", isCorrect: false, why: "Neither does this."),
        ]))
        #expect(single.table == QuestionTable(caption: "Invented readings", head: ["Time", "HR", ""], rows: [["0900", "82", ""], ["0915", "94", "extra"]]))
        #expect(single.images.isEmpty)

        let priority = set.questions[1]
        #expect(priority.images.count == 2)
        #expect(priority.images.first?.placement == .stem)
        #expect(priority.images.first?.caption == "Invented caption")
        #expect(priority.images.first?.file?.mediaType == "image/png")
        #expect(priority.images.last?.placement == .rationale)
        if case .svg(let markup)? = priority.images.last?.source {
            #expect(markup.hasPrefix("<svg"))
        } else {
            Issue.record("Expected SVG markup")
        }

        #expect(set.questions[3].body == .highlight(segments: [
            QuestionOption(text: "The client is alert.", isCorrect: false, why: "Expected."),
            QuestionOption(text: "Heart rate 128.", isCorrect: true, why: "Too fast."),
            QuestionOption(text: "Skin is cool and clammy.", isCorrect: true, why: "Poor perfusion."),
            QuestionOption(text: "Ate breakfast.", isCorrect: false, why: "Expected."),
        ]))
        #expect(set.questions[4].body == .order(items: [OrderItem(text: "Step one", why: "First."), OrderItem(text: "Step two"), OrderItem(text: "Step three")]))
        #expect(set.questions[5].body == .match(
            pairs: [MatchPair(left: "Drug A", right: "Class A", why: "A goes with A."), MatchPair(left: "Drug B", right: "Class B")],
            extra: [MatchExtra(right: "Class C", why: "Matches nothing.")]
        ))
        #expect(set.questions[6].body == .matrix(
            columns: ["Indicated", "Not indicated"],
            rows: [MatrixRow(text: "Order one", answer: "Indicated", why: "Helps."), MatrixRow(text: "Order two", answer: "Not indicated")]
        ))
        #expect(set.questions[7].body == .cloze(Cloze(
            text: "The client is most at risk for {0} because of {1}.",
            blanks: [ClozeBlank(options: ["bleeding", "infection", "falls"], answer: 1, why: "Invented reason."), ClozeBlank(options: ["the wound", "the diet"], answer: 0)]
        )))
    }

    @Test func restoreBringsBackThePreviousVersion() async throws {
        let fixture = try Fixture.load("practice-set-restore")
        let transport = try FixtureTransport([fixture])
        let (client, _) = TestClient.make(transport)
        let replacedID = fixture.request.path.split(separator: "/").dropLast().last.map(String.init)!
        let restored = try await client.restorePracticeSet(id: replacedID)
        try expectRequest(transport.requests.first, matches: fixture)
        #expect(restored.id != replacedID)
        #expect(restored.status == .restored)
        #expect(restored.canRestore)
        #expect(restored.questionCount == 2)
    }

    @Test func restoringAnOldVersionIsRefused() async throws {
        let fixture = try Fixture.load("practice-set-restore-not-current")
        let transport = try FixtureTransport([fixture])
        let (client, _) = TestClient.make(transport)
        let id = fixture.request.path.split(separator: "/").dropLast().last.map(String.init)!
        let error = await #expect(throws: QBankError.self) { try await client.restorePracticeSet(id: id) }
        #expect(error?.serverCode == .requestRefused)
        guard case .server(let server)? = error else {
            Issue.record("Expected a server error")
            return
        }
        #expect(server.status == 404)
        #expect(server.message == "That set is not the current version.")
    }

    @Test func practiceSetSurvivesTheCacheRoundTrip() throws {
        let set = try Fixture.load("practice-set").decodeBody(PracticeSet.self)
        let again = try QBankJSON.decoder.decode(PracticeSet.self, from: QBankJSON.encoder.encode(set))
        #expect(again == set)
        let original = try Fixture.load("practice-set").response.body
        #expect(try JSONDecoder().decode(JSONValue.self, from: QBankJSON.encoder.encode(set)) == original)
    }
}

@Suite("Contract: answers")
struct AttemptContractTests {
    /// The questions the attempt fixtures answered, from the same recording.
    static func questions() throws -> [String: Question] {
        let set = try Fixture.load("practice-set").decodeBody(PracticeSet.self)
        return Dictionary(uniqueKeysWithValues: set.questions.map { ($0.id, $0) })
    }

    static let practiceAttempts = [
        "attempt-saved", "attempt-partial", "attempt-guessed", "attempt-highlight",
        "attempt-order", "attempt-match", "attempt-matrix", "attempt-cloze",
    ]

    @Test(arguments: practiceAttempts)
    func sendsTheAnswerAndReadsTheReceipt(name: String) async throws {
        let fixture = try Fixture.load(name)
        let submission = try #require(fixture.request.body).decode(AttemptSubmission.self)
        let transport = try FixtureTransport([fixture])
        let (client, _) = TestClient.make(transport)
        let saved = try await client.recordAttempt(submission)
        try expectRequest(transport.requests.first, matches: fixture)
        #expect(saved.clientAttemptID == submission.clientAttemptID)
        #expect(saved.questionID == submission.questionID)
        #expect(saved.replayed == false)
        #expect(fixture.response.status == 201)
    }

    /// The phone's scoring gives the mark the server gave, for every format.
    @Test(arguments: practiceAttempts + ["exam-attempt"])
    func phoneScoringMatchesTheServer(name: String) throws {
        let fixture = try Fixture.load(name)
        let submission = try #require(fixture.request.body).decode(AttemptSubmission.self)
        let saved = try fixture.decodeBody(SavedAttempt.self)
        let question: Question
        if name == "exam-attempt" {
            let exam = try Fixture.load("exam-start").decodeBody(Exam.self)
            question = try #require(exam.questions.first { $0.id == submission.questionID })
        } else {
            question = try #require(try Self.questions()[submission.questionID])
        }
        let score = try Scoring.score(question.body, response: submission.response)
        #expect(score.points == saved.points)
        #expect(score.maxPoints == saved.maxPoints)
        #expect(score.status == saved.status)
        if name != "exam-attempt" {
            #expect(score.staysInReview(guessed: submission.guessed) == saved.inReview)
        }
    }

    @Test func replayReturnsTheSavedAttempt() async throws {
        let fixture = try Fixture.load("attempt-replayed")
        let transport = try FixtureTransport([fixture])
        let (client, _) = TestClient.make(transport)
        let submission = try #require(fixture.request.body).decode(AttemptSubmission.self)
        let saved = try await client.recordAttempt(submission)
        #expect(fixture.response.status == 200)
        #expect(saved.replayed == true)
        #expect(saved == SavedAttempt.replayOf(try Fixture.load("attempt-saved").decodeBody(SavedAttempt.self)))
    }

    @Test(arguments: [
        ("attempt-conflict", 409, ServerError.Code.attemptConflict),
        ("attempt-invalid", 400, .invalidResponse),
        ("exam-attempt-again", 409, .alreadyAnswered),
        ("exam-attempt-after-end", 409, .examFinished),
    ])
    func refusedAnswers(name: String, status: Int, code: ServerError.Code) async throws {
        let fixture = try Fixture.load(name)
        let transport = try FixtureTransport([fixture])
        let (client, _) = TestClient.make(transport)
        let submission = try #require(fixture.request.body).decode(AttemptSubmission.self)
        let error = await #expect(throws: QBankError.self) { try await client.recordAttempt(submission) }
        guard case .server(let server)? = error else {
            Issue.record("Expected a server error")
            return
        }
        #expect(server.status == status)
        #expect(server.code == code)
        #expect(error?.isTemporary == false)
        let refusal = try #require(error)
        #expect(AttemptQueue.keepsWaiting(after: refusal) == false)
        try expectRequest(transport.requests.first, matches: fixture)
    }
}

@Suite("Contract: Review")
struct ReviewContractTests {
    @Test func reviewList() async throws {
        let fixture = try Fixture.load("review")
        let transport = try FixtureTransport([fixture])
        let (client, _) = TestClient.make(transport)
        let list = try await client.review(courseID: courseID(of: fixture))
        try expectRequest(transport.requests.first, matches: fixture)
        #expect(list.filter == .all)
        #expect(list.counts == ReviewList.Counts(all: 7, missed: 2, partial: 4, guessed: 1))
        #expect(list.questions.count == 7)
    }

    @Test func filteredReviewList() async throws {
        let fixture = try Fixture.load("review-guessed")
        let transport = try FixtureTransport([fixture])
        let (client, _) = TestClient.make(transport)
        let list = try await client.review(courseID: courseID(of: fixture), filter: .guessed)
        try expectRequest(transport.requests.first, matches: fixture)
        #expect(list.filter == .guessed)
        #expect(list.questions.allSatisfy { $0.guessed })
    }

    @Test func reviewPractice() async throws {
        let fixture = try Fixture.load("review-practice")
        let transport = try FixtureTransport([fixture])
        let (client, _) = TestClient.make(transport)
        let set = try await client.reviewPractice(courseID: courseID(of: fixture), filter: .missed)
        try expectRequest(transport.requests.first, matches: fixture)
        #expect(set.id == set.courseID)
        #expect(set.questions.count == 2)
    }

    @Test func reviewPracticeOneQuestion() async throws {
        let fixture = try Fixture.load("review-practice-one")
        let transport = try FixtureTransport([fixture])
        let (client, _) = TestClient.make(transport)
        let questionID = try #require(fixture.request.query["question"])
        let set = try await client.reviewPractice(courseID: courseID(of: fixture), questionID: questionID)
        try expectRequest(transport.requests.first, matches: fixture)
        #expect(set.questions.map(\.id) == [questionID])
    }

    @Test func clearNeedsConfirmation() async throws {
        let fixture = try Fixture.load("review-clear-unconfirmed")
        let transport = try FixtureTransport([fixture])
        let (client, _) = TestClient.make(transport)
        let error = await #expect(throws: QBankError.self) {
            try await client.clearReview(courseID: courseID(of: fixture), confirmed: false)
        }
        #expect(error?.serverCode == .confirmationRequired)
        try expectRequest(transport.requests.first, matches: fixture)
    }

    @Test func clear() async throws {
        let fixture = try Fixture.load("review-clear")
        let transport = try FixtureTransport([fixture])
        let (client, _) = TestClient.make(transport)
        let cleared = try await client.clearReview(courseID: courseID(of: fixture))
        try expectRequest(transport.requests.first, matches: fixture)
        #expect(cleared == 7)
    }
}

@Suite("Contract: exams")
struct ExamContractTests {
    @Test func setupShowsWrongCountsPerWeek() async throws {
        let fixture = try Fixture.load("exam-setup")
        let transport = try FixtureTransport([fixture])
        let (client, _) = TestClient.make(transport)
        let setup = try await client.examSetup(courseID: courseID(of: fixture))
        try expectRequest(transport.requests.first, matches: fixture)
        #expect(setup.weeks.map(\.label) == ["Week 1", "Week 2"])
        #expect(setup.weeks.map(\.source) == [.exam, .practice])
        #expect(setup.weeks.map(\.wrongCount) == [1, 0])
        #expect(setup.inProgress == nil)
        #expect(setup.exams.isEmpty)
    }

    @Test func setupWithARunningExam() throws {
        let setup = try Fixture.load("exam-setup-in-progress").decodeBody(ExamSetup.self)
        let running = try #require(setup.inProgress)
        #expect(running.finishedAt == nil)
        #expect(running.endReason == nil)
        #expect(running.fullyRight == nil)
        #expect(running.pool == .all)
        #expect(running.practiceWeeks == ["Week 2"])
    }

    @Test func setupAfterExams() throws {
        let setup = try Fixture.load("exam-setup-after").decodeBody(ExamSetup.self)
        #expect(setup.exams.count == 1)
        #expect(setup.exams.first?.endReason == .finished)
        #expect(setup.inProgress?.pool == .wrong)
    }

    @Test func startOverEveryQuestion() async throws {
        let fixture = try Fixture.load("exam-start")
        let transport = try FixtureTransport([fixture])
        let (client, _) = TestClient.make(transport)
        let exam = try await client.startExam(courseID: courseID(of: fixture), weeks: ["Week 1", "Week 2"], pool: .all)
        try expectRequest(transport.requests.first, matches: fixture)
        #expect(exam.isRunning)
        #expect(exam.result == nil)
        #expect(exam.questions.count == 4)
        #expect(exam.questions.allSatisfy { $0.weekLabel != nil })
        #expect(exam.timeLimitSeconds == 360)
        #expect(exam.secondsLeftAtServerNow > 0)
    }

    @Test func startOverWrongQuestions() async throws {
        let fixture = try Fixture.load("exam-start-wrong")
        let transport = try FixtureTransport([fixture])
        let (client, _) = TestClient.make(transport)
        let exam = try await client.startExam(courseID: courseID(of: fixture), weeks: ["Week 1"], pool: .wrong)
        try expectRequest(transport.requests.first, matches: fixture)
        #expect(exam.pool == .wrong)
        #expect(exam.weeks == ["Week 1"])
    }

    @Test func weekWithoutWrongQuestionsIsRefused() async throws {
        let fixture = try Fixture.load("exam-start-no-wrong")
        let transport = try FixtureTransport([fixture])
        let (client, _) = TestClient.make(transport)
        let error = await #expect(throws: QBankError.self) {
            try await client.startExam(courseID: courseID(of: fixture), weeks: ["Week 2"], pool: .wrong)
        }
        #expect(error?.serverCode == .noWrongQuestions)
        try expectRequest(transport.requests.first, matches: fixture)
    }

    @Test func examAnswerNamesItsExam() async throws {
        let fixture = try Fixture.load("exam-attempt")
        let transport = try FixtureTransport([fixture])
        let (client, _) = TestClient.make(transport)
        let submission = try #require(fixture.request.body).decode(AttemptSubmission.self)
        #expect(submission.studySessionID != nil)
        _ = try await client.recordAttempt(submission)
        try expectRequest(transport.requests.first, matches: fixture)
    }

    @Test func runningExam() async throws {
        let fixture = try Fixture.load("exam-running")
        let transport = try FixtureTransport([fixture])
        let (client, _) = TestClient.make(transport)
        let id = String(fixture.request.path.split(separator: "/").last!)
        let exam = try await client.exam(id: id)
        try expectRequest(transport.requests.first, matches: fixture)
        #expect(exam.answeredQuestionIDs.count == 1)
        #expect(exam.isRunning)
    }

    @Test func finishScoresTheExam() async throws {
        let fixture = try Fixture.load("exam-finish")
        let transport = try FixtureTransport([fixture])
        let (client, _) = TestClient.make(transport)
        let id = String(fixture.request.path.split(separator: "/").dropLast().last!)
        let exam = try await client.finishExam(id: id, reason: .finished)
        try expectRequest(transport.requests.first, matches: fixture)
        #expect(exam.endReason == .finished)
        #expect(exam.isRunning == false)
        #expect(exam.result != nil)
    }

    @Test func endedExamResult() throws {
        let exam = try Fixture.load("exam-ended").decodeBody(Exam.self)
        let result = try #require(exam.result)
        #expect(result.questionCount == 4)
        #expect(result.answered == 1)
        #expect(result.unanswered == 3)
        #expect(result.byWeek.map(\.label) == ["Week 1", "Week 2"])
        #expect(result.byStep.map(\.label) == ["Analyze cues"])
        let answered = try #require(result.items.first)
        #expect(answered.status == .correct)
        #expect(answered.response == .single(choice: 0))
        #expect(answered.shuffle == .options(order: [0, 2, 1]))
        #expect(result.items.dropFirst().allSatisfy { $0.status == .unanswered && $0.response == nil && $0.shuffle == nil })
    }
}

@Suite("Contract: settings")
struct SettingsContractTests {
    @Test func emptyStudyPlace() async throws {
        let transport = try FixtureTransport("place-empty")
        let (client, _) = TestClient.make(transport)
        #expect(try await client.studyPlace() == nil)
        try expectRequest(transport.requests.first, matches: Fixture.load("place-empty"))
    }

    @Test func studyPlace() async throws {
        let fixture = try Fixture.load("place")
        let transport = try FixtureTransport([fixture])
        let (client, _) = TestClient.make(transport)
        let place = try await client.studyPlace()
        #expect(place == fixture.response.body["courseId"]?.stringValue)
        #expect(place != nil)
    }

    @Test func setStudyPlace() async throws {
        let fixture = try Fixture.load("place-put")
        let transport = try FixtureTransport([fixture])
        let (client, _) = TestClient.make(transport)
        let courseID = try #require(fixture.request.body?["courseId"]?.stringValue)
        try await client.setStudyPlace(courseID: courseID)
        try expectRequest(transport.requests.first, matches: fixture)
    }

    @Test func exportIsTheFileAsSent() async throws {
        let fixture = try Fixture.load("export")
        let transport = try FixtureTransport([fixture])
        let (client, _) = TestClient.make(transport)
        let data = try await client.exportProgress()
        try expectRequest(transport.requests.first, matches: fixture)
        #expect(try JSONDecoder().decode(JSONValue.self, from: data) == fixture.response.body)
    }

    @Test func passkeys() async throws {
        let transport = try FixtureTransport("passkeys")
        let (client, _) = TestClient.make(transport)
        #expect(try await client.passkeys().isEmpty)
        try expectRequest(transport.requests.first, matches: Fixture.load("passkeys"))
    }
}

@Suite("Contract: the recordings themselves")
struct FixtureTests {
    /// Every error the server sent decodes into a typed error with its code and message.
    @Test func everyErrorBodyDecodes() throws {
        let failures = try Fixture.all().filter { $0.response.status >= 400 }
        #expect(failures.count >= 10)
        for fixture in failures {
            let response = HTTPURLResponse(url: TestClient.baseURL, statusCode: fixture.response.status, httpVersion: nil, headerFields: fixture.response.headers)!
            let error = QBankClient.failure(status: fixture.response.status, data: try fixture.responseData, response: response)
            guard case .server(let server) = error else {
                Issue.record("\(fixture.name) did not decode as a server error")
                continue
            }
            #expect(server.code.rawValue == fixture.response.body["error"]?.stringValue, "\(fixture.name)")
            #expect(!server.message.isEmpty, "\(fixture.name)")
        }
    }

    /// Every recorded call is a path and method the pinned OpenAPI file documents, with that status.
    @Test func everyRecordingIsInTheOpenAPIFile() throws {
        let url = try #require(Bundle.module.url(forResource: "openapi", withExtension: "json", subdirectory: "Fixtures"))
        let spec = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        guard case .object(let paths)? = spec["paths"] else {
            Issue.record("openapi.json has no paths")
            return
        }
        for fixture in try Fixture.all() {
            let template = paths.keys.first { matches(template: $0, path: fixture.request.path) }
            let operation = template.flatMap { paths[$0]?[fixture.request.method.lowercased()] }
            #expect(operation != nil, "\(fixture.name): \(fixture.request.method) \(fixture.request.path) is not in openapi.json")
            #expect(operation?["responses"]?[String(fixture.response.status)] != nil, "\(fixture.name): status \(fixture.response.status) is not documented")
        }
    }

    /// The recordings hold no real session token, only placeholders.
    @Test func recordingsHoldOnlyPlaceholderTokens() throws {
        for fixture in try Fixture.all() {
            if let authorization = fixture.request.authorization {
                #expect(authorization.hasPrefix("Bearer synthetic-"), "\(fixture.name)")
            }
            if let token = fixture.response.body["token"]?.stringValue {
                #expect(token.hasPrefix("synthetic-"), "\(fixture.name)")
            }
        }
    }

    private func matches(template: String, path: String) -> Bool {
        let left = template.split(separator: "/")
        let right = path.split(separator: "/")
        guard left.count == right.count else { return false }
        return zip(left, right).allSatisfy { $0.hasPrefix("{") || $0 == $1 }
    }
}

/// The course id in a recorded `/api/courses/{id}/...` path.
func courseID(of fixture: Fixture) -> String {
    let parts = fixture.request.path.split(separator: "/")
    return String(parts[2])
}

extension SavedAttempt {
    /// What the server answers to a repeated id: the saved attempt with `replayed` set.
    static func replayOf(_ saved: SavedAttempt) -> SavedAttempt {
        SavedAttempt(
            clientAttemptID: saved.clientAttemptID, questionID: saved.questionID, courseID: saved.courseID,
            status: saved.status, points: saved.points, maxPoints: saved.maxPoints, guessed: saved.guessed,
            answeredAt: saved.answeredAt, inReview: saved.inReview, label: saved.label, replayed: true
        )
    }
}
