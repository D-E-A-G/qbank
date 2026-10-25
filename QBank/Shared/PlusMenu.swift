import SwiftUI

extension View {
    /// Puts a screen's + menu at the top right, while the screen is on screen. A toolbar menu left
    /// on a screen with another pushed over it kept the signed-in screens from going at sign-out,
    /// so signing in again brought them back as they were.
    func plusMenu(_ isShown: Bool, @ViewBuilder menu: () -> some View) -> some View {
        modifier(PlusMenu(isShown: isShown, menu: menu()))
    }
}

private struct PlusMenu<Items: View>: ViewModifier {
    let isShown: Bool
    let menu: Items
    @State private var isOnScreen = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                if isShown, isOnScreen {
                    ToolbarItem(placement: .topBarTrailing) {
                        menu
                    }
                }
            }
            .onAppear { isOnScreen = true }
            .onDisappear { isOnScreen = false }
    }
}
