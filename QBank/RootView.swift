import SwiftUI

struct RootView: View {
    let model: AppModel

    var body: some View {
        switch model.route {
        case .welcome:
            WelcomeView()
        }
    }
}

#Preview {
    RootView(model: AppModel())
}
