import Foundation
import QBankKit
import Testing
@testable import QBank

/// The course page's folders: the web's folder rules (`apps/web/src/course/folders.test.ts`), the
/// by-exam grouping with the server's rule for past exams, and what the phone remembers.
@MainActor
struct CourseFoldersTests {
    private func week(_ label: String, _ sets: [(questions: Int, answered: Int, right: Int)], bank: Int = 0) throws -> Week {
        let json = StudyBodies.week(label, sets: sets.enumerated().map { StudyBodies.set("\(label)-\($0.offset)", questions: $0.element.questions, answered: $0.element.answered, right: $0.element.right) }, bank: bank)
        return try QBankJSON.decoder.decode(Week.self, from: Data(json.utf8))
    }

    private func course(exams: [String]? = []) throws -> CourseDetail {
        try QBankJSON.decoder.decode(CourseDetail.self, from: Data(StudyBodies.course(exams: exams).utf8))
    }

    private func summary(_ json: String) throws -> ExamSummary {
        try QBankJSON.decoder.decode(ExamSummary.self, from: Data(json.utf8))
    }

    // MARK: Weeks

    @Test func progressAddsUpTheSetsAndNamesTheState() throws {
        let fresh = WeekProgress(try week("Week 1", [(14, 0, 0), (12, 0, 0)]))
        #expect(fresh == WeekProgress(try week("Week 9", [(14, 0, 0), (12, 0, 0)])))
        #expect(fresh.state == .fresh)
        #expect(fresh.setCount == 2)
        #expect(fresh.questionCount == 26)
        #expect(WeekProgress(try week("Week 3", [(15, 15, 12), (12, 7, 5)])).state == .started)
        #expect(WeekProgress(try week("Week 1", [(14, 14, 12), (13, 13, 10)])).state == .done)
        let over = WeekProgress(try week("Week 1", [(3, 5, 4)]))
        #expect(over.state == .done)
        #expect(over.answeredCount == 3)
        #expect(over.fullyRightCount == 3, "never past a set's size")
    }

    @Test func closedFolderLinesMatchTheWeb() throws {
        let fresh = try week("Week 4", [(14, 0, 0), (12, 0, 0)])
        #expect(FolderWording.weekMeta(fresh, WeekProgress(fresh)) == "2 sets · 26 questions")
        #expect(FolderWording.state(WeekProgress(fresh)) == "Not started")
        let started = try week("Week 3", [(15, 15, 12), (12, 7, 5)])
        #expect(FolderWording.weekMeta(started, WeekProgress(started)) == "2 sets · 22 of 27 answered")
        #expect(FolderWording.state(WeekProgress(started)) == "22 of 27")
        let done = try week("Week 1", [(14, 14, 12)])
        #expect(FolderWording.weekMeta(done, WeekProgress(done)) == "1 set · 12 of 14 fully right")
        #expect(FolderWording.state(WeekProgress(done)) == "Done")
        let bankOnly = try week("Week 8", [], bank: 1)
        #expect(FolderWording.weekMeta(bankOnly, WeekProgress(bankOnly)) == "Exam bank only · 1 question")
        #expect(FolderWording.state(WeekProgress(bankOnly)) == "")
        #expect(FolderWording.examBank(try week("Week 3", [(1, 0, 0)], bank: 27)) == "Exam bank: 27 questions, exams only")
        #expect(FolderWording.examBank(done) == "No exam bank yet · exams use practice questions")
    }

    @Test func onlyStartedWeeksOpenByThemselves() throws {
        let weeks = [
            try week("Week 1", [(2, 2, 2)]),
            try week("Week 2", [(2, 2, 2)]),
            try week("Week 3", [(2, 2, 2), (3, 1, 1)]),
            try week("Week 4", [(2, 0, 0)]),
            try week("Week 5", [(2, 0, 0)]),
        ]
        #expect(FolderDefaults.openWeeks(weeks) == ["Week 3"])
        #expect(FolderDefaults.openWeeks([try week("Week 1", [(2, 2, 2)]), try week("Week 2", [(2, 0, 0)])]) == ["Week 2"], "the newest when none is in progress")
        #expect(FolderDefaults.openWeeks([]).isEmpty)
    }

    // MARK: By exam

