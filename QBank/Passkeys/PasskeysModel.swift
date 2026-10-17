import Foundation
import Observation
import QBankKit

/// Settings' passkeys, as the web's Settings has them: the account's passkeys, each with a way to
/// remove it, and saving one on this device.
@Observable
final class PasskeysModel {
    /// Nil until the first load answers.
    private(set) var passkeys: [Passkey]?
    private(set) var loadProblem: String?
    private(set) var isSaving = false
    /// The passkey being removed.
    private(set) var removingID: String?
    private(set) var problem: String?
    /// True after a save, until she does something else here.
    private(set) var isSaved = false

    private let app: AppModel

    init(app: AppModel) {
        self.app = app
    }

    /// "2", or "None"; nil until the list is loaded.
    var count: String? {
        passkeys.map { $0.isEmpty ? "None" : "\($0.count)" }
    }

    func load() async {
        do {
            passkeys = try await app.client.passkeys()
            loadProblem = nil
        } catch {
            if app.handle(error) { return }
            // A list already shown stays, as it was; only a first load says what went wrong.
            if passkeys == nil {
                loadProblem = Wording.problem(error)
            }
        }
    }

    func save() async {
        guard !isSaving, removingID == nil else { return }
        isSaving = true
        problem = nil
        isSaved = false
        defer { isSaving = false }
        do {
            let passkey = try await app.savePasskey()
            passkeys = (passkeys ?? []) + [passkey]
            isSaved = true
        } catch {
            if let error = error as? QBankError, app.handle(error) { return }
            problem = Wording.passkeyProblem(error)
        }
    }

    func remove(_ passkey: Passkey) async {
        guard !isSaving, removingID == nil else { return }
        removingID = passkey.id
        problem = nil
        isSaved = false
        defer { removingID = nil }
        do {
            try await app.client.removePasskey(id: passkey.id)
            passkeys?.removeAll { $0.id == passkey.id }
        } catch {
            if app.handle(error) { return }
            problem = Wording.problem(error)
        }
    }
}
