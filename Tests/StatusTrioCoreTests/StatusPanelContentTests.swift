import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

/// The custom panel replaces `NSPopover` (issue #186). These pin the two pieces
/// that no longer come from AppKit: the SwiftUI content's sizing signal and the
/// window's key-window capability.
@MainActor
final class StatusPanelContentTests: XCTestCase {
    private struct FixedContent: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("Header")
                Divider()
                Text("Body")
            }
            .padding(14)
            .frame(width: 330)
        }
    }

    func testHostingControllerReportsTheFitSizeOnLayout() {
        let host = StatusPanelHostingController(rootView: FixedContent())
        var reported: [NSSize] = []
        host.onLayout = { reported.append($0) }

        host.view.layoutSubtreeIfNeeded()
        host.viewDidLayout()

        XCTAssertEqual(reported.count, 1)
        XCTAssertEqual(reported.first?.width, 330)
        XCTAssertGreaterThan(reported.first?.height ?? 0, 0)
        XCTAssertEqual(reported.first, host.view.fittingSize)
    }


    /// Issue #259: a hosting controller that has been replaced must stop driving
    /// the panel, even if it finishes a delayed layout pass afterwards.
    func testAReplacedHostIsNoLongerTheCurrentContent() {
        let panel = AnchoredStatusPanel()
        let first = StatusPanelHostingController(rootView: FixedContent())
        let second = StatusPanelHostingController(rootView: FixedContent())

        panel.installContent(first, backgroundStyle: .solid)
        XCTAssertTrue(panel.isCurrentContentHost(first))

        panel.installContent(second, backgroundStyle: .solid)
        XCTAssertFalse(panel.isCurrentContentHost(first), "a replaced host must not drive the panel")
        XCTAssertTrue(panel.isCurrentContentHost(second))
    }

    func testWrapperReportsTheSameIntrinsicSize() {
        let host = StatusPanelHostingController(rootView: FixedContent())
        let wrapper = StatusPanelContentViewController(hostingController: host, backgroundStyle: .solid)

        let size = wrapper.intrinsicContentSize

        XCTAssertEqual(size.width, 330)
        XCTAssertGreaterThan(size.height, 0)
        XCTAssertEqual(size.width, host.view.fittingSize.width)
    }

    func testReportsTheIdealContentHeightEvenWhenTheViewIsStretchedShort() {
        let host = StatusPanelHostingController(rootView: FixedContent())
        var reported: [NSSize] = []
        host.onLayout = { reported.append($0) }

        // Mimic the moment after leaving a shorter detail page: the hosting
        // view is still at the old height while the summary content is taller.
        host.view.frame = NSRect(x: 0, y: 0, width: 330, height: 40)
        host.view.layoutSubtreeIfNeeded()
        host.viewDidLayout()

        let ideal = host.sizeThatFits(in: NSSize(width: 330, height: CGFloat.greatestFiniteMagnitude))
        XCTAssertEqual(reported.last?.height ?? 0, ideal.height, accuracy: 0.5)
        XCTAssertGreaterThan(ideal.height, 40)
    }

    func testRootClipsRectangularDescendantsToThePanelCorners() throws {
        let host = StatusPanelHostingController(rootView: FixedContent())
        let wrapper = StatusPanelContentViewController(hostingController: host, backgroundStyle: .solid)
        let root = wrapper.view
        XCTAssertEqual(root.layer?.cornerRadius, AnchoredStatusPanel.cornerRadius)
        XCTAssertEqual(root.layer?.masksToBounds, true)

        root.frame = NSRect(x: 0, y: 0, width: 330, height: 120)
        root.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(root.bitmapImageRepForCachingDisplay(in: root.bounds))
        root.cacheDisplay(in: root.bounds, to: bitmap)

        // A rectangular descendant fills the root bounds; the root mask must
        // make the extreme corner transparent, otherwise the window shadow is
        // computed from a square silhouette.
        let cornerAlpha = bitmap.colorAt(x: 0, y: 0)?.alphaComponent ?? 1
        XCTAssertEqual(cornerAlpha, 0, accuracy: 0.001)
    }

    func testPanelCanBecomeKeyWithoutBecomingMain() {
        let panel = AnchoredStatusPanel()

        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertEqual(panel.collectionBehavior.contains(.fullScreenAuxiliary), true)
        XCTAssertEqual(panel.collectionBehavior.contains(.canJoinAllSpaces), true)
    }

    // MARK: - Background style (issue #233)

    private func makeWrapper(
        style: PanelBackgroundStyle,
        reduceTransparency: Bool = false
    ) -> StatusPanelContentViewController {
        let host = StatusPanelHostingController(rootView: FixedContent())
        return StatusPanelContentViewController(
            hostingController: host,
            backgroundStyle: style,
            isReduceTransparencyEnabled: { reduceTransparency }
        )
    }

    func testSolidBackgroundInstallsOpaqueFillBelowContent() {
        let wrapper = makeWrapper(style: .solid)
        let root = wrapper.view
        let backgroundIndex = root.subviews.firstIndex { $0 is SolidPanelBackgroundView }
        let contentIndex = root.subviews.firstIndex { $0 === wrapper.hostingController.view }

        XCTAssertNotNil(backgroundIndex, "solid style must add a SolidPanelBackgroundView")
        XCTAssertNotNil(contentIndex, "content host stays installed")
        if let backgroundIndex, let contentIndex {
            XCTAssertLessThan(backgroundIndex, contentIndex, "background sits behind content")
        }
    }

    func testReduceTransparencyForcesSolidBackground() {
        let wrapper = makeWrapper(style: .classicMaterial, reduceTransparency: true)
        let root = wrapper.view

        XCTAssertTrue(
            root.subviews.contains { $0 is SolidPanelBackgroundView },
            "Reduce Transparency must force the solid fill"
        )
        XCTAssertFalse(root.subviews.contains { $0 is NSVisualEffectView })
    }

    func testClassicMaterialInstallsPopoverVisualEffect() {
        let wrapper = makeWrapper(style: .classicMaterial)

        let effect = wrapper.view.subviews.compactMap { $0 as? NSVisualEffectView }.first
        XCTAssertNotNil(effect)
        XCTAssertEqual(effect?.material, .popover)
        XCTAssertEqual(effect?.blendingMode, .behindWindow)
    }

    func testLiquidGlassInstallsGlassOnSupportedSystem() throws {
        guard #available(macOS 26.0, *) else {
            throw XCTSkip("Liquid Glass needs macOS 26 or newer")
        }
        let wrapper = makeWrapper(style: .liquidGlass)

        XCTAssertTrue(
            wrapper.view.subviews.contains { $0 is NSGlassEffectView },
            "liquid glass style must add an NSGlassEffectView on macOS 26+"
        )
    }

    func testApplyingStyleSwapsBackgroundAndKeepsContent() {
        let wrapper = makeWrapper(style: .solid)
        let root = wrapper.view
        let content = wrapper.hostingController.view
        XCTAssertTrue(root.subviews.contains { $0 is SolidPanelBackgroundView })

        wrapper.applyBackgroundStyle(.classicMaterial)

        XCTAssertEqual(wrapper.backgroundStyle, .classicMaterial)
        XCTAssertFalse(root.subviews.contains { $0 is SolidPanelBackgroundView })
        XCTAssertTrue(root.subviews.contains { $0 is NSVisualEffectView })
        XCTAssertTrue(
            root.subviews.contains { $0 === content },
            "swapping the background must not replace the SwiftUI content"
        )
        XCTAssertNotNil(content.superview)
    }

    // MARK: - Reduce Transparency solid background (issue #234)

    func testSolidBackgroundResolvesWindowBackgroundForAquaAndDarkAqua() throws {
        let solid = SolidPanelBackgroundView(frame: NSRect(x: 0, y: 0, width: 320, height: 200))
        solid.wantsLayer = true

        solid.appearance = NSAppearance(named: .aqua)
        solid.updateLayer()
        let light = try XCTUnwrap(rgbComponents(of: solid))
        XCTAssertEqual(Double(light.red), 1.0, accuracy: 0.02)
        XCTAssertEqual(Double(light.green), 1.0, accuracy: 0.02)
        XCTAssertEqual(Double(light.blue), 1.0, accuracy: 0.02)

        solid.appearance = NSAppearance(named: .darkAqua)
        solid.updateLayer()
        let dark = try XCTUnwrap(rgbComponents(of: solid))
        XCTAssertEqual(Double(dark.red), 0.118, accuracy: 0.02)
        XCTAssertEqual(Double(dark.green), 0.118, accuracy: 0.02)
        XCTAssertEqual(Double(dark.blue), 0.118, accuracy: 0.02)
    }

    func testSolidBackgroundRepaintsWhenEffectiveAppearanceChanges() throws {
        let solid = SolidPanelBackgroundView(frame: NSRect(x: 0, y: 0, width: 320, height: 200))
        solid.wantsLayer = true
        solid.appearance = NSAppearance(named: .darkAqua)
        solid.updateLayer()
        let dark = try XCTUnwrap(rgbComponents(of: solid))

        solid.needsDisplay = false
        solid.appearance = NSAppearance(named: .aqua)
        solid.viewDidChangeEffectiveAppearance()

        solid.updateLayer()
        let light = try XCTUnwrap(rgbComponents(of: solid))
        XCTAssertGreaterThan(light.red, dark.red + 0.5)
    }

    private func rgbComponents(of view: NSView) -> (red: CGFloat, green: CGFloat, blue: CGFloat)? {
        guard
            let cgColor = view.layer?.backgroundColor,
            let color = NSColor(cgColor: cgColor)?.usingColorSpace(.deviceRGB)
        else { return nil }
        return (color.redComponent, color.greenComponent, color.blueComponent)
    }
}
