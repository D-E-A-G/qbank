import Foundation
import QBankKit
import Synchronization
@testable import QBank

/// Answers each request from a table of routes and keeps every request it was sent, so a test
/// says exactly what the server answers and checks exactly what the app asked.
final class StubServer: HTTPTransport {
    struct Reply: Sendable {
        let status: Int
        let body: String

        static func ok(_ body: String) -> Reply { Reply(status: 200, body: body) }

        static func error(_ status: Int, _ code: String, _ message: String) -> Reply {
            Reply(status: status, body: #"{"error":"\#(code)","message":"\#(message)"}"#)
        }

        /// No signal: the request never got an answer.
        static let offline = Reply(status: -1, body: "")
    }

    private let routes: Mutex<[String: Reply]>
    private let scripts = Mutex<[String: [Reply]]>([:])
    private let log = Mutex<[URLRequest]>([])

    /// - Parameter routes: Replies keyed by "METHOD /path". A route not in the table answers 404.
    init(_ routes: [String: Reply] = [:]) {
        self.routes = Mutex(routes)
    }

    subscript(route: String) -> Reply? {
        get { routes.withLock { $0[route] } }
        set { routes.withLock { $0[route] = newValue } }
    }

    /// Answers the next requests to a route with these replies, in order, then with the table again.
    func script(_ route: String, _ replies: [Reply]) {
        scripts.withLock { $0[route, default: []].append(contentsOf: replies) }
    }

    var requests: [URLRequest] {
        log.withLock { $0 }
    }

    /// The `clientAttemptId` of every answer sent, in order.
    var sentAttemptIDs: [String] {
        requests.filter { $0.url?.path() == "/api/attempts" }.compactMap { request in
            (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])?["clientAttemptId"] as? String
        }
    }

    /// "METHOD /path" of every request, in order.
    var calls: [String] {
        requests.map { "\($0.httpMethod ?? "?") \($0.url?.path() ?? "?")" }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        log.withLock { $0.append(request) }
        let key = "\(request.httpMethod ?? "GET") \(request.url?.path() ?? "")"
        let scripted = scripts.withLock { scripts -> Reply? in
            guard var replies = scripts[key], !replies.isEmpty else { return nil }
            let reply = replies.removeFirst()
            scripts[key] = replies
            return reply
        }
        let reply = scripted ?? routes.withLock { $0[key] } ?? .error(404, "request_refused", "Not stubbed: \(key)")
        if reply.status < 0 { throw URLError(.notConnectedToInternet) }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: nil)!
        return (Data(reply.body.utf8), response)
    }
}

/// Builds an app model around a stub server and an in-memory session store.
@MainActor
enum TestApp {
    static let token = "synthetic-test-token"

    /// - Parameters:
    ///   - storage: The phone's saved courses and unsent answers; another model made with the
    ///     same storage finds what this one left, as a relaunch does.
    ///   - connection: The phone's network path, online unless a test turns it off.
    static func make(
        _ server: StubServer,
        account: Account? = nil,
        storage: PhoneStorage = .memory(),
        connection: Connection = Connection()
    ) -> (AppModel, InMemorySessionStore) {
        let store = InMemorySessionStore(account.map { StoredSession(token: token, expiresAt: nil, account: $0) })
        let client = QBankClient(
            configuration: APIConfiguration(baseURL: URL(string: "https://stub.invalid")!),
            transport: server,
            sessionStore: store
        )
        let defaults = freshDefaults()
        let app = AppModel(
            client: client,
            look: LookStore(defaults: defaults),
            courseMemory: CourseMemory(defaults: defaults),
            storage: storage,
            connection: connection
        )
        return (app, store)
    }

