import Foundation
import QBankKit
import Testing
@testable import QBank

/// Deleting a set, a folder with its sets, and a past exam, Undo, and Recently deleted, end to end
/// against the fake server, which follows the server's rules and words; and the confirm a delete
/// sends and the refusals it shows, against a stub.
@MainActor
struct DeletionTests {
    static let communication = "communication-v1"
    static let communicationTitle = "Therapeutic Communication and the Relationship"

    /// The app signed in on the fake server as the student.
    static func app() -> AppModel {
        MakeQuestionsTests.app(maker: false)
    }

    static func course(_ app: AppModel) async -> CourseModel {
        let course = CourseModel(app: app, id: FakeQBankServer.mentalHealthID)
        await course.load()
        return course
    }

    // MARK: A set

    @Test func aSetsWarningSaysWhatGoesInTheServersWords() async throws {
        let model = DeleteModel(app: Self.app(), target: .set(id: Self.communication, title: Self.communicationTitle))
        #expect(model.title == "Delete \(Self.communicationTitle)?", "before the warning arrives")
        #expect(!model.canDelete)
        await model.load()
        let warning = try #require(model.warning)
        #expect(warning.title == "Delete \(Self.communicationTitle)?")
        #expect(warning.message == "Its 14 questions go with it. You have answered 9 of them: those answers stop counting toward your progress, and 5 questions leave your Review list. You can undo this for 30 days.")
        #expect(warning.refusal == nil)
        #expect(model.canDelete)
    }

    @Test func aDeletedSetLeavesItsFolderAndUndoPutsItBackInItsPlace() async throws {
        let app = Self.app()
        let course = await Self.course(app)
        #expect(course.folder(FakeStudy.week2)?.sets.map(\.id) == [Self.communication, "psychosocial-v2"])
        #expect(course.course?.reviewCount == 12)
        let model = DeleteModel(app: app, target: .set(id: Self.communication, title: Self.communicationTitle))
        await model.load()
        #expect(await model.delete())
        let offer = try #require(app.deletions.offer)
        #expect(offer.line == "\(Self.communicationTitle) deleted.")
        #expect(offer.state == .offered)
        await course.load()
        #expect(course.folder(FakeStudy.week2)?.sets.map(\.id) == ["psychosocial-v2"])
        #expect(course.course?.reviewCount == 7, "its questions leave Review")

        await app.deletions.undo(with: app)
        #expect(app.deletions.offer?.state == .undone)
        #expect(app.deletions.offer?.back == "\(Self.communicationTitle) is back.")
        await course.load()
        #expect(course.folder(FakeStudy.week2)?.sets.map(\.id) == [Self.communication, "psychosocial-v2"], "in its place")
        #expect(course.course?.reviewCount == 12)
    }

    @Test func anExamSetIsListedInItsFolderAndDeletedOnItsOwn() async throws {
        let app = Self.app()
        let course = await Self.course(app)
        let week1 = try #require(course.folder(FakeStudy.week1))
        #expect(week1.examSets == [ExamSetSummary(id: "bank1", title: "Rights and Communication Exam", questionCount: 17)])
        let model = DeleteModel(app: app, target: .set(id: "bank1", title: "Rights and Communication Exam"))
        await model.load()
        #expect(model.warning?.title == "Delete Rights and Communication Exam from Week 1's exam bank?")
        #expect(model.warning?.message == "Its 17 questions go with it, and exams over Week 1 go back to asking its practice questions. You can undo this for 30 days.")
        #expect(await model.delete())
        await course.load()
        #expect(course.folder(FakeStudy.week1)?.examSets == [])
        #expect(course.folder(FakeStudy.week1)?.examBankCount == 0)
        #expect(course.folder(FakeStudy.week1)?.sets.map(\.id) == ["rights-v1"], "its practice set stays")
    }

    // MARK: A folder

    /// Deleting a folder with sets warns that its sets go too, naming each one.
    @Test func aFoldersWarningNamesEverySetThatGoesWithIt() async throws {
        let model = DeleteModel(app: Self.app(), target: .folder(id: FakeStudy.week2, name: "Week 2"))
        await model.load()
        let warning = try #require(model.warning)
        #expect(warning.title == "Delete Week 2?")
        #expect(warning.message == "Its 2 sets go with it: Psychosocial Assessment and Safety Screening and \(Self.communicationTitle), 26 questions in all. You have answered 9 of them: those answers stop counting toward your progress, and 5 questions leave your Review list. It comes off Exam 1. Your 2 past exams over it stay. You can undo this for 30 days.")
        #expect(warning.deleted == "Week 2 and its 2 sets deleted.")
        #expect(warning.back == "Week 2 and its 2 sets are back.")
    }

