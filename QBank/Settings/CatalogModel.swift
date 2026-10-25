import Foundation
import Observation
import QBankKit

/// Her semesters and courses as Settings and Home's sheets edit them: the semesters she has, and
/// the screens and sheets that name and date a semester, add a course to it, and rename a course
/// or topic.
@Observable
final class CatalogModel {
    private(set) var catalog: Catalog?
    private(set) var isLoading = false
    /// Why the first load failed. A failed reload keeps the list and says nothing.
    private(set) var loadProblem: String?

    /// The web offers Semesters 1, 2 and 3; the server refuses any other number.
    static let semesterNumbers = 1...3

    let app: AppModel

    /// `catalog` is the list the screen that opens it already has, such as Home's, so a sheet
    /// shows its course at once.
    init(app: AppModel, catalog: Catalog? = nil) {
        self.app = app
        self.catalog = catalog
    }

    /// Students edit the catalog; the admin does it on the web, as there.
    var isEditable: Bool {
        app.account?.role == .student
    }

    /// Every semester, archived ones included. Nil until loaded.
    var semesters: [Semester]? {
        catalog?.semesters
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            catalog = try await app.client.catalog()
            loadProblem = nil
        } catch {
            guard !app.handle(error), catalog == nil else { return }
            loadProblem = Wording.problem(error)
        }
    }

    /// The semester Home's + adds next: the lowest of 1, 2 and 3 she does not have, or nil.
    static func nextSemesterNumber(after semesters: [Semester]) -> Int? {
        let taken = Set(semesters.map(\.number))
        return semesterNumbers.first { !taken.contains($0) }
    }

    func semester(id: String) -> Semester? {
        semesters?.first { $0.id == id }
    }

    func topic(id: String) -> CourseSummary? {
        catalog?.topics.first { $0.id == id }
    }

    /// A course and the semester it is in now.
    func course(id: String) -> (course: CourseSummary, semester: Semester)? {
        for semester in semesters ?? [] {
            if let course = semester.courses.first(where: { $0.id == id }) {
                return (course, semester)
            }
        }
        return nil
    }

    /// A semester's courses in the owner's order, archived ones included.
    static func courses(in semester: Semester) -> [CourseSummary] {
        semester.courses.sorted { ($0.sortOrder, $0.code) < ($1.sortOrder, $1.code) }
    }

    /// The line under a semester in Settings: "NURS 406, NURS 402", "NURS 406 · 1 archived", or
    /// "No courses yet", after "Archived" when she archived the semester.
    static func summary(of semester: Semester) -> String {
        let courses = courses(in: semester)
        let lead = semester.archivedAt == nil ? nil : "Archived"
        guard !courses.isEmpty else { return [lead, "No courses yet"].compactMap { $0 }.joined(separator: " · ") }
        let active = courses.filter { $0.archivedAt == nil }.map(\.code)
        let archived = courses.count - active.count
        let archivedText = archived > 0 ? "\(archived) archived" : nil
        return [lead, active.isEmpty ? nil : active.joined(separator: ", "), archivedText]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    /// Runs one edit and reloads, so every screen shows what the server saved.
    /// Returns what to tell her when it failed, or nil.
    func perform(_ work: () async throws(QBankError) -> Void) async -> String? {
        do {
            try await work()
        } catch {
            if app.handle(error) { return nil }
            await load()
            return Wording.problem(error)
        }
        await load()
        return nil
    }
}

/// One semester's screen, its name and dates and archiving it, and Home's New course sheet, which
/// adds a course to it.
@Observable
final class SemesterModel {
    let id: String
    var name: String {
        didSet { if name != oldValue { isSaved = false } }
    }
    var startsOn: Date? {
        didSet { if startsOn != oldValue { isSaved = false } }
    }
    var endsOn: Date? {
        didSet { if endsOn != oldValue { isSaved = false } }
    }
    var newCode = ""
    var newTitle = ""
    private(set) var isSaving = false
    private(set) var isAddingCourse = false
    private(set) var isArchiving = false
    /// Why archiving failed, or what it did.
    private(set) var archiveProblem: String?
    private(set) var archiveNote: String?
    private(set) var saveProblem: String?
    private(set) var addProblem: String?
    /// True after a save, until she edits again.
    private(set) var isSaved = false

    let catalog: CatalogModel

    init(catalog: CatalogModel, id: String) {
        self.catalog = catalog
        self.id = id
        let semester = catalog.semester(id: id)
        name = semester?.name ?? ""
        startsOn = CalendarDay.date(from: semester?.startsOn)
        endsOn = CalendarDay.date(from: semester?.endsOn)
    }

    var semester: Semester? {
        catalog.semester(id: id)
    }

    var isArchived: Bool {
        semester?.archivedAt != nil
    }

