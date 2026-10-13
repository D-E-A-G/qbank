import SwiftUI

@main
struct QBankApp: App {
    @State private var model = AppModel.launch()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
    }
}
