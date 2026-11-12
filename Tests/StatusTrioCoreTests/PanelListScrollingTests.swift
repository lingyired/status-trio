import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

/// The detail pages keep their own scroll bound when used on their own, but
/// inside the status panel they must hand scrolling to the panel's single outer
/// surface (#237).
@MainActor
final class PanelListScrollingTests: XCTestCase {
    func testWiFiListDropsItsOwnScrollerWhenThePanelOwnsScrolling() throws {
        let state = makeWiFiState(rowCount: 40)

        let managed = try measure {
            WiFiNetworkListView(
                state: state,
                onBack: {},
                onRequestNameAccess: {},
                onOpenWiFiSettings: {},
                onOpenLocationSettings: {},
                onSetPower: { _ in },
                onRefresh: {},
                onOpenSharingSettings: {},
                onCopyValue: { _ in },
                showsDetails: false,
                showsMore: false,
                onSetShowsDetails: { _ in },
                onSetShowsMore: { _ in }
            )
            .environment(\.statusPanelManagesScrolling, true)
        }
        XCTAssertTrue(
            scrollViews(in: managed.view).isEmpty,
            "the panel's page must expose every row to the outer scroll area"
        )
        XCTAssertGreaterThan(managed.size.height, 330)

        let standalone = try measure {
            WiFiNetworkListView(
                state: state,
                onBack: {},
                onRequestNameAccess: {},
                onOpenWiFiSettings: {},
                onOpenLocationSettings: {},
                onSetPower: { _ in },
                onRefresh: {},
                onOpenSharingSettings: {},
                onCopyValue: { _ in },
                showsDetails: false,
                showsMore: false,
                onSetShowsDetails: { _ in },
                onSetShowsMore: { _ in }
            )
        }
        let standaloneScroll = try XCTUnwrap(
            scrollViews(in: standalone.view).first,
            "a standalone Wi-Fi page still bounds its list"
        )
        XCTAssertLessThanOrEqual(standaloneScroll.contentView.bounds.height, 331)
    }

    func testInputSourceListDropsItsOwnScrollerWhenThePanelOwnsScrolling() throws {
        let state = InputSourcePanelState(
            title: "Input Sources",
            currentName: "U.S.",
            rows: (0..<30).map { index in
                InputSourcePanelState.Row(
                    id: "source-\(index)",
                    name: "Source \(index)",
                    iconURL: nil,
                    marker: "A",
                    isCurrent: index == 0
                )
            },
            emptyMessage: nil,
            failureText: nil,
            openSettingsLabel: "Open Keyboard Settings"
        )

        let managed = try measure {
            InputSourceListView(
                state: state,
                onBack: {},
                onSelect: { _ in },
                onOpenKeyboardSettings: {}
            )
            .environment(\.statusPanelManagesScrolling, true)
        }
        XCTAssertTrue(scrollViews(in: managed.view).isEmpty)
        XCTAssertGreaterThan(managed.size.height, 330)

        let standalone = try measure {
            InputSourceListView(
                state: state,
                onBack: {},
                onSelect: { _ in },
                onOpenKeyboardSettings: {}
            )
        }
        let standaloneScroll = try XCTUnwrap(scrollViews(in: standalone.view).first)
        XCTAssertLessThanOrEqual(standaloneScroll.contentView.bounds.height, 331)
    }

    // MARK: - Fixtures

    @MainActor
    private struct Measured {
        let host: NSHostingController<AnyView>
        let window: NSWindow
        let size: NSSize

        var view: NSView { host.view }
    }

    private func measure(@ViewBuilder _ content: () -> some View) throws -> Measured {
        let suiteName = "StatusTrioCoreTests.PanelListScrolling.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removeTestSuite(named: suiteName) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        let root = AnyView(
            content().environmentObject(localization).frame(width: 330)
        )
        let host = NSHostingController(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 330, height: 700),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        host.view.frame = NSRect(x: 0, y: 0, width: 330, height: 700)
        window.contentView?.addSubview(host.view)
        host.view.layoutSubtreeIfNeeded()
        let size = host.sizeThatFits(
            in: NSSize(width: 330, height: CGFloat.greatestFiniteMagnitude)
        )
        return Measured(host: host, window: window, size: size)
    }

    private func makeWiFiState(rowCount: Int) -> WiFiPanelState {
        let rows = (0..<rowCount).map { index in
            PanelWiFiNetworkRow(
                key: WiFiNetworkIdentity(ssid: "Network \(index)", security: .wpa2Personal),
                name: "Network \(index)",
                signalSymbol: .symbol(name: "wifi", variableValue: 1, fallback: "wifi"),
                signalSystemImage: "lock.fill",
                securityMarker: "lock.fill",
                selected: index == 0,
                accessibilityLabel: "Network \(index)",
                action: .none
            )
        }
        return WiFiPanelState(
            detail: PanelDetailState(
                title: "Wi-Fi",
                rows: [],
                isLoading: false,
                errorText: nil,
                explanation: nil
            ),
            collapsedDetailRowCount: 9,
            knownRows: rows,
            otherRows: [],
            powerIsOn: true,
            canSetPower: true,
            canRefresh: true,
            isScanning: false,
            message: nil,
            messageIntent: .none,
            showsConnectionDetails: false
        )
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
}
