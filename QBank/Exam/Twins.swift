import Foundation
import QBankKit

/// The Twin option's rules and words, as the web's (`apps/web/src/exam/twins.ts`): when Exam setup
/// offers Write exam twins and lists her twin jobs, and how a twin job and its steps read.
nonisolated enum Twins {
    /// The Twin option shows only while the server says this account may make questions now.
    static func canTwin(_ status: QuestionMakerStatus?) -> Bool {
        status?.available == true
    }

    /// Whether her twin jobs can be listed: she may make questions, now or once the daily limit
    /// passes. Any other account is refused by the twin-job routes, so they are not asked.
    static func listsJobs(_ status: QuestionMakerStatus?) -> Bool {
        guard let status else { return false }
        return status.available || status.nextAvailableAt != nil
    }

    /// Her twin jobs over this course, newest first as the server sends them.
    static func jobs(_ jobs: [TwinJob], courseID: String) -> [TwinJob] {
        jobs.filter { $0.course.id == courseID }
    }

    /// A job that is still writing is read again until it is done, failed, or cancelled.
    static func isRunning(_ job: TwinJob) -> Bool {
        job.status == .running
    }

    /// The line under Start exam: what Write exam twins does instead.
    static func offer(wrongOnly: Bool) -> String {
        "Or QBank writes a new exam twin of each \(wrongOnly ? "wrong question" : "question") in the folders you tick, and you take the exam on the twins. Your questions stay as they are."
    }

    /// The word at the right of a twin job's row: what it is doing, or how it ended. Nil for a
    /// status this version does not know.
    static func state(_ job: TwinJob) -> String? {
        switch job.status {
        case .running: "Writing"
        case .done: "Ready"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        default: nil
        }
    }

    /// "Week 5", or "Weeks 4-6": the folders she picked, as a past exam names them.
    static func title(_ job: TwinJob) -> String {
        Wording.folders(job.folders.map(\.name))
    }

    /// "Week 5 · today", as a past exam's row.
    static func rowTitle(_ job: TwinJob, now: Date = .now) -> String {
        "\(title(job)) · \(Wording.when(job.createdAt, now: now))"
    }

    /// "1 exam twin", "5 exam twins".
    static func count(_ job: TwinJob) -> String {
        Wording.count(job.twinCount, "exam twin")
    }

    /// "5 exam twins · Wrong questions only".
    static func meta(_ job: TwinJob) -> String {
        job.pool == .wrong ? "\(count(job)) · Wrong questions only" : count(job)
    }

    /// "Week 5 · Wrong questions only", under the count on the job's screen.
    static func scope(_ job: TwinJob) -> String {
        job.pool == .wrong ? "\(title(job)) · Wrong questions only" : title(job)
    }

    /// How far a step is: "Done", "2 of 5" while it runs, or how it stopped. A step not reached yet
    /// says nothing.
    static func progress(_ step: TwinJob.Step) -> String {
        switch step.state {
        case .done: return "Done"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        case .todo: return ""
        default:
            if let done = step.done, let total = step.total { return "\(done) of \(total)" }
            return "Working"
        }
    }

    /// A filed exam set's second line: "Week 5 · 2 questions · Twins of Week 5 Harder A".
    static func filed(_ set: TwinJob.FiledSet) -> String {
        "\(set.folderName) · \(Wording.count(set.questionCount, "question")) · Twins of \(set.twinsOf.title)"
    }

    static let stopped = "Stopped. Your questions stay as they are."
    static let nothingFiled = "Nothing was filed."
}
