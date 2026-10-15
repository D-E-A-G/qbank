import QBankDesign
import QBankKit
import SwiftUI

/// A folder: which exam page it is on and how far she is, Rename and Exam page, its sets, and its
/// exam line. Select puts a check circle on each set and a Move bar at the bottom, as Files does.
struct FolderView: View {
    let app: AppModel
    let model: CourseModel
    let id: String
    /// The set she is practicing, shown full screen over the tabs.
    @State private var practicing: PracticeRoute?
    /// The sets she ticked, while she selects.
    @State private var selection: Set<String>?
    @State private var sheet: Sheet?
    @Environment(TabNavigator.self) private var tabs: TabNavigator?

    private enum Sheet: Identifiable {
        case rename
        case page
        case move([PracticeSetSummary])
        case importHere

        var id: String {
            switch self {
            case .rename: "rename"
            case .page: "page"
            case .move: "move"
            case .importHere: "import"
            }
        }
    }

    var body: some View {
        ScrollView {
            if let folder = model.folder(id) {
                content(folder)
                    .screenColumn()
                    .padding(.bottom, QBankSpacing.space7)
            } else if model.course != nil {
                // Removed elsewhere, such as on the web, while it was open here.
                EmptyCard(message: "This folder is not in the course anymore.", systemImage: "folder")
                    .screenColumn()
                    .padding(.top, QBankSpacing.space4)
            }
        }
        .qbankScreenBackground()
        .navigationTitle(model.folder(id)?.name ?? "Folder")
        .screenColumnTitle()
        .refreshable { await model.load() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let selection, !selection.isEmpty, let folder = model.folder(id) {
                MoveBar(count: selection.count) {
                    sheet = .move(folder.sets.filter { selection.contains($0.id) })
                }
            }
        }
        .practiceCover(app: app, model: model, route: $practicing)
        .sheet(item: $sheet, onDismiss: { Task { await model.load() } }, content: { sheet in
            if let folder = model.folder(id) {
                switch sheet {
                case .rename:
                    RenameFolderSheet(model: model, folder: folder)
                case .page:
                    ExamPageSheet(model: model, folder: folder)
                case .move(let sets):
                    MoveSetsSheet(model: model, folder: folder, sets: sets) {
                        selection = nil
                    }
                case .importHere:
                    ImportHereSheet(app: app, courseID: model.id, folderID: folder.id) { set in
                        self.sheet = nil
                        Task { await model.load() }
                        // A replaced set stays in its own folder, which may be another one.
                        if set.folderID != id {
                            tabs?.openFolder(courseID: set.courseID, code: set.courseCode, folderID: set.folderID)
                        }
                    }
                }
            }
        })
        .onChange(of: model.folder(id)?.sets.map(\.id)) { _, sets in
            // Sets that left the folder leave the selection, and with none left, selecting ends.
            guard let sets, let current = selection else { return }
            selection = sets.isEmpty ? nil : current.intersection(sets)
        }
    }

    private func content(_ folder: Folder) -> some View {
        VStack(alignment: .leading, spacing: QBankSpacing.space4) {
            Text(FolderWording.folderNote(folder, page: model.page(of: folder)))
                .qbankFont(.subheadline)
                .foregroundStyle(.qbank(.text2))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("folder.note")
            if model.savedAt != nil {
                OfflineBanner.showingSaved(phoneIsOnline: app.connection.isOnline)
            }
            if let problem = model.problem {
                ProblemText(text: problem)
            }
            // The buttons keep their words on one line and wrap as a row when they do not fit.
            FlowLayout(spacing: QBankSpacing.space2, lineSpacing: QBankSpacing.space2) {
                Button {
                    sheet = .rename
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                .accessibilityIdentifier("folder.rename")
                Button {
                    sheet = .page
                } label: {
                    Label(model.page(of: folder)?.name ?? "Exam page", systemImage: "square.stack.3d.up")
                }
                .accessibilityLabel("Exam page: \(model.page(of: folder)?.name ?? "none")")
                .accessibilityIdentifier("folder.page")
                Button {
                    sheet = .importHere
                } label: {
                    Label("Import here", systemImage: "square.and.arrow.down")
                }
                .accessibilityIdentifier("folder.import")
            }
            .buttonStyle(.qbank(.secondary, size: .small))
            .disabled(!model.canEdit || selection != nil)
            sets(folder)
                .padding(.top, QBankSpacing.space3)
        }
    }

    private func sets(_ folder: Folder) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHead(
                title: "Sets",
                action: selection != nil ? "Cancel" : folder.sets.isEmpty ? nil : "Select",
                label: selection != nil ? "Cancel selecting" : "Select sets",
                identifier: "folder.select",
                isEnabled: selection != nil || model.canEdit
            ) {
                selection = selection == nil ? [] : nil
            }
            if folder.sets.isEmpty, folder.examBankCount == 0 {
                EmptyCard(message: "No sets yet. Move sets here from another folder.", systemImage: "folder")
            } else {
                QBankListGroup {
                    ForEach(folder.sets) { set in
                        if let selection {
                            SelectRow(set: set, isSelected: selection.contains(set.id)) {
                                toggle(set)
                            }
                        } else {
                            SetRow(set: set, isRestoring: model.isRestoring, isStudent: model.isStudent) {
                                practicing = PracticeRoute(source: .set(id: set.id), courseID: model.id, title: set.title)
                            } restore: {
                                Task { await model.restore(set) }
                            }
                        }
                    }
                    ExamBankLine(folder: folder)
                }
            }
        }
    }

    private func toggle(_ set: PracticeSetSummary) {
        guard var current = selection else { return }
        if current.contains(set.id) {
            current.remove(set.id)
        } else {
            current.insert(set.id)
        }
        selection = current
    }
}

