import AppKit
import XCTest
@testable import StatusTrioCore

/// Task 4 of the input-source plan at the renderer: an input source's own icon
/// file has to take the centre slot without turning into a general drawing
/// framework, and the menu bar and the Dock have to land it on the same line.
@MainActor
final class InputSourceIconRenderingTests: XCTestCase {
    private let menuBarSize: CGFloat = 120
    private let menuBarScale: CGFloat = 8

    func testIconInkLandsOnTheCentreLineAcrossShapesScalesAndBackgrounds() throws {
        let fixtures: [(name: String, width: Int, height: Int, ink: CGRect, background: InputSourceIconFixtures.Background)] = [
            ("square", 64, 64, CGRect(x: 38, y: 12, width: 18, height: 30), .transparent),
            ("wide", 160, 40, CGRect(x: 96, y: 8, width: 48, height: 24), .transparent),
            ("tall", 40, 160, CGRect(x: 24, y: 20, width: 10, height: 100), .transparent),
            ("padded", 128, 128, CGRect(x: 78, y: 44, width: 34, height: 40), .transparent),
            ("opaque", 64, 64, CGRect(x: 0, y: 0, width: 64, height: 64), .opaque)
        ]
        let scales = [
            IconSymbolState.normalizedScale(0.8),
            SettingsStore.defaultWifiSymbolScale,
            2.2
        ]

        for fixture in fixtures {
            let url = try InputSourceIconFixtures.writeIcon(
                pixelWidth: fixture.width,
                pixelHeight: fixture.height,
                inkRect: fixture.ink,
                background: fixture.background
            )
            defer { try? FileManager.default.removeItem(at: url) }

            for scale in scales {
                let pixels = try renderedCenterPixels(for: centerScene(url: url, scale: scale))
                XCTAssertEqual(
                    try XCTUnwrap(pixels.horizontalAlphaMidpoint(size: menuBarSize, scale: menuBarScale)),
                    StatusIconGeometry.artworkCenterX,
                    accuracy: 0.5,
                    "\(fixture.name) icon at scale \(scale) must sit on the artwork centre line"
                )
            }
        }
    }

