import XCTest

/// Deleting a folder with its sets, a set, and a past exam, each after a warning in the server's
/// words; Undo from the bar; Recently deleted; and a delete refused for now. End to end against the
/// in-process fake server of the Debug launch seam, with invented questions and accounts only.
final class DeletionUITests: XCTestCase {
    @MainActor
    override func setUp() async throws {
        continueAfterFailure = false
        try skipOnIPad()
    }

    /// Deleting a folder warns that its sets go too, naming each one, and Undo brings it all back.
    @MainActor
    func testDeletingAFolderNamesItsSetsAndUndoBringsItBack() throws {
        let app = launch("signed-in")
        XCTAssertTrue(app.navigationBars["NURS 310"].waitForExistence(timeout: 10))
        openFolder(app, "Week 2", on: "Exam 1")
        attach(app, "folder with Delete")

        app.buttons["folder.delete"].tap()
        let title = app.staticTexts["deleteSheet.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "Delete Week 2?")
        let message = app.staticTexts["deleteSheet.message"]
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertEqual(
            message.label,
            "Its 2 sets go with it: Psychosocial Assessment and Safety Screening and Therapeutic Communication and the Relationship, 26 questions in all. You have answered 9 of them: those answers stop counting toward your progress, and 5 questions leave your Review list. It comes off Exam 1. Your 2 past exams over it stay. You can undo this for 30 days."
        )
        XCTAssertTrue(app.buttons["deleteSheet.confirm"].isEnabled)
        attachLooks(app, "folder delete warning")

        tapWhenStill(app.buttons["deleteSheet.confirm"])
        XCTAssertTrue(app.navigationBars["Exam 1"].waitForExistence(timeout: 5), "the deleted folder's screen leaves")
        let line = app.staticTexts["undo.line"]
        XCTAssertTrue(line.waitForExistence(timeout: 5))
        XCTAssertEqual(line.label, "Week 2 and its 2 sets deleted.")
        XCTAssertTrue(app.buttons["folder.Week 2"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["folder.Week 1"].exists)
        attachLooks(app, "folder deleted, Undo")

        app.buttons["undo.button"].tap()
        waitForLabel(line, containing: "Week 2 and its 2 sets are back.")
        XCTAssertTrue(app.buttons["folder.Week 2"].waitForExistence(timeout: 5), "back on Exam 1")
        attach(app, "folder back")
        XCTAssertTrue(app.otherElements["undo.bar"].waitForNonExistence(timeout: 6), "the bar goes by itself")
    }

    /// A set is deleted from its row, and Recently deleted brings it back.
    @MainActor
    func testDeletingASetFromItsRowAndBringingItBackFromRecentlyDeleted() throws {
        let app = launch("signed-in")
        XCTAssertTrue(app.navigationBars["NURS 310"].waitForExistence(timeout: 10))
        openFolder(app, "Weeks 1-3")
        XCTAssertTrue(app.staticTexts["Touch and hold a set to delete it."].exists)
        let row = app.buttons["course.set.Mixed Clinical Judgment"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.press(forDuration: 1.2)
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        attach(app, "set touch and hold")
        delete.tap()

        let title = app.staticTexts["deleteSheet.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "Delete Mixed Clinical Judgment?")
        XCTAssertTrue(app.staticTexts["deleteSheet.message"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["deleteSheet.message"].label, "Its 8 questions go with it. You can undo this for 30 days.")
        attach(app, "set delete warning")
        tapWhenStill(app.buttons["deleteSheet.confirm"])
        XCTAssertTrue(row.waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["undo.line"].label, "Mixed Clinical Judgment deleted.")
        XCTAssertTrue(app.staticTexts["No sets yet. Move sets here from another folder."].waitForExistence(timeout: 5))

        goBack(app, from: "Weeks 1-3")
        tapVisible(app.buttons["course.recentlyDeleted"], in: app)
        XCTAssertTrue(app.navigationBars["Recently deleted"].waitForExistence(timeout: 5))
        let bringBack = app.buttons["deleted.bringBack.Mixed Clinical Judgment"]
        XCTAssertTrue(bringBack.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Weeks 1-3 · 8 questions"].exists)
        attachLooks(app, "recently deleted")

        bringBack.tap()
        XCTAssertTrue(app.staticTexts["Mixed Clinical Judgment is back."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Nothing deleted in the last 30 days."].waitForExistence(timeout: 5))
        attach(app, "recently deleted, brought back")
        goBack(app, from: "Recently deleted")
        openFolder(app, "Weeks 1-3")
        XCTAssertTrue(row.waitForExistence(timeout: 5), "back in its folder")
    }

    /// A past exam is deleted from its row on Exam setup, and Undo lists it again.
    @MainActor
    func testDeletingAPastExamFromExamSetup() throws {
        let app = launch("signed-in")
        XCTAssertTrue(app.navigationBars["NURS 310"].waitForExistence(timeout: 10))
        let tile = app.buttons["course.tile.exam"]
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        tile.tap()
        XCTAssertTrue(app.navigationBars["Exam"].waitForExistence(timeout: 5))
        let past = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "exam.past."))
        XCTAssertTrue(past.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(past.count, 3)
        let first = past.firstMatch
        let id = first.identifier
        reveal(first, in: app)
        XCTAssertTrue(app.staticTexts["Touch and hold an exam to delete it."].exists)
        first.press(forDuration: 1.2)
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()

        XCTAssertTrue(app.staticTexts["deleteSheet.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["deleteSheet.title"].label, "Delete this exam?")
        let message = app.staticTexts["deleteSheet.message"]
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertTrue(message.label.hasSuffix("You can undo this for 30 days."), message.label)
        attachLooks(app, "past exam delete warning")
        tapWhenStill(app.buttons["deleteSheet.confirm"])
        XCTAssertTrue(app.buttons[id].waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["undo.line"].label, "Exam deleted.")
        XCTAssertEqual(past.count, 2)
        attach(app, "past exam deleted, Undo")

        app.buttons["undo.button"].tap()
        XCTAssertTrue(app.buttons[id].waitForExistence(timeout: 5))
        waitForLabel(app.staticTexts["undo.line"], containing: "The exam is back.")
        XCTAssertEqual(past.count, 3)
    }

    /// An exam in progress asks the folder's questions: the warning says so in the server's words,
    /// and Delete waits.
    @MainActor
    func testADeleteRefusedForNowSaysWhyAndWaits() throws {
        let app = launch("exam-in-progress")
        XCTAssertTrue(app.navigationBars["NURS 310"].waitForExistence(timeout: 10))
        let page = app.buttons["course.page.Exam 1"]
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        tapVisible(page, in: app)
        XCTAssertTrue(app.navigationBars["Exam 1"].waitForExistence(timeout: 5))

        let row = app.buttons["folder.Week 2"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        tapVisible(row, in: app)
        XCTAssertTrue(app.navigationBars["Week 2"].waitForExistence(timeout: 5))
        app.buttons["folder.delete"].tap()
        let problem = app.staticTexts["An exam in progress asks questions from Week 2. Finish or leave that exam first."]
        XCTAssertTrue(problem.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["deleteSheet.confirm"].isEnabled, "Delete waits")
        attachLooks(app, "delete refused for now")
        tapWhenStill(app.buttons["deleteSheet.cancel"])
        XCTAssertTrue(app.navigationBars["Week 2"].waitForExistence(timeout: 5), "nothing was deleted")
        XCTAssertFalse(app.otherElements["undo.bar"].exists)
    }
}
