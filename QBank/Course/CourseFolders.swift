import Foundation
import QBankKit

/// How far she is through a week's practice sets, as the web's week folders count it
/// (`apps/web/src/course/folders.ts`).
nonisolated struct WeekProgress: Equatable {
    /// Nothing answered, some, or every question.
    enum State: Equatable {
        case fresh
        case started
        case done
    }

    let state: State
    let setCount: Int
    let questionCount: Int
    let answeredCount: Int
    let fullyRightCount: Int

    init(_ week: Week) {
        self.init(sets: week.sets)
    }

    init(sets: [PracticeSetSummary]) {
        setCount = sets.count
        questionCount = sets.reduce(0) { $0 + $1.questionCount }
        answeredCount = sets.reduce(0) { $0 + min($1.answeredCount, $1.questionCount) }
        fullyRightCount = sets.reduce(0) { $0 + min($1.fullyRightCount, $1.questionCount) }
        state = answeredCount == 0 ? .fresh : answeredCount >= questionCount ? .done : .started
    }

    /// Answered share for the folder's bar, 0 to 1.
    var fraction: Double {
        questionCount == 0 ? 0 : Double(answeredCount) / Double(questionCount)
    }
}

/// The lines a closed folder shows, worded as on the web.
nonisolated enum FolderWording {
    /// The line under the week name: "2 sets · 27 questions", "2 sets · 22 of 27 answered",
    /// "2 sets · 22 of 27 fully right", or "Exam bank only · 17 questions".
    static func weekMeta(_ week: Week, _ progress: WeekProgress) -> String {
        if progress.setCount == 0 { return "Exam bank only · \(Wording.count(week.examBankCount, "question"))" }
        let sets = Wording.count(progress.setCount, "set")
        switch progress.state {
        case .fresh: return "\(sets) · \(Wording.count(progress.questionCount, "question"))"
        case .done: return "\(sets) · \(progress.fullyRightCount) of \(progress.questionCount) fully right"
        case .started: return "\(sets) · \(progress.answeredCount) of \(progress.questionCount) answered"
        }
    }

    /// The word at the folder's right edge: Done, how far she is, or Not started. Empty for a
    /// folder without practice sets.
    static func state(_ progress: WeekProgress) -> String {
        guard progress.setCount > 0 else { return "" }
        switch progress.state {
        case .done: return "Done"
        case .fresh: return "Not started"
        case .started: return "\(progress.answeredCount) of \(progress.questionCount)"
        }
    }

    /// The exam-bank line inside an open week: "Exam bank: 27 questions, exams only", or that its
    /// exams use practice questions.
    static func examBank(_ week: Week) -> String {
        week.examBankCount > 0
            ? "Exam bank: \(Wording.count(week.examBankCount, "question")), exams only"
            : "No exam bank yet · exams use practice questions"
    }

    /// An exam folder's line: "Weeks 1-3 · 6 sets · 83 questions · 2 exams taken".
    static func examMeta(_ folder: ExamFolder) -> String {
        var parts = [folder.exam.weekLabels.isEmpty ? "No weeks yet" : Wording.weeks(folder.exam.weekLabels)]
        if folder.progress.setCount > 0 {
            parts.append(Wording.count(folder.progress.setCount, "set"))
            parts.append(Wording.count(folder.progress.questionCount, "question"))
        }
        let taken = folder.sittings.count { $0.finishedAt != nil }
        if taken > 0 { parts.append("\(Wording.count(taken, "exam")) taken") }
        return parts.joined(separator: " · ")
    }

    /// Under an exam's Start button: "40 questions from the 83 in its exam banks, or Wrong questions only."
    static func examDraw(_ folder: ExamFolder) -> String? {
        guard folder.examQuestionCount > 0 else { return nil }
        let plan = ExamPlan(folder.weeks.map { ExamPlan.Week(label: $0.label, questionCount: $0.examQuestionCount) })
        let total = folder.examQuestionCount
        let source: String
        if folder.weeks.allSatisfy({ $0.examBankCount > 0 }) {
            source = "the \(total) in its exam banks"
        } else if folder.weeks.allSatisfy({ $0.examBankCount == 0 }) {
            source = "its \(Wording.count(total, "practice question"))"
        } else {
            source = "the \(total) in its exam banks and practice sets"
        }
        return "\(Wording.count(plan.questionCount, "question")) from \(source), or Wrong questions only."
    }
}

