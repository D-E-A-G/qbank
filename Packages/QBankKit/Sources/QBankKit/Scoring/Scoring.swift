import Foundation

// The server's scoring rules (`packages/questions/src/score.ts`), so an answer given without
// signal shows the same mark on the phone that the server records when it is sent.

/// The result of scoring one question. `points` is never below 0 or above `maxPoints`.
public struct Score: Sendable, Equatable {
    public let points: Int
    public let maxPoints: Int
    public let status: ScoreStatus
    /// False when she skipped the question or never reached it. An empty submission is still answered.
    public let answered: Bool

    /// Whether this answer keeps the question in Review. A guess stays even when fully right;
    /// a question she did not answer never enters Review.
    public func staysInReview(guessed: Bool) -> Bool {
        answered && (guessed || status != .correct)
    }
}

/// An answer in a different format from its question, or a question format this version cannot score.
public struct ScoringError: Error, Sendable, Equatable {
    public let message: String
}

public enum Scoring {
    /// Scores one question. Pass nil for a question she skipped or never reached.
    ///
    /// The maximum is 1 for single and priority, the number of correct options for select-all and
    /// highlight, and one point per item, pair, row, or blank for the rest. A wrong, empty, or
    /// out-of-range answer is scored; only an answer in another format throws.
    public static func score(_ body: QuestionBody, response: AnswerResponse?) throws(ScoringError) -> Score {
        let maxPoints = try maximum(for: body)
        guard let response else {
            return Score(points: 0, maxPoints: maxPoints, status: status(0, maxPoints), answered: false)
        }
        let points = min(maxPoints, try earned(body, response))
        return Score(points: points, maxPoints: maxPoints, status: status(points, maxPoints), answered: true)
    }

    private static func status(_ points: Int, _ maxPoints: Int) -> ScoreStatus {
        if points == maxPoints { return .correct }
        if points > 0 { return .partial }
        return .incorrect
    }

    private static func maximum(for body: QuestionBody) throws(ScoringError) -> Int {
        switch body {
        case .single, .priority: 1
        case .sata(let options): options.count(where: \.isCorrect)
        case .highlight(let segments): segments.count(where: \.isCorrect)
        case .order(let items): items.count
        case .match(let pairs, _): pairs.count
        case .matrix(_, let rows): rows.count
        case .cloze(let cloze): cloze.blanks.count
        case .unsupported(let typeName): throw ScoringError(message: "Cannot score a \(typeName) question.")
        }
    }

    private static func earned(_ body: QuestionBody, _ response: AnswerResponse) throws(ScoringError) -> Int {
        switch (body, response) {
        case (.single(let options), .single(let choice)), (.priority(let options), .priority(let choice)):
            return options.indices.contains(choice) && options[choice].isCorrect ? 1 : 0
        case (.sata(let options), .sata(let picks)), (.highlight(let options), .highlight(let picks)):
            return plusMinus(options, picks)
        case (.order(let items), .order(let positions)):
            return zip(positions.prefix(items.count), 0...).count { $0 == $1 }
        case (.match(let pairs, _), .match(let choices)):
            return exact(pairs.map(\.right), choices)
        case (.matrix(_, let rows), .matrix(let choices)):
            return exact(rows.map(\.answer), choices)
        case (.cloze(let cloze), .cloze(let choices)):
            return exact(cloze.blanks.map(\.answer), choices)
        default:
            let expected = body.type?.rawValue ?? "unknown"
            throw ScoringError(message: "Cannot score a \(expected) question with a \(response.type.rawValue) answer.")
        }
    }

    // +1 for each correct option picked, -1 for each wrong one, never below 0.
    // A repeated index counts once, so it cannot raise the score.
    private static func plusMinus(_ options: [QuestionOption], _ picks: [Int]) -> Int {
        var seen = Set<Int>()
        var good = 0
        var bad = 0
        for index in picks where seen.insert(index).inserted {
            if options.indices.contains(index) && options[index].isCorrect {
                good += 1
            } else {
                bad += 1
            }
        }
        return max(0, good - bad)
    }

    private static func exact<T: Equatable>(_ expected: [T], _ choices: [T?]) -> Int {
        expected.indices.count { index in index < choices.count && choices[index] == expected[index] }
    }
}
