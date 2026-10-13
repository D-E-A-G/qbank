import QBankDesign
import QBankKit
import SwiftUI

/// A course: score line, the Exam, Review and Terms tiles, a Weeks | Exams switch, then its sets
/// in folders: one per week, or one per exam with its weeks inside, as the web's course page and
/// the approved by-exam view show them.
struct CourseView: View {
    let app: AppModel
    let route: CourseRoute
    @State private var model: CourseModel
    /// The set or Review list she is practicing, shown full screen over the tabs.
    @State private var practicing: PracticeRoute?
    /// A past or running exam opened from the by-exam view.
    @State private var exam: ExamRoute?
    @State private var examExit: ExamExit?
    @State private var editsExams = false
    @Environment(HomeNavigator.self) private var navigator: HomeNavigator?

    init(app: AppModel, route: CourseRoute) {
        self.app = app
        self.route = route
        _model = State(initialValue: CourseModel(app: app, id: route.id))
    }

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, QBankSpacing.gutterPhone)
                .padding(.bottom, QBankSpacing.space7)
        }
        .qbankScreenBackground()
        .navigationTitle(model.course?.code ?? route.code ?? "Course")
        .refreshable { await model.load() }
        .reloadsWithConnection(app) { await model.load() }
        .task {
            async let place: Void = model.rememberPlace()
            await model.load()
            await place
        }
        .onAppear {
            // Back from Review, Terms or an exam: its counts may have changed.
            guard model.course != nil else { return }
            Task { await model.load() }
        }
        .fullScreenCover(item: $practicing, onDismiss: {
            // Her answers changed the set's line and the course's score.
            Task { await model.load() }
        }, content: { route in
            PracticeView(app: app, route: route)
        })
        .fullScreenCover(item: $exam, onDismiss: examClosed) { route in
            ExamView(app: app, examID: route.id) { how in
                examExit = how
                exam = nil
            }
        }
        .sheet(isPresented: $editsExams) {
            if let course = model.course {
                EditExamsView(app: app, course: course) { saved in
                    guard saved else { return }
                    Task { await model.load() }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let course = model.course, let ref = model.ref {
            VStack(alignment: .leading, spacing: QBankSpacing.space4) {
                summary(course)
                if model.savedAt != nil {
                    OfflineBanner.showingSaved(phoneIsOnline: app.connection.isOnline)
                        .accessibilityIdentifier("course.offline")
                }
                if let problem = model.problem {
                    ProblemText(text: problem)
                }
                tiles(course, ref: ref)
                if course.weeks.isEmpty {
                    EmptyCard(message: "This course has no question sets yet.")
                        .padding(.top, QBankSpacing.space3)
                } else {
                    QBankSegmentedControl(
                        "Group by",
                        selection: Binding(get: { model.view }, set: { model.choose($0) }),
                        options: [.init(.weeks, "Weeks"), .init(.exams, "Exams")]
                    )
                    .padding(.top, QBankSpacing.space2)
                    .accessibilityIdentifier("course.view")
                    switch model.view {
                    case .weeks:
                        weekFolders(course.weeks)
                    case .exams:
                        if let grouping = model.grouping {
                            byExam(grouping, ref: ref)
                        }
                    }
                }
            }
        } else if let problem = model.problem {
            LoadFailed(problem: problem) {
                Task { await model.load() }
            }
        } else {
            Loading(title: "Loading the course")
        }
    }

    private func summary(_ course: CourseDetail) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(course.title) · \(Wording.size(questions: course.questionCount, weeks: course.weekCount))")
            if let score = Wording.score(course) {
                Text(score)
            }
        }
        .qbankFont(.subheadline)
        .foregroundStyle(.qbank(.text2))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("course.summary")
    }

    private func tiles(_ course: CourseDetail, ref: CourseRef) -> some View {
        HStack(spacing: QBankSpacing.space3) {
            NavigationLink(value: StudyRoute.exam(ExamSetupRoute(course: ref))) {
                Tile(systemImage: "timer", value: "Exam", label: Wording.examLength(questionCount: course.examQuestionCount))
            }
            .accessibilityIdentifier("course.tile.exam")
            NavigationLink(value: StudyRoute.review(ref)) {
                Tile(systemImage: "tray", value: "\(course.reviewCount)", label: "to review")
            }
            .accessibilityIdentifier("course.tile.review")
            NavigationLink(value: StudyRoute.terms(ref)) {
                Tile(systemImage: "book", value: "\(course.termCount)", label: course.termCount == 1 ? "term" : "terms")
            }
            .accessibilityIdentifier("course.tile.terms")
        }
        .buttonStyle(QBankCardButtonStyle(padding: QBankSpacing.space4))
    }

    private func weekFolders(_ weeks: [Week]) -> some View {
        VStack(spacing: 10) {
            ForEach(weeks) { week in
                weekFolder(week)
            }
        }
    }

    private func weekFolder(_ week: Week) -> some View {
        WeekFolder(
            week: week,
            isOpen: Binding(get: { model.isOpen(week: week) }, set: { model.setOpen($0, week: week) })
        ) {
            ForEach(week.sets) { set in
                SetRow(set: set, isRestoring: model.isRestoring, isStudent: model.isStudent) {
                    practicing = PracticeRoute(source: .set(id: set.id), courseID: route.id, title: set.title)
                } restore: {
                    Task { await model.restore(set) }
                }
            }
            ExamBankLine(week: week)
        }
    }

    // MARK: By exam

    private func byExam(_ grouping: ExamGrouping, ref: CourseRef) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                QBankSectionHeader("By exam")
                Spacer(minLength: QBankSpacing.space3)
                Button("Edit exams") { editsExams = true }
                    .buttonStyle(.qbank(.plain, size: .small))
                    .accessibilityIdentifier("course.editExams")
            }
            .padding(.leading, QBankSpacing.space1)
            if grouping.folders.isEmpty {
                NoExamsCard { editsExams = true }
            }
            ForEach(grouping.folders) { folder in
                ExamFolderView(
                    folder: folder,
                    isOpen: Binding(get: { model.isOpen(exam: folder) }, set: { model.setOpen($0, exam: folder) })
                ) {
                    ForEach(folder.weeks) { week in
                        weekFolder(week)
                    }
                    if !folder.sittings.isEmpty {
                        sittings("Your exams", folder.sittings)
                            .padding(.top, QBankSpacing.space2)
                    }
                    if model.isStudent, !folder.weeks.isEmpty, let setup = model.examSetup(for: folder) {
                        VStack(alignment: .leading, spacing: QBankSpacing.space2) {
                            NavigationLink(value: StudyRoute.exam(setup)) {
                                Label("Start exam over \(Wording.weeks(folder.weeks.map(\.label)))", systemImage: "timer")
                            }
                            .buttonStyle(.qbank(.secondary, size: .medium, fullWidth: true))
                            .accessibilityIdentifier("course.startExam.\(folder.exam.name)")
                            if let draw = FolderWording.examDraw(folder) {
                                Text(draw)
                                    .qbankFont(.footnote)
                                    .foregroundStyle(.qbank(.text3))
                                    .padding(.horizontal, QBankSpacing.space1)
                            }
                        }
                        .padding(.top, QBankSpacing.space2)
                    }
                }
            }
            if !grouping.freeWeeks.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    QBankSectionHeader("Not in an exam yet")
                    Spacer(minLength: QBankSpacing.space3)
                    Button("Add to an exam") { editsExams = true }
                        .buttonStyle(.qbank(.plain, size: .small))
                        .accessibilityIdentifier("course.addToExam")
                }
                .padding(.leading, QBankSpacing.space1)
                .padding(.top, QBankSpacing.space4)
                ForEach(grouping.freeWeeks) { week in
                    weekFolder(week)
                }
            }
            if !grouping.otherSittings.isEmpty {
                sittings("Other exams", grouping.otherSittings)
                    .padding(.top, QBankSpacing.space4)
            }
        }
    }

    private func sittings(_ title: String, _ exams: [ExamSummary]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            QBankSectionHeader(title)
                .padding(.horizontal, QBankSpacing.space1)
            QBankListGroup {
                ForEach(exams) { sitting in
                    Button {
                        exam = ExamRoute(id: sitting.id)
                    } label: {
                        PastExamRow(exam: sitting)
                    }
                    .buttonStyle(.qbankRow)
                    .accessibilityIdentifier("course.sitting.\(sitting.id)")
                }
            }
        }
    }

    private func examClosed() {
        Task { await model.load() }
        if examExit == .openReview, let ref = model.ref {
            navigator?.open(StudyRoute.review(ref))
        }
        examExit = nil
    }
}

