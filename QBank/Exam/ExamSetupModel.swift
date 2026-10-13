import Foundation
import Observation
import QBankKit

/// Exam setup, as the web's (`apps/web/src/exam/ExamSetupScreen.tsx`): the weeks to tick with
/// their question or wrong counts, Wrong questions only, the summary of what Start draws, her
/// running exam, and her past exams.
@Observable
final class ExamSetupModel {
    let route: ExamSetupRoute
    private(set) var setup: ExamSetup?
    /// When the setup arrived, for the running exam's minutes left.
    private(set) var loadedAt = Date.now
    private(set) var ticked: Set<String> = []
    var wrongOnly = false
    private(set) var isStarting = false
    private(set) var problem: String?

    private let app: AppModel
    private let now: () -> Date
    private var hasTicked = false

    init(app: AppModel, route: ExamSetupRoute, now: @escaping () -> Date = { .now }) {
        self.app = app
        self.route = route
        self.now = now
    }

    var course: CourseRef { route.course }

    /// Exams start and end on the server, so without a connection none can start.
    var needsConnection: Bool {
        !app.connection.isOnline
    }

    /// Only she starts exams; the owner sees the setup read-only.
    var isStudent: Bool {
        app.account?.role == .student
    }

    var weeks: [ExamSetup.Week] {
        setup?.weeks ?? []
    }

    /// The questions a week gives: all of them, or with Wrong questions only her wrong ones.
    func poolSize(_ week: ExamSetup.Week) -> Int {
        wrongOnly ? week.wrongCount : week.questionCount
    }

    /// A week with nothing to draw cannot be ticked. Its tick comes back when the switch is off.
    func canTick(_ week: ExamSetup.Week) -> Bool {
        poolSize(week) > 0
    }

    func isTicked(_ week: ExamSetup.Week) -> Bool {
        canTick(week) && ticked.contains(week.label)
    }

    func toggle(_ week: ExamSetup.Week) {
        guard isStudent, canTick(week) else { return }
        if ticked.contains(week.label) {
            ticked.remove(week.label)
        } else {
            ticked.insert(week.label)
        }
    }

    /// The ticked weeks that give questions, in week order.
    var picked: [ExamSetup.Week] {
        weeks.filter(isTicked)
    }

    var plan: ExamPlan {
        ExamPlan(picked.map { ExamPlan.Week(label: $0.label, questionCount: poolSize($0)) })
    }

    /// "4 in exam" beside a ticked week.
    func drawn(_ week: ExamSetup.Week) -> Int? {
        guard isTicked(week) else { return nil }
        return plan.weeks.first { $0.label == week.label }?.drawn
    }

    /// "27 questions", or "7 wrong of 20" with Wrong questions only on, and "· exam bank" when the
    /// week has one.
    func meta(_ week: ExamSetup.Week) -> String {
        let count = wrongOnly
            ? "\(week.wrongCount) wrong of \(week.questionCount)"
            : Wording.count(week.questionCount, "question")
        return week.source == .exam ? "\(count) · exam bank" : count
    }

    /// The summary's first line: "11 questions", with its time beside it. Nil before a tick.
    var summaryCount: String? {
        picked.isEmpty ? nil : Wording.count(plan.questionCount, "question")
    }

    var summaryTime: String {
        "in \(Wording.minutes(seconds: plan.timeLimitSeconds))"
    }

    /// "4 from Week 1 · 7 from Week 2 · Fewer than 40, so it’s all of them at 1.5 minutes each.",
    /// or what to tick.
    var summarySplit: String {
        if picked.isEmpty {
            if !wrongOnly { return "Tick at least one week." }
            return weeks.allSatisfy { $0.wrongCount == 0 }
                ? "No wrong questions in this course right now."
                : "Tick at least one week with wrong questions."
        }
        let split = plan.weeks.map { "\($0.drawn) from \($0.label)" }.joined(separator: " · ")
        guard plan.questionCount < ExamPlan.maxQuestions else { return split }
        return "\(split) · Fewer than \(ExamPlan.maxQuestions), so it’s all of them at 1.5 minutes each."
    }

    /// The ticked weeks without an exam bank, named only once the course has one, as the server does.
    var fallbackLine: String? {
        guard weeks.contains(where: { $0.source == .exam }) else { return nil }
        let practice = picked.filter { $0.source == .practice }.map(\.label)
        return practice.isEmpty ? nil : Wording.practiceWeeks(practice, before: true)
    }

    var footer: String {
        wrongOnly
            ? "Questions are drawn only from the wrong ones in the weeks you tick, in proportion to how many each week has."
            : "Questions are drawn only from the weeks you tick, in proportion to each week’s size."
    }

    /// "Exam 1 · Weeks 1-3 ticked for you", when she came from an exam's Start button.
    var preselectedLine: String? {
        guard let name = route.examName, !route.weeks.isEmpty else { return nil }
        return "\(name) · \(Wording.weeks(route.weeks)) ticked for you"
    }

    /// "Weeks 1-2 · Wrong questions only · 3 of 11 answered · 12 min left".
    func runningLine(_ exam: ExamSummary) -> String {
        let minutesLeft = max(1, Int((exam.endsAt.timeIntervalSince(loadedAt) / 60).rounded(.up)))
        var parts = [Wording.weeks(exam.weeks)]
        if exam.pool == .wrong { parts.append("Wrong questions only") }
        parts.append("\(exam.answeredCount) of \(exam.questionCount) answered")
        parts.append("\(minutesLeft) min left")
        return parts.joined(separator: " · ")
    }

    // MARK: Loading and starting

    func load() async {
        do {
            let loaded = try await app.client.examSetup(courseID: course.id)
            setup = loaded
            loadedAt = now()
            problem = nil
            if !hasTicked {
                hasTicked = true
                let labels = Set(loaded.weeks.map(\.label))
                ticked = Set(route.weeks.filter(labels.contains))
            }
        } catch {
            report(error)
        }
    }

    /// Starts the exam over the ticked weeks. A running exam of hers ends first, which she was
    /// asked about. Returns the new exam to open, or nil after a refusal, said in her words.
    func start() async -> Exam? {
        guard isStudent, !picked.isEmpty, !isStarting, !needsConnection else { return nil }
        isStarting = true
        defer { isStarting = false }
        problem = nil
        do {
            return try await app.client.startExam(courseID: course.id, weeks: picked.map(\.label), pool: wrongOnly ? .wrong : .all)
        } catch {
            report(error)
            return nil
        }
    }

    private func report(_ error: QBankError) {
        guard !app.handle(error) else { return }
        // Without a connection the screen says exams need one; the transport error adds nothing.
        if case .transport = error, needsConnection {
            problem = nil
            return
        }
        problem = Wording.problem(error)
    }
}

extension ExamSummary {
    /// A past exam's second line: "52 min · Wrong questions only · Time ran out".
    nonisolated var pastLine: String {
        var line = "\(minutesUsed ?? 0) min"
        if pool == .wrong { line += " · Wrong questions only" }
        switch endReason {
        case .timeout: line += " · Time ran out"
        case .left: line += " · Ended early"
        case .finished, nil: break
        }
        return line
    }

    /// "Weeks 1-2 · Oct 9".
    nonisolated var pastTitle: String {
        "\(Wording.weeks(weeks)) · \(Wording.when(finishedAt ?? startedAt))"
    }

    /// "31 of 40".
    nonisolated var scoreText: String {
        "\(fullyRight ?? 0) of \(questionCount)"
    }
}
