import QBankDesign
import QBankKit
import SwiftUI

/// A course: score line, the Exam, Review and Terms tiles, then two lists, as the iPhone Files app
/// lists things: her exam pages, and the folders on no exam page. Each exam page and each folder
/// opens as its own screen, sharing this screen's model. A study topic is the same screen, called
/// by its name, with study pages for exam pages; `Wording.words(_:)` picks what differs.
struct CourseView: View {
    let app: AppModel
    let route: CourseRoute
    @State private var model: CourseModel
    /// A new exam page she is making, and once made, its id.
    @State private var makesPage = false
    @State private var madePage: String?
    /// The folders on no exam page in her order, while she edits it.
    @State private var order: [String]?
    @State private var isSavingOrder = false
    /// Why her order was not saved, in the server's words.
    @State private var orderProblem: String?
    @Environment(HomeNavigator.self) private var navigator: HomeNavigator?

    init(app: AppModel, route: CourseRoute) {
        self.app = app
        self.route = route
        _model = State(initialValue: CourseModel(app: app, id: route.id))
    }

    var body: some View {
        ScrollView {
            content
                .screenColumn()
                .padding(.bottom, QBankSpacing.space7)
        }
        .qbankScreenBackground()
        .navigationTitle(model.course.map(Wording.name) ?? route.name ?? "Course")
        .screenColumnTitle()
        .refreshable { await model.load() }
        .reloadsWithConnection(app) { await model.load() }
        .task {
            async let place: Void = model.rememberPlace()
            await model.load()
            await place
        }
        .onAppear {
            // Back from Review, Terms or an exam: its counts may have changed.
            guard model.course != nil else { return }
            Task { await model.load() }
        }
        .onChange(of: app.deletions.revision) {
            // Deleted or brought back on one of its screens, or with Undo: its lists change.
            Task { await model.load() }
        }
        .onChange(of: model.course) { old, _ in
            // On iPad the courses stay beside this one, and their card shows these counts too.
            if old != nil {
                navigator?.courseChanged()
            }
        }
        .navigationDestination(for: CoursePage.self) { page in
            switch page {
            case .examPage(let id): ExamPageView(app: app, model: model, id: id)
            case .folder(let id): FolderView(app: app, model: model, id: id)
            case .recentlyDeleted: RecentlyDeletedView(app: app, courseID: model.id)
            }
        }
        .sheet(isPresented: $makesPage, onDismiss: {
            // A new page opens once the sheet is down.
            guard let id = madePage else { return }
            madePage = nil
            navigator?.open(CoursePage.examPage(id))
        }, content: {
            if let course = model.course {
                EditExamPageView(app: app, course: course, pageID: nil) { outcome in
                    Task { await model.load() }
                    if case .saved(let id) = outcome { madePage = id }
                }
            }
        })
    }

    @ViewBuilder
    private var content: some View {
        if let course = model.course, let ref = model.ref, let layout = model.layout {
            VStack(alignment: .leading, spacing: QBankSpacing.space4) {
                summary(course)
                if model.savedAt != nil {
                    OfflineBanner.showingSaved(phoneIsOnline: app.connection.isOnline)
                        .accessibilityIdentifier("course.offline")
                }
                if let problem = orderProblem ?? model.problem {
                    ProblemText(text: problem)
                }
                tiles(course, ref: ref)
                if course.folders.isEmpty, layout.pages.isEmpty {
                    EmptyCard(message: "This \(model.words.container) has no question sets yet.")
                        .padding(.top, QBankSpacing.space3)
                } else {
                    examPages(layout)
                        .padding(.top, QBankSpacing.space3)
                    if !layout.looseFolders.isEmpty {
                        folders(layout)
                            .padding(.top, QBankSpacing.space3)
                    }
                }
                recentlyDeleted
                    .padding(.top, QBankSpacing.space3)
            }
        } else if let problem = model.problem {
            LoadFailed(problem: problem) {
                Task { await model.load() }
            }
        } else {
            Loading(title: "Loading the \(Wording.words(route.kind).container)")
        }
    }

