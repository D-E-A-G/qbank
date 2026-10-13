import QBankDesign
import QBankKit
import SwiftUI

/// The Home tab: her courses by semester. Opens the course she used last on arrival.
struct HomeView: View {
    let app: AppModel
    @State private var model: HomeModel
    @State private var path = NavigationPath()

    init(app: AppModel) {
        self.app = app
        _model = State(initialValue: HomeModel(app: app))
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                content
                    .padding(.horizontal, QBankSpacing.gutterPhone)
                    .padding(.bottom, QBankSpacing.space7)
            }
            .qbankScreenBackground()
            .navigationTitle("Home")
            .refreshable { await model.load() }
            .onAppear {
                // Back from a course: its counts may have changed.
                guard model.semesters != nil else { return }
                Task { await model.load() }
            }
            .navigationDestination(for: CourseRoute.self) { route in
                CourseView(app: app, route: route)
            }
            .navigationDestination(for: ComingSoonRoute.self) { route in
                ComingSoonView(route: route)
            }
        }
        .task {
            await model.load()
            if let landing = await model.landingCourse(), path.isEmpty {
                path.append(landing)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let semesters = model.semesters {
            LazyVStack(alignment: .leading, spacing: QBankSpacing.space4) {
                if let problem = model.problem {
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
                            CourseCard(course: course)
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
struct CourseCard: View {
    let course: CourseSummary

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
                Text(Wording.size(questions: course.questionCount, weeks: course.weekCount))
                    .qbankFont(.subheadline)
                    .foregroundStyle(.qbank(.text2))
                Spacer(minLength: 0)
                if course.reviewCount > 0 {
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
