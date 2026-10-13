#if canImport(SwiftUI)
import SwiftUI

extension EnvironmentValues {
    /// The accent palette for this view tree. Set it with ``SwiftUICore/View/qbankPalette(_:)``.
    @Entry public var qbankPalette: QBankPalette = .default
}

extension View {
    /// Picks the accent palette for this view and everything inside it.
    public func qbankPalette(_ palette: QBankPalette) -> some View {
        environment(\.qbankPalette, palette)
    }
}

extension QBankAppearance {
    public init(_ colorScheme: ColorScheme) {
        self = colorScheme == .dark ? .dark : .light
    }
}

/// A semantic color that resolves against the view's palette and color scheme,
/// so `.foregroundStyle(.qbank(.text2))` follows dark mode and the palette picker.
public struct QBankColor: ShapeStyle, Hashable, Sendable {
    public let token: QBankColorToken

    public init(_ token: QBankColorToken) {
        self.token = token
    }

    public func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        token.value(palette: environment.qbankPalette, appearance: QBankAppearance(environment.colorScheme)).resolved
    }
}

extension ShapeStyle where Self == QBankColor {
    /// A QBank semantic color, for example `.qbank(.tint)`.
    public static func qbank(_ token: QBankColorToken) -> QBankColor {
        QBankColor(token)
    }
}

extension QBankRGBA {
    /// The fixed color, for places that need a `Color` rather than a shape style.
    public var color: Color {
        Color(.sRGB, red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255, opacity: alpha)
    }

    public var resolved: Color.Resolved {
        Color.Resolved(
            colorSpace: .sRGB,
            red: Float(red) / 255,
            green: Float(green) / 255,
            blue: Float(blue) / 255,
            opacity: Float(alpha)
        )
    }
}

extension View {
    /// Fills the screen behind this view with the canvas color (`bg`).
    public func qbankScreenBackground() -> some View {
        background(.qbank(.bg), ignoresSafeAreaEdges: .all)
    }
}
#endif
