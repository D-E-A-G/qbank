import QBankDesign
import QBankKit
import SwiftUI

/// The exam page editor, as a sheet: Cancel, New exam page or Edit Exam 2, Done; the page's name,
/// the course's folders as chips, and how many questions its folders hold. A page that exists can
/// be removed here; its folders go back under Folders.
struct EditExamPageView: View {
    @State private var model: EditExamPageModel
    @FocusState private var naming: Bool
    @Environment(\.dismiss) private var dismiss
    /// Called when the sheet closes, with how.
    let finished: (EditExamPageModel.Outcome) -> Void

    init(app: AppModel, course: CourseDetail, pageID: String?, finished: @escaping (EditExamPageModel.Outcome) -> Void) {
        _model = State(initialValue: EditExamPageModel(app: app, course: course, pageID: pageID))
        self.finished = finished
    }

    var body: some View {
        EditSheet(
            title: model.isNew ? "New exam page" : "Edit \(model.name.isEmpty ? "exam page" : model.name)",
            confirm: "Done",
            identifier: "editPage",
            isSaving: model.isSaving,
            hasChanges: model.hasChanges,
            save: save
        ) {
            if let problem = model.problem {
                ProblemText(text: problem)
            }
            card
            SheetHint(text: "Tap the folders on this page. A folder on another page is greyed and says which.")
            if !model.isNew {
                Button("Remove this exam page", role: .destructive) {
                    Task { if let outcome = await model.remove() { close(outcome) } }
                }
                .buttonStyle(.qbank(.destructive, size: .large, fullWidth: true))
                .disabled(model.isSaving)
                .padding(.top, QBankSpacing.space3)
                .accessibilityIdentifier("editPage.remove")
                SheetHint(text: "Its folders go back under Folders. No set moves.")
            }
        }
    }

    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: QBankRadius.md, style: .continuous)
        return VStack(alignment: .leading, spacing: QBankSpacing.space3) {
            TextField("Exam page name", text: $model.name)
                .qbankFont(.body)
                .foregroundStyle(.qbank(.text1))
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .focused($naming)
                .padding(.horizontal, QBankSpacing.space4)
                .frame(minHeight: QBankButtonStyle.Size.medium.minHeight)
                .background(.qbank(.surfaceSunken), in: .rect(cornerRadius: QBankRadius.sm, style: .continuous))
                .accessibilityLabel("Exam page name")
                .accessibilityIdentifier("editPage.name")
            if model.chips.isEmpty {
                Text("This course has no folders yet.")
                    .qbankFont(.subheadline)
                    .foregroundStyle(.qbank(.text2))
            } else {
                FlowLayout(spacing: QBankSpacing.space2, lineSpacing: QBankSpacing.space2) {
                    ForEach(model.chips) { chip in
                        FolderChip(name: chip.folder.name, isOn: model.isPicked(chip), holder: chip.heldBy) {
                            model.toggle(chip)
                        }
                        .accessibilityIdentifier("editPage.chip.\(chip.heldBy ?? "free").\(chip.folder.name)")
                    }
                }
            }
            Text(model.line)
                .qbankFont(.footnote)
                .foregroundStyle(.qbank(.text3))
                .accessibilityIdentifier("editPage.line")
        }
        .padding(QBankSpacing.space4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(.qbank(.surface)))
        .overlay(shape.strokeBorder(.qbank(.separator), lineWidth: QBankBorder.regular))
        .disabled(model.isSaving)
    }

    private func save() {
        naming = false
        Task {
            if let outcome = await model.save() { close(outcome) }
        }
    }

    private func close(_ outcome: EditExamPageModel.Outcome) {
        finished(outcome)
        dismiss()
    }
}

/// A folder as a chip: on this page (tinted), free (plain), or on another page (greyed, with that
/// page's name, and not tappable).
private struct FolderChip: View {
    let name: String
    let isOn: Bool
    let holder: String?
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                Text(name)
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
        .accessibilityLabel(holder.map { "\(name), on \($0)" } ?? name)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
