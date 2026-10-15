import QBankDesign
import QBankKit
import SwiftUI

/// One semester, with the web's fields: its name and dates, its courses, and adding a course.
struct SemesterView: View {
    @State private var model: SemesterModel
    @FocusState private var focus: Field?

    private enum Field {
        case name
        case code
        case title
    }

    init(catalog: CatalogModel, id: String) {
        _model = State(initialValue: SemesterModel(catalog: catalog, id: id))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: QBankSpacing.space7) {
                details
                courses
                addCourse
            }
            .screenColumn()
            .padding(.top, QBankSpacing.space3)
            .padding(.bottom, QBankSpacing.space7)
        }
        .scrollDismissesKeyboard(.interactively)
        .qbankScreenBackground()
        .navigationTitle(model.semester?.name ?? "Semester")
        .screenColumnTitle()
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: QBankSpacing.space4) {
            LabeledField(label: "Name") {
                TextField("Name", text: $model.name)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .focused($focus, equals: .name)
                    .accessibilityIdentifier("semester.name")
            }
            QBankListGroup {
                DayRow(title: "Starts", day: $model.startsOn, identifier: "semester.starts")
                DayRow(title: "Ends", day: $model.endsOn, identifier: "semester.ends")
            }
            if let problem = model.saveProblem {
                ProblemText(text: problem)
            }
            if model.isSaved {
                SavedText(text: "Saved.")
            }
            Button {
                focus = nil
                Task { await model.save() }
            } label: {
                if model.isSaving {
                    ProgressView().accessibilityLabel("Saving")
                } else {
                    Text("Save \(model.semester?.name ?? "semester")")
                }
            }
            .buttonStyle(.qbank(.secondary, size: .large, fullWidth: true))
            .disabled(model.isSaving)
            .accessibilityIdentifier("semester.save")
        }
    }

    private var courses: some View {
        QBankListGroup(header: "Courses", footer: "Open a course to rename it, move it to another semester, or archive it.") {
            let courses = model.semester.map(CatalogModel.courses(in:)) ?? []
            if courses.isEmpty {
                Text("No courses yet. Add one below.")
                    .qbankFont(.body)
                    .foregroundStyle(.qbank(.text3))
                    .frame(maxWidth: .infinity, minHeight: QBankSpacing.rowMin, alignment: .leading)
                    .padding(.horizontal, QBankSpacing.rowPaddingHorizontal)
                    .padding(.vertical, 11)
            }
            ForEach(courses) { course in
                NavigationLink(value: SettingsRoute.course(course.id)) {
                    QBankListRow(
                        course.code,
                        detail: course.archivedAt == nil ? course.title : "\(course.title) · Archived",
                        showsChevron: true
                    )
                }
                .buttonStyle(.qbankRow)
                .accessibilityIdentifier("semester.course.\(course.code)")
            }
        }
    }

    private var addCourse: some View {
        VStack(alignment: .leading, spacing: QBankSpacing.space4) {
            QBankSectionHeader("Add a course")
                .padding(.horizontal, QBankSpacing.space5)
                .padding(.bottom, -6)
            LabeledField(label: "Course code") {
                TextField("Course code", text: $model.newCode, prompt: Text("NURS 406").foregroundStyle(.qbank(.text4)))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focus, equals: .code)
                    .onSubmit { focus = .title }
                    .accessibilityIdentifier("semester.newCode")
            }
            LabeledField(label: "Course name") {
                TextField("Course name", text: $model.newTitle, prompt: Text("Mental Health").foregroundStyle(.qbank(.text4)))
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .focused($focus, equals: .title)
                    .onSubmit(addCourseNow)
                    .accessibilityIdentifier("semester.newTitle")
            }
            if let problem = model.addProblem {
                ProblemText(text: problem)
            }
            Button(action: addCourseNow) {
                if model.isAddingCourse {
                    ProgressView().accessibilityLabel("Adding")
                } else {
                    Text("Add a course to \(model.semester?.name ?? "this semester")")
                }
            }
            .buttonStyle(.qbank(.secondary, size: .large, fullWidth: true))
            .disabled(model.isAddingCourse)
            .accessibilityIdentifier("semester.addCourse")
        }
    }

    private func addCourseNow() {
        focus = nil
        Task { await model.addCourse() }
    }
}

/// A list row for an optional calendar date: the date with a way to clear it, or "Add date".
/// Either way the row keeps the list's 44pt height.
struct DayRow: View {
    let title: String
    @Binding var day: Date?
    let identifier: String

    var body: some View {
        if let day {
            QBankListRow(title, accessibilityChildren: .contain) {
                HStack(spacing: 0) {
                    DatePicker(
                        title,
                        selection: Binding(get: { day }, set: { self.day = $0 }),
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .accessibilityIdentifier("\(identifier).date")
                    Button {
                        self.day = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.qbank(.text4))
                            .frame(width: QBankSpacing.rowMin, height: QBankSpacing.rowMin)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(title): clear the date")
                    .accessibilityIdentifier("\(identifier).clear")
                }
                // The picker and the 44pt clear button reach into the row's own padding, so the
                // row is no taller than the others.
                .padding(.vertical, -11)
                .padding(.trailing, -QBankSpacing.space4)
            }
        } else {
            Button {
                day = Calendar.current.startOfDay(for: .now)
            } label: {
                QBankListRow(title) {
                    Text("Add date")
                        .qbankFont(.body)
                        .foregroundStyle(.qbank(.tint))
                }
            }
            .buttonStyle(.qbankRow)
            .accessibilityLabel("\(title): add a date")
            .accessibilityIdentifier("\(identifier).add")
        }
    }
}