    @Test func aDeletedFolderTakesItsSetsAndUndoPutsItBackOnItsExamPage() async throws {
        let app = Self.app()
        let course = await Self.course(app)
        let model = DeleteModel(app: app, target: .folder(id: FakeStudy.week2, name: "Week 2"))
        await model.load()
        #expect(await model.delete())
        await course.load()
        #expect(course.folder(FakeStudy.week2) == nil)
        #expect(course.layout?.page(FakeStudy.exam1)?.folders.map(\.name) == ["Week 1"], "it comes off Exam 1")
        #expect(app.deletions.offer?.line == "Week 2 and its 2 sets deleted.")

        await app.deletions.undo(with: app)
        await course.load()
        #expect(course.layout?.page(FakeStudy.exam1)?.folders.map(\.name) == ["Week 1", "Week 2"])
        #expect(course.folder(FakeStudy.week2)?.sets.count == 2, "with its sets")
    }

    // MARK: A past exam

    @Test func aPastExamIsDeletedFromExamSetupAndUndoListsItAgain() async throws {
        let app = Self.app()
        let ref = CourseRef(id: FakeQBankServer.mentalHealthID, code: "NURS 310", title: "Mental Health")
        let setup = ExamSetupModel(app: app, route: ExamSetupRoute(course: ref))
        await setup.load()
        let exams = try #require(setup.setup?.exams)
        #expect(exams.count == 3)
        let newest = try #require(exams.first)
        let model = DeleteModel(app: app, target: .exam(id: newest.id))
        await model.load()
        #expect(model.warning?.title == "Delete this exam?")
        #expect(model.warning?.message.hasPrefix("Your ") == true)
        #expect(model.warning?.message.hasSuffix("You can undo this for 30 days.") == true)
        #expect(await model.delete())
        #expect(app.deletions.offer?.line == "Exam deleted.")
        await setup.load()
        #expect(setup.setup?.exams.map(\.id) == exams.dropFirst().map(\.id))

        await app.deletions.undo(with: app)
        #expect(app.deletions.offer?.back == "The exam is back.")
        await setup.load()
        #expect(setup.setup?.exams.map(\.id) == exams.map(\.id))
    }

    // MARK: Refusals

    /// An exam in progress asks the folder's questions: the warning says so, and Delete waits.
    @Test func aDeleteTheServerRefusesForNowSaysWhyAndWaits() async throws {
        let app = Self.app()
        _ = try await app.client.startExam(courseID: FakeQBankServer.mentalHealthID, folderIDs: [FakeStudy.week2])
        let model = DeleteModel(app: app, target: .folder(id: FakeStudy.week2, name: "Week 2"))
        await model.load()
        #expect(model.warning?.refusal == "An exam in progress asks questions from Week 2. Finish or leave that exam first.")
        #expect(!model.canDelete)
        #expect(await model.delete() == false)
        #expect(app.deletions.offer == nil)
        let course = await Self.course(app)
        #expect(course.folder(FakeStudy.week2) != nil, "nothing was deleted")
    }

    @Test func anExamStillGoingCannotBeDeleted() async throws {
        let app = Self.app()
        let running = try await app.client.startExam(courseID: FakeQBankServer.mentalHealthID, folderIDs: [FakeStudy.week1])
        let model = DeleteModel(app: app, target: .exam(id: running.id))
        await model.load()
        #expect(model.warning?.refusal == "This exam is still going. Finish or leave it, then delete it.")
        #expect(!model.canDelete)
    }

    /// What goes changed since she was warned: nothing is deleted, she reads why and the new
    /// warning, and Delete sends the new confirm.
    @Test func aWarningThatChangedIsReadAgainBeforeAnythingGoes() async throws {
        let server = StubServer()
        let preview = { (confirm: String, sets: String) in
            StubServer.Reply.ok(#"{"folderId":"f1","name":"Week 1","examPageId":null,"examPageName":null,"sets":[],"setCount":\#(sets.isEmpty ? 0 : 1),"questionCount":2,"answeredCount":0,"reviewCount":0,"pastExamCount":0,"progress":\#(Self.standing),"message":"Delete Week 1? \#(sets)You can undo this for 30 days.","refusal":null,"confirm":"\#(confirm)","undoDays":30}"#)
        }
        server.script("GET /api/folders/f1/delete-preview", [preview("aaaa", ""), preview("bbbb", "Its set goes with it: Late, 2 questions in all. ")])
        server.script("DELETE /api/folders/f1", [
            .error(409, "deletion_changed", "Week 1 changed since you were warned. Look again before deleting it."),
            StubServer.Reply(status: 204, body: ""),
        ])
        let (app, _) = TestApp.make(server, account: .student())
        let model = DeleteModel(app: app, target: .folder(id: "f1", name: "Week 1"))
        await model.load()
        #expect(model.warning?.message == "You can undo this for 30 days.")
        #expect(await model.delete() == false)
        #expect(model.problem == "Week 1 changed since you were warned. Look again before deleting it.")
        #expect(model.warning?.message == "Its set goes with it: Late, 2 questions in all. You can undo this for 30 days.")
        #expect(model.warning?.confirm == "bbbb")
        #expect(app.deletions.offer == nil)
        #expect(await model.delete())
        #expect(model.problem == nil)
        let confirms = server.requests.filter { $0.httpMethod == "DELETE" }.map { URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)?.queryItems }
        #expect(confirms == [[URLQueryItem(name: "confirm", value: "aaaa")], [URLQueryItem(name: "confirm", value: "bbbb")]])
        #expect(app.deletions.offer?.line == "Week 1 and its set deleted.")
    }

