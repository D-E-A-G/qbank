import QBankDesign
import SwiftUI

/// Signed out: the Sign in screen, or Sign up for an email the owner added.
struct SignedOutView: View {
    let app: AppModel
    @State private var screen = Screen.signIn(nil)

    private enum Screen: Equatable {
        /// With what sign-up handed over, if anything.
        case signIn(SignInHandoff?)
        case signUp
    }

    var body: some View {
        Group {
            switch screen {
            case .signIn(let handoff):
                SignInView(app: app, handoff: handoff) { screen = .signUp }
                    .transition(.opacity)
            case .signUp:
                SignUpView(app: app) { handoff in screen = .signIn(handoff) }
                    .transition(.opacity)
            }
        }
        .animation(QBankMotion.reveal, value: screen)
    }
}
