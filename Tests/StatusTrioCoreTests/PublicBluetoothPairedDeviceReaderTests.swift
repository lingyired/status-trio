import Foundation
import Testing
@testable import StatusTrioCore

struct PublicBluetoothPairedDeviceReaderTests {
    @Test func mapsPublicMetadataAndConnectionState() throws {
        let result = PublicBluetoothPairedDeviceReader.result(from: .devices([
            device(
                address: "AC-90-85-C2-9C-1F",
                name: "AirPods",
                majorClass: PublicBluetoothDeviceClass.majorAudio,
                minorClass: 0x06,
                isConnected: true
            ),
            device(
                address: "AA-BB-CC-DD-EE-FF",
                name: "MX Keys",
                majorClass: PublicBluetoothDeviceClass.majorPeripheral,
                minorClass: PublicBluetoothDeviceClass.minorPeripheralKeyboard,
                isConnected: false
            )
        ]))

        let mappedDevices = try #require(devices(from: result))
        #expect(mappedDevices.count == 2)
        #expect(mappedDevices[0].id == "AC-90-85-C2-9C-1F")
        #expect(mappedDevices[0].name == "AirPods")
        #expect(mappedDevices[0].kind == .audio)
        #expect(mappedDevices[0].isConnected)
        #expect(mappedDevices[0].vendorID == nil)
        #expect(mappedDevices[0].productID == nil)
        #expect(mappedDevices[0].airPodsModel == nil)
        #expect(mappedDevices[0].isUnpairedGhost == false)
        #expect(mappedDevices[0].isReadOverTheAir == false)

        #expect(mappedDevices[1].kind == .peripheral(.keyboard))
        #expect(mappedDevices[1].isConnected == false)
    }

    @Test(arguments: [
        (
            PublicBluetoothDeviceClass.majorComputer,
            PublicBluetoothDeviceClass.minorComputerLaptop,
            BluetoothDeviceKind.computer(.laptop)
        ),
        (
            PublicBluetoothDeviceClass.majorComputer,
            PublicBluetoothDeviceClass.minorComputerDesktop,
            BluetoothDeviceKind.computer(.desktop)
        ),
        (
            PublicBluetoothDeviceClass.majorPhone,
            0,
            BluetoothDeviceKind.mobile(.phone)
        ),
        (
            PublicBluetoothDeviceClass.majorAudio,
            0,
            BluetoothDeviceKind.audio
        ),
        (
            PublicBluetoothDeviceClass.majorPeripheral,
            PublicBluetoothDeviceClass.minorPeripheralKeyboard,
            BluetoothDeviceKind.peripheral(.keyboard)
        ),
        (
            PublicBluetoothDeviceClass.majorPeripheral,
            PublicBluetoothDeviceClass.minorPeripheralPointing,
            BluetoothDeviceKind.peripheral(.mouse)
        ),
        (
            PublicBluetoothDeviceClass.majorPeripheral,
            PublicBluetoothDeviceClass.minorPeripheralPointing
                | PublicBluetoothDeviceClass.minorPeripheralPointingJoystick,
            BluetoothDeviceKind.peripheral(.gamepad)
        ),
        (
            PublicBluetoothDeviceClass.majorPeripheral,
            PublicBluetoothDeviceClass.minorPeripheralPointing
                | PublicBluetoothDeviceClass.minorPeripheralPointingDigitizerTablet,
            BluetoothDeviceKind.peripheral(.trackpad)
        ),
        (
            PublicBluetoothDeviceClass.majorPeripheral,
            PublicBluetoothDeviceClass.minorPeripheralCombo,
            BluetoothDeviceKind.peripheral(.unclassified)
        ),
        (
            PublicBluetoothDeviceClass.majorImaging,
            PublicBluetoothDeviceClass.minorImagingPrinter,
            BluetoothDeviceKind.imaging(.printer)
        ),
        (
            PublicBluetoothDeviceClass.majorWearable,
            PublicBluetoothDeviceClass.minorWearableWatch,
            BluetoothDeviceKind.mobile(.watch)
        ),
        (
            PublicBluetoothDeviceClass.majorToy,
            0,
            BluetoothDeviceKind.toy
        ),
        (
            PublicBluetoothDeviceClass.majorHealth,
            0,
            BluetoothDeviceKind.health
        ),
        (
            PublicBluetoothDeviceClass.majorMiscellaneous,
            0,
            BluetoothDeviceKind.unknown
        )
    ])
    func mapsPublicClassNumbers(
        major: Int,
        minor: Int,
        expected: BluetoothDeviceKind
    ) {
        #expect(PublicBluetoothDeviceClass.kind(major: major, minor: minor) == expected)
    }

    @Test func deduplicatesNormalizedAddressesConnectedFirst() throws {
        let result = PublicBluetoothPairedDeviceReader.result(from: .devices([
            device(
                address: "aa:bb:cc:dd:ee:ff",
                name: "Disconnected duplicate",
                majorClass: PublicBluetoothDeviceClass.majorPeripheral,
                minorClass: PublicBluetoothDeviceClass.minorPeripheralKeyboard,
                isConnected: false
            ),
            device(
                address: "AA-BB-CC-DD-EE-FF",
                name: "Connected duplicate",
                majorClass: PublicBluetoothDeviceClass.majorAudio,
                minorClass: 0,
                isConnected: true
            ),
            device(
                address: "11-22-33-44-55-66",
                name: "Second device",
                majorClass: PublicBluetoothDeviceClass.majorPhone,
                minorClass: 0,
                isConnected: false
            )
        ]))

        let mappedDevices = try #require(devices(from: result))
        #expect(mappedDevices.count == 2)
        #expect(mappedDevices[0].name == "Connected duplicate")
        #expect(mappedDevices[0].isConnected)
        #expect(mappedDevices[1].name == "Second device")
    }

