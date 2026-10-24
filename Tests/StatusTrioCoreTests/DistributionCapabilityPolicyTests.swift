import XCTest
@testable import StatusTrioCore

final class DistributionCapabilityPolicyTests: XCTestCase {
    func testStoreRuntimeDefaultBlocksPrivateControlsAndKeepsNotVerifiedEvidence() {
        let policy = DistributionCapabilityPolicy.runtimeDefault(for: .appStore)

        XCTAssertTrue(policy.blocksControl(.bluetoothRadioPower))
        XCTAssertTrue(policy.blocksControl(.appleListeningMode))
        XCTAssertTrue(policy.blocksControl(.privilegedHelper))
        XCTAssertTrue(policy.blocksControl(.privatePowerReaders))
        XCTAssertTrue(policy.blocksControl(.mobileBatteryHelper))

        XCTAssertEqual(
            policy.availability(of: .mobileBatteryHelper),
            .notVerified
        )
        XCTAssertEqual(
            policy.availability(of: .publicBluetoothReaders),
            .notVerified
        )
        XCTAssertFalse(policy.blocksControl(.publicBluetoothReaders))
        XCTAssertFalse(policy.blocksControl(.huaweiListeningMode))
        XCTAssertEqual(policy.channel.displayIdentity, "Mac App Store")
    }

    func testStoreEmptyRecordsFailClosedAndMergeCanonicalContract() {
        let policy = DistributionCapabilityPolicy(channel: .appStore, records: [])

        XCTAssertTrue(policy.blocksControl(.bluetoothRadioPower))
        XCTAssertTrue(policy.blocksControl(.appleListeningMode))
        XCTAssertTrue(policy.blocksControl(.privilegedHelper))
        XCTAssertTrue(policy.blocksControl(.privatePowerReaders))
        XCTAssertTrue(policy.blocksControl(.mobileBatteryHelper))
        XCTAssertEqual(
            policy.availability(of: .privatePowerReaders),
            .unsupported(reason: "distribution.private-power")
        )
    }

    func testStorePartialRecordsCannotOverrideOmittedPrivateBlocks() {
        let policy = DistributionCapabilityPolicy(
            channel: .appStore,
            records: [
                PlatformCapabilityRecord(
                    capability: DistributionCapabilityID.bluetoothRadioPower.rawValue,
                    availability: .permissionRequired,
                    reason: nil
                )
            ]
        )

        XCTAssertFalse(
            policy.blocksControl(.bluetoothRadioPower),
            "an explicit runtime state must replace the canonical block"
        )
        XCTAssertTrue(
            policy.blocksControl(.appleListeningMode),
            "omitted records retain the canonical Store block"
        )
        XCTAssertTrue(policy.blocksControl(.privilegedHelper))
        XCTAssertTrue(policy.blocksControl(.privatePowerReaders))
        XCTAssertTrue(policy.blocksControl(.mobileBatteryHelper))
    }

    func testStoreUnknownCapabilityFailsClosed() {
        let policy = DistributionCapabilityPolicy(
            channel: .appStore,
            records: [
                PlatformCapabilityRecord(
                    capability: "future.private.capability",
                    availability: .available,
                    reason: nil
                )
            ]
        )
        XCTAssertNil(DistributionCapabilityID(rawValue: "future.private.capability"))
        XCTAssertEqual(
            policy.availability(of: .privatePowerReaders),
            .unsupported(reason: "distribution.private-power")
        )
        XCTAssertTrue(policy.blocksControl(.privatePowerReaders))
    }

    func testDirectRuntimeDefaultDoesNotApplyStoreRestrictions() {
        let policy = DistributionCapabilityPolicy.runtimeDefault(for: .direct)

        XCTAssertFalse(policy.blocksControl(.bluetoothRadioPower))
        XCTAssertFalse(policy.blocksControl(.appleListeningMode))
        XCTAssertFalse(policy.blocksControl(.privilegedHelper))
        XCTAssertEqual(policy.channel.displayIdentity, "GitHub Direct")
    }

