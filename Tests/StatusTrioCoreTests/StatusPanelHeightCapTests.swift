import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

/// Regression coverage for issue #237: content that is taller than the screen
/// used to grow the panel past the screen edge. The panel now caps the content
/// at the screen budget, scrolls the overflow and keeps its footer pinned.
@MainActor
final class StatusPanelHeightCapTests: XCTestCase {
    func testTallSummaryStopsAtTheCapAndScrolls() throws {
        let fixture = try makeFixture(cap: 200)

        let size = fixture.measuredSize()

        XCTAssertEqual(size.width, 330)
        XCTAssertEqual(size.height, 200, accuracy: 1)
        XCTAssertEqual(
            fixture.host.view.fittingSize.height,
            200,
            accuracy: 1,
            "the panel opens at the cap instead of its natural, off-screen height"
        )
        let scrollView = try XCTUnwrap(
            firstScrollView(in: fixture.host.view),
            "a capped panel must scroll its overflow"
        )
        XCTAssertTrue(
            scrollView.documentView.map {
                $0.frame.height > scrollView.contentView.bounds.height + 0.5
            } ?? false,
            "the scroll view must have content to scroll"
        )
        XCTAssertEqual(
            allScrollViews(in: fixture.host.view).count,
            1,
            "the panel must own the only scroll surface; nested lists must not scroll"
        )
    }

    func testEveryRouteStaysWithinTheWidthAndHeightBudget() throws {
        let fixture = try makeFixture(cap: 200)
        let routes: [(name: String, route: StatusPanelRoute, open: () -> Void)] = [
            ("summary", .summary, { fixture.panel.showSummaryPage() }),
            ("battery", .battery, { fixture.panel.showBatteryPage() }),
            ("wifi", .wifi, { fixture.panel.showWiFiPage(showsDetailsInitially: false) }),
            ("ethernet", .ethernet, { fixture.panel.showWiredPage() }),
            ("inputSource", .inputSource, { fixture.panel.showInputSourcePage() })
        ]

        for (name, route, open) in routes {
            open()
            fixture.settleLayout()
            XCTAssertEqual(fixture.panel.route, route, "\(name) route should be open")

            let size = fixture.measuredSize()
            XCTAssertEqual(size.width, 330, "\(name) keeps the panel width")
            XCTAssertLessThanOrEqual(
                size.height,
                200.5,
                "\(name) must respect the panel height budget"
            )
            XCTAssertLessThanOrEqual(
                allScrollViews(in: fixture.host.view).count,
                1,
                "\(name) must not add nested scroll views"
            )
        }
    }

    func testThePinnedFooterSitsBelowTheScrollArea() throws {
        let fixture = try makeFixture(cap: 200)
        let scrollView = try XCTUnwrap(firstScrollView(in: fixture.host.view))

        let scrollFrame = fixture.host.view.convert(
            scrollView.bounds,
            from: scrollView
        )

        // The cap is 200pt; the footer occupies the bottom of the panel, so the
        // scroll view must end more than a footer's height above the bottom.
        XCTAssertLessThan(scrollFrame.height, 200 - 20)
        XCTAssertGreaterThan(fixture.host.view.bounds.height, 0)
    }

    func testShortSummaryKeepsItsNaturalHeightAndDoesNotScroll() throws {
        let uncapped = try makeFixture(cap: nil)
        let capped = try makeFixture(cap: 5000)

        let uncappedSize = uncapped.measuredSize()
        let cappedSize = capped.measuredSize()

        XCTAssertGreaterThan(uncappedSize.height, 0)
        XCTAssertLessThan(uncappedSize.height, 5000)
        XCTAssertEqual(cappedSize.height, uncappedSize.height, accuracy: 1)
        XCTAssertEqual(allScrollViews(in: capped.host.view).count, 1)
        let scrollView = try XCTUnwrap(firstScrollView(in: capped.host.view))
        XCTAssertFalse(scrollView.hasVerticalOverflow, "content that fits must not scroll")
    }

    func testALargerCapLetsTheSameContentGrow() throws {
        let tight = try makeFixture(cap: 200)
        let roomy = try makeFixture(cap: 420)
        let uncapped = try makeFixture(cap: nil)

        XCTAssertEqual(tight.measuredSize().height, 200, accuracy: 1)
        XCTAssertGreaterThan(roomy.measuredSize().height, 200)
        XCTAssertLessThanOrEqual(roomy.measuredSize().height, 420)
        XCTAssertGreaterThan(uncapped.measuredSize().height, 200)
    }


    /// Issue #259: the same content must follow a budget that shrinks and then
    /// returns, instead of sticking at the smallest cap it ever saw.
    func testTheSameContentFollowsABudgetThatShrinksAndRecovers() throws {
        let natural = try makeFixture(cap: nil).measuredSize().height
        XCTAssertGreaterThan(natural, 300, "the fixture content must exceed the test budget")

        let fixture = try makeFixture(cap: 300)
        XCTAssertEqual(fixture.measuredSize().height, 300, accuracy: 1)

        fixture.metrics.update(maximumPanelHeight: 200)
        fixture.settleLayout()
        XCTAssertEqual(fixture.measuredSize().height, 200, accuracy: 1)

        fixture.metrics.update(maximumPanelHeight: 300)
        fixture.settleLayout()
        XCTAssertEqual(fixture.measuredSize().height, 300, accuracy: 1)
    }

