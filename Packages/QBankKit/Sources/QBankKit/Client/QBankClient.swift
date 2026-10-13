import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The QBank API as the iPhone app uses it.
///
/// Sign-in stores the bearer token in the `SessionStore`; every later call sends it as
/// `Authorization: Bearer`. The client holds no API key and keeps no cookies.
public struct QBankClient: Sendable {
    public let configuration: APIConfiguration
    public let sessionStore: any SessionStore
    private let transport: any HTTPTransport

    public init(
        configuration: APIConfiguration = .production,
        transport: any HTTPTransport = URLSessionTransport(),
        sessionStore: any SessionStore
    ) {
        self.configuration = configuration
        self.transport = transport
        self.sessionStore = sessionStore
    }

    // MARK: Sign-in and session

    /// `GET /health`.
    public func health() async throws(QBankError) -> Health {
        try await send(Request(.get, "/health", authenticated: false))
    }

    /// Signs in with email and password and stores the session.
    /// Five wrong passwords lock the address for 15 minutes (`too_many_attempts`, 429, `retryAfterSeconds`).
    @discardableResult
    public func signIn(email: String, password: String) async throws(QBankError) -> SignedIn {
        let body = PasswordSignInRequest(email: email, password: password)
        let signedIn: SignedIn = try await send(Request(.post, "/api/sign-in/password", body: body, authenticated: false))
        try store(signedIn)
        return signedIn
    }

    /// Checks the stored session with the server and refreshes the stored account.
    /// A 401 means the session ended; the stored one is left for the app to clear.
    public func session() async throws(QBankError) -> Session {
        let session: Session = try await send(Request(.get, "/api/session"))
        if let stored = try loadSession() {
            try save(StoredSession(token: stored.token, expiresAt: session.expiresAt, account: session.user))
        }
        return session
    }

    /// The session stored on this device, without asking the server.
    public func storedSession() throws(QBankError) -> StoredSession? {
        try loadSession()
    }

    /// Ends this device's session on the server and forgets it here.
    /// The local session is cleared even when the server cannot be reached; the error still reports that.
    public func signOut() async throws(QBankError) {
        guard try loadSession() != nil else { return }
        var failure: QBankError?
        do {
            let _: StatusResponse = try await send(Request(.post, "/api/sign-out"))
        } catch {
            failure = error
        }
        do {
            try sessionStore.clear()
        } catch {
            throw .storage(error)
        }
        if let failure, !failure.needsSignIn { throw failure }
    }

    /// Replaces her password, including a temporary one. Her other sessions end and this one
    /// gets a fresh token, which is stored.
    @discardableResult
    public func changePassword(current: String, new: String) async throws(QBankError) -> SignedIn {
        let body = ChangePasswordRequest(currentPassword: current, newPassword: new)
        let signedIn: SignedIn = try await send(Request(.post, "/api/account/password", body: body))
        try store(signedIn)
        return signedIn
    }

    // MARK: Courses

    /// Home: every semester with its courses.
    public func semesters() async throws(QBankError) -> [Semester] {
        let response: SemestersResponse = try await send(Request(.get, "/api/semesters"))
        return response.semesters
    }

    /// A course, its weeks, and its practice sets.
    public func course(id: String) async throws(QBankError) -> CourseDetail {
        try await send(Request(.get, "/api/courses/\(id)"))
    }

    /// The course's terms, newest definition first when a term is defined twice.
    public func terms(courseID: String) async throws(QBankError) -> [Term] {
        let response: TermsResponse = try await send(Request(.get, "/api/courses/\(courseID)/terms"))
        return response.terms
    }

    /// The questions of a practice set, in the order she practices them.
    public func practiceSet(id: String) async throws(QBankError) -> PracticeSet {
        try await send(Request(.get, "/api/practice-sets/\(id)"))
    }

    // MARK: Answers

    /// Sends one answer. The server scores it and saves her progress. Sending the same
    /// `clientAttemptID` again returns the saved attempt with `replayed` set and counts nothing twice.
    public func recordAttempt(_ attempt: AttemptSubmission) async throws(QBankError) -> SavedAttempt {
        try await send(Request(.post, "/api/attempts", body: attempt))
    }

    // MARK: Review

    public func review(courseID: String, filter: ReviewFilter = .all) async throws(QBankError) -> ReviewList {
        try await send(Request(.get, "/api/courses/\(courseID)/review", query: filter == .all ? [] : [("filter", filter.rawValue)]))
    }

    /// The Review questions for the runner, in a new shuffled order each time, or only `questionID`.
    public func reviewPractice(courseID: String, filter: ReviewFilter = .all, questionID: String? = nil) async throws(QBankError) -> PracticeSet {
        var query: [(String, String)] = []
        if filter != .all { query.append(("filter", filter.rawValue)) }
        if let questionID { query.append(("question", questionID)) }
        return try await send(Request(.get, "/api/courses/\(courseID)/review/practice", query: query))
    }

    /// Empties the course's Review list. Answers and scores stay. Returns how many questions left it.
    /// The app asks her first; `confirmed: false` returns 400 `confirmation_required` with the question to ask.
    @discardableResult
    public func clearReview(courseID: String, confirmed: Bool = true) async throws(QBankError) -> Int {
        let response: ClearReviewResponse = try await send(
            Request(.post, "/api/courses/\(courseID)/review/clear", body: ClearReviewRequest(confirmed: confirmed))
        )
        return response.cleared
    }

    // MARK: Exams

    /// The week picker with per-week wrong counts, her running exam, and her ended exams.
    public func examSetup(courseID: String) async throws(QBankError) -> ExamSetup {
        try await send(Request(.get, "/api/courses/\(courseID)/exams"))
    }