    /// Archives the semester by hand, with its courses, or brings it back to Home.
    func toggleArchived() async {
        guard !isArchiving, semester != nil else { return }
        let archive = !isArchived
        isArchiving = true
        archiveProblem = nil
        archiveNote = nil
        defer { isArchiving = false }
        archiveProblem = await catalog.perform { () async throws(QBankError) in
            _ = try await catalog.app.client.setSemesterArchived(id: id, archive)
        }
        if archiveProblem == nil {
            archiveNote = archive ? "Archived. It moves to Archived on Home, with its courses." : "Unarchived. It shows on Home again."
        }
    }

    func save() async {
        guard !isSaving else { return }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            saveProblem = "Semester name is required."
            return
        }
        isSaving = true
        saveProblem = nil
        defer { isSaving = false }
        let name = name
        let startsOn = CalendarDay.text(from: startsOn)
        let endsOn = CalendarDay.text(from: endsOn)
        let problem = await catalog.perform { () async throws(QBankError) in
            _ = try await catalog.app.client.updateSemester(id: id, name: name, startsOn: startsOn, endsOn: endsOn)
        }
        saveProblem = problem
        if problem == nil, let saved = semester {
            // Show what the server kept, such as the name without its outer spaces.
            self.name = saved.name
            isSaved = true
        }
    }

    /// Adds the course she named to the semester. Returns it once made, or nil after a refusal,
    /// which `addProblem` says.
    func addCourse() async -> CourseSummary? {
        guard !isAddingCourse else { return nil }
        if newCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            addProblem = "Course code is required."
            return nil
        }
        if newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            addProblem = "Course name is required."
            return nil
        }
        isAddingCourse = true
        addProblem = nil
        defer { isAddingCourse = false }
        let code = newCode
        let title = newTitle
        var added: CourseSummary?
        let problem = await catalog.perform { () async throws(QBankError) in
            added = try await catalog.app.client.addCourse(semesterID: id, code: code, title: title)
        }
        addProblem = problem
        guard problem == nil else { return nil }
        newCode = ""
        newTitle = ""
        return added
    }
}

/// Renaming a course, from holding it on Home: its code and name. It stays in its semester.
@Observable
final class CourseEditModel {
    let id: String
    var code: String {
        didSet { if code != oldValue { note = nil } }
    }
    var title: String {
        didSet { if title != oldValue { note = nil } }
    }
    let semesterID: String
    private(set) var isSaving = false
    private(set) var problem: String?
    /// "Saved." once saved.
    private(set) var note: String?

    let catalog: CatalogModel

    init(catalog: CatalogModel, id: String) {
        self.catalog = catalog
        self.id = id
        let found = catalog.course(id: id)
        code = found?.course.code ?? ""
        title = found?.course.title ?? ""
        semesterID = found?.semester.id ?? ""
    }

    var course: CourseSummary? {
        catalog.course(id: id)?.course
    }

    var hasChanges: Bool {
        code != course?.code || title != course?.title
    }

    func save() async {
        guard !isSaving else { return }
        if code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            problem = "Course code is required."
            return
        }
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            problem = "Course name is required."
            return
        }
        isSaving = true
        problem = nil
        note = nil
        defer { isSaving = false }
        let code = code
        let title = title
        let semesterID = semesterID
        problem = await catalog.perform { () async throws(QBankError) in
            _ = try await catalog.app.client.updateCourse(id: id, code: code, title: title, semesterID: semesterID)
        }
        if problem == nil, let saved = catalog.course(id: id) {
            self.code = saved.course.code
            self.title = saved.course.title
            note = "Saved."
        }
    }
}

/// Renaming a study topic, from holding it on Home.
@Observable
final class TopicEditModel {
    let id: String
    var title: String {
        didSet { if title != oldValue { note = nil } }
    }
    private(set) var isSaving = false
    private(set) var problem: String?
    /// "Saved." once saved.
    private(set) var note: String?

    let catalog: CatalogModel

    init(catalog: CatalogModel, id: String) {
        self.catalog = catalog
        self.id = id
        title = catalog.topic(id: id)?.title ?? ""
    }

    var topic: CourseSummary? {
        catalog.topic(id: id)
    }

    var hasChanges: Bool {
        title != topic?.title
    }

    /// Renames the topic. Its folders, pages, sets and her answers stay with it.
    func save() async {
        guard !isSaving else { return }
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            problem = "Give the topic a name."
            return
        }
        isSaving = true
        problem = nil
        note = nil
        defer { isSaving = false }
        let title = title
        problem = await catalog.perform { () async throws(QBankError) in
            _ = try await catalog.app.client.renameTopic(id: id, title: title)
        }
        if problem == nil, let saved = topic {
            // Show what the server kept, such as the name without its outer spaces.
            self.title = saved.title
            note = "Saved."
        }
    }
}
