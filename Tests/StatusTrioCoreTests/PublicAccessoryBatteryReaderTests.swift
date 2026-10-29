import Foundation
import IOKit.ps
import Testing
@testable import StatusTrioCore

struct PublicAccessoryBatteryReaderTests {
    @Test func mapsPublicKeysAndExcludesInternalAndUPS() {
        let levels = PublicAccessoryBatteryReader.levels(from: .sources([
            source(
                type: PublicAccessoryBatteryReader.internalBatteryType,
                name: "InternalBattery-0",
                current: 80,
                maximum: 100
            ),
            source(
                type: PublicAccessoryBatteryReader.upsType,
                name: "UPS",
                current: 50,
                maximum: 100
            ),
            source(
                type: "Accessory Source",
                name: " MX Keys ",
                vendorID: 1133,
                productID: 45915,
                current: 100,
                maximum: 100
            ),
            source(
                type: "Accessory Source",
                name: "Earbuds",
                vendorID: 76,
                productID: 8207,
                current: 93,
                maximum: 100
            )
        ]))

        #expect(levels?.count == 2)
        #expect(levels?[0].name == "MX Keys")
        #expect(levels?[0].vendorID == 1133)
        #expect(levels?[0].productID == 45915)
        #expect(levels?[0].part == nil)
        #expect(levels?[0].percentage == 100)
        #expect(levels?[1].percentage == 93)
    }

    @Test func missingOrInvalidCapacityIsOmittedNotZero() {
        let levels = PublicAccessoryBatteryReader.levels(from: .sources([
            source(type: "Accessory Source", name: "Missing current", current: nil, maximum: 100),
            source(type: "Accessory Source", name: "Missing maximum", current: 50, maximum: nil),
            source(type: "Accessory Source", name: "Zero maximum", current: 50, maximum: 0),
            source(type: "Accessory Source", name: "Negative current", current: -1, maximum: 100),
            source(type: "Accessory Source", name: "Over maximum", current: 101, maximum: 100),
            source(type: "Accessory Source", name: "Valid", current: 50, maximum: 100)
        ]))

        #expect(levels?.count == 1)
        #expect(levels?.first?.name == "Valid")
        #expect(levels?.first?.percentage == 50)
    }

    @Test func missingVendorProductAndPartRemainNil() {
        let levels = PublicAccessoryBatteryReader.levels(from: .sources([
            source(
                type: "Accessory Source",
                name: "Unknown identity",
                vendorID: nil,
                productID: nil,
                current: 64,
                maximum: 100
            )
        ]))

        #expect(levels?.count == 1)
        #expect(levels?.first?.vendorID == nil)
        #expect(levels?.first?.productID == nil)
        #expect(levels?.first?.part == nil)
    }

    @Test func accessoryMetadataWithoutPublicTypeKeyIsNotFabricated() {
        let levels = PublicAccessoryBatteryReader.levels(from: .sources([
            source(
                type: nil,
                name: "Type unavailable",
                current: 64,
                maximum: 100
            )
        ]))

        #expect(levels?.count == 1)
        #expect(levels?.first?.name == "Type unavailable")
        #expect(levels?.first?.part == nil)
    }

    @Test func absentSourcesAreExcluded() {
        let levels = PublicAccessoryBatteryReader.levels(from: .sources([
            source(
                type: "Accessory Source",
                name: "Absent",
                current: 50,
                maximum: 100,
                isPresent: false
            ),
            source(
                type: "Accessory Source",
                name: "Present",
                current: 50,
                maximum: 100,
                isPresent: true
            )
        ]))

        #expect(levels?.count == 1)
        #expect(levels?.first?.name == "Present")
    }

    @Test func capacityIsNormalizedAgainstTheReportedMaximum() {
        let levels = PublicAccessoryBatteryReader.levels(from: .sources([
            source(
                type: "Accessory Source",
                name: "Earbuds",
                current: 1860,
                maximum: 2000
            )
        ]))

        #expect(levels?.first?.percentage == 93)
    }

