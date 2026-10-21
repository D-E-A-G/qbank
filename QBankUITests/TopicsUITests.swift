import XCTest

/// Study topics end to end against the in-process fake server of the Debug launch seam: made on
/// Home, filled by Import, given a study page with its primer, examined, and kept in Settings.
/// Invented topics and question files only.
final class TopicsUITests: XCTestCase {
    private let topic = "Invented Systems Design"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testATopicFromHomeToAnExamOverItsStudyPage() throws {
        try skipOnIPad()
        let app = launch("signed-in")

        // Her course reads as it always did.
        XCTAssertTrue(app.navigationBars["NURS 310"].appears(timeout: 10))
        XCTAssertTrue(app.staticTexts["Exam pages"].appears(timeout: 5))
        XCTAssertFalse(app.staticTexts["Study pages"].exists)
        goBack(app, from: "NURS 310")

        // Home: Study topics, empty, with New.
        reveal(app.staticTexts["A topic is a place for questions that are not a course: a certification, a language, your own notes."], in: app)
        attachLooks(app, "T-1 home, no topics")
        app.buttons["home.newTopic"].tap()
        let name = app.textFields["newTopic.name"]
        XCTAssertTrue(name.appears(timeout: 5))
        XCTAssertTrue(app.staticTexts["A topic has folders and study pages, like a course, without a semester."].exists)
        name.typeText(topic)
        attachLooks(app, "T-2 new topic")
        tapWhenStill(app.buttons["newTopic.save"])

        // Done opens it, called by its name, worded as a topic.
        XCTAssertTrue(app.navigationBars[topic].appears(timeout: 10))
        XCTAssertEqual(app.descendants(matching: .any)["course.summary"].label, "0 questions · 0 folders")
        XCTAssertTrue(app.staticTexts["This topic has no question sets yet."].exists)
        attachLooks(app, "T-3 topic, new")

        // Import files a set into it, from the Study topics group.
        openTab(app, "Add")
        XCTAssertTrue(app.navigationBars["Add questions"].appears(timeout: 5))
        app.buttons["add.import"].tap()
        XCTAssertTrue(app.navigationBars["Import"].appears(timeout: 5))
        waitForLabel(app.buttons["import.course"], containing: topic)
        paste(AddUITests.file, in: app)
        tapVisible(app.buttons["import.check"], in: app)
        XCTAssertTrue(app.buttons["import.commit"].appears(timeout: 5))
        tapVisible(app.buttons["import.commit"], in: app)
        XCTAssertTrue(app.staticTexts["import.done.title"].appears(timeout: 5))
        XCTAssertEqual(
            app.staticTexts["import.done.copy"].label,
            "“Invented Sleep and Rest” · 3 questions in \(topic), Unsorted. It is in the topic’s Folders list until you move it."
        )
        app.buttons["import.done.open"].tap()
        XCTAssertTrue(app.navigationBars["Unsorted"].appears(timeout: 5))
        goBack(app, from: "Unsorted")

        // New makes Page 1 with the topic's folder and its primer link.
        XCTAssertTrue(app.navigationBars[topic].appears(timeout: 5))
        XCTAssertTrue(app.staticTexts["Study pages"].appears(timeout: 5))
        XCTAssertTrue(app.staticTexts["No study pages yet. Tap New to make Page 1."].exists)
        XCTAssertTrue(app.staticTexts["Folders on no study page. Open one to see its sets."].exists)
        attachLooks(app, "T-4 topic, a folder")
        app.buttons["course.newPage"].tap()
        XCTAssertTrue(app.navigationBars["New study page"].appears(timeout: 5))
        XCTAssertEqual(app.textFields["editPage.name"].value as? String, "Page 1")
        app.buttons["editPage.chip.free.Unsorted"].tap()
        XCTAssertEqual(app.staticTexts["editPage.line"].label, "1 folder · 3 questions")
        let link = app.textFields["editPage.link"]
        tapVisible(link, in: app)
        link.typeText("notes.example.com/stage-1")
        app.buttons["editPage.save"].tap()
        XCTAssertTrue(app.staticTexts["A link has to be a web address, such as https://example.com/primer."].appears(timeout: 5))
        link.clearText()
        link.typeText("https://notes.example.com/stage-1")
        attachLooks(app, "T-5 new study page")
        app.buttons["editPage.save"].tap()

        // The study page opens with its primer above Start exam.
        XCTAssertTrue(app.navigationBars["Page 1"].appears(timeout: 10))
        let primer = app.buttons["page.primer"]
        XCTAssertTrue(primer.appears(timeout: 5))
        XCTAssertTrue(primer.label.contains("Open the primer"), primer.label)
        XCTAssertTrue(primer.label.contains("notes.example.com"), primer.label)
        XCTAssertTrue(app.staticTexts["Exams you finish over Page 1 show up here with their scores."].exists)
        attachLooks(app, "T-6 study page")

        // An exam over it runs as in a course, and goes back to the topic.
        app.buttons["page.startExam"].tap()
        XCTAssertTrue(app.navigationBars["Exam"].appears(timeout: 5))
        XCTAssertTrue(app.staticTexts[topic].exists, "the topic's name alone, with no code")
        XCTAssertTrue(app.staticTexts["Page 1"].exists, "the folders by study page")
        reveal(app.buttons["exam.start"], in: app)
        XCTAssertEqual(app.descendants(matching: .any)["exam.summary.count"].label, "3 questions, in 4.5 minutes")
        attachLooks(app, "T-7 exam setup")
        app.buttons["exam.start"].tap()
        XCTAssertTrue(app.buttons["exam.end"].appears(timeout: 10))
        app.buttons["exam.end"].tap()
        XCTAssertTrue(app.buttons["exam.endSheet.confirm"].appears(timeout: 5))
        app.buttons["exam.endSheet.confirm"].tap()
        XCTAssertTrue(app.staticTexts["examResult.title"].appears(timeout: 10))
        let back = app.buttons["examResult.back"]
        XCTAssertEqual(back.label, "Back to topic")
        back.tap()
        // Back to the screen the exam started from, as in a course: the study page, which now
        // lists the exam, then the topic, which lists the page.
        XCTAssertTrue(app.navigationBars["Page 1"].appears(timeout: 10))
        let sitting = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "page.sitting.")).firstMatch
        XCTAssertTrue(sitting.appears(timeout: 5))
        attachLooks(app, "T-8 study page, a past exam")
        goBack(app, from: "Page 1")
        XCTAssertTrue(app.navigationBars[topic].appears(timeout: 5))
        XCTAssertTrue(app.buttons["course.page.Page 1"].appears(timeout: 5))
    }

    @MainActor
    func testSettingsRenamesReordersAndArchivesTopics() throws {
        try skipOnIPad()
        let app = launch("signed-in")
        XCTAssertTrue(app.navigationBars["NURS 310"].appears(timeout: 10))
        openTab(app, "Settings")
        XCTAssertTrue(app.navigationBars["Settings"].appears(timeout: 5))

        // Two topics, added here.
        let field = app.textFields["settings.newTopicName"]
        reveal(field, in: app)
        XCTAssertTrue(app.staticTexts["No topics yet. Add one below."].exists)
        for name in ["Invented Spanish Verbs", topic] {
            tapVisible(field, in: app)
            field.typeText(name)
            tapVisible(app.buttons["settings.addTopic"], in: app)
            XCTAssertTrue(app.buttons["settings.topic.\(name)"].appears(timeout: 5), name)
        }
        let spanish = app.buttons["settings.topic.Invented Spanish Verbs"]
        reveal(app.buttons["settings.topics.edit"], in: app)
        XCTAssertLessThan(spanish.frame.minY, app.buttons["settings.topic.\(topic)"].frame.minY)
        attachLooks(app, "T-9 settings, topics")

        // Her order: Edit, up, Done.
        app.buttons["settings.topics.edit"].tap()
        let up = app.buttons["topicOrder.up.\(topic)"]
        XCTAssertTrue(up.appears(timeout: 5))
        XCTAssertFalse(app.buttons["topicOrder.up.Invented Spanish Verbs"].isEnabled)
        up.tap()
        attachLooks(app, "T-10 settings, topic order")
        app.buttons["settings.topics.edit"].tap()
        XCTAssertTrue(spanish.appears(timeout: 5))
        XCTAssertLessThan(app.buttons["settings.topic.\(topic)"].frame.minY, spanish.frame.minY)

        // Rename one, then archive it.
        open(app.buttons["settings.topic.\(topic)"], titled: topic, in: app)
        app.textFields["topic.title"].clearText()
        app.textFields["topic.title"].typeText("Invented Distributed Systems")
        app.buttons["topic.save"].tap()
        XCTAssertTrue(app.staticTexts["Saved."].appears(timeout: 5))
        XCTAssertTrue(app.navigationBars["Invented Distributed Systems"].appears(timeout: 5))
        let archive = app.buttons["topic.archive"]
        archive.tap()
        XCTAssertTrue(app.staticTexts["Archived. It moves to Archived on Home."].appears(timeout: 5))
        XCTAssertTrue(archive.label.contains("Unarchive Invented Distributed Systems"), archive.label)
        attachLooks(app, "T-11 topic, archived")
        goBack(app, from: "Invented Distributed Systems")
        XCTAssertTrue(app.buttons["settings.topic.Invented Distributed Systems"].label.contains("Archived"))

        // Home lists the other under Study topics, and the archived one under Archived, closed.
        openTab(app, "Home")
        if app.navigationBars["NURS 310"].exists {
            goBack(app, from: "NURS 310")
        }
        let studied = app.buttons["home.topic.Invented Spanish Verbs"]
        reveal(studied, in: app)
        XCTAssertFalse(app.buttons["home.topic.Invented Distributed Systems"].exists)
        let archived = app.buttons["home.archived"]
        tapVisible(archived, in: app)
        XCTAssertEqual(archived.value as? String, "Open")
        let card = app.buttons["home.topic.Invented Distributed Systems"]
        reveal(card, in: app)
        XCTAssertTrue(app.staticTexts["Study topics"].exists)
        attachLooks(app, "T-12 home, archived")
    }
}

private extension XCUIElement {
    /// Deletes what the field holds, from its end.
    func clearText() {
        tap()
        let current = value as? String ?? ""
        let placeholder = placeholderValue ?? ""
        guard !current.isEmpty, current != placeholder else { return }
        coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
    }
}