    @Test func examsHoldTheirWeeksAndThePastExamsOverThem() throws {
        let course = try course(exams: [
            StudyBodies.courseExam("x1", "Exam 1", order: 1, weeks: ["Week 1", "Week 2"]),
            StudyBodies.courseExam("x2", "Exam 2", order: 2, weeks: ["Week 9"]),
        ])
        let sittings = [
            try summary(StudyBodies.summary("s1", weeks: ["Week 1", "Week 2"], courseExam: "x1")),
            try summary(StudyBodies.summary("s2", weeks: ["Week 1"], courseExam: "x1")),
            try summary(StudyBodies.summary("s3", weeks: ["Week 1", "Week 3"])),
        ]
        let grouping = ExamGrouping(course: course, sittings: sittings)
        #expect(grouping.folders.map(\.exam.name) == ["Exam 1", "Exam 2"])
        let first = try #require(grouping.folders.first)
        #expect(first.weeks.map(\.label) == ["Week 1", "Week 2"])
        #expect(first.sittings.map(\.id) == ["s1", "s2"])
        #expect(first.progress.questionCount == 20)
        #expect(first.progress.answeredCount == 12)
        #expect(FolderWording.examMeta(first) == "Weeks 1-2 · 3 sets · 20 questions · 2 exams taken")
        #expect(FolderWording.state(first.progress) == "12 of 20")
        #expect(FolderWording.examDraw(first) == "20 questions from its 20 practice questions, or Wrong questions only.")
        // A week whose sets were moved away stays in the exam's name but shows no folder.
        #expect(grouping.folders[1].weeks.isEmpty)
        #expect(FolderWording.examMeta(grouping.folders[1]) == "Week 9")
        #expect(grouping.freeWeeks.map(\.label) == ["Week 3"])
        #expect(grouping.otherSittings.map(\.id) == ["s3"], "a sitting across two exams belongs to neither")
    }

    @Test func aSittingTheServerHasNotMatchedYetFollowsTheSubsetRule() throws {
        let course = try course(exams: [StudyBodies.courseExam("x1", "Exam 1", order: 1, weeks: ["Week 1", "Week 2"])])
        let stale = try summary(StudyBodies.summary("s1", weeks: ["Week 2"], courseExam: nil))
        let gone = try summary(StudyBodies.summary("s2", weeks: ["Week 3"], courseExam: "deleted"))
        let moved = try summary(StudyBodies.summary("s3", weeks: ["Week 1", "Week 3"], courseExam: "x1"))
        #expect(ExamGrouping.courseExam(of: stale, in: course.exams) == "x1")
        #expect(ExamGrouping.courseExam(of: gone, in: course.exams) == nil)
        #expect(ExamGrouping.courseExam(of: moved, in: course.exams) == nil, "x1 no longer holds Week 3")
    }

    @Test func examDrawNamesWhereItsQuestionsComeFrom() throws {
        let course = try course(exams: [StudyBodies.courseExam("x1", "Exam 1", order: 1, weeks: ["Week 2", "Week 3"])])
        let folder = try #require(ExamGrouping(course: course, sittings: []).folders.first)
        #expect(folder.examQuestionCount == 30, "Week 2's 10 practice questions and Week 3's exam bank of 20")
        #expect(FolderWording.examDraw(folder) == "30 questions from the 30 in its exam banks and practice sets, or Wrong questions only.")
    }

    @Test func theExamWithUnfinishedWorkOpensByItself() throws {
        let course = try course(exams: [
            StudyBodies.courseExam("x1", "Exam 1", order: 1, weeks: ["Week 1"]),
            StudyBodies.courseExam("x2", "Exam 2", order: 2, weeks: ["Week 2"]),
            StudyBodies.courseExam("x3", "Exam 3", order: 3, weeks: ["Week 3"]),
        ])
        let folders = ExamGrouping(course: course, sittings: []).folders
        #expect(FolderDefaults.openExams(folders) == ["x2"])
        #expect(FolderDefaults.openExams(Array(folders.dropFirst(2))) == ["x3"], "else the first not done")
        #expect(FolderDefaults.openExams([]).isEmpty)
    }

    // MARK: On this phone

