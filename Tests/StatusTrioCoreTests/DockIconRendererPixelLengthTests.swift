import AppKit
import Testing
@testable import StatusTrioCore

@MainActor
struct DockIconRendererPixelLengthTests {
    @Test func keepsTheDockRasterByDefault() throws {
        let image = try #require(renderDockFixture(
                status: .placeholder))
        let representation = try #require(
            image.representations.first as? NSBitmapImageRep
        )

        #expect(DockIconRenderer.pixelSize == 512)
        #expect(DockIconRenderer.scale == 2)
        #expect(representation.pixelsWide == DockIconRenderer.pixelSize)
        #expect(representation.pixelsHigh == DockIconRenderer.pixelSize)
        #expect(image.size == NSSize(width: 256, height: 256))
        #expect(
            DockIconRenderer.logicalSize
                == CGFloat(DockIconRenderer.pixelSize) / DockIconRenderer.scale
        )
    }

    @Test func rendersAPreviewAtTheRequestedPixelLength() throws {
        let image = try #require(
            renderDockFixture(
                status: .placeholder, pixelLength: 112)
        )
        let representation = try #require(
            image.representations.first as? NSBitmapImageRep
        )

        #expect(representation.pixelsWide == 112)
        #expect(representation.pixelsHigh == 112)
        #expect(image.size == NSSize(width: 56, height: 56))
    }

    @Test func explicitDockPixelLengthMatchesTheDefaultRaster() throws {
        let legacy = try #require(renderDockFixture(
                status: .placeholder))
        let explicit = try #require(
            renderDockFixture(
                status: .placeholder,
                pixelLength: DockIconRenderer.pixelSize
            )
        )
        let legacyPixels = try pixels(of: legacy)
        let explicitPixels = try pixels(of: explicit)

        #expect(legacyPixels.bytes == explicitPixels.bytes)
    }

    @Test func aPreviewRasterKeepsTheSameArtwork() throws {
        let preview = try pixels(
            of: try #require(
                renderDockFixture(
                status: .placeholder, pixelLength: 128)
            )
        )
        let body = preview.rgba(
            x: preview.width * 12 / 100,
            y: preview.height / 2
        )

        #expect(preview.width == 128)
        #expect(body.alpha > 250)
        #expect(abs(Int(body.red) - 21) <= 3)
        #expect(abs(Int(body.green) - 21) <= 3)
        #expect(abs(Int(body.blue) - 23) <= 3)
    }

    @Test func reusesTheBufferAcrossLengths() throws {
        let firstPass = try pixels(
            of: try #require(
                renderDockFixture(
                status: .placeholder, pixelLength: 64)
            )
        )
        _ = try #require(
            renderDockFixture(
                status: .placeholder, pixelLength: 512)
        )
        let secondPass = try pixels(
            of: try #require(
                renderDockFixture(
                status: .placeholder, pixelLength: 64)
            )
        )

        #expect(firstPass.bytes == secondPass.bytes)
    }

    @Test func rejectsANonsensicalPixelLength() {
        #expect(renderDockFixture(
                status: .placeholder, pixelLength: 0) == nil)
        #expect(renderDockFixture(
                status: .placeholder, pixelLength: -8) == nil)
        #expect(renderDockFixture(
                status: .placeholder, pixelLength: 4096) == nil)
    }

    private func pixels(of image: NSImage) throws -> PixelBuffer {
        let representation = try #require(
            image.representations.first as? NSBitmapImageRep
        )
        return try PixelBuffer(image: try #require(representation.cgImage))
    }
}
