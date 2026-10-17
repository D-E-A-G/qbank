import Foundation
import Observation
import QBankKit

/// The offer to save a passkey after she signs in with her password, as the web makes it: once for
/// each account on this device, until she saves one or says not now. Her answer is kept on the
/// device; signing out keeps it.
@Observable
final class PasskeyOffer {
    /// The account the offer is open for, or nil while it is closed.
    private(set) var accountID: String?
    private(set) var isSaving = false
    private(set) var problem: String?

    var isOpen: Bool {
        accountID != nil
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static func key(for accountID: String) -> String {
        "qbank-passkey-offer.\(accountID)"
    }

    /// After a password sign-in: opens the offer, unless she answered it on this device before.
    func open(for account: Account) {
        guard defaults.string(forKey: Self.key(for: account.id)) == nil else { return }
        problem = nil
        accountID = account.id
    }

    /// Not now: the offer closes and does not come back for this account on this device.
    func decline() {
        guard let accountID, !isSaving else { return }
        defaults.set("dismissed", forKey: Self.key(for: accountID))
        self.accountID = nil
    }

    /// Saves a passkey for this device, and closes once it is saved, or once the device says it
    /// already has one. A closed passkey sheet leaves the offer open, as on the web.
    func save(with app: AppModel) async {
        guard let accountID, !isSaving else { return }
        isSaving = true
        problem = nil
        defer { isSaving = false }
        do {
            try await app.savePasskey()
            saved(accountID)
        } catch PasskeyFailure.alreadySaved {
            saved(accountID)
        } catch {
            if let error = error as? QBankError, app.handle(error) { return }
            problem = Wording.passkeyProblem(error)
        }
    }

    /// Closes without keeping an answer, as when she signs out with the offer open.
    func close() {
        accountID = nil
        problem = nil
    }

    private func saved(_ accountID: String) {
        defaults.set("saved", forKey: Self.key(for: accountID))
        if self.accountID == accountID {
            self.accountID = nil
        }
    }
}
