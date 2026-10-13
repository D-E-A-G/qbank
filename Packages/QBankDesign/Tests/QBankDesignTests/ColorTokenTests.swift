import Testing
@testable import QBankDesign

@Suite("Color tokens match the web")
struct ColorTokenTests {
    let web: WebTokens

    init() throws {
        web = try WebTokens(file: "colors")
    }

    @Test("Every semantic token equals the web value", arguments: QBankPalette.allCases, QBankAppearance.allCases)
    func semanticTokensMatch(palette: QBankPalette, appearance: QBankAppearance) throws {
        for token in QBankColorToken.allCases {
            let expected = try web.color(token.cssName, palette: palette, appearance: appearance)
            #expect(
                token.value(palette: palette, appearance: appearance) == expected,
                "\(token.cssName) in \(palette.rawValue) \(appearance.rawValue)"
            )
        }
    }

    @Test("Every semantic color the web defines has a Swift token")
    func noWebTokenIsMissing() throws {
        let themed = try #require(web.blocks["[data-theme=\"light\"]"]).keys
        let swiftNames = Set(QBankColorToken.allCases.map(\.cssName))
        #expect(Set(themed).subtracting(swiftNames).sorted() == [])
        let dark = try #require(web.blocks["[data-theme=\"dark\"]"]).keys
        #expect(Set(dark) == Set(themed))
    }

    @Test("Accent, guess and app icon ramps equal the web palette blocks", arguments: QBankPalette.allCases)
    func palettesMatch(palette: QBankPalette) throws {
        let accent = palette.accent
        let guess = palette.guess
        let expectations: [(String, QBankRGBA)] = [
            ("--accent-50", accent.shade50), ("--accent-100", accent.shade100),
            ("--accent-300", accent.shade300), ("--accent-400", accent.shade400),
            ("--accent-500", accent.shade500), ("--accent-600", accent.shade600),
            ("--accent-700", accent.shade700), ("--accent-900", accent.shade900),
            ("--accent-tint-dark", accent.tintDark), ("--accent-pressed-dark", accent.pressedDark),
            ("--accent-on-tint-dark", accent.onTintDark), ("--accent-soft-dark", accent.softDark),
            ("--accent-soft-border-dark", accent.softBorderDark),
            ("--guess-50", guess.shade50), ("--guess-300", guess.shade300), ("--guess-400", guess.shade400),
            ("--guess-600", guess.shade600), ("--guess-900", guess.shade900),
            ("--guess-border-dark", guess.borderDark),
            ("--icon-top", palette.appIcon.top), ("--icon-bottom", palette.appIcon.bottom),
            ("--icon-fg", palette.appIcon.foreground),
        ]
        for (name, value) in expectations {
            #expect(try web.color(name, palette: palette, appearance: .light) == value, "\(name) in \(palette.rawValue)")
        }
    }

    @Test("The web offers exactly these palettes, with dusk as the default")
    func paletteList() throws {
        let webPalettes = web.blocks.keys.compactMap { selector -> String? in
            guard selector.hasPrefix("[data-palette=\"") else { return nil }
            return String(selector.dropFirst(15).dropLast(2))
        }
        #expect(Set(webPalettes) == Set(QBankPalette.allCases.map(\.rawValue)))
        #expect(QBankPalette.default == .dusk)
        // :root (no data-palette) is dusk too.
        for token in QBankColorToken.allCases {
            let root = try WebTokens.color(WebTokens.resolve(token.cssName, in: web.blocks[":root"] ?? [:]))
            #expect(root == token.value(palette: .dusk, appearance: .light), "\(token.cssName) on :root")
        }
    }

    @Test("Values the design readme quotes")
    func readmeValues() {
        let tints: [(QBankPalette, UInt32, UInt32)] = [
            (.pink, 0xC93D74, 0xF07AA6), (.ink, 0x36598A, 0x9DB6D6),
            (.earth, 0xC2573F, 0xF0977E), (.dusk, 0x7C3F60, 0xC994AE),
        ]
        for (palette, light, dark) in tints {
            #expect(QBankColorToken.tint.value(palette: palette, appearance: .light) == QBankRGBA(light))
            #expect(QBankColorToken.tint.value(palette: palette, appearance: .dark) == QBankRGBA(dark))
        }
        #expect(QBankColorToken.bg.value(appearance: .light).hex == "#F7F4EE")
        #expect(QBankColorToken.surface.value(appearance: .light).hex == "#FFFFFF")
        #expect(QBankColorToken.surfaceSunken.value(appearance: .light).hex == "#EDE8DF")
        #expect(QBankColorToken.text1.value(appearance: .light).hex == "#1C1B18")
        #expect(QBankColorToken.text2.value(appearance: .light).hex == "#5C5750")
        #expect(QBankColorToken.bg.value(appearance: .dark).hex == "#0C0C0B")
        #expect(QBankColorToken.surface.value(appearance: .dark).hex == "#151412")
        #expect(QBankColorToken.surfaceRaised.value(appearance: .dark).hex == "#1C1B18")
        #expect(QBankColorToken.text1.value(appearance: .dark).hex == "#F3EFE8")
        #expect(QBankColorToken.text2.value(appearance: .dark).hex == "#B8B2A8")
    }

    @Test("Answer states are shared; only guessed follows the palette")
    func statesAreShared() {
        let shared: [QBankColorToken] = [.correct, .correctSoft, .correctBorder, .partial, .partialSoft,
                                         .partialBorder, .wrong, .wrongSoft, .wrongBorder]
        for appearance in QBankAppearance.allCases {
            for token in shared {
                let values = Set(QBankPalette.allCases.map { token.value(palette: $0, appearance: appearance) })
                #expect(values.count == 1, "\(token) differs between palettes")
            }
            let guesses = Set(QBankPalette.allCases.map { QBankColorToken.guess.value(palette: $0, appearance: appearance) })
            #expect(guesses.count == QBankPalette.allCases.count)
            for palette in QBankPalette.allCases {
                #expect(QBankColorToken.guess.value(palette: palette, appearance: appearance)
                    != QBankColorToken.tint.value(palette: palette, appearance: appearance))
            }
        }
    }

    @Test("CSS names follow the web's spelling")
    func cssNames() {
        #expect(QBankColorToken.text1.cssName == "--text-1")
        #expect(QBankColorToken.bgSidebar.cssName == "--bg-sidebar")
        #expect(QBankColorToken.textOnTint.cssName == "--text-on-tint")
        #expect(QBankColorToken.tintSoftBorder.cssName == "--tint-soft-border")
    }

    @Test("Hex and rgba formatting")
    func rgbaFormatting() {
        #expect(QBankRGBA(0x0C0C0B).hex == "#0C0C0B")
        #expect(QBankRGBA(0x7C3F60).description == "#7C3F60")
        #expect(QBankRGBA(red: 28, green: 27, blue: 24, alpha: 0.4).description == "rgba(28, 27, 24, 0.4)")
        #expect(QBankRGBA(0xFFFFFF, alpha: 2).alpha == 1)
    }
}
