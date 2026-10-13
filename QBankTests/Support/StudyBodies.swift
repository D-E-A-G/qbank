import Foundation

/// Invented server bodies for slice 1c, shaped like the real routes' answers: Review, exams, and
/// courses with exams.
enum StudyBodies {
    static func week(_ label: String, sets: [String], bank: Int = 0) -> String {
        #"{"label":"\#(label)","sets":[\#(sets.joined(separator: ","))],"examBankCount":\#(bank)}"#
    }

    static func set(_ id: String, questions: Int, answered: Int = 0, right: Int = 0) -> String {
        let ids = (0..<questions).map { #""\#(id)-q\#($0)""# }.joined(separator: ",")
        let last = answered == 0 ? "null" : #""2026-10-10T00:00:00.000Z""#
        return #"{"id":"\#(id)","title":"Invented \#(id)","description":"","questionCount":\#(questions),"importedAt":"2026-10-01T00:00:00.000Z","activeSince":"2026-10-01T00:00:00.000Z","status":"imported","canRestore":false,"answeredCount":\#(answered),"fullyRightCount":\#(right),"lastAnsweredAt":\#(last),"questionIds":[\#(ids)]}"#
    }

    static func courseExam(_ id: String, _ name: String, order: Int, weeks: [String]) -> String {
        #"{"id":"\#(id)","name":"\#(name)","sortOrder":\#(order),"weekLabels":[\#(weeks.map { "\"\($0)\"" }.joined(separator: ","))]}"#
    }

    /// A course of three weeks: Week 1 done, Week 2 started, Week 3 not started with an exam bank.
    static func course(id: String = "c1", exams: [String]? = []) -> String {
        let weeks = [
            week("Week 1", sets: [set("w1", questions: 10, answered: 10, right: 8)]),
            week("Week 2", sets: [set("w2a", questions: 6, answered: 2, right: 1), set("w2b", questions: 4)]),
            week("Week 3", sets: [set("w3", questions: 12)], bank: 20),
        ]
        let examsField = exams.map { #","exams":[\#($0.joined(separator: ","))]"# } ?? ""
        return #"{"id":"\#(id)","code":"NURS 101","title":"Invented Basics","archivedAt":null,"semester":{"id":"s1","number":1,"name":"Semester 1"},"questionCount":32,"examQuestionCount":40,"weekCount":3,"termCount":4,"reviewCount":2,"answeredCount":12,"fullyRightCount":9,"points":9,"maxPoints":12,"weeks":[\#(weeks.joined(separator: ","))]\#(examsField)}"#
    }

    static func summary(
        _ id: String, weeks: [String], courseExam: String? = nil, pool: String = "all",
        finished: Bool = true, reason: String = "finished", answered: Int = 3, questions: Int = 5, right: Int = 2,
        endsAt: String = "2026-10-12T01:00:00.000Z"
    ) -> String {
        let weekList = weeks.map { "\"\($0)\"" }.joined(separator: ",")
        let courseExamField = courseExam.map { "\"\($0)\"" } ?? "null"
        let score = finished ? #""fullyRight":\#(right),"points":\#(right),"maxPoints":\#(questions),"minutesUsed":12"# : #""fullyRight":null,"points":null,"maxPoints":null,"minutesUsed":null"#
        return #"{"id":"\#(id)","courseId":"c1","weeks":[\#(weekList)],"courseExamId":\#(courseExamField),"pool":"\#(pool)","practiceWeeks":null,"questionCount":\#(questions),"timeLimitSeconds":\#(questions * 90),"startedAt":"2026-10-12T00:00:00.000Z","endsAt":"\#(endsAt)","finishedAt":\#(finished ? #""2026-10-12T00:12:00.000Z""# : "null"),"endReason":\#(finished ? "\"\(reason)\"" : "null"),"answeredCount":\#(answered),\#(score)}"#
    }

    static func setup(weeks: [(label: String, count: Int, wrong: Int, source: String)], inProgress: String? = nil, exams: [String] = []) -> String {
        let weekList = weeks.map { #"{"label":"\#($0.label)","questionCount":\#($0.count),"wrongCount":\#($0.wrong),"source":"\#($0.source)"}"# }
        return #"{"courseId":"c1","weeks":[\#(weekList.joined(separator: ","))],"inProgress":\#(inProgress ?? "null"),"exams":[\#(exams.joined(separator: ","))]}"#
    }

    /// The setup of `course()`: Week 3 has an exam bank, and only Weeks 1 and 2 have wrong questions.
    static let threeWeeks: [(label: String, count: Int, wrong: Int, source: String)] = [
        ("Week 1", 10, 2, "practice"), ("Week 2", 10, 3, "practice"), ("Week 3", 20, 0, "exam"),
    ]

    static func question(_ id: String, position: Int, type: String = "single") -> String {
        switch type {
        case "sata":
            return #"{"id":"\#(id)","publicId":"Q\#(position)","position":\#(position),"type":"sata","topic":"Invented \#(id)","cj":"Analyze cues","weekLabel":"Week 1","stem":"Stem.","ask":"Which apply?","rationale":"Because.","takeaway":"Remember.","terms":[],"body":{"options":[{"t":"A","ok":true},{"t":"B"},{"t":"C","ok":true}]}}"#
        default:
            return #"{"id":"\#(id)","publicId":"Q\#(position)","position":\#(position),"type":"single","topic":"Invented \#(id)","cj":"Take action","weekLabel":"Week 1","stem":"Stem.","ask":"Which one?","rationale":"Because.","takeaway":"Remember.","terms":[],"body":{"options":[{"t":"Right","ok":true},{"t":"Wrong"},{"t":"Also wrong"}]}}"#
        }
    }

    /// An exam of `count` single-answer questions, `e1-q0` and on, with 10 minutes left by the
    /// server's clock unless it ended.
    static func exam(
        id: String = "e1", count: Int = 3, answered: [String] = [], ended: String? = nil,
        serverNow: String = "2026-10-12T00:05:00.000Z", endsAt: String = "2026-10-12T00:15:00.000Z", result: String = "null"
    ) -> String {
        let questions = (0..<count).map { question("\(id)-q\($0)", position: $0 + 1) }.joined(separator: ",")
        let answeredList = answered.map { "\"\($0)\"" }.joined(separator: ",")
        return #"{"id":"\#(id)","courseId":"c1","courseCode":"NURS 101","courseTitle":"Invented Basics","weeks":["Week 1","Week 2"],"pool":"wrong","practiceWeeks":null,"timeLimitSeconds":\#(count * 90),"startedAt":"2026-10-12T00:00:00.000Z","endsAt":"\#(endsAt)","finishedAt":\#(ended == nil ? "null" : #""2026-10-12T00:10:00.000Z""#),"endReason":\#(ended.map { "\"\($0)\"" } ?? "null"),"serverNow":"\#(serverNow)","questions":[\#(questions)],"answeredQuestionIds":[\#(answeredList)],"result":\#(result)}"#
    }

    static func result(count: Int = 3) -> String {
        let items = (0..<count).map { #"{"questionId":"e1-q\#($0)","status":"\#($0 == 0 ? "correct" : "unanswered")","points":\#($0 == 0 ? 1 : 0),"maxPoints":1,"guessed":false,"response":\#($0 == 0 ? #"{"type":"single","choice":0}"# : "null"),"shuffle":null}"# }
        return #"{"questionCount":\#(count),"answered":1,"unanswered":\#(count - 1),"fullyRight":1,"partial":0,"missed":0,"guessed":0,"points":1,"maxPoints":\#(count),"minutesUsed":10,"reviewCount":0,"examBankWrong":0,"byWeek":[{"label":"Week 1","right":1,"total":\#(count)}],"byStep":[{"label":"Take action","right":1,"total":\#(count)}],"items":[\#(items.joined(separator: ","))]}"#
    }

    static func saved(question: String, attempt: String, status: String = "correct") -> String {
        #"{"clientAttemptId":"\#(attempt)","questionId":"\#(question)","courseId":"c1","status":"\#(status)","points":1,"maxPoints":1,"guessed":false,"answeredAt":"2026-10-12T00:06:00.000Z","inReview":false,"label":"Correct","replayed":false}"#
    }

    static func review(filter: String = "all", counts: (Int, Int, Int, Int) = (2, 1, 1, 1), questions: [String] = [reviewQuestion("q1", status: "incorrect", guessed: true), reviewQuestion("q2", status: "partial")]) -> String {
        #"{"filter":"\#(filter)","counts":{"all":\#(counts.0),"missed":\#(counts.1),"partial":\#(counts.2),"guessed":\#(counts.3)},"questions":[\#(questions.joined(separator: ","))]}"#
    }

    static func reviewQuestion(_ id: String, status: String, guessed: Bool = false) -> String {
        #"{"questionId":"\#(id)","topic":"Invented \#(id)","weekLabel":"Week 1","format":"Single answer","status":"\#(status)","guessed":\#(guessed),"answeredAt":"2026-10-10T00:00:00.000Z","setTitle":"Invented set"}"#
    }
}