    func testChangingRoutesReturnsThePageToTheTop() throws {
        let fixture = try makeFixture(cap: 200)
        let summaryScroll = try XCTUnwrap(firstScrollView(in: fixture.host.view))
        let document = try XCTUnwrap(summaryScroll.documentView)
        document.scroll(NSPoint(x: 0, y: document.bounds.maxY))
        fixture.settleLayout()
        XCTAssertGreaterThan(summaryScroll.contentView.bounds.minY, 0, "start from a genuinely scrolled summary")

        fixture.panel.showBatteryPage()
        fixture.settleLayout()
        let detailScroll = try XCTUnwrap(firstScrollView(in: fixture.host.view))
        XCTAssertEqual(detailScroll.contentView.bounds.minY, 0, accuracy: 1)

        fixture.panel.showSummaryPage()
        fixture.settleLayout()
        let returnedScroll = try XCTUnwrap(firstScrollView(in: fixture.host.view))
        XCTAssertEqual(returnedScroll.contentView.bounds.minY, 0, accuracy: 1, "returning to summary starts at its top")
    }

    // MARK: - Fixtures

    @MainActor
    private struct Fixture {
        let host: StatusPanelHostingController<AnyView>
        let window: NSWindow
        let panel: StatusPanelViewModel
        let metrics: StatusPanelLayoutMetrics

        func measuredSize() -> NSSize {
            host.view.layoutSubtreeIfNeeded()
            return host.sizeThatFits(
                in: NSSize(width: 330, height: CGFloat.greatestFiniteMagnitude)
            )
        }

        /// Lets a route change reach the SwiftUI tree before measuring.
        func settleLayout() {
            for _ in 0..<5 {
                host.view.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
            }
        }
    }

    private func makeFixture(cap: CGFloat?) throws -> Fixture {
        let suiteName = "StatusTrioCoreTests.StatusPanelHeightCap.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removeTestSuite(named: suiteName) }

        let settings = SettingsStore(defaults: defaults)
        // Every section on, so the summary is reliably taller than a small cap.
        for section in PopupSection.allCases {
            settings.setPopupSection(section, enabled: true)
        }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        let store = SystemStatusStore(
            batteryMonitor: CapProbeBatteryMonitor(),
            wifiMonitor: CapProbeWiFiMonitor(),
            volumeMonitor: CapProbeVolumeMonitor()
        )
        let panel = StatusPanelViewModel(
            store: store,
            settings: settings,
            localization: localization,
            actions: StatusPanelActions(store: store, settings: settings)
        )
        let metrics = StatusPanelLayoutMetrics()
        if let cap {
            metrics.update(maximumPanelHeight: cap)
        }
        let rootView = AnyView(
            StatusPopoverView(
                panel: panel,
                scrollTargets: PopoverScrollTargets(),
                layoutMetrics: metrics,
                requestWiFiNameAccess: {},
                requestBluetoothAuthorization: {},
                openBatterySettings: {},
                openAppBatterySettings: {},
                openWiFiSettings: {},
                openNetworkSettings: {},
                openSharingSettings: {},
                openLocationSettings: {},
                openBluetoothSettings: {},
                openBluetoothPermissionSettings: {},
                openSettings: {},
                openSoundSettings: {},
                openSoundInputSettings: {},
                openKeyboardSettings: {},
                quit: {}
            )
            .environmentObject(localization)
        )
        let host = StatusPanelHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 330, height: 700),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        host.view.frame = NSRect(x: 0, y: 0, width: 330, height: 700)
        window.contentView?.addSubview(host.view)
        let fixture = Fixture(host: host, window: window, panel: panel, metrics: metrics)
        fixture.settleLayout()
        return fixture
    }

    private func firstScrollView(in view: NSView) -> NSScrollView? {
        allScrollViews(in: view).first
    }

    private func allScrollViews(in view: NSView) -> [NSScrollView] {
        var result: [NSScrollView] = []
        if let scrollView = view as? NSScrollView {
            result.append(scrollView)
        }
        for subview in view.subviews {
            result.append(contentsOf: allScrollViews(in: subview))
        }
        return result
    }
}

@MainActor
private final class CapProbeBatteryMonitor: BatteryMonitoring {
    let updates: AsyncStream<BatteryStatus>
    init() { (updates, _) = AsyncStream.makeStream() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}

@MainActor
private final class CapProbeWiFiMonitor: WiFiMonitoring {
    let updates: AsyncStream<WiFiStatus>
    init() { (updates, _) = AsyncStream.makeStream() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func requestNameAccess() -> WiFiNameAccessRequestResult { .notNeeded }
}

@MainActor
private final class CapProbeVolumeMonitor: VolumeMonitoring {
    let updates: AsyncStream<VolumeStatus>
    init() { (updates, _) = AsyncStream.makeStream() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}
