import QBankDesign
import QBankKit
import SwiftUI

/// An exam to open full screen: one just started, her running one, or a past one's result.
struct ExamRoute: Identifiable, Hashable {
    let id: String
}

/// How she left an exam's full screen.
enum ExamExit {
    /// Done: back where she opened it.
    case done
    case backToCourse
    case openReview
}

/// Exam setup: Resume her running exam, Wrong questions only, the folders to tick by exam page,
/// the summary of what Start draws, Start exam, and her past exams.
struct ExamSetupView: View {
    let app: AppModel
    @State private var model: ExamSetupModel
    @State private var running: ExamRoute?
    @State private var exit: ExamExit?
    @State private var asksToReplace = false
    @Environment(HomeNavigator.self) private var navigator: HomeNavigator?

    init(app: AppModel, route: ExamSetupRoute) {
        self.app = app
        _model = State(initialValue: ExamSetupModel(app: app, route: route))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: QBankSpacing.gapSection) {
                VStack(alignment: .leading, spacing: QBankSpacing.space4) {
                    Text("\(model.course.code) · \(model.course.title)")
                        .qbankFont(.subheadline)
                        .foregroundStyle(.qbank(.text2))
                    if model.needsConnection {
                        OfflineBanner.examsNeedConnection
                            .accessibilityIdentifier("exam.needsConnection")
                    }
                    if let problem = model.problem {
                        ProblemText(text: problem)
                    }
                    if let exam = model.setup?.inProgress {
                        runningExam(exam)
                    }
                }
                content
            }
            .padding(.horizontal, QBankSpacing.gutterPhone)
            .padding(.bottom, QBankSpacing.space7)
        }
        .qbankScreenBackground()
        .navigationTitle("Exam")
        .refreshable { await model.load() }
        .reloadsWithConnection(app) { await model.load() }
        .task { await model.load() }
        .sensoryFeedback(.selection, trigger: model.ticked)
        .confirmSheet(
            isPresented: $asksToReplace,
            title: "Start a new exam?",
            message: "The exam in progress ends now. What you answered on it is scored, and the rest score 0.",
            confirm: "Start new exam",
            isDestructive: false,
            identifier: "exam.replaceSheet"
        ) {
            start()
        }
        .fullScreenCover(item: $running, onDismiss: closed) { route in
            ExamView(app: app, examID: route.id) { how in
                exit = how
                running = nil
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let setup = model.setup {
            if setup.folders.isEmpty {
                EmptyCard(message: "This course has no questions yet. An exam draws from the sets in the folders you tick.", systemImage: "timer")
            } else {
                wrongOnlySwitch
                folderPicker
                if model.isStudent {
                    summary
                }
            }
            if !setup.folders.isEmpty {
                pastExams(setup.exams)
            }
        } else if model.problem == nil, !model.needsConnection {
            Loading(title: "Loading the exam setup")
        }
    }

    private func runningExam(_ exam: ExamSummary) -> some View {
        QBankListGroup {
            Button {
                running = ExamRoute(id: exam.id)
            } label: {
                QBankListRow(
                    model.isStudent ? "Exam in progress" : "Her exam in progress",
                    detail: model.runningLine(exam),
                    systemImage: "timer",
                    showsChevron: true
                ) {
                    if model.isStudent {
                        Text("Resume")
                            .qbankFont(.subheadline, weight: .semibold)
                            .foregroundStyle(.qbank(.tint))
                    }
                }
            }
            .buttonStyle(.qbankRow)
            .accessibilityIdentifier("exam.resume")
        }
    }

    private var wrongOnlySwitch: some View {
        QBankListGroup {
            Toggle(isOn: $model.wrongOnly) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wrong questions only")
                        .qbankFont(.body)
                        .foregroundStyle(.qbank(.text1))
                    Text("Last answer not fully right")
                        .qbankFont(.footnote)
                        .foregroundStyle(.qbank(.text3))
                }
            }
            .tint(QBankColor(.tint))
            .disabled(!model.isStudent)
            .padding(.horizontal, QBankSpacing.rowPaddingHorizontal)
            .padding(.vertical, 11)
            .frame(minHeight: QBankSpacing.rowMin)
            .accessibilityIdentifier("exam.wrongOnly")
        }
    }

    private var folderPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            QBankSectionHeader("Folders this exam covers")
                .padding(.horizontal, QBankSpacing.space5)
            if let line = model.preselectedLine {
                Text(line)
                    .qbankFont(.footnote, weight: .semibold)
                    .foregroundStyle(.qbank(.tint))
                    .padding(.horizontal, QBankSpacing.space5)
                    .padding(.bottom, QBankSpacing.space1)
                    .accessibilityIdentifier("exam.preselected")
            }
            ForEach(model.groups) { group in
                if let title = group.title {
                    Text(title)
                        .qbankFont(.subheadline, weight: .semibold)
                        .foregroundStyle(.qbank(.text2))
                        .padding(.horizontal, QBankSpacing.space5)
                        .padding(.top, QBankSpacing.space3)
                        .accessibilityAddTraits(.isHeader)
                }
                QBankListGroup {
                    ForEach(group.folders) { folder in
                        FolderPickRow(
                            name: folder.name,
                            meta: model.meta(folder),
                            isTicked: model.isTicked(folder),
                            canTick: model.canTick(folder),
                            drawn: model.drawn(folder),
                            isStudent: model.isStudent
                        ) {
                            model.toggle(folder)
                        }
                        // With its page when another folder shares its name, so each row is found by one name.
                        .accessibilityIdentifier("exam.folder.\(model.name(folder))")
                    }
                }
            }
            Text(model.footer)
                .qbankFont(.footnote)
                .foregroundStyle(.qbank(.text3))
                .padding(.horizontal, QBankSpacing.space5)
        }
    }

    private var summary: some View {
        QBankCard {
            VStack(alignment: .leading, spacing: QBankSpacing.space3) {
                if let count = model.summaryCount {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(count)
                            .qbankFont(.title3, weight: .bold)
                            .foregroundStyle(.qbank(.text1))
                        Text(model.summaryTime)
                            .qbankFont(.body)
                            .foregroundStyle(.qbank(.text2))
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("exam.summary.count")
                }
                Text(model.summarySplit)
                    .qbankFont(.subheadline)
                    .foregroundStyle(.qbank(.text1))
                    .accessibilityIdentifier("exam.summary.split")
                if let fallback = model.fallbackLine {
                    Text(fallback)
                        .qbankFont(.subheadline)
                        .foregroundStyle(.qbank(.text1))
                        .accessibilityIdentifier("exam.summary.fallback")
                }
                Text("Feedback comes at the end. Leaving midway ends the exam and scores what you answered.")
                    .qbankFont(.footnote)
                    .foregroundStyle(.qbank(.text3))
                Button("Start exam") {
                    if model.setup?.inProgress != nil {
                        asksToReplace = true
                    } else {
                        start()
                    }
                }
                .buttonStyle(.qbank(.primary, size: .large, fullWidth: true))
                .disabled(model.picked.isEmpty || model.isStarting || model.needsConnection)
                .padding(.top, QBankSpacing.space1)
                .accessibilityIdentifier("exam.start")
            }
        }
    }

    private func pastExams(_ exams: [ExamSummary]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            QBankSectionHeader("Past exams")
                .padding(.horizontal, QBankSpacing.space5)
            if exams.isEmpty {
                EmptyCard(
                    message: model.isStudent ? "Exams you finish show up here with their scores." : "Her finished exams show up here with their scores.",
                    systemImage: "timer"
                )
            } else {
                QBankListGroup {
                    ForEach(exams) { exam in
                        Button {
                            running = ExamRoute(id: exam.id)
                        } label: {
                            PastExamRow(exam: exam)
                        }
                        .buttonStyle(.qbankRow)
                        .accessibilityIdentifier("exam.past.\(exam.id)")
                    }
                }
            }
        }
    }

    private func start() {
        Task {
            if let exam = await model.start() {
                running = ExamRoute(id: exam.id)
            }
        }
    }

    /// After the exam's full screen closed: her counts changed, and she may have asked for Review
    /// or the course.
    private func closed() {
        Task { await model.load() }
        switch exit {
        case .openReview:
            navigator?.open(StudyRoute.review(model.course))
        case .backToCourse:
            navigator?.back()
        case .done, nil:
            break
        }
        exit = nil
    }
}

