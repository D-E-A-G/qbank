import XCTest

final class QBankUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testWelcomeScreenAppearsOnLaunch() throws {
        let app = XCUIApplication()
        app.launchEnvironment["QB_UITEST_SCENARIO"] = "welcome"
        app.launch()

        let title = app.staticTexts["welcome.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "QBank")
    }
}
