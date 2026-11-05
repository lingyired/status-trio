import XCTest
import notify
@testable import StatusTrioCore

@MainActor
final class PowerModeNotificationMonitorTests: XCTestCase {
    func testDeliversTheNotifyKeyAndStopsAfterStop() async throws {
        // A private key: the test must never post a real system power-mode
        // notification, which would notify unrelated observers on this Mac.
        let name = "com.lingsmbp.StatusTrioTests.\(UUID().uuidString)"
        let monitor = PowerModeNotificationMonitor(names: [name])
        let received = expectation(description: "notify key delivered")
        var deliveries = 0
        monitor.start {
            deliveries += 1
            if deliveries == 1 { received.fulfill() }
        }

        notify_post(name)
        await fulfillment(of: [received], timeout: 2)

        monitor.stop()
        let deliveredBeforeStop = deliveries
        notify_post(name)
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(deliveries, deliveredBeforeStop, "a stopped monitor must release its token")
    }
}
