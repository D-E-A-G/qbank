import XCTest

/// The iPad layout end to end: her courses stay in a sidebar beside the course she chose, and every
/// screen keeps a reading column however wide the iPad is, in both orientations, light and dark.
/// Skipped on iPhone, whose layout the other suites cover.
final class IPadUITests: XCTestCase {
    /// The reading column's widest, `QBankLayout.contentMax`.
    private static let contentMax: CGFloat = 720

    @MainActor
    override func setUp() async throws {
        continueAfterFailure = false
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "the iPad layout runs on iPad")
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    override func tearDown() async throws {
        XCUIDevice.shared.orientation = .portrait
        try await super.tearDown()
    }

    @MainActor
    func testCoursesStayBesideTheCourseSheChose() throws {
        let app = launch("signed-in")
        XCTAssertTrue(app.navigationBars["NURS 310"].waitForExistence(timeout: 10), "lands on the course she used last")
        let mentalHealth = app.buttons["home.course.NURS 310"]
        let fundamentals = app.buttons["home.course.NURS 220"]
        XCTAssertTrue(mentalHealth.waitForExistence(timeout: 5))
        XCTAssertTrue(mentalHealth.isSelected, "the open course is marked in the list")
        let summary = app.descendants(matching: .any)["course.summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertLessThan(mentalHealth.frame.maxX, summary.frame.minX, "the course opens beside the list")
        expectReadingColumn(summary)

        // Deeper in the course, the list stays; another course opens on its own page.
        openFolder(app, "Week 2", on: "Exam 1")
        XCTAssertTrue(mentalHealth.isHittable)
        fundamentals.tap()
        XCTAssertTrue(app.navigationBars["NURS 220"].waitForExistence(timeout: 5))
        XCTAssertTrue(fundamentals.isSelected)
        XCTAssertFalse(mentalHealth.isSelected)

        mentalHealth.tap()
        XCTAssertTrue(app.navigationBars["NURS 310"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["course.page.Exam 1"].waitForExistence(timeout: 5), "back on the course's own page")

        // Landscape keeps both columns, and the course's screens open beside the list.
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(mentalHealth.waitForExistence(timeout: 5))
        XCTAssertTrue(mentalHealth.isHittable)
        expectReadingColumn(summary)
        app.buttons["course.tile.review"].tap()
        XCTAssertTrue(app.navigationBars["Review"].waitForExistence(timeout: 5))
        XCTAssertTrue(mentalHealth.isHittable)
    }

    @MainActor
    func testPracticeKeepsTheListCurrent() throws {
        let app = launch("signed-in")
        XCTAssertTrue(app.navigationBars["NURS 310"].waitForExistence(timeout: 10))
        let mentalHealth = app.buttons["home.course.NURS 310"]
        XCTAssertTrue(mentalHealth.waitForExistence(timeout: 5))
        let answered = try XCTUnwrap(mentalHealth.value as? String)

        openFolder(app, "Weeks 1-3")
        tapVisible(app.buttons["course.set.Mixed Clinical Judgment"], in: app)
        XCTAssertTrue(app.buttons["practice.close"].waitForExistence(timeout: 10))
        expectReadingColumn(app.staticTexts["practice.stem"])
        tapVisible(app.buttons["practice.option.0"], in: app)
        app.buttons["practice.check"].tap()
        XCTAssertTrue(app.buttons["practice.next"].waitForExistence(timeout: 5))
        app.buttons["practice.close"].tap()

        // The answer counts in the course's card in the list, which stayed on screen.
        let changed = NSPredicate(format: "value != %@", answered)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: changed, evaluatedWith: mentalHealth)], timeout: 10), .completed, "still \(answered)")
    }

    @MainActor
    func testSignInIsAColumnInTheMiddle() throws {
        let app = launch("signed-out")
        let title = app.staticTexts["signIn.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            let field = app.textFields["signIn.email"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            XCTAssertLessThanOrEqual(field.frame.width, 480)
            XCTAssertEqual(field.frame.midX, app.windows.firstMatch.frame.midX, accuracy: 1)
            attach(app, "ipad sign in, \(orientation == .portrait ? "portrait" : "landscape")")
        }
    }

    /// Every screen, in both orientations and both looks, for a look by eye in the test results.
    @MainActor
    func testScreensInBothOrientationsLightAndDark() throws {
        let app = launch("signed-in")
        XCTAssertTrue(app.navigationBars["NURS 310"].waitForExistence(timeout: 10))
        let mentalHealth = app.buttons["home.course.NURS 310"]
        for look in ["Light", "Dark"] {
            openTab(app, "Settings")
            let choice = app.buttons[look]
            reveal(choice, in: app)
            choice.tap()
            XCTAssertTrue(choice.isSelected)
            for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
                XCUIDevice.shared.orientation = orientation
                let tag = "\(look.lowercased()), \(orientation == .portrait ? "portrait" : "landscape")"
                openTab(app, "Settings")
                app.swipeDown()
                attach(app, "ipad settings, \(tag)")
                tapVisible(app.buttons["settings.changePassword"], in: app)
                XCTAssertTrue(app.secureTextFields["changePassword.current"].waitForExistence(timeout: 5))
                attach(app, "ipad change password, \(tag)")
                goBack(app, from: "Change password")
                tapVisible(app.buttons["settings.semester.1"], in: app)
                XCTAssertTrue(app.textFields["semester.name"].waitForExistence(timeout: 5))
                attach(app, "ipad semester, \(tag)")
                goBack(app, from: "Semester 1")
                XCTAssertTrue(app.buttons["settings.changePassword"].waitForExistence(timeout: 5))

                openTab(app, "Add")
                XCTAssertTrue(app.buttons["add.import"].waitForExistence(timeout: 5))
                attach(app, "ipad add, \(tag)")
                app.buttons["add.import"].tap()
                XCTAssertTrue(app.buttons["import.check"].waitForExistence(timeout: 5))
                expectReadingColumn(app.buttons["import.check"])
                attach(app, "ipad import, \(tag)")
                goBack(app, from: "Import")
                XCTAssertTrue(app.buttons["add.import"].waitForExistence(timeout: 5))

                openTab(app, "Home")
                mentalHealth.tap()
                XCTAssertTrue(app.buttons["course.page.Exam 1"].waitForExistence(timeout: 5))
                attach(app, "ipad course, \(tag)")

                app.buttons["course.newPage"].tap()
                let cancel = app.buttons["editPage.cancel"]
                XCTAssertTrue(cancel.waitForExistence(timeout: 5))
                attach(app, "ipad new exam page sheet, \(tag)")
                tapWhenStill(cancel)
                XCTAssertTrue(cancel.waitForNonExistence(timeout: 5))

                for tile in ["review", "terms", "exam"] {
                    app.buttons["course.tile.\(tile)"].tap()
                    XCTAssertTrue(app.buttons["course.tile.\(tile)"].waitForNonExistence(timeout: 5))
                    attach(app, "ipad \(tile), \(tag)")
                    if tile == "review" {
                        tapVisible(app.buttons["review.clear"], in: app)
                        XCTAssertTrue(app.staticTexts["review.clearSheet.title"].waitForExistence(timeout: 5))
                        attach(app, "ipad confirm sheet, \(tag)")
                        tapWhenStill(app.buttons["review.clearSheet.cancel"])
                        XCTAssertTrue(app.staticTexts["review.clearSheet.title"].waitForNonExistence(timeout: 5))
                    }
                    mentalHealth.tap()
                    XCTAssertTrue(app.buttons["course.page.Exam 1"].waitForExistence(timeout: 5))
                }

                openFolder(app, "Week 2", on: "Exam 1")
                attach(app, "ipad folder, \(tag)")
                mentalHealth.tap()
                XCTAssertTrue(app.buttons["course.page.Exam 1"].waitForExistence(timeout: 5))

                openFolder(app, "Weeks 1-3")
                tapVisible(app.buttons["course.set.Mixed Clinical Judgment"], in: app)
                XCTAssertTrue(app.buttons["practice.close"].waitForExistence(timeout: 10))
                attach(app, "ipad practice, \(tag)")
                tapVisible(app.buttons["practice.option.0"], in: app)
                app.buttons["practice.check"].tap()
                XCTAssertTrue(app.buttons["practice.next"].waitForExistence(timeout: 5))
                attach(app, "ipad practice feedback, \(tag)")
                app.buttons["practice.close"].tap()
                XCTAssertTrue(app.buttons["practice.close"].waitForNonExistence(timeout: 5))
            }
            XCUIDevice.shared.orientation = .portrait
        }
    }

    /// The element sits in a column no wider than the reading width.
    @MainActor
    private func expectReadingColumn(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertLessThanOrEqual(element.frame.width, Self.contentMax, "\(element) is \(element.frame.width) wide", file: file, line: line)
    }
}
