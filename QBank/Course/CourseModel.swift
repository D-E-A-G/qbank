import Foundation
import Observation
import QBankKit

/// One course: its score line, the Exam, Review and Terms tiles, and its weeks with their sets.
@Observable
final class CourseModel {
    let id: String
    private(set) var course: CourseDetail?
    private(set) var isLoading = false
    private(set) var problem: String?
    private(set) var isRestoring = false

    private let app: AppModel

    init(app: AppModel, id: String) {
        self.app = app
        self.id = id
    }

    /// A student's course is remembered as her study place, so the next launch opens it.
    var remembersPlace: Bool {
        app.account?.role == .student
    }

    /// Loads the course. A failed reload keeps what is already on screen.
    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            course = try await app.client.course(id: id)
            problem = nil
        } catch {
            report(error)
        }
    }

    /// Remembers this course as the one she used last. Failing is harmless: the next open tries again.
    func rememberPlace() async {
        guard remembersPlace else { return }
        try? await app.client.setStudyPlace(courseID: id)
    }

    /// Brings back the previous version of a set she confirmed, then reloads the course.
    func restore(_ set: PracticeSetSummary) async {
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await app.client.restorePracticeSet(id: set.id)
            problem = nil
        } catch {
            report(error)
            return
        }
        await load()
    }

    private func report(_ error: QBankError) {
        guard !app.handle(error), let words = Wording.problem(error) else { return }
        problem = words
    }
}
