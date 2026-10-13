import QBankDesign
import QBankKit
import SwiftUI

/// A practice set to open from the Course screen.
struct PracticeRoute: Identifiable, Hashable {
    let setID: String
    let courseID: String
    let title: String

    var id: String { setID }
}

/// The practice runner, shown full screen over the tabs: one question at a time, Check answer,
/// the verdict with a reason on every choice, the rationale, then the set result. Swipe-down does
/// not close it, so a stray thumb never loses a half-answered question; ✕ closes. Answers waiting
/// on the phone to be sent show as a count at the top right, which opens Saved for offline.
struct PracticeView: View {
    @State private var model: PracticeModel
    @State private var showsWaiting = false
    @Environment(\.dismiss) private var dismiss

    init(app: AppModel, route: PracticeRoute) {
        _model = State(initialValue: PracticeModel(app: app, setID: route.setID, courseID: route.courseID, title: route.title))
    }

    init(model: PracticeModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        Group {
            if let result = model.result {
                PracticeResultView(result: result) { dismiss() }
                    .transition(.opacity)
            } else {
                runner
            }
        }
        .animation(QBankMotion.reveal, value: model.phase)
        .qbankScreenBackground()
        .task { await model.load() }
        .sheet(isPresented: $showsWaiting) {
            NavigationStack {
                SavedForOfflineView(app: model.app)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showsWaiting = false }
                                .accessibilityIdentifier("savedForOffline.done")
                        }
                    }
            }
        }
    }

    private var runner: some View {
        RunnerShell(
            count: model.phase == .answering ? model.countText : "",
            title: model.title,
            progress: model.progress,
            waiting: model.waitingCount,
            close: { dismiss() },
            showWaiting: { showsWaiting = true }
        ) {
            content
        } footer: {
            if model.phase == .answering {
                footer
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            RunnerNote(text: "Loading the set.")
        case .failed(let problem):
            RunnerNote(text: problem)
        case .readOnly:
            RunnerNote(text: "Only she can answer questions. Her progress is read-only here.")
        case .answering, .finished:
            if let question = model.question, let attempt = model.attempt {
                QuestionPage(model: model, question: question, attempt: attempt)
                    .id(model.index)
            } else {
                RunnerNote(text: "This set has no questions.")
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if model.isRevealed || model.attempt?.draft == .unsupported {
            Button(model.isLast ? "See results" : "Next question") {
                model.next()
            }
            .buttonStyle(.qbank(.primary, size: .large, fullWidth: true))
            .accessibilityIdentifier("practice.next")
        } else if model.attempt != nil {
            Button("Check answer") {
                Task { await model.check() }
            }
            .buttonStyle(.qbank(.primary, size: .large, fullWidth: true))
            .disabled(!model.canCheck)
            .accessibilityIdentifier("practice.check")
        }
    }
}

/// The runner's frame: ✕, the question count over the set title, answers waiting to be sent, the
/// progress track, the scrolling question, and the pinned footer action. Content scrolls under
/// both bars.
private struct RunnerShell<Content: View, Footer: View>: View {
    let count: String
    let title: String
    let progress: Double
    let waiting: Int
    let close: () -> Void
    let showWaiting: () -> Void
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    /// Both sides of the header are as wide, so the count stays centered.
    private var sideWidth: CGFloat { waiting > 0 ? 96 : 44 }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 0).id(RunnerScroll.top)
                    content
                }
                .frame(maxWidth: QBankLayout.contentMax, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, QBankSpacing.gutterPhone)
                .padding(.top, 20)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.never)
            .environment(\.runnerScroll, RunnerScroll(proxy: proxy))
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    footer
                }
                .frame(maxWidth: QBankLayout.contentMax)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, QBankSpacing.gutterPhone)
                .padding(.vertical, QBankSpacing.space4)
                .background { RunnerBar(edge: .top) }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .foregroundStyle(.qbank(.text2))
                .accessibilityLabel("Close")
                .accessibilityIdentifier("practice.close")
                .frame(width: sideWidth, alignment: .leading)
                VStack(spacing: 0) {
                    Text(count)
                        .qbankFont(.headline)
                        .monospacedDigit()
                        .foregroundStyle(.qbank(.text1))
                    Text(title)
                        .qbankFont(.caption1)
                        .foregroundStyle(.qbank(.text3))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("practice.count")
                Group {
                    if waiting > 0 {
                        Button(action: showWaiting) {
                            QBankTintedLabel("\(waiting) waiting", systemImage: "arrow.up.circle", tone: .tint, size: .small)
                                .frame(minHeight: 44)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Wording.waitingToSend(waiting))
                        .accessibilityIdentifier("practice.waiting")
                    } else {
                        Color.clear.frame(width: 44, height: 44)
                    }
                }
                .frame(width: sideWidth, alignment: .trailing)
            }
            .padding(.horizontal, QBankSpacing.space3)
            .frame(minHeight: 48)
            QBankProgressBar(value: progress, height: 3, accessibilityTitle: "Progress")
                .padding(.horizontal, QBankSpacing.gutterPhone)
                .padding(.bottom, QBankSpacing.space3)
        }
        .background { RunnerBar(edge: .bottom) }
    }
}

