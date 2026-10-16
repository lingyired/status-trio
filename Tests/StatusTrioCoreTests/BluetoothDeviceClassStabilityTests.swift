import Foundation
import Testing
@testable import StatusTrioCore

/// A paired Bluetooth device's declared class must not change just because a
/// connected HID interface becomes available.
struct BluetoothDeviceClassStabilityTests {
    @Test(arguments: [
        ("Mouse", BluetoothDeviceKind.peripheral(.mouse)),
        ("Keyboard", .peripheral(.keyboard)),
        ("Trackpad", .peripheral(.trackpad)),
        ("Combined Keyboard Pointing", .peripheral(.unclassified)),
        ("Headphones", .audio),
        ("Unrecognized", .peripheral(.unclassified)),
    ])
    func theKindIsIndependentOfTheConnectionState(
        minorType: String,
        expected: BluetoothDeviceKind
    ) async {
        for isConnected in [false, true] {
            let collection = isConnected ? "device_connected" : "device_not_connected"
            let report = """
            {"SPBluetoothDataType": [{"\(collection)": [
              {"Test Device": {
                "device_address": "D3:6D:6C:40:A3:2E",
                "device_minorType": "\(minorType)",
                "device_majorType": "Peripheral"
              }}
            ]}]}
            """
            let worker = SystemProfilerBluetoothPairedDeviceWorker(
                outputProvider: { Data(report.utf8) }
            )
            let result: BluetoothWorkerResult = await withCheckedContinuation { continuation in
                worker.read { continuation.resume(returning: $0) }
            }
            guard case .success(let devices) = result else {
                Issue.record("Expected a successful profiler read")
                return
            }
            #expect(devices.count == 1)
            #expect(devices.first?.kind == expected)
            #expect(devices.first?.isConnected == isConnected)
        }
    }
}
