import XCTest

/// Passkeys end to end: the real app against the fake server of the Debug launch seam, with a
/// device whose passkeys the test sets up (`QB_UITEST_PASSKEYS`). Invented accounts only, never a
/// real one, never the production server; the system's passkey sheet never shows.
final class PasskeyUITests: XCTestCase {
    private static let email = "student@example.com"
    private static let password = "synthetic-pass-1"

    @MainActor
    override func setUp() async throws {
        continueAfterFailure = false
        try skipOnIPad()
    }

    @MainActor
    func testSignInWithThePasskeyFromHerMac() throws {
        let app = launch("signed-out", passkeys: "synced")
        let button = app.buttons["signIn.passkey"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        XCTAssertEqual(button.label, "Sign in with a passkey")
        attachLooks(app, "3-p1 sign in with a passkey")

        button.tap()
        XCTAssertTrue(app.navigationBars["NURS 310"].waitForExistence(timeout: 10), "lands on the course she used last")
        XCTAssertFalse(app.descendants(matching: .any)["passkeyOffer"].exists, "a passkey sign-in offers no passkey")
    }

    @MainActor
    func testClosingThePasskeySheetStaysOnSignInAndSaysNothing() throws {
        let app = launch("signed-out", passkeys: "cancels")
        let button = app.buttons["signIn.passkey"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        XCTAssertTrue(button.isEnabled)
        XCTAssertFalse(app.descendants(matching: .any)["problem"].exists)
        XCTAssertTrue(app.staticTexts["signIn.title"].exists)
    }

    /// After a password sign-in QBank offers a passkey once; the one she saves then signs her in.
    @MainActor
    func testPasswordSignInOffersAPasskeyThatThenSignsHerIn() throws {
        let app = launch("signed-out")
        XCTAssertTrue(app.staticTexts["signIn.title"].waitForExistence(timeout: 10))
        signIn(app, email: Self.email, password: Self.password)
        dismissSavePassword(app)
        let offer = passkeyOffer(app)
        XCTAssertTrue(app.staticTexts["Save a passkey for this iPhone?"].exists)
        XCTAssertTrue(app.staticTexts["Next time, sign in with Face ID instead of your password. You can remove it in Settings."].exists)
        attachLooks(app, "3-p2 passkey offer")

        tapWhenStill(app.buttons["passkeyOffer.confirm"])
        XCTAssertTrue(offer.waitForNonExistence(timeout: 5), "the offer closes once the passkey is saved")
        XCTAssertTrue(app.navigationBars["NURS 310"].waitForExistence(timeout: 10))

        openTab(app, "Settings")
        let row = app.buttons["settings.passkeys"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        waitForLabel(row, containing: "2")
        row.tap()
        XCTAssertTrue(app.navigationBars["Passkeys"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["MacBook Air"].exists)
        XCTAssertTrue(app.staticTexts["iPhone"].exists)
        goBack(app, from: "Passkeys")

        reveal(app.buttons["settings.signOut"], in: app)
        app.buttons["settings.signOut"].tap()
        let passkey = app.buttons["signIn.passkey"]
        XCTAssertTrue(passkey.waitForExistence(timeout: 10))
        passkey.tap()
        XCTAssertTrue(app.navigationBars["NURS 310"].waitForExistence(timeout: 10), "the passkey she saved signs her in")
    }

    @MainActor
    func testNotNowIsKeptOnThePhone() throws {
        let app = launch("signed-out")
        XCTAssertTrue(app.staticTexts["signIn.title"].waitForExistence(timeout: 10))
        signIn(app, email: Self.email, password: Self.password)
        dismissSavePassword(app)
        declinePasskeyOffer(app)
        XCTAssertTrue(app.navigationBars["NURS 310"].waitForExistence(timeout: 10))

        app.terminate()
        let again = launch("signed-out", keepPhoneSettings: true)
        XCTAssertTrue(again.staticTexts["signIn.title"].waitForExistence(timeout: 10))
        signIn(again, email: Self.email, password: Self.password)
        dismissSavePassword(again)
        XCTAssertTrue(again.navigationBars["NURS 310"].waitForExistence(timeout: 10))
        XCTAssertFalse(again.descendants(matching: .any)["passkeyOffer"].waitForExistence(timeout: 2), "asked once on this phone")
    }

    @MainActor
    func testSettingsListsSavesAndRemovesPasskeys() throws {
        let app = launch("signed-in")
        XCTAssertTrue(app.navigationBars["NURS 310"].waitForExistence(timeout: 10))
        openTab(app, "Settings")
        let row = app.buttons["settings.passkeys"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        waitForLabel(row, containing: "1")
        row.tap()
        XCTAssertTrue(app.navigationBars["Passkeys"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["MacBook Air"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Added \(Self.shortDate(daysAgo: 45))"].exists)
        XCTAssertTrue(app.staticTexts["Passkeys let you sign in with Face ID instead of your password."].exists)
        attachLooks(app, "3-p3 passkeys")

        app.buttons["passkeys.save"].tap()
        XCTAssertTrue(app.staticTexts["Passkey saved on this iPhone."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["iPhone"].exists)
        XCTAssertTrue(app.staticTexts["Added today"].exists)
        attachLooks(app, "3-p3 passkeys, saved")

        app.buttons["passkeys.remove.MacBook Air"].tap()
        let sheet = app.descendants(matching: .any)["passkeys.removeSheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Remove the passkey “MacBook Air”?"].exists)
        XCTAssertTrue(app.staticTexts["You won't be able to sign in with it anymore. Your password still works."].exists)
        attachLooks(app, "3-p4 remove a passkey")
        tapWhenStill(app.buttons["passkeys.removeSheet.confirm"])
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["MacBook Air"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["iPhone"].exists)

        goBack(app, from: "Passkeys")
        waitForLabel(row, containing: "1")
    }

    /// The device already has her passkey, synced from her Mac: iOS says so in its own sheet, and
    /// QBank says it in Settings.
    @MainActor
    func testADeviceThatHasHerPasskeySaysSo() throws {
        let app = launch("signed-in", passkeys: "synced")
        XCTAssertTrue(app.navigationBars["NURS 310"].waitForExistence(timeout: 10))
        openTab(app, "Settings")
        app.buttons["settings.passkeys"].tap()
        let save = app.buttons["passkeys.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        XCTAssertTrue(app.staticTexts["This iPhone already has a passkey for your account."].waitForExistence(timeout: 5))
    }

    /// The date `daysAgo` days back as the app writes it, such as "Sep 1".
    private static func shortDate(daysAgo: Int) -> String {
        Date.now.addingTimeInterval(-Double(daysAgo) * 86_400).formatted(.dateTime.month(.abbreviated).day())
    }
}
