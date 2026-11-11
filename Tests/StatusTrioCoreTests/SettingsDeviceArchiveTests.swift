import Combine
import CryptoKit
import Foundation
import XCTest
@testable import StatusTrioCore

@MainActor
final class SettingsDeviceArchiveTests: XCTestCase {
    private var suites: [String] = []

    override func tearDown() async throws {
        await MainActor.run {
            for name in suites { UserDefaults.standard.removePersistentDomain(forName: name) }
            suites = []
        }
        try await super.tearDown()
    }

    private func store(_ setup: (UserDefaults) -> Void = { _ in }) -> SettingsStore {
        let name = "SettingsDeviceArchiveTests.\(UUID().uuidString)"
        suites.append(name)
        let defaults = UserDefaults(suiteName: name)!
        setup(defaults)
        return SettingsStore(defaults: defaults)
    }

    private func token(_ domain: String, _ identity: String) -> String {
        SHA256.hash(data: Data("status-trio.device.v1:\(domain):\(identity)".utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    private func configuredStore() -> SettingsStore {
        let source = store { defaults in
            defaults.set(["speaker-secret", "other-speaker"], forKey: SettingsStore.outputDeviceOrderDefaultsKey)
            defaults.set(["mic-secret"], forKey: SettingsStore.inputDeviceOrderDefaultsKey)
            defaults.set(["AA:BB:CC:DD:EE:FF", "ble:00000000-0000-0000-0000-000000000001", "mobile-secret"],
                         forKey: SettingsStore.bluetoothDeviceOrderDefaultsKey)
        }
        source.setOutputDeviceHidden("speaker-secret", hidden: true)
        source.setInputDeviceHidden("mic-secret", hidden: true)
        source.setExternalVolumeConfiguration(.init(backend: .betterDisplay, betterDisplayUUID: "bd-secret"), for: "speaker-secret")
        source.setExternalBrightnessConfiguration(.init(backend: .betterDisplay, betterDisplayUUID: "bd-secret"), for: "display-secret")
        source.setBrightnessDisplayHidden("display-secret", hidden: true)
        source.setBluetoothDeviceHidden("AA:BB:CC:DD:EE:FF", hidden: true)
        source.setBluetoothGhostRevealed("AA:BB:CC:DD:EE:FF", revealed: true)
        source.setBluetoothNetworkIconDevice(address: "AA:BB:CC:DD:EE:FF", symbolName: "airpodspro")
        return source
    }

    func testSnapshotUsesDomainSeparatedSHA256AndContainsNoRawIdentityOrMetadata() throws {
        let source = configuredStore()
        let snapshot = SettingsDeviceArchive.snapshot(source)
        let encoded = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        for forbidden in ["speaker-secret", "mic-secret", "bd-secret", "display-secret", "AA:BB:CC:DD:EE:FF", "AABBCCDDEEFF", "mobile-secret", "ble:"] {
            XCTAssertFalse(encoded.contains(forbidden), forbidden)
        }
        guard case .object(let outputs) = snapshot["audioOutputs"] else {
            return XCTFail("Missing hashed output entries")
        }
        XCTAssertNotNil(outputs[token("output", "speaker-secret")])
        XCTAssertNil(outputs[token("input", "speaker-secret")])
        XCTAssertEqual(snapshot["bluetoothCenterDevice"], .object([
            "device": .string(token("bluetooth", "AABBCCDDEEFF")), "symbol": .string("airpodspro")
        ]))
    }

    func testMatchedRoundTripPersistsDeviceConfiguration() {
        let source = configuredStore()
        let target = store()
        let inventory = SettingsDeviceInventory(
            outputUIDs: ["speaker-secret", "other-speaker"], inputUIDs: ["mic-secret"],
            displayIDs: ["display-secret"], bluetoothAddresses: ["aa-bb-cc-dd-ee-ff"],
            betterDisplayUUIDs: ["bd-secret"])
        let prepared = SettingsDeviceArchive.prepare(SettingsDeviceArchive.snapshot(source), inventory: inventory)
        XCTAssertTrue(prepared.warnings.isEmpty, prepared.warnings.joined(separator: "; "))
        SettingsDeviceArchive.apply(prepared.values, to: target)
        XCTAssertEqual(target.outputDeviceOrder, ["speaker-secret", "other-speaker"])
        XCTAssertEqual(target.inputDeviceOrder, ["mic-secret"])
        XCTAssertEqual(target.hiddenOutputDeviceUIDs, ["speaker-secret"])
        XCTAssertEqual(target.hiddenInputDeviceUIDs, ["mic-secret"])
        XCTAssertEqual(target.externalVolumeConfigurations, source.externalVolumeConfigurations)
        XCTAssertEqual(target.externalBrightnessConfigurations, source.externalBrightnessConfigurations)
        XCTAssertEqual(target.hiddenBrightnessDisplayIDs, ["display-secret"])
        XCTAssertEqual(target.bluetoothDeviceOrder, ["AABBCCDDEEFF"])
        XCTAssertEqual(target.hiddenBluetoothDeviceAddresses, ["AABBCCDDEEFF"])
        XCTAssertEqual(target.revealedGhostBluetoothDeviceAddresses, ["AABBCCDDEEFF"])
        XCTAssertEqual(target.bluetoothNetworkIconDeviceAddress, "AABBCCDDEEFF")
        XCTAssertEqual(target.bluetoothNetworkIconSymbolName, "airpodspro")
    }

    func testUnmatchedInventorySkipsWithoutLeakingIdentifiersInWarnings() {
        let prepared = SettingsDeviceArchive.prepare(SettingsDeviceArchive.snapshot(configuredStore()), inventory: .init())
        let target = store()
        SettingsDeviceArchive.apply(prepared.values, to: target)
        XCTAssertFalse(prepared.warnings.isEmpty)
        XCTAssertTrue(target.outputDeviceOrder.isEmpty)
        XCTAssertTrue(target.externalBrightnessConfigurations.isEmpty)
        XCTAssertNil(target.bluetoothNetworkIconDeviceAddress)
        XCTAssertFalse(prepared.warnings.joined().contains("secret"))
    }

    func testSubsetPreservesUnrelatedTargetStateButCanExplicitlyUnhideMatchedDevice() {
        let source = store { $0.set(["a"], forKey: SettingsStore.outputDeviceOrderDefaultsKey) }
        let target = store { $0.set(["unrelated", "a"], forKey: SettingsStore.outputDeviceOrderDefaultsKey) }
        target.setOutputDeviceHidden("unrelated", hidden: true)
        target.setOutputDeviceHidden("a", hidden: true)
        target.setExternalVolumeConfiguration(.init(backend: .betterDisplay, betterDisplayUUID: "local"), for: "unrelated")
        let prepared = SettingsDeviceArchive.prepare(SettingsDeviceArchive.snapshot(source), inventory: .init(outputUIDs: ["a"]))
        SettingsDeviceArchive.apply(prepared.values, to: target)
        XCTAssertEqual(Set(target.outputDeviceOrder), ["a", "unrelated"])
        XCTAssertEqual(target.hiddenOutputDeviceUIDs, ["unrelated"])
        XCTAssertEqual(target.externalVolumeConfiguration(for: "unrelated").betterDisplayUUID, "local")
    }

    func testMissingBetterDisplayAssociationSkipsConfigurationInsteadOfGuessing() {
        let source = configuredStore()
        let target = store()
        target.setExternalVolumeConfiguration(.init(backend: .betterDisplay, betterDisplayUUID: "keep"), for: "speaker-secret")
        target.setExternalBrightnessConfiguration(.default, for: "display-secret")
        let prepared = SettingsDeviceArchive.prepare(SettingsDeviceArchive.snapshot(source), inventory: .init(outputUIDs: ["speaker-secret"], displayIDs: ["display-secret"]))
        SettingsDeviceArchive.apply(prepared.values, to: target)
        XCTAssertFalse(prepared.warnings.isEmpty)
        XCTAssertEqual(target.externalVolumeConfiguration(for: "speaker-secret").betterDisplayUUID, "keep")
        XCTAssertEqual(target.externalBrightnessConfiguration(for: "display-secret"), .default)
        XCTAssertTrue(target.hiddenBrightnessDisplayIDs.contains("display-secret"))
    }

    func testMalformedAndUnknownEntriesAreRejectedWithoutMutation() {
        let values: [String: SettingsTransferValue] = [
            "audioOutputs": .object([
                token("output", "a"): .object(["hidden": .string("true"), "order": .number(-1)]),
                "raw-identifier": .object(["hidden": .bool(true)])
            ]),
            "nearbyBLESelections": .array([]),
            "appleConsent": .bool(true)
        ]
        let prepared = SettingsDeviceArchive.prepare(values, inventory: .init(outputUIDs: ["a"]))
        let target = store()
        SettingsDeviceArchive.apply(prepared.values, to: target)
        XCTAssertFalse(prepared.warnings.isEmpty)
        XCTAssertTrue(prepared.warnings.allSatisfy { $0 == "devices" || $0.hasPrefix("devices.") })
        XCTAssertTrue(prepared.warnings.allSatisfy { !$0.contains(where: \.isWhitespace) })
        XCTAssertFalse(prepared.warnings.joined().contains("raw-identifier"))
        XCTAssertTrue(target.hiddenOutputDeviceUIDs.isEmpty)
        XCTAssertTrue(target.outputDeviceOrder.isEmpty)
        XCTAssertTrue(target.nearbyBLESelections.isEmpty)
    }

    func testSparseRecordPreservesMissingFieldsAndInvalidBackend() {
        let target = store()
        target.setOutputDeviceHidden("a", hidden: true)
        target.setExternalVolumeConfiguration(.init(backend: .betterDisplay, betterDisplayUUID: "keep"), for: "a")
        let prepared = SettingsDeviceArchive.prepare([
            "audioOutputs": .object([token("output", "a"): .object([
                "volume": .object(["backend": .string("invalid")])
            ])])
        ], inventory: .init(outputUIDs: ["a"]))
        SettingsDeviceArchive.apply(prepared.values, to: target)
        XCTAssertTrue(target.hiddenOutputDeviceUIDs.contains("a"))
        XCTAssertEqual(target.externalVolumeConfiguration(for: "a").betterDisplayUUID, "keep")
        XCTAssertFalse(prepared.warnings.isEmpty)
    }

    func testBLEAndAppleSelectionsAreNeverExportedOrApplied() {
        let source = configuredStore()
        source.hiddenBluetoothDeviceAddresses.insert("ble:00000000-0000-0000-0000-000000000001")
        source.hiddenBluetoothDeviceAddresses.insert("mobile-secret")
        let snapshot = SettingsDeviceArchive.snapshot(source)
        guard case .object(let bluetooth) = snapshot["bluetoothDevices"] else { return XCTFail("Missing Bluetooth entries") }
        XCTAssertEqual(bluetooth.count, 1)
        let prepared = SettingsDeviceArchive.prepare(snapshot, inventory: .init(bluetoothAddresses: ["mobile-secret", "ble:00000000-0000-0000-0000-000000000001"]))
        let target = store()
        SettingsDeviceArchive.apply(prepared.values, to: target)
        XCTAssertTrue(target.bluetoothDeviceOrder.isEmpty)
        XCTAssertTrue(target.nearbyBLESelections.isEmpty)
    }

    func testLocalInventoryIncludesDisconnectedConfiguredIdentifiers() {
        let inventory = SettingsDeviceArchive.localInventory(configuredStore())
        XCTAssertEqual(inventory.outputUIDs, ["speaker-secret", "other-speaker"])
        XCTAssertEqual(inventory.inputUIDs, ["mic-secret"])
        XCTAssertEqual(inventory.displayIDs, ["display-secret"])
        XCTAssertEqual(inventory.betterDisplayUUIDs, ["bd-secret"])
        XCTAssertEqual(inventory.bluetoothAddresses, ["AABBCCDDEEFF"])
    }

    func testTrustedLocalRestoreExactlyRemovesImportedStateAndRestoresDisconnectedDevices() {
        let target = configuredStore()
        let original = SettingsDeviceArchive.captureLocalState(target)
        let expected = SettingsDeviceArchive.snapshot(target)
        let originalOutputOrder = target.outputDeviceOrder
        let originalInputOrder = target.inputDeviceOrder
        let originalBluetoothOrder = target.bluetoothDeviceOrder
        let imported = store { defaults in
            defaults.set(["new-device"], forKey: SettingsStore.outputDeviceOrderDefaultsKey)
            defaults.set(["new-mic"], forKey: SettingsStore.inputDeviceOrderDefaultsKey)
            defaults.set(["112233445566"], forKey: SettingsStore.bluetoothDeviceOrderDefaultsKey)
        }
        imported.setInputDeviceHidden("new-mic", hidden: true)
        imported.setBluetoothDeviceHidden("112233445566", hidden: true)
        imported.setBluetoothGhostRevealed("112233445566", revealed: true)
        let prepared = SettingsDeviceArchive.prepare(SettingsDeviceArchive.snapshot(imported), inventory: .init(
            outputUIDs: ["new-device"], inputUIDs: ["new-mic"], bluetoothAddresses: ["112233445566"]))
        SettingsDeviceArchive.apply(prepared.values, to: target)
        target.setOutputDeviceHidden("new-device", hidden: true)
        target.setExternalVolumeConfiguration(.init(backend: .betterDisplay, betterDisplayUUID: "new-bd"), for: "new-device")
        target.setExternalBrightnessConfiguration(.default, for: "new-display")
        target.setBrightnessDisplayHidden("display-secret", hidden: false)
        target.setBluetoothNetworkIconDevice(address: nil, symbolName: nil)
        SettingsDeviceArchive.restoreLocalState(original, to: target)
        XCTAssertEqual(SettingsDeviceArchive.snapshot(target), expected)
        XCTAssertEqual(target.outputDeviceOrder, originalOutputOrder)
        XCTAssertEqual(target.inputDeviceOrder, originalInputOrder)
        XCTAssertEqual(target.bluetoothDeviceOrder, originalBluetoothOrder)
        XCTAssertEqual(target.hiddenInputDeviceUIDs, ["mic-secret"])
        XCTAssertEqual(target.hiddenBluetoothDeviceAddresses, ["AABBCCDDEEFF"])
        XCTAssertEqual(target.revealedGhostBluetoothDeviceAddresses, ["AABBCCDDEEFF"])
        XCTAssertEqual(target.bluetoothNetworkIconSymbolName, "airpodspro")
        XCTAssertFalse(target.hiddenOutputDeviceUIDs.contains("new-device"))
        XCTAssertNil(target.externalBrightnessConfigurations["new-display"])
        XCTAssertNil(target.externalVolumeConfigurations["new-device"])
    }

    func testExplicitNullClearsCenterSelectionButAbsentDeviceSettingsPreserveIt() {
        let target = configuredStore()
        SettingsDeviceArchive.apply([:], to: target)
        XCTAssertEqual(target.bluetoothNetworkIconDeviceAddress, "AA:BB:CC:DD:EE:FF")
        XCTAssertEqual(target.bluetoothNetworkIconSymbolName, "airpodspro")
        let source = store()
        let snapshot = SettingsDeviceArchive.snapshot(source)
        XCTAssertEqual(snapshot["bluetoothCenterDevice"], .null)
        let prepared = SettingsDeviceArchive.prepare(snapshot, inventory: .init())
        XCTAssertTrue(prepared.warnings.isEmpty)
        XCTAssertEqual(prepared.values["bluetoothCenterDevice"], .null)
        SettingsDeviceArchive.apply(prepared.values, to: target)
        XCTAssertNil(target.bluetoothNetworkIconDeviceAddress)
        XCTAssertNil(target.bluetoothNetworkIconSymbolName)
    }

    func testInvalidCenterSymbolAndLegacyBareHashAreSkippedWithoutChangingTarget() throws {
        let target = configuredStore()
        let hash = token("bluetooth", "112233445566")
        for value: SettingsTransferValue in [
            .string(hash),
            .object(["device": .string(hash), "symbol": .string("not-a-real-symbol-secret")]),
            .object(["device": .string(hash), "symbol": .string("airpodspro"), "name": .string("private-name")])
        ] {
            let prepared = SettingsDeviceArchive.prepare(["bluetoothCenterDevice": value],
                inventory: .init(bluetoothAddresses: ["112233445566"]))
            XCTAssertFalse(prepared.warnings.isEmpty)
            XCTAssertTrue(prepared.warnings.allSatisfy { $0.hasPrefix("devices.bluetoothCenterDevice.") })
            XCTAssertNil(prepared.values["bluetoothCenterDevice"])
            SettingsDeviceArchive.apply(prepared.values, to: target)
            XCTAssertEqual(target.bluetoothNetworkIconDeviceAddress, "AA:BB:CC:DD:EE:FF")
            XCTAssertEqual(target.bluetoothNetworkIconSymbolName, "airpodspro")
        }
        target.setBluetoothNetworkIconDevice(address: "112233445566", symbolName: "not-a-real-symbol-secret")
        let snapshot = SettingsDeviceArchive.snapshot(target)
        XCTAssertNil(snapshot["bluetoothCenterDevice"])
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self).contains("not-a-real-symbol-secret"))
    }

    func testApplyPublishesChangesThroughExistingSetters() {
        let source = store { $0.set(["a"], forKey: SettingsStore.outputDeviceOrderDefaultsKey) }
        source.setOutputDeviceHidden("a", hidden: true)
        let target = store()
        var changes = 0
        let subscription = target.$hiddenOutputDeviceUIDs.dropFirst().sink { _ in changes += 1 }
        let prepared = SettingsDeviceArchive.prepare(SettingsDeviceArchive.snapshot(source), inventory: .init(outputUIDs: ["a"]))
        SettingsDeviceArchive.apply(prepared.values, to: target)
        XCTAssertGreaterThan(changes, 0)
        withExtendedLifetime(subscription) {}
    }
}
