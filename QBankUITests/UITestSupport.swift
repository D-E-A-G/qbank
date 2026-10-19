import XCTest

extension XCTestCase {
    /// Launches the real app in a scenario of the Debug launch seam (`QB_UITEST_SCENARIO`).
    /// `keepPhoneSettings` keeps the settings an earlier launch saved on the phone, and
    /// `keepPhoneData` the courses it saved and the answers it left waiting. `online: false`
    /// starts without a network. `deviceOwner` is how the device answers the Face ID lock, such as
    /// `face-id` (`QB_UITEST_DEVICE_OWNER`), and `passkeys` what passkeys it has, such as `synced`
    /// (`QB_UITEST_PASSKEYS`); every launch gets fakes of both, so the simulator's own Face ID and
    /// passkey sheet never play a part.
    @MainActor
    func launch(
        _ scenario: String,
        keepPhoneSettings: Bool = false,
        keepPhoneData: Bool = false,
        online: Bool = true,
        deviceOwner: String = "face-id",
        passkeys: String = "none"
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["QB_UITEST_SCENARIO"] = scenario
        app.launchEnvironment["QB_UITEST_DEVICE_OWNER"] = deviceOwner
        app.launchEnvironment["QB_UITEST_PASSKEYS"] = passkeys
        if keepPhoneSettings {
            app.launchEnvironment["QB_UITEST_KEEP_PHONE_SETTINGS"] = "1"
        }
        if keepPhoneData {
            app.launchEnvironment["QB_UITEST_KEEP_PHONE_DATA"] = "1"
        }
        if !online {
            app.launchEnvironment["QB_UITEST_NETWORK"] = "offline"
        }
        app.launch()
        return app
    }

