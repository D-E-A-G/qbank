import XCTest

/// Connect an agent end to end: the real app against the fake server of the Debug launch seam,
/// whose agents wait under invented codes. Never a real account, a real key, or the production
/// server. Every line checked here is the web's, word for word, so a drift fails the test.
final class ConnectAgentUITests: XCTestCase {
    private static let notFound = "No agent is waiting under that code. Codes last 10 minutes: ask the agent for its new one."

    @MainActor
    override func setUp() async throws {
        continueAfterFailure = false
        try skipOnIPad()
    }

    /// From Settings: a code nobody waits under, then her agent's code in small letters without its
    /// dash, approved; its key shows once the agent picks it up, and Revoke asks before it stops it.
    @MainActor
    func testApproveAnAgentThenRevokeItsKey() throws {
        let app = openConnectAgent(attaching: "agents-0 settings")
        XCTAssertEqual(app.staticTexts["connectAgent.intro"].label, "Your agent shows you a short code. Enter it here to see what the agent asks to do, then approve or deny it. You never see or copy a key: the agent picks its own up.")
        XCTAssertTrue(app.staticTexts["The code your agent shows you, such as BCDF\u{2011}GHJK. It lasts 10 minutes."].exists)
        let mac = key(app, "My MacBook agent")
        XCTAssertTrue(mac.appears(timeout: 5))
        XCTAssertTrue(mac.label.contains("Can import sets and read progress"), mac.label)
        XCTAssertEqual(app.staticTexts["connectAgent.keysFooter"].label, "Each key works for this account only, and only for what it was approved to do. Revoking one stops it at once; what it imported or changed stays as it is.")
        attachLooks(app, "agents-1 connect an agent")

        enterCode("zzzz-zzzz\n", in: app)
        XCTAssertTrue(app.staticTexts[Self.notFound].appears(timeout: 5))

        enterCode("kxpdmwrt\n", in: app)
        let request = app.descendants(matching: .any)["connectAgent.request"]
        XCTAssertTrue(request.appears(timeout: 5))
        XCTAssertEqual(app.staticTexts["connectAgent.name"].label, "Study laptop agent")
        XCTAssertTrue(app.staticTexts["connectAgent.codeLine"].label.hasPrefix("Code KXPDMWRT · Works until "), app.staticTexts["connectAgent.codeLine"].label)
        XCTAssertTrue(app.staticTexts["It asks to"].exists)
        let scopes = ["import", "read"].map { app.descendants(matching: .any)["connectAgent.scope.\($0)"].label }
        XCTAssertTrue(scopes[0].hasPrefix("Import question sets"), scopes[0])
        XCTAssertTrue(scopes[1].hasPrefix("Read progress, read-only"), scopes[1])
        XCTAssertFalse(scopes.contains { $0.contains("Most access") }, "only manage reaches the most")
        XCTAssertEqual(app.staticTexts["connectAgent.note"].label, "Approve only a code your own agent is showing you now. Its key never changes a password, deletes anything, or reaches your other keys.")
        XCTAssertFalse(app.staticTexts[Self.notFound].exists, "a code that matched drops the line about the last")
        attachLooks(app, "agents-2 an agent asks to connect")

        tapVisible(app.buttons["connectAgent.approve"], in: app)
        let banner = app.descendants(matching: .any)["connectAgent.answered"]
        XCTAssertTrue(banner.appears(timeout: 5))
        XCTAssertEqual(banner.label, "Approved Study laptop agent. It picks up its key within a few seconds, and then it shows under Your keys.")
        XCTAssertEqual(app.textFields["connectAgent.code"].value as? String ?? "", "Code", "the field is empty again")
        let laptop = key(app, "Study laptop agent")
        XCTAssertTrue(laptop.appears(timeout: 10), "listed once the agent picks its key up")
        XCTAssertTrue(laptop.label.contains("Made today · Never used"), laptop.label)
        XCTAssertTrue(laptop.label.contains("Can import sets and read progress"), laptop.label)
        attachLooks(app, "agents-3 approved")

        let revoke = app.buttons["connectAgent.revoke.Study laptop agent"]
        tapVisible(revoke, in: app)
        let sheet = app.descendants(matching: .any)["connectAgent.revokeSheet"]
        XCTAssertTrue(sheet.appears(timeout: 5))
        XCTAssertEqual(app.staticTexts["connectAgent.revokeSheet.title"].label, "Revoke Study laptop agent?")
        XCTAssertEqual(app.staticTexts["connectAgent.revokeSheet.message"].label, "Its key stops working at once and for good. The sets it imported stay where they are. To connect this agent again, approve a new code from it.")
        attachLooks(app, "agents-4 revoke a key")
        tapWhenStill(app.buttons["connectAgent.revokeSheet.cancel"])
        XCTAssertTrue(sheet.disappears(timeout: 5))
        XCTAssertTrue(revoke.exists, "Cancel changes nothing")

        tapVisible(revoke, in: app)
        XCTAssertTrue(sheet.appears(timeout: 5))
        tapWhenStill(app.buttons["connectAgent.revokeSheet.confirm"])
        XCTAssertTrue(sheet.disappears(timeout: 5))
        XCTAssertTrue(app.staticTexts["Revoked Study laptop agent. It stopped working just now."].appears(timeout: 5))
        waitForLabel(laptop, containing: "Revoked: it never works again")
        XCTAssertTrue(laptop.label.contains("Made today · Revoked today"), laptop.label)
        XCTAssertFalse(revoke.exists, "a revoked key has no Revoke")
        XCTAssertTrue(app.buttons["connectAgent.revoke.My MacBook agent"].exists)
        attachLooks(app, "agents-5 revoked")
    }

