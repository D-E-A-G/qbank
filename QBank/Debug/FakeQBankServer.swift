#if DEBUG
import Foundation
import QBankKit
import Synchronization

/// An in-process stand-in for the QBank server, for UI tests and simulator review. It answers the
/// app's calls with invented accounts, courses and questions, the way the real routes answer them,
/// and scores answers with the server's rules, so the app runs end to end through `QBankClient`
/// without a network or a real account.
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
    static let semester1ID = "8d7b4f0e-0000-4000-8000-000000000001"
    static let semester2ID = "8d7b4f0e-0000-4000-8000-000000000002"

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

    private struct FakeSemester {
        let id: String
        let number: Int
        var name: String
        var startsOn: String?
        var endsOn: String?
    }

    /// A course with the counts Home shows. Courses added in Settings start at zero.
    private struct FakeCourse {
        let id: String
        var semesterID: String
        var code: String
        var title: String
        var sortOrder: Int
        var archivedAt: String?
        var questions = 0, weeks = 0, review = 0, answered = 0, right = 0, points = 0, maxPoints = 0
    }

    private struct State {
        var accounts: [Account]
        var semesters: [FakeSemester]
        var courses: [FakeCourse]
        /// Bearer token to account email.
        var sessions: [String: String]
        var place: String?
        var psychosocialRestored = false
        var tokenCount = 0
        /// Saved answers by `clientAttemptId`, so a repeated send is answered with the saved one.
        var attempts: [String: Data] = [:]
        /// Her latest answer to each question: (status, answered at).
        var latest: [String: (status: String, at: Date)] = [:]
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
            semesters: [
                FakeSemester(id: Self.semester1ID, number: 1, name: "Semester 1"),
                FakeSemester(id: Self.semester2ID, number: 2, name: "Semester 2"),
            ],
            courses: [
                FakeCourse(id: Self.mentalHealthID, semesterID: Self.semester1ID, code: "NURS 310", title: "Mental Health", sortOrder: 1,
                           questions: 86, weeks: 3, review: 12, answered: 35, right: 24, points: 61, maxPoints: 92),
                FakeCourse(id: Self.fundamentalsID, semesterID: Self.semester1ID, code: "NURS 220", title: "Fundamentals", sortOrder: 2,
                           questions: 146, weeks: 3, review: 5, answered: 92, right: 70, points: 131, maxPoints: 170),
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
            body: request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:],
            rawBody: request.httpBody
        )
        let data = try JSONSerialization.data(withJSONObject: body)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        return (data, response)
    }

    private typealias Reply = (Int, [String: Any])

    private func answer(method: String, path: String, token: String?, body: [String: Any], rawBody: Data?) -> Reply {
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
        case ("POST", "/api/semesters"):
            return addSemester(number: body["number"] as? Int)
        case ("POST", "/api/courses"):
            return addCourse(semesterID: body["semesterId"] as? String ?? "", code: body["code"] as? String ?? "", title: body["title"] as? String ?? "")
        case ("PATCH", _) where path.hasPrefix("/api/semesters/"):
            return updateSemester(id: String(path.dropFirst("/api/semesters/".count)), body: body)
        case ("PATCH", _) where path.hasPrefix("/api/courses/"):
            return updateCourse(id: String(path.dropFirst("/api/courses/".count)), body: body)
        case ("GET", "/api/me/place"):
            return (200, ["courseId": json(state.withLock { $0.place })])
        case ("PUT", "/api/me/place"):
            let place = body["courseId"] as? String
            state.withLock { $0.place = place }
            return (200, ["courseId": json(place)])
        case ("GET", "/api/courses/\(Self.mentalHealthID)"):
            return (200, mentalHealth().merging(stored(Self.mentalHealthID)) { _, edited in edited })
        case ("GET", "/api/courses/\(Self.fundamentalsID)"):
            return (200, fundamentals().merging(stored(Self.fundamentalsID)) { _, edited in edited })
        case ("POST", "/api/practice-sets/psychosocial-v2/restore"):
            let restored = state.withLock { state -> Bool in
                defer { state.psychosocialRestored = true }
                return state.psychosocialRestored
            }
            if restored { return failure(404, "request_refused", "That set is not the current version.") }
            return (200, psychosocial())
        case ("POST", "/api/attempts"):
            return recordAttempt(rawBody)
        default:
            break
        }
        if method == "GET", path.hasPrefix("/api/practice-sets/") {
            return practiceSet(id: String(path.dropFirst("/api/practice-sets/".count)))
        }
        return failure(404, "request_refused", "That is not in the app.")
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
        // The real route's order: the fields' rules, then the same password, then the current one.
        guard !current.isEmpty, (8...128).contains(new.utf16.count) else {
            return failure(400, "invalid_request", "Check the fields and try again.")
        }
        guard new != current else {
            return failure(400, "same_password", "Choose a password that is different from the temporary one.")
        }
        guard current == account.password else {
            return failure(401, "invalid_credentials", "That password is not right.")
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
        state.withLock { state in
            state.semesters.sorted { $0.number < $1.number }.map { semester in
                semesterJSON(semester, courses: state.courses)
            }
        }
    }

    private func semesterJSON(_ semester: FakeSemester, courses: [FakeCourse]) -> [String: Any] {
        [
            "id": semester.id, "number": semester.number, "name": semester.name,
            "startsOn": json(semester.startsOn), "endsOn": json(semester.endsOn),
            "courses": courses.filter { $0.semesterID == semester.id }.sorted { $0.sortOrder < $1.sortOrder }.map(courseJSON),
        ]
    }

    private func courseJSON(_ course: FakeCourse) -> [String: Any] {
        [
            "id": course.id, "code": course.code, "title": course.title, "sortOrder": course.sortOrder,
            "archivedAt": json(course.archivedAt),
            "questionCount": course.questions, "weekCount": course.weeks, "reviewCount": course.review,
            "answeredCount": course.answered, "fullyRightCount": course.right, "points": course.points, "maxPoints": course.maxPoints,
        ]
    }

    // MARK: Editing semesters and courses, with the content service's rules and words

    private func addSemester(number: Int?) -> Reply {
        guard let number, (1...3).contains(number) else {
            return failure(400, "request_refused", "A semester is 1, 2, or 3.")
        }
        return state.withLock { state -> Reply in
            guard !state.semesters.contains(where: { $0.number == number }) else {
                return failure(409, "request_refused", "Semester \(number) already exists.")
            }
            let semester = FakeSemester(id: "8d7b4f0e-0000-4000-8000-00000000000\(number)", number: number, name: "Semester \(number)")
            state.semesters.append(semester)
            return (201, semesterJSON(semester, courses: state.courses))
        }
    }

    private func updateSemester(id: String, body: [String: Any]) -> Reply {
        state.withLock { state -> Reply in
            guard let index = state.semesters.firstIndex(where: { $0.id == id }) else {
                return failure(404, "request_refused", "That semester is not in the app.")
            }
            var semester = state.semesters[index]
            if let name = body["name"] as? String {
                guard let text = requiredText(name, label: "Semester name", maxLength: 80) else {
                    return failure(400, "request_refused", textProblem(name, label: "Semester name"))
                }
                semester.name = text
            }
            for (key, label) in [("startsOn", "Start date"), ("endsOn", "End date")] where body.keys.contains(key) {
                let value = body[key] as? String
                if let value, !value.isEmpty, value.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) == nil {
                    return failure(400, "request_refused", "\(label) has to be a date like 2026-09-01.")
                }
                let date = value?.isEmpty == false ? value : nil
                if key == "startsOn" { semester.startsOn = date } else { semester.endsOn = date }
            }
            state.semesters[index] = semester
            return (200, semesterJSON(semester, courses: state.courses))
        }
    }

    private func addCourse(semesterID: String, code: String, title: String) -> Reply {
        state.withLock { state -> Reply in
            guard state.semesters.contains(where: { $0.id == semesterID }) else {
                return failure(404, "request_refused", "That semester is not in the app.")
            }
            guard let code = requiredText(code, label: "Course code", maxLength: 32) else {
                return failure(400, "request_refused", textProblem(code, label: "Course code"))
            }
            guard let title = requiredText(title, label: "Course name", maxLength: 160) else {
                return failure(400, "request_refused", textProblem(title, label: "Course name"))
            }
            if let taken = codeTaken(code, in: semesterID, except: nil, courses: state.courses) { return taken }
            state.tokenCount += 1
            let order = (state.courses.filter { $0.semesterID == semesterID }.map(\.sortOrder).max() ?? 0) + 1
            let course = FakeCourse(
                id: String(format: "8d7b4f0e-0000-4000-8000-%012d", 900 + state.tokenCount),
                semesterID: semesterID, code: code, title: title, sortOrder: order
            )
            state.courses.append(course)
            return (201, courseJSON(course))
        }
    }

    private func updateCourse(id: String, body: [String: Any]) -> Reply {
        state.withLock { state -> Reply in
            guard let index = state.courses.firstIndex(where: { $0.id == id }) else {
                return failure(404, "request_refused", "That course is not in the app.")
            }
            var course = state.courses[index]
            if let code = body["code"] as? String {
                guard let text = requiredText(code, label: "Course code", maxLength: 32) else {
                    return failure(400, "request_refused", textProblem(code, label: "Course code"))
                }
                course.code = text
            }
            if let title = body["title"] as? String {
                guard let text = requiredText(title, label: "Course name", maxLength: 160) else {
                    return failure(400, "request_refused", textProblem(title, label: "Course name"))
                }
                course.title = text
            }
            if let semesterID = body["semesterId"] as? String, semesterID != course.semesterID {
                guard state.semesters.contains(where: { $0.id == semesterID }) else {
                    return failure(404, "request_refused", "That semester is not in the app.")
                }
                course.semesterID = semesterID
                course.sortOrder = (state.courses.filter { $0.semesterID == semesterID }.map(\.sortOrder).max() ?? 0) + 1
            }
            if let taken = codeTaken(course.code, in: course.semesterID, except: id, courses: state.courses) { return taken }
            if let archived = body["archived"] as? Bool {
                course.archivedAt = archived ? QBankJSON.formatDate(.now) : nil
            }
            state.courses[index] = course
            return (200, courseJSON(course))
        }
    }

    private func requiredText(_ value: String, label: String, maxLength: Int) -> String? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty || text.count > maxLength ? nil : text
    }

    private func textProblem(_ value: String, label: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "\(label) is required." : "\(label) is too long."
    }

    private func codeTaken(_ code: String, in semesterID: String, except id: String?, courses: [FakeCourse]) -> Reply? {
        let taken = courses.contains { $0.semesterID == semesterID && $0.id != id && $0.code.lowercased() == code.lowercased() }
        return taken ? failure(409, "request_refused", "This semester already has a course with the code \(code).") : nil
    }

    /// The fields a course's detail shares with Settings, which can rename and move it.
    private func stored(_ id: String) -> [String: Any] {
        state.withLock { state in
            let course = state.courses.first { $0.id == id }!
            let semester = state.semesters.first { $0.id == course.semesterID }!
            return [
                "id": course.id, "code": course.code, "title": course.title, "archivedAt": json(course.archivedAt),
                "semester": ["id": semester.id, "number": semester.number, "name": semester.name],
            ]
        }
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
                    set("mixed-v1", "Mixed Clinical Judgment", questions: 8, daysAgo: 4),
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
        let questionIDs = (0..<questions).map { "\(id)-q\($0)" }
        // Once she answers here, the set's line counts her answers, as the server's does.
        let latest = state.withLock { state in questionIDs.compactMap { state.latest[$0] } }
        if !latest.isEmpty {
            return [
                "id": id, "title": title, "description": "", "questionCount": questions,
                "importedAt": date(days: -daysAgo), "activeSince": date(days: -daysAgo),
                "status": status, "canRestore": canRestore,
                "answeredCount": latest.count, "fullyRightCount": latest.count { $0.status == "correct" },
                "lastAnsweredAt": QBankJSON.formatDate(latest.map(\.at).max() ?? now),
                "questionIds": questionIDs,
            ]
        }
        return [
            "id": id, "title": title, "description": "", "questionCount": questions,
            "importedAt": date(days: -daysAgo), "activeSince": date(days: -daysAgo),
            "status": status, "canRestore": canRestore,
            "answeredCount": answered, "fullyRightCount": right,
            "lastAnsweredAt": json(answered == 0 ? nil : date(days: -(lastAnsweredDaysAgo ?? 1))),
            "questionIds": (0..<questions).map { "\(id)-q\($0)" },
        ]
    }

    // MARK: Practice

    /// A set of the Mental Health course, its questions drawn from `FakePracticeQuestions`.
    private func practiceSet(id: String) -> Reply {
        let found = (mentalHealth()["weeks"] as? [[String: Any]] ?? []).lazy.compactMap { week -> ([String: Any], String)? in
            guard let sets = week["sets"] as? [[String: Any]], let set = sets.first(where: { $0["id"] as? String == id }) else { return nil }
            return (set, week["label"] as? String ?? "")
        }.first
        guard let (set, weekLabel) = found, let count = set["questionCount"] as? Int else {
            return failure(404, "request_refused", "That set is not in the app.")
        }
        return (200, [
            "id": id, "courseId": Self.mentalHealthID, "title": set["title"] as? String ?? "", "weekLabel": weekLabel,
            "kind": "practice",
            "questions": (0..<count).map { FakePracticeQuestions.question(setID: id, index: $0) },
        ])
    }

    /// Scores an answer with the server's rules and saves it. A repeated `clientAttemptId` gets the
    /// saved attempt back with `replayed`, as on the server.
    private func recordAttempt(_ rawBody: Data?) -> Reply {
        guard let rawBody, let submission = try? JSONDecoder().decode(FakeSubmission.self, from: rawBody) else {
            return failure(400, "invalid_request", "That answer could not be read.")
        }
        if let data = state.withLock({ $0.attempts[submission.clientAttemptId] }),
           var saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            saved["replayed"] = true
            return (200, saved)
        }
        guard let template = FakePracticeQuestions.template(forQuestionID: submission.questionId),
              let data = try? JSONSerialization.data(withJSONObject: template.merging(
                  ["id": submission.questionId, "publicId": "Q", "position": 1], uniquingKeysWith: { $1 })),
              let question = try? QBankJSON.decoder.decode(Question.self, from: data) else {
            return failure(404, "request_refused", "That question is not in the app.")
        }
        let score: Score
        do {
            score = try Scoring.score(question.body, response: submission.response)
        } catch {
            return failure(400, "invalid_request", error.message)
        }
        let answeredAt = Date.now
        let saved: [String: Any] = [
            "clientAttemptId": submission.clientAttemptId, "questionId": submission.questionId, "courseId": Self.mentalHealthID,
            "status": score.status.rawValue, "points": score.points, "maxPoints": score.maxPoints,
            "guessed": submission.guessed, "answeredAt": QBankJSON.formatDate(answeredAt),
            "inReview": score.staysInReview(guessed: submission.guessed), "label": score.label, "replayed": false,
        ]
        let record = (try? JSONSerialization.data(withJSONObject: saved)) ?? Data()
        let status = score.status.rawValue
        state.withLock { state in
            state.attempts[submission.clientAttemptId] = record
            state.latest[submission.questionId] = (status, answeredAt)
        }
        return (201, saved)
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

/// The parts of `POST /api/attempts` the fake server reads.
private nonisolated struct FakeSubmission: Decodable {
    let clientAttemptId: String
    let questionId: String
    let response: AnswerResponse
    let guessed: Bool
}
#endif
