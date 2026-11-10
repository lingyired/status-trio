import AppKit
import Testing
@testable import StatusTrioCore

@MainActor
struct StatusBarTemplateImagePresenterTests {
    @Test func templateStaysCenteredWithoutInterceptingTheStatusButton() throws {
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 30, height: 24))
        let presenter = StatusBarTemplateImagePresenter()
        let image = templateImage(size: 22)

        presenter.display(image, in: host, contentSize: image.size)
        let imageView = try #require(host.subviews.first as? NSImageView)
        #expect(imageView.image === image)
        #expect(imageView.image?.isTemplate == true)
        #expect(imageView.frame == NSRect(x: 4, y: 1, width: 22, height: 22))
        #expect(imageView.isAccessibilityElement() == false)
        #expect(host.hitTest(NSPoint(x: 10, y: 10)) === host)

        host.setFrameSize(NSSize(width: 38, height: 30))
        #expect(imageView.frame == NSRect(x: 8, y: 4, width: 22, height: 22))

        let resized = templateImage(size: 26)
        presenter.display(resized, in: host, contentSize: resized.size)
        #expect(host.subviews.count == 1)
        #expect(host.subviews.first === imageView)
        #expect(imageView.image === resized)
        #expect(imageView.frame == NSRect(x: 6, y: 2, width: 26, height: 26))
    }

    @Test func movingAndClearingTheTemplateReleasesOnlyItsOwnView() {
        let first = NSView(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        let second = NSView(frame: first.frame)
        let unrelated = NSView(frame: first.bounds)
        first.addSubview(unrelated)
        let presenter = StatusBarTemplateImagePresenter()
        let image = templateImage(size: 22)

        weak var installedView: NSView?
        // AppKit's subview arrays are autoreleased; drain their temporary
        // ownership before checking that the presenter released the view.
        autoreleasepool {
            presenter.display(image, in: first, contentSize: image.size)
            #expect(first.subviews.count == 2)
            presenter.display(image, in: second, contentSize: image.size)
            #expect(first.subviews == [unrelated])
            #expect(second.subviews.count == 1)

            installedView = second.subviews.first
            presenter.clear()
            #expect(first.subviews == [unrelated])
            #expect(second.subviews.isEmpty)
        }
        #expect(installedView == nil)
        presenter.clear()
        #expect(second.subviews.isEmpty)
    }

    @Test func coloredLayerStaysAboveTheMonochromeRingTrack() throws {
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        let template = StatusBarTemplateImagePresenter()
        let overlay = StatusBarAnimationLayerPresenter()
        let image = templateImage(size: 28)
        template.display(image, in: host, contentSize: image.size)
        // AppKit can give the image view its own backing layer. Its stacking
        // order must still leave the status-colored ring above the track.
        host.subviews.first?.wantsLayer = true
        let cgImage = try #require(image.cgImage(
            forProposedRect: nil, context: nil, hints: nil
        ))
        _ = overlay.display(cgImage, in: host, contentSize: image.size, backingScale: 2)

        let layers = try #require(host.layer?.sublayers)
        let coloredLayer = try #require(layers.first {
            ($0.contents as AnyObject?) === (cgImage as AnyObject)
        })
        let imageLayer = try #require(host.subviews.first?.layer)
        #expect(coloredLayer.zPosition > imageLayer.zPosition)
        overlay.clear()
        #expect(host.subviews.count == 1)
        template.clear()
        #expect(host.subviews.isEmpty)
    }

    private func templateImage(size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
