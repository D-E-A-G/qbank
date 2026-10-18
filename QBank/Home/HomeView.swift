import QBankDesign
import QBankKit
import SwiftUI

/// The Home tab: her courses by semester. Opens the course she used last on arrival. Without a
/// connection it shows the courses saved on the phone, and how many answers wait to be sent.
///
/// On iPhone, a course opens over the list. On iPad, the list stays in a sidebar and the course
/// opens beside it, with its own screens; an iPad sharing its screen narrows it to one column.
struct HomeView: View {
    let app: AppModel
    @State private var model: HomeModel
    @Bindable private var navigator: HomeNavigator

    init(app: AppModel, navigator: HomeNavigator) {
        self.app = app
        self.navigator = navigator
        _model = State(initialValue: HomeModel(app: app))
    }

    var body: some View {
        Group {
            if navigator.isSplit {
                split
            } else {
                stack
            }
        }
        .environment(navigator)
        .task {
            await model.load()
            model.saveForOffline()
            if let landing = await model.landingCourse(), navigator.path.isEmpty, navigator.course == nil {
                navigator.open(landing)
            }
        }
    }

    /// iPhone: the courses, and a course pushed over them.
    private var stack: some View {
        NavigationStack(path: $navigator.path) {
            courses
                .onAppear {
                    // Back from a course: its counts may have changed.
                    guard model.semesters != nil else { return }
                    Task { await model.load() }
                }
                .navigationDestination(for: CourseRoute.self) { route in
                    CourseView(app: app, route: route)
                }
                .studyDestinations(app: app)
        }
        .undoBar(app)
    }

    /// iPad: the courses in a sidebar, and the course she chose beside them.
    private var split: some View {
        NavigationSplitView(preferredCompactColumn: $navigator.compactColumn) {
            courses
                .navigationSplitViewColumnWidth(QBankLayout.sidebarWidth)
        } detail: {
            NavigationStack(path: $navigator.path) {
                Group {
                    if let course = navigator.course {
                        CourseView(app: app, route: course)
                            // Another course gets a screen of its own.
                            .id(course.id)
                    } else {
                        NoCourseChosen(hasCourses: model.semesters.map { !$0.flatMap(\.courses).isEmpty })
                    }
                }
                .studyDestinations(app: app)
            }
            .undoBar(app)
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: navigator.courseRevision) {
            // The open course's counts changed, after practice or an exam: the list follows.
            Task { await model.load() }
        }
    }

    private var courses: some View {
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
                    savedForOffline {
                        WaitingLabel(count: waiting)
                    }
                    .accessibilityIdentifier("home.waiting")
                }
            } else if let refused = app.offline?.notSaved.count, refused > 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    savedForOffline {
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
        .reloadsWithConnection(app) {
            await model.load()
            model.saveForOffline()
        }
    }

    /// Opens Saved for offline: over Home on iPhone, beside it on iPad.
    @ViewBuilder
    private func savedForOffline(@ViewBuilder label: () -> some View) -> some View {
        if navigator.isSplit {
            Button {
                navigator.open(SavedForOfflineRoute())
            } label: {
                label()
            }
        } else {
            NavigationLink(value: SavedForOfflineRoute(), label: label)
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
                        courseLink(course)
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

    /// A course card: pushes the course on iPhone, and on iPad shows it beside the list, marked
    /// as the one open.
    @ViewBuilder
    private func courseLink(_ course: CourseSummary) -> some View {
        let route = CourseRoute(id: course.id, code: course.code)
        let card = CourseCard(course: course, savedAt: model.savedAt(course), isNarrow: navigator.isSplit)
        if navigator.isSplit {
            let isOpen = navigator.course?.id == course.id
            Button {
                navigator.select(route)
            } label: {
                card
            }
            .buttonStyle(QBankCardButtonStyle(padding: QBankSpacing.space4))
            .overlay {
                if isOpen {
                    RoundedRectangle(cornerRadius: QBankRadius.md, style: .continuous)
                        .strokeBorder(.qbank(.tint), lineWidth: QBankBorder.emphasis)
                }
            }
            .accessibilityAddTraits(isOpen ? .isSelected : [])
        } else {
            NavigationLink(value: route) {
                card
            }
            .buttonStyle(QBankCardButtonStyle(padding: QBankSpacing.space4))
        }
    }
}

extension View {
    /// The screens a course leads to, on Home's navigation stack: Review, Terms, the Exam, its exam
    /// twins, and Saved for offline.
    func studyDestinations(app: AppModel) -> some View {
        navigationDestination(for: StudyRoute.self) { route in
            switch route {
            case .review(let course): ReviewView(app: app, course: course)
            case .terms(let course): TermsView(app: app, course: course)
            case .exam(let setup): ExamSetupView(app: app, route: setup)
            case .twinJob(let job): TwinJobView(app: app, route: job)
            }
        }
        .navigationDestination(for: SavedForOfflineRoute.self) { _ in
            SavedForOfflineView(app: app)
        }
    }
}

/// The iPad's course column before she chooses a course, as when she has none or opened none yet.
private struct NoCourseChosen: View {
    /// Nil while the courses load.
    let hasCourses: Bool?

    var body: some View {
        VStack(spacing: QBankSpacing.space3) {
            Image(systemName: "books.vertical")
                .font(.system(size: 40))
                .foregroundStyle(.qbank(.text4))
                .padding(.bottom, QBankSpacing.space2)
                .accessibilityHidden(true)
            if let hasCourses {
                Text(hasCourses ? "Choose a course" : "No courses yet")
                    .qbankFont(.title3)
                    .foregroundStyle(.qbank(.text1))
                Text(hasCourses ? "Its exam pages, folders, Review and Terms open here." : "A course appears here when its first question file is imported.")
                    .qbankFont(.subheadline)
                    .foregroundStyle(.qbank(.text2))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(QBankSpacing.gutterTablet)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .qbankScreenBackground()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home.noCourse")
    }
}

/// A course on Home: code, title, size, what is waiting in Review, and how much she has answered.
/// Shown from the phone's copy, it says how old the copy is instead of the Review count.
struct CourseCard: View {
    let course: CourseSummary
    var savedAt: Date?
    /// In the iPad's sidebar, the badge goes under the size, which then fits on one line.
    var isNarrow = false

    var body: some View {
        VStack(alignment: .leading, spacing: QBankSpacing.space1) {
            Text(course.code)
                .qbankFont(.caption1)
                .foregroundStyle(.qbank(.text3))
            Text(course.title)
                .qbankFont(.headline)
                .foregroundStyle(.qbank(.text1))
                .multilineTextAlignment(.leading)
            let line = isNarrow
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: QBankSpacing.space3))
                : AnyLayout(HStackLayout(alignment: .center, spacing: QBankSpacing.space3))
            line {
                Text(Wording.size(questions: course.questionCount, folders: course.folderCount))
                    .qbankFont(.subheadline)
                    .foregroundStyle(.qbank(.text2))
                if !isNarrow {
                    Spacer(minLength: 0)
                }
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
