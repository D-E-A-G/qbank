#if DEBUG
import Foundation
import QBankKit
import Synchronization

/// An in-process stand-in for the QBank server, for UI tests and simulator review. It answers the
/// slice-1a calls with invented accounts and courses, the way the real routes answer them, so the
/// app runs end to end through `QBankClient` without a network or a real account.
nonisolated final class FakeQBankServer: HTTPTransport {
    struct Credentials {
        let email: String
        let password: String
    }

    /// A student who signs in normally and lands on the course she used last.
    static let student = Credentials(email: "student@example.com", password: "synthetic-pass-1")
    /// A student whose password the owner reset: she must choose a new one.
    static let resetStudent = Credentials(email: "reset@example.com", password: "synthetic-temp-1")
    static let sessionToken = "synthetic-session-token"

    static let mentalHealthID = "8d7b4f0e-0000-4000-8000-000000000310"
    static let fundamentalsID = "8d7b4f0e-0000-4000-8000-000000000220"

    private struct Account {
        let id: String
        let email: String
        let name: String
        var password: String
        var mustChangePassword: Bool

        var json: [String: Any] {
            ["id": id, "email": email, "name": name, "role": "student", "mustChangePassword": mustChangePassword]
        }
    }

    private struct State {
        var accounts: [Account]
        /// Bearer token to account email.
        var sessions: [String: String]
        var place: String?
        var psychosocialRestored = false
        var tokenCount = 0
    }

    private let state: Mutex<State>
    private let now: Date

    /// - Parameters:
    ///   - signedIn: Starts with `student`'s session, as `sessionToken`.
    ///   - place: The course she used last, or nil for none.
    init(signedIn: Bool, place: String? = FakeQBankServer.mentalHealthID, now: Date = .now) {
        self.now = now
        state = Mutex(State(
            accounts: [
                Account(id: "fake-student", email: Self.student.email, name: "Sam Student", password: Self.student.password, mustChangePassword: false),
                Account(id: "fake-reset", email: Self.resetStudent.email, name: "Robin Reset", password: Self.resetStudent.password, mustChangePassword: true),
            ],
            sessions: signedIn ? [Self.sessionToken: Self.student.email] : [:],
            place: place
        ))
    }

    /// The session the app keeps for `student` when a scenario starts signed in.
    static func storedStudentSession(expiresAt: Date = .now.addingTimeInterval(30 * 86_400)) -> StoredSession {
        StoredSession(
            token: sessionToken,
            expiresAt: expiresAt,
            account: QBankKit.Account(id: "fake-student", email: student.email, name: "Sam Student", role: .student, mustChangePassword: false)
        )
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url ?? URL(string: "https://fake.invalid")!
        let (status, body) = answer(
            method: request.httpMethod ?? "GET",
            path: url.path(),
            token: request.value(forHTTPHeaderField: "Authorization")?.replacingOccurrences(of: "Bearer ", with: ""),
            body: request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        )
        let data = try JSONSerialization.data(withJSONObject: body)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        return (data, response)
    }

    private typealias Reply = (Int, [String: Any])

    private func answer(method: String, path: String, token: String?, body: [String: Any]) -> Reply {
        if method == "POST", path == "/api/sign-in/password" {
            return signIn(email: body["email"] as? String ?? "", password: body["password"] as? String ?? "")
        }
        guard let token, let account = account(for: token) else {
            return failure(401, "unauthenticated", "Sign in to continue.")
        }
        switch (method, path) {
        case ("GET", "/api/session"):
            return (200, ["user": account.json, "expiresAt": date(days: 30)])
        case ("POST", "/api/sign-out"):
            state.withLock { _ = $0.sessions.removeValue(forKey: token) }
            return (200, ["status": "ok"])
        case ("POST", "/api/account/password"):
            return changePassword(account, token: token, current: body["currentPassword"] as? String ?? "", new: body["newPassword"] as? String ?? "")
        default:
            break
        }
        if account.mustChangePassword {
            return failure(403, "must_change_password", "Choose a new password to continue.")
        }
        switch (method, path) {
        case ("GET", "/api/semesters"):
            return (200, ["semesters": semesters()])
        case ("GET", "/api/me/place"):
            return (200, ["courseId": json(state.withLock { $0.place })])
        case ("PUT", "/api/me/place"):
            let place = body["courseId"] as? String
            state.withLock { $0.place = place }
            return (200, ["courseId": json(place)])
        case ("GET", "/api/courses/\(Self.mentalHealthID)"):
            return (200, mentalHealth())
        case ("GET", "/api/courses/\(Self.fundamentalsID)"):
            return (200, fundamentals())
        case ("POST", "/api/practice-sets/psychosocial-v2/restore"):
            let restored = state.withLock { state -> Bool in
                defer { state.psychosocialRestored = true }
                return state.psychosocialRestored
            }
            if restored { return failure(404, "request_refused", "That set is not the current version.") }
            return (200, psychosocial())
        default:
            return failure(404, "request_refused", "That is not in the app.")
        }
    }

    // MARK: Accounts

    private func account(for token: String) -> Account? {
        state.withLock { state in
            state.sessions[token].flatMap { email in state.accounts.first { $0.email == email } }
        }
    }

    private func signIn(email: String, password: String) -> Reply {
        let normalized = email.lowercased()
        let signedIn = state.withLock { state -> (String, Account)? in
            guard let account = state.accounts.first(where: { $0.email == normalized && $0.password == password }) else { return nil }
            state.tokenCount += 1
            let token = state.tokenCount == 1 ? Self.sessionToken : "\(Self.sessionToken)-\(state.tokenCount)"
            state.sessions[token] = account.email
            return (token, account)
        }
        guard let (token, account) = signedIn else {
            return failure(401, "invalid_credentials", "That email or password is not right.")
        }
        return (200, ["token": token, "user": account.json, "expiresAt": date(days: 30)])
    }

    private func changePassword(_ account: Account, token: String, current: String, new: String) -> Reply {
        guard current == account.password else {
            return failure(401, "invalid_credentials", "That password is not right.")
        }
        guard new != current else {
            return failure(400, "same_password", "Choose a password different from the temporary one.")
        }
        guard new.count >= 8 else {
            return failure(400, "request_refused", "Choose a password of at least 8 characters.")
        }
        let (fresh, updated) = state.withLock { state -> (String, Account) in
            let index = state.accounts.firstIndex { $0.email == account.email }!
            state.accounts[index].password = new
            state.accounts[index].mustChangePassword = false
            state.tokenCount += 1
            let fresh = "\(Self.sessionToken)-\(state.tokenCount)"
            state.sessions = state.sessions.filter { $0.value != account.email }
            state.sessions[fresh] = account.email
            return (fresh, state.accounts[index])
        }
        return (200, ["token": fresh, "user": updated.json, "expiresAt": date(days: 30)])
    }

    // MARK: Courses

    private func semesters() -> [[String: Any]] {
        [
            [
                "id": "fake-semester-1", "number": 1, "name": "Semester 1", "startsOn": NSNull(), "endsOn": NSNull(),
                "courses": [
                    courseSummary(id: Self.mentalHealthID, code: "NURS 310", title: "Mental Health", order: 1,
                                  questions: 86, weeks: 3, review: 12, answered: 35, right: 24, points: 61, max: 92),
                    courseSummary(id: Self.fundamentalsID, code: "NURS 220", title: "Fundamentals", order: 2,
                                  questions: 146, weeks: 3, review: 5, answered: 92, right: 70, points: 131, max: 170),
                ],
            ],
            ["id": "fake-semester-2", "number": 2, "name": "Semester 2", "startsOn": NSNull(), "endsOn": NSNull(), "courses": []],
        ]
    }

    private func courseSummary(
        id: String, code: String, title: String, order: Int,
        questions: Int, weeks: Int, review: Int, answered: Int, right: Int, points: Int, max: Int
    ) -> [String: Any] {
        [
            "id": id, "code": code, "title": title, "sortOrder": order, "archivedAt": NSNull(),
            "questionCount": questions, "weekCount": weeks, "reviewCount": review,
            "answeredCount": answered, "fullyRightCount": right, "points": points, "maxPoints": max,
        ]
    }

    private func mentalHealth() -> [String: Any] {
        [
            "id": Self.mentalHealthID, "code": "NURS 310", "title": "Mental Health", "archivedAt": NSNull(),
            "semester": ["id": "fake-semester-1", "number": 1, "name": "Semester 1"],
            "questionCount": 86, "examQuestionCount": 134, "weekCount": 3, "termCount": 180, "reviewCount": 12,
            "answeredCount": 35, "fullyRightCount": 24, "points": 61, "maxPoints": 92,
            "weeks": [
                week("Week 1", bank: 17, sets: [
                    set("rights-v1", "Rights, Law, and Ethics", questions: 17, daysAgo: 20,
                        answered: 17, right: 13, lastAnsweredDaysAgo: 9),
                ]),
                week("Week 2", bank: 0, sets: [
                    set("communication-v1", "Therapeutic Communication and the Relationship", questions: 14, daysAgo: 12, answered: 9, right: 6),
                    psychosocial(),
                ]),
                week("Week 3", bank: 31, sets: [
                    set("depression-v1", "Depression and Antidepressants", questions: 18, daysAgo: 0),
                    set("anxiety-v1", "Anxiety, Panic, and Anxiolytics", questions: 13, daysAgo: 0),
                ]),
                week("Weeks 1-3", bank: 0, sets: [
                    set("mixed-v1", "Mixed Clinical Judgment", questions: 12, daysAgo: 4),
                ]),
            ],
        ]
    }

    private func fundamentals() -> [String: Any] {
        [
            "id": Self.fundamentalsID, "code": "NURS 220", "title": "Fundamentals", "archivedAt": NSNull(),
            "semester": ["id": "fake-semester-1", "number": 1, "name": "Semester 1"],
            "questionCount": 146, "examQuestionCount": 146, "weekCount": 3, "termCount": 212, "reviewCount": 5,
            "answeredCount": 92, "fullyRightCount": 70, "points": 131, "maxPoints": 170,
            "weeks": [
                week("Week 1", bank: 0, sets: [set("vitals-v1", "Vital Signs Under Pressure", questions: 43, daysAgo: 30, answered: 43, right: 35)]),
                week("Week 2", bank: 0, sets: [set("safety-v1", "Safety and Infection Control", questions: 42, daysAgo: 22, answered: 42, right: 30)]),
                week("Week 3", bank: 0, sets: [set("mobility-v1", "Mobility and Skin Integrity", questions: 61, daysAgo: 8, answered: 7, right: 5)]),
            ],
        ]
    }

    /// The Week 2 set that was replaced, until she restores its previous version.
    private func psychosocial() -> [String: Any] {
        let restored = state.withLock { $0.psychosocialRestored }
        return restored
            ? set("psychosocial-v1", "Psychosocial Assessment and Safety Screening", questions: 12, daysAgo: 0, status: "restored", canRestore: true)
            : set("psychosocial-v2", "Psychosocial Assessment and Safety Screening", questions: 12, daysAgo: 6, status: "replaced", canRestore: true)
    }

    private func week(_ label: String, bank: Int, sets: [[String: Any]]) -> [String: Any] {
        ["label": label, "sets": sets, "examBankCount": bank]
    }

    private func set(
        _ id: String, _ title: String, questions: Int, daysAgo: Int,
        status: String = "imported", canRestore: Bool = false,
        answered: Int = 0, right: Int = 0, lastAnsweredDaysAgo: Int? = nil
    ) -> [String: Any] {
        [
            "id": id, "title": title, "description": "", "questionCount": questions,
            "importedAt": date(days: -daysAgo), "activeSince": date(days: -daysAgo),
            "status": status, "canRestore": canRestore,
            "answeredCount": answered, "fullyRightCount": right,
            "lastAnsweredAt": json(answered == 0 ? nil : date(days: -(lastAnsweredDaysAgo ?? 1))),
            "questionIds": (0..<questions).map { "\(id)-q\($0)" },
        ]
    }

    // MARK: Plumbing

    private func date(days: Int) -> String {
        QBankJSON.formatDate(now.addingTimeInterval(TimeInterval(days) * 86_400))
    }

    /// A JSON value that is null when nil.
    private func json(_ value: String?) -> Any {
        value.map { $0 as Any } ?? NSNull()
    }

    private func failure(_ status: Int, _ code: String, _ message: String) -> Reply {
        (status, ["error": code, "message": message])
    }
}
#endif
