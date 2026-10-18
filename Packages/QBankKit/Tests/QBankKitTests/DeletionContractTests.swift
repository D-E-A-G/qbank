import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import QBankKit

/// Deleting a set, a folder with its sets, and a past exam, Undo, and Recently deleted, against
/// recordings of the server's real routes: each call sends what the recorded request sent, and each
/// recorded response decodes into the models.
@Suite("Contract: deleting and Undo")
struct DeletionContractTests {
    static let course = "c0000000-0000-4000-8000-000000000701"
    static let week1 = "f0000000-0000-4000-8000-000000000701"
    static let week2 = "f0000000-0000-4000-8000-000000000702"
    static let exam1 = "ce000000-0000-4000-8000-000000000701"
    static let heartA = "5e700000-0000-4000-8000-000000000701"
    static let heartB = "5e700000-0000-4000-8000-000000000702"
    static let heartExam = "5e700000-0000-4000-8000-000000000703"
    static let lungs = "5e700000-0000-4000-8000-000000000704"
    static let kidneys = "5e700000-0000-4000-8000-000000000705"
    static let pastExam = "e0000000-0000-4000-8000-000000000701"
    static let runningExam = "e0000000-0000-4000-8000-000000000702"

    // MARK: A set

    @Test func aSetsPreviewNamesWhatGoesAndHowHerStandingChanges() async throws {
        let fixture = try Fixture.load("practice-set-delete-preview")
        let transport = try FixtureTransport([fixture])
        let (client, _) = TestClient.make(transport)
        let preview = try await client.practiceSetDeletion(id: Self.heartB)
        try expectRequest(transport.requests.first, matches: fixture)
        #expect(preview.setID == Self.heartB)
        #expect(preview.title == "Heart B")
        #expect(preview.kind == .practice)
        #expect(preview.folderID == Self.week1)
        #expect(preview.folderName == "Week 1")
        #expect(preview.examPageID == Self.exam1)
        #expect([preview.questionCount, preview.versionCount, preview.answeredCount, preview.reviewCount] == [3, 1, 1, 1] as [Int])
        #expect(preview.progress.answeredCount == CountChange(before: 7, after: 6))
        #expect(preview.progress.reviewCount == CountChange(before: 3, after: 2))
        #expect(preview.message == "Delete Heart B? Its 3 questions go with it. You have answered 1 of them: those answers stop counting toward your progress, and 1 question leaves your Review list. You can undo this for 30 days.")
        #expect(preview.refusal == nil)
        #expect(preview.confirm == "e1ce33d296348989")
        #expect(preview.undoDays == 30)
    }

    @Test func anExamSetsPreviewSaysItsFoldersExamsGoBackToPracticeQuestions() async throws {
        let fixture = try Fixture.load("practice-set-delete-preview-exam")
        let transport = try FixtureTransport([fixture])
        let (client, _) = TestClient.make(transport)
        let preview = try await client.practiceSetDeletion(id: Self.heartExam)
        try expectRequest(transport.requests.first, matches: fixture)
        #expect(preview.kind == .exam)
        #expect(preview.message.hasPrefix("Delete Heart A exam from Week 1's exam bank?"))
    }

    @Test func aSetIsDeletedWithThePreviewsConfirmAndUndoBringsItBackInItsFolder() async throws {
        let transport = try FixtureTransport("practice-set-delete", "practice-set-undo-delete")
        let (client, _) = TestClient.make(transport)
        try await client.deletePracticeSet(id: Self.heartB, confirm: "e1ce33d296348989")
        let folder = try await client.undoDeletePracticeSet(id: Self.heartB)
        try expectRequest(transport.requests.first, matches: Fixture.load("practice-set-delete"))
        try expectRequest(transport.requests.last, matches: Fixture.load("practice-set-undo-delete"))
        #expect(folder.id == Self.week1)
        #expect(folder.sets.map(\.title) == ["Heart A", "Heart B"])
        #expect(folder.examBankCount == 3)
        #expect(folder.examSets == [ExamSetSummary(id: Self.heartExam, title: "Heart A exam", questionCount: 3)])
    }

    // MARK: A folder