    /// Skips a test that walks the iPhone layout, where a course opens over Home; on iPad it opens
    /// beside the list, and `IPadUITests` walks that.
    @MainActor
    func skipOnIPad() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "walks the iPhone layout; IPadUITests covers the iPad's")
    }

    /// Turns the fake server's network off or on while the app runs, through the Darwin
    /// notifications `DebugLaunchScenario` names.
    func setNetwork(online: Bool) {
        let name = online ? "com.dimitrygallego.qbank.uitest.network.online" : "com.dimitrygallego.qbank.uitest.network.offline"
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(name as CFString), nil, nil, true)
    }

    /// Makes the fake device confirm her at the next Face ID check, or refuse as though she
    /// cancelled, through the Darwin notifications `DebugLaunchScenario` names.
    func setDeviceOwner(confirms: Bool) {
        let name = confirms ? "com.dimitrygallego.qbank.uitest.owner.confirms" : "com.dimitrygallego.qbank.uitest.owner.refuses"
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(name as CFString), nil, nil, true)
    }

    /// Opens another window of the app on iPad, as she can from the Dock, through the Darwin
    /// notification `DebugLaunchScenario` names.
    func openAnotherWindow() {
        let name = "com.dimitrygallego.qbank.uitest.window.new"
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(name as CFString), nil, nil, true)
    }

    /// Keeps a screenshot in the test results, for comparing the screens with the wireframes.
    @MainActor
    func attach(_ app: XCUIApplication, _ name: String) {
        // The screen's, not the app's: an iPad app's own screenshot comes out turned and cut in landscape.
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Keeps a screenshot in light and in dark, as she sees the screen after choosing Light or
    /// Dark in Settings, then goes back to Match device. The Look is set through the Darwin
    /// notifications `DebugLaunchScenario.lookNotification(_:)` names.
    @MainActor
    func attachLooks(_ app: XCUIApplication, _ name: String) {
        for look in ["light", "dark"] {
            setLook(look)
            attach(app, "\(name) \(look)")
        }
        setLook("auto")
    }

    /// Sets the app's Look, `light`, `dark`, or `auto`, and gives the screen a moment to redraw
    /// in its colors and to finish any animation.
    @MainActor
    private func setLook(_ look: String) {
        let name = "com.dimitrygallego.qbank.uitest.look.\(look)"
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(name as CFString), nil, nil, true)
        RunLoop.current.run(until: .now.addingTimeInterval(1))
    }

    /// Waits until the element's label contains the text.
    @MainActor
    func waitForLabel(_ element: XCUIElement, containing text: String, timeout: TimeInterval = 10) {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let result = XCTWaiter.wait(for: [expectation(for: predicate, evaluatedWith: element)], timeout: timeout)
        XCTAssertEqual(result, .completed, "\"\(element.label)\" never contained \"\(text)\"")
    }

    /// Taps a button once it stops moving, as one in a sheet does when the sheet settles at its
    /// height. A tap made while it moves can land beside it.
    @MainActor
    func tapWhenStill(_ element: XCUIElement) {
        waitUntilStill(element)
        element.tap()
    }

    /// Waits until the element has stopped moving and can be touched, for at most three seconds.
    /// A sheet's button can report where it will settle while the sheet still slides in.
    @MainActor
    func waitUntilStill(_ element: XCUIElement) {
        XCTAssertTrue(element.appears(timeout: 5))
        var frame = element.frame
        for _ in 0..<20 {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.15))
            let now = element.frame
            if now == frame, element.isHittable { break }
            frame = now
        }
    }

    /// Scrolls until the element is on screen, clear of the bars at the top and bottom, then taps it.
    @MainActor
    func tapVisible(_ element: XCUIElement, in app: XCUIApplication) {
        reveal(element, in: app)
        element.tap()
    }

    /// Scrolls until the element is on screen, clear of the bars at the top and bottom.
    @MainActor
    func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.appears(timeout: 5))
        let window = app.windows.firstMatch.frame
        for _ in 0..<10 {
            let frame = element.frame
            if element.isHittable, frame.minY > window.minY + 120, frame.maxY < window.maxY - 120 { return }
            if frame.midY > window.midY {
                app.swipeUp(velocity: .slow)
            } else {
                app.swipeDown(velocity: .slow)
            }
        }
    }

    /// A tab's button: in the tab bar at the bottom on iPhone, or at the top on iPad, whose tabs are
    /// plain buttons ahead of everything else on screen.
    @MainActor
    func tabButton(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        UIDevice.current.userInterfaceIdiom == .pad ? app.buttons[name].firstMatch : app.tabBars.buttons[name]
    }

    @MainActor
    func openTab(_ app: XCUIApplication, _ name: String, timeout: TimeInterval = 5) {
        let tab = tabButton(app, name)
        XCTAssertTrue(tab.appears(timeout: timeout))
        tab.tap()
    }

    /// Steps back from the screen titled `title`, and waits until it has gone, so the next tap
    /// lands on the screen underneath and not on one still sliding in.
    @MainActor
    func goBack(_ app: XCUIApplication, from title: String) {
        let bar = app.navigationBars[title]
        bar.buttons.firstMatch.tap()
        XCTAssertTrue(bar.disappears(timeout: 5), "still on \(title)")
    }

    /// Fills the sign-in form and presses Sign in. A nil email keeps what is in the field.
    @MainActor
    func signIn(_ app: XCUIApplication, email: String?, password: String) {
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
    func dismissSavePassword(_ app: XCUIApplication) {
        let notNow = app.buttons["Not Now"]
        guard notNow.appears(timeout: 4) else { return }
        // A tap while the prompt is still animating in does not register: tap until it is gone.
        for _ in 0..<5 {
            if notNow.isHittable { notNow.tap() }
            if notNow.disappears(timeout: 2) { return }
        }
        XCTFail("The Save Password prompt did not go away")
    }

    /// QBank's offer to save a passkey after a password sign-in, once it is on screen.
    @MainActor
    func passkeyOffer(_ app: XCUIApplication) -> XCUIElement {
        let offer = app.descendants(matching: .any)["passkeyOffer"]
        XCTAssertTrue(offer.appears(timeout: 10), "no passkey offer")
        return offer
    }

    /// Answers QBank's passkey offer with Not now, and waits until it has gone.
    @MainActor
    func declinePasskeyOffer(_ app: XCUIApplication) {
        let offer = passkeyOffer(app)
        tapWhenStill(app.buttons["passkeyOffer.cancel"])
        XCTAssertTrue(offer.disappears(timeout: 5), "the passkey offer stayed")
    }

    /// Opens a folder from the course page, through its exam page when it is on one.
    @MainActor
    func openFolder(_ app: XCUIApplication, _ name: String, on page: String? = nil) {
        if let page {
            let row = app.buttons["course.page.\(page)"]
            XCTAssertTrue(row.appears(timeout: 5))
            tapVisible(row, in: app)
            XCTAssertTrue(app.navigationBars[page].appears(timeout: 5))
        }
        let row = app.buttons["folder.\(name)"]
        XCTAssertTrue(row.appears(timeout: 5))
        tapVisible(row, in: app)
        XCTAssertTrue(app.navigationBars[name].appears(timeout: 5))
    }
}

extension XCUIElement {
    /// `waitForExistence(timeout:)`, but true at once for an element already on screen. XCTest's
    /// own wait takes its first look only after a second, even then, and over the suite's hundreds
    /// of waits those seconds added up to a third of the UI tests' time on GitHub's Mac.
    @MainActor
    func appears(timeout: TimeInterval) -> Bool {
        exists || waitForExistence(timeout: timeout)
    }

    /// `waitForNonExistence(timeout:)`, but true at once for an element already gone.
    @MainActor
    func disappears(timeout: TimeInterval) -> Bool {
        !exists || waitForNonExistence(timeout: timeout)
    }
}
