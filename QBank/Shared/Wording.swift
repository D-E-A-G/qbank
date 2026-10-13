import Foundation
import QBankKit

/// The lines the screens show, worded as the web app words them.
nonisolated enum Wording {
    /// "1 question", "86 questions".
    static func count(_ number: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(number) \(number == 1 ? singular : plural ?? singular + "s")"
    }

    /// "today", or a short month and day such as "Oct 3" in the phone's language.
    static func when(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "today" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// The course line on Home and under the Course title: "86 questions · 3 weeks".
    static func size(questions: Int, weeks: Int) -> String {
        "\(count(questions, "question")) · \(count(weeks, "week"))"
    }

    /// "35 of 86 answered · 24 fully right · 61 of 92 points", or nil before her first answer.
    static func score(_ course: CourseDetail) -> String? {
        guard course.answeredCount > 0 else { return nil }
        return "\(course.answeredCount) of \(course.questionCount) answered · \(course.fullyRightCount) fully right · \(course.points) of \(course.maxPoints) points"
    }

    /// Share of the course's questions she has answered, 0 to 100, as the Home card shows it.
    static func answeredPercent(_ course: CourseSummary) -> Int {
        guard course.questionCount > 0 else { return 0 }
        let answered = min(course.answeredCount, course.questionCount)
        return Int((Double(answered) / Double(course.questionCount) * 100).rounded())
    }

    /// How long an exam over every week takes: 60 minutes for 40 questions, or 1.5 minutes a
    /// question when there are fewer. "Not ready" without questions.
    static func examLength(questionCount: Int) -> String {
        guard questionCount > 0 else { return "Not ready" }
        let minutes = Double(min(questionCount, 40) * 90) / 60
        return minutes.rounded() == minutes ? "\(Int(minutes)) min" : String(format: "%.1f min", minutes)
    }

    /// A set's line on the Course screen: when it arrived, how far she got, or how it went.
    static func status(_ set: PracticeSetSummary, now: Date = .now) -> String {
        if set.answeredCount == 0 {
            let word = switch set.status {
            case .imported: "Imported"
            case .replaced: "Replaced"
            case .restored: "Restored"
            }
            return "\(word) \(when(set.activeSince, now: now)) · \(count(set.questionCount, "question"))"
        }
        if set.questionCount > 0, set.answeredCount >= set.questionCount {
            let finished = set.lastAnsweredAt ?? set.activeSince
            return "Done \(when(finished, now: now)) · \(set.fullyRightCount) of \(set.questionCount) fully right"
        }
        return "\(set.answeredCount) of \(set.questionCount) answered"
    }

    /// The week's exam line: its exam bank, or that its exams use practice questions.
    static func examBank(_ week: Week) -> String {
        week.examBankCount > 0
            ? "Exam bank · \(count(week.examBankCount, "question"))"
            : "No exam bank yet · exams use practice questions"
    }

    /// What went wrong, in words for her. The server's own messages are written for her, so they
    /// are shown as they come; everything else is said plainly. Nil when there is nothing to say.
    static func problem(_ error: QBankError) -> String? {
        switch error {
        case .server(let server):
            return server.message
        case .transport(let code):
            switch code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
                return "No connection. Check Wi-Fi or cellular data and try again."
            case .timedOut:
                return "QBank took too long to answer. Try again."
            default:
                return "QBank could not be reached. Try again in a moment."
            }
        case .unexpectedResponse(let status, _):
            return status >= 500
                ? "QBank is having trouble right now. Try again in a moment."
                : "Something went wrong. Try again."
        case .storage:
            return "This iPhone could not keep your sign-in. Try again."
        case .notSignedIn:
            return "Sign in to continue."
        case .invalidRequest:
            return "Something went wrong. Try again."
        case .cancelled:
            return nil
        }
    }
}
