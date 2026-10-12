import Testing
@testable import StatusTrioCore

@Suite
struct IconDesignerBehaviorCapabilityTests {
    @Test
    func outerRingCapabilitiesFollowTheSelectedPrimaryAndFallbackSource() throws {
        var configuration = IconConfigurationV1.classic
        configuration.composition.outerRing = SlotSelection(primary: .airPodsBattery, fallback: .systemBattery)

        let primary = IconDesignerEditingModel.effectiveBehaviorTarget(.primary, slot: .outerRing, in: configuration)
        let primarySource = try #require(IconDesignerEditingModel.source(for: primary, slot: .outerRing, in: configuration))
        #expect(primarySource == .ring(.airPodsBattery))
        #expect(IconDesignerEditingModel.behaviors(for: .outerRing, source: primarySource) == [.airPodsBattery])

        let fallback = IconDesignerEditingModel.effectiveBehaviorTarget(.fallback, slot: .outerRing, in: configuration)
        let fallbackSource = try #require(IconDesignerEditingModel.source(for: fallback, slot: .outerRing, in: configuration))
        #expect(fallbackSource == .ring(.systemBattery))
        #expect(IconDesignerEditingModel.behaviors(for: .outerRing, source: fallbackSource) == [.systemBattery])

        configuration.composition.outerRing = SlotSelection(primary: .systemBattery, fallback: .airPodsBattery)
        let reversedPrimary = try #require(IconDesignerEditingModel.source(for: .primary, slot: .outerRing, in: configuration))
        let reversedFallback = try #require(IconDesignerEditingModel.source(for: .fallback, slot: .outerRing, in: configuration))
        #expect(IconDesignerEditingModel.behaviors(for: .outerRing, source: reversedPrimary) == [.systemBattery])
        #expect(IconDesignerEditingModel.behaviors(for: .outerRing, source: reversedFallback) == [.airPodsBattery])

        configuration.composition.outerRing = SlotSelection(primary: .automaticLegacy)
        let legacySource = try #require(IconDesignerEditingModel.source(for: .primary, slot: .outerRing, in: configuration))
        #expect(IconDesignerEditingModel.behaviors(for: .outerRing, source: legacySource) == [.systemBattery])

        configuration.composition.outerRing = SlotSelection(primary: .none)
        let noneSource = try #require(IconDesignerEditingModel.source(for: .primary, slot: .outerRing, in: configuration))
        #expect(noneSource == .ring(.none))
        #expect(IconDesignerEditingModel.behaviors(for: .outerRing, source: noneSource).isEmpty)
    }

    @Test
    func onlySelectedAudioBluetoothTargetsExposeAudioAppearanceControls() {
        let audio = BluetoothDevice(
            id: "AA:BB:CC:DD:EE:FF", name: "Headphones", kind: .audio, isConnected: true
        )
        let keyboard = BluetoothDevice(
            id: "11:22:33:44:55:66", name: "Keyboard", kind: .peripheral(.keyboard), isConnected: true
        )
        let audioTarget = IconDesignerBluetoothTarget.connectedDevice(address: "aa-bb-cc-dd-ee-ff")
        let keyboardTarget = IconDesignerBluetoothTarget.connectedDevice(address: keyboard.id)

        #expect(IconDesignerEditingModel.behaviors(
            for: .center,
            source: .center(.connectedBluetoothDevice),
            bluetoothTarget: audioTarget,
            devices: [audio, keyboard]
        ) == [.bluetoothOutputAppearance])
        #expect(IconDesignerEditingModel.behaviors(
            for: .center,
            source: .center(.connectedBluetoothDevice),
            bluetoothTarget: keyboardTarget,
            devices: [audio, keyboard]
        ).isEmpty)
    }
}