    @Test func emptySourcesAreDistinctFromUnavailableAndFailedOutputs() {
        #expect(PublicAccessoryBatteryReader.levels(from: .sources([]))?.isEmpty == true)
        #expect(PublicAccessoryBatteryReader.levels(from: .unavailable) == nil)
        #expect(PublicAccessoryBatteryReader.levels(from: .failed) == nil)
    }

    @Test func malformedIOPSBoundaryProducesFailedWhileNilProducesUnavailable() {
        let wrongTypeDescription: [String: Any] = [
            kIOPSTypeKey: NSNumber(value: 42)
        ]

        #expect(PublicAccessoryBatteryReader.snapshot(from: .unavailable) == .unavailable)
        #expect(PublicAccessoryBatteryReader.snapshot(from: .malformed) == .failed)
        #expect(
            PublicAccessoryBatteryReader.snapshot(
                from: .descriptions([nil])
            ) == .failed
        )
        #expect(
            PublicAccessoryBatteryReader.snapshot(
                from: .descriptions([wrongTypeDescription])
            ) == .failed
        )
        #expect(PublicAccessoryBatteryReader.snapshot(from: .descriptions([])) == .sources([]))
    }

    @Test func rawIOPSBooleanAndNonIntegerNumbersAreRejected() {
        let fixtures: [[String: Any]] = [
            [
                kIOPSCurrentCapacityKey: NSNumber(value: true),
                kIOPSMaxCapacityKey: NSNumber(value: 100)
            ],
            [
                kIOPSCurrentCapacityKey: NSNumber(value: 50),
                kIOPSMaxCapacityKey: NSNumber(value: true)
            ],
            [
                kIOPSVendorIDKey: NSNumber(value: true)
            ],
            [
                kIOPSProductIDKey: NSNumber(value: false)
            ],
            [
                kIOPSIsPresentKey: NSNumber(value: 1)
            ],
            [
                kIOPSCurrentCapacityKey: NSNumber(value: 50.5),
                kIOPSMaxCapacityKey: NSNumber(value: 100)
            ]
        ]

        for (index, fixture) in fixtures.enumerated() {
            #expect(
                PublicAccessoryBatteryReader.snapshot(
                    from: .descriptions([fixture])
                ) == .failed,
                "raw IOPS fixture \(index) was not rejected"
            )
        }
    }

    @Test func eachReadCallsTheProviderExactlyOnce() async {
        let provider = CountingAccessorySnapshotProvider(snapshot: .sources([]))
        let reader = PublicAccessoryBatteryReader(snapshotProvider: provider.read)
        let results = AccessoryResultBox()

        reader.read { results.append($0) }
        await waitUntil { results.count == 1 }
        try? await Task.sleep(for: .milliseconds(30))

        #expect(provider.callCount == 1)
        #expect(results.count == 1)
    }

    @Test func boundsBlockedReadsAndReopensCapacityAfterCompletion() async {
        let gate = BoundedAccessoryReadGate()
        defer { gate.releaseAll() }
        let reader = PublicAccessoryBatteryReader(snapshotProvider: gate.read)
        let results = AccessoryResultBox()

        reader.read { results.append($0) }
        #expect(gate.waitForFirstRead())
        reader.read { results.append($0) }
        #expect(gate.waitForSecondRead())

        reader.read { results.append($0) }
        await waitUntil { results.count == 1 }
        #expect(results[0] == nil)
        #expect(gate.callCount == 2)
        #expect(gate.maximumSimultaneousCalls == 2)

        gate.releaseFirstRead()
        await waitUntil { results.count == 2 }

        reader.read { results.append($0) }
        #expect(gate.waitForThirdRead())
        #expect(gate.maximumSimultaneousCalls == 2)

        gate.releaseSecondRead()
        gate.releaseThirdRead()
        await waitUntil { results.count == 4 }
        #expect(gate.callCount == 3)
    }

    @Test func shutdownStopsNewBackgroundWorkWithoutClaimingCancellation() async {
        let provider = CountingAccessorySnapshotProvider(snapshot: .sources([]))
        let reader = PublicAccessoryBatteryReader(snapshotProvider: provider.read)
        let results = AccessoryResultBox()

        reader.shutdown()
        reader.read { results.append($0) }
        await waitUntil { results.count == 1 }

        #expect(provider.callCount == 0)
        #expect(results[0] == nil)
    }

    private func source(
        type: String?,
        name: String?,
        vendorID: Int? = nil,
        productID: Int? = nil,
        current: Int?,
        maximum: Int?,
        isPresent: Bool? = true
    ) -> PublicAccessoryPowerSource {
        PublicAccessoryPowerSource(
            type: type,
            name: name,
            vendorID: vendorID,
            productID: productID,
            currentCapacity: current,
            maxCapacity: maximum,
            isPresent: isPresent
        )
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<500 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        Issue.record("Timed out waiting for the accessory read")
    }
}

