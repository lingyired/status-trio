import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

/// Layout coverage for the panel's single scroll surface (#237): a short page
/// hugs its content, a tall page is capped and scrolls, and the footer stays
/// outside the scroll area either way.
@MainActor
final class StatusPanelScrollAreaTests: XCTestCase {
    func testShortPageHugsItsContentAndDoesNotScroll() throws {
        let fixture = makeFixture(contentHeight: 80, footerHeight: 40, cap: 300)

        let size = fixture.measuredSize()

        XCTAssertEqual(size.width, 330)
        XCTAssertEqual(size.height, 120, accuracy: 1)
        XCTAssertEqual(scrollViews(in: fixture.host.view).count, 1)
        let scrollView = try XCTUnwrap(scrollViews(in: fixture.host.view).first)
        XCTAssertFalse(scrollView.hasVerticalOverflow, "a short page must not scroll")
    }

    func testTallPageIsCappedAndScrolls() throws {
        let fixture = makeFixture(contentHeight: 600, footerHeight: 40, cap: 300)

        let size = fixture.measuredSize()

        XCTAssertEqual(size.width, 330)
        XCTAssertEqual(size.height, 300, accuracy: 1)
        let scrollView = try XCTUnwrap(
            scrollViews(in: fixture.host.view).first,
            "an overflowing page must scroll"
        )
        let documentHeight = try XCTUnwrap(scrollView.documentView?.frame.height)
        XCTAssertGreaterThan(documentHeight, 500)
        XCTAssertLessThan(
            scrollView.contentView.bounds.height,
            300 - 30,
            "the footer must keep its own space below the scroll viewport"
        )
    }

    func testTheFooterSitsOutsideTheScrollableViewport() throws {
        let fixture = makeFixture(contentHeight: 600, footerHeight: 40, cap: 300)
        let scrollView = try XCTUnwrap(scrollViews(in: fixture.host.view).first)
        let marker = try XCTUnwrap(
            firstView(ofType: FooterMarker.self, in: fixture.host.view)
        )

        XCTAssertNotNil(marker.superview)
        XCTAssertFalse(
            isDescendant(marker, of: scrollView.documentView),
            "the footer must not scroll away with the page"
        )
        let scrollFrame = fixture.host.view.convert(scrollView.bounds, from: scrollView)
        let markerFrame = fixture.host.view.convert(marker.bounds, from: marker)
        XCTAssertLessThanOrEqual(
            scrollFrame.minY,
            markerFrame.maxY,
            "the scroll viewport sits above the pinned footer"
        )
    }

    func testTallPageHidesTheSystemScrollerForTheSlimIndicator() throws {
        let fixture = makeFixture(contentHeight: 600, footerHeight: 40, cap: 300)
        let scrollView = try XCTUnwrap(scrollViews(in: fixture.host.view).first)

        // macOS fixes the overlay scroller at ~15pt; the panel hides it and
        // draws its own 4pt capsule while the wheel is moving (#237 follow-up).
        XCTAssertFalse(
            scrollView.hasVerticalScroller,
            "the native scroller must be hidden so only the slim indicator shows"
        )
        XCTAssertFalse(scrollView.hasHorizontalScroller)
    }

    func testPanelForcesOverlayChromeWhenTheSystemPrefersLegacyScrollers() throws {
        let fixture = makeFixture(contentHeight: 600, footerHeight: 40, cap: 300)
        let scrollView = try XCTUnwrap(scrollViews(in: fixture.host.view).first)
        let documentView = try XCTUnwrap(scrollView.documentView)
        let fullWidth = scrollView.bounds.width

        // Reproduce "Show scroll bars: Always". A legacy vertical scroller
        // removes its own gutter from the scrolling content.
        scrollView.scrollerStyle = .legacy
        scrollView.hasVerticalScroller = true
        scrollView.layoutSubtreeIfNeeded()

        // The panel draws its own 4pt overlay. Re-laying out the bridge must
        // force overlay chrome before hiding the system scroller, so the page
        // never keeps the legacy gutter as its horizontal layout.
        scrollView.needsLayout = true
        fixture.host.view.needsLayout = true
        settle(fixture.host)

        XCTAssertEqual(scrollView.scrollerStyle, .overlay)
        XCTAssertFalse(scrollView.hasVerticalScroller)
        XCTAssertEqual(scrollView.contentView.frame.width, fullWidth, accuracy: 0.5)
        XCTAssertEqual(documentView.frame.width, fullWidth, accuracy: 0.5)
    }

