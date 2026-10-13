import Testing
@testable import QBankKit

/// The server's scoring cases (`packages/questions/src/score.test.ts`), run against the Swift port.
@Suite("Scoring")
struct ScoringTests {
    static func options(_ correct: Set<Int>, count: Int) -> [QuestionOption] {
        (0..<count).map { QuestionOption(text: "Option \($0)", isCorrect: correct.contains($0)) }
    }

    func expectScore(_ body: QuestionBody, _ response: AnswerResponse?, _ points: Int, _ status: ScoreStatus, answered: Bool = true, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let score = try Scoring.score(body, response: response)
        #expect(score.points == points, sourceLocation: sourceLocation)
        #expect(score.status == status, sourceLocation: sourceLocation)
        #expect(score.answered == answered, sourceLocation: sourceLocation)
        #expect((0...score.maxPoints).contains(score.points), sourceLocation: sourceLocation)
    }

    @Test func single() throws {
        let body = QuestionBody.single(options: Self.options([0], count: 4))
        try expectScore(body, .single(choice: 0), 1, .correct)
        try expectScore(body, .single(choice: 1), 0, .incorrect)
        try expectScore(body, .single(choice: 9), 0, .incorrect)
        try expectScore(body, .single(choice: -1), 0, .incorrect)
        #expect(try Scoring.score(body, response: .single(choice: 0)).maxPoints == 1)
    }

    @Test func priority() throws {
        let body = QuestionBody.priority(options: Self.options([2], count: 4))
        try expectScore(body, .priority(choice: 2), 1, .correct)
        try expectScore(body, .priority(choice: 0), 0, .incorrect)
    }

    @Test func selectAll() throws {
        let body = QuestionBody.sata(options: Self.options([0, 2], count: 4))
        #expect(try Scoring.score(body, response: nil).maxPoints == 2)
        try expectScore(body, .sata(picks: [0, 2]), 2, .correct)
        try expectScore(body, .sata(picks: [0]), 1, .partial)
        try expectScore(body, .sata(picks: [0, 1, 2]), 1, .partial)
        try expectScore(body, .sata(picks: [0, 1, 3]), 0, .incorrect)
        try expectScore(body, .sata(picks: [1, 3]), 0, .incorrect)
        try expectScore(body, .sata(picks: [0, 0, 2]), 2, .correct)
        try expectScore(body, .sata(picks: [0, 2, 1, 1]), 1, .partial)
        try expectScore(body, .sata(picks: [0, 2, 9]), 1, .partial)
        try expectScore(body, .sata(picks: []), 0, .incorrect)
    }

    @Test func highlight() throws {
        let body = QuestionBody.highlight(segments: Self.options([1, 2], count: 4))
        try expectScore(body, .highlight(picks: [1, 2]), 2, .correct)
        try expectScore(body, .highlight(picks: [1, 3]), 0, .incorrect)
        try expectScore(body, .highlight(picks: [1]), 1, .partial)
    }

    @Test func order() throws {
        let body = QuestionBody.order(items: ["A", "B", "C", "D"].map { OrderItem(text: $0) })
        try expectScore(body, .order(positions: [0, 1, 2, 3]), 4, .correct)
        try expectScore(body, .order(positions: [0, 2, 1, 3]), 2, .partial)
        try expectScore(body, .order(positions: [1, 0, 3, 2]), 0, .incorrect)
        try expectScore(body, .order(positions: [0, 1, 2, 3, 4]), 4, .correct)
        try expectScore(body, .order(positions: [0, 1]), 2, .partial)
    }

    @Test func match() throws {
        let body = QuestionBody.match(
            pairs: [
                MatchPair(left: "Bradypnea", right: "Slow breathing"),
                MatchPair(left: "Hemoptysis", right: "Coughing up blood"),
                MatchPair(left: "Dyspnea", right: "Shortness of breath"),
            ],
            extra: [MatchExtra(right: "Fast breathing")]
        )
        try expectScore(body, .match(choices: ["Slow breathing", "Coughing up blood", "Shortness of breath"]), 3, .correct)
        try expectScore(body, .match(choices: ["Fast breathing", "Coughing up blood", "Shortness of breath"]), 2, .partial)
        try expectScore(body, .match(choices: ["Coughing up blood", "Shortness of breath", "Slow breathing"]), 0, .incorrect)
        try expectScore(body, .match(choices: ["Slow breathing", nil, nil]), 1, .partial)
    }

    @Test func matrix() throws {
        let body = QuestionBody.matrix(
            columns: ["Indicated", "Nonessential", "Contraindicated"],
            rows: [
                MatrixRow(text: "A", answer: "Indicated"),
                MatrixRow(text: "B", answer: "Nonessential"),
                MatrixRow(text: "C", answer: "Contraindicated"),
            ]
        )
        try expectScore(body, .matrix(choices: ["Indicated", "Nonessential", "Contraindicated"]), 3, .correct)
        try expectScore(body, .matrix(choices: ["Indicated", "Nonessential", "Nonessential"]), 2, .partial)
        try expectScore(body, .matrix(choices: ["Nonessential", "Indicated", "Contraindicated"]), 1, .partial)
        try expectScore(body, .matrix(choices: ["Nonessential", "Indicated", "Indicated"]), 0, .incorrect)
    }

    @Test func cloze() throws {
        let body = QuestionBody.cloze(Cloze(text: "{0} and {1}", blanks: [
            ClozeBlank(options: ["a", "b"], answer: 0),
            ClozeBlank(options: ["c", "d", "e"], answer: 2),
        ]))
        try expectScore(body, .cloze(choices: [0, 2]), 2, .correct)
        try expectScore(body, .cloze(choices: [0, 0]), 1, .partial)
        try expectScore(body, .cloze(choices: [1, 1]), 0, .incorrect)
        try expectScore(body, .cloze(choices: [0, nil]), 1, .partial)
    }

    @Test func unansweredEarnsNothingAndIsNotAnswered() throws {
        let body = QuestionBody.order(items: ["A", "B", "C"].map { OrderItem(text: $0) })
        try expectScore(body, nil, 0, .incorrect, answered: false)
        #expect(try Scoring.score(body, response: nil).maxPoints == 3)
    }

    @Test func reviewRules() throws {
        let body = QuestionBody.sata(options: Self.options([0, 2], count: 4))
        let right = try Scoring.score(body, response: .sata(picks: [0, 2]))
        let wrong = try Scoring.score(body, response: .sata(picks: [1]))
        let partial = try Scoring.score(body, response: .sata(picks: [0]))
        let skipped = try Scoring.score(body, response: nil)
        #expect(right.staysInReview(guessed: true))
        #expect(!right.staysInReview(guessed: false))
        #expect(wrong.staysInReview(guessed: false))
        #expect(partial.staysInReview(guessed: false))
        #expect(!skipped.staysInReview(guessed: false))
        #expect(!skipped.staysInReview(guessed: true))
    }

    @Test func answerInAnotherFormatThrows() {
        #expect(throws: ScoringError.self) {
            try Scoring.score(.single(options: Self.options([0], count: 3)), response: .sata(picks: [0]))
        }
        #expect(throws: ScoringError.self) {
            try Scoring.score(.unsupported(typeName: "hotspot"), response: nil)
        }
    }
}
