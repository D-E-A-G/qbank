import QBankDesign
import QBankKit
import SwiftUI

/// Edit exams, as a sheet over the course: Cancel, Exams, Done; a card per exam with its name,
/// the course's weeks as chips, and how many questions its weeks hold; Add exam.
struct EditExamsView: View {
    @State private var model: EditExamsModel
    @Environment(\.dismiss) private var dismiss
    /// Called when the sheet closes, with whether anything was saved.
    let finished: (Bool) -> Void

    init(app: AppModel, course: CourseDetail, finished: @escaping (Bool) -> Void) {
        _model = State(initialValue: EditExamsModel(app: app, course: course))
        self.finished = finished
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: QBankSpacing.space4) {
                    Text("Name each exam and tap the weeks it covers. A week can be in one exam.")
                        .qbankFont(.footnote)
                        .foregroundStyle(.qbank(.text2))
                    if let problem = model.problem {
                        ProblemText(text: problem)
                    }
                    ForEach(Array(model.drafts.enumerated()), id: \.element.id) { position, draft in
                        ExamCard(model: model, draft: draft, position: position)
                    }
                    Button {
                        withAnimation(QBankMotion.reveal) { model.addExam() }
                    } label: {
                        Label("Add exam", systemImage: "plus")
                    }
                    .buttonStyle(.qbank(.secondary, size: .large, fullWidth: true))
                    .disabled(model.isSaving)
                    .accessibilityIdentifier("editExams.add")
                }
                .padding(.horizontal, QBankSpacing.gutterPhone)
                .padding(.top, QBankSpacing.space2)
                .padding(.bottom, QBankSpacing.space7)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(.qbank(.surface), ignoresSafeAreaEdges: .all)
            .navigationTitle("Exams")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { close(saved: model.savedSome) }
                        .disabled(model.isSaving)
                        .accessibilityIdentifier("editExams.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    if model.isSaving {
                        ProgressView()
                    } else {
                        Button("Done") {
                            Task {
                                guard await model.save() else { return }
                                close(saved: model.savedSome)
                            }
                        }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("editExams.done")
                    }
                }
            }
        }
        .interactiveDismissDisabled(model.hasChanges || model.isSaving)
    }

    private func close(saved: Bool) {
        finished(saved)
        dismiss()
    }
}

/// One exam: its name, a remove button, every week as a chip, and its weeks and questions.
private struct ExamCard: View {
    let model: EditExamsModel
    let draft: EditExamsModel.Draft
    /// Its place among the cards, for UI tests: the name changes as she types.
    let position: Int

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: QBankRadius.md, style: .continuous)
        VStack(alignment: .leading, spacing: QBankSpacing.space3) {
                HStack(spacing: QBankSpacing.space2) {
                    TextField("Exam name", text: Binding(get: { draft.name }, set: { model.rename(draft, to: $0) }))
                        .qbankFont(.body)
                        .foregroundStyle(.qbank(.text1))
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .padding(.horizontal, QBankSpacing.space4)
                        .frame(minHeight: QBankButtonStyle.Size.medium.minHeight)
                        .background(.qbank(.surfaceSunken), in: .rect(cornerRadius: QBankRadius.sm, style: .continuous))
                        .accessibilityLabel("Exam name")
                        .accessibilityIdentifier("editExams.name.\(position)")
                    Button {
                        withAnimation(QBankMotion.reveal) { model.remove(draft) }
                    } label: {
                        Image(systemName: "trash")
                            .font(.body)
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .foregroundStyle(.qbank(.text3))
                    .accessibilityLabel("Remove \(draft.name)")
                    .accessibilityIdentifier("editExams.remove.\(position)")
                }
                FlowLayout(spacing: QBankSpacing.space2, lineSpacing: QBankSpacing.space2) {
                    ForEach(model.weekLabels, id: \.self) { week in
                        WeekChip(
                            week: week,
                            isOn: draft.weeks.contains(week),
                            holder: model.holder(of: week, besides: draft)?.name
                        ) {
                            model.toggle(week, in: draft)
                        }
                        .accessibilityIdentifier("editExams.chip.\(position).\(week)")
                    }
                }
                Text(model.line(draft))
                    .qbankFont(.footnote)
                    .foregroundStyle(.qbank(.text3))
        }
        .padding(QBankSpacing.space4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(.qbank(.surface)))
        .overlay(shape.strokeBorder(.qbank(.separator), lineWidth: QBankBorder.regular))
        .disabled(model.isSaving)
    }
}

/// A week as a chip: in this exam (tinted), free (plain), or held by another exam (greyed, with that
/// exam's name, and not tappable).
private struct WeekChip: View {
    let week: String
    let isOn: Bool
    let holder: String?
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                Text(week)
                    .qbankFont(.subheadline, weight: isOn ? .semibold : .medium)
                if let holder {
                    Text(holder)
                        .qbankFont(.caption1)
                }
            }
            .foregroundStyle(.qbank(isOn ? .tint : holder == nil ? .text1 : .text4))
            .padding(.horizontal, 14)
            .frame(minHeight: 34)
            .background {
                Capsule().fill(.qbank(isOn ? .tintSoft : .surfaceSunken))
            }
            .overlay {
                if isOn {
                    Capsule().strokeBorder(.qbank(.tintSoftBorder), lineWidth: QBankBorder.regular)
                }
            }
            .padding(.vertical, 5)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(holder != nil)
        .accessibilityLabel(holder.map { "\(week), in \($0)" } ?? week)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
