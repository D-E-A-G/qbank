/// The raw color ramps behind every palette, named after the web tokens
/// (`--paper-100` is `paper100`). Screens should not use these directly: use
/// ``QBankColorToken`` so the palette and dark mode keep working.
public enum QBankBaseColors {
    // MARK: Warm paper neutrals

    public static let paper0 = QBankRGBA(0xFFFFFF)
    public static let paper50 = QBankRGBA(0xFBF9F5)
    public static let paper100 = QBankRGBA(0xF7F4EE)
    public static let paper200 = QBankRGBA(0xEDE8DF)
    public static let paper300 = QBankRGBA(0xE7E3DA)
    public static let paper400 = QBankRGBA(0xCFC9BD)
    public static let paper500 = QBankRGBA(0x9A948A)
    public static let paper600 = QBankRGBA(0x6E6960)
    public static let paper700 = QBankRGBA(0x4A463F)
    public static let paper800 = QBankRGBA(0x2A2825)
    public static let paper850 = QBankRGBA(0x1C1B18)
    public static let paper900 = QBankRGBA(0x151412)
    public static let paper950 = QBankRGBA(0x0C0C0B)

    // MARK: Accent A: bubblegum pink

    public static let pink50 = QBankRGBA(0xFDEEF4)
    public static let pink100 = QBankRGBA(0xFBDCE8)
    public static let pink300 = QBankRGBA(0xF5A9C4)
    public static let pink400 = QBankRGBA(0xF07AA6)
    public static let pink500 = QBankRGBA(0xE25A8F)
    public static let pink600 = QBankRGBA(0xC93D74)
    public static let pink700 = QBankRGBA(0xA82F60)
    public static let pink900 = QBankRGBA(0x3B1220)

    // MARK: Accent B: ink blue

    public static let ink50 = QBankRGBA(0xEDF1F7)
    public static let ink100 = QBankRGBA(0xDCE5F0)
    public static let ink300 = QBankRGBA(0x9DB6D6)
    public static let ink400 = QBankRGBA(0x7D9CC6)
    public static let ink500 = QBankRGBA(0x4A71A3)
    public static let ink600 = QBankRGBA(0x36598A)
    public static let ink700 = QBankRGBA(0x2A4870)
    public static let ink900 = QBankRGBA(0x17263A)

    // MARK: Accent C: earth (salmon to peach)

    public static let earth50 = QBankRGBA(0xFDEFE9)
    public static let earth100 = QBankRGBA(0xFBDCD0)
    public static let earth300 = QBankRGBA(0xF4B39E)
    public static let earth400 = QBankRGBA(0xF0977E)
    public static let earth500 = QBankRGBA(0xE67A5E)
    public static let earth600 = QBankRGBA(0xC2573F)
    public static let earth700 = QBankRGBA(0xA2452F)
    public static let earth900 = QBankRGBA(0x3A1A12)

    // MARK: Accent D: dusk (mauve), with peach for "guessed"

    public static let dusk50 = QBankRGBA(0xF6ECF1)
    public static let dusk100 = QBankRGBA(0xEDD7E2)
    public static let dusk300 = QBankRGBA(0xC994AE)
    public static let dusk400 = QBankRGBA(0xB26F92)
    public static let dusk500 = QBankRGBA(0x935073)
    public static let dusk600 = QBankRGBA(0x7C3F60)
    public static let dusk700 = QBankRGBA(0x62324D)
    public static let dusk900 = QBankRGBA(0x502D55)

    public static let peach50 = QBankRGBA(0xFBF3EA)
    public static let peach300 = QBankRGBA(0xF6DBC0)
    public static let peach400 = QBankRGBA(0xE9C39E)
    public static let peach600 = QBankRGBA(0x9C6A3C)
    public static let peach900 = QBankRGBA(0x33241A)

    // MARK: Answer states, shared by every palette

    public static let sage50 = QBankRGBA(0xE6F4EA)
    public static let sage300 = QBankRGBA(0x9AD3AE)
    public static let sage400 = QBankRGBA(0x7ACC98)
    public static let sage600 = QBankRGBA(0x2D8A55)
    public static let sage900 = QBankRGBA(0x16291D)

    public static let amber50 = QBankRGBA(0xFBF1DA)
    public static let amber300 = QBankRGBA(0xEBCB7A)
    public static let amber400 = QBankRGBA(0xE5B94E)
    public static let amber600 = QBankRGBA(0x8A6512)
    public static let amber900 = QBankRGBA(0x2A2208)

