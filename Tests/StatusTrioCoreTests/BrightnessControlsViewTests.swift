import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

@MainActor
final class BrightnessControlsViewTests: XCTestCase {
    func testUpToThreeDisplaysNeedNoDisclosure() {
        for count in [0, 1, 3] {
            let state = BrightnessPanelState(rows: Self.rows(count))
            XCTAssertFalse(state.hasHiddenRows)
            XCTAssertEqual(state.visibleRows(expanded: false).map(\.id), state.rows.map(\.id))
        }
    }

    func testMoreThanThreeDisplaysCollapseAndExpandWithoutReordering() {
        for count in [4, 6] {
            let state = BrightnessPanelState(rows: Self.rows(count))
            XCTAssertTrue(state.hasHiddenRows)
            XCTAssertEqual(state.visibleRows(expanded: false).map(\.id), ["0", "1", "2"])
            XCTAssertEqual(state.visibleRows(expanded: true), state.rows)
            XCTAssertEqual(state.visibleRows(expanded: false).map(\.id), ["0", "1", "2"])
        }
    }

    func testCollapsedHostingCreatesOnlyThreeSliders() throws {
        let host = try host(rows: Self.rows(6))
        XCTAssertEqual(sliders(in: host).count, 3)
    }

    func testIdenticalDisplayNamesAreNumberedWithoutChangingTheirIdentity() {
        let state = BrightnessPanelState(rows: Self.rows(2, name: "Studio Display"))
        XCTAssertEqual(state.displayName(for: state.rows[0], builtInName: "Built-in"), "Studio Display · 1")
        XCTAssertEqual(state.displayName(for: state.rows[1], builtInName: "Built-in"), "Studio Display · 2")
        XCTAssertEqual(state.rows.map(\.name), ["Studio Display", "Studio Display"])
        XCTAssertEqual(state.rows.map(\.id), ["0", "1"])
    }

    func testThinSlidersKeepThirtyPointRowsForLongDisplayNames() throws {
        var heights: [CGFloat] = []
        for value in [0.0, 0.5, 1.0] {
            let row = Self.rows(1, scalar: value, name: "LG UltraFine 5K Display With A Very Long Name")
            let host = try host(rows: row)
            let slider = try XCTUnwrap(sliders(in: host).first)
            XCTAssertFalse(containsCapsule(in: host), "brightness uses the thin native slider")
            XCTAssertGreaterThanOrEqual(slider.bounds.width, 100)
            XCTAssertEqual(slider.doubleValue, value, accuracy: 0.01)
            XCTAssertEqual(slider.accessibilityLabel(), row[0].name)
            XCTAssertEqual(slider.accessibilityValue() as? String, row[0].percentageText)
            heights.append(host.fittingSize.height)
        }
        XCTAssertTrue(heights.allSatisfy { $0 <= 32 }, "display names must not create a second line")
        XCTAssertEqual(heights.min(), heights.max())
    }

    func testUnreadableValueRemainsDisabled() throws {
        let host = try host(rows: Self.rows(1, scalar: nil))
        let slider = try XCTUnwrap(sliders(in: host).first)
        XCTAssertFalse(slider.isAccessibilityEnabled())
    }

