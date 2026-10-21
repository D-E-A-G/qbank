import Foundation
import Observation
import QBankKit

/// Home: her semesters with their courses, her study topics, what she archived, and the course or
/// topic she used last. Without a connection it shows the copy saved on the phone, with her
/// waiting answers counted in.
@Observable
final class HomeModel {
    /// What she archived by hand, under its semester or Study topics: an archived semester with
    /// every course of it, or the archived courses of a semester she still studies, or her
    /// archived topics.
    struct ArchivedGroup: Identifiable, Equatable {
        let id: String
        let title: String
        let courses: [CourseSummary]
    }

    private(set) var catalog: Catalog?
    private(set) var isLoading = false
    private(set) var problem: String?
    /// When the courses on screen were saved on the phone, or nil when they came from QBank just now.
    private(set) var savedAt: Date?
    /// Each course's saved copy, for its "Saved" badge and to count waiting answers into its card.
    private(set) var savedCourses: [String: Cached<CourseDetail>] = [:]
    private(set) var waitingProgress = WaitingProgress(answers: [:])

    private let app: AppModel
    /// Whether a user account is signed in, not the admin, as it was when Home was made. Home is
    /// made again for each sign-in, so it never changes; read live, it would change under the
    /// screens that signing out takes away, and keep them from going.
    private let isUserAccount: Bool

    init(app: AppModel) {
        self.app = app
        isUserAccount = app.account?.role == .student
    }

    /// Every semester, archived ones included. Nil until loaded.
    var semesters: [Semester]? {
        catalog?.semesters
    }

    /// The semesters Home lists, in number order: those she has not archived.
    var studiedSemesters: [Semester] {
        semesters?.filter { $0.archivedAt == nil } ?? []
    }

    /// The courses Home shows in a semester: archived ones are left out, the rest in the owner's
    /// order, with her waiting answers counted in.
    func courses(in semester: Semester) -> [CourseSummary] {
        Self.ordered(semester.courses.filter { $0.archivedAt == nil }).map(counted)
    }

    /// Her study topics in her order, without the archived ones, with her waiting answers counted in.
    var topics: [CourseSummary] {
        (catalog?.topics ?? []).filter { $0.archivedAt == nil }.map(counted)
    }

    /// What she archived, last on Home: each semester's, then her topics'. Empty when nothing is.
    var archived: [ArchivedGroup] {
        guard let catalog else { return [] }
        var groups: [ArchivedGroup] = []
        for semester in catalog.semesters {
            let courses = semester.archivedAt == nil ? semester.courses.filter { $0.archivedAt != nil } : semester.courses
            if semester.archivedAt != nil || !courses.isEmpty {
                groups.append(ArchivedGroup(id: semester.id, title: semester.name, courses: Self.ordered(courses).map(counted)))
            }
        }
        let topics = catalog.topics.filter { $0.archivedAt != nil }
        if !topics.isEmpty {
            groups.append(ArchivedGroup(id: "topics", title: "Study topics", courses: topics.map(counted)))
        }
        return groups
    }

    /// A user account makes topics; the admin's view of her account is read-only. Making one needs
    /// QBank, so not from the copy on the phone.
    var canMakeTopic: Bool {
        isUserAccount && savedAt == nil && app.connection.isOnline
    }

    var showsNewTopic: Bool {
        isUserAccount
    }

    /// A semester's courses in the owner's order.
    private static func ordered(_ courses: [CourseSummary]) -> [CourseSummary] {
        courses.sorted { ($0.sortOrder, $0.code) < ($1.sortOrder, $1.code) }
    }

    private func counted(_ course: CourseSummary) -> CourseSummary {
        waitingProgress.counting(course, saved: savedCourses[course.id]?.value)
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
            let loaded = try await app.load(.catalog) { () async throws(QBankError) in try await app.client.catalog() }
            catalog = loaded.value
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
        guard let catalog, savedAt == nil else { return }
        app.offline?.saveCourses(in: catalog, force: force)
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
        for course in catalog?.everyCourse ?? [] {
            saved[course.id] = await offline.saved(.course(course.id))
        }
        savedCourses = saved
        waitingProgress = await offline.waitingProgress()
    }

    /// The course or topic to open on first arrival after sign-in, as on the web: the one she used
    /// last. Nil when she has none, when it was opened already, or for an admin, who has no study
    /// place.
    func landingCourse() async -> CourseRoute? {
        guard !app.hasLanded, app.account?.role == .student else { return nil }
        app.hasLanded = true
        guard savedAt == nil, let id = try? await app.client.studyPlace() else { return nil }
        let course = catalog?.course(id: id)
        return CourseRoute(id: id, name: course.map(Wording.name), kind: course?.kind ?? .course)
    }

    /// Reads the list again after she made a topic, which then opens.
    func made(_ topic: CourseSummary) async -> CourseRoute {
        await load()
        return CourseRoute(id: topic.id, name: Wording.name(topic), kind: topic.kind)
    }
}

/// A course or topic on the navigation stack. Its name, a course's code or a topic's title, shows
/// as the title before it loads.
struct CourseRoute: Hashable {
    let id: String
    let name: String?
    /// Picks the words its screen says while it loads, when known.
    var kind: CourseKind = .course
}
