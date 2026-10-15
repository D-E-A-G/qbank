#if DEBUG
import Foundation

/// The app's Look, which a UI test sets while the app runs, so it can keep a screenshot of the
/// screen it is on in dark as well as in light, the way she sees it after choosing Dark in
/// Settings.
///
/// The test posts the Darwin notification `DebugLaunchScenario.lookNotification(_:)` names; it
/// crosses from the test runner to the app on the same simulator. Compiled only into Debug builds.
final class DebugLook {
    let store: LookStore

    init(store: LookStore) {
        self.store = store
    }

    /// Starts following the test's notifications, until this listener is released.
    func listen() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        let callback: CFNotificationCallback = { _, observer, name, _, _ in
            guard let observer, let name else { return }
            let listener = Unmanaged<DebugLook>.fromOpaque(observer).takeUnretainedValue()
            guard let look = Look.allCases.first(where: { DebugLaunchScenario.lookNotification($0) == name.rawValue as String }) else { return }
            Task { @MainActor in listener.store.look = look }
        }
        for look in Look.allCases {
            CFNotificationCenterAddObserver(center, observer, callback, DebugLaunchScenario.lookNotification(look) as CFString, nil, .deliverImmediately)
        }
    }

    deinit {
        CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque())
    }
}
#endif