    @Test func aFoldersPreviewNamesEverySetThatGoesWithIt() async throws {
        let fixture = try Fixture.load("folder-delete-preview")
        let transport = try FixtureTransport([fixture])
        let (client, _) = TestClient.make(transport)
        let preview = try await client.folderDeletion(id: Self.week1)
        try expectRequest(transport.requests.first, matches: fixture)
        #expect(preview.folderID == Self.week1)
        #expect(preview.name == "Week 1")
        #expect(preview.examPageID == Self.exam1)
        #expect(preview.examPageName == "Exam 1")
        #expect(preview.sets.map(\.title) == ["Heart A", "Heart B", "Heart A exam"])
        #expect(preview.sets.map(\.kind) == [.practice, .practice, .exam])
        #expect([preview.setCount, preview.questionCount, preview.answeredCount, preview.reviewCount, preview.pastExamCount] == [3, 10, 4, 2, 0] as [Int])
        #expect(preview.message == "Delete Week 1? Its 3 sets go with it: Heart A, Heart B and Heart A exam, 10 questions in all. You have answered 4 of them: those answers stop counting toward your progress, and 2 questions leave your Review list. It comes off Exam 1. You can undo this for 30 days.")
        #expect(preview.refusal == nil)
        #expect(preview.confirm == "36a24767c0033cfc")
    }

