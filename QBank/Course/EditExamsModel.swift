import Foundation
import Observation
import QBankKit

/// The Edit exams sheet: one card per exam with its name and the course's weeks as chips. A week
/// is in one exam at most, so a week another card holds is greyed and names that exam. Done saves
/// every change through the server, which has the last word: a refusal is shown in its words.
@Observable
final class EditExamsModel {
    /// One exam as she edits it.
    struct Draft: Identifiable, Equatable {
        let id: UUID
        /// The exam on the server, or nil for one she added here.
        let examID: String?
        var name: String
        var weeks: Set<String>
    }

    let courseID: String
    /// Every week a chip can stand for: the course's weeks in the server's order, then any week an
    /// exam still holds after its sets were moved away.
    let weekLabels: [String]
    private(set) var drafts: [Draft]
    private(set) var problem: String?
    private(set) var isSaving = false
    /// Something was saved before a refusal stopped the rest, so the course has to be read again.
    private(set) var savedSome = false

    /// The exams as the server has them, kept up to date as each change is saved, so Done after a
    /// refusal sends only what is still to do.
    private var saved: [CourseExam]
    private let practiceCounts: [String: Int]
    private let app: AppModel

    init(app: AppModel, course: CourseDetail) {
        self.app = app
        courseID = course.id
        let exams = course.exams.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
        saved = exams
        practiceCounts = Dictionary(course.weeks.map { week in (week.label, week.sets.reduce(0) { $0 + $1.questionCount }) }, uniquingKeysWith: +)
        let known = course.weeks.map(\.label)
        let orphans = Set(course.exams.flatMap(\.weekLabels)).subtracting(known)
        weekLabels = known + orphans.sorted(by: Self.weekOrder)
        drafts = exams.map { Draft(id: UUID(), examID: $0.id, name: $0.name, weeks: Set($0.weekLabels)) }
    }

    var hasChanges: Bool {
        let current = drafts.map { "\($0.examID ?? "new")|\($0.name)|\($0.weeks.sorted())" }
        let server = saved.map { "\($0.id)|\($0.name)|\(Set($0.weekLabels).sorted())" }
        return current != server
    }

    /// The other exam holding a week, which greys its chip on this card.
    func holder(of week: String, besides draft: Draft) -> Draft? {
        drafts.first { $0.id != draft.id && $0.weeks.contains(week) }
    }

    func toggle(_ week: String, in draft: Draft) {
        guard let index = drafts.firstIndex(where: { $0.id == draft.id }), holder(of: week, besides: draft) == nil else { return }
        if drafts[index].weeks.contains(week) {
            drafts[index].weeks.remove(week)
        } else {
            drafts[index].weeks.insert(week)
        }
    }

    func rename(_ draft: Draft, to name: String) {
        guard let index = drafts.firstIndex(where: { $0.id == draft.id }) else { return }
        drafts[index].name = name
    }

    /// A new card with the next free name: Exam 1, Exam 2, ...
    func addExam() {
        let taken = Set(drafts.map { $0.name.trimmingCharacters(in: .whitespaces).lowercased() })
        var number = drafts.count + 1
        while taken.contains("exam \(number)") { number += 1 }
        drafts.append(Draft(id: UUID(), examID: nil, name: "Exam \(number)", weeks: []))
    }

    /// Takes a card away. Its weeks go back to Not in an exam yet; their sets and her past exams stay.
    func remove(_ draft: Draft) {
        drafts.removeAll { $0.id == draft.id }
    }

    /// "Weeks 1-3 · 83 questions", or "No weeks yet".
    func line(_ draft: Draft) -> String {
        guard !draft.weeks.isEmpty else { return "No weeks yet" }
        let labels = weekLabels.filter(draft.weeks.contains)
        let questions = labels.reduce(0) { $0 + (practiceCounts[$1] ?? 0) }
        return "\(Wording.weeks(labels)) · \(Wording.count(questions, "question"))"
    }

    /// Saves every change. Weeks one exam gives up are released first, so moving a week from one
    /// exam to another is never refused as held. Returns true when everything was saved.
    func save() async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        problem = nil
        do {
            let kept = Set(drafts.compactMap(\.examID))
            for exam in saved where !kept.contains(exam.id) {
                try await app.client.deleteCourseExam(id: exam.id)
                saved.removeAll { $0.id == exam.id }
                savedSome = true
            }
            for draft in drafts {
                guard let id = draft.examID, let exam = saved.first(where: { $0.id == id }) else { continue }
                let keep = exam.weekLabels.filter(draft.weeks.contains)
                guard keep.count < exam.weekLabels.count else { continue }
                record(try await app.client.updateCourseExam(id: id, name: exam.name, weekLabels: keep))
            }
            for index in drafts.indices {
                let draft = drafts[index]
                let weeks = weekLabels.filter(draft.weeks.contains)
                if let id = draft.examID, let exam = saved.first(where: { $0.id == id }) {
                    guard exam.name != draft.name || Set(exam.weekLabels) != draft.weeks else { continue }
                    record(try await app.client.updateCourseExam(id: id, name: draft.name, weekLabels: weeks))
                } else {
                    let created = try await app.client.createCourseExam(courseID: courseID, name: draft.name, weekLabels: weeks)
                    drafts[index] = Draft(id: draft.id, examID: created.id, name: draft.name, weeks: draft.weeks)
                    record(created)
                }
            }
            return true
        } catch {
            if !app.handle(error) {
                problem = Wording.problem(error)
            }
            return false
        }
    }

    private func record(_ exam: CourseExam) {
        if let index = saved.firstIndex(where: { $0.id == exam.id }) {
            saved[index] = exam
        } else {
            saved.append(exam)
        }
        savedSome = true
    }

    /// The server's week order: by the first number in the label, then by name.
    nonisolated static func weekOrder(_ a: String, _ b: String) -> Bool {
        let rank = { (label: String) in label.firstMatch(of: /\d+/).flatMap { Int($0.output) } ?? Int.max }
        let (left, right) = (rank(a), rank(b))
        return left == right ? a.localizedCompare(b) == .orderedAscending : left < right
    }
}
