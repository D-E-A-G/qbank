import QBankDesign
import QBankKit
import SwiftUI

/// Settings' Study topics, as the web's: her topics in her order, the archived ones last, each
/// opening its own screen to rename or archive it. Edit puts them in order; a new one needs only
/// its name.
struct TopicsGroup: View {
    let catalog: CatalogModel
    /// The topics she studies in her order, while she edits it.
    @State private var order: [String]?
    @State private var isSavingOrder = false
    @State private var newName = ""
    @FocusState private var naming: Bool

    var body: some View {
        let topics = catalog.topics
        let studied = topics.filter { $0.archivedAt == nil }
        VStack(alignment: .leading, spacing: QBankSpacing.space3) {
            VStack(alignment: .leading, spacing: 6) {
                SectionHead(
                    title: "Study topics",
                    action: order == nil ? "Edit" : "Done",
                    label: order == nil ? "Edit topic order" : "Done, save topic order",
                    identifier: "settings.topics.edit",
                    isEnabled: !isSavingOrder && (order != nil || studied.count > 1)
                ) {
                    editOrder(studied)
                }
                QBankListGroup(footer: order == nil
                    ? "Rename, reorder, archive or unarchive a topic. Topics can also be made from Home and Import."
                    : "Use the arrows to put your topics in your order. Archived topics stay last."
                ) {
                    if topics.isEmpty {
                        Text("No topics yet. Add one below.")
                            .qbankFont(.body)
                            .foregroundStyle(.qbank(.text3))
                            .frame(maxWidth: .infinity, minHeight: QBankSpacing.rowMin, alignment: .leading)
                            .padding(.horizontal, QBankSpacing.rowPaddingHorizontal)
                            .padding(.vertical, 11)
                    }
                    if let order {
                        ForEach(Array(order.enumerated()), id: \.element) { position, id in
                            if let topic = studied.first(where: { $0.id == id }) {
                                TopicOrderRow(topic: topic, canMoveUp: position > 0, canMoveDown: position < order.count - 1) { offset in
                                    move(id, by: offset)
                                }
                            }
                        }
                    } else {
                        ForEach(topics) { topic in
                            NavigationLink(value: SettingsRoute.topic(topic.id)) {
                                QBankListRow(topic.title, detail: CatalogModel.line(of: topic), showsChevron: true)
                            }
                            .buttonStyle(.qbankRow)
                            .accessibilityIdentifier("settings.topic.\(topic.title)")
                        }
                    }
                }
            }
            if let problem = catalog.topicProblem {
                ProblemText(text: problem)
                    .padding(.horizontal, QBankSpacing.space5)
            }
            if order == nil {
                addTopic
                    .padding(.top, QBankSpacing.space2)
            }
        }
    }

    private var addTopic: some View {
        VStack(alignment: .leading, spacing: QBankSpacing.space4) {
            LabeledField(label: "New topic name") {
                TextField("New topic name", text: $newName, prompt: Text("Spanish verbs").foregroundStyle(.qbank(.text4)))
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .focused($naming)
                    .onSubmit(add)
                    .accessibilityIdentifier("settings.newTopicName")
            }
            Button(action: add) {
                if catalog.isAddingTopic {
                    ProgressView().accessibilityLabel("Adding")
                } else {
                    Text("Add a topic")
                }
            }
            .buttonStyle(.qbank(.secondary, size: .large, fullWidth: true))
            .disabled(catalog.isAddingTopic)
            .accessibilityIdentifier("settings.addTopic")
        }
    }

    private func add() {
        naming = false
        Task {
            if await catalog.addTopic(named: newName) { newName = "" }
        }
    }

    /// Edit puts the list in order mode; Done saves her order when it changed.
    private func editOrder(_ studied: [CourseSummary]) {
        guard let edited = order else {
            order = studied.map(\.id)
            return
        }
        guard edited != studied.map(\.id) else {
            order = nil
            return
        }
        isSavingOrder = true
        Task {
            await catalog.saveTopicOrder(edited)
            isSavingOrder = false
            order = nil
        }
    }

