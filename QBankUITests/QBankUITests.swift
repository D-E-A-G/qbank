import XCTest

/// Slices 1a and 1d end to end: the real app against the in-process fake server of the Debug launch seam.
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
        XCTAssertTrue(app.buttons["course.page.Exam 1"].waitForExistence(timeout: 5))
        let summary = app.descendants(matching: .any)["course.summary"]
        XCTAssertTrue(summary.label.hasPrefix("Mental Health · 86 questions · 4 folders"), summary.label)
        attach(app, "1a-4 course")

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
        openFolder(app, "Week 2", on: "Exam 1")
        let restore = app.buttons["course.restore"]
        reveal(restore, in: app)
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
    func testTilesOpenExamReviewAndTerms() throws {
        let app = launch("signed-in")
        XCTAssertTrue(app.navigationBars["NURS 310"].waitForExistence(timeout: 10))
        for (tile, title) in [("exam", "Exam"), ("review", "Review"), ("terms", "Terms")] {
            app.buttons["course.tile.\(tile)"].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), title)
            app.navigationBars[title].buttons.firstMatch.tap()
            XCTAssertTrue(app.navigationBars["NURS 310"].waitForExistence(timeout: 5))
        }
    }

    // MARK: Settings (slice 1d)

    @MainActor
    func testLookIsKeptOnThePhone() throws {
        let app = launch("signed-in")
        openSettings(app)
        let matchDevice = app.buttons["Match device"]
        XCTAssertTrue(matchDevice.waitForExistence(timeout: 5))
        XCTAssertTrue(matchDevice.isSelected, "Match device is the first choice")
        app.buttons["Dark"].tap()
        XCTAssertTrue(app.buttons["Dark"].isSelected)
        XCTAssertFalse(matchDevice.isSelected)

        app.terminate()
        let again = launch("signed-in", keepPhoneSettings: true)
        openSettings(again)
        XCTAssertTrue(again.buttons["Dark"].waitForExistence(timeout: 5))
        XCTAssertTrue(again.buttons["Dark"].isSelected, "Dark survives a relaunch")
        again.buttons["Match device"].tap()
        XCTAssertTrue(again.buttons["Match device"].isSelected)
    }

    @MainActor
    func testChangePasswordExplainsEachRefusal() throws {
        let app = launch("signed-in")
        openSettings(app)
        app.buttons["settings.changePassword"].tap()
        let current = app.secureTextFields["changePassword.current"]
        let new = app.secureTextFields["changePassword.new"]
        XCTAssertTrue(current.waitForExistence(timeout: 5))

        app.buttons["changePassword.save"].tap()
        XCTAssertTrue(app.staticTexts["Enter your current password and a new one."].waitForExistence(timeout: 5))

        type(current, "not-it")
        type(new, "short")
        app.buttons["changePassword.save"].tap()
        XCTAssertTrue(app.staticTexts["Choose a password of at least 8 characters."].waitForExistence(timeout: 5))

        type(new, "-and-longer")
        app.buttons["changePassword.save"].tap()
        XCTAssertTrue(app.staticTexts["That password is not right."].waitForExistence(timeout: 5))
        let left = current.value as? String ?? ""
        XCTAssertTrue(left.isEmpty || left == current.placeholderValue, "the wrong current password is cleared, not \(left)")

        type(current, Self.password)
        app.buttons["changePassword.save"].tap()
        dismissSavePassword(app)
        XCTAssertTrue(app.staticTexts["Password saved."].waitForExistence(timeout: 5))
        attach(app, "1d-2 change password, saved")
        XCTAssertTrue(app.navigationBars["Change password"].exists, "still signed in, on the same screen")

        app.navigationBars["Change password"].buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts[Self.email].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSemestersAndCoursesAreEditedLikeOnTheWeb() throws {
        let app = launch("signed-in")
        openSettings(app)
        let semesterOne = app.buttons["settings.semester.1"]
        XCTAssertTrue(semesterOne.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["NURS 310, NURS 220"].exists)

        // Add Semester 3, then the row is gone: there are only three.
        let add = app.buttons["settings.addSemester"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        XCTAssertTrue(add.label.contains("Add Semester 3"), add.label)
        add.tap()
        XCTAssertTrue(app.buttons["settings.semester.3"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["settings.addSemester"].exists)

        // Rename Semester 1 and give it a start date.
        semesterOne.tap()
        let name = app.textFields["semester.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.clearAndType("Fall 2026")
        app.buttons["semester.starts.add"].tap()
        XCTAssertTrue(app.buttons["semester.starts.clear"].waitForExistence(timeout: 5))
        app.buttons["semester.save"].tap()
        XCTAssertTrue(app.staticTexts["Saved."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Fall 2026"].waitForExistence(timeout: 5))

        // A course code the semester already has is refused with the server's words.
        type(app.textFields["semester.newCode"], "nurs 220")
        type(app.textFields["semester.newTitle"], "Again")
        app.buttons["semester.addCourse"].tap()
        XCTAssertTrue(app.staticTexts["This semester already has a course with the code nurs 220."].waitForExistence(timeout: 5))
        app.textFields["semester.newCode"].clearAndType("NURS 406")
        app.buttons["semester.addCourse"].tap()
        XCTAssertTrue(app.buttons["semester.course.NURS 406"].waitForExistence(timeout: 5))

        // Archive Fundamentals: it leaves Home.
        app.buttons["semester.course.NURS 220"].tap()
        let archive = app.buttons["course.archive"]
        XCTAssertTrue(archive.waitForExistence(timeout: 5))
        archive.tap()
        XCTAssertTrue(app.staticTexts["Archived. It no longer shows on Home."].waitForExistence(timeout: 5))
        XCTAssertTrue(archive.label.contains("Unarchive NURS 220"), archive.label)

        app.tabBars.buttons["Home"].tap()
        if app.navigationBars["NURS 310"].exists {
            app.navigationBars["NURS 310"].buttons["Home"].tap()
        }
        XCTAssertTrue(app.buttons["home.course.NURS 406"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["home.course.NURS 220"].exists)
        XCTAssertTrue(app.staticTexts["FALL 2026"].exists || app.staticTexts["Fall 2026"].exists)
    }

    /// Every Settings screen in Light and in Dark, kept as screenshots to compare with the
    /// approved wireframes.
    @MainActor
    func testSettingsScreensInLightAndDark() throws {
        let app = launch("signed-in")
        openSettings(app)
        for look in ["Light", "Dark"] {
            let tag = look.lowercased()
            app.buttons[look].tap()
            XCTAssertTrue(app.buttons[look].isSelected)
            app.swipeDown()
            attach(app, "1d-1 settings, \(tag)")
            scroll(app, until: app.staticTexts["settings.version"])
            attach(app, "1d-1 settings scrolled, \(tag)")

            app.swipeDown()
            app.buttons["settings.changePassword"].tap()
            XCTAssertTrue(app.secureTextFields["changePassword.current"].waitForExistence(timeout: 5))
            attach(app, "1d-2 change password, \(tag)")
            app.buttons["changePassword.save"].tap()
            XCTAssertTrue(app.staticTexts["Enter your current password and a new one."].waitForExistence(timeout: 5))
            attach(app, "1d-2 change password, problem, \(tag)")
            app.navigationBars["Change password"].buttons["Settings"].tap()

            app.buttons["settings.semester.1"].tap()
            XCTAssertTrue(app.textFields["semester.name"].waitForExistence(timeout: 5))
            app.buttons["semester.starts.add"].tap()
            XCTAssertTrue(app.buttons["semester.starts.clear"].waitForExistence(timeout: 5))
            attach(app, "1d-3 semester, \(tag)")
            scroll(app, until: app.buttons["semester.addCourse"])
            attach(app, "1d-3 semester scrolled, \(tag)")
            app.swipeDown()

            app.buttons["semester.course.NURS 310"].tap()
            XCTAssertTrue(app.textFields["course.code"].waitForExistence(timeout: 5))
            attach(app, "1d-4 course, \(tag)")
            app.navigationBars["NURS 310"].buttons["Semester 1"].tap()
            app.navigationBars["Semester 1"].buttons["Settings"].tap()
            XCTAssertTrue(app.buttons[look].waitForExistence(timeout: 5))
        }
    }

    // MARK: Helpers

    /// The signed-in scenario opens her last course; Settings is one tab away.
    @MainActor
    private func openSettings(_ app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars["NURS 310"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    /// Swipes up until `element` is on screen and clear of the tab bar. A swipe made while the
    /// previous screen is still settling can be lost, so it tries again.
    @MainActor
    private func scroll(_ app: XCUIApplication, until element: XCUIElement) {
        for _ in 0..<4 {
            app.swipeUp()
            if element.isHittable, element.frame.maxY < app.tabBars.firstMatch.frame.minY { return }
        }
        XCTFail("\(element) did not scroll into view")
    }

    @MainActor
    private func type(_ field: XCUIElement, _ text: String) {
        field.tap()
        field.typeText(text)
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

    /// The date `daysAgo` days back as the app writes it, such as "Oct 6".
    private static func shortDate(daysAgo: Int) -> String {
        Date.now.addingTimeInterval(-Double(daysAgo) * 86_400).formatted(.dateTime.month(.abbreviated).day())
    }
}

private extension XCUIElement {
    /// Replaces the field's text: deletes what is there, then types `text`.
    func clearAndType(_ text: String) {
        tap()
        let current = value as? String ?? ""
        let placeholder = placeholderValue ?? ""
        if !current.isEmpty, current != placeholder {
            typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        typeText(text)
    }
}
