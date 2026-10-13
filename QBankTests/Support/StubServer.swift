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
    private let log = Mutex<[URLRequest]>([])

    /// - Parameter routes: Replies keyed by "METHOD /path". A route not in the table answers 404.
    init(_ routes: [String: Reply] = [:]) {
        self.routes = Mutex(routes)
    }

    subscript(route: String) -> Reply? {
        get { routes.withLock { $0[route] } }
        set { routes.withLock { $0[route] = newValue } }
    }

    var requests: [URLRequest] {
        log.withLock { $0 }
    }

    /// "METHOD /path" of every request, in order.
    var calls: [String] {
        requests.map { "\($0.httpMethod ?? "?") \($0.url?.path() ?? "?")" }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        log.withLock { $0.append(request) }
        let key = "\(request.httpMethod ?? "GET") \(request.url?.path() ?? "")"
        let reply = routes.withLock { $0[key] } ?? .error(404, "request_refused", "Not stubbed: \(key)")
        if reply.status < 0 { throw URLError(.notConnectedToInternet) }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: nil)!
        return (Data(reply.body.utf8), response)
    }
}

/// Builds an app model around a stub server and an in-memory session store.
@MainActor
enum TestApp {
    static let token = "synthetic-test-token"

    static func make(_ server: StubServer, account: Account? = nil) -> (AppModel, InMemorySessionStore) {
        let store = InMemorySessionStore(account.map { StoredSession(token: token, expiresAt: nil, account: $0) })
        let client = QBankClient(
            configuration: APIConfiguration(baseURL: URL(string: "https://stub.invalid")!),
            transport: server,
            sessionStore: store
        )
        return (AppModel(client: client, look: LookStore(defaults: freshDefaults())), store)
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

    static func set(id: String, title: String = "Invented set", status: String = "imported", canRestore: Bool = false) -> String {
        #"{"id":"\#(id)","title":"\#(title)","description":"","questionCount":2,"importedAt":"2026-10-01T00:00:00.000Z","activeSince":"2026-10-01T00:00:00.000Z","status":"\#(status)","canRestore":\#(canRestore),"answeredCount":0,"fullyRightCount":0,"lastAnsweredAt":null,"questionIds":["q1","q2"]}"#
    }

    static func courseDetail(id: String = "c1", sets: [String] = [set(id: "set1")]) -> String {
        #"{"id":"\#(id)","code":"NURS 101","title":"Invented Basics","archivedAt":null,"semester":{"id":"s1","number":1,"name":"Semester 1"},"questionCount":10,"examQuestionCount":12,"weekCount":1,"termCount":3,"reviewCount":2,"answeredCount":0,"fullyRightCount":0,"points":0,"maxPoints":0,"weeks":[{"label":"Week 1","sets":[\#(sets.joined(separator: ","))],"examBankCount":2}]}"#
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
