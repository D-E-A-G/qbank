import Foundation
import Observation
import QBankKit

/// Settings' Change password: her current password and a new one, sent to the same
/// `POST /api/account/password` the web uses. The server ends her other sessions and gives
/// this phone a fresh one.
@Observable
final class ChangePasswordModel {
    var currentPassword = "" {
        didSet { if currentPassword != oldValue { isSaved = false } }
    }
    var newPassword = "" {
        didSet { if newPassword != oldValue { isSaved = false } }
    }
    private(set) var isSaving = false
    private(set) var problem: String?
    /// True after a change, until she types again.
    private(set) var isSaved = false

    static let sameAsCurrent = "Choose a new password that is different from your current one."

    private let app: AppModel

    init(app: AppModel) {
        self.app = app
    }

    func save() async {
        guard !isSaving else { return }
        guard !currentPassword.isEmpty, !newPassword.isEmpty else {
            problem = "Enter your current password and a new one."
            return
        }
        if let rule = PasswordRules.problem(newPassword: newPassword) {
            problem = rule
            return
        }
        guard newPassword != currentPassword else {
            problem = Self.sameAsCurrent
            return
        }
        isSaving = true
        problem = nil
        defer { isSaving = false }
        do {
            let signedIn = try await app.client.changePassword(current: currentPassword, new: newPassword)
            app.passwordChosen(signedIn)
            currentPassword = ""
            newPassword = ""
            isSaved = true
        } catch {
            report(error)
        }
    }

    private func report(_ error: QBankError) {
        if app.handle(error) { return }
        switch error.serverCode {
        case .samePassword:
            // The server's sentence speaks of a temporary password; here it is her own.
            problem = Self.sameAsCurrent
        case .invalidCredentials:
            currentPassword = ""
            problem = Wording.problem(error)
        default:
            problem = Wording.problem(error)
        }
    }
}
