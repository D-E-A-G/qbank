/// The accent palettes the web app offers (`data-palette` on `<html>`).
/// Everything except the accent and the "guessed" color is identical across them.
public enum QBankPalette: String, CaseIterable, Identifiable, Sendable {
    /// Mauve with peach. The default, as on the web.
    case dusk
    /// Bubblegum pink with periwinkle.
    case pink
    /// Ink blue with plum.
    case ink
    /// Salmon and peach with lavender.
    case earth
    /// Graphite with periwinkle: one quiet accent.
    case slate

    public static let `default`: QBankPalette = .dusk

    public var id: String { rawValue }

    /// Sentence-case name for a picker in Settings.
    public var displayName: String {
        switch self {
        case .dusk: "Dusk"
        case .pink: "Pink"
        case .ink: "Ink"
        case .earth: "Earth"
        case .slate: "Slate"
        }
    }

    public var accent: QBankAccentRamp {
        typealias C = QBankBaseColors
        switch self {
        case .dusk:
            return QBankAccentRamp(
                shade50: C.dusk50, shade100: C.dusk100, shade300: C.dusk300, shade400: C.dusk400,
                shade500: C.dusk500, shade600: C.dusk600, shade700: C.dusk700, shade900: C.dusk900,
                tintDark: C.dusk300, pressedDark: C.dusk100, onTintDark: C.dusk900,
                softDark: QBankRGBA(0x2E1F2E), softBorderDark: QBankRGBA(0x4A3348)
            )
        case .pink:
            return QBankAccentRamp(
                shade50: C.pink50, shade100: C.pink100, shade300: C.pink300, shade400: C.pink400,
                shade500: C.pink500, shade600: C.pink600, shade700: C.pink700, shade900: C.pink900,
                tintDark: C.pink400, pressedDark: C.pink300, onTintDark: C.pink900,
                softDark: QBankRGBA(0x3A1F2B), softBorderDark: QBankRGBA(0x5A2E42)
            )
        case .ink:
            return QBankAccentRamp(
                shade50: C.ink50, shade100: C.ink100, shade300: C.ink300, shade400: C.ink400,
                shade500: C.ink500, shade600: C.ink600, shade700: C.ink700, shade900: C.ink900,
                tintDark: C.ink300, pressedDark: C.ink100, onTintDark: QBankRGBA(0x111820),
                softDark: QBankRGBA(0x1F2A38), softBorderDark: QBankRGBA(0x2E3E54)
            )
        case .earth:
            return QBankAccentRamp(
                shade50: C.earth50, shade100: C.earth100, shade300: C.earth300, shade400: C.earth400,
                shade500: C.earth500, shade600: C.earth600, shade700: C.earth700, shade900: C.earth900,
                tintDark: C.earth400, pressedDark: C.earth300, onTintDark: C.earth900,
                softDark: QBankRGBA(0x3A2420), softBorderDark: QBankRGBA(0x5C3A32)
            )
        case .slate:
            return QBankAccentRamp(
                shade50: C.slate50, shade100: C.slate100, shade300: C.slate300, shade400: C.slate400,
                shade500: C.slate500, shade600: C.slate600, shade700: C.slate700, shade900: C.slate900,
                tintDark: C.slate300, pressedDark: C.slate100, onTintDark: C.slate900,
                softDark: QBankRGBA(0x202326), softBorderDark: QBankRGBA(0x393E42)
            )
        }
    }

    public var guess: QBankGuessRamp {
        typealias C = QBankBaseColors
        switch self {
        case .dusk:
            return QBankGuessRamp(
                shade50: C.peach50, shade300: C.peach300, shade400: C.peach400, shade600: C.peach600,
                shade900: C.peach900, borderDark: QBankRGBA(0x5C4630)
            )
        case .pink, .slate:
            return QBankGuessRamp(
                shade50: C.peri50, shade300: C.peri300, shade400: C.peri400, shade600: C.peri600,
                shade900: C.peri900, borderDark: QBankRGBA(0x34407A)
            )
        case .ink:
            return QBankGuessRamp(
                shade50: C.plum50, shade300: C.plum300, shade400: C.plum400, shade600: C.plum600,
                shade900: C.plum900, borderDark: QBankRGBA(0x4B3E62)
            )
        case .earth:
            return QBankGuessRamp(
                shade50: C.lav50, shade300: C.lav300, shade400: C.lav400, shade600: C.lav600,
                shade900: C.lav900, borderDark: QBankRGBA(0x4A4070)
            )
        }
    }
}

/// One palette's accent ramp (`--accent-*` on the web) plus its dark-mode picks.
public struct QBankAccentRamp: Hashable, Sendable {
    public let shade50, shade100, shade300, shade400, shade500, shade600, shade700, shade900: QBankRGBA
    public let tintDark, pressedDark, onTintDark, softDark, softBorderDark: QBankRGBA
}

/// One palette's "guessed" ramp (`--guess-*` on the web).
public struct QBankGuessRamp: Hashable, Sendable {
    public let shade50, shade300, shade400, shade600, shade900: QBankRGBA
    public let borderDark: QBankRGBA
}
