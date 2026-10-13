import QBankDesign
import QBankKit
import SwiftUI

/// A course: score line, the Exam, Review and Terms tiles, then each week's exam line and sets.
struct CourseView: View {
    let app: AppModel
    let route: CourseRoute
    @State private var model: CourseModel
    /// The set she is practicing, shown full screen over the tabs.
    @State private var practicing: PracticeRoute?

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
        .task {
            async let place: Void = model.rememberPlace()
            await model.load()
            await place
        }
        .fullScreenCover(item: $practicing, onDismiss: {
            // Her answers changed the set's line and the course's score.
            Task { await model.load() }
        }, content: { route in
            PracticeView(app: app, route: route)
        })
    }

    @ViewBuilder
    private var content: some View {
        if let course = model.course {
            VStack(alignment: .leading, spacing: QBankSpacing.space4) {
                summary(course)
                if let problem = model.problem {
                    ProblemText(text: problem)
                }
                tiles(course)
                if course.weeks.isEmpty {
                    EmptyCard(message: "This course has no question sets yet.")
                        .padding(.top, QBankSpacing.space3)
                }
                ForEach(course.weeks) { week in
                    WeekSection(week: week, isRestoring: model.isRestoring) { set in
                        practicing = PracticeRoute(setID: set.id, courseID: course.id, title: set.title)
                    } restore: { set in
                        Task { await model.restore(set) }
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

    private func tiles(_ course: CourseDetail) -> some View {
        HStack(spacing: QBankSpacing.space3) {
            NavigationLink(value: ComingSoonRoute.exam) {
                Tile(systemImage: "timer", value: "Exam", label: Wording.examLength(questionCount: course.examQuestionCount))
            }
            .accessibilityIdentifier("course.tile.exam")
            NavigationLink(value: ComingSoonRoute.review) {
                Tile(systemImage: "tray", value: "\(course.reviewCount)", label: "to review")
            }
            .accessibilityIdentifier("course.tile.review")
            NavigationLink(value: ComingSoonRoute.terms) {
                Tile(systemImage: "book", value: "\(course.termCount)", label: course.termCount == 1 ? "term" : "terms")
            }
            .accessibilityIdentifier("course.tile.terms")
        }
        .buttonStyle(QBankCardButtonStyle(padding: QBankSpacing.space4))
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

/// A week: its label, whether its exams have their own bank, and its sets.
private struct WeekSection: View {
    let week: Week
    let isRestoring: Bool
    let open: (PracticeSetSummary) -> Void
    let restore: (PracticeSetSummary) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: QBankSpacing.space3) {
            QBankSectionHeader(week.label)
                .padding(.horizontal, QBankSpacing.space1)
            QBankTintedLabel(
                Wording.examBank(week),
                systemImage: "timer",
                tone: .neutral,
                style: week.examBankCount > 0 ? .outline : .dashed,
                size: .small
            )
            .accessibilityIdentifier("course.bank.\(week.label)")
            if !week.sets.isEmpty {
                QBankListGroup {
                    ForEach(week.sets) { set in
                        SetRow(set: set, isRestoring: isRestoring) { open(set) } restore: { restore(set) }
                    }
                }
            }
        }
        .padding(.top, QBankSpacing.space5)
    }
}

/// A practice set: its title and how far she got. A replaced set offers its previous version back,
/// with Restore beside the row rather than inside it, so each is its own button. Restore asks first.
private struct SetRow: View {
    let set: PracticeSetSummary
    let isRestoring: Bool
    let open: () -> Void
    let restore: () -> Void
    @State private var asksToRestore = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: open) {
                SetLabel(set: set, showsChevron: !set.canRestore)
            }
            .buttonStyle(.qbankRow)
            .accessibilityIdentifier("course.set.\(set.title)")
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

/// A set's title and status line, in the web's type: headline over subhead.
private struct SetLabel: View {
    let set: PracticeSetSummary
    let showsChevron: Bool

    var body: some View {
        HStack(spacing: QBankSpacing.space4) {
            VStack(alignment: .leading, spacing: QBankSpacing.space1) {
                Text(set.title)
                    .qbankFont(.headline)
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
        .padding(.horizontal, QBankSpacing.rowPaddingHorizontal)
        .padding(.vertical, QBankSpacing.rowPaddingVertical)
        .frame(minHeight: QBankSpacing.rowMin)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
