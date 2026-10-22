#if canImport(SwiftUI)
import Foundation
import ImageIO
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import QBankDesign

/// Renders the component gallery to PNGs for a visual check. Runs only when
/// `QBANK_DESIGN_RENDER_DIR` names an output folder.
@Suite("Gallery render", .enabled(if: ProcessInfo.processInfo.environment["QBANK_DESIGN_RENDER_DIR"] != nil))
@MainActor
struct GalleryRenderTests {
    @Test("Gallery in every palette, light and dark", arguments: QBankPalette.allCases)
    func render(palette: QBankPalette) throws {
        let folder = try #require(ProcessInfo.processInfo.environment["QBANK_DESIGN_RENDER_DIR"])
        for scheme in [ColorScheme.light, .dark] {
            let renderer = ImageRenderer(
                content: QBankGallery()
                    .frame(width: 390)
                    .qbankPalette(palette)
                    .environment(\.colorScheme, scheme)
            )
            try write(renderer, to: folder, name: "gallery-\(palette.rawValue)-\(scheme == .dark ? "dark" : "light")")
        }
    }

    @Test("Gallery at the largest accessibility text size")
    func renderLargeText() throws {
        let folder = try #require(ProcessInfo.processInfo.environment["QBANK_DESIGN_RENDER_DIR"])
        let renderer = ImageRenderer(
            content: QBankGallery()
                .frame(width: 390)
                .environment(\.dynamicTypeSize, .accessibility5)
        )
        // The page is several screens tall at this size; 2x keeps the PNG within ImageIO's limits.
        try write(renderer, to: folder, name: "gallery-dusk-light-accessibility5", scale: 2)
    }

    @Test("The mark at the app icon's size, to lay over AppIcon.png")
    func renderMark() throws {
        let folder = try #require(ProcessInfo.processInfo.environment["QBANK_DESIGN_RENDER_DIR"])
        try write(ImageRenderer(content: QBankMark(size: 1024)), to: folder, name: "mark-1024", scale: 1)
    }

    private func write(_ renderer: ImageRenderer<some View>, to folder: String, name: String, scale: CGFloat = 3) throws {
        renderer.scale = scale
        let image = try #require(renderer.cgImage)
        print("\(name): \(image.width)x\(image.height)")
        let url = URL(fileURLWithPath: folder).appendingPathComponent("\(name).png")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }
}
#endif