    // MARK: - Slim indicator geometry

    func testIndicatorIsAbsentWhenThePageFits() {
        XCTAssertNil(
            PanelScrollIndicatorMetrics(
                viewportHeight: 300,
                contentHeight: 300,
                offset: 0
            )
        )
        XCTAssertNil(
            PanelScrollIndicatorMetrics(
                viewportHeight: 300,
                contentHeight: 299,
                offset: 0
            )
        )
        XCTAssertNil(
            PanelScrollIndicatorMetrics(
                viewportHeight: 0,
                contentHeight: 600,
                offset: 0
            )
        )
    }

    func testIndicatorFollowsTheScrollProgress() throws {
        let start = try XCTUnwrap(
            PanelScrollIndicatorMetrics(
                viewportHeight: 300,
                contentHeight: 600,
                offset: 0
            )
        )
        XCTAssertEqual(start.thumbHeight, 150, accuracy: 0.5)
        XCTAssertEqual(start.thumbOffset, 0, accuracy: 0.5)

        let middle = try XCTUnwrap(
            PanelScrollIndicatorMetrics(
                viewportHeight: 300,
                contentHeight: 600,
                offset: 150
            )
        )
        XCTAssertEqual(middle.thumbOffset, 75, accuracy: 0.5)

        let end = try XCTUnwrap(
            PanelScrollIndicatorMetrics(
                viewportHeight: 300,
                contentHeight: 600,
                offset: 300
            )
        )
        XCTAssertEqual(end.thumbOffset, 150, accuracy: 0.5)

        let overscrolled = try XCTUnwrap(
            PanelScrollIndicatorMetrics(
                viewportHeight: 300,
                contentHeight: 600,
                offset: 900
            )
        )
        XCTAssertEqual(overscrolled.thumbOffset, 150, accuracy: 0.5)
    }

    func testIndicatorKeepsAMinimumThumbHeight() throws {
        let metrics = try XCTUnwrap(
            PanelScrollIndicatorMetrics(
                viewportHeight: 300,
                contentHeight: 6000,
                offset: 0
            )
        )

        XCTAssertEqual(metrics.thumbHeight, PanelScrollIndicatorMetrics.minimumThumbHeight)
        XCTAssertEqual(metrics.thumbOffset, 0, accuracy: 0.5)
    }

    func testScrollOffsetFollowsTheClipViewInBothOrientations() {
        // Flipped document (the SwiftUI hosting case): clip origin starts at 0.
        XCTAssertEqual(
            PanelScrollOffset.topOffset(
                documentHeight: 600,
                viewportHeight: 300,
                clipOriginY: 0,
                documentIsFlipped: true
            ),
            0
        )
        XCTAssertEqual(
            PanelScrollOffset.topOffset(
                documentHeight: 600,
                viewportHeight: 300,
                clipOriginY: 150,
                documentIsFlipped: true
            ),
            150
        )
        XCTAssertEqual(
            PanelScrollOffset.topOffset(
                documentHeight: 600,
                viewportHeight: 300,
                clipOriginY: 999,
                documentIsFlipped: true
            ),
            300
        )

        // Unflipped document: the clip origin starts at the maximum offset.
        XCTAssertEqual(
            PanelScrollOffset.topOffset(
                documentHeight: 600,
                viewportHeight: 300,
                clipOriginY: 300,
                documentIsFlipped: false
            ),
            0
        )
        XCTAssertEqual(
            PanelScrollOffset.topOffset(
                documentHeight: 600,
                viewportHeight: 300,
                clipOriginY: 150,
                documentIsFlipped: false
            ),
            150
        )
        XCTAssertEqual(
            PanelScrollOffset.topOffset(
                documentHeight: 600,
                viewportHeight: 300,
                clipOriginY: 0,
                documentIsFlipped: false
            ),
            300
        )

        XCTAssertEqual(
            PanelScrollOffset.topOffset(
                documentHeight: 300,
                viewportHeight: 300,
                clipOriginY: 0,
                documentIsFlipped: true
            ),
            0
        )
    }