    /// A set landed in the folder after she was warned: nothing is deleted, and a new preview names it.
    @Test func aFolderThatChangedSinceTheWarningIsRefusedAndPreviewedAgain() async throws {
        let transport = try FixtureTransport("folder-delete-changed", "folder-delete-preview-changed", "folder-delete")
        let (client, _) = TestClient.make(transport)
        let error = await #expect(throws: QBankError.self) {
            try await client.deleteFolder(id: Self.week1, confirm: "36a24767c0033cfc")
        }
        try MakeQuestionsContractTests.expect(error, is: Fixture.load("folder-delete-changed"), code: .deletionChanged)
        let again = try await client.folderDeletion(id: Self.week1)
        #expect(again.sets.map(\.title) == ["Heart A", "Heart B", "Heart C", "Heart A exam"])
        #expect(again.confirm != "36a24767c0033cfc")
        try await client.deleteFolder(id: Self.week1, confirm: again.confirm)
        let fixtures = try ["folder-delete-changed", "folder-delete-preview-changed", "folder-delete"].map(Fixture.load)
        for (request, fixture) in zip(transport.requests, fixtures) {
            try expectRequest(request, matches: fixture)
        }
    }

    /// The app always sends the preview's `confirm`; without one, a folder with sets is refused.
    @Test func aFolderWithSetsIsNotDeletedWithoutConfirm() throws {
        let fixture = try Fixture.load("folder-delete-unconfirmed")
        let response = try #require(HTTPURLResponse(url: TestClient.baseURL, statusCode: fixture.response.status, httpVersion: "HTTP/1.1", headerFields: nil))
        let error = QBankClient.failure(status: fixture.response.status, data: try fixture.responseData, response: response)
        try MakeQuestionsContractTests.expect(error, is: fixture, code: .confirmationRequired)
    }

    @Test func undoBringsTheFolderBackWithItsSets() async throws {
        let fixture = try Fixture.load("folder-undo-delete")
        let transport = try FixtureTransport([fixture])
        let (client, _) = TestClient.make(transport)
        let folder = try await client.undoDeleteFolder(id: Self.week1)
        try expectRequest(transport.requests.first, matches: fixture)
        #expect(folder.examPageID == Self.exam1)
        #expect(folder.sets.map(\.title) == ["Heart A", "Heart B", "Heart C"])
        #expect(folder.examSets.map(\.title) == ["Heart A exam"])
    }

    // MARK: A past exam

    @Test func aPastExamsPreviewSaysWhichAnswersGoBack() async throws {
        let fixture = try Fixture.load("exam-delete-preview")
        let transport = try FixtureTransport([fixture])
        let (client, _) = TestClient.make(transport)
        let preview = try await client.examDeletion(id: Self.pastExam)
        try expectRequest(transport.requests.first, matches: fixture)
        #expect(preview.examID == Self.pastExam)
        #expect(preview.courseID == Self.course)
        #expect(preview.finishedAt != nil)
        #expect([preview.questionCount, preview.answeredCount, preview.changedCount, preview.unansweredCount] == [3, 2, 1, 1] as [Int])
        #expect(preview.message == "Delete this exam? Your 2 answers on it go with it and stop counting toward your progress. 1 question goes back to your answer before it, and 1 question goes back to not answered. You can undo this for 30 days.")
        #expect(preview.refusal == nil)
    }

    @Test func aPastExamIsDeletedAndUndoListsItAgain() async throws {
        let transport = try FixtureTransport("exam-delete", "exam-undo-delete")
        let (client, _) = TestClient.make(transport)
        try await client.deleteExam(id: Self.pastExam, confirm: "3b71b71bc2530c3b")
        let exam = try await client.undoDeleteExam(id: Self.pastExam)
        try expectRequest(transport.requests.first, matches: Fixture.load("exam-delete"))
        try expectRequest(transport.requests.last, matches: Fixture.load("exam-undo-delete"))
        #expect(exam.id == Self.pastExam)
        #expect(exam.weeks == ["Week 2"])
        #expect(exam.endReason == .finished)
    }

    @Test func anExamStillGoingIsRefusedInHerWords() async throws {
        let preview = try Fixture.load("exam-delete-preview-in-progress")
        let refused = try Fixture.load("exam-delete-in-progress")
        let transport = try FixtureTransport([preview, refused])
        let (client, _) = TestClient.make(transport)
        let shown = try await client.examDeletion(id: Self.runningExam)
        #expect(shown.finishedAt == nil)
        #expect(shown.refusal == "This exam is still going. Finish or leave it, then delete it.")
        let error = await #expect(throws: QBankError.self) {
            try await client.deleteExam(id: Self.runningExam, confirm: shown.confirm)
        }
        try expectRequest(transport.requests.first, matches: preview)
        try expectRequest(transport.requests.last, matches: refused)
        try MakeQuestionsContractTests.expect(error, is: refused, code: .examInProgress)
    }

    // MARK: Refusals

    @Test func aSetARunningExamAsksIsRefusedWithThePreviewsSentence() async throws {
        let preview = try Fixture.load("practice-set-delete-preview-in-use")
        let refused = try Fixture.load("practice-set-delete-in-use")
        let transport = try FixtureTransport([preview, refused])
        let (client, _) = TestClient.make(transport)
        let shown = try await client.practiceSetDeletion(id: Self.heartExam)
        #expect(shown.refusal == "An exam in progress asks questions from Heart A exam. Finish or leave that exam first.")
        let error = await #expect(throws: QBankError.self) {
            try await client.deletePracticeSet(id: Self.heartExam, confirm: shown.confirm)
        }
        try expectRequest(transport.requests.last, matches: refused)
        try MakeQuestionsContractTests.expect(error, is: refused, code: .inUse)
    }

    @Test(arguments: [
        ("practice-set-undo-expired", DeletionContractTests.kidneys, ServerError.Code.undoExpired),
        ("practice-set-undo-with-folder", DeletionContractTests.heartA, .requestRefused),
    ])
    func undoRefusalsSayWhyInHerWords(name: String, set: String, code: ServerError.Code) async throws {
        let fixture = try Fixture.load(name)
        let transport = try FixtureTransport([fixture])
        let (client, _) = TestClient.make(transport)
        let error = await #expect(throws: QBankError.self) { try await client.undoDeletePracticeSet(id: set) }
        try expectRequest(transport.requests.first, matches: fixture)
        try MakeQuestionsContractTests.expect(error, is: fixture, code: code)
    }

    // MARK: Recently deleted

    @Test func recentlyDeletedListsFoldersWithTheirSetsSetsAndExams() async throws {
        let fixture = try Fixture.load("course-deleted")
        let transport = try FixtureTransport([fixture])
        let (client, _) = TestClient.make(transport)
        let deleted = try await client.recentlyDeleted(courseID: Self.course)
        try expectRequest(transport.requests.first, matches: fixture)
        #expect(deleted.undoDays == 30)
        #expect(!deleted.isEmpty)
        let folder = try #require(deleted.folders.first)
        #expect(folder.id == Self.week1)
        #expect(folder.examPageID == Self.exam1)
        #expect(folder.sets.map(\.title) == ["Heart A", "Heart B", "Heart C", "Heart A exam"])
        #expect(folder.undoRefusal == nil)
        #expect(abs(folder.undoUntil.timeIntervalSince(folder.deletedAt) - 30 * 86_400) < 0.001)
        // A set that went with its folder is under it; one deleted on its own is listed by itself.
        // Kidneys was deleted 31 days ago, so it is not listed.
        #expect(deleted.sets.map(\.id) == [Self.lungs])
        #expect(deleted.sets.first?.folderID == Self.week2)
        #expect(deleted.sets.first?.folderName == "Week 2")
        let exam = try #require(deleted.exams.first)
        #expect(exam.id == Self.pastExam)
        #expect(exam.exam.weeks == ["Week 2"])
        #expect(exam.exam.fullyRight == 2)
        #expect(exam.undoUntil > exam.deletedAt)
    }
}
