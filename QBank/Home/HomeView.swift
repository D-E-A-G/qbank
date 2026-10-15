import QBankDesign
import QBankKit
import SwiftUI

/// The Home tab: her courses by semester. Opens the course she used last on arrival. Without a
/// connection it shows the courses saved on the phone, and how many answers wait to be sent.
struct HomeView: View {
    let app: AppModel
    @State private var model: HomeModel
    @State private var navigator = HomeNavigator()

    init(app: AppModel) {
        self.app = app
        _model = State(initialValue: HomeModel(app: app))
    }

    var body: some View {
        NavigationStack(path: $navigator.path) {
            ScrollView {
                content
                    .padding(.horizontal, QBankSpacing.gutterPhone)
                    .padding(.bottom, QBankSpacing.space7)
            }
            .qbankScreenBackground()
            .navigationTitle("Home")
            .toolbar {
                if let waiting = app.offline?.waiting.count, waiting > 0 {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink(value: SavedForOfflineRoute()) {
                            WaitingLabel(count: waiting)
                        }
                        .accessibilityIdentifier("home.waiting")
                    }
                } else if let refused = app.offline?.notSaved.count, refused > 0 {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink(value: SavedForOfflineRoute()) {
                            Text("\(Image(systemName: "exclamationmark.circle")) \(refused) not saved")
                                .foregroundStyle(.qbank(.wrong))
                                .accessibilityLabel("\(Wording.count(refused, "answer")) not saved")
                        }
                        .accessibilityIdentifier("home.notSaved")
                    }
                }
            }
            .refreshable {
                await model.load()
                model.saveForOffline(force: true)
            }
            .onAppear {
                // Back from a course: its counts may have changed.
                guard model.semesters != nil else { return }
                Task { await model.load() }
            }
            .reloadsWithConnection(app) {
                await model.load()
                model.saveForOffline()
            }
            .navigationDestination(for: CourseRoute.self) { route in
                CourseView(app: app, route: route)
            }
            .navigationDestination(for: StudyRoute.self) { route in
                switch route {
                case .review(let course): ReviewView(app: app, course: course)
                case .terms(let course): TermsView(app: app, course: course)
                case .exam(let setup): ExamSetupView(app: app, route: setup)
                }
            }
            .navigationDestination(for: SavedForOfflineRoute.self) { _ in
                SavedForOfflineView(app: app)
            }
        }
        .environment(navigator)
        .task {
            await model.load()
            model.saveForOffline()
            if let landing = await model.landingCourse(), navigator.path.isEmpty {
                navigator.open(landing)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let semesters = model.semesters {
            LazyVStack(alignment: .leading, spacing: QBankSpacing.space4) {
                if model.savedAt != nil {
                    OfflineBanner.showingSaved(phoneIsOnline: app.connection.isOnline)
                        .padding(.top, QBankSpacing.space3)
                        .accessibilityIdentifier("home.offline")
                }
                if let problem = model.problem ?? app.offline?.problem {
                    ProblemText(text: problem)
                        .padding(.top, QBankSpacing.space3)
                }
                if semesters.isEmpty {
                    EmptyCard(message: "A course appears here when its first question file is imported.")
                        .padding(.top, QBankSpacing.space3)
                }
                ForEach(semesters) { semester in
                    let courses = model.courses(in: semester)
                    QBankSectionHeader(semester.name)
                        .padding(.horizontal, QBankSpacing.space1)
                        .padding(.top, QBankSpacing.space5)
                        .padding(.bottom, -QBankSpacing.space2)
                    if courses.isEmpty {
                        EmptyCard(message: "A course appears here when its first question file is imported.")
                    }
                    ForEach(courses) { course in
                        NavigationLink(value: CourseRoute(id: course.id, code: course.code)) {
                            CourseCard(course: course, savedAt: model.savedAt(course))
                        }
                        .buttonStyle(QBankCardButtonStyle(padding: QBankSpacing.space4))
                        .accessibilityIdentifier("home.course.\(course.code)")
                    }
                }
            }
        } else if let problem = model.problem {
            LoadFailed(problem: problem) {
                Task { await model.load() }
            }
        } else {
            Loading(title: "Loading your courses")
        }
    }
}

/// A course on Home: code, title, size, what is waiting in Review, and how much she has answered.
/// Shown from the phone's copy, it says how old the copy is instead of the Review count.
struct CourseCard: View {
    let course: CourseSummary
    var savedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: QBankSpacing.space1) {
            Text(course.code)
                .qbankFont(.caption1)
                .foregroundStyle(.qbank(.text3))
            Text(course.title)
                .qbankFont(.headline)
                .foregroundStyle(.qbank(.text1))
                .multilineTextAlignment(.leading)
            HStack(alignment: .center, spacing: QBankSpacing.space3) {
                Text(Wording.size(questions: course.questionCount, folders: course.folderCount))
                    .qbankFont(.subheadline)
                    .foregroundStyle(.qbank(.text2))
                Spacer(minLength: 0)
                if let savedAt {
                    SavedBadge(date: savedAt)
                } else if course.reviewCount > 0 {
                    QBankTintedLabel("\(course.reviewCount) to review", systemImage: "tray", tone: .tint, size: .small)
                }
            }
            .padding(.top, QBankSpacing.space2)
            QBankProgressPill(value: Double(Wording.answeredPercent(course)) / 100)
                .padding(.top, QBankSpacing.space3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
