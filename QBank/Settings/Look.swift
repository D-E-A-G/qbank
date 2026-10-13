import Foundation
import Observation
import SwiftUI
import UIKit

/// Light or dark, as Settings offers it. The raw values are the web's, so the phone and the
/// browser speak of the same three choices.
enum Look: String, CaseIterable {
    case matchDevice = "auto"
    case light
    case dark

    var label: String {
        switch self {
        case .matchDevice: "Match device"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .matchDevice: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }
}

/// The Look she chose, kept on this phone. Like the web's, it is a device setting: it is not
/// sent to the server, and it stays when she signs out.
@Observable
final class LookStore {
    static let key = "qbank-look"

    var look: Look {
        didSet { defaults.set(look.rawValue, forKey: Self.key) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        look = defaults.string(forKey: Self.key).flatMap(Look.init(rawValue:)) ?? .matchDevice
    }
}

/// Applies a Look to the window it is placed in, so every screen, sheet and alert follows it,
/// and Match device hands the choice back to the system.
struct WindowLook: UIViewRepresentable {
    let look: Look

    func makeUIView(context: Context) -> LookView {
        let view = LookView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ view: LookView, context: Context) {
        view.style = look.userInterfaceStyle
    }

    final class LookView: UIView {
        var style: UIUserInterfaceStyle = .unspecified {
            didSet { apply() }
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            apply()
        }

        private func apply() {
            window?.overrideUserInterfaceStyle = style
        }
    }
}
