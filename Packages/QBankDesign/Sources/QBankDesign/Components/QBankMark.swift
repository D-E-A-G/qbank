#if canImport(SwiftUI)
import SwiftUI

/// The app's mark: the app icon's Q (direction A2) in paper-100 on the Dusk gradient tile, over
/// the sign-in and lock screens. It is the icon's own drawing, so it looks the same in every
/// palette and in light and dark, as the icon on the home screen does.
public struct QBankMark: View {
    private let size: CGFloat

    /// - Parameter size: The tile's side; the corners round with it, 16 at the usual 64.
    public init(size: CGFloat = 64) {
        self.size = size
    }

    public var body: some View {
        QBankMarkShape()
            .fill(QBankBaseColors.paper100.color)
            .frame(width: size, height: size)
            .background(
                LinearGradient(
                    colors: [QBankBaseColors.dusk500.color, QBankBaseColors.dusk900.color],
                    startPoint: .top, endPoint: .bottom
                ),
                in: .rect(cornerRadius: size / 4, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}

/// The Q of `docs/app-icon/AppIcon.svg`, drawn on the icon's 1024 grid and scaled to fit: a
/// letter-shaped bowl (an outer ellipse less an inner one) and a short square-cut tail off its
/// lower right, joined. The square it fits stands for the whole icon, so the Q sits where it does
/// on the icon.
public struct QBankMarkShape: Shape {
    /// The icon's grid.
    static let grid: CGFloat = 1024
    /// The bowl's outer and inner ellipses, centred on (500, 495).
    static let outer = CGRect(x: 265, y: 240, width: 470, height: 510)
    static let inner = CGRect(x: 368, y: 323, width: 264, height: 344)
    /// The tail: a line from (610, 620) to (706, 716), 100 wide, with butt ends.
    static let tailStart = CGPoint(x: 610, y: 620)
    static let tailEnd = CGPoint(x: 706, y: 716)
    static let tailWidth: CGFloat = 100

    public init() {}

    public func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let scale = side / Self.grid
        let transform = CGAffineTransform(translationX: rect.midX - side / 2, y: rect.midY - side / 2)
            .scaledBy(x: scale, y: scale)
        return Self.glyph.applying(transform)
    }

    /// The Q on the 1024 grid.
    static var glyph: Path {
        let bowl = Path(ellipseIn: outer).subtracting(Path(ellipseIn: inner))
        return bowl.union(tail)
    }

    /// The tail's stroke as a filled four-sided shape: the line pushed half its width to each side.
    static var tail: Path {
        let dx = tailEnd.x - tailStart.x
        let dy = tailEnd.y - tailStart.y
        let length = (dx * dx + dy * dy).squareRoot()
        let half = tailWidth / 2
        let offset = CGPoint(x: -dy / length * half, y: dx / length * half)
        var path = Path()
        path.move(to: CGPoint(x: tailStart.x + offset.x, y: tailStart.y + offset.y))
        path.addLine(to: CGPoint(x: tailEnd.x + offset.x, y: tailEnd.y + offset.y))
        path.addLine(to: CGPoint(x: tailEnd.x - offset.x, y: tailEnd.y - offset.y))
        path.addLine(to: CGPoint(x: tailStart.x - offset.x, y: tailStart.y - offset.y))
        path.closeSubpath()
        return path
    }
}

#Preview("Mark") {
    HStack(spacing: QBankSpacing.space5) {
        QBankMark(size: 40)
        QBankMark()
        QBankMark(size: 120)
    }
    .padding(QBankSpacing.gutterPhone)
    .qbankScreenBackground()
}
#endif
