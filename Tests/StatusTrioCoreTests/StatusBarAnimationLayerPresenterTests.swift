import AppKit
import CoreGraphics
import Testing
@testable import StatusTrioCore

@MainActor
struct StatusBarAnimationLayerPresenterTests {
    @Test func installsOneLayerThenUpdatesItsCachedImageContents() throws {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
        let presenter = StatusBarAnimationLayerPresenter()
        let firstImage = try solidCGImage(color: CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        let secondImage = try solidCGImage(color: CGColor(red: 0, green: 1, blue: 0, alpha: 1))

        let firstResult = presenter.display(
            firstImage,
            in: view,
            contentSize: CGSize(width: 22, height: 22),
            backingScale: 2
        )
        #expect(firstResult == .installed)
        let contentsLayer = try #require(view.layer?.sublayers?.first)
        #expect(contentsLayer.frame == view.bounds)
        #expect(contentsLayer.contentsScale == 2)
        #expect((contentsLayer.contents as AnyObject?) === (firstImage as AnyObject))

        let secondResult = presenter.display(
            secondImage,
            in: view,
            contentSize: CGSize(width: 22, height: 22),
            backingScale: 2
        )
        #expect(secondResult == .updated)
        #expect(view.layer?.sublayers?.count == 1)
        #expect(view.layer?.sublayers?.first === contentsLayer)
        #expect((contentsLayer.contents as AnyObject?) === (secondImage as AnyObject))

        presenter.clear()
        #expect(view.layer?.sublayers?.contains(where: { $0 === contentsLayer }) != true)
        #expect(view.wantsLayer == false)
    }

    @Test func existingLayerTracksTheContentRectAndBackingScale() throws {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
        let presenter = StatusBarAnimationLayerPresenter()
        let firstImage = try solidCGImage(color: CGColor(gray: 1, alpha: 1))
        let resizedImage = try solidCGImage(color: CGColor(gray: 0.5, alpha: 1))

        _ = presenter.display(
            firstImage,
            in: view,
            contentSize: CGSize(width: 22, height: 22),
            backingScale: 2
        )
        let contentsLayer = try #require(view.layer?.sublayers?.first)
        view.frame = NSRect(x: 0, y: 0, width: 26, height: 20)

        let result = presenter.display(
            resizedImage,
            in: view,
            contentSize: CGSize(width: 22, height: 22),
            backingScale: 1
        )

        #expect(result == .updated)
        // The status item centres its image, so the overlay is centred on the
        // icon's own size rather than stretched to the button's bounds.
        #expect(contentsLayer.frame == CGRect(x: 2, y: -1, width: 22, height: 22))
        #expect(contentsLayer.contentsScale == 1)
        #expect((contentsLayer.contents as AnyObject?) === (resizedImage as AnyObject))
    }

    @Test func rejectsANonPositiveContentSize() throws {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
        let presenter = StatusBarAnimationLayerPresenter()
        let image = try solidCGImage(color: CGColor(gray: 1, alpha: 1))

        #expect(presenter.display(
            image,
            in: view,
            contentSize: CGSize(width: 0, height: 22),
            backingScale: 2
        ) == nil)
        #expect(view.layer?.sublayers?.isEmpty != false)
    }

    @Test func transparentPlaceholderPreservesSizeWithoutDoubleCompositing() throws {
        let placeholder = try #require(
            StatusIconRenderer.transparentMenuBarImage(size: 22, scale: 2)
        )
        let cgImage = try #require(placeholder.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        ))
        let pixels = try PixelBuffer(image: cgImage)

        #expect(placeholder.size == NSSize(width: 22, height: 22))
        #expect(cgImage.width == 44)
        #expect(cgImage.height == 44)
        #expect(pixels.bytes.allSatisfy { $0 == 0 })
    }

    private func solidCGImage(color: CGColor) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil,
            width: 2,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(color)
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        return try #require(context.makeImage())
    }
}
