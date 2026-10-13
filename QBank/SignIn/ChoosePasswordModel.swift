import Foundation
import Observation
import QBankKit

/// After the owner resets her password, the server asks for a new one before anything else.
@Observable
final class ChoosePasswordModel {
    var temporaryPassword: String
    var newPassword = ""
    private(set) var isSaving = false
    private(set) var problem: String?

    private let app: AppModel

    init(app: AppModel) {
        self.app = app
        temporaryPassword = app.temporaryPassword ?? ""
    }

    func save() async {
        guard !isSaving else { return }
        guard !temporaryPassword.isEmpty, !newPassword.isEmpty else {
            problem = "Enter the temporary password and a new one."
            return
        }
        if let rule = PasswordRules.problem(newPassword: newPassword) {
            problem = rule
            return
        }
        isSaving = true
        problem = nil
        defer { isSaving = false }
        do {
            let signedIn = try await app.client.changePassword(current: temporaryPassword, new: newPassword)
            app.passwordChosen(signedIn)
        } catch {
            if !app.handle(error) {
                problem = Wording.problem(error)
            }
        }
    }

    /// Back to the sign-in screen, which ends this session.
    func cancel() async {
        await app.signOut()
    }
}
