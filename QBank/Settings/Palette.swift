import QBankDesign
import QBankKit

extension Account.Palette {
    /// The palette the screens are drawn in for this color scheme.
    var design: QBankPalette {
        switch self {
        case .dusk: .dusk
        case .slate: .slate
        }
    }

    /// Its name in Settings: "Dusk" or "Slate".
    var label: String {
        design.displayName
    }
}
