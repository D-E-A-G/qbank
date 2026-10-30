import XCTest

/// Striking out the choices she has ruled out, and restoring them, in a practice set and in an
/// exam, against the in-process fake server of the Debug launch seam. Strikes are her own aid
/// while she answers: they never reach the answer she sends. Invented questions and accounts only.
final class StrikeOutUITests: XCTestCase {
    @MainActor
    override func setUp() async throws {
        continueAfterFailure = false
        try skipOnIPad()
    }

    @MainActor
    func testStrikeAndRestoreInPractice() throws {
        let app = launch("signed-in")
        XCTAssertTrue(app.navigationBars["NURS 310"].appears(timeout: 10))
        openFolder(app, "Weeks 1-3")
        let set = app.buttons["course.set.Mixed Clinical Judgment"]
        XCTAssertTrue(set.appears(timeout: 5))
        tapVisible(set, in: app)
        expectCount(app, "1 of 8")
        attach(app, "strike, practice open")

        // Striking her pick unpicks it, and a struck choice cannot be picked.
        let option = app.buttons["practice.option.1"]
        let strike = app.buttons["practice.strike.1"]
        tapVisible(option, in: app)
        XCTAssertTrue(option.isSelected)
        XCTAssertTrue(strike.label.hasPrefix("Strike out "), strike.label)
        strike.tap()
        expectStruck(option, strike)
        XCTAssertFalse(option.isSelected, "striking her pick unpicks it")
        XCTAssertFalse(app.buttons["practice.check"].isEnabled)
        option.tap()
        XCTAssertFalse(option.isSelected, "a struck choice cannot be picked")
        attachLooks(app, "strike, practice, one struck")

        // The same control restores it, and it can be picked again.
        strike.tap()
        expectRestored(option, strike)
        option.tap()
        XCTAssertTrue(option.isSelected)
        attach(app, "strike, practice, restored and picked")

        // A long press offers the same.
        let other = app.buttons["practice.option.2"]
        other.press(forDuration: 1)
        let menuStrike = app.buttons["Strike out"]
        XCTAssertTrue(menuStrike.appears(timeout: 5))
        attach(app, "strike, practice, long press")
        menuStrike.tap()
        expectStruck(other, app.buttons["practice.strike.2"])

        // Checking shows every verdict as it would without strikes, and the controls go away.
        let check = app.buttons["practice.check"]
        XCTAssertTrue(check.isEnabled)
        check.tap()
        XCTAssertTrue(app.descendants(matching: .any)["practice.feedback"].appears(timeout: 5))
        XCTAssertFalse(app.buttons["practice.strike.2"].exists)
        XCTAssertNotEqual(other.value as? String, "Struck out")
        attach(app, "strike, practice, checked")

        // The next question starts with nothing struck.
        app.buttons["practice.next"].tap()
        expectCount(app, "2 of 8")
        XCTAssertTrue(app.buttons["practice.strike.1"].appears(timeout: 5))
        XCTAssertNotEqual(app.buttons["practice.option.1"].value as? String, "Struck out")
    }

    @MainActor
    func testStrikesStayWithAnExamQuestionUntilRestored() throws {
        let app = launch("signed-in")
        XCTAssertTrue(app.navigationBars["NURS 310"].appears(timeout: 10))
        let tile = app.buttons["course.tile.exam"]
        XCTAssertTrue(tile.appears(timeout: 5))
        tile.tap()
        XCTAssertTrue(app.navigationBars["Exam"].appears(timeout: 5))
        let wrongOnly = app.switches["exam.wrongOnly"]
        XCTAssertTrue(wrongOnly.appears(timeout: 5))
        wrongOnly.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        let week1 = app.buttons["exam.folder.Week 1"]
        waitForLabel(week1, containing: "4 wrong of 17")
        week1.tap()
        reveal(app.buttons["exam.start"], in: app)
        app.buttons["exam.start"].tap()
        XCTAssertTrue(app.buttons["exam.end"].appears(timeout: 10))
        expectCount(app, "1 of 4")

        let option = app.buttons["practice.option.1"]
        let strike = app.buttons["practice.strike.1"]
        tapVisible(option, in: app)
        strike.tap()
        expectStruck(option, strike)
        XCTAssertFalse(option.isSelected, "striking her pick unpicks it")
        XCTAssertFalse(app.buttons["exam.submit"].isEnabled)
        attachLooks(app, "strike, exam, one struck")

        // Skip to the end and wrap back: the strike is still there.
        for next in ["2 of 4", "3 of 4", "4 of 4", "1 of 4"] {
            app.buttons["exam.skip"].tap()
            expectCount(app, next)
            // Every other question starts with nothing struck; one with no choice list has no option rows.
            let other = app.buttons["practice.option.1"]
            if next != "1 of 4", other.exists {
                XCTAssertNotEqual(other.value as? String, "Struck out", next)
            }
        }
        expectStruck(option, strike)
        attach(app, "strike, exam, back to the skipped question")

        // Restore it, pick it, and submit: the answer goes in as picked.
        strike.tap()
        expectRestored(option, strike)
        option.tap()
        XCTAssertTrue(option.isSelected)
        let submit = app.buttons["exam.submit"]
        XCTAssertTrue(submit.isEnabled)
        submit.tap()
        expectCount(app, "2 of 4")
    }

    // MARK: Helpers

    @MainActor
    private func expectCount(_ app: XCUIApplication, _ count: String) {
        let counter = app.staticTexts["practice.count"]
        XCTAssertTrue(counter.appears(timeout: 5))
        let changed = NSPredicate(format: "label BEGINSWITH %@", "\(count),")
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: changed, evaluatedWith: counter)], timeout: 5), .completed, "count is \(counter.label)")
    }

    @MainActor
    private func expectStruck(_ option: XCUIElement, _ strike: XCUIElement) {
        waitForLabel(option, valueContaining: "Struck out")
        XCTAssertTrue(strike.label.hasPrefix("Restore "), strike.label)
    }

    @MainActor
    private func expectRestored(_ option: XCUIElement, _ strike: XCUIElement) {
        waitForLabel(strike, containing: "Strike out ")
        XCTAssertNotEqual(option.value as? String, "Struck out")
    }
}
