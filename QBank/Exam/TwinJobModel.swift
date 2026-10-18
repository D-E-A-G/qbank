import Foundation
import Observation
import QBankKit

/// A twin job followed while its screen is open, as the web's twin job page
/// (`apps/web/src/exam/TwinJobScreen.tsx`): QBank reads her questions, writes their exam twins, and
/// files them; once done, the exam starts on the twins. The work goes on on the server when she
/// leaves; this only reads it, stops it, and starts the exam.
@Observable
final class TwinJobModel {
    let route: TwinJobRoute
    private(set) var job: TwinJob?
    /// Why the job could not be read, said in her words.
    private(set) var problem: String?
    /// Why Stop or Start exam on the twins did not go through.
    private(set) var actionProblem: String?
    /// The job is not hers or not there anymore.
    private(set) var isGone = false
    /// Her exam in progress, read once the twins are ready: starting the exam on them ends it.
    private(set) var inProgress: ExamSummary?
    private(set) var isStopping = false
    private(set) var isStarting = false

    private let app: AppModel
    private let pollInterval: Duration
    private var hasReadSetup = false

    init(app: AppModel, route: TwinJobRoute, pollInterval: Duration = .seconds(2)) {
        self.app = app
        self.route = route
        self.pollInterval = pollInterval
        job = route.seed
    }

    var course: CourseRef { route.course }

    /// The twins are filed, and the exam on them can start.
    var isDone: Bool {
        job?.status == .done
    }

    /// The server is working on it, so the screen keeps reading it, as it does before the first
    /// read, until the job turns out to be gone.
    var isWorking: Bool {
        !isGone && job.map(Twins.isRunning) ?? true
    }

    /// Stop and Start reach the server, so without a connection they wait.
    var needsConnection: Bool {
        !app.connection.isOnline
    }

    func load() async {
        do {
            job = try await app.client.twinJob(id: route.jobID)
            problem = nil
        } catch {
            if app.handle(error) { return }
            // A refusal is the answer; a dropped connection or a server hiccup is tried again.
            if case .server(let server) = error, server.status < 500 {
                isGone = true
            }
            problem = Wording.problem(error) ?? "Could not load the exam twins. Trying again."
        }
        if isDone, !hasReadSetup {
            await readSetup()
        }
    }

    /// Reads the job until it has ended, every couple of seconds, for as long as the screen is open.
    func follow() async {
        await load()
        while isWorking, !Task.isCancelled {
            try? await Task.sleep(for: pollInterval)
            guard !Task.isCancelled else { return }
            await load()
        }
    }

    /// Her exam in progress, so Start exam on the twins asks first, as Exam setup does.
    private func readSetup() async {
        guard let setup = try? await app.client.examSetup(courseID: route.course.id) else { return }
        hasReadSetup = true
        inProgress = setup.inProgress
    }

    /// Stops the job. Nothing more is written or filed; sets already filed stay.
    func stop() async {
        guard !isStopping else { return }
        isStopping = true
        actionProblem = nil
        defer { isStopping = false }
        do {
            job = try await app.client.cancelTwinJob(id: route.jobID)
        } catch {
            if app.handle(error) { return }
            actionProblem = Wording.problem(error) ?? "Could not stop the exam twins."
        }
    }

    /// Starts the exam the job names, sent as it is: the folders the twins are in, and the pool
    /// she picked. Her exam in progress ends first, which she was asked about. Returns the exam to
    /// open, or nil after a refusal, said in her words.
    func startExam() async -> Exam? {
        guard let job, let exam = job.exam, !isStarting, !needsConnection else { return nil }
        isStarting = true
        actionProblem = nil
        defer { isStarting = false }
        do {
            let started = try await app.client.startExam(courseID: job.course.id, on: exam)
            inProgress = nil
            return started
        } catch {
            if app.handle(error) { return nil }
            actionProblem = Wording.problem(error) ?? "Could not start the exam."
            return nil
        }
    }

    /// After the exam's full screen closed: an exam she left running asks again before the next one.
    func examClosed() async {
        hasReadSetup = false
        if isDone { await readSetup() }
    }
}
