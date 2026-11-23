import Testing
@testable import StatusTrioCore

struct IconDesignerReviewFixTests {
    @Test func currentOutputFallbackDoesNotClearAnotherRolesDevice() {
        var configuration = IconDesignerDefaults.configuration()
        configuration.composition.center = SlotSelection(primary: .connectedBluetoothDevice, fallback: .bluetoothAudioOutput)
        var address: String? = "AA:BB:CC:DD:EE:FF"
        #expect(IconDesignerBluetoothTargetModel.selectedAddress(for: .fallback, in: configuration, deviceAddress: address) == nil)
        #expect(IconDesignerBluetoothTargetModel.selectedAddress(for: .primary, in: configuration, deviceAddress: address) == BluetoothBatteryReader.normalizedAddress("AA:BB:CC:DD:EE:FF"))
        #expect(IconDesignerBluetoothTargetModel.setTarget(.currentAudioOutput, for: .fallback, in: &configuration, deviceAddress: &address))
        #expect(address == "AA:BB:CC:DD:EE:FF")
        #expect(configuration.composition.center.primary == .connectedBluetoothDevice)
        #expect(configuration.composition.center.fallback == .bluetoothAudioOutput)
    }

    @Test func duplicateTargetCannotDeleteAnotherRoleOrOverwriteItsAddress() {
        var configuration = IconDesignerDefaults.configuration()
        configuration.composition.center = SlotSelection(primary: .connectedBluetoothDevice, fallback: .bluetoothAudioOutput)
        let before = configuration
        var address: String? = "AA:BB:CC:DD:EE:FF"
        #expect(IconDesignerBluetoothTargetModel.setTarget(.connectedDevice(address: "11:22:33:44:55:66"), for: .fallback,
            in: &configuration, deviceAddress: &address) == false)
        #expect(configuration == before)
        #expect(address == "AA:BB:CC:DD:EE:FF")
    }

    @Test func noPrimaryContentStillOffersReachableNetworkWarningAppearance() {
        var configuration = IconDesignerDefaults.configuration()
        configuration.composition.center = SlotSelection(primary: .none)
        #expect(IconDesignerInspectorModel.showsAppearance(slot: .center, configuration: configuration, targetIsAudio: false) == false)
        configuration.composition.centerOverride.networkProblemOverridesPrimary = true
        #expect(IconDesignerInspectorModel.showsAppearance(slot: .center, configuration: configuration, targetIsAudio: false))
    }

    @Test func ambiguousAirPodsFallbackRequiresPersistentSelectionNotice() {
        var configuration = IconDesignerDefaults.configuration()
        configuration.composition.outerRing.fallback = .airPodsBattery
        let devices = [
            BluetoothDevice(id: "AA:BB:CC:DD:EE:FF", name: "One", kind: .audio, isConnected: true, airPodsModel: .airPodsPro),
            BluetoothDevice(id: "11:22:33:44:55:66", name: "Two", kind: .audio, isConnected: true, airPodsModel: .airPodsPro)
        ]
        #expect(IconDesignerInspectorModel.fallbackSetupReason(slot: .outerRing, configuration: configuration,
            bluetoothAuthorized: true, devices: devices, airPodsAddress: nil, connectedDeviceAddress: nil) == .iconDesignerControlChooseBluetoothDevice)
        #expect(IconDesignerInspectorModel.fallbackSetupReason(slot: .outerRing, configuration: configuration,
            bluetoothAuthorized: true, devices: [devices[0]], airPodsAddress: nil, connectedDeviceAddress: nil) == nil)
        #expect(IconDesignerInspectorModel.fallbackSetupReason(slot: .outerRing, configuration: configuration,
            bluetoothAuthorized: false, devices: devices, airPodsAddress: nil, connectedDeviceAddress: nil) == .settingsBluetoothPermissionRequired)
    }
}
