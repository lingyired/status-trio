import AppKit
import CoreAudio
import SwiftUI
import XCTest
@testable import StatusTrioCore

/// Window-local AppKit events on the production SwiftUI button. No global
/// events, pointer movement, key-window request or real AirPods are involved.
@MainActor
final class AirPodsDisclosureIntegrationTests: VisibleUITestCase {
    func testContentFollowingTheAirPodsContainerMovesContinuouslyWithItsWindow() throws {
        let f = try Fixture()
        defer { f.close() }
        f.pump(0.3)
        f.resetSamples()
        try f.press()
        f.pump(0.05)
        try f.press()
        f.pump(0.5)
        f.assertContinuous(file: #filePath, line: #line)
    }

    func testCollapseChangesTheLayoutTargetAtTheClickRatherThanAfterTheExit() throws {
        let source = ProgressiveSource()
        let f = try Fixture(controlsFactory: { source.makeControls($0) })
        defer { f.close() }
        f.pump(0.3)
        let collapsed = f.panel.frame.height
        try f.press()
        XCTAssertGreaterThan(source.backend.activeCount, 0)
        f.pump(0.02)
        let beforeCollapse = f.panel.frame.height
        XCTAssertGreaterThan(beforeCollapse, collapsed)
        f.resetSamples()
        try f.press()
        XCTAssertEqual(source.backend.activeCount, 0, "hardware demand stops on the click")
        f.pump(0.04)
        // Momentum can initially continue outward after reversing the target.
        // Requiring a height below the click position would demand a velocity
        // discontinuity. A declining segment proves collapse has already begun.
        XCTAssertTrue(zip(f.samples, f.samples.dropFirst()).contains { $1.height < $0.height },
                      "the actual container must start shrinking without a 170ms unload delay")
        f.pump(0.6)
        XCTAssertEqual(f.panel.frame.height, collapsed, accuracy: 1)
    }

    func testRapidDisclosureSchedulesConvergeWithoutFooterOrAnchorJumps() throws {
        // Times are actual intervals between local button clicks, including 50ms+30ms
        // and reversal during collapse. Last press always collapses.
        for intervals in [[0.02], [0.05, 0.03, 0.04], [0.10], [0.30, 0.06, 0.02]] {
            let f = try Fixture()
            defer { f.close() }
            f.pump(0.3)
            let collapsed = f.panel.frame.height
            f.resetSamples()
            try f.press()
            for interval in intervals {
                f.pump(interval)
                try f.press()
            }
            f.pump(0.8)
            XCTAssertEqual(f.panel.frame.height, collapsed, accuracy: 1)
            f.assertContinuous(file: #filePath, line: #line)
            try f.assertFitsContent()
            let writes = f.panel.frameWriteCount
            f.pump(0.15)
            XCTAssertEqual(f.panel.frameWriteCount, writes)
        }
    }

    func testThirtyRapidAlternatingPressesKeepTheLastIntent() throws {
        let source = ProgressiveSource()
        let f = try Fixture(controlsFactory: { source.makeControls($0) })
        defer { f.close() }
        f.pump(0.3)
        let collapsed = f.panel.frame.height
        f.resetSamples()
        for index in 0..<30 {
            try f.press()
            XCTAssertEqual(source.backend.activeCount > 0, index % 2 == 0,
                           "every individual click must update hardware demand immediately")
            f.pump([0.02, 0.05, 0.08, 0.03][index % 4])
            if index % 2 == 0 {
                XCTAssertGreaterThan(f.panel.frame.height, collapsed,
                                     "each expansion must enter the actual layout pipeline")
            }
        }
        f.pump(0.8)
        XCTAssertEqual(f.panel.frame.height, collapsed, accuracy: 1)
        f.assertContinuous(file: #filePath, line: #line)
        try f.saveArtifacts("thirty-clicks-collapsed")
        // Prove the retained disclosure can still expand after all reversals.
        try f.press()
        f.pump(0.8)
        XCTAssertGreaterThan(f.panel.frame.height, collapsed + 80)
        XCTAssertEqual(source.models.count, 1)
        try f.assertFitsContent()
        try f.saveArtifacts("thirty-clicks-expanded")
    }

    func testImmediateReversalBeforeTheFirstTickCannotReplayPendingGrowth() throws {
        let f = try Fixture()
        defer { f.close() }
        f.pump(0.3)
        let collapsed = f.panel.frame.height
        try f.press()
        try f.press()
        f.pump(0.6)
        XCTAssertEqual(f.panel.frame.height, collapsed, accuracy: 1)
        let writes = f.panel.frameWriteCount
        f.pump(0.2)
        XCTAssertEqual(f.panel.frameWriteCount, writes)
    }

    func testNativeBackgroundStylesUseTheSameWindowAndFooterTimeline() throws {
        for style in [PanelBackgroundStyle.solid, .classicMaterial, .liquidGlass] {
            let f = try Fixture(backgroundStyle: style)
            defer { f.close() }
            f.pump(0.3)
            let collapsed = f.panel.frame.height
            f.resetSamples()
            try f.press()
            f.pump(0.05)
            try f.press()
            f.pump(0.03)
            try f.press()
            f.pump(0.5)
            XCTAssertGreaterThan(f.panel.frame.height, collapsed + 80)
            f.assertContinuous(file: #filePath, line: #line)
        }
    }

    func testClosingDuringCollapseStopsAllFrameWrites() throws {
        let f = try Fixture()
        defer { f.close() }
        f.pump(0.3)
        try f.press()
        f.pump(0.3)
        try f.press()
        f.pump(0.04)
        f.panel.close()
        let writes = f.panel.frameWriteCount
        f.pump(0.4)
        XCTAssertEqual(f.panel.frameWriteCount, writes)
    }

    func testExpansionPastTheScreenBudgetKeepsFooterReachable() throws {
        let f = try Fixture(extraHeight: max(0, (NSScreen.main?.visibleFrame.height ?? 900) - 200))
        defer { f.close() }
        f.pump(0.3)
        try f.press()
        f.pump(0.8)
        let maximum = try XCTUnwrap(f.panel.layoutMetrics.maximumPanelHeight)
        XCTAssertLessThanOrEqual(f.panel.frame.height, maximum + 1)
        let footer = try XCTUnwrap(f.footerFrame())
        XCTAssertGreaterThanOrEqual(footer.minY, -1)
        XCTAssertLessThanOrEqual(footer.maxY, f.panel.frame.height + 1)
    }

    func testProgressiveDeviceUpdatesAndRowRefreshPreserveIntentAndOneControlsModel() throws {
        let source = ProgressiveSource()
        source.holdSecondBatch = true
        let f = try Fixture(controlsFactory: { source.makeControls($0) })
        defer { source.releaseSecondBatch(); f.close() }
        f.pump(0.3)
        let collapsed = f.panel.frame.height
        f.resetSamples()
        try f.press()
        f.pump(0.025)
        let original = f.data.rows[0]
        // A fresh row value from a device refresh keeps the same stable ID.
        var refreshed = original
        refreshed.volumeText = "65%"
        refreshed.helpText = "Refreshed device"
        f.data.rows = [refreshed]
        f.pump(0.04)
        XCTAssertTrue(source.secondBatchWaiting)
        XCTAssertTrue(try XCTUnwrap(source.models.first).busy)
        XCTAssertEqual(source.publications, 1)
        try f.press()
        XCTAssertEqual(source.backend.activeCount, 0, "collapse stops hardware before its visual transition")
        let cancelledSnapshot = try XCTUnwrap(source.models.first).snapshot
        source.releaseSecondBatch()
        f.pump(0.08)
        XCTAssertEqual(source.models.first?.snapshot, cancelledSnapshot,
                       "releasing a known in-flight cancelled batch must not publish")
        try f.press()
        f.pump(0.5)
        XCTAssertEqual(source.models.count, 1, "layout and row updates must not recreate the content model")
        XCTAssertEqual(source.reads, 2, "only user expansion restarts the read")
        XCTAssertGreaterThanOrEqual(source.publications, 3)
        XCTAssertTrue(try XCTUnwrap(source.models.first).snapshot.loaded)
        XCTAssertGreaterThan(f.panel.frame.height, collapsed + 80)
        f.assertContinuous(file: #filePath, line: #line)
        try f.press()
        let snapshotAtStop = try XCTUnwrap(source.models.first).snapshot
        f.pump(0.5)
        XCTAssertEqual(f.panel.frame.height, collapsed, accuracy: 1)
        XCTAssertEqual(source.backend.activeCount, 0)
        XCTAssertEqual(source.models.first?.snapshot, snapshotAtStop, "cancelled batches must not overwrite the stopped model")
    }

    func testClosingWhileExpandedReleasesTheControlsObservation() throws {
        let source = ProgressiveSource()
        let f = try Fixture(controlsFactory: { source.makeControls($0) })
        defer { f.close() }
        f.pump(0.3)
        try f.press()
        f.pump(0.04)
        XCTAssertGreaterThan(source.backend.activeCount, 0)
        f.panel.close()
        f.pump(0.2)
        XCTAssertEqual(source.backend.activeCount, 0)
        XCTAssertFalse(try XCTUnwrap(source.models.first).busy)
        let anchor = try XCTUnwrap(f.anchorWindow.contentView)
        f.panel.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        f.pump(0.2)
        XCTAssertEqual(source.models.count, 1)
        XCTAssertEqual(source.reads, 2)
        XCTAssertGreaterThan(source.backend.activeCount, 0)
    }

    func testClosedRetainedTreeDoesNotRestartHardwareForDeviceMetadataUpdates() throws {
        let source = ProgressiveSource()
        let f = try Fixture(controlsFactory: { source.makeControls($0) })
        defer { f.close() }
        f.pump(0.3)
        try f.press()
        f.pump(0.02)
        f.panel.close()
        let original = f.data.rows[0]
        f.data.rows = [.init(key: original.key, name: "Renamed AirPods", symbol: original.symbol,
                             selected: true, enabled: true, accessibilityLabel: "Renamed AirPods",
                             isPreview: true, supportsAirPodsSystemControls: true,
                             airPodsSpatialSupported: true, airPodsConversationSupported: true)]
        let writes = f.panel.frameWriteCount
        f.pump(0.3)
        XCTAssertEqual(source.backend.activeCount, 0, "a hidden retained row must not restart hardware")
        XCTAssertEqual(f.panel.frameWriteCount, writes)
    }

    func testChangingTheDisplayScaleRealignsTheRetainedRowsIntermediateHeights() throws {
        let f = try Fixture()
        defer { f.close() }
        f.pump(0.3)
        f.data.displayScale = 2
        try f.press()
        f.pump(0.04)
        f.data.displayScale = 1
        f.pump(0.03) // allow the new environment to reach the existing row
        f.resetSamples()
        f.pump(0.16)
        XCTAssertTrue(f.samples.contains { $0.height != f.samples.first?.height }, "must cover ongoing motion")
        for sample in f.samples {
            XCTAssertEqual(sample.height, sample.height.rounded(), accuracy: 0.01,
                           "the retained driver must adopt the new display's pixel grid")
        }
        f.pump(0.3)
        try f.assertFitsContent()
    }

    func testPlacementEnvironmentChangeReanchorsBeforeLockingTheNextMeasurement() throws {
        let f = try Fixture()
        defer { f.close() }
        f.pump(0.3)
        let top = f.panel.frame.maxY
        let origin = f.anchorWindow.frame.origin
        f.anchorWindow.setFrameOrigin(NSPoint(x: origin.x, y: origin.y - 200))
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        f.pump(0.2)
        XCTAssertEqual(f.panel.frame.maxY, top - 200, accuracy: 1)
        let newTop = f.panel.frame.maxY
        f.resetSamples()
        try f.press()
        f.pump(0.5)
        XCTAssertEqual(f.panel.frame.maxY, newTop, accuracy: 1)
        f.assertContinuous(file: #filePath, line: #line)
    }

    func testFlippedPlacementKeepsItsActuallySelectedBottomEdgeFixed() throws {
        let f = try Fixture(anchorAtBottom: true)
        defer { f.close() }
        f.pump(0.3)
        let edge = f.panel.frame.minY
        f.resetSamples()
        try f.press()
        f.pump(0.06)
        try f.press()
        f.pump(0.02)
        try f.press()
        f.pump(0.6)
        XCTAssertGreaterThan(f.panel.frame.height, 178)
        // In a flipped placement the actual bottom, not preferred .minY,
        // remains fixed throughout the full event/layout callback pipeline.
        for sample in f.samples {
            XCTAssertEqual(sample.edge - sample.height, edge, accuracy: 1)
        }
        f.assertContinuous(bottomAnchored: true, file: #filePath, line: #line)
    }

    func testGrowthNearAScreenEdgeScrollsWithoutFlippingOrLeavingTheScreen() throws {
        let f = try Fixture(anchorHeightAboveBottom: 180)
        defer { f.close() }
        f.pump(0.3)
        let collapsed = f.panel.frame.height
        let top = f.panel.frame.maxY
        f.resetSamples()
        try f.press()
        f.pump(0.6)
        let visible = try XCTUnwrap(f.panel.screen).visibleFrame
        for sample in f.samples {
            XCTAssertEqual(sample.edge, top, accuracy: 1)
            XCTAssertGreaterThanOrEqual(sample.edge - sample.height, visible.minY, "growth must scroll on its selected side")
        }
        XCTAssertLessThanOrEqual(f.panel.frame.height, 174)
        XCTAssertGreaterThan(f.panel.frame.height, collapsed + 40)
        XCTAssertEqual(f.panel.frame.height, try XCTUnwrap(f.panel.layoutMetrics.maximumPanelHeight), accuracy: 1)
        XCTAssertGreaterThan(try XCTUnwrap(f.contentNaturalHeight()), f.panel.frame.height - 40)
        f.assertContinuous(file: #filePath, line: #line)
    }

    func testImmediateHeightResizeUsesTheSameSelectedSideBudget() throws {
        let f = try Fixture(anchorHeightAboveBottom: 180, animatesContentResizes: false)
        defer { f.close() }
        f.pump(0.3)
        let top = f.panel.frame.maxY
        let collapsed = f.panel.frame.height
        try f.press()
        f.pump(0.2)
        XCTAssertEqual(f.panel.frame.maxY, top, accuracy: 1)
        XCTAssertGreaterThan(f.panel.frame.height, collapsed + 40)
        XCTAssertLessThanOrEqual(f.panel.frame.height, 174)
        XCTAssertEqual(f.panel.frame.height, try XCTUnwrap(f.panel.layoutMetrics.maximumPanelHeight), accuracy: 1)
    }

    private final class RowEndMarker: NSView {}
    private struct RowEnd: NSViewRepresentable {
        func makeNSView(context: Context) -> RowEndMarker { RowEndMarker() }
        func updateNSView(_ view: RowEndMarker, context: Context) {}
    }

    private final class FooterMarker: NSView {}
    private struct Footer: NSViewRepresentable {
        func makeNSView(context: Context) -> FooterMarker { FooterMarker() }
        func updateNSView(_ view: FooterMarker, context: Context) {}
    }

    private struct Page: View {
        @ObservedObject var metrics: StatusPanelLayoutMetrics
        @ObservedObject var data: RowData
        let extraHeight: CGFloat
        var controlsFactory: ((PanelAudioDeviceRow) -> AirPodsSystemControlsModel)?
        var body: some View {
            StatusPanelScrollArea(
                maximumHeight: metrics.maximumPanelHeight,
                fillsWindow: metrics.fillsWindow,
                onNaturalHeight: { metrics.measure(contentHeight: $0) }
            ) {
                VStack(spacing: 0) {
                    ForEach(data.rows) { row in
                        OutputDeviceRow(state: row, onSelect: {}, onSelectListeningMode: { _ in },
                                        controlsFactory: controlsFactory)
                    }
                    RowEnd().frame(height: 1)
                    Color.clear.frame(height: extraHeight)
                }
                .padding(14)
                .environment(\.statusPanelVisibility, metrics.visibilityPublisher)
            } footer: {
                Footer().frame(height: 40)
            }
            .frame(width: 330)
        }
    }

    @MainActor
    private final class Fixture {
        let panel = AnchoredStatusPanel()
        let host: StatusPanelHostingController<AnyView>
        let anchorWindow: NSWindow
        let localization: Localization
        let suite: String
        let data: RowData
        private let originalActivationPolicy: NSApplication.ActivationPolicy
        private let focusProbe = FocusProbe()
        var samples: [(time: TimeInterval, height: CGFloat, edge: CGFloat, footer: CGFloat)] = []
        private var displayedFooters: [CGFloat] = []
        private var displayedRowEnds: [(time: TimeInterval, y: CGFloat, height: CGFloat, fits: Bool)] = []
        private var recordsFooters = false
        private var displayObserver: NSObjectProtocol?
        private var pressCount = 0
        private let backgroundStyle: PanelBackgroundStyle
        let foregroundPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        init(
            extraHeight: CGFloat = 0,
            anchorAtBottom: Bool = false,
            anchorHeightAboveBottom: Optional<CGFloat> = nil,
            backgroundStyle: PanelBackgroundStyle = .solid,
            animatesContentResizes: Bool = true,
            controlsFactory: ((PanelAudioDeviceRow) -> AirPodsSystemControlsModel)? = nil
        ) throws {
            self.backgroundStyle = backgroundStyle
            _ = NSApplication.shared
            originalActivationPolicy = NSApp.activationPolicy()
            // SwiftPM test executables start with .prohibited and are absent
            // from NSWorkspace's app/AX registry. Accessory registers this test
            // process without activating it or adding a Dock icon.
            XCTAssertTrue(NSApp.setActivationPolicy(.accessory))
            NSApp.finishLaunching()
            suite = "AirPodsDisclosureIntegrationTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            localization = Localization(defaults: defaults, preferredLanguages: ["en"])
            let device = try XCTUnwrap(ListeningModePreview.outputRows(for: .init(
                isEnabled: true, deviceName: "AirPods Pro", deviceCount: 1, languageCode: "en"
            )).first)
            let row = PanelAudioDeviceRow(
                key: .init(id: device.id, uid: try XCTUnwrap(device.uid)), name: "AirPods Pro",
                symbol: .symbol(name: "airpodspro", variableValue: nil, fallback: nil),
                selected: true, enabled: true, accessibilityLabel: "AirPods Pro",
                isPreview: true,
                supportsAirPodsSystemControls: true,
                airPodsSpatialSupported: true,
                airPodsConversationSupported: true
            )
            data = RowData(rows: [row])
            host = StatusPanelHostingController(rootView: AnyView(
                Page(metrics: panel.layoutMetrics, data: data, extraHeight: extraHeight,
                     controlsFactory: controlsFactory)
                    .environmentObject(localization)
                    .environment(\.statusPanelAnimatesDisclosures, animatesContentResizes)
            ))
            panel.installContent(host, backgroundStyle: backgroundStyle)
            panel.becomesKeyOnlyIfNeeded = true
            let screen = try XCTUnwrap(NSScreen.main)
            anchorWindow = NSWindow(
                contentRect: NSRect(x: screen.visibleFrame.midX,
                                    y: anchorHeightAboveBottom.map { screen.visibleFrame.minY + $0 }
                                        ?? (anchorAtBottom ? screen.visibleFrame.minY : screen.visibleFrame.maxY - 30),
                                    width: 24, height: 20),
                styleMask: .borderless, backing: .buffered, defer: false
            )
            anchorWindow.isReleasedWhenClosed = false
            let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 24, height: 20))
            anchorWindow.contentView = anchor
            // The anchor window stays hidden. The nonactivating panel's normal
            // presentation never requests a key window or activates NSApp.
            panel.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
            // Observe completed native window updates for footer placement.
            // The 4ms timer also samples between resize and layout, which is
            // useful for frame motion but is not a displayed footer frame.
            displayObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didUpdateNotification, object: panel, queue: nil
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.recordsFooters, let footer = self.footerFrame() else { return }
                    self.displayedFooters.append(footer.minY)
                    if let y = self.rowEndY() {
                        let natural = self.contentNaturalHeight() ?? .infinity
                        let fits = natural + 40 <= (self.panel.layoutMetrics.maximumPanelHeight ?? .infinity) + 0.5
                        self.displayedRowEnds.append((ProcessInfo.processInfo.systemUptime, y, self.panel.frame.height, fits))
                    }
                    if abs(footer.minY) > 1 {
                        print("FOOTER TRACE style=\(self.backgroundStyle) click=\(self.pressCount) window=\(self.panel.frame) wrapper=\(String(describing: self.panel.contentView?.bounds)) host=\(self.host.view.frame) hostBounds=\(self.host.view.bounds) parent=\(String(describing: self.host.view.superview?.frame)) footer=\(footer) \(self.panel.resizeDiagnostics.debugDescription)")
                    }
                }
            }
        }

        func press() throws {
            pressCount += 1
            // Fixture layout: 14pt page inset and a 24x28pt disclosure at
            // the trailing edge of the first row. This is local view event
            // dispatch, never CGEventPost, a pointer warp or a global click.
            let local = NSPoint(x: host.view.bounds.width - 26,
                                y: host.view.isFlipped ? 28 : host.view.bounds.height - 28)
            let point = host.view.convert(local, to: nil)
            _ = try XCTUnwrap(panel.contentView?.hitTest(point))
            func event(_ type: NSEvent.EventType) throws -> NSEvent {
                try XCTUnwrap(NSEvent.mouseEvent(
                    with: type, location: point, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: panel.windowNumber, context: nil,
                    eventNumber: 0, clickCount: 1, pressure: 1
                ))
            }
            // NSWindow dispatch includes SwiftUI's gesture recognizers, which
            // a direct NSView.mouseDown call bypasses. Delivery stays entirely
            // in this test window; no system event queue receives these events.
            panel.sendEvent(try event(.leftMouseDown))
            panel.sendEvent(try event(.leftMouseUp))
            XCTAssertFalse(panel.isKeyWindow, "button clicks must not take keyboard focus")
        }

        func pump(_ seconds: TimeInterval) {
            let deadline = Date().addingTimeInterval(seconds)
            // NSApplication's event loop owns SwiftUI's AX and display service.
            // A bare CFRunLoop can size views but does not service remote AX.
            let timer = Timer(timeInterval: 0.004, repeats: true) { [self] _ in
                MainActor.assumeIsolated {
                    samples.append((ProcessInfo.processInfo.systemUptime, panel.frame.height, panel.frame.maxY, footerFrame()?.minY ?? 0))
                    if Date() >= deadline {
                        NSApp.stop(nil)
                    }
                    // Return nextEvent so NSApplication performs its ordinary
                    // window update/display cycle on each observation turn.
                    // A CFRunLoop timer alone does not return nextEvent.
                    if let event = NSEvent.otherEvent(
                        with: .applicationDefined, location: .zero, modifierFlags: [],
                        timestamp: 0, windowNumber: 0, context: nil,
                        subtype: 0, data1: 0, data2: 0
                    ) { NSApp.postEvent(event, atStart: false) }
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            NSApp.run()
            timer.invalidate()
        }

        func resetSamples() {
            samples = []
            displayedFooters = []
            displayedRowEnds = rowEndY().map {
                [(ProcessInfo.processInfo.systemUptime, $0, panel.frame.height,
                  (contentNaturalHeight() ?? .infinity) + 40 <= (panel.layoutMetrics.maximumPanelHeight ?? .infinity) + 0.5)]
            } ?? []
            recordsFooters = true
        }

        func footerFrame() -> NSRect? {
            func find(_ view: NSView) -> NSView? {
                if view is FooterMarker { return view }
                return view.subviews.lazy.compactMap { find($0) }.first
            }
            guard let marker = find(host.view), let root = panel.contentView else { return nil }
            return root.convert(marker.bounds, from: marker)
        }

        func rowEndY() -> Optional<CGFloat> {
            func find(_ view: NSView) -> NSView? {
                if view is RowEndMarker { return view }
                return view.subviews.lazy.compactMap { find($0) }.first
            }
            guard let marker = find(host.view) else { return nil }
            let rect = host.view.convert(marker.bounds, from: marker)
            return host.view.isFlipped ? rect.minY : host.view.bounds.height - rect.maxY
        }

        func contentNaturalHeight() -> Optional<CGFloat> {
            func find(_ view: NSView) -> NSScrollView? {
                if let scroll = view as? NSScrollView { return scroll }
                return view.subviews.lazy.compactMap { find($0) }.first
            }
            return find(host.view)?.documentView?.frame.height
        }

        func saveArtifacts(_ name: String) throws {
            guard let directory = ProcessInfo.processInfo.environment["STATUS_TRIO_UI_ARTIFACTS_DIR"] else { return }
            let root = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let rows = samples.map {
                "\($0.time),\($0.height),\($0.edge),\($0.footer)"
            }
            try (["uptime,window_height,top_edge,footer_window_y"] + rows).joined(separator: "\n")
                .write(to: root.appendingPathComponent(name + ".csv"), atomically: true, encoding: .utf8)
            if let view = panel.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?
                    .write(to: root.appendingPathComponent(name + ".png"))
            }
            let maxGap = zip(samples, samples.dropFirst()).map { $1.time - $0.time }.max() ?? 0
            print("AirPods real-window evidence: samples=\(samples.count) maxGapSeconds=\(maxGap) frameWrites=\(panel.frameWriteCount) scale=\(panel.backingScaleFactor) foregroundActivations=\(focusProbe.activations)")
        }

        func assertFitsContent(file: StaticString = #filePath, line: UInt = #line) throws {
            let natural = try XCTUnwrap(contentNaturalHeight(), file: file, line: line) + 40
            let expected = min(natural, panel.layoutMetrics.maximumPanelHeight ?? natural)
            XCTAssertEqual(panel.frame.height, expected, accuracy: 1, file: file, line: line)
        }

        func assertContinuous(bottomAnchored: Bool = false, file: StaticString, line: UInt) {
            guard let first = samples.first else { return XCTFail("no samples", file: file, line: line) }
            for sample in samples {
                let edge = bottomAnchored ? sample.edge - sample.height : sample.edge
                let firstEdge = bottomAnchored ? first.edge - first.height : first.edge
                XCTAssertEqual(edge, firstEdge, accuracy: 1, file: file, line: line)
            }
            for (before, after) in zip(samples, samples.dropFirst()) {
                // Allow actual elapsed time, rather than assuming the run loop
                // can sample at the requested frequency under build load.
                // The writer ticks at 120Hz; a 4ms observer can see an entire
                // 8.3ms motion step between two adjacent observations.
                let budget = CGFloat(after.time - before.time + 1.0 / 120) * 6500 + 1
                XCTAssertLessThanOrEqual(abs(after.height - before.height), budget, file: file, line: line)
            }
            if let baseline = displayedRowEnds.first, baseline.fits {
                for (before, sample) in zip(displayedRowEnds, displayedRowEnds.dropFirst()) where sample.fits {
                    // didUpdate is a native update notification, not an atomic
                    // compositor snapshot. The asynchronous measurement follower
                    // may be one layout step apart; it must never retain the
                    // final-height jump or a persistent offset from that clock.
                    let step = max(abs(sample.height - before.height), abs(sample.y - before.y))
                    XCTAssertLessThanOrEqual(abs((sample.height - sample.y) - (baseline.height - baseline.y)), step + 1,
                                             "window and disclosure must stay within one measured layout step", file: file, line: line)
                }
                if let last = displayedRowEnds.last, last.fits {
                    XCTAssertEqual(last.height - last.y, baseline.height - baseline.y, accuracy: 1,
                                   "no layout correction may remain after settling", file: file, line: line)
                }
            }
            for (before, after) in zip(displayedRowEnds, displayedRowEnds.dropFirst()) {
                let budget = CGFloat(after.time - before.time + 1.0 / 120) * 6500 + 1
                XCTAssertLessThanOrEqual(abs(after.y - before.y), budget,
                                        "content below AirPods must move with the disclosure, not jump to its target", file: file, line: line)
            }
            XCTAssertGreaterThan(displayedFooters.count, 2, "must observe actual displayed footer frames", file: file, line: line)
            for footer in displayedFooters {
                XCTAssertEqual(footer, 0, accuracy: 1, "displayed footer stays on the moving window's bottom", file: file, line: line)
            }
        }

        func close() {
            panel.close()
            anchorWindow.close()
            if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }
            XCTAssertEqual(focusProbe.activations, 0, "background fixture must not activate its process")
            focusProbe.stop()
            NSApp.setActivationPolicy(originalActivationPolicy)
            TestUserDefaults.removeSuite(named: suite)
        }
    }

    @MainActor
    private final class FocusProbe {
        private(set) var activations = 0
        private var observer: NSObjectProtocol?
        init() {
            observer = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { [weak self] notification in
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                if app?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
                    MainActor.assumeIsolated { self?.activations += 1 }
                }
            }
        }
        func stop() {
            if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
            observer = nil
        }
    }

    @MainActor
    private final class RowData: ObservableObject {
        @Published var displayScale: CGFloat = NSScreen.main?.backingScaleFactor ?? 1
        @Published var rows: [PanelAudioDeviceRow]
        init(rows: [PanelAudioDeviceRow]) { self.rows = rows }
    }

    @MainActor
    private final class ProgressiveSource {
        let backend = ListenerBackend()
        var models: [AirPodsSystemControlsModel] = []
        var reads = 0
        var publications = 0
        var holdSecondBatch = false
        private(set) var secondBatchWaiting = false
        private var secondBatch: CheckedContinuation<Void, Never>?

        func releaseSecondBatch() {
            holdSecondBatch = false
            secondBatch?.resume()
            secondBatch = nil
        }

        func makeControls(_ row: PanelAudioDeviceRow) -> AirPodsSystemControlsModel {
            let model = AirPodsSystemControlsModel(
                deviceID: row.key, deviceName: row.name,
                listenerBackend: backend, spatialReader: { [] },
                readSnapshot: { [weak self] publish in
                    guard let self else { return .init() }
                    reads += 1
                    var snapshot = AirPodsSystemSnapshot()
                    for stage in 1...3 {
                        if stage == 2, holdSecondBatch {
                            secondBatchWaiting = true
                            await withCheckedContinuation { secondBatch = $0 }
                            secondBatchWaiting = false
                        }
                        // Deliberately allow late publication attempts after
                        // cancellation; the real model must reject them.
                        try? await Task.sleep(for: .milliseconds(20))
                        snapshot.adaptive = stage == 1 ? 50 : 70
                        snapshot.conversation = [.init(title: "On", selected: true)]
                        snapshot.conversationLoaded = true
                        snapshot.loaded = stage == 3
                        publications += 1
                        publish(snapshot)
                    }
                    return snapshot
                }
            )
            models.append(model)
            return model
        }
    }

    private final class ListenerBackend: BluetoothListeningModePropertyListening, @unchecked Sendable {
        private let lock = NSLock()
        private var active: Set<AudioObjectPropertySelector> = []
        var activeCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return active.count
        }
        func addListener(deviceID: AudioDeviceID, address: AudioObjectPropertyAddress,
                         queue: DispatchQueue?, block: @escaping AudioObjectPropertyListenerBlock) -> OSStatus {
            lock.lock()
            defer { lock.unlock() }
            active.insert(address.mSelector)
            return noErr
        }
        func removeListener(deviceID: AudioDeviceID, address: AudioObjectPropertyAddress,
                            queue: DispatchQueue?, block: @escaping AudioObjectPropertyListenerBlock) -> OSStatus {
            lock.lock()
            defer { lock.unlock() }
            active.remove(address.mSelector)
            return noErr
        }
    }
}