    private func summary(_ course: CourseDetail) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Wording.summary(course))
            if let score = Wording.score(course) {
                Text(score)
            }
        }
        .qbankFont(.subheadline)
        .foregroundStyle(.qbank(.text2))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("course.summary")
    }

    private func tiles(_ course: CourseDetail, ref: CourseRef) -> some View {
        HStack(spacing: QBankSpacing.space3) {
            NavigationLink(value: StudyRoute.exam(ExamSetupRoute(course: ref))) {
                Tile(systemImage: "timer", value: "Exam", label: Wording.examLength(questionCount: course.examQuestionCount))
            }
            .accessibilityIdentifier("course.tile.exam")
            NavigationLink(value: StudyRoute.review(ref)) {
                Tile(systemImage: "tray", value: "\(course.reviewCount)", label: "to review")
            }
            .accessibilityIdentifier("course.tile.review")
            NavigationLink(value: StudyRoute.terms(ref)) {
                Tile(systemImage: "book", value: "\(course.termCount)", label: course.termCount == 1 ? "term" : "terms")
            }
            .accessibilityIdentifier("course.tile.terms")
        }
        .buttonStyle(QBankCardButtonStyle(padding: QBankSpacing.space4))
    }

    private func examPages(_ layout: CourseLayout) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            let words = model.words
            SectionHead(title: words.pages, action: "New", label: "New \(words.page)", identifier: "course.newPage", isEnabled: model.canEdit && order == nil) {
                makesPage = true
            }
            if layout.pages.isEmpty {
                EmptyCard(message: "No \(words.pages.lowercased()) yet. Tap New to make \(model.nextPageName).", systemImage: "square.stack.3d.up")
                    .accessibilityIdentifier("course.noPages")
            } else {
                QBankListGroup {
                    ForEach(layout.pages) { page in
                        NavigationLink(value: CoursePage.examPage(page.id)) {
                            ExamPageRow(page: page)
                        }
                        .buttonStyle(.qbankRow)
                        .accessibilityIdentifier("course.page.\(page.exam.name)")
                    }
                }
            }
        }
    }

    private func folders(_ layout: CourseLayout) -> some View {
        // As on the web, ordering is offered only when there are two folders to put in order, and
        // while the phone can save it. Done stays while she is already ordering.
        let hasOrder = layout.looseFolders.count > 1
        let offersEdit = order != nil || (hasOrder && model.canEdit)
        return VStack(alignment: .leading, spacing: 6) {
            SectionHead(
                title: "Folders",
                action: offersEdit ? (order == nil ? "Edit" : "Done") : nil,
                label: order == nil ? "Edit folder order" : "Done, save folder order",
                identifier: "course.editFolders",
                isEnabled: !isSavingOrder
            ) {
                editOrder(layout.looseFolders)
            }
            FolderList(folders: layout.looseFolders, order: $order)
            Text(order == nil ? "Folders on no \(model.words.page). Open one to see its sets." : "Drag a folder by its grip, or use the arrows, to put them in your order.")
                .qbankFont(.footnote)
                .foregroundStyle(.qbank(.text3))
                .padding(.horizontal, QBankSpacing.space5)
            if hasOrder, !offersEdit {
                Text("Putting folders in order needs a connection.")
                    .qbankFont(.footnote)
                    .foregroundStyle(.qbank(.text3))
                    .padding(.horizontal, QBankSpacing.space5)
                    .accessibilityIdentifier("course.orderNeedsConnection")
            }
        }
    }

    /// What she deleted in the course, for 30 days.
    private var recentlyDeleted: some View {
        QBankListGroup {
            NavigationLink(value: CoursePage.recentlyDeleted) {
                QBankListRow("Recently deleted", detail: "Bring back sets, folders and exams for 30 days", systemImage: "trash", showsChevron: true)
            }
            .buttonStyle(.qbankRow)
            .disabled(order != nil)
            .accessibilityIdentifier("course.recentlyDeleted")
        }
    }

    /// Edit puts the list in order mode; Done saves her order when it changed.
    private func editOrder(_ folders: [Folder]) {
        guard let edited = order else {
            orderProblem = nil
            order = folders.map(\.id)
            return
        }
        guard edited != folders.map(\.id) else {
            order = nil
            return
        }
        isSavingOrder = true
        Task {
            orderProblem = await model.saveOrder(page: nil, folderIDs: edited)
            isSavingOrder = false
            order = nil
        }
    }

}

extension View {
    /// Practice over the tabs, from a set of the course. Her answers change the set's line and the
    /// course's score, so the course is read again when it closes.
    func practiceCover(app: AppModel, model: CourseModel, route: Binding<PracticeRoute?>) -> some View {
        fullScreenCover(item: route, onDismiss: {
            Task { await model.load() }
        }, content: { route in
            PracticeView(app: app, route: route)
        })
    }

    /// A past or running exam over the tabs. Open Review goes to the course's Review list; Back to
    /// course does what `backToCourse` says.
    func examCover(app: AppModel, model: CourseModel, route: Binding<ExamRoute?>, backToCourse: @escaping () -> Void = {}) -> some View {
        modifier(ExamCover(app: app, model: model, route: route, backToCourse: backToCourse))
    }
}

private struct ExamCover: ViewModifier {
    let app: AppModel
    let model: CourseModel
    @Binding var route: ExamRoute?
    let backToCourse: () -> Void
    @State private var exit: ExamExit?
    @Environment(HomeNavigator.self) private var navigator: HomeNavigator?

    func body(content: Content) -> some View {
        content.fullScreenCover(item: $route, onDismiss: closed) { route in
            ExamView(app: app, examID: route.id, kind: model.course?.kind ?? .course) { how in
                exit = how
                self.route = nil
            }
        }
    }

    private func closed() {
        Task { await model.load() }
        switch exit {
        case .openReview:
            if let ref = model.ref { navigator?.open(StudyRoute.review(ref)) }
        case .backToCourse:
            backToCourse()
        case .done, nil:
            break
        }
        exit = nil
    }
}

/// One of the three study tiles under the course title.
private struct Tile: View {
    let systemImage: String
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.qbank(.tint))
                .frame(height: 26)
                .padding(.bottom, QBankSpacing.space3)
                .accessibilityHidden(true)
            Text(value)
                .qbankFont(.title2)
                .monospacedDigit()
                .foregroundStyle(.qbank(.text1))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .qbankFont(.footnote)
                .foregroundStyle(.qbank(.text2))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