    /// Starts an exam over the ticked weeks: up to 40 questions, 90 seconds each.
    /// With `.wrong`, only the questions she last answered not fully right; a ticked week with none
    /// is refused with 400 `no_wrong_questions`.
    public func startExam(courseID: String, weeks: [String], pool: ExamPool = .all) async throws(QBankError) -> Exam {
        try await send(Request(.post, "/api/courses/\(courseID)/exams", body: StartExamRequest(weeks: weeks, pool: pool)))
    }

    /// One exam. An exam whose time ran out is ended first.
    public func exam(id: String) async throws(QBankError) -> Exam {
        try await send(Request(.get, "/api/exams/\(id)"))
    }

    /// Ends the exam and scores it. Ending an ended exam returns it unchanged.
    public func finishExam(id: String, reason: ExamEndReason) async throws(QBankError) -> Exam {
        try await send(Request(.post, "/api/exams/\(id)/finish", body: FinishExamRequest(reason: reason)))
    }

    // MARK: Settings

    /// The course she used last, or nil.
    public func studyPlace() async throws(QBankError) -> String? {
        let place: StudyPlaceBody = try await send(Request(.get, "/api/me/place"))
        return place.courseId
    }

    /// Remembers the course she just opened.
    public func setStudyPlace(courseID: String) async throws(QBankError) {
        let _: StudyPlaceBody = try await send(Request(.put, "/api/me/place", body: StudyPlaceBody(courseId: courseID)))
    }

    /// Her progress as one JSON file, for the share sheet.
    public func exportProgress() async throws(QBankError) -> Data {
        try await sendForData(Request(.get, "/api/me/export"))
    }

    /// The passkeys saved on her account.
    public func passkeys() async throws(QBankError) -> [Passkey] {
        let response: PasskeysResponse = try await send(Request(.get, "/api/passkeys"))
        return response.passkeys
    }

    public func removePasskey(id: String) async throws(QBankError) {
        let _: StatusResponse = try await send(Request(.delete, "/api/passkeys/\(id)"))
    }

    // MARK: Plumbing

    private func store(_ signedIn: SignedIn) throws(QBankError) {
        try save(StoredSession(token: signedIn.token, expiresAt: signedIn.expiresAt, account: signedIn.user))
    }

    private func loadSession() throws(QBankError) -> StoredSession? {
        do {
            return try sessionStore.load()
        } catch {
            throw .storage(error)
        }
    }

    private func save(_ session: StoredSession) throws(QBankError) {
        do {
            try sessionStore.save(session)
        } catch {
            throw .storage(error)
        }
    }

    private func send<Response: Decodable>(_ request: Request) async throws(QBankError) -> Response {
        let (data, status) = try await exchange(request)
        do {
            return try QBankJSON.decoder.decode(Response.self, from: data)
        } catch {
            throw .unexpectedResponse(status: status, detail: "The answer to \(request.method.rawValue) \(request.path) does not match \(Response.self): \(error)")
        }
    }

    private func sendForData(_ request: Request) async throws(QBankError) -> Data {
        try await exchange(request).data
    }

    private func exchange(_ request: Request) async throws(QBankError) -> (data: Data, status: Int) {
        var token: String?
        if request.authenticated {
            guard let session = try loadSession() else { throw .notSignedIn }
            token = session.token
        }
        let urlRequest = try request.urlRequest(configuration: configuration, token: token)
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(urlRequest)
        } catch let error as URLError {
            throw error.code == .cancelled ? .cancelled : .transport(error.code)
        } catch is CancellationError {
            throw .cancelled
        } catch {
            throw .transport(.unknown)
        }
        let status = response.statusCode
        guard (200..<300).contains(status) else {
            throw Self.failure(status: status, data: data, response: response)
        }
        return (data, status)
    }

    static func failure(status: Int, data: Data, response: HTTPURLResponse) -> QBankError {
        guard let body = try? QBankJSON.decoder.decode(ErrorBody.self, from: data) else {
            let text = String(decoding: data.prefix(200), as: UTF8.self)
            return .unexpectedResponse(status: status, detail: text.isEmpty ? "No body" : text)
        }
        let retryAfter = body.retryAfterSeconds ?? response.value(forHTTPHeaderField: "Retry-After").flatMap { Int($0) }
        return .server(ServerError(status: status, code: .init(rawValue: body.error), message: body.message, retryAfterSeconds: retryAfter))
    }
}

/// One API call before it becomes a URLRequest.
struct Request {
    enum Method: String {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case delete = "DELETE"
    }

    let method: Method
    let path: String
    let query: [(String, String)]
    let body: (any Encodable & Sendable)?
    let authenticated: Bool

    init(
        _ method: Method,
        _ path: String,
        query: [(String, String)] = [],
        body: (any Encodable & Sendable)? = nil,
        authenticated: Bool = true
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
        self.authenticated = authenticated
    }

    func urlRequest(configuration: APIConfiguration, token: String?) throws(QBankError) -> URLRequest {
        guard var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false) else {
            throw .invalidRequest("Bad base URL \(configuration.baseURL)")
        }
        // Path parameters are ids from the server; percent-encode them anyway.
        let base = components.percentEncodedPath.hasSuffix("/") ? String(components.percentEncodedPath.dropLast()) : components.percentEncodedPath
        components.percentEncodedPath = base + (path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path)
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        }
        guard let url = components.url else {
            throw .invalidRequest("Bad path \(path)")
        }
        var request = URLRequest(url: url, timeoutInterval: configuration.timeout)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            do {
                request.httpBody = try QBankJSON.encoder.encode(body)
            } catch {
                throw .invalidRequest("Cannot encode the request body: \(error)")
            }
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }
}
