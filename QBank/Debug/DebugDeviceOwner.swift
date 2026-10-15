#if DEBUG
import Foundation

/// A device that answers for its owner as a UI test tells it to, so the lock can be tested without
/// the simulator's Face ID. It confirms, or refuses as though she cancelled, until the test posts
/// the Darwin notifications named in `DebugLaunchScenario` to change its answer while the app runs.
/// Compiled only into Debug builds.
final class DebugDeviceOwner: DeviceOwner {
    enum Kind: String {
        /// Face ID that confirms her.
        case faceID = "face-id"
        /// Face ID that refuses until told to confirm.
        case faceIDRefusing = "face-id-refusing"
        /// Touch ID that confirms her.
        case touchID = "touch-id"
        /// A device with no passcode, which cannot confirm anyone.
        case noPasscode = "no-passcode"
    }

    private let unlockMethod: UnlockMethod?
    private(set) var confirms: Bool
    /// How many times the app asked it to confirm her.
    private(set) var asked = 0

    init(_ kind: Kind) {
        switch kind {
        case .faceID, .faceIDRefusing: unlockMethod = .faceID
        case .touchID: unlockMethod = .touchID
        case .noPasscode: unlockMethod = nil
        }
        confirms = kind != .faceIDRefusing
    }

    func method() -> UnlockMethod? {
        unlockMethod
    }

    func confirm(reason: String) async -> OwnerCheck {
        asked += 1
        guard unlockMethod != nil else { return .unavailable }
        return confirms ? .confirmed : .cancelled
    }

    func set(confirms: Bool) {
        self.confirms = confirms
    }

    /// Starts following the test's notifications, until this device is released.
    func listen() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        let callback: CFNotificationCallback = { _, observer, name, _, _ in
            guard let observer, let name else { return }
            let owner = Unmanaged<DebugDeviceOwner>.fromOpaque(observer).takeUnretainedValue()
            let confirms = name.rawValue as String == DebugLaunchScenario.ownerConfirmsNotification
            Task { @MainActor in owner.set(confirms: confirms) }
        }
        for name in [DebugLaunchScenario.ownerConfirmsNotification, DebugLaunchScenario.ownerRefusesNotification] {
            CFNotificationCenterAddObserver(center, observer, callback, name as CFString, nil, .deliverImmediately)
        }
    }

    deinit {
        CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque())
    }
}
#endif