extension Week {
    /// How many questions an exam over this week draws from: its exam bank, or its practice
    /// questions when it has none.
    nonisolated var examQuestionCount: Int {
        examBankCount > 0 ? examBankCount : sets.reduce(0) { $0 + $1.questionCount }
    }
}

/// An exam of the course with its weeks and the exams she took over them.
nonisolated struct ExamFolder: Equatable, Identifiable {
    let exam: CourseExam
    /// Its weeks that the course still has, in week order.
    let weeks: [Week]
    /// Her exams over these weeks, the running one first, then newest first.
    let sittings: [ExamSummary]
    let progress: WeekProgress

    var id: String { exam.id }

    var examQuestionCount: Int {
        weeks.reduce(0) { $0 + $1.examQuestionCount }
    }
}

/// The course grouped by exam: each exam's folder, the weeks no exam holds yet, and the exams she
/// took that no single exam holds, such as a final over every week.
nonisolated struct ExamGrouping: Equatable {
    let folders: [ExamFolder]
    let freeWeeks: [Week]
    let otherSittings: [ExamSummary]

    /// - Parameter sittings: Her exams, the running one first, then newest first.
    init(course: CourseDetail, sittings: [ExamSummary]) {
        let exams = course.exams.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
        folders = exams.map { exam in
            let weeks = course.weeks.filter { exam.weekLabels.contains($0.label) }
            return ExamFolder(
                exam: exam,
                weeks: weeks,
                sittings: sittings.filter { Self.courseExam(of: $0, in: exams) == exam.id },
                progress: WeekProgress(sets: weeks.flatMap(\.sets))
            )
        }
        let held = Set(exams.flatMap(\.weekLabels))
        freeWeeks = course.weeks.filter { !held.contains($0.label) }
        otherSittings = sittings.filter { Self.courseExam(of: $0, in: exams) == nil }
    }

    /// The exam a sitting belongs to: the one holding every week it covered, as the server rules
    /// (`courseExamOf`). The server's answer is kept while that exam still holds the weeks; the rule
    /// itself covers a sitting read before the exams changed.
    static func courseExam(of sitting: ExamSummary, in exams: [CourseExam]) -> String? {
        guard !sitting.weeks.isEmpty else { return nil }
        let holds = { (exam: CourseExam) in sitting.weeks.allSatisfy(exam.weekLabels.contains) }
        if let id = sitting.courseExamID, let exam = exams.first(where: { $0.id == id }), holds(exam) { return id }
        return exams.first(where: holds)?.id
    }
}

/// Which folders open on a first visit, and remembering what she opens or closes.
nonisolated enum FolderDefaults {
    /// The weeks open on a first visit: every week she has started but not finished. When there is
    /// none, the newest week opens, so the page never arrives fully folded.
    static func openWeeks(_ weeks: [Week]) -> Set<String> {
        let started = weeks.filter { WeekProgress($0).state == .started }.map(\.label)
        if !started.isEmpty { return Set(started) }
        return weeks.last.map { [$0.label] } ?? []
    }

    /// The exams open on a first visit: those with a week she has started but not finished. When
    /// there is none, the first exam not yet done opens.
    static func openExams(_ folders: [ExamFolder]) -> Set<String> {
        let started = folders.filter { folder in folder.weeks.contains { WeekProgress($0).state == .started } }.map(\.id)
        if !started.isEmpty { return Set(started) }
        return (folders.first { $0.progress.state != .done } ?? folders.first).map { [$0.id] } ?? []
    }
}
