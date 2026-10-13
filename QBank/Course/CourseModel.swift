import Foundation
import Observation
import QBankKit

/// One course: its score line, the Exam, Review and Terms tiles, and its sets, by week or by exam.
/// Each week and each exam is a folder; which ones are open, and which view she chose, is kept on
/// this phone per course, as the web keeps it per browser. Without a connection it shows the copy
/// saved on the phone, with her waiting answers counted in.
@Observable
final class CourseModel {
    let id: String
    private(set) var course: CourseDetail?
    /// Her exams in this course, for the by-exam view: the running one first, then newest first.
    private(set) var sittings: [ExamSummary] = []
    private(set) var isLoading = false
    private(set) var problem: String?
    private(set) var isRestoring = false
    /// When the course on screen was saved on the phone, or nil when it came from QBank just now.
    private(set) var savedAt: Date?
    private(set) var view: CourseMemory.View = .weeks
    private var openedWeeks: [String: Bool]
    private var openedExams: [String: Bool]
    private var hasChosenView: Bool

    private let app: AppModel
    private var memory: CourseMemory { app.courseMemory }

    init(app: AppModel, id: String) {
        self.app = app
        self.id = id
        openedWeeks = app.courseMemory.weeks(course: id)
        openedExams = app.courseMemory.exams(course: id)
        let chosen = app.courseMemory.view(course: id)
        hasChosenView = chosen != nil
        view = chosen ?? .weeks
    }

    /// A student's course is remembered as her study place, so the next launch opens it.
    var remembersPlace: Bool {
        app.account?.role == .student
    }

    var isStudent: Bool {
        app.account?.role == .student
    }

    /// The course as the study screens name it.
    var ref: CourseRef? {
        course.map { CourseRef(id: $0.id, code: $0.code, title: $0.title) }
    }

    /// Loads the course and her exams in it. A failed reload keeps what is already on screen. Her
    /// exams are only for the by-exam view and come from QBank, so failing to read them, or having
    /// no connection, leaves the course usable with the exams it showed last.
    func load() async {
        isLoading = true
        defer { isLoading = false }
        async let setup = sittingsSetup()
        do {
            let loaded = try await app.load(.course(id)) { () async throws(QBankError) in try await app.client.course(id: id) }
            course = await counted(loaded.value)
            savedAt = loaded.savedAt
            problem = nil
            // Before she chooses, a course with exams opens on them: the view she asked for.
            if !hasChosenView {
                view = loaded.value.exams.isEmpty ? .weeks : .exams
            }
        } catch {
            _ = await setup
            report(error)
            return
        }
        if let setup = await setup {
            sittings = (setup.inProgress.map { [$0] } ?? []) + setup.exams
        }
    }

    private func sittingsSetup() async -> ExamSetup? {
        guard app.connection.isOnline else { return nil }
        return try? await app.client.examSetup(courseID: id)
    }

    /// The course with the answers waiting on the phone counted in.
    private func counted(_ course: CourseDetail) async -> CourseDetail {
        guard let offline = app.offline, !offline.waiting.isEmpty else { return course }
        return await offline.waitingProgress().counting(course)
    }

    /// Remembers this course as the one she used last. Failing is harmless: the next open tries again.
    func rememberPlace() async {
        guard remembersPlace, app.connection.isOnline else { return }
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

    // MARK: Folders

    func choose(_ view: CourseMemory.View) {
        self.view = view
        hasChosenView = true
        memory.setView(view, course: id)
    }

    var grouping: ExamGrouping? {
        course.map { ExamGrouping(course: $0, sittings: sittings) }
    }

    func isOpen(week: Week) -> Bool {
        openedWeeks[week.label] ?? FolderDefaults.openWeeks(course?.weeks ?? []).contains(week.label)
    }

    func setOpen(_ open: Bool, week: Week) {
        openedWeeks[week.label] = open
        memory.setWeek(week.label, open: open, course: id)
    }

    func isOpen(exam: ExamFolder) -> Bool {
        openedExams[exam.id] ?? FolderDefaults.openExams(grouping?.folders ?? []).contains(exam.id)
    }

    func setOpen(_ open: Bool, exam: ExamFolder) {
        openedExams[exam.id] = open
        memory.setExam(exam.id, open: open, course: id)
    }

    /// Exam setup with an exam's weeks ticked, from its folder's Start button.
    func examSetup(for folder: ExamFolder) -> ExamSetupRoute? {
        ref.map { ExamSetupRoute(course: $0, weeks: folder.weeks.map(\.label), examName: folder.exam.name) }
    }

    private func report(_ error: QBankError) {
        guard !app.handle(error), let words = Wording.problem(error) else { return }
        problem = words
    }
}