    /// A defaults suite of its own, empty, so a test never reads or writes the host's settings.
    static func freshDefaults() -> UserDefaults {
        let name = "qbank-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}

/// Invented server bodies, shaped like the real routes' answers.
enum Bodies {
    static func account(role: String = "student", mustChangePassword: Bool = false) -> String {
        #"{"id":"a1","email":"student@example.com","name":"Sam Student","role":"\#(role)","mustChangePassword":\#(mustChangePassword)}"#
    }

    static func signedIn(token: String = "synthetic-new-token", mustChangePassword: Bool = false) -> String {
        #"{"token":"\#(token)","user":\#(account(mustChangePassword: mustChangePassword)),"expiresAt":"2027-01-01T00:00:00.000Z"}"#
    }

    static func session(mustChangePassword: Bool = false) -> String {
        #"{"user":\#(account(mustChangePassword: mustChangePassword)),"expiresAt":"2027-01-01T00:00:00.000Z"}"#
    }

    static func course(
        id: String, code: String, order: Int = 1, archived: Bool = false, review: Int = 0, answered: Int = 0
    ) -> String {
        #"{"id":"\#(id)","code":"\#(code)","title":"Invented \#(code)","sortOrder":\#(order),"archivedAt":\#(archived ? #""2026-01-01T00:00:00.000Z""# : "null"),"questionCount":10,"weekCount":2,"reviewCount":\#(review),"answeredCount":\#(answered),"fullyRightCount":0,"points":0,"maxPoints":0}"#
    }

    static func semester(id: String, number: Int, name: String? = nil, startsOn: String? = nil, endsOn: String? = nil, courses: [String] = []) -> String {
        let date = { (day: String?) in day.map { "\"\($0)\"" } ?? "null" }
        return #"{"id":"\#(id)","number":\#(number),"name":"\#(name ?? "Semester \(number)")","startsOn":\#(date(startsOn)),"endsOn":\#(date(endsOn)),"courses":[\#(courses.joined(separator: ","))]}"#
    }

    static func catalog(_ semesters: [String]) -> String {
        #"{"semesters":[\#(semesters.joined(separator: ","))]}"#
    }

    static func semesters(_ courses: [String] = [course(id: "c1", code: "NURS 101")]) -> String {
        #"{"semesters":[{"id":"s1","number":1,"name":"Semester 1","startsOn":null,"endsOn":null,"courses":[\#(courses.joined(separator: ","))]}]}"#
    }

    static func set(
        id: String, title: String = "Invented set", status: String = "imported", canRestore: Bool = false,
        questionIDs: [String] = ["q1", "q2"]
    ) -> String {
        let ids = questionIDs.map { "\"\($0)\"" }.joined(separator: ",")
        return #"{"id":"\#(id)","title":"\#(title)","description":"","questionCount":\#(questionIDs.count),"importedAt":"2026-10-01T00:00:00.000Z","activeSince":"2026-10-01T00:00:00.000Z","status":"\#(status)","canRestore":\#(canRestore),"answeredCount":0,"fullyRightCount":0,"lastAnsweredAt":null,"questionIds":[\#(ids)]}"#
    }

    static func courseDetail(id: String = "c1", sets: [String] = [set(id: "set1")]) -> String {
        #"{"id":"\#(id)","code":"NURS 101","title":"Invented Basics","archivedAt":null,"semester":{"id":"s1","number":1,"name":"Semester 1"},"questionCount":10,"examQuestionCount":12,"weekCount":1,"termCount":3,"reviewCount":2,"answeredCount":0,"fullyRightCount":0,"points":0,"maxPoints":0,"weeks":[{"label":"Week 1","sets":[\#(sets.joined(separator: ","))],"examBankCount":2}]}"#
    }

    /// The semesters of a `semesters` or `catalog` body.
    static func decodeSemesters(_ body: String) throws -> [Semester] {
        struct Response: Decodable { let semesters: [Semester] }
        return try QBankJSON.decoder.decode(Response.self, from: Data(body.utf8)).semesters
    }

    static func place(_ courseID: String?) -> String {
        #"{"courseId":\#(courseID.map { "\"\($0)\"" } ?? "null")}"#
    }
}

extension Account {
    static func student(mustChangePassword: Bool = false) -> Account {
        Account(id: "a1", email: "student@example.com", name: "Sam Student", role: .student, mustChangePassword: mustChangePassword)
    }

    static let admin = Account(id: "a2", email: "owner@example.com", name: "Owner", role: .admin, mustChangePassword: false)
}

/// Waits for something the app does in the background, such as sending answers when the
/// connection returns.
@MainActor
func waitUntil(timeout: Duration = .seconds(5), _ condition: () -> Bool) async throws {
    struct TimedOut: Error {}
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while !condition() {
        guard clock.now < deadline else { throw TimedOut() }
        try await Task.sleep(for: .milliseconds(10))
    }
}

/// A value a test shares with closures the app may call from any thread, such as its clock.
final class Locked<Value: Sendable>: Sendable {
    private let mutex: Mutex<Value>

    init(_ value: Value) {
        mutex = Mutex(value)
    }

    var value: Value {
        get { mutex.withLock { $0 } }
        set { mutex.withLock { $0 = newValue } }
    }
}
