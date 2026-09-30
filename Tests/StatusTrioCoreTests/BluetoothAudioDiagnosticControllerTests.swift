import Foundation
import XCTest
@testable import StatusTrioCore

@MainActor
final class BluetoothAudioDiagnosticControllerTests: XCTestCase {
    func testSuccessfulRefreshReportsUnknownMetadataOncePerController() async throws {
        let json = #"""
        {
          "SPBluetoothDataType": [{
            "device_connected": [{
              "Renamed Headphones": {
                "device_address": "AA:BB:CC:DD:EE:FF",
                "device_minorType": "Headphones",
                "device_productID": "0x2042",
                "device_vendorID": "0x004C"
              }
            }]
          }]
        }
        """#
        let devices = try XCTUnwrap(BluetoothPairedDeviceReader.parse(json: Data(json.utf8)))
        let firstReporter = AppleBluetoothAudioDiagnosticReporter()
        let firstWorker = ImmediateBluetoothDeviceReader(result: .success(devices))
        let firstStateMonitor = TestBluetoothStateMonitor()
        let firstController = makeController(
            worker: firstWorker,
            reporter: firstReporter,
            stateMonitor: firstStateMonitor
        )

        firstController.activate()
        await waitUntil { firstWorker.readCount == 1 && firstReporter.retainedFingerprintCount == 1 }
        firstController.refresh()
        await waitUntil { firstWorker.readCount == 2 }
        XCTAssertEqual(firstReporter.retainedFingerprintCount, 1)

        let secondReporter = AppleBluetoothAudioDiagnosticReporter()
        let secondWorker = ImmediateBluetoothDeviceReader(result: .success(devices))
        let secondController = makeController(
            worker: secondWorker,
            reporter: secondReporter,
            stateMonitor: TestBluetoothStateMonitor()
        )
        secondController.activate()
        await waitUntil { secondWorker.readCount == 1 && secondReporter.retainedFingerprintCount == 1 }
        XCTAssertEqual(secondReporter.retainedFingerprintCount, 1)

        firstController.deactivate()
        secondController.deactivate()
    }

    private func makeController(
        worker: ImmediateBluetoothDeviceReader,
        reporter: AppleBluetoothAudioDiagnosticReporter,
        stateMonitor: TestBluetoothStateMonitor
    ) -> BluetoothDeviceController {
        BluetoothDeviceController(
            worker: worker,
            appleBluetoothAudioDiagnosticReporter: reporter,
            stateMonitor: stateMonitor,
            batteryReader: TestBluetoothBatteryReader(),
            notificationCenter: NotificationCenter(),
            workspaceNotificationCenter: NotificationCenter()
        )
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(condition(), "condition did not become true before timeout")
    }
}

@MainActor
private final class TestBluetoothStateMonitor: BluetoothStateMonitoring {
    var onStateChange: ((BluetoothAuthorizationStatus, BluetoothManagerState) -> Void)?
    let authorization: BluetoothAuthorizationStatus = .allowed

    func start() { onStateChange?(.allowed, .poweredOn) }
    func stop() {}
}

private final class ImmediateBluetoothDeviceReader: BluetoothPairedDeviceReading, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private let result: BluetoothWorkerResult

    init(result: BluetoothWorkerResult) {
        self.result = result
    }

    var readCount: Int { lock.withLock { count } }

    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void) {
        lock.withLock { count += 1 }
        completion(result)
    }
}

private final class TestBluetoothBatteryReader: BluetoothBatteryReading {
    func read(completion: @escaping @Sendable ([String: BluetoothBatteryLevel]?) -> Void) {
        completion([:])
    }
}
