#if canImport(SwiftUI)
import SwiftUI

extension QBankMotion.Curve {
    public func animation(duration: TimeInterval) -> Animation {
        .timingCurve(x1, y1, x2, y2, duration: duration)
    }
}

extension QBankMotion {
    /// Press feedback: 100 ms, standard ease.
    public static var press: Animation { easeStandard.animation(duration: instant) }
    /// Selecting or checking: 180 ms, standard ease.
    public static var select: Animation { easeStandard.animation(duration: quick) }
    /// The answer feedback reveal and progress changes: 260 ms, ease out.
    public static var reveal: Animation { easeOut.animation(duration: standard) }
    /// Sheets: 420 ms, iOS-like.
    public static var present: Animation { easeSheet.animation(duration: sheet) }
}

extension View {
    /// Applies the elevation's light-mode shadows, or its dark-mode ring, around `shape`.
    /// Use it on an opaque surface drawn in the same shape.
    public func qbankElevation<S: InsettableShape>(_ elevation: QBankElevation, in shape: S) -> some View {
        modifier(QBankElevationModifier(elevation: elevation, shape: shape))
    }
}

private struct QBankElevationModifier<S: InsettableShape>: ViewModifier {
    let elevation: QBankElevation
    let shape: S
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let appearance = QBankAppearance(colorScheme)
        let layers = elevation.shadows(appearance)
        content
            .background {
                // Shadows only show in light mode (and popovers in dark), where elevated
                // surfaces are `surfaceRaised`; filling with it keeps rounded edges clean.
                ZStack {
                    ForEach(Array(layers.enumerated()), id: \.offset) { _, layer in
                        // SwiftUI's shadow radius is about half the CSS blur radius.
                        shape.fill(.qbank(.surfaceRaised))
                            .shadow(color: layer.color.color, radius: layer.blur / 2, x: layer.x, y: layer.y)
                    }
                }
            }
            .overlay {
                if let ring = elevation.ring(appearance) {
                    shape.strokeBorder(ring.color, lineWidth: QBankBorder.hairline)
                }
            }
    }
}
#endif
