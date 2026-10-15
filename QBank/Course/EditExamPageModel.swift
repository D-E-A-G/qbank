import Foundation
import Observation
import QBankKit

/// The exam page editor: the page's name and the course's folders as chips. A folder is on one
/// exam page at most, so a folder another page holds is greyed and names that page. Done saves
/// through the server, which has the last word: a refusal is shown in its words.
@Observable
final class EditExamPageModel {
    /// How the editor closed.
    enum Outcome: Equatable {
        case cancelled
        /// The page was made or changed; its id.
        case saved(String)
        case removed
    }

    /// A folder as a chip.
    struct Chip: Identifiable, Equatable {
        let folder: Folder
        /// The other exam page holding it, which greys the chip, or nil.
        let heldBy: String?

        var id: String { folder.id }
    }

    let courseID: String
    /// The page on the server, or nil for a new one.
    let pageID: String?
    var name: String
    /// Its folders as she picks them, in her order: the ones it had, then the ones she adds.
    private(set) var picked: [String]
    /// Every folder a chip can stand for: this page's, then those on no page, then other pages'.
    let chips: [Chip]
    private(set) var problem: String?
    private(set) var isSaving = false

    private let savedName: String
    private let savedFolders: [String]
    private let app: AppModel

    init(app: AppModel, course: CourseDetail, pageID: String?) {
        self.app = app
        courseID = course.id
        let page = course.exams.first { $0.id == pageID }
        self.pageID = page?.id
        let layout = CourseLayout(course: course, sittings: [])
        let own = layout.page(page?.id ?? "")?.folders ?? []
        let others = layout.pages.filter { $0.id != page?.id }
        chips = own.map { Chip(folder: $0, heldBy: nil) }
            + layout.looseFolders.map { Chip(folder: $0, heldBy: nil) }
            + others.flatMap { other in other.folders.map { Chip(folder: $0, heldBy: other.exam.name) } }
        savedName = page?.name ?? CourseModel.nextExamName(after: course.exams.map(\.name))
        name = savedName
        savedFolders = own.map(\.id)
        picked = savedFolders
    }

    var isNew: Bool {
        pageID == nil
    }

    var hasChanges: Bool {
        isNew || name != savedName || folderIDs != savedFolders
    }

    /// The page's folders as saved: the ones it kept in her order, then the ones she added, in the
    /// order she tapped them. Tapping a folder off and on again leaves the order as it was.
    var folderIDs: [String] {
        savedFolders.filter(picked.contains) + picked.filter { !savedFolders.contains($0) }
    }

    func isPicked(_ chip: Chip) -> Bool {
        picked.contains(chip.id)
    }

    func toggle(_ chip: Chip) {
        guard chip.heldBy == nil else { return }
        if let index = picked.firstIndex(of: chip.id) {
            picked.remove(at: index)
        } else {
            picked.append(chip.id)
        }
    }

    /// "5 folders · 217 questions", or "No folders yet".
    var line: String {
        let folders = chips.map(\.folder).filter { picked.contains($0.id) }
        guard !folders.isEmpty else { return "No folders yet" }
        let questions = folders.reduce(0) { $0 + FolderProgress($1).questionCount }
        return "\(Wording.count(folders.count, "folder")) · \(Wording.count(questions, "question"))"
    }

    /// Makes or changes the page. Returns how the editor closes, or nil after a refusal.
    func save() async -> Outcome? {
        guard !isSaving else { return nil }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            problem = "Exam name is required."
            return nil
        }
        if pageID != nil, name == savedName, folderIDs == savedFolders { return .cancelled }
        isSaving = true
        defer { isSaving = false }
        problem = nil
        do {
            if let pageID {
                _ = try await app.client.updateCourseExam(id: pageID, name: name, folderIDs: folderIDs)
                return .saved(pageID)
            }
            let created = try await app.client.createCourseExam(courseID: courseID, name: name, folderIDs: folderIDs)
            return .saved(created.id)
        } catch {
            report(error)
            return nil
        }
    }

    /// Removes the page. Its folders go back to the course's Folders list; no set moves.
    func remove() async -> Outcome? {
        guard let pageID, !isSaving else { return nil }
        isSaving = true
        defer { isSaving = false }
        problem = nil
        do {
            try await app.client.deleteCourseExam(id: pageID)
            return .removed
        } catch {
            report(error)
            return nil
        }
    }

    private func report(_ error: QBankError) {
        guard !app.handle(error) else { return }
        problem = Wording.problem(error)
    }
}