/// The bar at the bottom while sets are ticked: Move N sets.
private struct MoveBar: View {
    let count: Int
    let move: () -> Void

    var body: some View {
        Button(action: move) {
            Label("Move \(Wording.count(count, "set"))", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
        }
        .buttonStyle(.qbank(.primary, size: .large, fullWidth: true))
        .screenColumn()
        .padding(.vertical, QBankSpacing.space3)
        .background(.qbank(.bg))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.qbank(.separator))
                .frame(height: QBankBorder.hairline)
        }
        .accessibilityIdentifier("folder.move")
    }
}

/// A set while she selects: a check circle, its title and how far she got.
private struct SelectRow: View {
    let set: PracticeSetSummary
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: QBankSpacing.space4) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(.qbank(isSelected ? .tint : .separatorStrong))
                    .accessibilityHidden(true)
                SetText(set: set)
            }
            .padding(.horizontal, QBankSpacing.rowPaddingHorizontal)
            .padding(.vertical, 10)
            .frame(minHeight: QBankSpacing.rowMin)
            .contentShape(.rect)
        }
        .buttonStyle(.qbankRow)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("folder.pick.\(set.title)")
    }
}

/// A practice set in its folder: its title and how far she got. A replaced set offers its previous
/// version back, with Restore beside the row rather than inside it, so each is its own button.
/// Restore asks first.
private struct SetRow: View {
    let set: PracticeSetSummary
    let isRestoring: Bool
    let isStudent: Bool
    let open: () -> Void
    let restore: () -> Void
    @State private var asksToRestore = false

    var body: some View {
        HStack(spacing: 0) {
            if isStudent {
                Button(action: open) {
                    label(showsChevron: !set.canRestore)
                }
                .buttonStyle(.qbankRow)
                .accessibilityIdentifier("course.set.\(set.title)")
            } else {
                label(showsChevron: false)
            }
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

    private func label(showsChevron: Bool) -> some View {
        HStack(spacing: QBankSpacing.space4) {
            SetText(set: set)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.qbank(.text4))
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, QBankSpacing.rowPaddingHorizontal)
        .padding(.vertical, 10)
        .frame(minHeight: QBankSpacing.rowMin)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// A set's title and status line, as the web's folder rows set them: callout over subhead.
private struct SetText: View {
    let set: PracticeSetSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(set.title)
                .qbankFont(.callout, weight: .semibold)
                .foregroundStyle(.qbank(.text1))
                .multilineTextAlignment(.leading)
            QBankDetailText(Wording.status(set))
                .qbankFont(.subheadline)
                .foregroundStyle(.qbank(.text2))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The folder's exam line under its sets: its exam bank, or that its exams use practice questions.
private struct ExamBankLine: View {
    let folder: Folder

    var body: some View {
        Label {
            QBankDetailText(FolderWording.examBank(folder))
        } icon: {
            Image(systemName: "timer")
                .foregroundStyle(.qbank(folder.examBankCount > 0 ? .tint : .text3))
        }
        .qbankFont(.footnote)
        .foregroundStyle(.qbank(.text3))
        .padding(.horizontal, QBankSpacing.rowPaddingHorizontal)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("folder.bank")
    }
}
