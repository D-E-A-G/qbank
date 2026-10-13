import Foundation
import Observation
import QBankKit

/// Home: every semester with its courses, and the course she used last.
@Observable
final class HomeModel {
    private(set) var semesters: [Semester]?
    private(set) var isLoading = false
    private(set) var problem: String?

    private let app: AppModel

    init(app: AppModel) {
        self.app = app
    }

    /// The courses Home shows in a semester: archived ones are left out, the rest in the owner's order.
    func courses(in semester: Semester) -> [CourseSummary] {
        semester.courses
            .filter { $0.archivedAt == nil }
            .sorted { ($0.sortOrder, $0.code) < ($1.sortOrder, $1.code) }
    }

    /// Loads the semesters. A failed reload keeps what is already on screen.
    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            semesters = try await app.client.semesters()
            problem = nil
        } catch {
            guard !app.handle(error), let words = Wording.problem(error) else { return }
            problem = words
        }
    }

    /// The course to open on first arrival after sign-in, as on the web: the one she used last.
    /// Nil when she has none, when it was opened already, or for an admin, who has no study place.
    func landingCourse() async -> CourseRoute? {
        guard !app.hasLanded, app.account?.role == .student else { return nil }
        app.hasLanded = true
        guard let id = try? await app.client.studyPlace() else { return nil }
        let code = semesters?.lazy.flatMap(\.courses).first { $0.id == id }?.code
        return CourseRoute(id: id, code: code)
    }
}

/// A course on the navigation stack. The code shows as the title before the course loads.
struct CourseRoute: Hashable {
    let id: String
    let code: String?
}
