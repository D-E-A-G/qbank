import QBankDesign
import QBankKit
import SwiftUI

/// One course, with the web's fields: its code and name, its semester, and archiving.
struct CourseEditView: View {
    @State private var model: CourseEditModel
    @FocusState private var focus: Field?

    private enum Field {
        case code
        case title
    }

    init(catalog: CatalogModel, id: String) {
        _model = State(initialValue: CourseEditModel(catalog: catalog, id: id))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: QBankSpacing.space7) {
                VStack(alignment: .leading, spacing: QBankSpacing.space4) {
                    LabeledField(label: "Code") {
                        TextField("Code", text: $model.code)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .submitLabel(.next)
                            .focused($focus, equals: .code)
                            .onSubmit { focus = .title }
                            .accessibilityIdentifier("course.code")
                    }
                    LabeledField(label: "Name") {
                        TextField("Name", text: $model.title)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .focused($focus, equals: .title)
                            .accessibilityIdentifier("course.title")
                    }
                }
                QBankListGroup(header: "Semester") {
                    ForEach(model.catalog.semesters ?? []) { semester in
                        Button {
                            model.semesterID = semester.id
                        } label: {
                            QBankListRow(semester.name, isSelected: semester.id == model.semesterID) {
                                if semester.id == model.semesterID {
                                    Image(systemName: "checkmark")
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.qbank(.tint))
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                        .buttonStyle(.qbankRow)
                        .accessibilityIdentifier("course.semester.\(semester.number)")
                    }
                }
                VStack(alignment: .leading, spacing: QBankSpacing.space4) {
                    if let problem = model.problem {
                        ProblemText(text: problem)
                    }
                    if let note = model.note {
                        SavedText(text: note)
                    }
                    Button {
                        focus = nil
                        Task { await model.save() }
                    } label: {
                        if model.isSaving {
                            ProgressView()
                                .tint(QBankColor(.textOnTint))
                                .accessibilityLabel("Saving")
                        } else {
                            Text("Save \(model.course?.code ?? "course")")
                        }
                    }
                    .buttonStyle(.qbank(.primary, size: .large, fullWidth: true))
                    .disabled(model.isSaving || model.isArchiving)
                    .accessibilityIdentifier("course.save")
                }
                QBankListGroup(footer: model.isArchived
                    ? "Unarchiving brings the course back to Home."
                    : "An archived course leaves Home. Your answers in it stay."
                ) {
                    Button {
                        Task { await model.toggleArchived() }
                    } label: {
                        QBankListRow(
                            "\(model.isArchived ? "Unarchive" : "Archive") \(model.course?.code ?? "course")",
                            systemImage: model.isArchived ? "tray.and.arrow.up" : "archivebox"
                        ) {
                            if model.isArchiving {
                                ProgressView()
                            }
                        }
                    }
                    .buttonStyle(.qbankRow)
                    .disabled(model.isSaving || model.isArchiving)
                    .accessibilityIdentifier("course.archive")
                }
            }
            .screenColumn()
            .padding(.top, QBankSpacing.space3)
            .padding(.bottom, QBankSpacing.space7)
        }
        .scrollDismissesKeyboard(.interactively)
        .qbankScreenBackground()
        .navigationTitle(model.course?.code ?? "Course")
        .screenColumnTitle()
    }
}
