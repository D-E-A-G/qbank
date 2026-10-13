import Foundation
import QBankKit
import Testing
@testable import QBank

@MainActor
struct SavedForOfflineTests {
    @Test func listsTheWaitingAnswersBySetAndTheSavedCourses() async throws {
        let server = StubServer([
            "GET /api/semesters": .ok(Bodies.semesters()),
            "GET /api/courses/c1": .ok(Bodies.courseDetail(sets: [Bodies.set(id: "set1", title: "Rights, Law, and Ethics", questionIDs: ["q-sata", "q-single"])])),
            "GET /api/practice-sets/set1": .ok(PracticeModelTests.practiceSet()),
        ])
        let connection = Connection()
        let (app, _) = TestApp.make(server, account: .student(), connection: connection)
        let home = HomeModel(app: app)
        await home.load()
        home.saveForOffline()
        await app.offline?.finishSavingCourses()

        let practice = PracticeModel(app: app, source: .set(id: "set1"), courseID: "c1", title: "Rights, Law, and Ethics")
        await practice.load()
        connection.update(isOnline: false)
        practice.update(.sata([0]))
        await practice.check()

        let model = SavedForOfflineModel(app: app)
        await model.load()
        #expect(model.groups.map(\.title) == ["Rights, Law, and Ethics"])
        #expect(model.groups.map(\.count) == [1])
        #expect(model.courses?.map(\.code) == ["NURS 101"])
        #expect(model.courses?.first?.savedQuestionCount == 2)

        server["POST /api/attempts"] = StubServer.Reply(status: 201, body: PracticeModelTests.saved(id: "x", question: "q-sata", status: "incorrect", points: 0, max: 2))
        await model.sendNow()
        #expect(model.groups.isEmpty)
        #expect(app.offline?.waiting.isEmpty == true)
    }
}
