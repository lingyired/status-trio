import AppKit
import Combine
import SwiftUI
import XCTest
@testable import StatusTrioCore

private let footerHeight: CGFloat = 40

/// Real-window coverage for measurement-driven status-panel layout. The
/// content is synthetic and `VisibleUITestCase` skips this suite by default.
@MainActor
final class StatusPanelLayoutIntegrationTests: VisibleUITestCase {
    func testThirtyRapidAlternatingResizesKeepTheLastIntentAndConverge() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.pump(0.3)

        let collapsedHeight = fixture.panel.frame.height
        let anchoredEdge = fixture.panel.frame.maxY
        fixture.resetSamples()
        for index in 0..<30 {
            try fixture.press()
            fixture.pump([0.02, 0.05, 0.08, 0.03][index % 4])
        }
        fixture.pump(0.8)

        XCTAssertFalse(fixture.state.isExpanded)
        XCTAssertEqual(fixture.panel.frame.height, collapsedHeight, accuracy: 1)
        XCTAssertEqual(fixture.panel.frame.maxY, anchoredEdge, accuracy: 1)
        try fixture.assertFitsContent()
        fixture.assertContinuous()
#if DEBUG
        let writesAtSettle = fixture.panel.frameWriteCount
        fixture.pump(0.2)
        XCTAssertEqual(fixture.panel.frameWriteCount, writesAtSettle)
#endif
    }

    func testImmediateReversalDuringCollapseEndsAtTheLatestTarget() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.pump(0.3)

        let collapsedHeight = fixture.panel.frame.height
        let anchoredEdge = fixture.panel.frame.maxY
        fixture.resetSamples()
        try fixture.press()
        fixture.pump(0.1)
        try fixture.press()
        fixture.pump(0.025)
        try fixture.press()
        fixture.pump(0.8)

        XCTAssertTrue(fixture.state.isExpanded)
        XCTAssertGreaterThan(fixture.panel.frame.height, collapsedHeight + 80)
        XCTAssertEqual(fixture.panel.frame.maxY, anchoredEdge, accuracy: 1)
        try fixture.assertFitsContent()
        fixture.assertContinuous()
    }

    func testOversizedExpansionUsesTheScreenBudgetAndKeepsTheFooterVisible() throws {
        let visibleHeight = NSScreen.main?.visibleFrame.height ?? 900
        let fixture = try Fixture(extraHeight: max(0, visibleHeight - 420))
        defer { fixture.close() }
        fixture.pump(0.3)

        let anchoredEdge = fixture.panel.frame.maxY
        let maximumHeight = try XCTUnwrap(fixture.panel.layoutMetrics.maximumPanelHeight)
        fixture.resetSamples()
        try fixture.press()
        fixture.pump(0.8)

        let naturalHeight = try XCTUnwrap(fixture.contentNaturalHeight()) + footerHeight
        XCTAssertGreaterThan(naturalHeight, maximumHeight + 1)
        XCTAssertLessThanOrEqual(fixture.panel.frame.height, maximumHeight + 1)
        XCTAssertEqual(
            fixture.panel.frame.height,
            fixture.panel.layoutMetrics.contentHeight ?? -1,
            accuracy: 1
        )
        XCTAssertEqual(fixture.panel.frame.maxY, anchoredEdge, accuracy: 1)
        let footer = try XCTUnwrap(fixture.footerFrame())
        XCTAssertGreaterThanOrEqual(footer.minY, -1)
        XCTAssertLessThanOrEqual(footer.maxY, fixture.panel.frame.height + 1)
        fixture.assertContinuous()
    }

    func testBottomPlacementKeepsItsActualSelectedEdgeDuringRapidChanges() throws {
        let fixture = try Fixture(anchorAtBottom: true)
        defer { fixture.close() }
        fixture.pump(0.3)

        let selectedBottomEdge = fixture.panel.frame.minY
        fixture.resetSamples()
        try fixture.press()
        fixture.pump(0.07)
        try fixture.press()
        fixture.pump(0.03)
        try fixture.press()
        fixture.pump(0.7)

        XCTAssertTrue(fixture.state.isExpanded)
        XCTAssertEqual(fixture.panel.frame.minY, selectedBottomEdge, accuracy: 1)
        try fixture.assertFitsContent()
        fixture.assertContinuous(keepsBottomEdge: true)
    }

