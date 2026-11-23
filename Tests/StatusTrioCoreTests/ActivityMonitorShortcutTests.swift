import XCTest
@testable import StatusTrioCore

final class ActivityMonitorShortcutTests: XCTestCase {
    func testConstantsNameTheSystemActivityMonitor() {
        XCTAssertEqual(ActivityMonitorShortcut.bundleIdentifier, "com.apple.ActivityMonitor")
        XCTAssertEqual(
            ActivityMonitorShortcut.applicationPath,
            "/System/Applications/Utilities/Activity Monitor.app"
        )
    }

    func testApplicationURLPrefersTheBundleIdentifierLookup() {
        let expected = URL(fileURLWithPath: "/Somewhere/Activity Monitor.app")
        let url = ActivityMonitorShortcut.applicationURL(
            bundleIdentifierLookup: { identifier in
                XCTAssertEqual(identifier, ActivityMonitorShortcut.bundleIdentifier)
                return expected
            },
            fileExists: { _ in false }
        )
        XCTAssertEqual(url, expected)
    }

    func testApplicationURLFallsBackToTheUtilitiesPathWhenBundleLookupMisses() {
        let url = ActivityMonitorShortcut.applicationURL(
            bundleIdentifierLookup: { _ in nil },
            fileExists: { path in
                XCTAssertEqual(path, ActivityMonitorShortcut.applicationPath)
                return true
            }
        )
        XCTAssertEqual(url, URL(fileURLWithPath: ActivityMonitorShortcut.applicationPath))
    }

    func testApplicationURLIsNilWhenNeitherCandidateExists() {
        let url = ActivityMonitorShortcut.applicationURL(
            bundleIdentifierLookup: { _ in nil },
            fileExists: { _ in false }
        )
        XCTAssertNil(url)
    }
}