    public static let brick50 = QBankRGBA(0xF8E6E2)
    public static let brick300 = QBankRGBA(0xE4A79C)
    public static let brick400 = QBankRGBA(0xE08A7A)
    public static let brick600 = QBankRGBA(0xB13A2E)
    public static let brick900 = QBankRGBA(0x2C1512)

    // MARK: "Guessed" ramps (one per palette, so it never collides with the accent)

    public static let peri50 = QBankRGBA(0xECF0FE)
    public static let peri300 = QBankRGBA(0xAEBEFC)
    public static let peri400 = QBankRGBA(0x8FA6FA)
    public static let peri600 = QBankRGBA(0x4A62D6)
    public static let peri900 = QBankRGBA(0x1F2542)

    public static let lav50 = QBankRGBA(0xF1EEF8)
    public static let lav300 = QBankRGBA(0xC3B8E2)
    public static let lav400 = QBankRGBA(0xA99BD1)
    public static let lav600 = QBankRGBA(0x6F5FA3)
    public static let lav900 = QBankRGBA(0x262137)

    public static let plum50 = QBankRGBA(0xEFE9F6)
    public static let plum300 = QBankRGBA(0xC4B2E0)
    public static let plum400 = QBankRGBA(0xB9A0E0)
    public static let plum600 = QBankRGBA(0x6A4C98)
    public static let plum900 = QBankRGBA(0x2A2336)

    /// Every ramp color by its CSS name, for checking against the web.
    static let byCSSName: [String: QBankRGBA] = [
        "--paper-0": paper0,
        "--paper-50": paper50,
        "--paper-100": paper100,
        "--paper-200": paper200,
        "--paper-300": paper300,
        "--paper-400": paper400,
        "--paper-500": paper500,
        "--paper-600": paper600,
        "--paper-700": paper700,
        "--paper-800": paper800,
        "--paper-850": paper850,
        "--paper-900": paper900,
        "--paper-950": paper950,
        "--pink-50": pink50,
        "--pink-100": pink100,
        "--pink-300": pink300,
        "--pink-400": pink400,
        "--pink-500": pink500,
        "--pink-600": pink600,
        "--pink-700": pink700,
        "--pink-900": pink900,
        "--ink-50": ink50,
        "--ink-100": ink100,
        "--ink-300": ink300,
        "--ink-400": ink400,
        "--ink-500": ink500,
        "--ink-600": ink600,
        "--ink-700": ink700,
        "--ink-900": ink900,
        "--earth-50": earth50,
        "--earth-100": earth100,
        "--earth-300": earth300,
        "--earth-400": earth400,
        "--earth-500": earth500,
        "--earth-600": earth600,
        "--earth-700": earth700,
        "--earth-900": earth900,
        "--dusk-50": dusk50,
        "--dusk-100": dusk100,
        "--dusk-300": dusk300,
        "--dusk-400": dusk400,
        "--dusk-500": dusk500,
        "--dusk-600": dusk600,
        "--dusk-700": dusk700,
        "--dusk-900": dusk900,
        "--peach-50": peach50,
        "--peach-300": peach300,
        "--peach-400": peach400,
        "--peach-600": peach600,
        "--peach-900": peach900,
        "--sage-50": sage50,
        "--sage-300": sage300,
        "--sage-400": sage400,
        "--sage-600": sage600,
        "--sage-900": sage900,
        "--amber-50": amber50,
        "--amber-300": amber300,
        "--amber-400": amber400,
        "--amber-600": amber600,
        "--amber-900": amber900,
        "--brick-50": brick50,
        "--brick-300": brick300,
        "--brick-400": brick400,
        "--brick-600": brick600,
        "--brick-900": brick900,
        "--peri-50": peri50,
        "--peri-300": peri300,
        "--peri-400": peri400,
        "--peri-600": peri600,
        "--peri-900": peri900,
        "--lav-50": lav50,
        "--lav-300": lav300,
        "--lav-400": lav400,
        "--lav-600": lav600,
        "--lav-900": lav900,
        "--plum-50": plum50,
        "--plum-300": plum300,
        "--plum-400": plum400,
        "--plum-600": plum600,
        "--plum-900": plum900,
    ]
}
