import XCTest

extension XCTestCase {
    /// Launches the real app in a scenario of the Debug launch seam (`QB_UITEST_SCENARIO`).
    /// `keepPhoneSettings` keeps the settings an earlier launch saved on the phone, and
    /// `keepPhoneData` the courses it saved and the answers it left waiting. `online: false`
    /// starts without a network.
    @MainActor
    func launch(_ scenario: String, keepPhoneSettings: Bool = false, keepPhoneData: Bool = false, online: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["QB_UITEST_SCENARIO"] = scenario
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

    /// Turns the fake server's network off or on while the app runs, through the Darwin
    /// notifications `DebugLaunchScenario` names.
    func setNetwork(online: Bool) {
        let name = online ? "com.dimitrygallego.qbank.uitest.network.online" : "com.dimitrygallego.qbank.uitest.network.offline"
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(name as CFString), nil, nil, true)
    }

    /// Keeps a screenshot in the test results, for comparing the screens with the wireframes.
    @MainActor
    func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
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

    /// Scrolls until the element is on screen, clear of the bars at the top and bottom, then taps it.
    @MainActor
    func tapVisible(_ element: XCUIElement, in app: XCUIApplication) {
        reveal(element, in: app)
        element.tap()
    }

    /// Scrolls until the element is on screen, clear of the bars at the top and bottom.
    @MainActor
    func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
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

    /// Opens a folder from the course page, through its exam page when it is on one.
    @MainActor
    func openFolder(_ app: XCUIApplication, _ name: String, on page: String? = nil) {
        if let page {
            let row = app.buttons["course.page.\(page)"]
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            tapVisible(row, in: app)
            XCTAssertTrue(app.navigationBars[page].waitForExistence(timeout: 5))
        }
        let row = app.buttons["folder.\(name)"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        tapVisible(row, in: app)
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 5))
    }
}
