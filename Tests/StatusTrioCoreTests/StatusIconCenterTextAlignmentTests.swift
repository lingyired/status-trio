import AppKit
import CoreGraphics
import XCTest
@testable import StatusTrioCore

private typealias RGBA = (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)

@MainActor
final class StatusIconCenterTextAlignmentTests: XCTestCase {
    func testCenterTextInkBoundsStayCenteredForMenuBarAndDockRenderers() throws {
        let menuBarSizes: [CGFloat] = [24, 36, 160]
        let renderScales: [CGFloat] = [1, 1.5, 2]
        let textScales: [Double] = [1, 1.5, 2]
        let textValues = ["8", "80", "100"]

        for renderScale in renderScales {
            let dockPixelLength = Int((CGFloat(DockIconRenderer.pixelSize) * renderScale / 2).rounded())
            for textScale in textScales {
                for value in textValues {
                    let scene = IconSceneState(center: .text(IconTextState(
                        text: value,
                        color: .primary,
                        scale: textScale
                    )))

                    for menuBarSize in menuBarSizes {
                        let menuBarEnvironment = StatusIconRenderEnvironment(
                            size: menuBarSize,
                            scale: renderScale,
                            foreground: CGColor(gray: 1, alpha: 1),
                            criticalColor: StatusIconRenderer.defaultCriticalColor
                        )
                        let menuBarImage = try XCTUnwrap(StatusIconRenderer.render(
                            scene: scene,
                            environment: menuBarEnvironment
                        ))
                        let menuBarPixels = try PixelBuffer(image: menuBarImage)
                        let menuBarBounds = try XCTUnwrap(inkBounds(in: menuBarPixels) { $0.alpha >= 32 })
                        let menuBarPixelsPerSVGUnit = menuBarSize * renderScale / StatusIconGeometry.canvas.width
                        assertCentered(
                            menuBarBounds,
                            at: CGPoint(
                                x: StatusIconGeometry.artworkCenterX * menuBarPixelsPerSVGUnit,
                                y: 64 * menuBarPixelsPerSVGUnit
                            ),
                            tolerance: 1.5,
                            label: "menu bar \(menuBarSize)pt, raster scale \(renderScale), text scale \(textScale), text \(value)"
                        )
                    }

                    let dockImage = try XCTUnwrap(DockIconRenderer.image(
                        scene: scene,
                        backgroundStyle: .dark,
                        pixelLength: dockPixelLength
                    ))
                    let dockCGImage = try XCTUnwrap(
                        (dockImage.representations.first as? NSBitmapImageRep)?.cgImage
                    )
                    let dockPixels = try PixelBuffer(image: dockCGImage)
                    let dockBounds = try XCTUnwrap(inkBounds(in: dockPixels) { pixel in
                        pixel.red >= 240 && pixel.green >= 240 && pixel.blue >= 240
                    })
                    let dockPixelsPerDesignUnit = CGFloat(dockPixelLength) / DockIconGlyphLayout.designLength
                    assertCentered(
                        dockBounds,
                        at: CGPoint(
                            x: (DockIconGlyphLayout.glyphSVGOrigin.x
                                + StatusIconGeometry.artworkCenterX
                                    / StatusIconGeometry.canvas.width
                                    * DockIconGlyphLayout.glyphSVGSize) * dockPixelsPerDesignUnit,
                            y: (DockIconGlyphLayout.glyphSVGOrigin.y
                                + 64 / StatusIconGeometry.canvas.height
                                    * DockIconGlyphLayout.glyphSVGSize) * dockPixelsPerDesignUnit
                        ),
                        tolerance: 1.5,
                        label: "Dock raster scale \(renderScale), text scale \(textScale), text \(value)"
                    )
                }
            }
        }
    }

    private func inkBounds(
        in pixels: PixelBuffer,
        matches: (RGBA) -> Bool
    ) -> CGRect? {
        var minX = pixels.width
        var minY = pixels.height
        var maxX = -1
        var maxY = -1

        for y in 0..<pixels.height {
            for x in 0..<pixels.width where matches(pixels.rgba(x: x, y: y)) {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    private func assertCentered(
        _ bounds: CGRect,
        at expectedCenter: CGPoint,
        tolerance: CGFloat,
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let actualCenter = CGPoint(x: bounds.midX, y: bounds.midY)
        XCTAssertLessThanOrEqual(
            abs(actualCenter.x - expectedCenter.x),
            tolerance,
            "horizontal ink-bounds center for \(label): bounds=\(bounds), expected=\(expectedCenter)",
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            abs(actualCenter.y - expectedCenter.y),
            tolerance,
            "vertical ink-bounds center for \(label): bounds=\(bounds), expected=\(expectedCenter)",
            file: file,
            line: line
        )
    }
}