/// A folder to tick: its name, its question or wrong count, and how many the exam takes from it.
private struct FolderPickRow: View {
    let name: String
    let meta: String
    let isTicked: Bool
    let canTick: Bool
    let drawn: Int?
    let isStudent: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: QBankSpacing.space4) {
                if isStudent {
                    Image(systemName: isTicked ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(.qbank(isTicked ? .tint : .separatorStrong))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .qbankFont(.body)
                        .foregroundStyle(.qbank(.text1))
                    QBankDetailText(meta)
                        .qbankFont(.footnote)
                        .foregroundStyle(.qbank(.text3))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let drawn {
                    Text("\(drawn) in exam")
                        .qbankFont(.footnote, weight: .semibold)
                        .foregroundStyle(.qbank(.text2))
                }
            }
            .padding(.horizontal, QBankSpacing.rowPaddingHorizontal)
            .padding(.vertical, 11)
            .frame(minHeight: QBankSpacing.rowMin)
            .contentShape(.rect)
            .opacity(canTick || !isStudent ? 1 : 0.45)
        }
        .buttonStyle(.qbankRow)
        .disabled(!isStudent || !canTick)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isTicked ? .isSelected : [])
    }
}

/// A past exam: its folders and date, its minutes and kind, and how many were fully right.
struct PastExamRow: View {
    let exam: ExamSummary

    var body: some View {
        HStack(spacing: QBankSpacing.space4) {
            VStack(alignment: .leading, spacing: 2) {
                Text(exam.finishedAt == nil ? "\(Wording.folders(exam.weeks)) · In progress" : exam.pastTitle)
                    .qbankFont(.body)
                    .foregroundStyle(.qbank(.text1))
                Text(exam.finishedAt == nil ? "\(exam.answeredCount) of \(exam.questionCount) answered" : exam.pastLine)
                    .qbankFont(.footnote)
                    .foregroundStyle(.qbank(.text3))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(exam.finishedAt == nil ? "Resume" : exam.scoreText)
                .qbankFont(.subheadline, weight: .semibold)
                .monospacedDigit()
                .foregroundStyle(.qbank(exam.finishedAt == nil ? .tint : .text1))
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.qbank(.text4))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, QBankSpacing.rowPaddingHorizontal)
        .padding(.vertical, 11)
        .frame(minHeight: QBankSpacing.rowMin)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
