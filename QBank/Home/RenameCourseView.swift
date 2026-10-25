import QBankDesign
import QBankKit
import SwiftUI

/// Rename, from holding a course or topic on Home: a course's code and name, or a topic's name.
/// Only the name changes; its folders, sets and her answers stay with it.
struct RenameCourseView: View {
    private enum Model {
        case course(CourseEditModel)
        case topic(TopicEditModel)
    }

    @State private var model: Model
    @FocusState private var focus: Field?
    @Environment(\.dismiss) private var dismiss

    private enum Field {
        case code
        case title
    }

    init(app: AppModel, catalog: Catalog?, course: CourseSummary) {
        let catalog = CatalogModel(app: app, catalog: catalog)
        _model = State(initialValue: course.kind == .topic
            ? .topic(TopicEditModel(catalog: catalog, id: course.id))
            : .course(CourseEditModel(catalog: catalog, id: course.id)))
    }

    var body: some View {
        Group {
            switch model {
            case .course(let course): courseSheet(course)
            case .topic(let topic): topicSheet(topic)
            }
        }
        .onAppear { focus = .title }
        .presentationDetents([.medium, .large])
    }

    private func courseSheet(_ course: CourseEditModel) -> some View {
        @Bindable var course = course
        return EditSheet(title: "Rename course", confirm: "Save", identifier: "renameCourse", isSaving: course.isSaving, hasChanges: course.hasChanges) {
            save { await course.save() } succeeded: { course.problem == nil }
        } content: {
            LabeledField(label: "Course code") {
                TextField("Course code", text: $course.code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focus, equals: .code)
                    .onSubmit { focus = .title }
                    .accessibilityIdentifier("renameCourse.code")
            }
            LabeledField(label: "Course name") {
                TextField("Course name", text: $course.title)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .focused($focus, equals: .title)
                    .accessibilityIdentifier("renameCourse.title")
            }
            if let problem = course.problem {
                ProblemText(text: problem)
            }
            SheetHint(text: "Only the name changes. Its folders, sets and your answers stay with it.")
        }
    }

    private func topicSheet(_ topic: TopicEditModel) -> some View {
        @Bindable var topic = topic
        return EditSheet(title: "Rename topic", confirm: "Save", identifier: "renameCourse", isSaving: topic.isSaving, hasChanges: topic.hasChanges) {
            save { await topic.save() } succeeded: { topic.problem == nil }
        } content: {
            LabeledField(label: "Topic name") {
                TextField("Topic name", text: $topic.title)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .focused($focus, equals: .title)
                    .accessibilityIdentifier("renameCourse.title")
            }
            if let problem = topic.problem {
                ProblemText(text: problem)
            }
            SheetHint(text: "Only the name changes. Its folders, pages, sets and your answers stay with it.")
        }
    }

    /// Saves, and closes once the server took it.
    private func save(_ work: @escaping () async -> Void, succeeded: @escaping () -> Bool) {
        focus = nil
        Task {
            await work()
            if succeeded() { dismiss() }
        }
    }
}