    @Test func undoThatComesTooLateSaysSoInTheServersWords() async throws {
        let server = StubServer(["POST /api/practice-sets/s1/undo-delete": .error(409, "undo_expired", "Heart A was deleted more than 30 days ago, so it can't be brought back.")])
        let (app, _) = TestApp.make(server, account: .student())
        app.deletions.deleted(.set(id: "s1", title: "Heart A"), line: "Heart A deleted.", back: "Heart A is back.")
        await app.deletions.undo(with: app)
        #expect(app.deletions.offer?.state == .failed("Heart A was deleted more than 30 days ago, so it can't be brought back."))
    }

    // MARK: Recently deleted

    @Test func recentlyDeletedListsWhatWentAndBringsItBack() async throws {
        let app = Self.app()
        let deleteSet = DeleteModel(app: app, target: .set(id: "mixed-v1", title: "Mixed Clinical Judgment"))
        await deleteSet.load()
        #expect(await deleteSet.delete())
        let deleteFolder = DeleteModel(app: app, target: .folder(id: FakeStudy.week3, name: "Week 3"))
        await deleteFolder.load()
        #expect(await deleteFolder.delete())

        let list = RecentlyDeletedModel(app: app, courseID: FakeQBankServer.mentalHealthID)
        await list.load()
        let deleted = try #require(list.deleted)
        #expect(deleted.folders.map(\.name) == ["Week 3"])
        #expect(deleted.folders.first.map(RecentlyDeletedWording.sets) == "Anxiety, Panic, and Anxiolytics, Depression and Antidepressants and Depression and Anxiety Exam")
        #expect(deleted.sets.map(\.title) == ["Mixed Clinical Judgment"])
        #expect(deleted.sets.first.map(RecentlyDeletedWording.set) == "Weeks 1-3 · 8 questions")
        #expect(deleted.exams.isEmpty)
        let folder = try #require(deleted.folders.first)
        #expect(RecentlyDeletedWording.window(deletedAt: folder.deletedAt, undoUntil: folder.undoUntil, now: folder.deletedAt).hasPrefix("Deleted today · until "))

        let revision = app.deletions.revision
        await list.bringBack(.folder(id: folder.id, name: folder.name), saying: "Week 3 and its 3 sets are back.")
        #expect(list.back == "Week 3 and its 3 sets are back.")
        #expect(list.problem == nil)
        #expect(app.deletions.revision == revision + 1, "the course reads itself again")
        #expect(list.deleted?.folders.isEmpty == true)
        #expect(list.deleted?.sets.map(\.title) == ["Mixed Clinical Judgment"])
        let course = await Self.course(app)
        #expect(course.layout?.page(FakeStudy.exam2)?.folders.map(\.name) == ["Week 3"], "back on Exam 2")
    }

    @Test func aSetWhoseFolderIsDeletedWaitsForTheFolder() async throws {
        let app = Self.app()
        let deleteSet = DeleteModel(app: app, target: .set(id: "depression-v1", title: "Depression and Antidepressants"))
        await deleteSet.load()
        #expect(await deleteSet.delete())
        let deleteFolder = DeleteModel(app: app, target: .folder(id: FakeStudy.week3, name: "Week 3"))
        await deleteFolder.load()
        #expect(deleteFolder.warning?.message.contains("Depression and Antidepressants") == false, "a set deleted before is not named again")
        #expect(await deleteFolder.delete())
        let list = RecentlyDeletedModel(app: app, courseID: FakeQBankServer.mentalHealthID)
        await list.load()
        #expect(list.deleted?.sets.first?.undoRefusal == "Its folder Week 3 is deleted. Bring the folder back first.")
    }

    // MARK: Words

    @Test func theWarningSplitsAtItsQuestion() {
        let split = DeleteWording.split("Delete Week 1? Its 3 sets go with it: A, B and C, 10 questions in all. You can undo this for 30 days.")
        #expect(split?.title == "Delete Week 1?")
        #expect(split?.message == "Its 3 sets go with it: A, B and C, 10 questions in all. You can undo this for 30 days.")
        #expect(DeleteWording.split("No question here.") == nil)
        #expect(DeleteWording.deleted(.folder(id: "f", name: "Week 1")) == "Week 1 deleted.")
        #expect(DeleteWording.deleted(.folder(id: "f", name: "Week 1"), setCount: 1) == "Week 1 and its set deleted.")
        #expect(DeleteWording.back(.folder(id: "f", name: "Week 1")) == "Week 1 is back.")
        #expect(DeleteWording.question(.exam(id: "e")) == "Delete this exam?")
    }

    private static let standing = #"{"answeredCount":{"before":0,"after":0},"fullyRightCount":{"before":0,"after":0},"reviewCount":{"before":0,"after":0},"points":{"before":0,"after":0},"maxPoints":{"before":0,"after":0},"wrongCount":{"before":0,"after":0}}"#
}
