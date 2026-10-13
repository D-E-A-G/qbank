import Foundation
import QBankKit
import Testing
@testable import QBank

@MainActor
struct ExamModelTests {
    /// A model whose shuffles keep the stored order, whose ids count up, and whose clock and
    /// retries are under the test's control.
    static func model(
        _ server: StubServer,
        account: Account = .student(),
        clock: @escaping () -> ContinuousClock.Instant = { .now },
        sleep: @escaping (Duration) async throws -> Void = { _ in }
    ) -> ExamModel {
        let (app, _) = TestApp.make(server, account: account)
        var next = 0
        return ExamModel(
            app: app, examID: "e1", clock: clock, sleep: sleep,
            makeLayout: { body in
                if case .single(let options) = body { return .options(order: Array(options.indices)) }
                return .plain
            },
            newAttemptID: {
                next += 1
                return "attempt-\(next)"
            }
        )
    }

    private func sentBody(_ server: StubServer) throws -> [String: Any] {
        let data = try #require(server.requests.last?.httpBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// Lets a task the model started run to its end.
    private func settle(_ until: () -> Bool) async {
        for _ in 0..<300 where !until() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func opensOnTheFirstQuestionStillOpenWithTheServersTimeLeft() async throws {
        let server = StubServer(["GET /api/exams/e1": .ok(StudyBodies.exam(answered: ["e1-q0"]))])
        let model = Self.model(server)
        await model.load()
        #expect(model.phase == .running)
        #expect(model.items.map(\.submitted) == [true, false, false])
        #expect(model.index == 1)
        #expect(model.countText == "2 of 3")
        #expect(model.title == "Exam · Weeks 1-2")
        #expect(model.progress == 1.0 / 3)
        #expect(abs(model.secondsLeft - 600) < 1, "15 minutes from the start, 5 gone by the server's clock")
        #expect(!model.canSubmit, "nothing picked yet")
    }

    @Test func submitSendsTheAnswerWithTheExamAndMovesOn() async throws {
        let server = StubServer([
            "GET /api/exams/e1": .ok(StudyBodies.exam()),
            "POST /api/attempts": StubServer.Reply(status: 201, body: StudyBodies.saved(question: "e1-q0", attempt: "attempt-1")),
        ])
        let model = Self.model(server)
        await model.load()
        model.update(.single(0))
        model.setGuessed(true)
        #expect(model.canSubmit)
        await model.submit()
        let body = try sentBody(server)
        #expect(body["studySessionId"] as? String == "e1")
        #expect(body["clientAttemptId"] as? String == "attempt-1")
        #expect(body["questionId"] as? String == "e1-q0")
        #expect(body["guessed"] as? Bool == true)
        #expect((body["response"] as? [String: Any])?["choice"] as? Int == 0)
        #expect(model.items[0].submitted)
        #expect(model.index == 1)
        #expect(model.submittedCount == 1)
        #expect(model.endMessage == "The 1 question you answered will be scored. Skipped and unreached questions score 0 and stay out of Review.")
    }

    @Test func skippedQuestionsComeBackAfterTheLastOneAndTheLastOpenOneFinishes() async throws {
        let server = StubServer([
            "GET /api/exams/e1": .ok(StudyBodies.exam()),
            "POST /api/attempts": StubServer.Reply(status: 201, body: StudyBodies.saved(question: "e1-q1", attempt: "a")),
            "POST /api/exams/e1/finish": .ok(StudyBodies.exam(ended: "finished", result: StudyBodies.result())),
        ])
        let model = Self.model(server)
        await model.load()
        await model.skip()
        #expect(model.index == 1)
        #expect(model.items[0].skipped)
        #expect(model.skippedLeft == 0, "not back at the skipped ones yet")
        model.update(.single(1))
        await model.submit()
        #expect(model.index == 2)
        await model.skip()
        #expect(model.index == 0, "wraps back to the first skipped question")
        #expect(model.isReturning)
        #expect(model.wrappedTo == 0)
        #expect(model.skippedLeft == 2)
        #expect(!model.isLastPending)
        model.update(.single(0))
        await model.submit()
        #expect(model.index == 2)
        #expect(model.wrappedTo == nil)
        #expect(model.isLastPending, "its button says Finish exam")
        model.update(.single(0))
        await model.submit()
        await settle { model.phase == .ended }
        #expect(model.phase == .ended)
        #expect(server.calls.last == "POST /api/exams/e1/finish")
        #expect(try sentBody(server)["reason"] as? String == "finished")
        #expect(model.exam?.result?.fullyRight == 1)
    }

    @Test func anAnswerTheServerAlreadyHasCountsAsSent() async throws {
        let server = StubServer([
            "GET /api/exams/e1": .ok(StudyBodies.exam()),
            "POST /api/attempts": .error(409, "already_answered", "That question was already answered on this exam."),
        ])
        let model = Self.model(server)
        await model.load()
        model.update(.single(0))
        await model.submit()
        #expect(model.items[0].submitted)
        #expect(model.index == 1)
        #expect(model.problem == nil)
    }

    @Test func anExamThatEndedMeanwhileShowsItsResult() async throws {
        let server = StubServer([
            "GET /api/exams/e1": .ok(StudyBodies.exam()),
            "POST /api/attempts": .error(409, "exam_finished", "This exam has ended. That answer was not saved."),
        ])
        let model = Self.model(server)
        await model.load()
        server["GET /api/exams/e1"] = .ok(StudyBodies.exam(ended: "timeout", result: StudyBodies.result()))
        model.update(.single(0))
        await model.submit()
        #expect(model.phase == .ended)
        #expect(model.exam?.endReason == .timeout)
    }

    @Test func aDroppedConnectionIsRetriedWithTheSameId() async throws {
        let server = StubServer([
            "GET /api/exams/e1": .ok(StudyBodies.exam()),
            "POST /api/attempts": .offline,
        ])
        var waits: [Duration] = []
        var model: ExamModel?
        var sawWaiting = false
        model = Self.model(server, sleep: { delay in
            waits.append(delay)
            sawWaiting = sawWaiting || model?.isWaiting == true
            if waits.count == 3 {
                server["POST /api/attempts"] = StubServer.Reply(status: 201, body: StudyBodies.saved(question: "e1-q0", attempt: "attempt-1"))
            }
        })
        let exam = try #require(model)
        await exam.load()
        exam.update(.single(0))
        await exam.submit()
        #expect(waits == [.seconds(1), .seconds(2), .seconds(4)])
        #expect(sawWaiting)
        #expect(!exam.isWaiting)
        let ids = server.requests.filter { $0.httpMethod == "POST" }.map { request in
            request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["clientAttemptId"] as? String
        }
        #expect(ids.count == 4)
        #expect(Set(ids) == ["attempt-1"])
        #expect(exam.index == 1)
    }

    @Test func endingEarlyScoresWhatSheAnswered() async throws {
        let server = StubServer([
            "GET /api/exams/e1": .ok(StudyBodies.exam()),
            "POST /api/exams/e1/finish": .ok(StudyBodies.exam(ended: "left", result: StudyBodies.result())),
        ])
        let model = Self.model(server)
        await model.load()
        await model.end(.left)
        #expect(model.phase == .ended)
        #expect(try sentBody(server)["reason"] as? String == "left")
        #expect(model.exam?.endReason == .left)
    }

    @Test func anEndThatDoesNotGoThroughSaysSoAndKeepsTheExam() async throws {
        let server = StubServer([
            "GET /api/exams/e1": .ok(StudyBodies.exam()),
            "POST /api/exams/e1/finish": .offline,
        ])
        let model = Self.model(server)
        await model.load()
        await model.end(.left)
        #expect(model.phase == .running)
        #expect(!model.isEnding)
        #expect(model.problem == "Could not end the exam. Check the connection and try again.")
    }

    @Test func aRefusedEndShowsTheServersWords() async throws {
        let server = StubServer([
            "GET /api/exams/e1": .ok(StudyBodies.exam()),
            "POST /api/exams/e1/finish": .error(404, "exam_not_found", "That exam is not in the app."),
        ])
        let model = Self.model(server)
        await model.load()
        await model.end(.left)
        #expect(model.problem == "That exam is not in the app.")
    }

    @Test func anAnswerStillRetryingStopsWhenTheExamTurnsOutEnded() async throws {
        let server = StubServer([
            "GET /api/exams/e1": .ok(StudyBodies.exam()),
            "POST /api/attempts": .offline,
        ])
        var model: ExamModel?
        var retries = 0
        model = Self.model(server, sleep: { _ in
            retries += 1
            if retries == 1 {
                // She comes back to the app: the server has ended the exam meanwhile.
                server["GET /api/exams/e1"] = .ok(StudyBodies.exam(ended: "timeout", result: StudyBodies.result()))
                await model?.resync()
            }
        })
        let exam = try #require(model)
        await exam.load()
        exam.update(.single(0))
        await exam.submit()
        #expect(exam.phase == .ended)
        #expect(retries == 1, "no retry after the exam ended")
        #expect(!exam.isSaving)
        #expect(!exam.isWaiting)
    }

    @Test func theTimeRunningOutEndsTheExam() async throws {
        let start = ContinuousClock.now
        var elapsed = Duration.zero
        let server = StubServer([
            "GET /api/exams/e1": .ok(StudyBodies.exam()),
            "POST /api/exams/e1/finish": .ok(StudyBodies.exam(ended: "timeout", result: StudyBodies.result())),
        ])
        let model = Self.model(server, clock: { start.advanced(by: elapsed) })
        await model.load()
        elapsed = .seconds(599)
        model.tick()
        #expect(abs(model.secondsLeft - 1) < 0.01)
        #expect(model.phase == .running)
        elapsed = .seconds(601)
        model.tick()
        #expect(model.secondsLeft == 0)
        await settle { model.phase == .ended }
        #expect(model.phase == .ended)
        #expect(try sentBody(server)["reason"] as? String == "timeout")
    }

    @Test func comingBackChecksTheTimeWithTheServer() async throws {
        let server = StubServer(["GET /api/exams/e1": .ok(StudyBodies.exam())])
        let model = Self.model(server)
        await model.load()
        model.update(.single(1))
        server["GET /api/exams/e1"] = .ok(StudyBodies.exam(serverNow: "2026-10-12T00:14:00.000Z"))
        await model.resync()
        #expect(abs(model.secondsLeft - 60) < 1, "the server's clock wins")
        #expect(model.items[0].draft == .single(1), "her open answer stays")
        server["GET /api/exams/e1"] = .ok(StudyBodies.exam(ended: "timeout", result: StudyBodies.result()))
        await model.resync()
        #expect(model.phase == .ended)
    }

    @Test func anEndedExamOpensOnItsResult() async throws {
        let server = StubServer(["GET /api/exams/e1": .ok(StudyBodies.exam(ended: "finished", result: StudyBodies.result()))])
        let model = Self.model(server)
        await model.load()
        #expect(model.phase == .ended)
        #expect(model.items.isEmpty)
    }

    @Test func theOwnerWatchesHerRunningExam() async throws {
        let server = StubServer(["GET /api/exams/e1": .ok(StudyBodies.exam())])
        let model = Self.model(server, account: .admin)
        await model.load()
        #expect(model.phase == .watching)
    }

    @Test func aMissingExamIsSaidInTheServersWords() async throws {
        let server = StubServer(["GET /api/exams/e1": .error(404, "exam_not_found", "That exam is not in the app.")])
        let model = Self.model(server)
        await model.load()
        #expect(model.phase == .failed("That exam is not in the app."))
    }

    @Test func onlyConnectionTroubleIsRetried() {
        #expect(ExamModel.isTransient(.transport(.notConnectedToInternet)))
        #expect(ExamModel.isTransient(.transport(.timedOut)))
        #expect(ExamModel.isTransient(.server(ServerError(status: 502, code: .init(rawValue: "x"), message: ""))))
        #expect(ExamModel.isTransient(.unexpectedResponse(status: 503, detail: "proxy")))
        #expect(!ExamModel.isTransient(.server(ServerError(status: 409, code: .examFinished, message: ""))))
        #expect(!ExamModel.isTransient(.unexpectedResponse(status: 500, detail: "")))
        #expect(!ExamModel.isTransient(.cancelled))
        #expect(!ExamModel.isTransient(.notSignedIn))
    }

    @Test func examBankWrongIsWordedAsOnTheWeb() {
        #expect(ExamResultView.bankWrongText(1, isStudent: true) == "1 exam-bank question you got wrong stays out of Review. Turn on Wrong questions only to take it again.")
        #expect(ExamResultView.bankWrongText(2, isStudent: true) == "2 exam-bank questions you got wrong stay out of Review. Turn on Wrong questions only to take them again.")
        #expect(ExamResultView.bankWrongText(1, isStudent: false) == "1 exam-bank question she got wrong stays out of Review. It comes back when she takes Wrong questions only.")
    }
}

@MainActor
struct EditExamsModelTests {
    private static let exams = [
        StudyBodies.courseExam("x1", "Exam 1", order: 1, weeks: ["Week 1", "Week 2"]),
        StudyBodies.courseExam("x2", "Exam 2", order: 2, weeks: ["Week 3", "Week 9"]),
    ]

    private func model(_ server: StubServer) throws -> EditExamsModel {
        let (app, _) = TestApp.make(server, account: .student())
        let course = try QBankJSON.decoder.decode(CourseDetail.self, from: Data(StudyBodies.course(exams: Self.exams).utf8))
        return EditExamsModel(app: app, course: course)
    }

    @Test func chipsAreTheCoursesWeeksAndAWeekIsInOneExam() throws {
        let model = try model(StubServer())
        #expect(model.weekLabels == ["Week 1", "Week 2", "Week 3", "Week 9"], "a week whose sets moved away stays until taken out")
        let (first, second) = (model.drafts[0], model.drafts[1])
        #expect(model.holder(of: "Week 1", besides: second)?.name == "Exam 1")
        #expect(model.holder(of: "Week 1", besides: first) == nil)
        model.toggle("Week 1", in: second)
        #expect(!model.drafts[1].weeks.contains("Week 1"), "a week another exam holds cannot be tapped")
        model.toggle("Week 2", in: first)
        model.toggle("Week 2", in: model.drafts[1])
        #expect(model.drafts[1].weeks == ["Week 2", "Week 3", "Week 9"])
        #expect(model.line(model.drafts[0]) == "Week 1 · 10 questions")
        #expect(model.line(model.drafts[1]) == "Weeks 2-3, 9 · 22 questions")
        #expect(model.hasChanges)
    }

    @Test func addExamTakesTheNextFreeName() throws {
        let model = try model(StubServer())
        model.addExam()
        #expect(model.drafts.last?.name == "Exam 3")
        #expect(model.line(try #require(model.drafts.last)) == "No weeks yet")
        model.rename(model.drafts[2], to: "Exam 4")
        model.addExam()
        #expect(model.drafts.last?.name == "Exam 5")
        model.remove(model.drafts[3])
        #expect(model.drafts.count == 3)
    }

    @Test func savingReleasesWeeksBeforeAnotherExamTakesThem() async throws {
        let server = StubServer([
            "PUT /api/course-exams/x1": .ok(StudyBodies.courseExam("x1", "Exam 1", order: 1, weeks: ["Week 1"])),
            "PUT /api/course-exams/x2": .ok(StudyBodies.courseExam("x2", "Midterm", order: 2, weeks: ["Week 2", "Week 3", "Week 9"])),
            "POST /api/courses/c1/course-exams": StubServer.Reply(status: 201, body: StudyBodies.courseExam("x3", "Exam 3", order: 3, weeks: [])),
        ])
        let model = try model(server)
        model.toggle("Week 2", in: model.drafts[0])
        model.toggle("Week 2", in: model.drafts[1])
        model.rename(model.drafts[1], to: "Midterm")
        model.addExam()
        #expect(await model.save())
        #expect(server.calls == ["PUT /api/course-exams/x1", "PUT /api/course-exams/x2", "POST /api/courses/c1/course-exams"])
        let bodies = try server.requests.map { String(decoding: try #require($0.httpBody), as: UTF8.self) }
        #expect(bodies == [
            #"{"name":"Exam 1","weekLabels":["Week 1"]}"#,
            #"{"name":"Midterm","weekLabels":["Week 2","Week 3","Week 9"]}"#,
            #"{"name":"Exam 3","weekLabels":[]}"#,
        ])
        #expect(model.savedSome)
        #expect(!model.hasChanges)
    }

    @Test func aRemovedExamIsDeletedFirst() async throws {
        let server = StubServer([
            "DELETE /api/course-exams/x2": StubServer.Reply(status: 204, body: ""),
            "PUT /api/course-exams/x1": .ok(StudyBodies.courseExam("x1", "Exam 1", order: 1, weeks: ["Week 1", "Week 2", "Week 3"])),
        ])
        let model = try model(server)
        model.remove(model.drafts[1])
        model.toggle("Week 3", in: model.drafts[0])
        #expect(await model.save())
        #expect(server.calls == ["DELETE /api/course-exams/x2", "PUT /api/course-exams/x1"])
    }

    @Test func aRefusalIsSaidInTheServersWordsAndDoneSendsOnlyWhatIsLeft() async throws {
        let server = StubServer([
            "PUT /api/course-exams/x2": .error(409, "request_refused", "This course already has an exam named exam 1."),
            "POST /api/courses/c1/course-exams": StubServer.Reply(status: 201, body: StudyBodies.courseExam("x3", "Exam 3", order: 3, weeks: [])),
        ])
        let model = try model(server)
        model.rename(model.drafts[1], to: "exam 1")
        model.addExam()
        #expect(await model.save() == false)
        #expect(model.problem == "This course already has an exam named exam 1.")
        #expect(server.calls == ["PUT /api/course-exams/x2"], "it stops at the refusal")
        #expect(!model.savedSome)

        server["PUT /api/course-exams/x2"] = .ok(StudyBodies.courseExam("x2", "Final", order: 2, weeks: ["Week 3", "Week 9"]))
        model.rename(model.drafts[1], to: "Final")
        #expect(await model.save())
        #expect(model.problem == nil)
        #expect(server.calls == ["PUT /api/course-exams/x2", "PUT /api/course-exams/x2", "POST /api/courses/c1/course-exams"])

        // Done again has nothing left to send.
        #expect(await model.save())
        #expect(server.calls.count == 3)
    }

    @Test func weekOrderIsTheServers() {
        #expect(["Week 10", "Weeks 1-3", "Week 2", "Week 1", "Orientation"].sorted(by: EditExamsModel.weekOrder) == ["Week 1", "Weeks 1-3", "Week 2", "Week 10", "Orientation"])
    }
}
