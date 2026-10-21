import Foundation
import Observation
import QBankKit

/// Where a new set goes, as Import and Make questions pick it: one of her courses or study topics
/// (or, for Import, a new course or a new topic), and a folder in it. The folder is the course's
/// Unsorted unless she picks one of her folders or names a new one; "Import here" on a folder
/// starts with that folder picked.
@Observable
final class SetDestination {
    /// One of her courses or topics, or a new course or topic made by the import.
    enum CourseChoice: Hashable {
        case existing(String)
        case new
        case newTopic
    }

    /// Unsorted (made on first use), one of her folders, or a new one she names.
    enum FolderChoice: Hashable {
        case unsorted
        case folder(String)
        case new
    }

    /// A group of folder chips: an exam page's folders, or those on no exam page.
    struct FolderGroup: Identifiable, Equatable {
        let id: String
        let title: String
        let folders: [Folder]
    }

    /// The folder the server files a set under when she picks none.
    nonisolated static let unsorted = "Unsorted"

    /// Her courses, for the course menu: those in the semesters she studies, without the archived
    /// ones. Nil until loaded.
    private(set) var courses: [CourseSummary]?
    /// Her study topics in her order, without the archived ones: the menu's Study topics group.
    private(set) var topics: [CourseSummary] = []
    private(set) var course: CourseChoice = .new
    /// The picked course's folders and exam pages, for the folder chips. Nil for a new course and
    /// while it loads.
    private(set) var detail: CourseDetail?
    var folder: FolderChoice = .unsorted
    var newFolderName = ""
    var newCode = ""
    var newTitle = ""
    var semesterNumber = 1
    /// The new topic's name.
    var newTopicName = ""
    /// Import can make a course or a topic; Make questions files only into one of hers.
    let allowsNewCourse: Bool

    private let app: AppModel
    /// The course and folder "Import here" opened it with.
    private let preset: (courseID: String, folderID: String)?
    private var detailLoads = 0

    init(app: AppModel, courseID: String? = nil, folderID: String? = nil, allowsNewCourse: Bool) {
        self.app = app
        self.allowsNewCourse = allowsNewCourse
        if let courseID, let folderID {
            preset = (courseID, folderID)
            course = .existing(courseID)
            folder = .folder(folderID)
        } else {
            preset = nil
        }
    }

    /// The picked course or topic, when it is one of hers.
    var courseID: String? {
        guard case .existing(let id) = course else { return nil }
        // Before her lists load, the one "Import here" opened it with.
        guard courses != nil else { return id }
        return summary(id) == nil ? nil : id
    }

    /// True when the import makes a topic: New topic is picked.
    var makesTopic: Bool {
        courseID == nil && course == .newTopic && allowsNewCourse
    }

    /// True when the import makes a course: New course is picked, or a course that is not hers anymore.
    var makesCourse: Bool {
        courseID == nil && !makesTopic && allowsNewCourse
    }

    /// What the course menu shows as picked.
    var menuChoice: CourseChoice {
        if let courseID { return .existing(courseID) }
        return makesTopic ? .newTopic : .new
    }

    /// "NURS 406 · Mental Health", a topic's name, "New course", "New topic", or while her courses
    /// are not here yet, why.
    var courseLabel: String {
        guard courses != nil else { return app.connection.isOnline ? "Loading your courses" : "Needs a connection" }
        if makesTopic { return "New topic" }
        guard let id = courseID else { return allowsNewCourse ? "New course" : "No courses yet" }
        return summary(id).map(Self.label) ?? detail.map(Wording.line) ?? "Loading"
    }

    /// A course by its code and name, a topic by its name, as the menu lists them.
    static func label(_ course: CourseSummary) -> String {
        Wording.line(course)
    }

    /// Her course or topic of this id, from the menu's lists.
    private func summary(_ id: String) -> CourseSummary? {
        courses?.first { $0.id == id } ?? topics.first { $0.id == id }
    }

    /// The course's own Unsorted, once it exists. Before, the chip says it is new.
    var unsortedExists: Bool {
        existingUnsorted != nil
    }

    /// The picked folder's name: Unsorted, hers, or the new one.
    var folderName: String {
        switch folder {
        case .unsorted: Self.unsorted
        case .folder(let id): detail?.folders.first { $0.id == id }?.name ?? Self.unsorted
        case .new: newFolderName.trimmingCharacters(in: .whitespaces)
        }
    }

    /// Her folders as chips, grouped by exam page then those on no page, without her Unsorted,
    /// which is always the first chip.
    var folderGroups: [FolderGroup] {
        guard let detail else { return [] }
        let layout = CourseLayout(course: detail, sittings: [])
        let unsorted = existingUnsorted?.id
        var groups = layout.pages.map { page in
            FolderGroup(id: page.id, title: page.exam.name, folders: page.folders.filter { $0.id != unsorted })
        }
        groups.append(FolderGroup(id: "folders", title: "Folders", folders: layout.looseFolders.filter { $0.id != unsorted }))
        return groups.filter { !$0.folders.isEmpty }
    }

    private var existingUnsorted: Folder? {
        detail?.folders.first { $0.examPageID == nil && $0.name == Self.unsorted }
    }

    /// Her courses and topics, and the one to start on: the folder's course from "Import here",
    /// else the course or topic she studied last, else her first course, else her first topic.
    func load() async throws(QBankError) {
        // Without a connection, the courses saved on the phone, so the form shows what she has.
        let catalog = try await app.load(.catalog) { () async throws(QBankError) in try await app.client.catalog() }.value
        let mine = catalog.semesters.filter { $0.archivedAt == nil }.flatMap(\.courses).filter { $0.archivedAt == nil }
        topics = catalog.topics.filter { $0.archivedAt == nil }
        courses = mine
        let every = mine + topics
        if preset == nil, courseID == nil, course != .newTopic, let first = every.first {
            let place = try? await app.client.studyPlace()
            let start = every.first { $0.id == place } ?? first
            course = .existing(start.id)
        }
        await loadDetail()
    }

    /// The picked course's folders, for the chips.
    private func loadDetail() async {
        detailLoads += 1
        let load = detailLoads
        guard let id = courseID else {
            detail = nil
            return
        }
        let read = try? await app.load(.course(id)) { () async throws(QBankError) in try await app.client.course(id: id) }.value
        guard load == detailLoads else { return }
        detail = read
        // A folder from "Import here" that is gone falls back to Unsorted.
        if case .folder(let folderID) = folder, let read, !read.folders.contains(where: { $0.id == folderID }) {
            folder = .unsorted
        }
    }

    func chooseCourse(_ next: CourseChoice) async {
        guard next != course else { return }
        // Only Import makes a course or a topic.
        if case .existing = next {} else if !allowsNewCourse { return }
        course = next
        detail = nil
        folder = .unsorted
        await loadDetail()
    }

    /// Back to a course or topic after a set was filed, with Unsorted picked. One the import made
    /// is hers now, so the list is read again.
    func restart(on courseID: String) async {
        folder = .unsorted
        newFolderName = ""
        newTopicName = ""
        if courses != nil, summary(courseID) == nil {
            try? await load()
        }
        course = .existing(courseID)
        await loadDetail()
    }

    /// The folder to send, or nil when a new folder has no name yet.
    var importFolder: ImportRequest.Folder? {
        switch folder {
        case .unsorted: return .unsorted
        case .folder(let id): return .id(id)
        case .new:
            let name = newFolderName.trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? nil : .named(name)
        }
    }
}
