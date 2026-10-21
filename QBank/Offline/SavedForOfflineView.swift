import Observation
import QBankDesign
import QBankKit
import SwiftUI

/// Saved for offline, opened from Settings, from "3 waiting to send" on Home, or from the runner.
struct SavedForOfflineRoute: Hashable {}

/// What Saved for offline lists: the waiting answers by set, and the courses saved on the phone.
@Observable
final class SavedForOfflineModel {
    private(set) var groups: [WaitingGroup] = []
    private(set) var courses: [SavedCourse]?

    let app: AppModel

    init(app: AppModel) {
        self.app = app
    }

    var offline: OfflineStore? { app.offline }

    func load() async {
        guard let offline else {
            groups = []
            courses = []
            return
        }
        groups = await offline.waitingGroups()
        courses = await offline.savedCourses()
    }

    /// Sends the waiting answers now rather than waiting for the next try.
    func sendNow() async {
        await offline?.send()
        await load()
    }
}

/// Where she sees what is on the phone and what has not reached QBank yet: the answers waiting to
/// be sent, with Send now, and the courses saved for practicing without signal.
struct SavedForOfflineView: View {
    @State private var model: SavedForOfflineModel

    init(app: AppModel) {
        _model = State(initialValue: SavedForOfflineModel(app: app))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: QBankSpacing.space7) {
                if let problem = model.offline?.problem {
                    ProblemText(text: problem)
                        .padding(.horizontal, QBankSpacing.space5)
                }
                waiting
                if let notSaved = model.offline?.notSaved, !notSaved.isEmpty {
                    refused(notSaved)
                }
                courses
            }
            .screenColumn()
            .padding(.top, QBankSpacing.space3)
            .padding(.bottom, QBankSpacing.space7)
        }
        .qbankScreenBackground()
        .navigationTitle("Saved for offline")
        .screenColumnTitle()
        .refreshable { await model.load() }
        .task(id: model.offline?.waiting) { await model.load() }
        .onChange(of: model.offline?.savedRevision) {
            Task { await model.load() }
        }
    }

    private var waiting: some View {
        let isSending = model.offline?.isSending ?? false
        let isEmpty = model.offline?.waiting.isEmpty ?? true
        return QBankListGroup(
            header: "Waiting to send",
            footer: isEmpty ? nil : "They also send by themselves as soon as the \(Device.noun) is online."
        ) {
            if isEmpty {
                QBankListRow("Nothing waiting", detail: "Every answer you gave is saved on QBank.")
                    .accessibilityIdentifier("savedForOffline.nothingWaiting")
            } else {
                ForEach(model.groups) { group in
                    QBankListRow(
                        Wording.count(group.count, "answer"),
                        detail: "\(group.title) · \(Wording.answered(from: group.firstAnsweredAt, to: group.lastAnsweredAt))"
                    )
                    .accessibilityIdentifier("savedForOffline.waiting.\(group.title)")
                }
                Button {
                    Task { await model.sendNow() }
                } label: {
                    QBankListRow("Send now", systemImage: "arrow.up.circle") {
                        if isSending {
                            ProgressView()
                        }
                    }
                }
                .buttonStyle(.qbankRow)
                .disabled(isSending)
                .accessibilityIdentifier("savedForOffline.sendNow")
            }
        }
    }

    private func refused(_ notSaved: [RefusedAttempt]) -> some View {
        QBankListGroup(
            header: "Not saved",
            footer: "QBank refused these answers, so they were not saved. Answer the questions again to save them."
        ) {
            ForEach(notSaved, id: \.attempt.id) { refused in
                QBankListRow("1 answer", detail: Wording.problem(refused.error) ?? "QBank refused it.")
            }
            Button {
                model.offline?.dismissNotSaved()
            } label: {
                QBankListRow("Dismiss")
            }
            .buttonStyle(.qbankRow)
            .accessibilityIdentifier("savedForOffline.dismissNotSaved")
        }
    }

    private var courses: some View {
        QBankListGroup(
            header: model.courses?.contains { $0.kind == .topic } == true ? "Courses and topics on this \(Device.noun)" : "Courses on this \(Device.noun)",
            footer: "Courses save by themselves while the app is online, so every set can be practiced without signal."
        ) {
            if let courses = model.courses {
                if courses.isEmpty {
                    QBankListRow("Nothing saved yet", detail: "Open Home with a connection to save your courses.")
                }
                ForEach(courses) { course in
                    // A topic is called by its name alone.
                    QBankListRow(course.kind == .topic ? course.title : "\(course.code) \(course.title)", detail: Wording.savedCourse(course))
                        .accessibilityIdentifier("savedForOffline.course.\(Wording.name(course))")
                }
            } else {
                QBankListRow("Reading what is saved") {
                    ProgressView()
                }
            }
        }
    }
}