/// One of the three study tiles under the course title.
private struct Tile: View {
    let systemImage: String
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.qbank(.tint))
                .frame(height: 26)
                .padding(.bottom, QBankSpacing.space3)
                .accessibilityHidden(true)
            Text(value)
                .qbankFont(.title2)
                .monospacedDigit()
                .foregroundStyle(.qbank(.text1))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .qbankFont(.footnote)
                .foregroundStyle(.qbank(.text2))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Before the course has exams: what the view is for, and a way to make the first one.
private struct NoExamsCard: View {
    let add: () -> Void

    var body: some View {
        QBankCard(padding: QBankSpacing.space4) {
            VStack(alignment: .leading, spacing: QBankSpacing.space3) {
                Text("Group the course’s weeks into exams, such as Exam 1 for Weeks 1-3. Each exam then holds its weeks and the exams you took over them.")
                    .qbankFont(.subheadline)
                    .foregroundStyle(.qbank(.text2))
                Button(action: add) {
                    Label("Add an exam", systemImage: "plus")
                }
                .buttonStyle(.qbank(.secondary, size: .medium))
                .accessibilityIdentifier("course.addExam")
            }
        }
    }
}

/// A practice set in an open folder: its title and how far she got, lined up with the week name.
/// A replaced set offers its previous version back, with Restore beside the row rather than inside
/// it, so each is its own button. Restore asks first.
private struct SetRow: View {
    let set: PracticeSetSummary
    let isRestoring: Bool
    let isStudent: Bool
    let open: () -> Void
    let restore: () -> Void
    @State private var asksToRestore = false

