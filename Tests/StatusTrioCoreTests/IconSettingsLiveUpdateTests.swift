import Combine
import XCTest
@testable import StatusTrioCore

/// Every icon setting must re-render the menu bar / Dock immediately.
///
/// The historical bug: a mapper that read the store inside `resolveInputs` got
/// the pre-change value during `@Published`'s willSet emission, so an edit
/// rendered one step late (or not at all). These drive the real view-model
/// pipeline (preferences = the production publisher) and assert the scene
/// changes on the same turn as the edit.
@MainActor
final class IconSettingsLiveUpdateTests: XCTestCase {
    private func snapshot(charging: Bool, connected: Bool? = nil, batteryPresent: Bool = true, device: AudioOutputDevice? = nil) -> StatusSnapshot {
        StatusSnapshot(
            battery: BatteryStatus(
                rawPercentage: charging ? 40 : 55,
                isPresent: batteryPresent,
                isCharging: charging,
                isLowPowerMode: false,
                isConnectedToPower: connected ?? charging
            ),
            wifi: WiFiStatus(state: .connected, rssi: -52),
            connection: .wifi,
            volume: VolumeStatus(scalar: 0.6, isMuted: false, deviceName: device?.name ?? "Output", currentDevice: device)
        )
    }

    private func model(_ store: SettingsStore, _ snapshot: StatusSnapshot) throws -> IconPresentationViewModel {
        var seed: IconPresentationSettings?
        let cancellable = store.iconPresentationPublisher.first().sink { seed = $0 }
        cancellable.cancel()
        let subject = CurrentValueSubject<StatusSnapshot, Never>(snapshot)
        let view = IconPresentationViewModel(
            snapshot: snapshot,
            settings: try XCTUnwrap(seed),
            snapshots: subject.eraseToAnyPublisher(),
            preferences: store.iconPresentationPublisher,
            resolveInputs: { [store] snap in
                var inputs = IconPresentationResourceResolver.inputs(
                    snapshot: snap,
                    runtimeOptions: store.iconRuntimePresentationOptions
                )
                inputs.sources = IconPresentationResourceResolver.sourceSnapshot(snapshot: snap)
                return inputs
            },
            mapScene: { inputs, _, configuration in
                IconCompositionResolver.resolve(
                    inputs: IconResolutionInputs(system: inputs, sources: inputs.sources),
                    configuration: configuration
                ).scene
            },
            snapshotScheduler: ManualIconPresentationScheduler()
        )
        view.start()
        return view
    }

    private func assertUpdate(
        _ name: String,
        charging: Bool = true,
        connected: Bool? = nil,
        batteryPresent: Bool = true,
        center: ConnectionCenterSource = .network,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ edit: (SettingsStore) -> Void
    ) throws {
        let suite = "StatusTrioCoreTests.IconLive.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }

        let store = SettingsStore(defaults: defaults)
        store.connectionCenterSource = center
        let device = center == .bluetoothDevice
            ? AudioOutputDevice(id: 1, name: "AirPods Pro", isCurrent: true, transport: .bluetooth)
            : nil
        let view = try model(store, snapshot(charging: charging, connected: connected, batteryPresent: batteryPresent, device: device))
        let before = view.output.scene
        edit(store)
        XCTAssertNotEqual(view.output.scene, before, "\(name) must re-render immediately", file: file, line: line)
        view.stop()
    }

    func testBatterySettingsRenderImmediately() throws {
        try assertUpdate("batteryOnBatteryMarker", charging: false) { $0.batteryOnBatteryMarker = $0.batteryOnBatteryMarker == .hidden ? .percentage : .hidden }
        try assertUpdate("batteryChargingMarker") { $0.batteryChargingMarker = .percentage }
        try assertUpdate("batteryConnectedMarker", charging: false, connected: true) { $0.batteryConnectedMarker = .hidden }
        try assertUpdate("batteryCriticalThreshold") { $0.batteryCriticalThreshold = 45 }
        try assertUpdate("usesBatteryStatusColors") { $0.usesBatteryStatusColors = false }
        try assertUpdate("batterySplitGapProgress") { $0.batterySplitGapProgress.toggle() }
        try assertUpdate("batterySymbolScale", charging: false) { $0.batterySymbolScale = 1.2 }
    }

    func testCentreAndFooterSettingsRenderImmediately() throws {
        try assertUpdate("wifiSymbolScale") { $0.wifiSymbolScale = 1.15 }
        try assertUpdate("ringStrokeStyle") { $0.ringStrokeStyle = .bold }
        try assertUpdate("volumeDisplayStyle") { $0.volumeDisplayStyle = .arc }
        try assertUpdate("connectionCenterSource") { $0.connectionCenterSource = .batteryPercentage }
    }

    func testBluetoothSettingsRenderImmediately() throws {
        try assertUpdate("bluetoothIconColor", center: .bluetoothDevice) { $0.bluetoothIconColor = .primary }
        try assertUpdate("bluetoothNetworkIconSymbolName", center: .bluetoothDevice) { $0.bluetoothNetworkIconSymbolName = "airpodsmax" }
        try assertUpdate("bluetoothAudioIconChoice", center: .bluetoothDevice) { $0.bluetoothAudioIconChoiceRawValue = "headset" }
        try assertUpdate("usesBluetoothAudioVolumeColor", center: .bluetoothDevice) { $0.usesBluetoothAudioVolumeColor = true }
    }

    func testBatteryStatusColorsRenderImmediately() throws {
        try assertUpdate("batteryStatusColors") {
            $0.batteryStatusColors = BatteryStatusColors(
                charging: .preset(.rose),
                lowPower: .preset(.rose),
                highPower: .preset(.rose),
                critical: .preset(.rose)
            )
        }
    }
}