    func testIndicatorNeverExceedsTheViewport() throws {
        let metrics = try XCTUnwrap(
            PanelScrollIndicatorMetrics(
                viewportHeight: 20,
                contentHeight: 21,
                offset: 1
            )
        )

        XCTAssertEqual(metrics.thumbHeight, 20, accuracy: 0.5)
        XCTAssertEqual(metrics.thumbOffset, 0, accuracy: 0.5)
    }

    func testExpansionStateSurvivesCrossingTheCapAndCapRoundTrip() throws {
        let metrics = StatusPanelLayoutMetrics()
        metrics.update(maximumPanelHeight: 300)
        let host = NSHostingController(rootView: ExpansionRoot(metrics: metrics))
        let window = NSWindow(contentViewController: host)
        window.setContentSize(NSSize(width: 330, height: 300))
        settle(host)
        let button = try XCTUnwrap(firstView(ofType: NSButton.self, in: host.view))
        XCTAssertEqual(button.title, "Expand")

        // This mutates the probe's own @State. Expansion itself crosses the cap.
        button.performClick(nil)
        settle(host)
        XCTAssertEqual(button.title, "Collapse")
        let scrollView = try XCTUnwrap(scrollViews(in: host.view).first)
        XCTAssertTrue(scrollView.hasVerticalOverflow)
        XCTAssertEqual(host.sizeThatFits(in: NSSize(width: 330, height: 5000)).height, 300, accuracy: 1)

        for cap: CGFloat in [900, 200, 900] {
            metrics.update(maximumPanelHeight: cap)
            settle(host)
            XCTAssertTrue(scrollViews(in: host.view).first === scrollView, "the scroll surface keeps its identity")
            XCTAssertEqual(button.title, "Collapse", "cap changes must preserve the content's local @State")
            let expectedHeight = min(640, cap)
            XCTAssertEqual(host.sizeThatFits(in: NSSize(width: 330, height: 5000)).height, expectedHeight, accuracy: 1)
            XCTAssertEqual(scrollView.hasVerticalOverflow, cap < 640)
        }
        withExtendedLifetime(window) {}
    }

    func testFooterStaysVisibleAndWheelRoutingTracksTheSameHostsCap() throws {
        let metrics = StatusPanelLayoutMetrics()
        metrics.update(maximumPanelHeight: 900)
        let host = NSHostingController(rootView: MetricsRoot(metrics: metrics))
        let window = NSWindow(contentViewController: host)
        window.setContentSize(NSSize(width: 330, height: 900))
        settle(host)
        let scrollView = try XCTUnwrap(scrollViews(in: host.view).first)
        let marker = try XCTUnwrap(firstView(ofType: FooterMarker.self, in: host.view))

        for cap: CGFloat in [900, 300, 900] {
            metrics.update(maximumPanelHeight: cap)
            settle(host)
            let size = host.sizeThatFits(in: NSSize(width: 330, height: 5000))
            host.view.setFrameSize(size)
            settle(host)
            let root = host.view
            let viewport = root.convert(scrollView.bounds, from: scrollView)
            let footerBefore = root.convert(marker.bounds, from: marker)
            let contentPoint = NSPoint(x: viewport.midX, y: viewport.midY)
            let footerPoint = NSPoint(x: footerBefore.midX, y: footerBefore.midY)
            XCTAssertEqual(PanelScrollHitTesting.pointerIsOverScrollableScrollView(at: contentPoint, in: root), cap < 640)
            XCTAssertFalse(PanelScrollHitTesting.pointerIsOverScrollableScrollView(at: footerPoint, in: root))
            XCTAssertTrue(root.bounds.contains(footerBefore), "the whole footer remains visible")
            XCTAssertFalse(isDescendant(marker, of: scrollView.documentView))
            if scrollView.hasVerticalOverflow {
                scrollView.documentView?.scroll(NSPoint(x: 0, y: 600))
                root.layoutSubtreeIfNeeded()
                XCTAssertEqual(root.convert(marker.bounds, from: marker), footerBefore, "scrolling must not move the footer")
                XCTAssertTrue(PanelScrollHitTesting.pointerIsOverScrollableScrollView(at: contentPoint, in: root), "the wheel stays with the page at its end")
            }
        }
        withExtendedLifetime(window) {}
    }

