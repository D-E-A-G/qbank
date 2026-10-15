import Foundation
import LocalAuthentication
import Observation

/// How the device confirms its owner: biometrics with the passcode behind them, or the passcode
/// alone on a device without Face ID or Touch ID set up.
enum UnlockMethod: Equatable {
    case faceID
    case touchID
    case opticID
    case passcode

    /// "Face ID", "Touch ID", "Optic ID", "passcode".
    var name: String {
        switch self {
        case .faceID: "Face ID"
        case .touchID: "Touch ID"
        case .opticID: "Optic ID"
        case .passcode: "passcode"
        }
    }

    var systemImage: String {
        switch self {
        case .faceID: "faceid"
        case .touchID: "touchid"
        case .opticID: "opticid"
        case .passcode: "lock"
        }
    }
}

/// What came of asking the device to confirm its owner.
enum OwnerCheck: Equatable {
    case confirmed
    /// She cancelled, or the system did, such as when the app left the screen.
    case cancelled
    /// The device has no passcode, so it cannot confirm anyone.
    case unavailable
}

/// The device's own check of who is holding it: Face ID, Touch ID, or the passcode.
protocol DeviceOwner {
    /// How the device confirms its owner, or nil when it cannot because it has no passcode.
    func method() -> UnlockMethod?
    /// Asks the device to confirm its owner. `reason` shows with Touch ID and the passcode;
    /// Face ID shows the app's usage description instead.
    func confirm(reason: String) async -> OwnerCheck
}

/// `DeviceOwner` through LocalAuthentication, which needs no entitlement, so a free Personal Team
/// signs it. The passcode stands behind biometrics, so a face that is not recognized, or
/// biometrics locked after failed tries, never lock her out of QBank.
struct LocalDeviceOwner: DeviceOwner {
    func method() -> UnlockMethod? {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return nil }
        // Asked after the policy check, which is what fills in the biometry type.
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        default: return .passcode
        }
    }

    func confirm(reason: String) async -> OwnerCheck {
        let context = LAContext()
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) ? .confirmed : .cancelled
        } catch LAError.passcodeNotSet {
            return .unavailable
        } catch {
            return .cancelled
        }
    }
}

/// The optional lock over QBank, kept on this device and off until she turns it on in Settings.
/// It covers the screens of a signed-in account until the device confirms its owner, at launch
/// and each time QBank comes back from the background. It changes nothing about the session: the
/// Keychain keeps it as before, and answers waiting to send still go while QBank is locked.
@Observable
final class AppLock {
    static let key = "qbank-app-lock"

    private(set) var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Self.key) }
    }
    /// True while the screens are covered and wait for the device's owner.
    private(set) var isLocked: Bool
    /// True while the device is asking for Face ID or the passcode.
    private(set) var isChecking = false
    /// How the device confirms its owner, or nil without a passcode; read again by `refresh()`.
    private(set) var method: UnlockMethod?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let owner: DeviceOwner
    /// True when the lock should ask by itself the next time QBank is on screen: after a launch
    /// or a return from the background, not again after she cancelled.
    @ObservationIgnored private var asksWhenActive: Bool

    init(defaults: UserDefaults = .standard, owner: DeviceOwner = LocalDeviceOwner()) {
        self.defaults = defaults
        self.owner = owner
        let isEnabled = defaults.bool(forKey: Self.key)
        self.isEnabled = isEnabled
        isLocked = isEnabled
        asksWhenActive = isEnabled
        method = owner.method()
    }

    /// Reads again how the device confirms its owner, which can change in the Settings app.
    func refresh() {
        method = owner.method()
    }

    /// Turns the lock on once the device confirms its owner, so she knows it works and it is her.
    func turnOn() async {
        guard !isEnabled, !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        let check = await owner.confirm(reason: "Turn on the lock for QBank")
        refresh()
        if check == .confirmed {
            isEnabled = true
        }
    }

    func turnOff() {
        isEnabled = false
        isLocked = false
        asksWhenActive = false
    }

    /// QBank left the screen: it locks, and asks when it comes back.
    func enteredBackground() {
        guard isEnabled else { return }
        isLocked = true
        asksWhenActive = true
    }

    /// QBank is on screen again: asks once, if it locked since it last asked. The passcode or
    /// Face ID may have changed in the Settings app meanwhile.
    func becameActive() async {
        refresh()
        guard isLocked, asksWhenActive else { return }
        await unlock()
    }

    /// Asks the device to confirm its owner, and unlocks when it does. A device whose passcode was
    /// removed cannot confirm anyone, and is open to whoever holds it, so the lock turns off.
    func unlock() async {
        guard isLocked, !isChecking else { return }
        asksWhenActive = false
        isChecking = true
        defer { isChecking = false }
        switch await owner.confirm(reason: "Unlock QBank") {
        case .confirmed:
            isLocked = false
        case .unavailable:
            turnOff()
        case .cancelled:
            break
        }
        refresh()
    }

    /// She just signed in with her password, which is proof enough until QBank next leaves the screen.
    func signedIn() {
        isLocked = false
        asksWhenActive = false
    }
}
