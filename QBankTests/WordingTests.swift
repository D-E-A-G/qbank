import Foundation
import QBankKit
import Testing
@testable import QBank

struct WordingTests {
    private let now = QBankJSON.parseDate("2026-10-12T15:00:00.000Z")!

    @Test func counts() {
        #expect(Wording.count(1, "question") == "1 question")
        #expect(Wording.count(86, "question") == "86 questions")
        #expect(Wording.size(questions: 1, weeks: 3) == "1 question · 3 weeks")
    }

    @Test func todayOrAShortDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        #expect(Wording.when(now.addingTimeInterval(-3600), now: now, calendar: calendar) == "today")
        #expect(Wording.when(now.addingTimeInterval(-9 * 86_400), now: now, calendar: calendar) != "today")
    }

    @Test(arguments: [(0, "Not ready"), (4, "6 min"), (5, "7.5 min"), (39, "58.5 min"), (40, "60 min"), (134, "60 min")])
    func examLength(questions: Int, expected: String) {
        #expect(Wording.examLength(questionCount: questions) == expected)
    }

    @Test func examBankLine() throws {
        let weeks = try QBankJSON.decoder.decode([Week].self, from: Data(#"""
        [{"label":"Week 1","sets":[],"examBankCount":17},{"label":"Week 2","sets":[],"examBankCount":1},{"label":"Week 3","sets":[],"examBankCount":0}]
        """#.utf8))
        #expect(weeks.map(Wording.examBank) == [
            "Exam bank · 17 questions",
            "Exam bank · 1 question",
            "No exam bank yet · exams use practice questions",
        ])
    }

    @Test func setStatusLines() throws {
        func set(_ status: String, answered: Int, right: Int = 0, last: String = "null") throws -> PracticeSetSummary {
            try QBankJSON.decoder.decode(PracticeSetSummary.self, from: Data(#"""
            {"id":"s","title":"t","description":"","questionCount":17,"importedAt":"2026-10-12T09:00:00.000Z","activeSince":"2026-10-12T09:00:00.000Z","status":"\#(status)","canRestore":false,"answeredCount":\#(answered),"fullyRightCount":\#(right),"lastAnsweredAt":\#(last),"questionIds":[]}
            """#.utf8))
        }
        #expect(Wording.status(try set("imported", answered: 0), now: now) == "Imported today · 17 questions")
        #expect(Wording.status(try set("replaced", answered: 0), now: now) == "Replaced today · 17 questions")
        #expect(Wording.status(try set("restored", answered: 0), now: now) == "Restored today · 17 questions")
        #expect(Wording.status(try set("imported", answered: 9), now: now) == "9 of 17 answered")
        #expect(Wording.status(try set("imported", answered: 17, right: 13, last: #""2026-10-12T10:00:00.000Z""#), now: now) == "Done today · 13 of 17 fully right")
    }

    @Test func answeredPercentRoundsAndCaps() throws {
        func course(questions: Int, answered: Int) throws -> CourseSummary {
            try QBankJSON.decoder.decode(CourseSummary.self, from: Data(#"""
            {"id":"c","code":"N","title":"T","sortOrder":1,"archivedAt":null,"questionCount":\#(questions),"weekCount":1,"reviewCount":0,"answeredCount":\#(answered),"fullyRightCount":0,"points":0,"maxPoints":0}
            """#.utf8))
        }
        #expect(Wording.answeredPercent(try course(questions: 86, answered: 35)) == 41)
        #expect(Wording.answeredPercent(try course(questions: 10, answered: 12)) == 100)
        #expect(Wording.answeredPercent(try course(questions: 0, answered: 0)) == 0)
    }

    @Test func problemsInPlainWords() {
        #expect(Wording.problem(.server(ServerError(status: 401, code: .invalidCredentials, message: "That email or password is not right."))) == "That email or password is not right.")
        #expect(Wording.problem(.transport(.notConnectedToInternet)) == "No connection. Check Wi-Fi or cellular data and try again.")
        #expect(Wording.problem(.transport(.timedOut)) == "QBank took too long to answer. Try again.")
        #expect(Wording.problem(.transport(.cannotFindHost)) == "QBank could not be reached. Try again in a moment.")
        #expect(Wording.problem(.unexpectedResponse(status: 502, detail: "Bad Gateway")) == "QBank is having trouble right now. Try again in a moment.")
        #expect(Wording.problem(.unexpectedResponse(status: 200, detail: "")) == "Something went wrong. Try again.")
        #expect(Wording.problem(.cancelled) == nil)
    }

    @Test func formatsUseTheWebsLabels() {
        #expect(Wording.format(.single) == "Single answer")
        #expect(Wording.format(.priority) == "Priority / first action")
        #expect(Wording.format(.sata) == "Select all that apply")
        #expect(Wording.format(.highlight) == "Highlight")
        #expect(Wording.format(.order) == "Ordering")
        #expect(Wording.format(.match) == "Matching")
        #expect(Wording.format(.matrix) == "Matrix")
        #expect(Wording.format(.cloze) == "Drop-down")
        #expect(Wording.format(nil) == "Question")
    }

    @Test func durationIsSecondsThenWholeMinutes() {
        #expect(Wording.duration(0) == "0 sec")
        #expect(Wording.duration(44.6) == "45 sec")
        #expect(Wording.duration(59.4) == "59 sec")
        #expect(Wording.duration(60) == "1 min")
        #expect(Wording.duration(89) == "1 min")
        #expect(Wording.duration(90) == "2 min")
        #expect(Wording.duration(24 * 60 + 10) == "24 min")
        #expect(Wording.duration(-5) == "0 sec")
    }

    @Test func savedTimesAreTheTimeTodayOrTheDate() {
        let earlier = now.addingTimeInterval(-60)
        let today = Wording.time(earlier, now: earlier.addingTimeInterval(60))
        #expect(today == earlier.formatted(date: .omitted, time: .shortened))
        let old = now.addingTimeInterval(-9 * 86_400)
        #expect(Wording.time(old, now: now) == old.formatted(.dateTime.month(.abbreviated).day()))
        #expect(Wording.saved(old, now: now) == "Saved \(Wording.time(old, now: now))")
    }

    @Test func waitingAnswersInWords() {
        #expect(Wording.waitingToSend(3) == "3 waiting to send")
        let first = now.addingTimeInterval(-240)
        #expect(Wording.answered(from: first, to: first, now: now) == "answered \(Wording.time(first, now: now))")
        #expect(Wording.answered(from: first, to: now, now: now) == "answered \(Wording.time(first, now: now)) to \(Wording.time(now, now: now))")
    }

    @Test func savedCoursesInWords() {
        func course(_ code: String, saved: Int, of total: Int, at date: Date) -> SavedCourse {
            SavedCourse(id: code, code: code, title: "T", questionCount: total, savedQuestionCount: saved, isComplete: saved == total, savedAt: date)
        }
        let old = now.addingTimeInterval(-9 * 86_400)
        let updated = "updated \(Wording.time(now, now: now))"
        #expect(Wording.savedCourse(course("A", saved: 86, of: 86, at: now), now: now) == "86 questions · \(updated)")
        #expect(Wording.savedCourse(course("A", saved: 70, of: 86, at: now), now: now) == "70 of 86 questions · \(updated)")
        #expect(Wording.savedCourses([course("A", saved: 1, of: 1, at: old), course("B", saved: 1, of: 1, at: now)], now: now) == "2 courses · \(updated)")
        #expect(Wording.savedCourses([], now: now) == "Nothing saved yet")
    }
}