/// The translucent bar behind the runner's header and footer, with a hairline on the side that
/// meets the question.
private struct RunnerBar: View {
    let edge: VerticalEdge

    var body: some View {
        Rectangle()
            .fill(.qbank(.material))
            .background(.ultraThinMaterial)
            .overlay(alignment: edge == .top ? .top : .bottom) {
                Rectangle()
                    .fill(.qbank(.separator))
                    .frame(height: QBankBorder.hairline)
            }
            .ignoresSafeArea()
    }
}

/// Lets a question scroll the runner: back to the top for a new question, and to the verdict
/// when she checks.
struct RunnerScroll {
    static let top = "practice.top"
    static let feedback = "practice.feedback"

    var proxy: ScrollViewProxy?

    func scroll(to id: String, anchor: UnitPoint? = nil) {
        proxy?.scrollTo(id, anchor: anchor)
    }
}

extension EnvironmentValues {
    @Entry var runnerScroll = RunnerScroll()
}

/// A short line in place of the question: loading, a problem, or nothing to answer.
private struct RunnerNote: View {
    let text: String

    var body: some View {
        Text(text)
            .qbankFont(.body)
            .foregroundStyle(.qbank(.text2))
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("practice.note")
    }
}

/// One question: format and topic, stem, exhibits, ask, then her answer. After Check answer, the
/// verdict sits right under the ask, every choice carries its reason, and the rationale, key
/// takeaway and terms follow.
private struct QuestionPage: View {
    let model: PracticeModel
    let question: Question
    let attempt: PracticeModel.Attempt
    @Environment(\.runnerScroll) private var scroll

    private var revealed: Bool { attempt.score != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let problem = model.problem {
                ProblemText(text: problem)
            }
            meta
            Text(question.stem)
                .qbankFont(.reading)
                .foregroundStyle(.qbank(.text1))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("practice.stem")
            StemExhibits(question: question)
            Text(question.ask)
                .qbankFont(.headline)
                .foregroundStyle(.qbank(.text1))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            if let score = attempt.score {
                VStack(alignment: .leading, spacing: QBankSpacing.space4) {
                    if model.isWaitingToSend {
                        Group {
                            if model.app.offline?.keepsAnswers == false {
                                OfflineBanner.answerNotKept
                            } else {
                                OfflineBanner.answerSaved
                            }
                        }
                        .accessibilityIdentifier("practice.savedOnPhone")
                    }
                    FeedbackBox(score: score, type: question.type, guessed: attempt.guessed)
                }
                .id(RunnerScroll.feedback)
            }
            AnswerArea(
                question: question,
                layout: attempt.layout,
                draft: attempt.draft,
                revealed: revealed,
                isLocked: revealed || model.isChecking
            ) { draft in
                model.update(draft)
            }
            if !revealed, attempt.draft != .unsupported {
                GuessToggle(isOn: Binding(get: { attempt.guessed }, set: { model.setGuessed($0) }))
                    .disabled(model.isChecking)
            }
            if revealed {
                RationaleSections(question: question)
                    .padding(.top, QBankSpacing.space2)
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: revealed) { _, now in now }
        .onAppear {
            scroll.scroll(to: RunnerScroll.top, anchor: .top)
        }
        .onChange(of: revealed) { _, now in
            guard now else { return }
            withAnimation(QBankMotion.reveal) {
                scroll.scroll(to: RunnerScroll.feedback)
            }
            AccessibilityNotification.Announcement(attempt.score?.label ?? "").post()
        }
    }

    private var meta: some View {
        FlowLayout(spacing: 10, lineSpacing: QBankSpacing.space2, rowAlignment: .firstTextBaseline) {
            Text(Wording.format(question.type))
                .foregroundStyle(.qbank(.tint))
            if !question.topic.isEmpty {
                Text(question.topic)
                    .foregroundStyle(.qbank(.text3))
            }
        }
        .qbankFont(.footnote, weight: .semibold)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("practice.meta")
    }
}

