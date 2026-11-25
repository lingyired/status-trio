import XCTest
@testable import StatusTrioCore

/// The app's accessory reader is IOKit-first with a `pmset` fallback. These pin
/// the selection rule: IOKit answers only when it actually reports an accessory;
/// a missing or empty result falls through to the fallback.
final class BluetoothAccessoryBatteryWorkerTests: XCTestCase {
    private final class CountingReader: BluetoothAccessoryBatteryReading, @unchecked Sendable {
        private let lock = NSLock()
        private let answer: [BluetoothAccessoryBatteryLevel]?
        private(set) var calls = 0

        init(answer: [BluetoothAccessoryBatteryLevel]?) {
            self.answer = answer
        }

        func read(completion: @escaping @Sendable ([BluetoothAccessoryBatteryLevel]?) -> Void) {
            lock.lock()
            calls += 1
            lock.unlock()
            completion(answer)
        }

        var callCount: Int {
            lock.lock(); defer { lock.unlock() }
            return calls
        }
    }

    private func reading(name: String, charging: Bool?) -> BluetoothAccessoryBatteryLevel {
        BluetoothAccessoryBatteryLevel(
            identifier: "ID", name: name, vendorID: nil, productID: nil,
            part: nil, percentage: 80, isCharging: charging
        )
    }

    private func awaitAnswer(
        _ worker: SystemAccessoryBatteryWorker
    ) async -> [BluetoothAccessoryBatteryLevel]? {
        await withCheckedContinuation { continuation in
            worker.read { continuation.resume(returning: $0) }
        }
    }

    func testUsesIOKitWhenItReportsAnAccessory() async {
        let fallback = CountingReader(answer: [reading(name: "Fallback", charging: false)])
        let worker = SystemAccessoryBatteryWorker(
            iokitProvider: {
                [BluetoothAccessoryBatteryLevel(
                    identifier: "ID", name: "IOKit", vendorID: nil, productID: nil,
                    part: nil, percentage: 80, isCharging: true
                )]
            },
            fallback: fallback
        )
        let result = await awaitAnswer(worker)
        XCTAssertEqual(result?.first?.name, "IOKit")
        XCTAssertEqual(fallback.callCount, 0)
    }

    func testFallsBackWhenIOKitIsUnavailableOrEmpty() async {
        let fallback = CountingReader(answer: [reading(name: "Fallback", charging: false)])
        let unavailable = SystemAccessoryBatteryWorker(iokitProvider: { nil }, fallback: fallback)
        let first = await awaitAnswer(unavailable)
        XCTAssertEqual(first?.first?.name, "Fallback")

        let empty = SystemAccessoryBatteryWorker(iokitProvider: { [] }, fallback: fallback)
        let second = await awaitAnswer(empty)
        XCTAssertEqual(second?.first?.name, "Fallback")
        XCTAssertEqual(fallback.callCount, 2)
    }
}
