import QBankDesign
import SwiftUI

struct RootView: View {
    let model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch model.route {
            case .signedOut:
                SignInView(app: model)
                    .transition(.opacity)
            case .choosingPassword:
                ChoosePasswordView(app: model)
                    .transition(.opacity)
            case .signedIn(let account):
                SignedInView(app: model)
                    // A new sign-in starts from fresh screens.
                    .id(account.id)
                    .transition(.opacity)
            }
        }
        .animation(QBankMotion.reveal, value: model.route)
        .tint(QBankColor(.tint))
        .qbankPalette(.default)
        .background(WindowLook(look: model.look.look))
        .task {
            // A session kept from an earlier launch: check the server still accepts it.
            await model.refreshSession()
        }
        .onChange(of: scenePhase) { _, phase in
            // Back to the front: answers left waiting may go now.
            if phase == .active {
                model.offline?.sendIfWaiting()
            }
        }
    }
}

/// The three tabs: Home, Add (make or import questions), and Settings.
struct SignedInView: View {
    let app: AppModel
    @State private var tabs = TabNavigator()

    var body: some View {
        TabView(selection: $tabs.tab) {
            Tab("Home", systemImage: "house", value: AppTab.home) {
                HomeView(app: app, navigator: tabs.home)
            }
            Tab("Add", systemImage: "plus.circle", value: AppTab.add) {
                AddView(app: app)
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView(app: app)
            }
        }
        .environment(tabs)
    }
}
