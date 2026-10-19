import XCTest

/// The Face ID lock end to end, on iPhone and iPad: the real app with the Debug launch seam's fake
/// device, which confirms or refuses her as the test says. Never the simulator's own Face ID.
final class LockUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLockAsksForFaceIDAndCoversTheAppUntilItConfirms() throws {
        let app = launch("signed-in")
        XCTAssertTrue(app.navigationBars["NURS 310"].appears(timeout: 10))
        openTab(app, "Settings")
        let toggle = app.switches["settings.lock"]
        reveal(toggle, in: app)
        XCTAssertEqual(toggle.value as? String, "0", "the lock starts off")
        XCTAssertTrue(app.staticTexts["Lock with Face ID"].exists)
        flip(toggle)
        waitForValue(toggle, "1")
        attach(app, "3 settings, lock on")

        // QBank leaves the screen and comes back: locked, and Face ID refused keeps it so.
        setDeviceOwner(confirms: false)
        XCUIDevice.shared.press(.home)
        app.activate()
        let unlock = app.buttons["lock.unlock"]
        XCTAssertTrue(unlock.appears(timeout: 10))
        XCTAssertEqual(unlock.label, "Unlock with Face ID")
        XCTAssertTrue(app.staticTexts["Locked. Unlock with Face ID to keep studying."].exists)
        XCTAssertFalse(toggle.isHittable, "Settings is covered")
        attach(app, "3 lock screen")

        setDeviceOwner(confirms: true)
        unlock.tap()
        XCTAssertTrue(unlock.disappears(timeout: 5))
        XCTAssertTrue(toggle.isHittable)

        // The lock is kept on the device: the next launch starts locked.
        app.terminate()
        let relaunched = launch("signed-in", keepPhoneSettings: true, deviceOwner: "face-id-refusing")
        let unlockAgain = relaunched.buttons["lock.unlock"]
        XCTAssertTrue(unlockAgain.appears(timeout: 10))
        setDeviceOwner(confirms: true)
        unlockAgain.tap()
        XCTAssertTrue(unlockAgain.disappears(timeout: 5))
        XCTAssertTrue(relaunched.navigationBars["NURS 310"].appears(timeout: 10), "her course is underneath, as she left it")

        // Off again: leaving and coming back asks for nothing.
        openTab(relaunched, "Settings")
        let toggleAgain = relaunched.switches["settings.lock"]
        reveal(toggleAgain, in: relaunched)
        waitForValue(toggleAgain, "1")
        flip(toggleAgain)
        waitForValue(toggleAgain, "0")
        XCUIDevice.shared.press(.home)
        relaunched.activate()
        XCTAssertTrue(toggleAgain.appears(timeout: 5))
        XCTAssertFalse(relaunched.buttons["lock.unlock"].exists)
    }

    @MainActor
    func testLockStaysOverPracticeAndLeavesItAsItWas() throws {
        let app = launch("signed-in")
        XCTAssertTrue(app.navigationBars["NURS 310"].appears(timeout: 10))
        openTab(app, "Settings")
        let toggle = app.switches["settings.lock"]
        reveal(toggle, in: app)
        flip(toggle)
        waitForValue(toggle, "1")
        openTab(app, "Home")

        openFolder(app, "Weeks 1-3")
        let set = app.buttons["course.set.Mixed Clinical Judgment"]
        XCTAssertTrue(set.appears(timeout: 5))
        tapVisible(set, in: app)
        let count = app.staticTexts["practice.count"]
        XCTAssertTrue(count.appears(timeout: 10))
        let question = count.label

        setDeviceOwner(confirms: false)
        XCUIDevice.shared.press(.home)
        app.activate()
        let unlock = app.buttons["lock.unlock"]
        XCTAssertTrue(unlock.appears(timeout: 10))
        attach(app, "3 lock screen over practice")
        setDeviceOwner(confirms: true)
        unlock.tap()
        XCTAssertTrue(unlock.disappears(timeout: 5))
        XCTAssertTrue(count.appears(timeout: 5), "practice is still open")
        XCTAssertEqual(count.label, question)
    }

    /// An iPad can have several QBank windows. One opening, which sends the other to the
    /// background, leaves QBank open; QBank locks once all of it leaves the screen.
    @MainActor
    func testAnotherWindowLeavesQBankOpenUntilAllOfItLeaves() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "only an iPad has more than one window")
        let app = launch("signed-in")
        XCTAssertTrue(app.navigationBars["NURS 310"].appears(timeout: 10))
        openTab(app, "Settings")
        let toggle = app.switches["settings.lock"]
        reveal(toggle, in: app)
        flip(toggle)
        waitForValue(toggle, "1")
        setDeviceOwner(confirms: false)

        // The new window opens on Home, and nothing covers it. The other window, in the
        // background, keeps its cover for the app switcher.
        openAnotherWindow()
        let mentalHealth = app.buttons["home.course.NURS 310"]
        XCTAssertTrue(mentalHealth.appears(timeout: 10), "no new window")
        let onScreen = NSPredicate(format: "isHittable == true")
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: onScreen, evaluatedWith: mentalHealth)], timeout: 5), .completed, "another window locked QBank")
        let unlock = app.buttons["lock.unlock"].firstMatch
        XCTAssertFalse(unlock.exists, "the other window's cover offers to unlock what is not locked")
        mentalHealth.tap()
        let course = app.buttons["course.page.Exam 1"]
        XCTAssertTrue(course.appears(timeout: 5))
        attach(app, "3 another window")

        // All of QBank leaves the screen: every window locks, and Face ID refused keeps them so.
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(unlock.appears(timeout: 10))
        XCTAssertFalse(course.isHittable, "the course is covered")

        // Back again, and Face ID confirms her: her course is there as she left it.
        setDeviceOwner(confirms: true)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: onScreen, evaluatedWith: course)], timeout: 10), .completed, "still locked")
    }

    @MainActor
    func testADeviceWithoutPasscodeCannotLock() throws {
        let app = launch("signed-in", deviceOwner: "no-passcode")
        XCTAssertTrue(app.navigationBars["NURS 310"].appears(timeout: 10))
        openTab(app, "Settings")
        let toggle = app.switches["settings.lock"]
        reveal(toggle, in: app)
        XCTAssertFalse(toggle.isEnabled)
        let device = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        XCTAssertTrue(app.staticTexts["Set a passcode for this \(device) in the Settings app to lock QBank."].exists)
        attach(app, "3 settings, no passcode")
    }

    /// Taps a SwiftUI toggle's switch, not its label, which does nothing on a tap.
    @MainActor
    private func flip(_ toggle: XCUIElement) {
        let control = toggle.switches.firstMatch
        (control.exists ? control : toggle).tap()
    }

    @MainActor
    private func waitForValue(_ element: XCUIElement, _ value: String) {
        let predicate = NSPredicate(format: "value == %@", value)
        let result = XCTWaiter.wait(for: [expectation(for: predicate, evaluatedWith: element)], timeout: 5)
        XCTAssertEqual(result, .completed, "\(element) never had the value \(value)")
    }
}