    func testPermissionAndTemporaryStatesKeepRuntimeGate() {
        let policy = DistributionCapabilityPolicy(
            channel: .appStore,
            records: [
                PlatformCapabilityRecord(
                    capability: DistributionCapabilityID.bluetoothRadioPower.rawValue,
                    availability: .permissionRequired,
                    reason: nil
                ),
                PlatformCapabilityRecord(
                    capability: DistributionCapabilityID.appleListeningMode.rawValue,
                    availability: .temporarilyUnavailable(reason: "busy"),
                    reason: "busy"
                )
            ]
        )

        XCTAssertFalse(policy.blocksControl(.bluetoothRadioPower))
        XCTAssertFalse(policy.blocksControl(.appleListeningMode))
        XCTAssertEqual(
            policy.availability(of: .bluetoothRadioPower),
            .permissionRequired
        )
        XCTAssertEqual(
            policy.availability(of: .appleListeningMode),
            .temporarilyUnavailable(reason: "busy")
        )
    }

    func testUnsupportedReasonIsLocalizedAndNotReportedAsAvailable() {
        let policy = DistributionCapabilityPolicy(
            channel: .appStore,
            records: [
                .unsupported(
                    DistributionCapabilityID.privatePowerReaders.rawValue,
                    reason: "distribution.private-power"
                )
            ]
        )

        XCTAssertNotEqual(
            policy.availability(of: .privatePowerReaders),
            .available
        )
        XCTAssertEqual(
            policy.unavailableReasonKey(for: .privatePowerReaders),
            .capabilityUnavailableDistribution
        )
    }
}

@MainActor
final class DistributionCapabilityActionTests: XCTestCase {
    func testStorePolicyStopsPrivateBluetoothPowerBeforeCommand() {
        let policy = DistributionCapabilityPolicy(
            channel: .appStore,
            records: [
                .unsupported(
                    DistributionCapabilityID.bluetoothRadioPower.rawValue,
                    reason: "distribution.private-bluetooth"
                )
            ]
        )
        var commands: [Bool] = []
        let actions = StatusPanelActions(
            capabilityPolicy: policy,
            setBluetoothPower: { commands.append($0) }
        )

        actions.setBluetoothPower(false)

        XCTAssertTrue(commands.isEmpty)
    }

    func testRuntimeGateAllowsBluetoothPowerWhenCapabilityIsPermissionGated() {
        let policy = DistributionCapabilityPolicy(
            channel: .appStore,
            records: [
                PlatformCapabilityRecord(
                    capability: DistributionCapabilityID.bluetoothRadioPower.rawValue,
                    availability: .permissionRequired,
                    reason: nil
                )
            ]
        )
        var commands: [Bool] = []
        let actions = StatusPanelActions(
            capabilityPolicy: policy,
            setBluetoothPower: { commands.append($0) }
        )

        actions.setBluetoothPower(true)

        XCTAssertEqual(commands, [true])
    }

    func testAppleListeningModeIsBlockedWhileHuaweiUsesRuntimePath() {
        let policy = DistributionCapabilityPolicy(
            channel: .appStore,
            records: [
                .unsupported(
                    DistributionCapabilityID.appleListeningMode.rawValue,
                    reason: "distribution.private-hal"
                )
            ]
        )
        let airPods = BluetoothDevice(
            id: "AA:BB:CC:DD:EE:01",
            name: "AirPods Pro",
            kind: .audio,
            isConnected: true
        )
        let huawei = BluetoothDevice(
            id: "AA:BB:CC:DD:EE:02",
            name: "FreeBuds Pro",
            kind: .audio,
            isConnected: true
        )
        let presentation = BluetoothListeningModePresentation(
            availableModes: [.noiseCancellation, .transparency],
            selectedMode: .noiseCancellation
        )
        var calls: [(mode: BluetoothListeningMode, address: String)] = []
        let actions = StatusPanelActions(
            capabilityPolicy: policy,
            setListeningMode: { mode, address in
                calls.append((mode, address))
            },
            listeningModePresentations: {
                [
                    BluetoothBatteryReader.normalizedAddress(airPods.id): presentation,
                    BluetoothBatteryReader.normalizedAddress(huawei.id): presentation
                ]
            },
            listeningModeDevices: { [airPods, huawei] }
        )

        actions.setListeningMode(address: airPods.id, mode: .transparency)
        XCTAssertTrue(calls.isEmpty)

        actions.setListeningMode(address: huawei.id, mode: .transparency)
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.mode, .transparency)
        XCTAssertEqual(
            calls.first?.address,
            BluetoothBatteryReader.normalizedAddress(huawei.id)
        )
    }
}
