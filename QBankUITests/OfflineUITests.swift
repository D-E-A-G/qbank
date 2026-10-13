import XCTest

/// Slice 1e end to end: the app loses its connection, keeps working from what it saved, keeps the
/// answers on the phone through a relaunch, and sends them when the connection is back. The fake
/// server of the Debug launch seam stands in for QBank, and the test turns its network off and on.
/// Invented courses and accounts only.
final class OfflineUITests: XCTestCase {
    private static let set = "Anxiety, Panic, and Anxiolytics"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testPracticeWithoutSignalThenSendWhenBackOnline() throws {
        let app = launch("signed-in")
        XCTAssertTrue(app.navigationBars["NURS 310"].waitForExistence(timeout: 10))

        // Online, the app saves both courses with every set, so any set can be practiced offline.
        app.tabBars.buttons["Settings"].tap()
        let savedRow = app.buttons["settings.savedForOffline"]
        reveal(savedRow, in: app)
        waitForLabel(savedRow, containing: "2 courses · updated ")
        attach(app, "1e settings, on this phone")
        savedRow.tap()
        XCTAssertTrue(app.descendants(matching: .any)["savedForOffline.nothingWaiting"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["savedForOffline.course.NURS 310"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["savedForOffline.course.NURS 220"].exists)
        attach(app, "1e-5 saved for offline, nothing waiting")
        app.tabBars.buttons["Home"].tap()

        // Signal lost: the course shows what is saved on the phone.
        setNetwork(online: false)
        XCTAssertTrue(app.descendants(matching: .any)["course.offline"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["No connection"].exists)
        attach(app, "1e course, no connection")

        // A set never opened before opens from the phone and is answered there.
        let set = app.buttons["course.set.\(Self.set)"]
        tapVisible(set, in: app)
        XCTAssertTrue(app.buttons["practice.close"].waitForExistence(timeout: 5))
        expectCount(app, "1 of 13")
        tapVisible(app.buttons["practice.option.0"], in: app)
        check(app)
        XCTAssertTrue(feedback(app).label.hasPrefix("Correct"), feedback(app).label)
        XCTAssertTrue(app.descendants(matching: .any)["practice.savedOnPhone"].exists)
        XCTAssertEqual(app.buttons["practice.waiting"].label, "1 waiting to send")
        attach(app, "1e-2 answer saved on the phone")
        next(app)

        expectCount(app, "2 of 13")
        tapVisible(app.buttons["practice.option.1"], in: app)
        check(app)
        XCTAssertTrue(feedback(app).label.hasPrefix("Not correct"), feedback(app).label)
        attach(app, "1e-2 answer saved on the phone, not correct")
        next(app)

        expectCount(app, "3 of 13")
        for option in [0, 1, 3] {
            tapVisible(app.buttons["practice.option.\(option)"], in: app)
        }
        check(app)
        XCTAssertTrue(feedback(app).label.contains("1 of 3 points"), feedback(app).label)
        XCTAssertEqual(app.buttons["practice.waiting"].label, "3 waiting to send")

        // The count opens the list of what waits.
        app.buttons["practice.waiting"].tap()
        let waiting = app.descendants(matching: .any)["savedForOffline.waiting.\(Self.set)"]
        XCTAssertTrue(waiting.waitForExistence(timeout: 5))
        XCTAssertTrue(waiting.label.hasPrefix("3 answers, \(Self.set) · answered "), waiting.label)
        attach(app, "1e-5 saved for offline, from the runner")
        app.buttons["savedForOffline.done"].tap()
        XCTAssertTrue(waiting.waitForNonExistence(timeout: 5))

        // Back on the course, the set counts her waiting answers.
        app.buttons["practice.close"].tap()
        let line = app.buttons["course.set.\(Self.set)"]
        XCTAssertTrue(line.waitForExistence(timeout: 5))
        waitForLabel(line, containing: "3 of 13 answered")
        reveal(line, in: app)
        attach(app, "1e course, waiting answers counted")

        // Exams start and end on the server.
        app.swipeDown()
        app.swipeDown()
        tapVisible(app.buttons["course.tile.exam"], in: app)
        XCTAssertTrue(app.descendants(matching: .any)["exam.needsConnection"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Exams need a connection"].exists)
        attach(app, "1e-3 exams need a connection")
        app.navigationBars["Exam"].buttons.firstMatch.tap()

        // Home says what it shows and what waits.
        app.navigationBars["NURS 310"].buttons["Home"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["home.offline"].waitForExistence(timeout: 5))
        let pill = app.buttons["home.waiting"]
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        XCTAssertEqual(pill.label, "3 waiting to send")
        let card = app.buttons["home.course.NURS 310"]
        XCTAssertTrue(card.label.contains("Saved "), card.label)
        XCTAssertTrue(app.buttons["home.course.NURS 220"].label.contains("Saved "))
        attach(app, "1e-1 home, no connection")

        // The app is closed and opened again, still without signal: the answers are still waiting.
        app.terminate()
        let again = launch("signed-in", keepPhoneData: true, online: false)
        let pillAgain = again.buttons["home.waiting"]
        XCTAssertTrue(pillAgain.waitForExistence(timeout: 10))
        XCTAssertEqual(pillAgain.label, "3 waiting to send")
        XCTAssertTrue(again.descendants(matching: .any)["home.offline"].exists)
        attach(again, "1e-1 home after a relaunch without signal")
        pillAgain.tap()
        XCTAssertTrue(again.descendants(matching: .any)["savedForOffline.waiting.\(Self.set)"].waitForExistence(timeout: 5))
        XCTAssertTrue(again.buttons["savedForOffline.sendNow"].exists)
        attach(again, "1e-5 saved for offline, waiting to send")

        // Signal is back: the answers go by themselves.
        setNetwork(online: true)
        XCTAssertTrue(again.descendants(matching: .any)["savedForOffline.nothingWaiting"].waitForExistence(timeout: 10))
        attach(again, "1e-5 saved for offline, sent")
        again.navigationBars.buttons["Home"].tap()
        XCTAssertTrue(pillAgain.waitForNonExistence(timeout: 10))
        XCTAssertTrue(again.descendants(matching: .any)["home.offline"].waitForNonExistence(timeout: 10))
        XCTAssertFalse(again.buttons["home.course.NURS 310"].label.contains("Saved "))
        attach(again, "1e home, back online")

        // QBank has them: the fake server, started afresh at the relaunch, counts the three.
        again.buttons["home.course.NURS 310"].tap()
        let sent = again.buttons["course.set.\(Self.set)"]
        XCTAssertTrue(sent.waitForExistence(timeout: 10))
        waitForLabel(sent, containing: "3 of 13 answered")
        XCTAssertFalse(again.descendants(matching: .any)["course.offline"].exists)
    }

    @MainActor
    func testAnOfflineAnswerSendsWhileTheRunnerIsOpen() throws {
        let app = launch("signed-in")
        XCTAssertTrue(app.navigationBars["NURS 310"].waitForExistence(timeout: 10))
        tapVisible(app.buttons["course.set.Mixed Clinical Judgment"], in: app)
        XCTAssertTrue(app.buttons["practice.close"].waitForExistence(timeout: 5))
        expectCount(app, "1 of 8")

        setNetwork(online: false)
        tapVisible(app.buttons["practice.option.0"], in: app)
        check(app)
        let banner = app.descendants(matching: .any)["practice.savedOnPhone"]
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["practice.waiting"].exists)

        setNetwork(online: true)
        XCTAssertTrue(banner.waitForNonExistence(timeout: 10), "sent: it no longer waits on the phone")
        XCTAssertFalse(app.buttons["practice.waiting"].exists)
        XCTAssertTrue(feedback(app).label.hasPrefix("Correct"))
        attach(app, "1e-2 answer sent once back online")
    }

    // MARK: Helpers

    @MainActor
    private func expectCount(_ app: XCUIApplication, _ count: String) {
        let counter = app.staticTexts["practice.count"]
        XCTAssertTrue(counter.waitForExistence(timeout: 5))
        waitForLabel(counter, containing: "\(count),", timeout: 5)
    }

    @MainActor
    private func check(_ app: XCUIApplication) {
        let button = app.buttons["practice.check"]
        XCTAssertTrue(button.isEnabled)
        button.tap()
        XCTAssertTrue(feedback(app).waitForExistence(timeout: 5))
    }

    @MainActor
    private func feedback(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["practice.feedback"]
    }

    @MainActor
    private func next(_ app: XCUIApplication) {
        app.buttons["practice.next"].tap()
    }
}