    private func settle<Content: View>(_ host: NSHostingController<Content>) {
        for _ in 0..<5 {
            host.view.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        }
    }

    private struct MetricsRoot: View {
        @ObservedObject var metrics: StatusPanelLayoutMetrics
        var body: some View {
            StatusPanelScrollArea(maximumHeight: metrics.maximumPanelHeight) {
                Color.blue.frame(height: 600)
            } footer: {
                Color.green.frame(height: 40).background(FooterMarkerView())
            }
            .frame(width: 330)
        }
    }

    private struct ExpansionRoot: View {
        @ObservedObject var metrics: StatusPanelLayoutMetrics
        var body: some View {
            StatusPanelScrollArea(maximumHeight: metrics.maximumPanelHeight) {
                ExpansionProbe()
            } footer: {
                Color.green.frame(height: 40)
            }
            .frame(width: 330)
        }
    }

    private struct ExpansionProbe: View {
        @State private var isExpanded = false
        var body: some View {
            ExpansionControl(isExpanded: $isExpanded)
                .frame(height: isExpanded ? 600 : 80)
        }
    }

    private struct ExpansionControl: NSViewRepresentable {
        @Binding var isExpanded: Bool
        func makeNSView(context: Context) -> NSButton {
            let button = NSButton(title: "Expand", target: context.coordinator, action: #selector(Coordinator.toggle))
            return button
        }
        func updateNSView(_ button: NSButton, context: Context) {
            context.coordinator.binding = $isExpanded
            button.title = isExpanded ? "Collapse" : "Expand"
        }
        func makeCoordinator() -> Coordinator { Coordinator(binding: $isExpanded) }
        final class Coordinator: NSObject {
            var binding: Binding<Bool>
            init(binding: Binding<Bool>) { self.binding = binding }
            @objc func toggle() { binding.wrappedValue.toggle() }
        }
    }

    // MARK: - Fixtures

    @MainActor
    private struct Fixture {
        let host: NSHostingController<AnyView>
        let window: NSWindow

        func measuredSize() -> NSSize {
            host.view.layoutSubtreeIfNeeded()
            return host.sizeThatFits(
                in: NSSize(width: 330, height: CGFloat.greatestFiniteMagnitude)
            )
        }
    }

    private func makeFixture(
        contentHeight: CGFloat,
        footerHeight: CGFloat,
        cap: CGFloat
    ) -> Fixture {
        let root = AnyView(
            StatusPanelScrollArea(maximumHeight: cap) {
                Color.blue.frame(height: contentHeight)
            } footer: {
                Color.green
                    .frame(height: footerHeight)
                    .background(FooterMarkerView())
            }
            .frame(width: 330)
        )
        let controller = NSHostingController(rootView: root)
        // Off-screen content host: no window is ordered in, so this stays safe
        // for ordinary background test runs.
        let window = NSWindow(contentViewController: controller)
        window.setFrame(NSRect(x: 0, y: 0, width: 330, height: cap), display: false)
        settle(controller)
        return Fixture(host: controller, window: window)
    }

    private func scrollViews(in view: NSView) -> [NSScrollView] {
        var result: [NSScrollView] = []
        if let scrollView = view as? NSScrollView {
            result.append(scrollView)
        }
        for subview in view.subviews {
            result.append(contentsOf: scrollViews(in: subview))
        }
        return result
    }

    private func firstView<T: NSView>(ofType type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for subview in view.subviews {
            if let match = firstView(ofType: type, in: subview) {
                return match
            }
        }
        return nil
    }

    private func isDescendant(_ view: NSView, of ancestor: NSView?) -> Bool {
        var current = view.superview
        while let candidate = current {
            if candidate === ancestor { return true }
            current = candidate.superview
        }
        return false
    }
}

/// A distinguishable footer view so the test can prove it is outside the scroll
/// document.
private final class FooterMarker: NSView {}

private struct FooterMarkerView: NSViewRepresentable {
    func makeNSView(context: Context) -> FooterMarker { FooterMarker() }
    func updateNSView(_ nsView: FooterMarker, context: Context) {}
}
