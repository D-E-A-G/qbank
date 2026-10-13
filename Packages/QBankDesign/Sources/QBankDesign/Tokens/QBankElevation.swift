import Foundation

/// One shadow layer, in CSS terms (`0 1px 2px rgba(...)`).
public struct QBankShadowLayer: Hashable, Sendable {
    public let color: QBankRGBA
    public let x: CGFloat
    public let y: CGFloat
    /// The CSS blur radius.
    public let blur: CGFloat
}

/// Elevation: a very faint shadow in light mode. Dark mode has no shadows; surfaces
/// get lighter as they rise, with at most a faint light hairline ring.
public enum QBankElevation: String, CaseIterable, Sendable {
    case card
    case raised
    case sheet
    case popover

    public func shadows(_ appearance: QBankAppearance) -> [QBankShadowLayer] {
        let ink = { (alpha: Double) in QBankRGBA(red: 28, green: 27, blue: 24, alpha: alpha) }
        switch (self, appearance) {
        case (.card, .light):
            return [.init(color: ink(0.04), x: 0, y: 0.5, blur: 0), .init(color: ink(0.05), x: 0, y: 1, blur: 2)]
        case (.raised, .light):
            return [.init(color: ink(0.06), x: 0, y: 1, blur: 2), .init(color: ink(0.06), x: 0, y: 4, blur: 12)]
        case (.sheet, .light):
            return [.init(color: ink(0.04), x: 0, y: -1, blur: 0), .init(color: ink(0.12), x: 0, y: -8, blur: 32)]
        case (.popover, .light):
            return [.init(color: ink(0.08), x: 0, y: 2, blur: 6), .init(color: ink(0.14), x: 0, y: 12, blur: 32)]
        case (.popover, .dark):
            return [.init(color: QBankRGBA(red: 0, green: 0, blue: 0, alpha: 0.5), x: 0, y: 12, blur: 32)]
        case (.card, .dark), (.raised, .dark), (.sheet, .dark):
            return []
        }
    }

    /// The 0.5pt light ring dark mode draws instead of a shadow, if any.
    public func ring(_ appearance: QBankAppearance) -> QBankRGBA? {
        guard appearance == .dark else { return nil }
        switch self {
        case .card: return nil
        case .raised: return QBankRGBA(red: 255, green: 255, blue: 255, alpha: 0.06)
        case .sheet, .popover: return QBankRGBA(red: 255, green: 255, blue: 255, alpha: 0.08)
        }
    }
}
