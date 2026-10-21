import QBankDesign
import QBankKit
import SwiftUI

/// An exam page: its folders and sets, Start exam over them, its folders in her order, and the
/// exams she took over them. Edit puts the folders in order and offers the page's name and folders.
/// A topic's study page is the same screen, with its primer link when it has one.
struct ExamPageView: View {
    let app: AppModel
    let model: CourseModel
    let id: String
    /// A past or running exam she opened.
    @State private var exam: ExamRoute?
    /// Its folders in her order, while she edits it.
    @State private var order: [String]?
    @State private var isSavingOrder = false
    @State private var editsPage = false
    @State private var isRemoved = false
    @State private var problem: String?
    /// The past exam she asked to delete, while its warning is open.
    @State private var deleting: DeleteRequest?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            if let page = model.layout?.page(id) {
                content(page)
                    .screenColumn()
                    .padding(.bottom, QBankSpacing.space7)
            } else if model.course != nil, !isRemoved {
                // Removed elsewhere, such as on the web, while it was open here.
                EmptyCard(message: "This \(model.words.page) is not in the \(model.words.container) anymore. Its folders are under Folders.", systemImage: "square.stack.3d.up")
                    .screenColumn()
                    .padding(.top, QBankSpacing.space4)
            }
        }
        .qbankScreenBackground()
        .navigationTitle(model.layout?.page(id)?.exam.name ?? model.words.pageTitle)
        .screenColumnTitle()
        .refreshable { await model.load() }
        .onAppear {
            // Back from Exam setup or a folder: an exam she took shows under Past exams.
            Task { await model.load() }
        }
        .examCover(app: app, model: model, route: $exam) { dismiss() }
        .onChange(of: app.deletions.revision) {
            // A folder or exam deleted, or brought back with Undo while this page is open.
            Task { await model.load() }
        }
        .deleteSheet(app: app, request: $deleting)
        .sheet(isPresented: $editsPage, onDismiss: {
            // A removed page leaves once the sheet is down.
            order = nil
            if isRemoved { dismiss() }
        }, content: {
            if let course = model.course {
                EditExamPageView(app: app, course: course, pageID: id) { outcome in
                    Task { await model.load() }
                    isRemoved = outcome == .removed
                }
            }
        })
    }

    private func content(_ page: ExamPage) -> some View {
        VStack(alignment: .leading, spacing: QBankSpacing.space4) {
            Text(FolderWording.pageNote(page))
                .qbankFont(.subheadline)
                .foregroundStyle(.qbank(.text2))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("page.note")
            if let link = page.exam.linkURL {
                PrimerRow(address: link)
            }
            if let problem = problem ?? model.problem {
                ProblemText(text: problem)
            }
            if model.isStudent, let setup = model.examSetup(for: page), let draw = FolderWording.examDraw(page) {
                VStack(alignment: .leading, spacing: QBankSpacing.space2) {
                    NavigationLink(value: StudyRoute.exam(setup)) {
                        Label("Start exam", systemImage: "timer")
                    }
                    .buttonStyle(.qbank(.primary, size: .large, fullWidth: true))
                    .accessibilityIdentifier("page.startExam")
                    Text(draw)
                        .qbankFont(.footnote)
                        .foregroundStyle(.qbank(.text3))
                        .padding(.horizontal, QBankSpacing.space1)
                        .accessibilityIdentifier("page.draw")
                    if let twins = FolderWording.examTwins(page) {
                        Label {
                            QBankDetailText(twins)
                        } icon: {
                            Image(systemName: "timer")
                                .foregroundStyle(.qbank(.tint))
                                .accessibilityHidden(true)
                        }
                        .qbankFont(.footnote)
                        .foregroundStyle(.qbank(.text3))
                        .padding(.horizontal, QBankSpacing.space1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("page.twins")
                    }
                }
            }
            folders(page)
                .padding(.top, QBankSpacing.space3)
            sittings(page)
                .padding(.top, QBankSpacing.space3)
        }
    }

    private func folders(_ page: ExamPage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHead(
                title: "Study material",
                action: order == nil ? "Edit" : "Done",
                label: order == nil ? "Edit study material" : "Done, save folder order",
                identifier: "page.edit",
                isEnabled: !isSavingOrder && (order != nil || model.canEdit)
            ) {
                edit(page)
            }
            if order != nil {
                Button {
                    openEditor(page)
                } label: {
                    Label("Name and folders of \(page.exam.name)", systemImage: "pencil")
                }
                .buttonStyle(.qbank(.secondary, size: .medium, fullWidth: true))
                .disabled(isSavingOrder)
                .padding(.bottom, QBankSpacing.space2)
                .accessibilityIdentifier("page.editPage")
            }
            if page.folders.isEmpty {
                EmptyCard(message: "No folders on this page yet. Tap Edit to add some.", systemImage: "folder")
            } else {
                FolderList(folders: page.folders, order: $order)
                if order != nil, page.folders.count > 1 {
                    Text("Drag a folder by its grip, or use the arrows, to put them in your order.")
                        .qbankFont(.footnote)
                        .foregroundStyle(.qbank(.text3))
                        .padding(.horizontal, QBankSpacing.space5)
                }
            }
        }
    }

    @ViewBuilder
    private func sittings(_ page: ExamPage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHead(title: model.isStudent ? "Past exams" : "Her past exams")
            if page.sittings.isEmpty {
                EmptyCard(
                    message: model.isStudent
                        ? "Exams you finish over \(page.exam.name) show up here with their scores."
                        : "Her finished exams over \(page.exam.name) show up here with their scores.",
                    systemImage: "timer"
                )
            } else {
                QBankListGroup(footer: model.isStudent && model.canEdit ? "Touch and hold an exam to delete it." : nil) {
                    ForEach(page.sittings) { sitting in
                        Button {
                            exam = ExamRoute(id: sitting.id)
                        } label: {
                            PastExamRow(exam: sitting)
                        }
                        .buttonStyle(.qbankRow)
                        .deletable("exam", isEnabled: model.isStudent && model.canEdit && sitting.finishedAt != nil) {
                            deleting = DeleteRequest(target: .exam(id: sitting.id))
                        }
                        .accessibilityIdentifier("page.sitting.\(sitting.id)")
                    }
                }
            }
        }
    }

    /// The page's editor starts from its saved folders, so an order she changed is saved first. If
    /// that is refused, she reads why and the editor stays closed.
    private func openEditor(_ page: ExamPage) {
        guard let edited = order, edited != page.folders.map(\.id) else {
            editsPage = true
            return
        }
        isSavingOrder = true
        Task {
            problem = await model.saveOrder(page: page.id, folderIDs: edited)
            isSavingOrder = false
            if problem == nil {
                editsPage = true
            } else {
                order = nil
            }
        }
    }

    /// Edit puts the folders in order mode and offers the page's editor; Done saves her order when
    /// it changed.
    private func edit(_ page: ExamPage) {
        guard let edited = order else {
            problem = nil
            order = page.folders.map(\.id)
            return
        }
        guard edited != page.folders.map(\.id) else {
            order = nil
            return
        }
        isSavingOrder = true
        Task {
            problem = await model.saveOrder(page: page.id, folderIDs: edited)
            isSavingOrder = false
            order = nil
        }
    }
}

/// A study page's primer: the page where she wrote it up, opened in the browser. Nothing of it is
/// shown here but where it lives.
private struct PrimerRow: View {
    let address: String

    var body: some View {
        QBankListGroup {
            if let url = URL(string: address), url.host() != nil {
                Link(destination: url) {
                    row(detail: url.host() ?? address) {
                        Image(systemName: "arrow.up.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.qbank(.text4))
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.qbankRow)
                .accessibilityHint("Opens in Safari")
                .accessibilityIdentifier("page.primer")
            } else {
                row(detail: address) { EmptyView() }
                    .accessibilityIdentifier("page.primer")
            }
        }
    }

    private func row(detail: String, @ViewBuilder accessory: () -> some View) -> some View {
        QBankListRow("Open the primer", detail: detail, systemImage: "link", accessory: accessory)
    }
}
