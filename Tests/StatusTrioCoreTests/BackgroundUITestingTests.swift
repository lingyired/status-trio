import AppKit
import XCTest
@testable import StatusTrioCore

final class BackgroundUITestingTests: XCTestCase {
    func testConfigurationDefaultsAndReleaseBoundary() {
        XCTAssertFalse(BackgroundUITestingConfiguration(arguments: []).isEnabled)
        XCTAssertFalse(BackgroundUITestingConfiguration(arguments: []).rejectsLaunch)
        let configuration = BackgroundUITestingConfiguration(arguments: [
            "--background-ui-testing", "--test-display=secondary"
        ])
        #if DEBUG
        XCTAssertTrue(configuration.isEnabled)
        XCTAssertEqual(configuration.display, .secondary)
        XCTAssertFalse(configuration.opensStatusPanel)
        XCTAssertFalse(configuration.rejectsLaunch)
        #else
        XCTAssertFalse(configuration.isEnabled)
        XCTAssertEqual(configuration.display, .automatic)
        XCTAssertFalse(configuration.opensStatusPanel)
        XCTAssertFalse(configuration.rejectsLaunch)
        #endif
    }

    func testStatusPanelRequiresBackgroundTestingAndIsDebugOnly() {
        let configuration = BackgroundUITestingConfiguration(arguments: [
            "--background-ui-testing",
            "--test-display=secondary",
            "--test-open-status-panel"
        ])
        #if DEBUG
        XCTAssertTrue(configuration.isEnabled)
        XCTAssertTrue(configuration.opensStatusPanel)
        XCTAssertEqual(configuration.display, .secondary)
        XCTAssertFalse(configuration.rejectsLaunch)
        #else
        XCTAssertFalse(configuration.isEnabled)
        XCTAssertFalse(configuration.opensStatusPanel)
        XCTAssertFalse(configuration.rejectsLaunch)
        #endif
    }

    @MainActor
    func testBackgroundStatusPanelRefusesKeyWindowStatus() {
        let panel = AnchoredStatusPanel()
        XCTAssertTrue(panel.canBecomeKey)
        panel.disablesKeyWindowForTesting = true
        XCTAssertFalse(panel.canBecomeKey)
        panel.disablesKeyWindowForTesting = false
        XCTAssertTrue(panel.canBecomeKey)
    }

    func testInvalidReservedArgumentsRejectDebugLaunchInsteadOfUsingNormalPresentation() {
        for arguments in [
            ["--test-display=secondary"],
            ["--background-ui-testing", "--test-display=primary"],
            ["--background-ui-testing", "--background-ui-testing-typo"],
            ["--background-ui-testing", "--test-display"],
            ["--background-ui-testing", "--background-ui-testing"],
            ["--test-open-status-panel"],
            ["--background-ui-testing", "--test-open-status-panel-typo"],
            ["--background-ui-testing", "--test-open-status-panel",
             "--test-open-status-panel"]
        ] {
            let configuration = BackgroundUITestingConfiguration(arguments: arguments)
            XCTAssertFalse(configuration.isEnabled, "\(arguments)")
            #if DEBUG
            XCTAssertFalse(configuration.diagnostics.isEmpty, "\(arguments)")
            XCTAssertTrue(configuration.rejectsLaunch, "\(arguments)")
            #else
            XCTAssertFalse(configuration.rejectsLaunch, "\(arguments)")
            #endif
        }
        XCTAssertTrue(BackgroundUITestingConfiguration(
            arguments: ["-NSDocumentRevisionsDebugMode", "YES"]
        ).diagnostics.isEmpty)
    }

    func testSecondaryUsesDisplayIDsAndNegativeCoordinates() throws {
        let main = UITestingScreen(displayID: 10, visibleFrame: NSRect(x: 0, y: 0, width: 1400, height: 850))
        let left = UITestingScreen(displayID: 20, visibleFrame: NSRect(x: -1920, y: 50, width: 1920, height: 1000))
        let frame = try XCTUnwrap(BackgroundUIWindowPlacement.frame(
            current: NSRect(x: 100, y: 100, width: 720, height: 530),
            display: .secondary, screens: [left, main], mainDisplayID: 10
        ))
        XCTAssertTrue(left.visibleFrame.contains(frame))
        XCTAssertLessThan(frame.maxX, 0)
        let swapped = try XCTUnwrap(BackgroundUIWindowPlacement.frame(
            current: frame, display: .secondary, screens: [left, main], mainDisplayID: 20
        ))
        XCTAssertTrue(main.visibleFrame.contains(swapped))
    }

    func testUnpluggedDisplayClampsToMainAndPreservesVisibleWindow() throws {
        let main = UITestingScreen(displayID: 1, visibleFrame: NSRect(x: 0, y: 24, width: 1400, height: 850))
        let frame = try XCTUnwrap(BackgroundUIWindowPlacement.frame(
            current: NSRect(x: -1900, y: 1200, width: 720, height: 530),
            display: .secondary, screens: [main], mainDisplayID: 1
        ))
        XCTAssertTrue(main.visibleFrame.contains(frame))
        XCTAssertEqual(BackgroundUIWindowPlacement.frame(
            current: frame, display: .automatic, screens: [main], mainDisplayID: 1
        ), frame)
        XCTAssertNil(BackgroundUIWindowPlacement.frame(
            current: frame, display: .secondary, screens: [], mainDisplayID: 1
        ))
    }

    func testDisplayAboveMainAndSmallScreenKeepTitleVisible() throws {
        let above = UITestingScreen(displayID: 2, visibleFrame: NSRect(x: 30, y: 1100, width: 500, height: 400))
        let frame = try XCTUnwrap(BackgroundUIWindowPlacement.frame(
            current: NSRect(x: 100, y: 100, width: 720, height: 530),
            display: .secondary, screens: [above], mainDisplayID: 1
        ))
        XCTAssertEqual(frame.maxY, above.visibleFrame.maxY)
        XCTAssertEqual(frame.minX, above.visibleFrame.minX)
    }
}
