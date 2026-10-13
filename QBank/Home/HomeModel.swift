import Foundation
import Observation
import QBankKit

/// Home: every semester with its courses, and the course she used last. Without a connection it
/// shows the copy saved on the phone, with her waiting answers counted in.
@Observable
final class HomeModel {
    private(set) var semesters: [Semester]?
    private(set) var isLoading = false
    private(set) var problem: String?
    /// When the courses on screen were saved on the phone, or nil when they came from QBank just now.
    private(set) var savedAt: Date?
    /// Each course's saved copy, for its "Saved" badge and to count waiting answers into its card.
    private(set) var savedCourses: [String: Cached<CourseDetail>] = [:]
    private(set) var waitingProgress = WaitingProgress(answers: [:])

    private let app: AppModel

    init(app: AppModel) {
        self.app = app
    }

    /// The courses Home shows in a semester: archived ones are left out, the rest in the owner's
    /// order, with her waiting answers counted in.
    func courses(in semester: Semester) -> [CourseSummary] {
        semester.courses
            .filter { $0.archivedAt == nil }
            .sorted { ($0.sortOrder, $0.code) < ($1.sortOrder, $1.code) }
            .map { waitingProgress.counting($0, saved: savedCourses[$0.id]?.value) }
    }

    /// The "Saved" badge of a course shown from the phone's copy: when its own copy was saved.
    func savedAt(_ course: CourseSummary) -> Date? {
        guard let savedAt else { return nil }
        return savedCourses[course.id]?.savedAt ?? savedAt
    }

    /// Loads the semesters. A failed reload keeps what is already on screen.
    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await app.load(.semesters) { () async throws(QBankError) in try await app.client.semesters() }
            semesters = loaded.value
            savedAt = loaded.savedAt
            problem = nil
        } catch {
            guard !app.handle(error), let words = Wording.problem(error) else { return }
            problem = words
            return
        }
        await readSaved()
    }

    /// Saves every course for offline in the background. `force` saves again even if it just did.
    func saveForOffline(force: Bool = false) {
        guard let semesters, savedAt == nil else { return }
        app.offline?.saveCourses(in: semesters, force: force)
    }

    /// The saved copies Home needs: for the badges when it shows the phone's copy, and to count
    /// waiting answers into the cards.
    private func readSaved() async {
        guard let offline = app.offline, savedAt != nil || !offline.waiting.isEmpty else {
            savedCourses = [:]
            waitingProgress = WaitingProgress(answers: [:])
            return
        }
        var saved: [String: Cached<CourseDetail>] = [:]
        for course in semesters?.flatMap(\.courses) ?? [] {
            saved[course.id] = await offline.saved(.course(course.id))
        }
        savedCourses = saved
        waitingProgress = await offline.waitingProgress()
    }

    /// The course to open on first arrival after sign-in, as on the web: the one she used last.
    /// Nil when she has none, when it was opened already, or for an admin, who has no study place.
    func landingCourse() async -> CourseRoute? {
        guard !app.hasLanded, app.account?.role == .student else { return nil }
        app.hasLanded = true
        guard savedAt == nil, let id = try? await app.client.studyPlace() else { return nil }
        let code = semesters?.lazy.flatMap(\.courses).first { $0.id == id }?.code
        return CourseRoute(id: id, code: code)
    }
}

/// A course on the navigation stack. The code shows as the title before the course loads.
struct CourseRoute: Hashable {
    let id: String
    let code: String?
}