    private func move(_ id: String, by offset: Int) {
        guard var current = order, let from = current.firstIndex(of: id) else { return }
        let to = from + offset
        guard current.indices.contains(to) else { return }
        withAnimation(QBankMotion.reveal) {
            current.swapAt(from, to)
            order = current
        }
    }
}

/// A topic while she puts the list in order: its name, and up and down buttons.
private struct TopicOrderRow: View {
    let topic: CourseSummary
    let canMoveUp: Bool
    let canMoveDown: Bool
    let move: (Int) -> Void

    var body: some View {
        HStack(spacing: QBankSpacing.space3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(topic.title)
                    .qbankFont(.body)
                    .foregroundStyle(.qbank(.text1))
                QBankDetailText(CatalogModel.line(of: topic))
                    .qbankFont(.footnote)
                    .foregroundStyle(.qbank(.text3))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            HStack(spacing: 0) {
                arrow("chevron.up", label: "Move \(topic.title) up", enabled: canMoveUp, identifier: "topicOrder.up.\(topic.title)") { move(-1) }
                arrow("chevron.down", label: "Move \(topic.title) down", enabled: canMoveDown, identifier: "topicOrder.down.\(topic.title)") { move(1) }
            }
        }
        .padding(.leading, QBankSpacing.rowPaddingHorizontal)
        .padding(.trailing, QBankSpacing.space2)
        .padding(.vertical, 6)
        .frame(minHeight: QBankSpacing.rowMin)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("topicOrder.\(topic.title)")
    }

    private func arrow(_ systemImage: String, label: String, enabled: Bool, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .foregroundStyle(.qbank(enabled ? .tint : .text4))
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

/// One study topic, with the web's fields: its name, and archiving by hand.
struct TopicEditView: View {
    @State private var model: TopicEditModel
    @FocusState private var naming: Bool

    init(catalog: CatalogModel, id: String) {
        _model = State(initialValue: TopicEditModel(catalog: catalog, id: id))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: QBankSpacing.space7) {
                VStack(alignment: .leading, spacing: QBankSpacing.space4) {
                    LabeledField(label: "Name") {
                        TextField("Name", text: $model.title)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .focused($naming)
                            .accessibilityIdentifier("topic.title")
                    }
                    if let problem = model.problem {
                        ProblemText(text: problem)
                    }
                    if let note = model.note {
                        SavedText(text: note)
                    }
                    Button {
                        naming = false
                        Task { await model.save() }
                    } label: {
                        if model.isSaving {
                            ProgressView()
                                .tint(QBankColor(.textOnTint))
                                .accessibilityLabel("Saving")
                        } else {
                            Text("Save \(model.topic?.title ?? "topic")")
                        }
                    }
                    .buttonStyle(.qbank(.primary, size: .large, fullWidth: true))
                    .disabled(model.isSaving || model.isArchiving)
                    .accessibilityIdentifier("topic.save")
                }
                QBankListGroup(footer: model.isArchived
                    ? "Unarchiving brings the topic back under Study topics on Home."
                    : "An archived topic moves to Archived, at the bottom of Home. Your answers in it stay."
                ) {
                    Button {
                        Task { await model.toggleArchived() }
                    } label: {
                        QBankListRow(
                            "\(model.isArchived ? "Unarchive" : "Archive") \(model.topic?.title ?? "topic")",
                            systemImage: model.isArchived ? "tray.and.arrow.up" : "archivebox"
                        ) {
                            if model.isArchiving {
                                ProgressView()
                            }
                        }
                    }
                    .buttonStyle(.qbankRow)
                    .disabled(model.isSaving || model.isArchiving)
                    .accessibilityIdentifier("topic.archive")
                }
            }
            .screenColumn()
            .padding(.top, QBankSpacing.space3)
            .padding(.bottom, QBankSpacing.space7)
        }
        .scrollDismissesKeyboard(.interactively)
        .qbankScreenBackground()
        .navigationTitle(model.topic?.title ?? "Topic")
        .screenColumnTitle()
    }
}
