import QBankDesign
import QBankKit
import SwiftUI

/// Where a Settings row leads.
enum SettingsRoute: Hashable {
    case changePassword
    case semester(String)
    case course(String)
}

/// The Settings tab, as the web's Settings for a student: her account, her semesters and
/// courses, and Look. Export stays on the web.
struct SettingsView: View {
    let app: AppModel
    @State private var catalog: CatalogModel
    @State private var path = NavigationPath()
    @State private var isSigningOut = false

    init(app: AppModel) {
        self.app = app
        _catalog = State(initialValue: CatalogModel(app: app))
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: QBankSpacing.space7) {
                    account
                    if catalog.isEditable {
                        semesters
                    }
                    look
                    Text(Self.version)
                        .qbankFont(.footnote)
                        .foregroundStyle(.qbank(.text3))
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("settings.version")
                }
                .padding(.horizontal, QBankSpacing.gutterPhone)
                .padding(.top, QBankSpacing.space3)
                .padding(.bottom, QBankSpacing.space7)
            }
            .qbankScreenBackground()
            .navigationTitle("Settings")
            .refreshable { await catalog.load() }
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .changePassword:
                    ChangePasswordView(app: app)
                case .semester(let id):
                    SemesterView(catalog: catalog, id: id)
                case .course(let id):
                    CourseEditView(catalog: catalog, id: id)
                }
            }
        }
        .task {
            guard catalog.isEditable else { return }
            await catalog.load()
        }
    }

    private var account: some View {
        QBankListGroup(header: "Account") {
            VStack(alignment: .leading, spacing: 2) {
                Text("Signed in as")
                    .qbankFont(.footnote)
                    .foregroundStyle(.qbank(.text3))
                Text(app.account?.email ?? "")
                    .qbankFont(.body)
                    .foregroundStyle(.qbank(.text1))
            }
            .frame(maxWidth: .infinity, minHeight: QBankSpacing.rowMin, alignment: .leading)
            .padding(.horizontal, QBankSpacing.rowPaddingHorizontal)
            .padding(.vertical, 11)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("settings.account")
            NavigationLink(value: SettingsRoute.changePassword) {
                QBankListRow("Change password", showsChevron: true)
            }
            .buttonStyle(.qbankRow)
            .accessibilityIdentifier("settings.changePassword")
            QBankListRow("Passkeys and Face ID", detail: "Coming in a later update", showsChevron: true)
                .opacity(0.4)
                .accessibilityIdentifier("settings.passkeys")
            Button {
                isSigningOut = true
                Task { await app.signOut() }
            } label: {
                QBankListRow("Sign out", isDestructive: true) {
                    if isSigningOut {
                        ProgressView()
                    }
                }
            }
            .buttonStyle(.qbankRow)
            .disabled(isSigningOut)
            .accessibilityIdentifier("settings.signOut")
        }
    }

    private var semesters: some View {
        VStack(alignment: .leading, spacing: QBankSpacing.space3) {
            QBankListGroup(
                header: "Semesters and courses",
                footer: "Rename, move between semesters, archive or unarchive a course."
            ) {
                if let semesters = catalog.semesters {
                    ForEach(semesters) { semester in
                        NavigationLink(value: SettingsRoute.semester(semester.id)) {
                            QBankListRow(semester.name, detail: CatalogModel.summary(of: semester), showsChevron: true)
                        }
                        .buttonStyle(.qbankRow)
                        .accessibilityIdentifier("settings.semester.\(semester.number)")
                    }
                    if let number = catalog.nextSemesterNumber {
                        Button {
                            Task { await catalog.addSemester() }
                        } label: {
                            QBankListRow("Add Semester \(number)", systemImage: "plus") {
                                if catalog.isAdding {
                                    ProgressView()
                                }
                            }
                        }
                        .buttonStyle(.qbankRow)
                        .disabled(catalog.isAdding)
                        .accessibilityIdentifier("settings.addSemester")
                    }
                } else if let problem = catalog.loadProblem {
                    QBankListRow(problem, accessibilityChildren: .contain) {
                        Button("Try again") {
                            Task { await catalog.load() }
                        }
                        .buttonStyle(.qbank(.secondary, size: .small))
                        .accessibilityIdentifier("settings.semesters.retry")
                    }
                } else {
                    QBankListRow("Loading your semesters") {
                        ProgressView()
                    }
                }
            }
            if let problem = catalog.addProblem {
                ProblemText(text: problem)
                    .padding(.horizontal, QBankSpacing.space5)
            }
        }
    }

    private var look: some View {
        @Bindable var store = app.look
        return QBankListGroup(header: "Look", footer: "Match device follows this device's light or dark setting.") {
            QBankSegmentedControl("Look", selection: $store.look, options: Look.allCases.map { .init($0, $0.label) })
                .padding(QBankSpacing.space3)
                .accessibilityIdentifier("settings.look")
        }
    }

    /// "QBank 0.1.0 (1)": the version and build, as Settings shows it.
    static var version: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "QBank \(version) (\(build))"
    }
}
