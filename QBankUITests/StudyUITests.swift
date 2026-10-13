import XCTest

/// Slice 1c end to end: Review, Terms, an exam over her wrong questions, and the course page's
/// week and exam folders with Edit exams, against the in-process fake server of the Debug launch
/// seam, which keeps the server's rules and words. Invented questions and accounts only.
final class StudyUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: Review (1c-1)

    @MainActor
    func testReviewFiltersPracticesAndClears() throws {
        let app = launch("signed-in")
        openTile(app, "review", title: "Review")
        XCTAssertTrue(app.staticTexts["NURS 310 · what you missed or guessed"].exists)
        for label in ["All 12", "Missed 6", "Partly 3", "Guessed 4"] {
            XCTAssertTrue(app.buttons[label].exists, label)
        }
        XCTAssertTrue(app.buttons["All 12"].isSelected)
        XCTAssertTrue(app.buttons["Practice these 12 (shuffled)"].exists)
        let first = app.buttons["review.question.communication-v1-q6"]
        XCTAssertTrue(first.label.contains("Missed, guessed"), first.label)
        XCTAssertTrue(app.buttons["review.question.communication-v1-q3"].label.contains("Partly right"))
        XCTAssertTrue(app.buttons["review.question.communication-v1-q8"].label.contains("Guessed"))
        attach(app, "1c-1 review")

        app.buttons["Missed 6"].tap()
        XCTAssertTrue(app.buttons["Practice these 6 (shuffled)"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["review.question.communication-v1-q3"].exists, "partly right is not missed")
        attach(app, "1c-1 review, missed")

        // One question, answered fully right without guessing, leaves the list.
        tapVisible(app.buttons["review.question.rights-v1-q0"], in: app)
        XCTAssertTrue(app.buttons["practice.close"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["practice.count"].label.hasPrefix("1 of 1"))
        tapVisible(app.buttons["practice.option.0"], in: app)
        app.buttons["practice.check"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["practice.feedback"].waitForExistence(timeout: 5))
        app.buttons["practice.next"].tap()
        XCTAssertTrue(app.staticTexts["result.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(hasText(app, "Review finished · Review question"))
        app.buttons["result.done"].tap()
        XCTAssertTrue(app.buttons["Missed 5"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["review.question.rights-v1-q0"].exists)

        // The filtered list in the runner.
        tapVisible(app.buttons["Practice these 5 (shuffled)"], in: app)
        XCTAssertTrue(app.buttons["practice.close"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["practice.count"].label.hasPrefix("1 of 5"), app.staticTexts["practice.count"].label)
        app.buttons["practice.close"].tap()

        // Clear asks first, in the web's words.
        app.buttons["All 11"].tap()
        tapVisible(app.buttons["review.clear"], in: app)
        XCTAssertTrue(app.staticTexts["review.clearSheet.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["review.clearSheet.title"].label, "Clear all 11 questions from this course's Review list?")
        XCTAssertTrue(app.staticTexts["Your answers and scores are kept. Only the list is emptied."].exists)
        attach(app, "1c-1 clear asks first")
        app.buttons["review.clearSheet.confirm"].tap()
        XCTAssertTrue(
            app.staticTexts["Questions you miss or flag as a guess show up here. They leave when you answer them fully right without guessing."]
                .waitForExistence(timeout: 5)
        )
        XCTAssertFalse(app.buttons["review.clear"].exists)
        attach(app, "1c-1 review, cleared")

        app.navigationBars["Review"].buttons.firstMatch.tap()
        let tile = app.buttons["course.tile.review"]
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        let emptied = NSPredicate(format: "label BEGINSWITH %@", "0")
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: emptied, evaluatedWith: tile)], timeout: 5), .completed, tile.label)
    }

    // MARK: Terms (1c-2)

    @MainActor
    func testTermsAreSearchable() throws {
        let app = launch("signed-in")
        openTile(app, "terms", title: "Terms")
        XCTAssertTrue(app.staticTexts["When a term is defined in more than one set, the newest set’s definition is the one shown here."].exists)
        XCTAssertTrue(app.descendants(matching: .any)["terms.term.Advocacy"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["terms.term.Autonomy"].label.contains("Week 1 · Rights, Law, and Ethics"))
        attach(app, "1c-2 terms")

        let search = app.searchFields["Search terms"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("choices")
        XCTAssertTrue(app.descendants(matching: .any)["terms.term.Autonomy"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["terms.term.Advocacy"].exists)
        attach(app, "1c-2 terms, search")

        search.typeText(" zebra")
        XCTAssertTrue(app.staticTexts["No term matches “choices zebra”."].waitForExistence(timeout: 5))
    }

    // MARK: Exams (1c-3 to 1c-6)

    @MainActor
    func testWrongQuestionsExamFromSetupToResult() throws {
        let app = launch("signed-in")
        openTile(app, "exam", title: "Exam")
        XCTAssertTrue(app.staticTexts["NURS 310 · Mental Health"].exists)
        let week1 = app.buttons["exam.week.Week 1"]
        let week2 = app.buttons["exam.week.Week 2"]
        let week3 = app.buttons["exam.week.Week 3"]
        XCTAssertTrue(week1.waitForExistence(timeout: 5))
        XCTAssertTrue(week1.label.contains("17 questions · exam bank"), week1.label)
        XCTAssertTrue(week2.label.contains("26 questions"), week2.label)
        XCTAssertTrue(app.staticTexts["Tick at least one week."].exists)
        XCTAssertFalse(app.buttons["exam.start"].isEnabled)
        attach(app, "1c-3 exam setup")

        flip(app.switches["exam.wrongOnly"])
        XCTAssertTrue(week1.label.contains("4 wrong of 17 · exam bank"), week1.label)
        XCTAssertTrue(week3.label.contains("0 wrong of 31 · exam bank"), week3.label)
        XCTAssertFalse(week3.isEnabled, "a week with nothing wrong cannot be ticked")
        week1.tap()
        week2.tap()
        XCTAssertTrue(week1.isSelected)
        XCTAssertTrue(week1.label.contains("4 in exam"), week1.label)
        XCTAssertTrue(week2.label.contains("7 in exam"), week2.label)
        let count = app.descendants(matching: .any)["exam.summary.count"]
        reveal(app.buttons["exam.start"], in: app)
        XCTAssertEqual(count.label, "11 questions, in 16.5 minutes")
        XCTAssertEqual(
            app.staticTexts["exam.summary.split"].label,
            "4 from Week 1 · 7 from Week 2 · Fewer than 40, so it’s all of them at 1.5 minutes each."
        )
        XCTAssertEqual(app.staticTexts["exam.summary.fallback"].label, "Week 2 has no exam bank yet, so it uses its practice questions.")
        attach(app, "1c-3 exam setup, wrong questions only")

        app.buttons["exam.start"].tap()
        XCTAssertTrue(app.buttons["exam.end"].waitForExistence(timeout: 10))
        expectCount(app, "1 of 11")
        XCTAssertTrue(app.staticTexts["practice.count"].label.contains("Exam · Weeks 1-2"))
        XCTAssertTrue(app.descendants(matching: .any)["exam.timer"].exists)
        XCTAssertFalse(app.buttons["exam.submit"].isEnabled, "nothing picked yet")
        attach(app, "1c-4 exam")

        // 1 single, right. 2 priority, skipped. 3 select all, partly right. 4 highlight, skipped.
        // 5 single from practice, wrong. 6 to 11 skipped.
        tapVisible(app.buttons["practice.option.0"], in: app)
        attach(app, "1c-4 exam, picked")
        submit(app, next: "2 of 11")
        app.buttons["exam.skip"].tap()
        expectCount(app, "3 of 11")
        tapVisible(app.buttons["practice.option.0"], in: app)
        submit(app, next: "4 of 11")
        app.buttons["exam.skip"].tap()
        expectCount(app, "5 of 11")
        tapVisible(app.buttons["practice.option.1"], in: app)
        submit(app, next: "6 of 11")
        for position in 6...11 {
            app.buttons["exam.skip"].tap()
            if position < 11 { expectCount(app, "\(position + 1) of 11") }
        }
        expectCount(app, "2 of 11")
        let notice = app.descendants(matching: .any)["exam.skippedNotice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["8 skipped questions left. This is the first one."].exists)
        XCTAssertTrue(app.descendants(matching: .any)["practice.meta"].label.contains("Skipped earlier"))
        attach(app, "1c-4 exam, back to the skipped ones")

        app.buttons["exam.end"].tap()
        XCTAssertTrue(app.staticTexts["exam.endSheet.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["exam.endSheet.title"].label, "End the exam now?")
        XCTAssertTrue(app.staticTexts["The 3 questions you answered will be scored. Skipped and unreached questions score 0 and stay out of Review."].exists)
        attach(app, "1c-5 end the exam")
        app.buttons["exam.endSheet.cancel"].tap()
        XCTAssertTrue(app.staticTexts["exam.endSheet.title"].waitForNonExistence(timeout: 5))
        expectCount(app, "2 of 11")

        app.buttons["exam.end"].tap()
        XCTAssertTrue(app.buttons["exam.endSheet.confirm"].waitForExistence(timeout: 5))
        app.buttons["exam.endSheet.confirm"].tap()
        let title = app.staticTexts["examResult.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "1 of 11 fully right")
        XCTAssertTrue(app.staticTexts["examResult.points"].label.hasSuffix(" · Ended early"), app.staticTexts["examResult.points"].label)
        XCTAssertTrue(hasText(app, "Exam result · Weeks 1-2 · Wrong questions only"))
        XCTAssertTrue(app.staticTexts["Week 2 had no exam bank, so its questions came from practice sets."].exists)
        for (label, value) in [("Partly right", "1"), ("Missed", "1"), ("Guessed", "0"), ("Not answered", "8")] {
            XCTAssertTrue(app.descendants(matching: .any)["examResult.stat.\(label)"].label.hasPrefix(value), label)
        }
        XCTAssertTrue(app.buttons["Open Review · 1 from this exam"].exists)
        XCTAssertEqual(
            app.staticTexts["examResult.bankWrong"].label,
            "1 exam-bank question you got wrong stays out of Review. Turn on Wrong questions only to take it again."
        )
        attach(app, "1c-6 exam result")
        app.swipeUp()
        XCTAssertTrue(hasText(app, "Week 1, exam bank, 1 of 4"))
        XCTAssertTrue(hasText(app, "Week 2, practice questions, 0 of 7"))
        attach(app, "1c-6 exam result, by week and step")
        tapVisible(app.buttons["examResult.question.1"], in: app)
        XCTAssertEqual(app.buttons["examResult.question.1"].value as? String, "Expanded")
        attach(app, "1c-6 exam result, question opened")

        // Open Review goes to the course's Review list; Back returns to the setup.
        reveal(app.buttons["examResult.openReview"], in: app)
        app.buttons["examResult.openReview"].tap()
        XCTAssertTrue(app.navigationBars["Review"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["review.question.communication-v1-q0"].waitForExistence(timeout: 5), "the practice question she missed")
        app.navigationBars["Review"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Exam"].waitForExistence(timeout: 5))
        reveal(app.staticTexts["Past exams"], in: app)
        attach(app, "1c-3 exam setup, after the exam")
    }

    @MainActor
    func testPastExamOpensItsResultAndTimeRunsOutOnTheServer() throws {
        let app = launch("signed-in")
        openTile(app, "exam", title: "Exam")
        let past = app.buttons["exam.past.e0000000-0000-4000-8000-000000000002"]
        reveal(past, in: app)
        XCTAssertTrue(past.label.contains("Time ran out"), past.label)
        past.tap()
        XCTAssertTrue(app.staticTexts["examResult.title"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["examResult.points"].label.hasSuffix("· Time ran out"), app.staticTexts["examResult.points"].label)
        XCTAssertTrue(app.descendants(matching: .any)["examResult.stat.Not answered"].label.hasPrefix("2"))
        app.buttons["examResult.done"].tap()
        XCTAssertTrue(app.navigationBars["Exam"].waitForExistence(timeout: 5))
    }

    // MARK: Course folders and exams (screens A to D)

    @MainActor
    func testCourseFoldersByWeekAndByExam() throws {
        let app = launch("signed-in")
        XCTAssertTrue(app.navigationBars["NURS 310"].waitForExistence(timeout: 10))
        // A course with exams opens on them, until she chooses.
        XCTAssertTrue(app.buttons["Exams"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Exams"].isSelected)
        let exam1 = app.buttons["course.exam.Exam 1"]
        XCTAssertTrue(exam1.waitForExistence(timeout: 5))
        XCTAssertEqual(exam1.value as? String, "Expanded", "the exam with unfinished work opens by itself")
        XCTAssertTrue(exam1.label.contains("Weeks 1-2 · 3 sets · 43 questions · 2 exams taken"), exam1.label)
        XCTAssertEqual(app.buttons["course.exam.Exam 2"].value as? String, "Collapsed")
        attach(app, "B course by exam")
        reveal(app.buttons["course.startExam.Exam 1"], in: app)
        XCTAssertTrue(app.staticTexts["Your exams"].exists)
        XCTAssertTrue(app.staticTexts["40 questions from the 43 in its exam banks and practice sets, or Wrong questions only."].exists)
        attach(app, "B course by exam, your exams")
        reveal(app.buttons["course.addToExam"], in: app)
        XCTAssertTrue(app.staticTexts["Not in an exam yet"].exists)
        reveal(app.staticTexts["Other exams"], in: app)
        XCTAssertTrue(app.buttons["course.sitting.e0000000-0000-4000-8000-000000000003"].exists, "Weeks 1-3 spans both exams")
        attach(app, "B course by exam, not in an exam and other exams")

        // A past exam under Your exams opens its result.
        let sitting = app.buttons["course.sitting.e0000000-0000-4000-8000-000000000001"]
        tapVisible(sitting, in: app)
        XCTAssertTrue(app.staticTexts["examResult.title"].waitForExistence(timeout: 10))
        app.buttons["examResult.done"].tap()
        XCTAssertTrue(app.navigationBars["NURS 310"].waitForExistence(timeout: 5))

        // By week: only the unfinished week is open; what she opens or closes stays on the phone.
        app.swipeDown()
        app.swipeDown()
        app.buttons["Weeks"].tap()
        let week2 = app.buttons["course.week.Week 2"]
        let week3 = app.buttons["course.week.Week 3"]
        XCTAssertTrue(week2.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["course.week.Week 1"].value as? String, "Collapsed")
        XCTAssertTrue(app.buttons["course.week.Week 1"].label.contains("1 set · 13 of 17 fully right"))
        XCTAssertEqual(week2.value as? String, "Expanded")
        XCTAssertTrue(week2.label.contains("2 sets · 9 of 26 answered"), week2.label)
        XCTAssertEqual(week3.value as? String, "Collapsed")
        XCTAssertTrue(week3.label.contains("Not started"), week3.label)
        attach(app, "A course by week")
        week2.tap()
        tapVisible(week3, in: app)
        XCTAssertEqual(week3.value as? String, "Expanded")
        XCTAssertTrue(app.descendants(matching: .any)["course.bank.Week 3"].label.contains("Exam bank: 31 questions, exams only"))
        attach(app, "A course by week, Week 3 opened")

        app.terminate()
        let again = launch("signed-in", keepPhoneSettings: true)
        XCTAssertTrue(again.buttons["course.week.Week 3"].waitForExistence(timeout: 10))
        XCTAssertTrue(again.buttons["Weeks"].isSelected, "the view she chose stays")
        XCTAssertEqual(again.buttons["course.week.Week 3"].value as? String, "Expanded")
        XCTAssertEqual(again.buttons["course.week.Week 2"].value as? String, "Collapsed")
    }

    @MainActor
    func testEditExamsThenStartOneFromItsFolder() throws {
        let app = launch("signed-in")
        XCTAssertTrue(app.buttons["course.editExams"].waitForExistence(timeout: 10))
        app.buttons["course.editExams"].tap()
        XCTAssertTrue(app.navigationBars["Exams"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Name each exam and tap the weeks it covers. A week can be in one exam."].exists)
        let held = app.buttons["editExams.chip.1.Week 1"]
        XCTAssertEqual(held.label, "Week 1, in Exam 1")
        XCTAssertFalse(held.isEnabled, "a week another exam holds is greyed")
        XCTAssertTrue(app.buttons["editExams.chip.0.Week 1"].isSelected)
        attach(app, "C edit exams")

        app.buttons["editExams.add"].tap()
        let added = app.textFields["editExams.name.2"]
        XCTAssertTrue(added.waitForExistence(timeout: 5))
        XCTAssertEqual(added.value as? String, "Exam 3")
        tapVisible(app.buttons["editExams.chip.2.Weeks 1-3"], in: app)
        XCTAssertTrue(app.staticTexts["Weeks 1-3 · 8 questions"].exists)
        attach(app, "C edit exams, Exam 3 added")

        // The server refuses a name the course already uses, in its words.
        let second = app.textFields["editExams.name.1"]
        reveal(second, in: app)
        second.tap()
        second.clearAndType("exam 1")
        app.buttons["editExams.done"].tap()
        XCTAssertTrue(app.staticTexts["This course already has an exam named exam 1."].waitForExistence(timeout: 5))
        attach(app, "C edit exams, refused")
        reveal(second, in: app)
        second.tap()
        second.clearAndType("Final")
        app.buttons["editExams.done"].tap()
        XCTAssertTrue(app.navigationBars["Exams"].waitForNonExistence(timeout: 5))

        let final = app.buttons["course.exam.Final"]
        XCTAssertTrue(final.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["course.exam.Exam 3"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["course.addToExam"].exists, "every week is in an exam now")
        attach(app, "B course by exam, after Edit exams")

        // Start exam over an exam's weeks opens the setup with them ticked.
        tapVisible(app.buttons["course.startExam.Exam 1"], in: app)
        XCTAssertTrue(app.navigationBars["Exam"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["exam.preselected"].label, "Exam 1 · Weeks 1-2 ticked for you")
        XCTAssertTrue(app.buttons["exam.week.Week 1"].isSelected)
        XCTAssertTrue(app.buttons["exam.week.Week 2"].isSelected)
        XCTAssertFalse(app.buttons["exam.week.Week 3"].isSelected)
        attach(app, "D exam setup from Exam 1")
        reveal(app.buttons["exam.start"], in: app)
        XCTAssertEqual(app.descendants(matching: .any)["exam.summary.count"].label, "40 questions, in 60 minutes")
        attach(app, "D exam setup from Exam 1, summary")
    }

    // MARK: Helpers

    /// Opens one of the course's three tiles from the course she landed on.
    @MainActor
    private func openTile(_ app: XCUIApplication, _ tile: String, title: String) {
        XCTAssertTrue(app.navigationBars["NURS 310"].waitForExistence(timeout: 10))
        let button = app.buttons["course.tile.\(tile)"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
    }

    /// Whether a text shows, as one element or as part of a combined one, in any letter case.
    @MainActor
    private func hasText(_ app: XCUIApplication, _ text: String) -> Bool {
        app.descendants(matching: .any).matching(NSPredicate(format: "label ==[c] %@", text)).firstMatch.waitForExistence(timeout: 5)
    }

    @MainActor
    private func expectCount(_ app: XCUIApplication, _ count: String) {
        let counter = app.staticTexts["practice.count"]
        XCTAssertTrue(counter.waitForExistence(timeout: 5))
        let changed = NSPredicate(format: "label BEGINSWITH %@", "\(count),")
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: changed, evaluatedWith: counter)], timeout: 5), .completed, "count is \(counter.label)")
    }

    @MainActor
    private func submit(_ app: XCUIApplication, next: String) {
        let button = app.buttons["exam.submit"]
        XCTAssertTrue(button.isEnabled)
        button.tap()
        expectCount(app, next)
    }

    /// Flips a switch by its knob, which a tap on the middle of the row does not reach.
    @MainActor
    private func flip(_ toggle: XCUIElement) {
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let before = toggle.value as? String
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        let flipped = NSPredicate(format: "value != %@", before ?? "")
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: flipped, evaluatedWith: toggle)], timeout: 5), .completed)
    }
}

private extension XCUIElement {
    func clearAndType(_ text: String) {
        let current = value as? String ?? ""
        typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        typeText(text)
    }
}
