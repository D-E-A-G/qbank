import QBankDesign
import QBankKit
import SwiftUI

/// Settings' Connect an agent, as the web's: the code her agent shows, then the agent's name and
/// what it asks to do with Deny and Approve, and under it Your keys, each with Revoke. No key is
/// ever shown or copied.
struct ConnectAgentView: View {
    @State private var model: ConnectAgentModel
    @FocusState private var isFocused: Bool
    /// The key the sheet asks about. It outlives the sheet, which closes before its action runs.
    @State private var toRevoke: AgentKey?
    @State private var asksToRevoke = false

    init(app: AppModel) {
        _model = State(initialValue: ConnectAgentModel(app: app))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: QBankSpacing.space7) {
                Text(AgentWording.intro)
                    .qbankFont(.subheadline)
                    .foregroundStyle(.qbank(.text2))
                    .accessibilityIdentifier("connectAgent.intro")
                approve
                yourKeys
            }
            .screenColumn()
            .padding(.top, QBankSpacing.space3)
            .padding(.bottom, QBankSpacing.space7)
        }
        .scrollDismissesKeyboard(.interactively)
        .qbankScreenBackground()
        .navigationTitle("Connect an agent")
        .screenColumnTitle()
        .refreshable { await model.load() }
        .task { await model.load() }
        .task(id: model.watching) { await model.watchForPickup() }
        .task(id: model.lockedUntil) {
            guard let lockedUntil = model.lockedUntil else { return }
            try? await Task.sleep(for: .seconds(max(0, lockedUntil.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            model.lockEnded()
        }
        .confirmSheet(
            isPresented: $asksToRevoke,
            title: AgentWording.revokeTitle(toRevoke?.name ?? ""),
            message: AgentWording.revokeMessage(toRevoke?.scopes ?? []),
            confirm: "Revoke",
            identifier: "connectAgent.revokeSheet"
        ) {
            guard let key = toRevoke else { return }
            Task { await model.revoke(key) }
        }
    }

    // MARK: Approve a code

    private var approve: some View {
        VStack(alignment: .leading, spacing: 6) {
            QBankSectionHeader("Approve a code")
                .padding(.horizontal, QBankSpacing.space5)
            QBankCard(padding: QBankSpacing.space4) {
                VStack(alignment: .leading, spacing: 14) {
                    if case .found(let code, let pairing) = model.stage {
                        PairingRequest(code: code, pairing: pairing, isAdmin: model.isAdmin, isBusy: model.isBusy) { approve in
                            Task { await model.answer(approve: approve) }
                        }
                    } else {
                        if case .answered(let approved, let name) = model.stage {
                            AnswerBanner(approved: approved, name: name)
                        }
                        codeForm
                    }
                    if let problem = model.problem {
                        ProblemText(text: problem)
                    }
                }
            }
        }
    }

    private var codeForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            LabeledField(label: "Code", hint: AgentWording.codeHint) {
                TextField("Code", text: $model.code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .submitLabel(.continue)
                    .focused($isFocused)
                    .onSubmit(lookUp)
                    .onChange(of: model.code) { model.codeChanged() }
                    .accessibilityIdentifier("connectAgent.code")
            }
            Button(action: lookUp) {
                if model.isBusy {
                    ProgressView()
                        .tint(QBankColor(.textOnTint))
                        .accessibilityLabel("Continue")
                } else {
                    Text("Continue")
                }
            }
            .buttonStyle(.qbank(.primary, size: .large, fullWidth: true))
            .disabled(!model.canContinue)
            .accessibilityIdentifier("connectAgent.continue")
        }
    }

    private func lookUp() {
        isFocused = false
        Task { await model.lookUp() }
    }

    // MARK: Your keys

    private var yourKeys: some View {
        VStack(alignment: .leading, spacing: 6) {
            QBankSectionHeader("Your keys")
                .padding(.horizontal, QBankSpacing.space5)
            if let revoked = model.revoked {
                SavedText(text: revoked)
                    .padding(.horizontal, QBankSpacing.space5)
                    .padding(.vertical, QBankSpacing.space2)
            }
            if let problem = model.revokeProblem {
                ProblemText(text: problem)
                    .padding(.horizontal, QBankSpacing.space5)
                    .padding(.vertical, QBankSpacing.space2)
            }
            if let keys = model.keys {
                if keys.isEmpty {
                    EmptyCard(message: AgentWording.noKeys, systemImage: "key")
                        .accessibilityIdentifier("connectAgent.noKeys")
                } else {
                    QBankListGroup {
                        ForEach(keys) { key in
                            KeyRow(key: key, isRevoking: model.revokingID == key.id, isDisabled: model.revokingID != nil) {
                                toRevoke = key
                                asksToRevoke = true
                            }
                        }
                    }
                }
            } else if let problem = model.loadProblem {
                QBankListGroup {
                    QBankListRow(problem, accessibilityChildren: .contain) {
                        Button("Try again") {
                            Task { await model.load() }
                        }
                        .buttonStyle(.qbank(.secondary, size: .small))
                        .accessibilityIdentifier("connectAgent.keys.retry")
                    }
                }
            } else {
                QBankListGroup {
                    QBankListRow(AgentWording.loadingKeys) {
                        ProgressView()
                    }
                }
            }
            Text(AgentWording.keysFooter)
                .qbankFont(.footnote)
                .foregroundStyle(.qbank(.text3))
                .padding(.horizontal, QBankSpacing.space5)
                .accessibilityIdentifier("connectAgent.keysFooter")
        }
    }
}

