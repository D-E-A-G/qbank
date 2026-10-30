import Foundation
import Observation
import QBankDesign
import QBankKit
import SwiftUI

/// New topic, from Home: a name, nothing else. The server refuses a name another of her topics
/// has, in its words.
@Observable
final class NewTopicModel {
    var name = ""
    private(set) var isSaving = false
    private(set) var problem: String?

    private let app: AppModel

    init(app: AppModel) {
        self.app = app
    }

    /// Makes the topic. Returns it, or nil after a refusal, which `problem` says.
    func save() async -> CourseSummary? {
        guard !isSaving else { return nil }
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            problem = "Give the topic a name."
            return nil
        }
        isSaving = true
        problem = nil
        defer { isSaving = false }
        do {
            return try await app.client.createTopic(title: title)
        } catch {
            if !app.handle(error) {
                problem = Wording.problem(error) ?? "Could not make the topic."
            }
            return nil
        }
    }
}

/// The New topic sheet: Cancel, New topic, Done, and the topic's name. Once made, `made` runs
/// before the sheet goes down, so the topic can open after it.
struct NewTopicView: View {
    @State private var model: NewTopicModel
    /// The topic is made and Home reads its list again before the sheet goes down.
    @State private var isOpening = false
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss
    let made: (CourseSummary) async -> Void

    init(app: AppModel, made: @escaping (CourseSummary) async -> Void) {
        _model = State(initialValue: NewTopicModel(app: app))
        self.made = made
    }

    var body: some View {
        EditSheet(title: "New topic", confirm: "Done", identifier: "newTopic", isSaving: model.isSaving || isOpening, hasChanges: !model.name.isEmpty, save: save) {
            LabeledField(label: "Topic name") {
                TextField("Topic name", text: $model.name)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .focused($focused)
                    .onSubmit(save)
                    .accessibilityIdentifier("newTopic.name")
            }
            if let problem = model.problem {
                ProblemText(text: problem)
            }
            SheetHint(text: "A topic has folders and pages, like a course, without a semester.")
        }
        .onAppear { focused = true }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        guard !isOpening else { return }
        Task {
            guard let topic = await model.save() else { return }
            isOpening = true
            await made(topic)
            dismiss()
        }
    }
}