    @Test func skipsNilEmptyAndInvalidMetadata() throws {
        let result = PublicBluetoothPairedDeviceReader.result(from: .devices([
            device(
                address: nil,
                name: "Missing address",
                majorClass: PublicBluetoothDeviceClass.majorAudio,
                minorClass: 0,
                isConnected: true
            ),
            device(
                address: "not-an-address",
                name: "Invalid address",
                majorClass: PublicBluetoothDeviceClass.majorAudio,
                minorClass: 0,
                isConnected: true
            ),
            device(
                address: "AA-BB-CC-DD-EE-FF",
                name: nil,
                majorClass: PublicBluetoothDeviceClass.majorAudio,
                minorClass: 0,
                isConnected: true
            ),
            device(
                address: "11-22-33-44-55-66",
                name: "   ",
                majorClass: PublicBluetoothDeviceClass.majorAudio,
                minorClass: 0,
                isConnected: true
            ),
            device(
                address: "22-33-44-55-66-77",
                name: "  Valid device  ",
                majorClass: PublicBluetoothDeviceClass.majorAudio,
                minorClass: 0,
                isConnected: true
            )
        ]))

        let mappedDevices = try #require(devices(from: result))
        #expect(mappedDevices.count == 1)
        #expect(mappedDevices[0].id == "22-33-44-55-66-77")
        #expect(mappedDevices[0].name == "Valid device")
    }

    @Test func emptyListIsSuccessAndOtherStatesStayDistinct() throws {
        let empty = PublicBluetoothPairedDeviceReader.result(from: .devices([]))
        let emptyDevices = try #require(devices(from: empty))
        #expect(emptyDevices.isEmpty)

        #expect(isPoweredOff(PublicBluetoothPairedDeviceReader.result(from: .poweredOff)))
        #expect(isUnavailable(PublicBluetoothPairedDeviceReader.result(from: .unavailable)))
        #expect(isFailed(PublicBluetoothPairedDeviceReader.result(from: .failed)))
    }

    @Test func eachReadCallsTheProviderExactlyOnce() async {
        let provider = CountingPairedSnapshotProvider(snapshot: .devices([]))
        let reader = PublicBluetoothPairedDeviceReader(snapshotProvider: provider.read)
        let results = PairedResultBox()

        reader.read { results.append($0) }
        await waitUntil { results.count == 1 }
        try? await Task.sleep(for: .milliseconds(30))

        #expect(provider.callCount == 1)
        #expect(results.count == 1)
    }

    @Test func boundsBlockedReadsAndReopensCapacityAfterCompletion() async {
        let gate = BoundedPairedReadGate()
        defer { gate.releaseAll() }
        let reader = PublicBluetoothPairedDeviceReader(snapshotProvider: gate.read)
        let results = PairedResultBox()

        reader.read { results.append($0) }
        #expect(gate.waitForFirstRead())
        reader.read { results.append($0) }
        #expect(gate.waitForSecondRead())

        reader.read { results.append($0) }
        await waitUntil { results.count == 1 }
        #expect(isUnavailable(results[0]))
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
        let provider = CountingPairedSnapshotProvider(snapshot: .devices([]))
        let reader = PublicBluetoothPairedDeviceReader(snapshotProvider: provider.read)
        let results = PairedResultBox()

        reader.shutdown()
        reader.read { results.append($0) }
        await waitUntil { results.count == 1 }

        #expect(provider.callCount == 0)
        #expect(isUnavailable(results[0]))
    }

    private func device(
        address: String?,
        name: String?,
        majorClass: Int,
        minorClass: Int,
        isConnected: Bool
    ) -> PublicBluetoothPairedSnapshot.Device {
        PublicBluetoothPairedSnapshot.Device(
            address: address,
            name: name,
            majorClass: majorClass,
            minorClass: minorClass,
            isConnected: isConnected
        )
    }

    private func devices(from result: BluetoothWorkerResult) -> [BluetoothDevice]? {
        guard case let .success(devices) = result else { return nil }
        return devices
    }

    private func isPoweredOff(_ result: BluetoothWorkerResult) -> Bool {
        guard case .poweredOff = result else { return false }
        return true
    }

    private func isUnavailable(_ result: BluetoothWorkerResult) -> Bool {
        guard case .unavailable = result else { return false }
        return true
    }

    private func isFailed(_ result: BluetoothWorkerResult) -> Bool {
        guard case .failed = result else { return false }
        return true
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<500 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        Issue.record("Timed out waiting for the paired-device read")
    }
}

private final class PairedResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [BluetoothWorkerResult] = []

    var count: Int { lock.withLock { results.count } }
    subscript(index: Int) -> BluetoothWorkerResult {
        lock.withLock { results[index] }
    }

    func append(_ result: BluetoothWorkerResult) {
        lock.withLock { results.append(result) }
    }
}

private final class CountingPairedSnapshotProvider: @unchecked Sendable {
    private let lock = NSLock()
    private let snapshot: PublicBluetoothPairedSnapshot
    private var calls = 0

    init(snapshot: PublicBluetoothPairedSnapshot) {
        self.snapshot = snapshot
    }

    var callCount: Int { lock.withLock { calls } }

    func read() -> PublicBluetoothPairedSnapshot {
        lock.withLock {
            calls += 1
            return snapshot
        }
    }
}

private final class BoundedPairedReadGate: @unchecked Sendable {
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

    func read() -> PublicBluetoothPairedSnapshot {
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
        return .devices([])
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
