import Foundation
import QBankKit
import Testing
@testable import QBank

@MainActor
struct PracticeModelTests {
    /// A set of two invented questions, listed out of order: a select-all at position 1 and a
    /// single answer at position 2.
    static func practiceSet(courseID: String = "c1", kind: String = "practice") -> String {
        #"""
        {"id":"set1","courseId":"\#(courseID)","title":"Invented set","weekLabel":"Week 1","kind":"\#(kind)","questions":[
         {"id":"q-single","publicId":"Q2","position":2,"type":"single","topic":"Invented single","cj":"Take action",
          "stem":"Stem two.","ask":"Which one?","rationale":"Because.","takeaway":"Remember.","terms":[],
          "body":{"options":[{"t":"Right","ok":true},{"t":"Wrong"},{"t":"Also wrong"}]}},
         {"id":"q-sata","publicId":"Q1","position":1,"type":"sata","topic":"","cj":null,
          "stem":"Stem one.","ask":"Which apply?","rationale":"Because.","takeaway":"Remember.","terms":[],
          "body":{"options":[{"t":"A","ok":true},{"t":"B"},{"t":"C","ok":true}]}}
        ]}
        """#
    }

    static func saved(id: String, question: String, status: String, points: Int, max: Int, guessed: Bool = false) -> String {
        #"{"clientAttemptId":"\#(id)","questionId":"\#(question)","courseId":"c1","status":"\#(status)","points":\#(points),"maxPoints":\#(max),"guessed":\#(guessed),"answeredAt":"2026-10-13T00:00:00.000Z","inReview":true,"label":"x","replayed":false}"#
    }

    /// A model whose shuffles keep the stored order, whose ids count up, and whose clock and
    /// retries are under the test's control.
    static func model(
        _ server: StubServer,
        account: Account = .student(),
        now: @escaping () -> Date = { Date(timeIntervalSince1970: 1_000) },
        sleep: @escaping (Duration) async throws -> Void = { _ in }
    ) -> (PracticeModel, AppModel) {
        let (app, _) = TestApp.make(server, account: account)
        var next = 0
        let model = PracticeModel(
            app: app, setID: "set1", courseID: "c1", title: "From the course",
            now: now,
            sleep: sleep,
            makeLayout: { body in
                switch body {
                case .single(let options), .priority(let options), .sata(let options): .options(order: Array(options.indices).reversed())
                default: .plain
                }
            },
            newAttemptID: {
                next += 1
                return "attempt-\(next)"
            }
        )
        return (model, app)
    }

    @Test func loadsTheSetInPracticeOrderWithOneShuffleAndIdPerQuestion() async throws {
        let server = StubServer(["GET /api/practice-sets/set1": .ok(Self.practiceSet())])
        let (model, _) = Self.model(server)
        #expect(model.title == "From the course", "the Course screen's title shows while it loads")
        await model.load()
        #expect(model.phase == .answering)
        #expect(model.title == "Invented set")
        #expect(model.questions.map(\.id) == ["q-sata", "q-single"])
        #expect(model.attempts.map(\.clientAttemptID) == ["attempt-1", "attempt-2"])
        #expect(model.attempts.first?.layout == .options(order: [2, 1, 0]))
        #expect(model.attempts.first?.draft == .sata([]))
        #expect(model.countText == "1 of 2")
        #expect(model.progress == 0)
        #expect(!model.canCheck)
    }

    @Test func anExamBankIsNotPracticed() async {
        let server = StubServer(["GET /api/practice-sets/set1": .ok(Self.practiceSet(kind: "exam"))])
        let (model, _) = Self.model(server)
        await model.load()
        #expect(model.phase == .failed("This set’s questions are asked only on exams."))
    }

    @Test func aSetFromAnotherCourseIsRefused() async {
        let server = StubServer(["GET /api/practice-sets/set1": .ok(Self.practiceSet(courseID: "other"))])
        let (model, _) = Self.model(server)
        await model.load()
        #expect(model.phase == .failed("That set is not in this course."))
    }

    @Test func noSignalSaysSo() async {
        let server = StubServer(["GET /api/practice-sets/set1": .offline])
        let (model, _) = Self.model(server)
        await model.load()
        #expect(model.phase == .failed("No connection. Check Wi-Fi or cellular data and try again."))
    }

    @Test func anEndedSessionSignsOut() async {
        let server = StubServer(["GET /api/practice-sets/set1": .error(401, "unauthenticated", "Sign in to continue.")])
        let (model, app) = Self.model(server)
        await model.load()
        #expect(app.route == .signedOut)
        #expect(model.phase == .loading)
    }

    @Test func theOwnerCanLookButNotAnswer() async {
        let server = StubServer()
        let (model, _) = Self.model(server, account: .admin)
        await model.load()
        #expect(model.phase == .readOnly)
        #expect(server.requests.isEmpty)
    }

    @Test func checkSendsTheAnswerInStoredIndexesAndShowsTheServersScore() async throws {
        let server = StubServer([
            "GET /api/practice-sets/set1": .ok(Self.practiceSet()),
            // The server's word wins, even where the phone would score it otherwise.
            "POST /api/attempts": StubServer.Reply(status: 201, body: Self.saved(id: "attempt-1", question: "q-sata", status: "partial", points: 1, max: 2, guessed: true)),
        ])
        let (model, _) = Self.model(server)
        await model.load()
        model.update(.sata([2, 0]))
        model.setGuessed(true)
        #expect(model.canCheck)
        await model.check()

        let sent = try #require(server.requests.last?.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: sent) as? [String: Any])
        #expect(body["clientAttemptId"] as? String == "attempt-1")
        #expect(body["questionId"] as? String == "q-sata")
        #expect(body["guessed"] as? Bool == true)
        #expect((body["response"] as? [String: Any])?["picks"] as? [Int] == [2, 0])
        #expect((body["shuffle"] as? [String: Any])?["order"] as? [Int] == [2, 1, 0])

        #expect(model.attempt?.score == Score(points: 1, maxPoints: 2, status: .partial, answered: true))
        #expect(model.isRevealed)
        #expect(model.progress == 0.5)
        #expect(!model.canCheck)
        model.update(.sata([0]))
        #expect(model.attempt?.draft == .sata([2, 0]), "a checked answer cannot change")
    }

    @Test func aDroppedConnectionIsRetriedWithTheSameId() async throws {
        let server = StubServer([
            "GET /api/practice-sets/set1": .ok(Self.practiceSet()),
            "POST /api/attempts": .offline,
        ])
        var waits: [Duration] = []
        var sawWaiting = false
        var modelRef: PracticeModel?
        let (model, _) = Self.model(server, sleep: { delay in
            waits.append(delay)
            sawWaiting = sawWaiting || modelRef?.isWaiting == true
            if waits.count == 5 {
                server["POST /api/attempts"] = StubServer.Reply(status: 201, body: Self.saved(id: "attempt-1", question: "q-sata", status: "correct", points: 2, max: 2))
            }
        })
        modelRef = model
        await model.load()
        model.update(.sata([0, 2]))
        await model.check()

        let attempts = server.requests.filter { $0.url?.path() == "/api/attempts" }
        #expect(attempts.count == 6)
        let ids = try attempts.map { request in
            try #require(try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])["clientAttemptId"] as? String
        }
        #expect(Set(ids) == ["attempt-1"])
        #expect(waits == [.seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(15)])
        #expect(sawWaiting)
        #expect(!model.isWaiting)
        #expect(model.attempt?.score?.status == .correct)
        #expect(model.problem == nil)
    }

    @Test func aRefusalIsSaidAndTheAnswerStaysOpen() async {
        let server = StubServer([
            "GET /api/practice-sets/set1": .ok(Self.practiceSet()),
            "POST /api/attempts": .error(404, "request_refused", "That question is no longer in the set."),
        ])
        let (model, _) = Self.model(server)
        await model.load()
        model.update(.sata([0]))
        await model.check()
        #expect(model.problem == "That question is no longer in the set.")
        #expect(!model.isRevealed)
        #expect(model.canCheck, "she can try again")
        #expect(model.attempt?.clientAttemptID == "attempt-1", "a retry keeps the same id")
    }

    @Test func leavingWhileWaitingStopsQuietly() async {
        let server = StubServer([
            "GET /api/practice-sets/set1": .ok(Self.practiceSet()),
            "POST /api/attempts": .offline,
        ])
        let (model, _) = Self.model(server, sleep: { _ in throw CancellationError() })
        await model.load()
        model.update(.sata([0]))
        await model.check()
        #expect(model.problem == nil)
        #expect(!model.isChecking)
        #expect(!model.isWaiting)
        #expect(!model.isRevealed)
    }

    @Test func nextWalksTheSetThenShowsTheResult() async throws {
        var clock = Date(timeIntervalSince1970: 1_000)
        let server = StubServer([
            "GET /api/practice-sets/set1": .ok(Self.practiceSet()),
            "POST /api/attempts": StubServer.Reply(status: 201, body: Self.saved(id: "a", question: "q", status: "partial", points: 1, max: 2)),
        ])
        let (model, _) = Self.model(server, now: { clock })
        await model.load()
        model.next()
        #expect(model.index == 0, "she checks before moving on")
        model.update(.sata([0]))
        await model.check()
        model.next()
        #expect(model.index == 1)
        #expect(model.countText == "2 of 2")
        #expect(model.isLast)
        model.update(.single(0))
        server["POST /api/attempts"] = StubServer.Reply(status: 201, body: Self.saved(id: "b", question: "q", status: "correct", points: 1, max: 1))
        await model.check()
        #expect(model.progress == 1)
        clock = clock.addingTimeInterval(95)
        model.next()
        #expect(model.phase == .finished)
        let result = try #require(model.result)
        #expect(result.fullyRight == 1)
        #expect(result.partial == 1)
        #expect(result.points == 2)
        #expect(result.maxPoints == 3)
        #expect(result.elapsed == 95)
    }

    @Test func onlyConnectionTroubleIsRetried() {
        #expect(PracticeModel.isTransient(.transport(.notConnectedToInternet)))
        #expect(PracticeModel.isTransient(.transport(.timedOut)))
        #expect(PracticeModel.isTransient(.server(ServerError(status: 502, code: .init(rawValue: "x"), message: "", retryAfterSeconds: nil))))
        #expect(PracticeModel.isTransient(.unexpectedResponse(status: 503, detail: "proxy")))
        #expect(PracticeModel.isTransient(.unexpectedResponse(status: 504, detail: "proxy")))
        #expect(!PracticeModel.isTransient(.server(ServerError(status: 503, code: .init(rawValue: "auth_unavailable"), message: "", retryAfterSeconds: nil))))
        #expect(!PracticeModel.isTransient(.server(ServerError(status: 409, code: .init(rawValue: "attempt_conflict"), message: "", retryAfterSeconds: nil))))
        #expect(!PracticeModel.isTransient(.unexpectedResponse(status: 500, detail: "")))
        #expect(!PracticeModel.isTransient(.cancelled))
        #expect(!PracticeModel.isTransient(.notSignedIn))
    }
}