#if DEBUG
    func testClosingDuringRapidChangesStopsAllFrameWrites() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.pump(0.3)
        try fixture.press()
        fixture.pump(0.03)
        try fixture.press()
        fixture.pump(0.02)

        fixture.panel.close()
        let writesAtClose = fixture.panel.frameWriteCount
        fixture.pump(0.4)
        XCTAssertFalse(fixture.panel.isVisible)
        XCTAssertEqual(fixture.panel.frameWriteCount, writesAtClose)
    }
#endif

    @MainActor
    private final class DisclosureState: ObservableObject {
        @Published private(set) var isExpanded = false

        func toggle() {
            isExpanded.toggle()
        }
    }

    private struct Page: View {
        @ObservedObject var metrics: StatusPanelLayoutMetrics
        @ObservedObject var state: DisclosureState
        @StateObject private var disclosure = StatusPanelResizeCoordinator()
        @Environment(\.displayScale) private var displayScale
        let extraHeight: CGFloat

        var body: some View {
            StatusPanelScrollArea(
                maximumHeight: metrics.maximumPanelHeight,
                fillsWindow: metrics.fillsWindow,
                onNaturalHeight: { metrics.measure(contentHeight: $0) }
            ) {
                VStack(spacing: 0) {
                    Button(action: { state.toggle() }) {
                        Text("Toggle")
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Color.clear.frame(height: 72 + disclosure.presentedHeight)
                    Color.clear.frame(height: extraHeight)
                    Marker(kind: .contentEnd).frame(height: 1)
                }
                .padding(14)
            } footer: {
                Marker(kind: .footer).frame(height: footerHeight)
            }
            .frame(width: 330)
            .transaction { $0.animation = nil }
            .onAppear { disclosure.pixelScale = displayScale }
            .onChange(of: state.isExpanded) { expanded in
                disclosure.retarget(to: expanded ? 268 : 0,
                                    fromHeight: disclosure.presentedHeight)
            }
            .onDisappear { disclosure.cancel() }
        }
    }

    private final class MarkerView: NSView {
        enum Kind { case footer, contentEnd }
        let kind: Kind
        init(kind: Kind) {
            self.kind = kind
            super.init(frame: .zero)
        }
        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }
    }

    private struct Marker: NSViewRepresentable {
        let kind: MarkerView.Kind
        func makeNSView(context: Context) -> MarkerView { MarkerView(kind: kind) }
        func updateNSView(_ view: MarkerView, context: Context) {}
    }

    @MainActor
    private final class Fixture {
        let panel: AnchoredStatusPanel
        let state: DisclosureState
        let host: StatusPanelHostingController<AnyView>
        let anchorWindow: NSWindow
        private let originalActivationPolicy: NSApplication.ActivationPolicy
        private let focusProbe = FocusProbe()
        private var displayObserver: NSObjectProtocol?
        private var recordsDisplayFrames = false
        private var samples: [Sample] = []
        private var displayedFooters: [CGFloat] = []
        private var displayedRowEnds: [DisplayedRowEnd] = []

        private struct Sample {
            let time: TimeInterval
            let height: CGFloat
            let topEdge: CGFloat
        }

        private struct DisplayedRowEnd {
            let y: CGFloat
            let height: CGFloat
            let fits: Bool
        }

        init(extraHeight: CGFloat = 0, anchorAtBottom: Bool = false) throws {
            _ = NSApplication.shared
            originalActivationPolicy = NSApp.activationPolicy()
            XCTAssertTrue(NSApp.setActivationPolicy(.accessory))
            NSApp.finishLaunching()

            let panel = AnchoredStatusPanel()
            let state = DisclosureState()
            self.panel = panel
            self.state = state
            host = StatusPanelHostingController(
                rootView: AnyView(Page(metrics: panel.layoutMetrics, state: state, extraHeight: extraHeight))
            )
            panel.installContent(host, backgroundStyle: .solid)
            panel.isFloatingPanel = false
            panel.level = .normal
            panel.disablesKeyWindowForTesting = true
            panel.avoidsOrderFrontRegardlessForTesting = true

            let screen = try XCTUnwrap(NSScreen.main)
            let anchorWindow = NSWindow(
                contentRect: NSRect(
                    x: screen.visibleFrame.midX,
                    y: anchorAtBottom ? screen.visibleFrame.minY : screen.visibleFrame.maxY - 30,
                    width: 24,
                    height: 20
                ),
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            anchorWindow.isReleasedWhenClosed = false
            let anchorView = NSView(frame: NSRect(x: 0, y: 0, width: 24, height: 20))
            anchorWindow.contentView = anchorView
            self.anchorWindow = anchorWindow
            panel.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)

            displayObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didUpdateNotification,
                object: panel,
                queue: nil
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.recordDisplayedFrame() }
            }
        }

        func press() throws {
            // Local window events exercise the SwiftUI button without the
            // highlight delay in NSButton.performClick or any global input.
            let local = NSPoint(x: host.view.bounds.midX,
                                y: host.view.isFlipped ? 32 : host.view.bounds.height - 32)
            let point = host.view.convert(local, to: nil)
            _ = try XCTUnwrap(panel.contentView?.hitTest(point))
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try XCTUnwrap(NSEvent.mouseEvent(
                    with: type, location: point, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: panel.windowNumber, context: nil,
                    eventNumber: 0, clickCount: 1, pressure: 1
                ))
                panel.sendEvent(event)
            }
            XCTAssertFalse(panel.isKeyWindow)
        }

        func pump(_ seconds: TimeInterval) {
            let deadline = Date().addingTimeInterval(seconds)
            let timer = Timer(timeInterval: 0.004, repeats: true) { [self] _ in
                MainActor.assumeIsolated {
                    samples.append(.init(
                        time: ProcessInfo.processInfo.systemUptime,
                        height: panel.frame.height,
                        topEdge: panel.frame.maxY
                    ))
                    if Date() >= deadline { NSApp.stop(nil) }
                    if let event = NSEvent.otherEvent(
                        with: .applicationDefined,
                        location: .zero,
                        modifierFlags: [],
                        timestamp: 0,
                        windowNumber: 0,
                        context: nil,
                        subtype: 0,
                        data1: 0,
                        data2: 0
                    ) {
                        NSApp.postEvent(event, atStart: false)
                    }
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            NSApp.run()
            timer.invalidate()
        }

        func resetSamples() {
            samples = [.init(
                time: ProcessInfo.processInfo.systemUptime,
                height: panel.frame.height,
                topEdge: panel.frame.maxY
            )]
            displayedFooters = []
            displayedRowEnds = []
            recordsDisplayFrames = true
            if let y = rowEndY() {
                displayedRowEnds.append(.init(
                    y: y,
                    height: panel.frame.height,
                    fits: contentFitsBudget()
                ))
            }
        }

        func contentNaturalHeight() -> CGFloat? {
            Self.views(of: NSScrollView.self, in: host.view).first?.documentView?.frame.height
        }

        func footerFrame() -> NSRect? {
            guard let marker = Self.views(of: MarkerView.self, in: host.view)
                .first(where: { $0.kind == .footer }),
                  let root = panel.contentView else { return nil }
            return root.convert(marker.bounds, from: marker)
        }

        func assertFitsContent(file: StaticString = #filePath, line: UInt = #line) throws {
            let naturalHeight = try XCTUnwrap(contentNaturalHeight(), file: file, line: line)
                + footerHeight
            let expected = min(naturalHeight, panel.layoutMetrics.maximumPanelHeight ?? naturalHeight)
            XCTAssertEqual(panel.frame.height, expected, accuracy: 1, file: file, line: line)
            XCTAssertEqual(
                panel.frame.height,
                panel.layoutMetrics.contentHeight ?? -1,
                accuracy: 1,
                file: file,
                line: line
            )
        }

        func assertContinuous(
            keepsBottomEdge: Bool = false,
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            guard let first = samples.first else {
                return XCTFail("no window samples", file: file, line: line)
            }
            XCTAssertGreaterThan(samples.count, 2, file: file, line: line)
            let firstEdge = keepsBottomEdge ? first.topEdge - first.height : first.topEdge
            for sample in samples {
                let edge = keepsBottomEdge ? sample.topEdge - sample.height : sample.topEdge
                XCTAssertEqual(edge, firstEdge, accuracy: 1, file: file, line: line)
            }
            for (before, after) in zip(samples, samples.dropFirst()) {
                let elapsed = max(0, after.time - before.time)
                let budget = CGFloat(elapsed + 1.0 / 120.0) * 6_500 + 1
                XCTAssertLessThanOrEqual(
                    abs(after.height - before.height),
                    budget,
                    file: file,
                    line: line
                )
            }

            if let baseline = displayedRowEnds.first, baseline.fits {
                let baselineOffset = baseline.height - baseline.y
                for (before, after) in zip(displayedRowEnds, displayedRowEnds.dropFirst())
                    where after.fits {
                    let step = max(abs(after.height - before.height), abs(after.y - before.y))
                    let beforeOffset = before.height - before.y
                    let afterOffset = after.height - after.y
                    XCTAssertLessThanOrEqual(
                        abs(afterOffset - baselineOffset),
                        step + 1,
                        file: file,
                        line: line
                    )
                    XCTAssertLessThanOrEqual(
                        abs(beforeOffset - afterOffset),
                        step + 1,
                        file: file,
                        line: line
                    )
                }
                if let last = displayedRowEnds.last, last.fits {
                    XCTAssertEqual(
                        last.height - last.y,
                        baselineOffset,
                        accuracy: 1,
                        file: file,
                        line: line
                    )
                }
            }
            XCTAssertGreaterThan(displayedFooters.count, 2, file: file, line: line)
            for footerY in displayedFooters {
                XCTAssertEqual(
                    footerY,
                    0,
                    accuracy: 1,
                    "footer must stay on the window's bottom",
                    file: file,
                    line: line
                )
            }
        }

        func close() {
            recordsDisplayFrames = false
            panel.close()
            anchorWindow.close()
            if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }
            XCTAssertEqual(focusProbe.activations, 0)
            focusProbe.stop()
            NSApp.setActivationPolicy(originalActivationPolicy)
        }

        private func contentFitsBudget() -> Bool {
            let naturalHeight = contentNaturalHeight() ?? .infinity
            let maximumHeight = panel.layoutMetrics.maximumPanelHeight ?? .infinity
            return naturalHeight + footerHeight <= maximumHeight + 0.5
        }

        private func recordDisplayedFrame() {
            guard recordsDisplayFrames, let footer = footerFrame() else { return }
            displayedFooters.append(footer.minY)
            if let y = rowEndY() {
                displayedRowEnds.append(.init(
                    y: y,
                    height: panel.frame.height,
                    fits: contentFitsBudget()
                ))
            }
        }

        private func rowEndY() -> CGFloat? {
            guard let marker = Self.views(of: MarkerView.self, in: host.view)
                .first(where: { $0.kind == .contentEnd }) else { return nil }
            let rect = host.view.convert(marker.bounds, from: marker)
            return host.view.isFlipped ? rect.minY : host.view.bounds.height - rect.maxY
        }

        private static func views<T: NSView>(of type: T.Type, in root: NSView) -> [T] {
            if let match = root as? T {
                return [match] + root.subviews.flatMap { views(of: type, in: $0) }
            }
            return root.subviews.flatMap { views(of: type, in: $0) }
        }
    }

    @MainActor
    private final class FocusProbe {
        private(set) var activations = 0
        private var observer: NSObjectProtocol?

        init() {
            observer = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication
                guard app?.processIdentifier == ProcessInfo.processInfo.processIdentifier else {
                    return
                }
                MainActor.assumeIsolated { self?.activations += 1 }
            }
        }

        func stop() {
            if let observer {
                NSWorkspace.shared.notificationCenter.removeObserver(observer)
            }
            observer = nil
        }
    }
}
