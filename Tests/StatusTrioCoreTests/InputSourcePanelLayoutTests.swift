import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

/// The panel's input-source section is a row that opens the list, not the list
/// itself: an enabled section must not turn the panel into a picker. The
/// interactive targets are what a user without the mouse precision for a
/// one-line button actually clicks, so they are the measurable part.
@MainActor
final class InputSourcePanelLayoutTests: XCTestCase {
    func testTheSummaryRowDoesNotDrawTheSourceList() {
        let sizes = interactiveSubViewSizes(
            for: summaryView(),
            size: NSSize(width: 330, height: 80)
        )

        XCTAssertFalse(sizes.isEmpty, "the summary row has to be interactive")
        XCTAssertTrue(
            sizes.contains { $0.width >= 280 },
            "the whole row opens the list, got \(sizes)"
        )
        XCTAssertFalse(
            sizes.contains { $0.height < 24 },
            "the summary row must not draw one target per input source, got \(sizes)"
        )
    }

    func testTheOpenedListCarriesABackRowAndOneTargetPerSource() {
        let sizes = interactiveSubViewSizes(
            for: listView(),
            size: NSSize(width: 330, height: 400)
        )

        XCTAssertTrue(
            sizes.contains { $0.height >= 30 },
            "the opened list needs its back row, got \(sizes)"
        )
        XCTAssertTrue(
            sizes.contains { $0.height < 24 },
            "each input source has to be its own target, got \(sizes)"
        )
    }

    // MARK: - Fixtures

    private func state() -> InputSourcePanelState {
        InputSourcePanelState(
            title: "输入法",
            currentName: "微信输入法",
            rows: [
                .init(id: "abc", name: "ABC", iconURL: nil, marker: "A", isCurrent: false),
                .init(id: "wetype", name: "微信输入法", iconURL: nil, marker: "拼", isCurrent: true)
            ],
            emptyMessage: nil,
            failureText: nil,
            openSettingsLabel: "打开键盘设置"
        )
    }

    private func summaryView() -> some View {
        InputSourceStatusView(state: state(), onOpen: {}, onOpenKeyboardSettings: {})
            .environmentObject(makeLocalization())
            .frame(width: 330)
    }

    private func listView() -> some View {
        InputSourceListView(state: state(), onBack: {}, onSelect: { _ in }, onOpenKeyboardSettings: {})
            .environmentObject(makeLocalization())
            .frame(width: 330)
    }

    private func makeLocalization() -> Localization {
        let suiteName = "StatusTrioCoreTests.InputSourcePanelLayout.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removeTestSuite(named: suiteName)
        addTeardownBlock { TestUserDefaults.removeSuite(named: suiteName) }
        return Localization(defaults: defaults, preferredLanguages: ["zh-Hans"])
    }

    /// Interactive targets only exist once the view is inside an ordered
    /// window, and the interactive subtree the SDK realises is not identical on
    /// every macOS version, so this polls with a bounded timeout instead of
    /// asserting on a fixed sleep.
    private func interactiveSubViewSizes<V: View>(for view: V, size: NSSize) -> [NSSize] {
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }

        let deadline = Date().addingTimeInterval(2)
        var sizes: [NSSize] = []
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            hostingView.layoutSubtreeIfNeeded()
            sizes = hostingView.subviews
                .filter { !$0.isHidden && $0.frame.height > 0 }
                .map(\.frame.size)
            if !sizes.isEmpty { break }
        }
        return sizes
    }
}
