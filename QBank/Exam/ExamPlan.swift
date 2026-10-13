import Foundation

/// How many questions an exam over the ticked weeks takes from each, and its time: the server's
/// `planExam` (`packages/questions/src/exam.ts`), so the summary she reads before Start is the
/// exam she gets.
///
/// Up to 40 questions in 60 minutes. When the weeks hold fewer than 40, the exam is all of them
/// at 1.5 minutes each. A larger pool is split in proportion to each week's size by largest
/// remainder, so Weeks 1 to 3 holding 22, 27, and 37 give 10 + 13 + 17. A week with questions
/// always gives at least one, so every ticked week stays represented.
nonisolated struct ExamPlan: Equatable {
    /// A ticked week with the questions it holds.
    struct Week: Equatable {
        let label: String
        let questionCount: Int
    }

    /// One row per ticked week, in the order given.
    struct Draw: Equatable {
        let label: String
        let questionCount: Int
        /// How many of the week's questions the exam takes.
        let drawn: Int
    }

    static let maxQuestions = 40
    static let fullSeconds = 60 * 60
    static let secondsPerQuestion = 90

    let questionCount: Int
    let timeLimitSeconds: Int
    let weeks: [Draw]

    init(_ weeks: [Week]) {
        let sizes = weeks.map { max(0, $0.questionCount) }
        let pool = sizes.reduce(0, +)
        guard pool > Self.maxQuestions else {
            questionCount = pool
            timeLimitSeconds = pool * Self.secondsPerQuestion
            self.weeks = zip(weeks, sizes).map { Draw(label: $0.label, questionCount: $1, drawn: $1) }
            return
        }

        let quotas = sizes.map { Double($0 * Self.maxQuestions) / Double(pool) }
        var drawn = quotas.map { Int($0.rounded(.down)) }
        var left = Self.maxQuestions - drawn.reduce(0, +)
        let byRemainder = quotas.indices.sorted { a, b in
            let ra = quotas[a] - quotas[a].rounded(.down), rb = quotas[b] - quotas[b].rounded(.down)
            if ra != rb { return ra > rb }
            if sizes[a] != sizes[b] { return sizes[a] > sizes[b] }
            return a < b
        }
        for index in byRemainder where left > 0 {
            drawn[index] += 1
            left -= 1
        }

        // A small week next to large ones can round to 0. It borrows one from the week that is
        // furthest over its share, so the total stays 40.
        let surplus = { (index: Int) in Double(drawn[index]) - quotas[index] }
        for index in drawn.indices where sizes[index] > 0 && drawn[index] == 0 {
            var lender: Int?
            for other in drawn.indices where drawn[other] > 1 {
                if let current = lender, surplus(other) <= surplus(current) { continue }
                lender = other
            }
            guard let lender else { break }
            drawn[lender] -= 1
            drawn[index] = 1
        }

        questionCount = Self.maxQuestions
        timeLimitSeconds = Self.fullSeconds
        self.weeks = weeks.indices.map { Draw(label: weeks[$0].label, questionCount: sizes[$0], drawn: drawn[$0]) }
    }
}
