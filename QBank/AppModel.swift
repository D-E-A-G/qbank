import Observation

/// The app's top-level state. Phase 0 has one screen; slice 1a adds the
/// signed-out and signed-in routes.
@Observable
final class AppModel {
    enum Route: Equatable {
        case welcome
    }

    var route: Route

    init(route: Route = .welcome) {
        self.route = route
    }

    /// The model the app starts with. Debug builds let UI tests choose a
    /// scenario through `DebugLaunchScenario`; Release builds always start
    /// from the default.
    static func launch() -> AppModel {
        #if DEBUG
        if let model = DebugLaunchScenario.makeModel() {
            return model
        }
        #endif
        return AppModel()
    }
}