    func testAdjustmentKeysKeepEditingBoundariesButDisabledControlsDoNotEdit() throws {
        let slider = NativePanelLevelSliderControl()
        var boundaries: [Bool] = []
        slider.onEditingChanged = { boundaries = boundaries + [$0] }
        let rightArrow = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "\u{f703}",
            charactersIgnoringModifiers: "\u{f703}", isARepeat: false, keyCode: 124
        ))
        slider.keyDown(with: rightArrow)
        XCTAssertEqual(boundaries, [true, false])
        boundaries = []
        slider.isEnabled = false
        slider.keyDown(with: rightArrow)
        XCTAssertTrue(boundaries.isEmpty)
    }

    fileprivate static func rows(
        _ count: Int,
        scalar: Double? = 0.5,
        name: String? = nil
    ) -> [BrightnessRowState] {
        (0..<count).map { index in
            BrightnessRowState(
                id: String(index), name: name ?? "Display \(index)", isBuiltin: false,
                scalar: scalar, canAdjust: true, backend: .displayServices,
                source: .displayServices,
                percentageText: scalar.map { BrightnessPanelMapper.percentText($0) } ?? "",
                accessibilityLabel: name ?? "Display \(index) brightness", unavailableText: nil
            )
        }
    }

    private func host(rows: [BrightnessRowState]) throws -> NSView {
        let suite = "BrightnessControlsViewTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { TestUserDefaults.removeSuite(named: suite) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        let host = NSHostingView(rootView: BrightnessControlsView(
            state: BrightnessPanelState(rows: rows), actions: StatusPanelActions(),
            scrollTargets: PopoverScrollTargets(), onOpenDisplaySettings: {}
        ).frame(width: 302).environmentObject(localization))
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        return host
    }

    private func sliders(in view: NSView) -> [NSSlider] {
        (view as? NSSlider).map { [$0] } ?? view.subviews.flatMap { sliders(in: $0) }
    }

    private func containsCapsule(in view: NSView) -> Bool {
        view is PanelLevelSliderView || view.subviews.contains { containsCapsule(in: $0) }
    }
}

@MainActor
final class BrightnessControlsInteractionTests: VisibleUITestCase {
    func testDisclosureKeepsThreeDisplaysInMainAndShowsRemainingThreeBesideIt() async throws {
        let observation = NativeSubmenuInteractionObservation(label: "brightness-three-plus-three")
        let suite = "BrightnessControlsInteractionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removeTestSuite(named: suite) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        let coordinator = CascadingSubmenuCoordinator()
        let root = BrightnessControlsView(
            state: previewState,
            actions: StatusPanelActions(), scrollTargets: PopoverScrollTargets(),
            onOpenDisplaySettings: {}
        ).frame(width: 302).padding(14)
            .environmentObject(localization)
            .environment(\.cascadingSubmenuCoordinator, coordinator)
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
            .environment(\.colorScheme, .dark)
        let host = StatusPanelHostingController(rootView: root)
        let window = AnchoredStatusPanel()
        window.appearance = NSAppearance(named: .darkAqua)
        window.installContent(host, backgroundStyle: .solid)
        let anchorWindow = NSWindow(contentRect: NSRect(x: 250, y: 500, width: 330, height: 40),
                                    styleMask: .borderless, backing: .buffered, defer: false)
        anchorWindow.isReleasedWhenClosed = false
        let anchor = NSView(frame: anchorWindow.contentView!.bounds)
        anchorWindow.contentView!.addSubview(anchor)
        defer {
            window.close()
            anchorWindow.close()
            observation.finish()
        }
        window.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        try await Task.sleep(for: .milliseconds(100))
        let originalFrame = window.frame
        XCTAssertEqual(sliders(in: host.view).count, 3)
        try snapshot(window.contentView!, named: "main-collapsed")

        try pressDisclosure(host.view, in: window)
        try await Task.sleep(for: .milliseconds(100))
        let child = try XCTUnwrap(window.childWindows?.first as? AnchoredStatusPanel)
        XCTAssertTrue(child.isShown)
        XCTAssertEqual(sliders(in: host.view).count, 3)
        XCTAssertEqual(sliders(in: try XCTUnwrap(child.contentView)).count, 3)
        XCTAssertEqual(window.frame, originalFrame, "opening overflow leaves the main panel fixed")
        XCTAssertTrue(child.frame.minX >= window.frame.maxX + StatusPanelPlacement.gap
            || child.frame.maxX <= window.frame.minX - StatusPanelPlacement.gap)
        try snapshot(window.contentView!, named: "main-with-child")
        try snapshot(child.contentView!, named: "child-three-displays")
        try snapshotGroup(parent: window, child: child)
        let geometry = "main=\(NSStringFromRect(window.frame)) child=\(NSStringFromRect(child.frame))"
        print("BRIGHTNESS_SUBMENU_PREVIEW \(geometry)")
        if let path = ProcessInfo.processInfo.environment["STATUS_TRIO_BRIGHTNESS_PREVIEW_DIR"] {
            try geometry.write(to: URL(fileURLWithPath: path).appendingPathComponent("geometry.txt"),
                               atomically: true, encoding: .utf8)
        }

        child.cancelOperation(nil)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(child.isShown)
        XCTAssertTrue(window.isShown)
        XCTAssertFalse(coordinator.hasOpenChild)
        XCTAssertEqual(sliders(in: host.view).count, 3)
        XCTAssertEqual(window.frame, originalFrame)
        try pressDisclosure(host.view, in: window)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(window.childWindows?.count, 1, "the entry can reopen after child Escape")
        window.close()
        XCTAssertFalse(coordinator.hasOpenChild)
        XCTAssertTrue(window.childWindows?.isEmpty ?? true)
    }