private final class AccessoryResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [[BluetoothAccessoryBatteryLevel]?] = []

    var count: Int { lock.withLock { results.count } }
    subscript(index: Int) -> [BluetoothAccessoryBatteryLevel]? {
        lock.withLock { results[index] }
    }

    func append(_ result: [BluetoothAccessoryBatteryLevel]?) {
        lock.withLock { results.append(result) }
    }
}

private final class CountingAccessorySnapshotProvider: @unchecked Sendable {
    private let lock = NSLock()
    private let snapshot: PublicAccessoryBatterySnapshot
    private var calls = 0

    init(snapshot: PublicAccessoryBatterySnapshot) {
        self.snapshot = snapshot
    }

    var callCount: Int { lock.withLock { calls } }

    func read() -> PublicAccessoryBatterySnapshot {
        lock.withLock {
            calls += 1
            return snapshot
        }
    }
}

private final class BoundedAccessoryReadGate: @unchecked Sendable {
    private let lock = NSLock()
    private let firstStarted = DispatchSemaphore(value: 0)
    private let secondStarted = DispatchSemaphore(value: 0)
    private let thirdStarted = DispatchSemaphore(value: 0)
    private let releaseFirst = DispatchSemaphore(value: 0)
    private let releaseSecond = DispatchSemaphore(value: 0)
    private let releaseThird = DispatchSemaphore(value: 0)
    private var calls = 0
    private var simultaneousCalls = 0
    private var maximumSimultaneous = 0

    var callCount: Int { lock.withLock { calls } }
    var maximumSimultaneousCalls: Int { lock.withLock { maximumSimultaneous } }

    func read() -> PublicAccessoryBatterySnapshot {
        let call = lock.withLock {
            calls += 1
            simultaneousCalls += 1
            maximumSimultaneous = max(maximumSimultaneous, simultaneousCalls)
            return calls
        }
        defer {
            lock.withLock { simultaneousCalls -= 1 }
        }
        switch call {
        case 1:
            firstStarted.signal()
            releaseFirst.wait()
        case 2:
            secondStarted.signal()
            releaseSecond.wait()
        case 3:
            thirdStarted.signal()
            releaseThird.wait()
        default:
            break
        }
        return .sources([])
    }

    func waitForFirstRead() -> Bool {
        firstStarted.wait(timeout: .now() + 1) == .success
    }

    func waitForSecondRead() -> Bool {
        secondStarted.wait(timeout: .now() + 1) == .success
    }

    func waitForThirdRead() -> Bool {
        thirdStarted.wait(timeout: .now() + 1) == .success
    }

    func releaseFirstRead() {
        releaseFirst.signal()
    }

    func releaseSecondRead() {
        releaseSecond.signal()
    }

    func releaseThirdRead() {
        releaseThird.signal()
    }

    func releaseAll() {
        releaseFirst.signal()
        releaseSecond.signal()
        releaseThird.signal()
    }
}
