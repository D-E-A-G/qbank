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
        var questions = 0, folders = 0, review = 0, answered = 0, right = 0, points = 0, maxPoints = 0
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
    private let offline = Mutex(false)
    /// Review, Terms, exams and the course's exams.
    private let study: FakeStudy

    /// Without signal, every call fails before it reaches the server, as on a phone with no network.
    var isOffline: Bool {
        get { offline.withLock { $0 } }
        set { offline.withLock { $0 = newValue } }
    }

    /// - Parameters:
    ///   - signedIn: Starts with `student`'s session, as `sessionToken`.
    ///   - place: The course she used last, or nil for none.
    init(signedIn: Bool, place: String? = FakeQBankServer.mentalHealthID, now: Date = .now) {
        self.now = now
        study = FakeStudy(now: now)
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
                           questions: 86, folders: 4, review: 12, answered: 35, right: 24, points: 61, maxPoints: 92),
                FakeCourse(id: Self.fundamentalsID, semesterID: Self.semester1ID, code: "NURS 220", title: "Fundamentals", sortOrder: 2,
                           questions: 146, folders: 3, review: 5, answered: 92, right: 70, points: 131, maxPoints: 170),
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
        if isOffline { throw URLError(.notConnectedToInternet) }
        let url = request.url ?? URL(string: "https://fake.invalid")!
        let query = (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            .reduce(into: [String: String]()) { $0[$1.name] = $1.value ?? "" }
        let (status, body) = answer(
            method: request.httpMethod ?? "GET",
            path: url.path(),
            query: query,
            token: request.value(forHTTPHeaderField: "Authorization")?.replacingOccurrences(of: "Bearer ", with: ""),
            body: request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:],
            rawBody: request.httpBody
        )
        // A 204 has no body, as the server sends it.
        let data = status == 204 ? Data() : try JSONSerialization.data(withJSONObject: body)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        return (data, response)
    }

    private typealias Reply = (Int, [String: Any])

    private func answer(method: String, path: String, query: [String: String], token: String?, body: [String: Any], rawBody: Data?) -> Reply {
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
            return (200, mentalHealth().merging(stored(Self.mentalHealthID)) { _, edited in edited }.merging(studied(Self.mentalHealthID)) { _, now in now })
        case ("GET", "/api/courses/\(Self.fundamentalsID)"):
            return (200, fundamentals().merging(stored(Self.fundamentalsID)) { _, edited in edited }.merging(studied(Self.fundamentalsID)) { _, now in now })
        case ("POST", "/api/practice-sets/psychosocial-v2/restore"):
            let restored = state.withLock { state -> Bool in
                defer { state.psychosocialRestored = true }
                return state.psychosocialRestored
            }
            if restored { return failure(404, "request_refused", "That set is not the current version.") }
            study.replace(set: "psychosocial-v2", with: "psychosocial-v1")
            return (200, set("psychosocial-v1"))
        case ("POST", "/api/attempts"):
            return recordAttempt(rawBody)
        default:
            break
        }
        if method == "GET", path.hasPrefix("/api/practice-sets/") {
            return practiceSet(id: String(path.dropFirst("/api/practice-sets/".count)))
        }
        if let reply = study.answer(method: method, path: path, query: query, body: body, folderJSON: folderJSON) {
            return reply
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
                semesterJSON(semester, courses: state.courses, latest: state.latest)
            }
        }
    }

    private func semesterJSON(_ semester: FakeSemester, courses: [FakeCourse], latest: [String: (status: String, at: Date)]) -> [String: Any] {
        [
            "id": semester.id, "number": semester.number, "name": semester.name,
            "startsOn": json(semester.startsOn), "endsOn": json(semester.endsOn),
            "courses": courses.filter { $0.semesterID == semester.id }.sorted { $0.sortOrder < $1.sortOrder }.map { courseJSON($0, latest: latest) },
        ]
    }

    private func courseJSON(_ course: FakeCourse, latest: [String: (status: String, at: Date)]) -> [String: Any] {
        let added = Self.added(courseID: course.id, latest: latest)
        // The two studied courses count the folders she has now; the others, their invented count.
        let folders = FakeStudy.codes[course.id] == nil ? nil : study.folders(course.id)
        return [
            "id": course.id, "code": course.code, "title": course.title, "sortOrder": course.sortOrder,
            "archivedAt": json(course.archivedAt),
            "questionCount": course.questions,
            "weekCount": folders.map { Set($0.filter { !$0.sets.isEmpty }.map(\.name)).count } ?? course.folders,
            "folderCount": folders?.count ?? course.folders,
            "reviewCount": FakeStudy.codes[course.id] == nil ? course.review : study.reviewCount(course.id),
            "answeredCount": course.answered + added.answered, "fullyRightCount": course.right + added.right,
            "points": course.points, "maxPoints": course.maxPoints,
        ]
    }

    /// Progress she made before the scenario starts, by set: questions answered, fully right, and
    /// days since her last answer.
    private static let earlierProgress: [String: (answered: Int, right: Int, lastAnsweredDaysAgo: Int)] = [
        "rights-v1": (17, 13, 9),
        "communication-v1": (9, 6, 1),
        "vitals-v1": (43, 35, 1),
        "safety-v1": (42, 30, 1),
        "mobility-v1": (7, 5, 1),
    ]

    /// Every set of each course, in all its versions.
    private static let setsByCourse: [String: Set<String>] = [
        mentalHealthID: ["rights-v1", "communication-v1", "psychosocial-v1", "psychosocial-v2", "depression-v1", "anxiety-v1", "mixed-v1"],
        fundamentalsID: ["vitals-v1", "safety-v1", "mobility-v1"],
    ]

    /// What her answers here add to a course's invented counts. A set she answered here counts her
    /// answers instead of its earlier progress, as the set's own line does.
    private static func added(courseID: String, latest: [String: (status: String, at: Date)]) -> (answered: Int, right: Int) {
        let sets = setsByCourse[courseID] ?? []
        var bySet: [String: [String]] = [:]
        for (questionID, answer) in latest {
            let setID = questionID.split(separator: "-").dropLast().joined(separator: "-")
            if sets.contains(setID) {
                bySet[setID, default: []].append(answer.status)
            }
        }
        return bySet.reduce(into: (0, 0)) { total, entry in
            let earlier = earlierProgress[entry.key]
            total.0 += entry.value.count - (earlier?.answered ?? 0)
            total.1 += entry.value.count { $0 == "correct" } - (earlier?.right ?? 0)
        }
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
            return (201, semesterJSON(semester, courses: state.courses, latest: state.latest))
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
            return (200, semesterJSON(semester, courses: state.courses, latest: state.latest))
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
            return (201, courseJSON(course, latest: state.latest))
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
            return (200, courseJSON(course, latest: state.latest))
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

    /// What a course's detail says about her study: its exams, and her Review and terms counts.
    private func studied(_ id: String) -> [String: Any] {
        ["exams": study.courseExamsJSON(id), "reviewCount": study.reviewCount(id), "termCount": study.termCount(id)]
    }

    private func mentalHealth() -> [String: Any] {
        let added = state.withLock { Self.added(courseID: Self.mentalHealthID, latest: $0.latest) }
        return [
            "id": Self.mentalHealthID, "code": "NURS 310", "title": "Mental Health", "archivedAt": NSNull(),
            "semester": ["id": "fake-semester-1", "number": 1, "name": "Semester 1"],
            "questionCount": 86, "examQuestionCount": 134, "termCount": 180, "reviewCount": 12,
            "answeredCount": 35 + added.answered, "fullyRightCount": 24 + added.right, "points": 61, "maxPoints": 92,
        ].merging(folders(Self.mentalHealthID)) { _, folders in folders }
    }

    private func fundamentals() -> [String: Any] {
        let added = state.withLock { Self.added(courseID: Self.fundamentalsID, latest: $0.latest) }
        return [
            "id": Self.fundamentalsID, "code": "NURS 220", "title": "Fundamentals", "archivedAt": NSNull(),
            "semester": ["id": "fake-semester-1", "number": 1, "name": "Semester 1"],
            "questionCount": 146, "examQuestionCount": 146, "termCount": 212, "reviewCount": 5,
            "answeredCount": 92 + added.answered, "fullyRightCount": 70 + added.right, "points": 131, "maxPoints": 170,
        ].merging(folders(Self.fundamentalsID)) { _, folders in folders }
    }

    /// A course's folders with their sets, and the same sets by folder name for an app from before
    /// folders, as the server sends both.
    private func folders(_ courseID: String) -> [String: Any] {
        let folders = study.folders(courseID)
        var weeks: [[String: Any]] = []
        for folder in folders.sorted(by: { Self.weekOrder($0.name, $1.name) }) {
            let sets = folder.sets.map(set)
            if let index = weeks.firstIndex(where: { $0["label"] as? String == folder.name }) {
                weeks[index]["sets"] = (weeks[index]["sets"] as? [[String: Any]] ?? []) + sets
                weeks[index]["examBankCount"] = (weeks[index]["examBankCount"] as? Int ?? 0) + folder.bank.count
            } else {
                weeks.append(["label": folder.name, "sets": sets, "examBankCount": folder.bank.count])
            }
        }
        return [
            "folders": folders.map(folderJSON),
            "folderCount": folders.count,
            "weeks": weeks,
            "weekCount": weeks.count { !(($0["sets"] as? [[String: Any]]) ?? []).isEmpty },
        ]
    }

    /// A folder as the server sends it, with its sets.
    private func folderJSON(_ folder: FakeStudy.Folder) -> [String: Any] {
        [
            "id": folder.id, "name": folder.name, "examPageId": json(folder.examPageID), "sortOrder": folder.sortOrder,
            "sets": folder.sets.map(set), "examBankCount": folder.bank.count,
        ]
    }

    /// The server's week order (`compareWeeks`): by the first number in the name, then by name.
    private static func weekOrder(_ a: String, _ b: String) -> Bool {
        let rank = { (name: String) in name.firstMatch(of: /\d+/).flatMap { Int($0.output) } ?? Int.max }
        let (left, right) = (rank(a), rank(b))
        return left == right ? a.localizedCompare(b) == .orderedAscending : left < right
    }

    /// Every set of the invented courses: title, size, how many days ago it arrived, and how.
    private static let catalog: [String: (title: String, questions: Int, daysAgo: Int, status: String, canRestore: Bool)] = [
        "rights-v1": ("Rights, Law, and Ethics", 17, 20, "imported", false),
        "communication-v1": ("Therapeutic Communication and the Relationship", 14, 12, "imported", false),
        "psychosocial-v2": ("Psychosocial Assessment and Safety Screening", 12, 6, "replaced", true),
        "psychosocial-v1": ("Psychosocial Assessment and Safety Screening", 12, 0, "restored", true),
        "depression-v1": ("Depression and Antidepressants", 18, 0, "imported", false),
        "anxiety-v1": ("Anxiety, Panic, and Anxiolytics", 13, 0, "imported", false),
        "mixed-v1": ("Mixed Clinical Judgment", 8, 4, "imported", false),
        "vitals-v1": ("Vital Signs Under Pressure", 43, 30, "imported", false),
        "safety-v1": ("Safety and Infection Control", 42, 22, "imported", false),
        "mobility-v1": ("Mobility and Skin Integrity", 61, 8, "imported", false),
    ]

    private func set(_ id: String) -> [String: Any] {
        let entry = Self.catalog[id] ?? ("Invented set", 0, 0, "imported", false)
        let earlier = Self.earlierProgress[id]
        let questionIDs = (0..<entry.questions).map { "\(id)-q\($0)" }
        // Once she answers here, the set's line counts her answers, as the server's does.
        let latest = state.withLock { state in questionIDs.compactMap { state.latest[$0] } }
        var json: [String: Any] = [
            "id": id, "title": entry.title, "description": "", "questionCount": entry.questions,
            "importedAt": date(days: -entry.daysAgo), "activeSince": date(days: -entry.daysAgo),
            "status": entry.status, "canRestore": entry.canRestore, "questionIds": questionIDs,
        ]
        if latest.isEmpty {
            json["answeredCount"] = earlier?.answered ?? 0
            json["fullyRightCount"] = earlier?.right ?? 0
            json["lastAnsweredAt"] = self.json(earlier.map { date(days: -$0.lastAnsweredDaysAgo) })
        } else {
            json["answeredCount"] = latest.count
            json["fullyRightCount"] = latest.count { $0.status == "correct" }
            json["lastAnsweredAt"] = QBankJSON.formatDate(latest.map(\.at).max() ?? now)
        }
        return json
    }

    // MARK: Practice

    /// A set of either course, its questions drawn from `FakePracticeQuestions`.
    private func practiceSet(id: String) -> Reply {
        guard let (courseID, folder) = find(set: id), let entry = Self.catalog[id] else {
            return failure(404, "request_refused", "That set is not in the app.")
        }
        return (200, [
            "id": id, "courseId": courseID, "title": entry.title, "weekLabel": folder.name, "folderId": folder.id,
            "kind": "practice",
            "questions": (0..<entry.questions).map { FakePracticeQuestions.question(setID: id, index: $0) },
        ])
    }

    /// The course and folder a current set is in.
    private func find(set id: String) -> (courseID: String, folder: FakeStudy.Folder)? {
        for courseID in [Self.mentalHealthID, Self.fundamentalsID] {
            if let folder = study.folders(courseID).first(where: { $0.sets.contains(id) }) {
                return (courseID, folder)
            }
        }
        return nil
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
        if let session = submission.studySessionId {
            let (status, saved) = study.examAnswer(
                sessionID: session, clientAttemptID: submission.clientAttemptId, questionID: submission.questionId,
                response: submission.response, guessed: submission.guessed, shuffle: submission.shuffle
            )
            if status == 201, let record = try? JSONSerialization.data(withJSONObject: saved) {
                state.withLock { $0.attempts[submission.clientAttemptId] = record }
            }
            return (status, saved)
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
        // Question ids are "<set id>-q<index>".
        let setID = submission.questionId.split(separator: "-").dropLast().joined(separator: "-")
        let saved: [String: Any] = [
            "clientAttemptId": submission.clientAttemptId, "questionId": submission.questionId,
            "courseId": find(set: setID)?.courseID ?? Self.mentalHealthID,
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
        if let (weekLabel, setTitle) = placeOf(questionID: submission.questionId) {
            study.practiced(
                questionID: submission.questionId, courseID: Self.mentalHealthID, score: score,
                guessed: submission.guessed, at: answeredAt, weekLabel: weekLabel, setTitle: setTitle
            )
        }
        return (201, saved)
    }

    /// The folder name and set title of a Mental Health practice question, from its set's id.
    private func placeOf(questionID: String) -> (String, String)? {
        let setID = questionID.split(separator: "-").dropLast().joined(separator: "-")
        guard let (courseID, folder) = find(set: setID), courseID == Self.mentalHealthID, let entry = Self.catalog[setID] else { return nil }
        return (folder.name, entry.title)
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
    let shuffle: Layout?
    let studySessionId: String?
}
#endif