    /// An agent that asks to manage says it reaches the most, and that what it deletes goes to
    /// Recently deleted; denied, it gets no key.
    @MainActor
    func testAnAgentThatAsksToManageSaysSoAndCanBeDenied() throws {
        let app = openConnectAgent()
        enterCode("HZNB-QLVS", in: app)
        tapVisible(app.buttons["connectAgent.continue"], in: app)
        XCTAssertTrue(app.descendants(matching: .any)["connectAgent.request"].appears(timeout: 5))
        XCTAssertEqual(app.staticTexts["connectAgent.name"].label, "Library desktop agent")
        let manage = app.descendants(matching: .any)["connectAgent.scope.manage"]
        XCTAssertTrue(manage.label.contains("Add, change, and delete your content"), manage.label)
        XCTAssertTrue(manage.label.contains("Most access"), manage.label)
        XCTAssertTrue(manage.label.contains("Recently deleted"), manage.label)
        XCTAssertEqual(app.staticTexts["connectAgent.note"].label, "Approve only a code your own agent is showing you now. Its key never answers questions for you, changes a password, or reaches your other keys, and what it deletes goes to Recently deleted.")
        attachLooks(app, "agents-6 an agent asks to manage")

        tapVisible(app.buttons["connectAgent.deny"], in: app)
        let banner = app.descendants(matching: .any)["connectAgent.answered"]
        XCTAssertTrue(banner.appears(timeout: 5))
        XCTAssertEqual(banner.label, "Denied Library desktop agent. No key was made.")
        XCTAssertFalse(key(app, "Library desktop agent").appears(timeout: 3), "no key was made")

        enterCode("HZNB-QLVS\n", in: app)
        XCTAssertTrue(app.staticTexts[Self.notFound].appears(timeout: 5), "answered already")
    }

    /// The set her agent imported says so under its line, as on the web; her own sets do not.
    @MainActor
    func testASetHerAgentImportedSaysSo() throws {
        let app = launch("signed-in")
        XCTAssertTrue(app.navigationBars["NURS 310"].appears(timeout: 10))
        openFolder(app, "Weeks 1-3")
        let set = app.buttons["course.set.Mixed Clinical Judgment"]
        XCTAssertTrue(set.appears(timeout: 5))
        XCTAssertTrue(set.label.contains("Imported by your agent"), set.label)
        attachLooks(app, "agents-7 imported by your agent")
        goBack(app, from: "Weeks 1-3")
        openFolder(app, "Week 1", on: "Exam 1")
        let own = app.buttons["course.set.Rights, Law, and Ethics"]
        XCTAssertTrue(own.appears(timeout: 5))
        XCTAssertFalse(own.label.contains("Imported by"), own.label)
    }

    /// Signed in, Settings > Connect an agent, from its row under Passkeys. `attaching` names
    /// screenshots of Settings with the row.
    @MainActor
    private func openConnectAgent(attaching name: String? = nil) -> XCUIApplication {
        let app = launch("signed-in")
        XCTAssertTrue(app.navigationBars["NURS 310"].appears(timeout: 10))
        openTab(app, "Settings")
        let row = app.buttons["settings.connectAgent"]
        XCTAssertTrue(row.appears(timeout: 5))
        XCTAssertTrue(row.label.contains("Connect an agent"), row.label)
        XCTAssertTrue(row.label.contains("Approve its code, and see your keys"), row.label)
        if let name {
            attachLooks(app, name)
        }
        open(row, titled: "Connect an agent", in: app)
        return app
    }

    /// Puts the code in the field in place of what is there. A code ending in a return sends it, as
    /// the keyboard's Continue does.
    @MainActor
    private func enterCode(_ code: String, in app: XCUIApplication) {
        let field = app.textFields["connectAgent.code"]
        tapVisible(field, in: app)
        let typed = (field.value as? String).map { $0 == "Code" ? 0 : $0.count } ?? 0
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: typed) + code)
    }

    @MainActor
    private func key(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.descendants(matching: .any)["connectAgent.key.\(name)"]
    }
}
