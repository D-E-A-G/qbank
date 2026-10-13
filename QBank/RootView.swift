import QBankDesign
import SwiftUI

struct RootView: View {
    let model: AppModel

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
    }
}

/// The two tabs of phase 1: Home and Settings.
struct SignedInView: View {
    let app: AppModel

    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") {
                HomeView(app: app)
            }
            Tab("Settings", systemImage: "gearshape") {
                SettingsView(app: app)
            }
        }
    }
}