    /// Monochrome primitives are template-tinted on the real menu bar, so the
    /// tint the drawing handler receives flips with the appearance. The ink
    /// position must not: it is measured against the artwork, not the colour.
    func testIconInkKeepsTheCentreLineInLightAndDarkMenuBars() throws {
        let url = try InputSourceIconFixtures.writeIcon(
            pixelWidth: 96,
            pixelHeight: 48,
            inkRect: CGRect(x: 48, y: 8, width: 40, height: 32)
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let scene = centerScene(url: url, scale: SettingsStore.defaultWifiSymbolScale)

        let darkBar = try renderedCenterPixels(for: scene, foreground: CGColor(gray: 1, alpha: 1))
        let lightBar = try renderedCenterPixels(for: scene, foreground: CGColor(gray: 0.1, alpha: 1))

        for (name, pixels) in [("dark menu bar", darkBar), ("light menu bar", lightBar)] {
            XCTAssertEqual(
                try XCTUnwrap(pixels.horizontalAlphaMidpoint(size: menuBarSize, scale: menuBarScale)),
                StatusIconGeometry.artworkCenterX,
                accuracy: 0.5,
                "the \(name) tint must not move the icon's ink"
            )
        }
    }

    /// The menu bar redraws through a drawing handler on every display pass, so
    /// an unchanged input source has to come back from the decode cache instead
    /// of the file system. Removing the file between two renders makes a re-read
    /// fall through to the fallback symbol and change the pixels.
    func testRerenderReusesTheDecodedIconInsteadOfRereadingTheFile() throws {
        let url = try InputSourceIconFixtures.writeIcon(
            pixelWidth: 96,
            pixelHeight: 48,
            inkRect: CGRect(x: 48, y: 8, width: 40, height: 32)
        )
        let scene = centerScene(url: url, scale: SettingsStore.defaultWifiSymbolScale)

        let first = try renderedCenterPixels(for: scene)
        try FileManager.default.removeItem(at: url)
        let second = try renderedCenterPixels(for: scene)

        XCTAssertEqual(first.bytes, second.bytes)
        XCTAssertEqual(
            try XCTUnwrap(second.horizontalAlphaMidpoint(size: menuBarSize, scale: menuBarScale)),
            StatusIconGeometry.artworkCenterX,
            accuracy: 0.5
        )
    }

    /// 无图标 fallback: a source whose icon file is gone still fills the slot
    /// with its fallback symbol, on the same centre line.
    func testMissingIconFileFallsBackToItsSymbolOnTheCentreLine() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("status-trio-missing-\(UUID().uuidString).png")
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))

        let scene = centerScene(url: missing, scale: SettingsStore.defaultWifiSymbolScale)
        let pixels = try renderedCenterPixels(for: scene)

        XCTAssertEqual(
            try XCTUnwrap(pixels.horizontalAlphaMidpoint(size: menuBarSize, scale: menuBarScale)),
            StatusIconGeometry.artworkCenterX,
            accuracy: 0.5
        )
    }

    /// Real input sources hand over a PDF (`menu_icon.pdf`), not a bitmap. Its
    /// ink has no pixels to measure until the vector is rasterised, so this is
    /// the case that proves the measurement works on the file an IME ships.
    func testPDFInputSourceIconInkLandsOnTheCentreLine() throws {
        let url = try InputSourceIconFixtures.writePDFIcon(
            pointWidth: 48,
            pointHeight: 48,
            inkRect: CGRect(x: 20, y: 12, width: 26, height: 20)
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let scene = centerScene(url: url, scale: SettingsStore.defaultWifiSymbolScale)
        let rendered = try renderedCenterPixels(for: scene)

        XCTAssertEqual(
            try XCTUnwrap(rendered.horizontalAlphaMidpoint(size: menuBarSize, scale: menuBarScale)),
            StatusIconGeometry.artworkCenterX,
            accuracy: 0.5
        )
    }

    /// Menu bar / Dock parity: the Dock tile draws the same scene through the
    /// same renderer, so the input source's icon has to land on the same centre
    /// line there, in both tile styles.
    func testDockIconSharesTheMenuBarCentreLine() throws {
        let url = try InputSourceIconFixtures.writeIcon(
            pixelWidth: 96,
            pixelHeight: 48,
            inkRect: CGRect(x: 48, y: 8, width: 40, height: 32)
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let scene = centerScene(url: url, scale: SettingsStore.defaultWifiSymbolScale)

        let menuBar = try renderedCenterPixels(for: scene)
        XCTAssertEqual(
            try XCTUnwrap(menuBar.horizontalAlphaMidpoint(size: menuBarSize, scale: menuBarScale)),
            StatusIconGeometry.artworkCenterX,
            accuracy: 0.5
        )

        for style in [DockIconBackgroundStyle.dark, .light] {
            XCTAssertEqual(
                try dockCenterMidpoint(scene: scene, style: style),
                StatusIconGeometry.artworkCenterX,
                accuracy: 0.5,
                "the \(style) Dock tile must share the menu bar centre line"
            )
        }
    }

    private func centerScene(url: URL, scale: Double) -> IconSceneState {
        IconSceneState(center: .symbol(IconSymbolState(
            source: .image(url: url, fallbackSymbol: "keyboard"),
            color: .primary,
            scale: scale
        )))
    }

    private func renderedCenterPixels(
        for scene: IconSceneState,
        foreground: CGColor = CGColor(gray: 1, alpha: 1)
    ) throws -> PixelBuffer {
        let image = try XCTUnwrap(StatusIconRenderer.render(
            scene: scene,
            environment: StatusIconRenderEnvironment(
                size: menuBarSize,
                scale: menuBarScale,
                foreground: foreground,
                criticalColor: StatusIconRenderer.defaultCriticalColor
            )
        ))
        return try PixelBuffer(image: image)
    }

    /// The Dock tile carries its own opaque body, so the glyph is isolated by
    /// rendering the same tile without a centre slot and diffing the two: every
    /// differing pixel belongs to the icon. The result is converted back into
    /// the scene's own units, where every other centring assertion is written.
    private func dockCenterMidpoint(
        scene: IconSceneState,
        style: DockIconBackgroundStyle
    ) throws -> CGFloat {
        let withIcon = try dockPixels(scene: scene, style: style)
        let bare = try dockPixels(scene: IconSceneState(), style: style)
        XCTAssertEqual(withIcon.width, bare.width)
        XCTAssertEqual(withIcon.height, bare.height)

        let pixelsPerDesignUnit = CGFloat(withIcon.width) / DockIconGlyphLayout.designLength
        let designUnitsPerSceneUnit = DockIconGlyphLayout.glyphSVGSize
            / StatusIconGeometry.canvas.width

        var minX = withIcon.width
        var maxX = -1
        for y in 0..<withIcon.height {
            for x in 0..<withIcon.width where withIcon.rgba(x: x, y: y) != bare.rgba(x: x, y: y) {
                minX = min(minX, x)
                maxX = max(maxX, x)
            }
        }
        guard minX <= maxX else {
            XCTFail("the \(style) Dock tile drew no icon ink")
            return .nan
        }

        let midpointPixels = (CGFloat(minX) + CGFloat(maxX) + 1) / 2
        let designX = midpointPixels / pixelsPerDesignUnit
        return (designX - DockIconGlyphLayout.glyphSVGOrigin.x) / designUnitsPerSceneUnit
    }

    private func dockPixels(
        scene: IconSceneState,
        style: DockIconBackgroundStyle
    ) throws -> PixelBuffer {
        let image = try XCTUnwrap(DockIconRenderer.image(scene: scene, backgroundStyle: style))
        let representation = try XCTUnwrap(image.representations.first as? NSBitmapImageRep)
        return try PixelBuffer(image: try XCTUnwrap(representation.cgImage))
    }
}