/// The agent waiting under the code: its name, what it asks to do, and Deny or Approve.
private struct PairingRequest: View {
    let code: String
    let pairing: AgentPairing
    let isAdmin: Bool
    let isBusy: Bool
    let answer: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(pairing.name)
                    .qbankFont(.title3)
                    .foregroundStyle(.qbank(.text1))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("connectAgent.name")
                QBankDetailText(AgentWording.codeLine(code, pairing))
                    .qbankFont(.footnote)
                    .foregroundStyle(.qbank(.text2))
                    .accessibilityIdentifier("connectAgent.codeLine")
            }
            VStack(alignment: .leading, spacing: QBankSpacing.space3) {
                Text("It asks to")
                    .qbankFont(.subheadline, weight: .semibold)
                    .foregroundStyle(.qbank(.text2))
                ForEach(AgentWording.pairingScopes(pairing, admin: isAdmin)) { scope in
                    ScopeRow(scope: scope)
                }
            }
            Text(AgentWording.approvalNote(pairing.scopes))
                .qbankFont(.callout)
                .foregroundStyle(.qbank(.text2))
                .accessibilityIdentifier("connectAgent.note")
            HStack(spacing: QBankSpacing.space4) {
                Button("Deny") { answer(false) }
                    .buttonStyle(.qbank(.secondary, size: .large, fullWidth: true))
                    .accessibilityIdentifier("connectAgent.deny")
                Button("Approve") { answer(true) }
                    .buttonStyle(.qbank(.primary, size: .large, fullWidth: true))
                    .accessibilityIdentifier("connectAgent.approve")
            }
            .disabled(isBusy)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("connectAgent.request")
    }
}

/// One thing the agent asks to do: a check, its title, and its plain words.
private struct ScopeRow: View {
    let scope: AgentWording.AskedScope

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(.qbank(.tint))
                .padding(.top, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                TaggedTitle(title: scope.title, isStrongest: scope.isStrongest)
                Text(scope.detail)
                    .qbankFont(.footnote)
                    .foregroundStyle(.qbank(.text2))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("connectAgent.scope.\(scope.scope.rawValue)")
    }
}

/// A title with the Most access tag beside it, which wraps under it when the line is full.
private struct TaggedTitle: View {
    let title: String
    let isStrongest: Bool
    var isStrong = false

    var body: some View {
        FlowLayout(spacing: QBankSpacing.space3, lineSpacing: QBankSpacing.space1) {
            Text(title)
                .qbankFont(.body, weight: isStrong ? .semibold : .regular)
                .foregroundStyle(.qbank(.text1))
            if isStrongest {
                QBankTintedLabel(AgentWording.mostAccess, size: .small)
            }
        }
    }
}

/// What came of her answer, over the code field.
private struct AnswerBanner: View {
    let approved: Bool
    let name: String

    var body: some View {
        let text = approved ? AgentWording.approved(name) : AgentWording.denied(name)
        Label {
            Text(text)
                .qbankFont(.subheadline)
                .foregroundStyle(.qbank(.text1))
        } icon: {
            Image(systemName: approved ? "checkmark" : "xmark")
                .fontWeight(.semibold)
                .foregroundStyle(.qbank(.tint))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, QBankSpacing.space4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.qbank(.tintSoft), in: .rect(cornerRadius: QBankRadius.md, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("connectAgent.answered")
        .onAppear {
            AccessibilityNotification.Announcement(text).post()
        }
    }
}

/// One of her keys: its name, when it was made and last used, and what it can do, with Revoke. A
/// revoked key stays listed, quieter, without its Revoke.
private struct KeyRow: View {
    let key: AgentKey
    let isRevoking: Bool
    let isDisabled: Bool
    let revoke: () -> Void

    var body: some View {
        HStack(spacing: QBankSpacing.space4) {
            VStack(alignment: .leading, spacing: 2) {
                if key.isRevoked {
                    Text(key.name)
                        .qbankFont(.body, weight: .semibold)
                        .foregroundStyle(.qbank(.text3))
                } else {
                    TaggedTitle(title: key.name, isStrongest: key.scopes.contains(.manage), isStrong: true)
                }
                QBankDetailText(AgentWording.keyDates(key))
                    .qbankFont(.footnote)
                    .foregroundStyle(.qbank(.text2))
                Text(key.isRevoked ? AgentWording.revokedKey : AgentWording.scopesLine(key.scopes))
                    .qbankFont(.footnote)
                    .foregroundStyle(.qbank(.text2))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("connectAgent.key.\(key.name)")
            if !key.isRevoked {
                if isRevoking {
                    ProgressView()
                } else {
                    Button("Revoke", action: revoke)
                        .buttonStyle(.qbank(.destructive, size: .small))
                        .disabled(isDisabled)
                        .accessibilityLabel("Revoke \(key.name)")
                        .accessibilityIdentifier("connectAgent.revoke.\(key.name)")
                }
            }
        }
        .padding(.horizontal, QBankSpacing.rowPaddingHorizontal)
        .padding(.vertical, 11)
        .frame(minHeight: QBankSpacing.rowMin)
    }
}