    private var previewState: BrightnessPanelState {
        let names = ["Built-in Retina Display", "Dell U2723QE", "LG UltraFine 5K",
                     "Studio Display", "Dell U2723QE", "BenQ PD3220U"]
        let levels = [0.72, 0.52, 0.85, 0.42, 0.7, 0.65]
        return BrightnessPanelState(rows: names.enumerated().map { index, name in
            BrightnessRowState(
                id: String(index), name: name, isBuiltin: index == 0,
                scalar: levels[index], canAdjust: true, backend: .displayServices,
                source: .displayServices,
                percentageText: BrightnessPanelMapper.percentText(levels[index]),
                accessibilityLabel: name, unavailableText: nil
            )
        })
    }

    private func pressDisclosure(_ host: NSView, in window: NSWindow) throws {
        let y = host.isFlipped ? host.bounds.maxY - 27 : host.bounds.minY + 27
        let point = host.convert(NSPoint(x: host.bounds.midX, y: y), to: nil)
        func event(_ type: NSEvent.EventType) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0
            ))
        }
        let down = try event(.leftMouseDown)
        let up = try event(.leftMouseUp)
        NSApp.postEvent(up, atStart: true)
        window.sendEvent(down)
        if let pending = NSApp.nextEvent(matching: .leftMouseUp, until: Date().addingTimeInterval(0.01),
                                        inMode: .eventTracking, dequeue: true) {
            window.sendEvent(pending)
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        host.layoutSubtreeIfNeeded()
    }

    private func sliders(in view: NSView) -> [NSSlider] {
        (view as? NSSlider).map { [$0] } ?? view.subviews.flatMap { sliders(in: $0) }
    }

    private func snapshot(_ host: NSView, named name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["STATUS_TRIO_BRIGHTNESS_PREVIEW_DIR"] else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent("\(name).png"))
    }

    /// Render fresh native view caches together at their observed window offsets.
    /// This contains only this fixture's parent/child content, never the desktop.
    private func snapshotGroup(parent: NSWindow, child: NSWindow) throws {
        guard let path = ProcessInfo.processInfo.environment["STATUS_TRIO_BRIGHTNESS_PREVIEW_DIR"] else { return }
        let bounds = parent.frame.union(child.frame)
        let scale = parent.backingScaleFactor
        let canvas = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * scale),
            pixelsHigh: Int(bounds.height * scale), bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        canvas.size = bounds.size
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: canvas))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        for window in [parent, child] {
            let view = try XCTUnwrap(window.contentView)
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            bitmap.draw(in: NSRect(
                x: window.frame.minX - bounds.minX, y: window.frame.minY - bounds.minY,
                width: window.frame.width, height: window.frame.height
            ))
        }
        context.flushGraphics()
        let png = try XCTUnwrap(canvas.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: path).appendingPathComponent("native-six-display-group.png"))
    }
}