    var body: some View {
        HStack(spacing: 0) {
            if isStudent {
                Button(action: open) {
                    SetLabel(set: set, showsChevron: !set.canRestore)
                }
                .buttonStyle(.qbankRow)
                .accessibilityIdentifier("course.set.\(set.title)")
            } else {
                SetLabel(set: set, showsChevron: false)
            }
            if set.canRestore {
                Button("Restore") { asksToRestore = true }
                    .buttonStyle(.qbank(.secondary, size: .small))
                    .disabled(isRestoring)
                    .padding(.trailing, QBankSpacing.rowPaddingHorizontal)
                    .accessibilityLabel("Restore the previous version of \(set.title)")
                    .accessibilityIdentifier("course.restore")
                    .confirmationDialog(
                        "Restore the previous “\(set.title)”?",
                        isPresented: $asksToRestore,
                        titleVisibility: .visible
                    ) {
                        Button("Restore", action: restore)
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("The set you are looking at stays saved. Restoring brings the previous version back, and you can swap again.")
                    }
            }
        }
    }
}

/// A set's title and status line, as the web's folder rows set them: callout over subhead.
private struct SetLabel: View {
    let set: PracticeSetSummary
    let showsChevron: Bool

    var body: some View {
        HStack(spacing: QBankSpacing.space4) {
            VStack(alignment: .leading, spacing: 2) {
                Text(set.title)
                    .qbankFont(.callout, weight: .semibold)
                    .foregroundStyle(.qbank(.text1))
                    .multilineTextAlignment(.leading)
                Text(Wording.status(set))
                    .qbankFont(.subheadline)
                    .foregroundStyle(.qbank(.text2))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.qbank(.text4))
                    .accessibilityHidden(true)
            }
        }
        .padding(.leading, FolderMetrics.inset)
        .padding(.trailing, QBankSpacing.rowPaddingHorizontal)
        .padding(.vertical, 10)
        .frame(minHeight: QBankSpacing.rowMin)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// The week's exam line at the foot of its open folder: its exam bank, or that its exams use
/// practice questions.
private struct ExamBankLine: View {
    let week: Week

    var body: some View {
        Label {
            Text(FolderWording.examBank(week))
        } icon: {
            Image(systemName: "timer")
                .foregroundStyle(.qbank(week.examBankCount > 0 ? .tint : .text3))
        }
        .qbankFont(.footnote)
        .foregroundStyle(.qbank(.text3))
        .padding(.leading, FolderMetrics.inset)
        .padding(.trailing, QBankSpacing.rowPaddingHorizontal)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("course.bank.\(week.label)")
    }
}
