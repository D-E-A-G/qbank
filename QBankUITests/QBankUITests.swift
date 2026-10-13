import XCTest

/// Slice 1a end to end: the real app against the in-process fake server of the Debug launch seam.
/// Invented accounts only, never a real one, never the production server.
final class QBankUITests: XCTestCase {
    private static let email = "student@example.com"
    private static let password = "synthetic-pass-1"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSignInLandsOnHerLastCourseAndSignsOut() throws {
        let app = launch("signed-out")
        XCTAssertTrue(app.staticTexts["signIn.title"].waitForExistence(timeout: 10))
        attach(app, "1a-1 sign in")

        signIn(app, email: Self.email, password: "not-the-password")
        let problem = app.staticTexts["That email or password is not right."]
        XCTAssertTrue(problem.waitForExistence(timeout: 5))
        dismissKeyboard(app)
        attach(app, "1a-1 sign in, wrong password")

        signIn(app, email: nil, password: Self.password)
        dismissSavePassword(app)
        XCTAssertTrue(app.navigationBars["NURS 310"].waitForExistence(timeout: 10), "lands on the course she used last")
        XCTAssertTrue(app.staticTexts["Exam bank · 17 questions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No exam bank yet · exams use practice questions"].exists)
        let summary = app.descendants(matching: .any)["course.summary"]
        XCTAssertTrue(summary.label.hasPrefix("Mental Health · 86 questions · 3 weeks"), summary.label)
        attach(app, "1a-4 course")
        app.swipeUp()
        attach(app, "1a-4 course, scrolled")
        app.swipeDown()

        let back = app.navigationBars["NURS 310"].buttons["Home"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["home.course.NURS 310"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["home.course.NURS 220"].exists)
        XCTAssertTrue(app.staticTexts["A course appears here when its first question file is imported."].exists)
        attach(app, "1a-3 home")

        app.buttons["home.course.NURS 220"].tap()
        XCTAssertTrue(app.navigationBars["NURS 220"].waitForExistence(timeout: 5))
        app.navigationBars["NURS 220"].buttons["Home"].tap()

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts[Self.email].waitForExistence(timeout: 5))
        attach(app, "1d settings (sign out)")

        app.buttons["settings.signOut"].tap()
        XCTAssertTrue(app.staticTexts["signIn.title"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testTemporaryPasswordAsksForANewOneFirst() throws {
        let app = launch("signed-out")
        XCTAssertTrue(app.staticTexts["signIn.title"].waitForExistence(timeout: 10))
        signIn(app, email: "reset@example.com", password: "synthetic-temp-1")

        XCTAssertTrue(app.staticTexts["choosePassword.title"].waitForExistence(timeout: 10))
        dismissSavePassword(app)
        let newPassword = app.secureTextFields["choosePassword.new"]
        XCTAssertTrue(newPassword.waitForExistence(timeout: 5))
        dismissKeyboard(app)
        attach(app, "1a-2 choose a new password")

        newPassword.tap()
        newPassword.typeText("short")
        app.buttons["choosePassword.save"].tap()
        XCTAssertTrue(app.staticTexts["Choose a password of at least 8 characters."].waitForExistence(timeout: 5))

        newPassword.tap()
        newPassword.typeText("-and-longer")
        app.buttons["choosePassword.save"].tap()
        dismissSavePassword(app)
        XCTAssertTrue(app.navigationBars["NURS 310"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testRestoreAsksFirstThenBringsBackThePreviousVersion() throws {
        let app = launch("signed-in")
        XCTAssertTrue(app.navigationBars["NURS 310"].waitForExistence(timeout: 10))
        let restore = app.buttons["course.restore"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Replaced \(Self.shortDate(daysAgo: 6)) · 12 questions"].exists)
        restore.tap()

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        XCTAssertTrue(sheet.staticTexts["Restore the previous “Psychosocial Assessment and Safety Screening”?"].exists)
        attach(app, "1a-4 restore asks first")
        sheet.buttons["Restore"].tap()

        XCTAssertTrue(app.staticTexts["Restored today · 12 questions"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["That set is not the current version."].exists)
    }

    @MainActor
    func testSetsAndTilesSayWhatIsComing() throws {
        let app = launch("signed-in")
        XCTAssertTrue(app.navigationBars["NURS 310"].waitForExistence(timeout: 10))
        app.buttons["course.set.Rights, Law, and Ethics"].tap()
        XCTAssertTrue(app.staticTexts["comingSoon.message"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["NURS 310"].tap()
        app.buttons["course.tile.review"].tap()
        XCTAssertTrue(app.navigationBars["Review"].waitForExistence(timeout: 5))
    }

    // MARK: Helpers

    @MainActor
    private func launch(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["QB_UITEST_SCENARIO"] = scenario
        app.launch()
        return app
    }

    /// Fills the sign-in form and presses Sign in. A nil email keeps what is in the field.
    @MainActor
    private func signIn(_ app: XCUIApplication, email: String?, password: String) {
        if let email {
            let field = app.textFields["signIn.email"]
            field.tap()
            field.typeText(email)
        }
        let field = app.secureTextFields["signIn.password"]
        field.tap()
        field.typeText(password)
        app.buttons["signIn.submit"].tap()
    }

    /// iOS offers to save the password after a sign-in; the tests decline, as she may.
    @MainActor
    private func dismissSavePassword(_ app: XCUIApplication) {
        let notNow = app.buttons["Not Now"]
        guard notNow.waitForExistence(timeout: 4) else { return }
        // A tap while the prompt is still animating in does not register: tap until it is gone.
        for _ in 0..<5 {
            if notNow.isHittable { notNow.tap() }
            if notNow.waitForNonExistence(timeout: 2) { return }
        }
        XCTFail("The Save Password prompt did not go away")
    }

    @MainActor
    private func dismissKeyboard(_ app: XCUIApplication) {
        guard app.keyboards.firstMatch.exists else { return }
        app.swipeDown()
        _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 3)
    }

    /// Keeps a screenshot in the test results, for comparing the screens with the wireframes.
    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The date `daysAgo` days back as the app writes it, such as "Oct 6".
    private static func shortDate(daysAgo: Int) -> String {
        Date.now.addingTimeInterval(-Double(daysAgo) * 86_400).formatted(.dateTime.month(.abbreviated).day())
    }
}
