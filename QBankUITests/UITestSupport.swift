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

    @MainActor
    func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        let window = app.windows.firstMatch.frame
        for _ in 0..<8 {
            let frame = element.frame
            if element.isHittable, frame.minY > window.minY + 120, frame.maxY < window.maxY - 120 { return }
            if frame.midY > window.midY {
                app.swipeUp(velocity: .slow)
            } else {
                app.swipeDown(velocity: .slow)
            }
        }
    }
}