    @Test func memoryKeepsEachCoursesFoldersAndView() {
        let defaults = TestApp.freshDefaults()
        let memory = CourseMemory(defaults: defaults)
        #expect(memory.view(course: "a") == nil)
        memory.setView(.exams, course: "a")
        memory.setWeek("Week 1", open: true, course: "a")
        memory.setWeek("Week 3", open: false, course: "a")
        memory.setExam("x1", open: false, course: "a")
        let again = CourseMemory(defaults: defaults)
        #expect(again.view(course: "a") == .exams)
        #expect(again.weeks(course: "a") == ["Week 1": true, "Week 3": false])
        #expect(again.exams(course: "a") == ["x1": false])
        #expect(again.weeks(course: "b").isEmpty)
        #expect(defaults.dictionary(forKey: "qbank.course-weeks.a") as? [String: Bool] == ["Week 1": true, "Week 3": false])
    }

    @Test func memoryIgnoresWhatItDidNotWrite() {
        let defaults = TestApp.freshDefaults()
        defaults.set(["Week 1": "yes", "Week 2": false], forKey: "qbank.course-weeks.c")
        defaults.set("sideways", forKey: "qbank.course-view.c")
        let memory = CourseMemory(defaults: defaults)
        #expect(memory.weeks(course: "c") == ["Week 2": false])
        #expect(memory.view(course: "c") == nil)
    }

    // MARK: The course model

    @Test func aCourseWithExamsOpensOnThemUntilSheChooses() async throws {
        let exams = [StudyBodies.courseExam("x1", "Exam 1", order: 1, weeks: ["Week 1"])]
        let server = StubServer([
            "GET /api/courses/c1": .ok(StudyBodies.course(exams: exams)),
            "GET /api/courses/c1/exams": .ok(StudyBodies.setup(
                weeks: StudyBodies.threeWeeks,
                inProgress: StudyBodies.summary("run", weeks: ["Week 1"], courseExam: "x1", finished: false),
                exams: [StudyBodies.summary("s1", weeks: ["Week 1"], courseExam: "x1")]
            )),
        ])
        let (app, _) = TestApp.make(server, account: .student())
        let model = CourseModel(app: app, id: "c1")
        await model.load()
        #expect(model.view == .exams)
        #expect(model.sittings.map(\.id) == ["run", "s1"], "the running exam first")
        #expect(model.grouping?.folders.first?.sittings.map(\.id) == ["run", "s1"])

        model.choose(.weeks)
        let again = CourseModel(app: app, id: "c1")
        await again.load()
        #expect(again.view == .weeks, "her choice stays on the phone")
    }

    @Test func aCourseWithoutExamsOpensOnWeeksAndStillLoadsWhenItsExamsCannot() async throws {
        let server = StubServer(["GET /api/courses/c1": .ok(StudyBodies.course(exams: nil))])
        let (app, _) = TestApp.make(server, account: .student())
        let model = CourseModel(app: app, id: "c1")
        await model.load()
        #expect(model.course?.exams == [], "an older server sends no exams")
        #expect(model.view == .weeks)
        #expect(model.sittings.isEmpty)
        #expect(model.problem == nil)
    }

    @Test func foldersFollowTheDefaultsUntilSheOpensOrClosesThem() async throws {
        let exams = [StudyBodies.courseExam("x1", "Exam 1", order: 1, weeks: ["Week 1", "Week 2"])]
        let server = StubServer([
            "GET /api/courses/c1": .ok(StudyBodies.course(exams: exams)),
            "GET /api/courses/c1/exams": .ok(StudyBodies.setup(weeks: StudyBodies.threeWeeks)),
        ])
        let (app, _) = TestApp.make(server, account: .student())
        let model = CourseModel(app: app, id: "c1")
        await model.load()
        let weeks = try #require(model.course?.weeks)
        #expect(weeks.map { model.isOpen(week: $0) } == [false, true, false])
        model.setOpen(true, week: weeks[2])
        model.setOpen(false, week: weeks[1])
        let folder = try #require(model.grouping?.folders.first)
        #expect(model.isOpen(exam: folder))
        model.setOpen(false, exam: folder)

        let again = CourseModel(app: app, id: "c1")
        await again.load()
        #expect(weeks.map { again.isOpen(week: $0) } == [false, false, true])
        #expect(!again.isOpen(exam: folder))
        #expect(again.examSetup(for: folder) == ExamSetupRoute(
            course: CourseRef(id: "c1", code: "NURS 101", title: "Invented Basics"), weeks: ["Week 1", "Week 2"], examName: "Exam 1"
        ))
    }
}
