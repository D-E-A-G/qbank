#if DEBUG
import UIKit

/// Opens another QBank window when a UI test posts `DebugLaunchScenario.newWindowNotification`,
/// as she can on an iPad from the Dock or the app switcher. An iPhone has one window, and ignores
/// it. Compiled only into Debug builds.
enum DebugWindows {
    private static var isListening = false

    /// Starts following the test's notification while the app runs, once however many models
    /// the scenarios make.
    static func listen() {
        guard !isListening else { return }
        isListening = true
        let callback: CFNotificationCallback = { _, _, _, _, _ in
            Task { @MainActor in
                UIApplication.shared.requestSceneSessionActivation(nil, userActivity: nil, options: nil)
            }
        }
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), nil, callback, DebugLaunchScenario.newWindowNotification as CFString, nil,
            .deliverImmediately
        )
    }
}
#endif
