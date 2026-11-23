import Foundation
import XCTest
@testable import StatusTrioCore

/// Guards the wiring of the hardware-detail header shortcut. The Activity
/// Monitor button is plain SwiftUI, so instead of synthesising a real click we
/// assert the two pieces that make the tap work: the shared header lays its
/// trailing control outside the back button, and `HardwareDetailView` supplies
/// an Activity Monitor button that calls the injected opener and carries an
/// accessibility label.
final class HardwareDetailHeaderShortcutTests: XCTestCase {
    private func source(_ relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // StatusTrioCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testNavigationBackRowPlacesTrailingOutsideTheBackButton() throws {
        let source = try source("Sources/StatusTrioCore/UI/NavigationBackRow.swift")
        // The trailing control must be a separate sibling of the back button,
        // not nested inside it, so tapping it never triggers navigation.
        let backButtonStart = try XCTUnwrap(source.range(of: "Button(action: action) {"))
        let trailingUse = try XCTUnwrap(source.range(of: "\n            trailing\n"))
        XCTAssertGreaterThan(
            trailingUse.lowerBound, backButtonStart.upperBound,
            "Trailing control should follow the back button in the header HStack"
        )
        XCTAssertTrue(source.contains("let trailing: Trailing"), "Header should accept optional trailing content")
    }

    func testHardwareDetailViewSuppliesActivityMonitorShortcut() throws {
        let source = try source("Sources/StatusTrioCore/UI/HardwareDetailView.swift")
        XCTAssertTrue(
            source.contains("localization.string(.hardwareDetailOpenActivityMonitor)"),
            "Activity Monitor button should carry a localized accessibility label / tooltip"
        )
        XCTAssertTrue(
            source.contains("Button(action: openActivityMonitor)"),
            "Activity Monitor button should call the injected opener"
        )
        XCTAssertTrue(
            source.contains("var openActivityMonitor: () -> Void"),
            "The opener should be injectable for testing"
        )
    }
}