/// The verdict under the question: Correct, Partly correct or Not correct, the points of a
/// multi-part answer, the scoring rule, and whether it was a guess.
private struct FeedbackBox: View {
    let score: Score
    let type: QuestionType?
    let guessed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: QBankSpacing.space2) {
            Label {
                Text(score.label)
            } icon: {
                Image(systemName: icon)
                    .fontWeight(.semibold)
            }
            .qbankFont(.headline)
            .foregroundStyle(.qbank(tone))
            Group {
                if let type, let points = score.pointsText(for: type) {
                    Text(points)
                }
                if let rule = type?.scoringRule {
                    Text(rule)
                }
                if guessed {
                    Text("Flagged as a guess")
                }
            }
            .qbankFont(.subheadline)
            .foregroundStyle(.qbank(.text1))
        }
        .padding(.vertical, 14)
        .padding(.horizontal, QBankSpacing.space5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.qbank(soft), in: .rect(cornerRadius: QBankRadius.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: QBankRadius.sm, style: .continuous)
                .strokeBorder(.qbank(border), lineWidth: QBankBorder.regular)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("practice.feedback")
    }

    private var icon: String {
        switch score.status {
        case .correct: "checkmark.circle"
        case .partial: "minus.circle"
        case .incorrect: "xmark.circle"
        }
    }

    private var tone: QBankColorToken {
        switch score.status {
        case .correct: .correct
        case .partial: .partial
        case .incorrect: .wrong
        }
    }

    private var soft: QBankColorToken {
        switch score.status {
        case .correct: .correctSoft
        case .partial: .partialSoft
        case .incorrect: .wrongSoft
        }
    }

    private var border: QBankColorToken {
        switch score.status {
        case .correct: .correctBorder
        case .partial: .partialBorder
        case .incorrect: .wrongBorder
        }
    }
}

/// "I'm guessing · Flag for review": a guess stays in Review even when it was right.
private struct GuessToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 0) {
                Text("I'm guessing")
                    .qbankFont(.body)
                    .foregroundStyle(.qbank(.text1))
                Text("Flag for review")
                    .qbankFont(.caption1)
                    .foregroundStyle(.qbank(.text3))
            }
        }
        .toggleStyle(GuessToggleStyle())
        .accessibilityIdentifier("practice.guess")
    }
}

private struct GuessToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: QBankSpacing.space4) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(.qbank(configuration.isOn ? .guess : .surface))
                    .overlay {
                        if configuration.isOn {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.qbank(.textOnTint))
                        } else {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(.qbank(.separatorStrong), lineWidth: QBankBorder.emphasis)
                        }
                    }
                    .frame(width: 22, height: 22)
                configuration.label
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .frame(minHeight: QBankSpacing.rowMin)
            .background(.qbank(.guessSoft), in: .rect(cornerRadius: QBankRadius.sm, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: QBankRadius.sm, style: .continuous)
                    .strokeBorder(.qbank(.guessBorder), lineWidth: QBankBorder.hairline)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

/// After Check answer: the rationale with its images, the key takeaway, and the question's terms.
private struct RationaleSections: View {
    let question: Question

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: QBankSpacing.space1) {
                Kicker("Rationale")
                Prose(question.rationale)
                    .accessibilityIdentifier("practice.rationale")
                RationaleImages(question: question)
                    .padding(.top, QBankSpacing.space4)
            }
            VStack(alignment: .leading, spacing: QBankSpacing.space1) {
                Kicker("Key takeaway")
                Prose(question.takeaway)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, QBankSpacing.space5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.qbank(.tintSoft), in: .rect(cornerRadius: QBankRadius.sm, style: .continuous))
            if !question.terms.isEmpty {
                VStack(alignment: .leading, spacing: QBankSpacing.space1) {
                    Kicker("Terms in this question")
                    ForEach(Array(question.terms.enumerated()), id: \.offset) { offset, term in
                        VStack(alignment: .leading, spacing: QBankSpacing.space1) {
                            Text(term.term)
                                .qbankFont(.headline)
                                .foregroundStyle(.qbank(.text1))
                            Text(term.meaning)
                                .qbankFont(.subheadline)
                                .foregroundStyle(.qbank(.text2))
                        }
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .top) {
                            if offset > 0 {
                                Rectangle()
                                    .fill(.qbank(.separator))
                                    .frame(height: QBankBorder.hairline)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}

/// A small uppercase label over a section: "RATIONALE", "KEY TAKEAWAY".
struct Kicker: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .textCase(.uppercase)
            .qbankFont(.footnote, weight: .semibold, trackingEm: QBankTextStyle.capsTrackingEm)
            .foregroundStyle(.qbank(.text3))
            .accessibilityAddTraits(.isHeader)
    }
}

/// Rationale and takeaway text, in the smaller reading size.
struct Prose: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .qbankFont(.readingSmall)
            .foregroundStyle(.qbank(.text1))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
