import CoreLocation
import XCTest
@testable import StatusTrioCore

@MainActor
final class WiFiNameAuthorizerTests: XCTestCase {
    func testUnansweredRequestDoesNotRepeatedlyRequestAuthorization() {
        let manager = StubWiFiLocationManager()
        let authorizer = CoreLocationWiFiNameAuthorizer(manager: manager)

        XCTAssertEqual(authorizer.requestAccess(), .requested)
        XCTAssertEqual(authorizer.requestAccess(), .openLocationSettings)

        XCTAssertEqual(manager.requestCount, 1)
    }

    func testDeniedAndRestrictedPermissionsOfferSettingsWithoutRequestingAgain() async {
        for status: CLAuthorizationStatus in [.denied, .restricted] {
            let manager = StubWiFiLocationManager()
            let authorizer = CoreLocationWiFiNameAuthorizer(manager: manager)
            await deliver(status, from: manager, to: authorizer)

            XCTAssertEqual(authorizer.requestAccess(), .openLocationSettings)
            XCTAssertEqual(manager.requestCount, 0)
        }
    }

    func testAlreadyAuthorizedPermissionDoesNotRequestOrOfferSettings() async {
        let manager = StubWiFiLocationManager()
        let authorizer = CoreLocationWiFiNameAuthorizer(manager: manager)
        await deliver(.authorizedAlways, from: manager, to: authorizer)

        XCTAssertEqual(authorizer.requestAccess(), .notNeeded)
        XCTAssertEqual(manager.requestCount, 0)
    }

    func testFreshAuthorizationTakesPrecedenceOverTheEarlierRequest() async {
        let manager = StubWiFiLocationManager()
        let authorizer = CoreLocationWiFiNameAuthorizer(manager: manager)
        XCTAssertEqual(authorizer.requestAccess(), .requested)

        await deliver(.denied, from: manager, to: authorizer)
        XCTAssertEqual(authorizer.requestAccess(), .openLocationSettings)

        await deliver(.authorizedAlways, from: manager, to: authorizer)
        XCTAssertEqual(authorizer.requestAccess(), .notNeeded)
        XCTAssertEqual(manager.requestCount, 1)
    }

    func testAuthorizationChangeNotifiesAfterUpdatingAccess() async {
        let manager = StubWiFiLocationManager()
        let authorizer = CoreLocationWiFiNameAuthorizer(manager: manager)
        var notifiedAccess: [WiFiNameAccess] = []
        authorizer.onAccessChange = { notifiedAccess.append(authorizer.access) }

        await deliver(.authorizedAlways, from: manager, to: authorizer)

        XCTAssertEqual(notifiedAccess.last, .authorized)
    }

    /// Outside the delegate callback, `authorizationStatus` can be a synchronous
    /// reply from locationd; when locationd stopped answering, that read froze the
    /// main actor inside `WiFiMonitor.receive(_:)`. Reading access must stay local.
    func testReadingAccessNeverAsksCoreLocationForTheStatus() async {
        let manager = StubWiFiLocationManager()
        manager.currentAuthorization = .authorizedAlways
        let authorizer = CoreLocationWiFiNameAuthorizer(manager: manager)

        let readsBeforeReport = manager.statusReadCount
        XCTAssertEqual(authorizer.access, .notDetermined)
        XCTAssertEqual(manager.statusReadCount, readsBeforeReport)

        await deliver(.authorizedAlways, from: manager, to: authorizer)
        let readsAfterReport = manager.statusReadCount
        for _ in 0..<3 {
            XCTAssertEqual(authorizer.access, .authorized)
        }
        XCTAssertEqual(authorizer.requestAccess(), .notNeeded)
        XCTAssertEqual(manager.statusReadCount, readsAfterReport)
    }

    /// Reports a status the way Core Location does, then gives the authorizer's
    /// main-actor hop real time to land. The deadline makes a regression fail
    /// instead of hang.
    private func deliver(
        _ status: CLAuthorizationStatus,
        from manager: StubWiFiLocationManager,
        to authorizer: CoreLocationWiFiNameAuthorizer,
        timeout: Duration = .seconds(5)
    ) async {
        manager.currentAuthorization = status
        authorizer.locationManagerDidChangeAuthorization(manager)
        let expected: WiFiNameAccess = switch status {
        case .authorizedAlways: .authorized
        case .denied: .denied
        case .restricted: .restricted
        default: .notDetermined
        }
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while authorizer.access != expected {
            if ContinuousClock.now >= deadline {
                XCTFail("Timed out waiting for the authorizer to record \(expected).")
                return
            }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(2))
        }
    }
}

private final class StubWiFiLocationManager: CLLocationManager {
    var currentAuthorization: CLAuthorizationStatus = .notDetermined
    private(set) var requestCount = 0
    private(set) var statusReadCount = 0

    override var authorizationStatus: CLAuthorizationStatus {
        statusReadCount += 1
        return currentAuthorization
    }

    override func requestWhenInUseAuthorization() {
        requestCount += 1
    }
}
